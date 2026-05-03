<?php
header('Content-Type: application/json');
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: GET, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type, Authorization");

$scheme = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') ? 'https' : 'http';
$host = $_SERVER['HTTP_HOST'] ?? 'localhost';
$requestPath = parse_url($_SERVER['REQUEST_URI'] ?? '/Api2/other_profile_new.php', PHP_URL_PATH);
$apiDir = rtrim(str_replace('\\', '/', dirname($requestPath ?: '/Api2/other_profile_new.php')), '/');
$base_url = $scheme . '://' . $host . $apiDir . '/';

$host = "localhost"; 
$db_name = "ms";
$username = "root";
$password = "";

$conn = new mysqli($host, $username, $password, $db_name);

if ($conn->connect_error) {
    die(json_encode([
        "status" => "error",
        "message" => "Database connection failed"
    ]));
}

$userid = isset($_GET['userid']) ? intval($_GET['userid']) : 0;
$myid   = isset($_GET['myid']) ? intval($_GET['myid']) : 0;

if ($userid <= 0 || $myid <= 0) {
    echo json_encode([
        "status" => "error",
        "message" => "Invalid user ID"
    ]);
    exit;
}

require_once __DIR__ . '/deletion_guard.php';
if (isUserPendingDeletionMysqli($conn, $myid) || isUserPendingDeletionMysqli($conn, $userid)) {
    echo json_encode([
        "status" => "error",
        "success" => false,
        "message" => "Profile is unavailable while account deletion is pending",
        "error_code" => "ACCOUNT_DELETION_PENDING"
    ]);
    $conn->close();
    exit;
}

/* =============================
   BLOCK GATE (BIDIRECTIONAL)
============================= */

$blockStmt = $conn->prepare("\nSELECT blocker_id, blocked_id FROM blocks\nWHERE (blocker_id=? AND blocked_id=?)\n   OR (blocker_id=? AND blocked_id=?)\nLIMIT 1\n");
$blockStmt->bind_param("iiii", $myid, $userid, $userid, $myid);
$blockStmt->execute();
$blockRes = $blockStmt->get_result();
$blockRow = $blockRes->fetch_assoc();
$blockStmt->close();

if ($blockRow) {
    $default = "Hidden";
    $isBlocked = ((int)$blockRow['blocker_id'] === $myid && (int)$blockRow['blocked_id'] === $userid);
    $isBlockedBy = ((int)$blockRow['blocker_id'] === $userid && (int)$blockRow['blocked_id'] === $myid);

    echo json_encode([
        "status" => "success",
        "blocked_profile" => true,
        "block_status" => [
            "is_blocked" => $isBlocked,
            "is_blocked_by" => $isBlockedBy,
            "either_blocked" => true,
        ],
        "data" => [
            "personalDetail" => [
                "photo_request" => "not_sent",
                "photo_request_type" => "none",
                "chat_request" => "not_sent",
                "chat_request_type" => "none",
                "firstName" => $default,
                "lastName" => "",
                "profile_picture" => "",
                "usertype" => "",
                "isVerified" => 0,
                "privacy" => "private",
                "city" => $default,
                "country" => $default,
                "educationmedium" => $default,
                "educationtype" => $default,
                "faculty" => $default,
                "degree" => $default,
                "areyouworking" => $default,
                "occupationtype" => $default,
                "companyname" => $default,
                "designation" => $default,
                "workingwith" => $default,
                "annualincome" => $default,
                "businessname" => $default,
                "memberid" => $default,
                "height_name" => $default,
                "maritalStatusId" => "",
                "maritalStatusName" => $default,
                "motherTongue" => $default,
                "aboutMe" => $default,
                "birthDate" => $default,
                "Disability" => $default,
                "bloodGroup" => $default,
                "religionName" => $default,
                "communityName" => $default,
                "subCommunityName" => $default,
                "manglik" => $default,
                "birthtime" => $default,
                "birthcity" => $default,
            ],
            "familyDetail" => [],
            "lifestyle" => [],
            "partner" => [],
        ],
        "partner_match" => [
            "matched_count" => 0,
            "total_count" => 0,
            "details" => [],
        ],
        "gallery" => [],
        "access_control" => [
            "current_user_plan" => "free",
            "can_view_photo" => false,
            "can_chat" => false,
            "can_send_requests" => false,
        ],
    ]);
    $conn->close();
    exit;
}

/* =============================
   CURRENT USER PLAN
============================= */

$current_plan = "free";
$viewer_is_verified = false;

$planStmt = $conn->prepare("SELECT usertype, isVerified FROM users WHERE id=?");
$planStmt->bind_param("i",$myid);
$planStmt->execute();
$planRes = $planStmt->get_result();
if($planRes->num_rows>0){
    $p = $planRes->fetch_assoc();
    if($p['usertype']=="paid") $current_plan="paid";
    // isVerified is a persisted column in the users table.  It is updated by
    // masterdata.php whenever document status changes (approved / rejected).
    // !empty() treats 0, NULL, and "" all as false, matching MySQL TINYINT(1).
    $viewer_is_verified = !empty($p['isVerified']);
}
$planStmt->close();

/* =============================
   PHOTO REQUEST
============================= */

$photo_request="not_sent";
$photo_request_type="none";
$can_view_photo=false;
$photo_access_active=false;
$photo_access_expires_at=null;
$photo_access_remaining_seconds=0;

$photoStmt=$conn->prepare("
SELECT sender_id,receiver_id,status,created_at FROM proposals
WHERE request_type='Photo'
AND ((sender_id=? AND receiver_id=?)
OR (sender_id=? AND receiver_id=?))
ORDER BY id DESC LIMIT 1
");
$photoStmt->bind_param("iiii",$myid,$userid,$userid,$myid);
$photoStmt->execute();
$photoRes=$photoStmt->get_result();

if($photoRes->num_rows>0){
    $photoRow=$photoRes->fetch_assoc();
    $photo_request=$photoRow['status'];

    if($photoRow['sender_id']==$myid){
        $photo_request_type="sent";
    }else{
        $photo_request_type="received";
    }

    // Photo visibility is valid for 24 hours from accepted timestamp.
    if ($photo_request === "accepted") {
        $accepted_at_raw = $photoRow['created_at'] ?? null;
        $accepted_ts = $accepted_at_raw ? strtotime($accepted_at_raw) : false;
        if ($accepted_ts !== false) {
            $expires_ts = $accepted_ts + (24 * 60 * 60);
            $now_ts = time();
            if ($now_ts <= $expires_ts) {
                $photo_access_active = true;
                $can_view_photo = true;
                $photo_access_remaining_seconds = max(0, $expires_ts - $now_ts);
            }
            $photo_access_expires_at = gmdate('c', $expires_ts);
        }
    }
}
$photoStmt->close();

/* =============================
   CHAT REQUEST
============================= */

$chat_request="not_sent";
$chat_request_type="none";
$can_chat=false;

$chatStmt=$conn->prepare("
SELECT sender_id,receiver_id,status FROM proposals
WHERE request_type='Chat'
AND ((sender_id=? AND receiver_id=?)
OR (sender_id=? AND receiver_id=?))
ORDER BY id DESC LIMIT 1
");
$chatStmt->bind_param("iiii",$myid,$userid,$userid,$myid);
$chatStmt->execute();
$chatRes=$chatStmt->get_result();

if($chatRes->num_rows>0){
    $chatRow=$chatRes->fetch_assoc();
    $chat_request=$chatRow['status'];

    if($chatRow['sender_id']==$myid){
        $chat_request_type="sent";
    }else{
        $chat_request_type="received";
    }
}

// Chat requires both: viewer has a paid package AND the chat request is accepted.
// A package alone does not unlock direct messaging — an accepted request is
// always required.  Free users can still accept incoming requests (the request
// system is open to all verified users) but cannot open the chat screen itself.
if($current_plan=="paid" && $chat_request=="accepted"){
    $can_chat=true;
}
$chatStmt->close();

/* =============================
   FULL PROFILE QUERY (ALL SECTIONS)
============================= */

$sql = "SELECT 
u.firstName,u.lastName,u.profile_picture,u.profile_photo_status,u.usertype,u.isVerified,u.privacy,
pa.city,pa.country,
ec.educationmedium AS ec_educationmedium,
ec.educationtype,ec.faculty,ec.degree,
ec.areyouworking,ec.occupationtype,ec.companyname,
ec.designation AS ec_designation,
ec.workingwith AS ec_workingwith,ec.annualincome AS ec_annualincome,ec.businessname,
up.memberid,up.height_name,up.maritalStatusId,ms.name AS maritalStatusName,
up.religionId,up.communityId,up.subCommunityId,
up.motherTongue,up.aboutMe,up.birthDate,up.Disability,up.bloodGroup,
r.name AS religionName,
c.name AS communityName,
sc.name AS subCommunityName,
ua.manglik,ua.birthtime,ua.birthcity,
uf.id AS familyId,uf.familytype,uf.familybackground,
uf.fatherstatus,uf.fathername,uf.fathereducation,uf.fatheroccupation,
uf.motherstatus,uf.mothercaste,uf.mothereducation,uf.motheroccupation,uf.familyorigin,
ul.id AS lifestyleId,ul.smoketype,ul.diet,ul.drinks,ul.drinktype,ul.smoke,
upa.minage,upa.maxage,upa.maritalstatus,upa.profilewithchild,
upa.minheight,upa.maxheight,
upa.familytype AS partnerFamilyType,
upa.religion AS partnerReligion,
upa.caste AS partnerCaste,
upa.mothertoungue AS partnerMotherTongue,
upa.herscopeblief,
upa.manglik AS partnerManglik,
upa.country AS partnerCountry,
upa.state AS partnerState,
upa.city AS partnerCity,
upa.qualification AS partnerQualification,
upa.educationmedium AS partnerEducationMedium,
upa.proffession AS partnerProfession,
upa.workingwith AS partnerWorkingWith,
upa.annualincome AS partnerAnnualIncome,
upa.diet AS partnerDiet,
upa.smokeaccept,upa.drinkaccept,upa.disabilityaccept,
upa.complexion AS partnerComplexion,
upa.bodytype AS partnerBodyType,
upa.otherexpectation AS partnerOtherExpectation
FROM users u
LEFT JOIN permanent_address pa ON u.id=pa.userid
LEFT JOIN educationcareer ec ON u.id=ec.userid
LEFT JOIN userpersonaldetail up ON u.id=up.userid
LEFT JOIN maritalstatus ms ON up.maritalStatusId=ms.id
LEFT JOIN religion r ON up.religionId=r.id
LEFT JOIN community c ON up.communityId=c.id
LEFT JOIN subcommunity sc ON up.subCommunityId=sc.id
LEFT JOIN user_astrologic ua ON u.id=ua.userid
LEFT JOIN user_family uf ON u.id=uf.userid
LEFT JOIN user_lifestyle ul ON u.id=ul.userid
LEFT JOIN user_partner upa ON u.id=upa.userid
WHERE u.id=?";

$stmt=$conn->prepare($sql);
$stmt->bind_param("i",$userid);
$stmt->execute();
$res=$stmt->get_result();

if($res->num_rows==0){
    echo json_encode(["status"=>"error","message"=>"User not found"]);
    exit;
}

$row=$res->fetch_assoc();

$raw_profile_picture = (string)($row['profile_picture'] ?? '');
$resolved_profile_picture = $raw_profile_picture !== ''
    ? (preg_match('#^https?://#i', $raw_profile_picture) ? $raw_profile_picture : $base_url . ltrim($raw_profile_picture, '/'))
    : '';

// Mandatory photo-request gating: profile photo is revealed only after
// photo request is accepted AND admin has approved the photo.
$profile_photo_status = (string)($row['profile_photo_status'] ?? 'pending');
$profile_picture = ($can_view_photo && $profile_photo_status === 'approved') ? $resolved_profile_picture : "";

$default="Not available";

/* =============================
   PARTNER MATCH CALCULATION
============================= */

$currentUser=$conn->query("
SELECT up.birthDate, up.height_name, up.motherTongue, up.Disability,
       r.name AS religion, c.name AS community,
       ms.name AS maritalStatus,
       pa.country, pa.state, pa.city,
       ul.diet, ul.smoke, ul.drinks,
       uf.familytype,
       ec.degree, ec.occupationtype
FROM users u
LEFT JOIN userpersonaldetail up ON u.id=up.userid
LEFT JOIN religion r ON up.religionId=r.id
LEFT JOIN community c ON up.communityId=c.id
LEFT JOIN maritalstatus ms ON up.maritalStatusId=ms.id
LEFT JOIN permanent_address pa ON u.id=pa.userid
LEFT JOIN user_lifestyle ul ON u.id=ul.userid
LEFT JOIN user_family uf ON u.id=uf.userid
LEFT JOIN educationcareer ec ON u.id=ec.userid
WHERE u.id=$myid
")->fetch_assoc();

function age($dob){
 if(empty($dob)) return 0;
 return (new DateTime())->diff(new DateTime($dob))->y;
}

// Helper: check if viewer's value satisfies a preference field (comma-separated or single, "Any" = always match)
function prefMatch($pref, $value) {
    $p = trim($pref ?? '');
    if ($p === '' || $p === 'Not available' || $p === '0') return true; // unset = all accepted
    $items = array_map('trim', explode(',', $p));
    if (in_array('Any', $items)) return true;
    return in_array(trim($value ?? ''), $items);
}

// Helper: extract numeric cm from height string like "170 cm" or "170"
function extractCm($h) {
    if (preg_match('/(\d+)/', (string)($h ?? ''), $m)) return (int)$m[1];
    return 0;
}

$current_age = age($currentUser['birthDate'] ?? '');
$viewer_h    = extractCm($currentUser['height_name'] ?? '');
$min_h       = extractCm($row['minheight'] ?? '');
$max_h       = extractCm($row['maxheight'] ?? '');

$minage = (int)($row['minage'] ?? 0);
$maxage = (int)($row['maxage'] ?? 0);

$partner_match=[
    "age"        => ($minage == 0 && $maxage == 0) || ($current_age >= $minage && $current_age <= $maxage),
    "height"     => ($min_h == 0 && $max_h == 0) || ($viewer_h > 0 && $viewer_h >= $min_h && $viewer_h <= $max_h),
    "religion"   => prefMatch($row['partnerReligion'], $currentUser['religion']),
    "caste"      => prefMatch($row['partnerCaste'], $currentUser['community']),
    "maritalstatus" => prefMatch($row['maritalstatus'], $currentUser['maritalStatus']),
    "mothertoungue" => prefMatch($row['partnerMotherTongue'], $currentUser['motherTongue']),
    "country"    => prefMatch($row['partnerCountry'], $currentUser['country']),
    "state"      => prefMatch($row['partnerState'], $currentUser['state']),
    "city"       => prefMatch($row['partnerCity'], $currentUser['city']),
    "diet"       => prefMatch($row['partnerDiet'], $currentUser['diet']),
    "smokeaccept"=> prefMatch($row['smokeaccept'], $currentUser['smoke']),
    "drinkaccept"=> prefMatch($row['drinkaccept'], $currentUser['drinks']),
    "familytype" => prefMatch($row['partnerFamilyType'], $currentUser['familytype']),
    "qualification"=> prefMatch($row['partnerQualification'], $currentUser['degree']),
    "proffession"  => prefMatch($row['partnerProfession'], $currentUser['occupationtype']),
    "disabilityaccept" => prefMatch($row['disabilityaccept'], $currentUser['Disability']),
];

$total_preferences    = count($partner_match);
$matched_preferences  = count(array_filter($partner_match));

/* =============================
   GALLERY
============================= */

$gallery=[];
// Always fetch approved gallery photos - frontend controls visibility based on can_view_photo
$g=$conn->prepare("SELECT id,imageurl,status,reject_reason FROM user_gallery WHERE userid=? AND status='approved'");
$g->bind_param("i",$userid);
$g->execute();
$gr=$g->get_result();
while($img=$gr->fetch_assoc()){
 $rawImageUrl = (string)($img['imageurl'] ?? '');
 $imageUrl = preg_match('#^https?://#i', $rawImageUrl)
    ? $rawImageUrl
    : $base_url . ltrim($rawImageUrl, '/');
 $gallery[]=[
  "id"=>$img['id'],
    "imageurl"=>$imageUrl,
  "status"=>$img['status'],
  "reject_reason"=>$img['reject_reason']
 ];
}
$g->close();

/* =============================
   FINAL RESPONSE
============================= */

echo json_encode([
 "status"=>"success",
 "data"=>[
  "personalDetail"=>[
    "photo_request"=>$photo_request,
   "photo_request_type"=>$photo_request_type,
   "chat_request"=>$chat_request,
   "chat_request_type"=>$chat_request_type,
   "firstName"=>$row['firstName']??$default,
   "lastName"=>$row['lastName']??$default,
   "profile_picture"=>$profile_picture,
   "usertype"=>$row['usertype'],
   "isVerified"=>$row['isVerified'],
   "privacy"=>$row['privacy'],
   "city"=>$row['city'],
   "country"=>$row['country'],
   "educationmedium" => $row['ec_educationmedium'] ?? $default,
        "educationtype" => $row['educationtype'] ?? $default,
        "faculty" => $row['faculty'] ?? $default,
        "degree" => $row['degree'] ?? $default,
        "areyouworking" => $row['areyouworking'] ?? $default,
        "occupationtype" => $row['occupationtype'] ?? $default,
        "companyname" => $row['companyname'] ?? $default,
        "designation" => $row['ec_designation'] ?? $default,
        "workingwith" => $row['ec_workingwith'] ?? $default,
        "annualincome" => $row['ec_annualincome'] ?? $default,
        "businessname" => $row['businessname'] ?? $default,
        "memberid" => $row['memberid'] ?? $default,
        "height_name" => $row['height_name'] ?? $default,
        "maritalStatusId" => $row['maritalStatusId'] ?? $default,
            "religionId" => (int)($row['religionId'] ?? 0),
            "communityId" => (int)($row['communityId'] ?? 0),
            "subCommunityId" => (int)($row['subCommunityId'] ?? 0),
            "maritalStatusName" => $row['maritalStatusName'] ?? $default,
        "motherTongue" => $row['motherTongue'] ?? $default,
        "aboutMe" => $row['aboutMe'] ?? $default,
        "birthDate" => $row['birthDate'] ?? $default,
        "Disability" => $row['Disability'] ?? $default,
        "bloodGroup" => $row['bloodGroup'] ?? $default,
        "religionName" => $row['religionName'] ?? $default,
        "communityName" => $row['communityName'] ?? $default,
        "subCommunityName" => $row['subCommunityName'] ?? $default,
        "manglik" => $row['manglik'] ?? $default,
        "birthtime" => $row['birthtime'] ?? $default,
        "birthcity" => $row['birthcity'] ?? $default
   
  ],
  "familyDetail" => [
        "familyId" => $row['familyId'] ?? $default,
        "familytype" => $row['familytype'] ?? $default,
        "familybackground" => $row['familybackground'] ?? $default,
        "fatherstatus" => $row['fatherstatus'] ?? $default,
        "fathername" => $row['fathername'] ?? $default,
        "fathereducation" => $row['fathereducation'] ?? $default,
        "fatheroccupation" => $row['fatheroccupation'] ?? $default,
        "motherstatus" => $row['motherstatus'] ?? $default,
        "mothercaste" => $row['mothercaste'] ?? $default,
        "mothereducation" => $row['mothereducation'] ?? $default,
        "motheroccupation" => $row['motheroccupation'] ?? $default,
        "familyorigin" => $row['familyorigin'] ?? $default
    ],
  "lifestyle" => [
        "lifestyleId" => $row['lifestyleId'] ?? $default,
        "smoketype" => $row['smoketype'] ?? $default,
        "diet" => $row['diet'] ?? $default,
        "drinks" => $row['drinks'] ?? $default,
        "drinktype" => $row['drinktype'] ?? $default,
        "smoke" => $row['smoke'] ?? $default
    ],
"partner" => [
        "minage" => $row['minage'] ?? $default,
        "maxage" => $row['maxage'] ?? $default,
            "minheight" => $row['minheight'] ?? $default,
            "maxheight" => $row['maxheight'] ?? $default,
            "maritalstatus" => $row['maritalstatus'] ?? $default,
        "profilewithchild" => $row['profilewithchild'] ?? $default,
        "familytype" => $row['partnerFamilyType'] ?? $default,
        "religion" => $row['partnerReligion'] ?? $default,
        "caste" => $row['partnerCaste'] ?? $default,
        "mothertoungue" => $row['partnerMotherTongue'] ?? $default,
        "herscopeblief" => $row['herscopeblief'] ?? $default,
        "manglik" => $row['partnerManglik'] ?? $default,
        "country" => $row['partnerCountry'] ?? $default,
        "state" => $row['partnerState'] ?? $default,
        "city" => $row['partnerCity'] ?? $default,
        "qualification" => $row['partnerQualification'] ?? $default,
        "educationmedium" => $row['partnerEducationMedium'] ?? $default,
        "proffession" => $row['partnerProfession'] ?? $default,
        "workingwith" => $row['partnerWorkingWith'] ?? $default,
        "annualincome" => $row['partnerAnnualIncome'] ?? $default,
        "diet" => $row['partnerDiet'] ?? $default,
        "smokeaccept" => $row['smokeaccept'] ?? $default,
        "drinkaccept" => $row['drinkaccept'] ?? $default,
        "disabilityaccept" => $row['disabilityaccept'] ?? $default,
        "complexion" => $row['partnerComplexion'] ?? $default,
        "bodytype" => $row['partnerBodyType'] ?? $default,
        "otherexpectation" => $row['partnerOtherExpectation'] ?? $default
    ]
 ],
 "partner_match"=>[
  "matched_count"=>$matched_preferences,
  "total_count"=>$total_preferences,
  "details"=>$partner_match
 ],
 "gallery"=>$gallery,
 "access_control"=>[
  "current_user_plan"=>$current_plan,
  "can_view_photo"=>$can_view_photo,
  "can_chat"=>$can_chat,
  // Sending a request requires: viewer is document-verified AND has a paid package.
            "photo_access_active" => false,
            "photo_access_expires_at" => null,
            "photo_access_remaining_seconds" => 0,
    "can_send_requests"=>($current_plan=="paid" && $viewer_is_verified),
    "photo_access_active"=>$photo_access_active,
    "photo_access_expires_at"=>$photo_access_expires_at,
    "photo_access_remaining_seconds"=>$photo_access_remaining_seconds
 ]
]);

$stmt->close();
$conn->close();
?> 