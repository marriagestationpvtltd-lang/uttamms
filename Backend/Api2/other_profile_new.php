<?php
header('Content-Type: application/json');
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: GET, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type, Authorization");

$base_url = "https://digitallami.com/Api2/";

$host = "localhost"; 
$db_name = "ms";
$username = "ms";
$password = "ms";

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

/* =============================
   CURRENT USER PLAN
============================= */

$current_plan = "free";

$planStmt = $conn->prepare("SELECT usertype FROM users WHERE id=?");
$planStmt->bind_param("i",$myid);
$planStmt->execute();
$planRes = $planStmt->get_result();
if($planRes->num_rows>0){
    $p = $planRes->fetch_assoc();
    if($p['usertype']=="paid") $current_plan="paid";
}
$planStmt->close();

/* =============================
   PHOTO REQUEST
============================= */

$photo_request="not_sent";
$photo_request_type="none";
$can_view_photo=false;

$photoStmt=$conn->prepare("
SELECT sender_id,receiver_id,status FROM proposals
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
}

// A paid viewer may always see accepted-request photos.
// An unpaid viewer may see photos when the photo request was accepted
// (meaning the other side – who is paid – sent the request and it was accepted).
if($current_plan=="paid" || $photo_request=="accepted"){
    $can_view_photo=true;
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

// A paid user may always chat; an unpaid user may chat when the chat
// request has been accepted (i.e. a paid user reached out to them).
if($current_plan=="paid" || $chat_request=="accepted"){
    $can_chat=true;
}
$chatStmt->close();

/* =============================
   FULL PROFILE QUERY (ALL SECTIONS)
============================= */

$sql = "SELECT 
u.firstName,u.lastName,u.profile_picture,u.usertype,u.isVerified,u.privacy,
pa.city,pa.country,
ec.educationmedium AS ec_educationmedium,
ec.educationtype,ec.faculty,ec.degree,
ec.areyouworking,ec.occupationtype,ec.companyname,
ec.designation AS ec_designation,
ec.workingwith AS ec_workingwith,ec.annualincome AS ec_annualincome,ec.businessname,
up.memberid,up.height_name,up.maritalStatusId,ms.name AS maritalStatusName,
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

$profile_picture=!empty($row['profile_picture'])
?$base_url.$row['profile_picture']:"";

$default="Not available";

/* =============================
   PARTNER MATCH CALCULATION
============================= */

$currentUser=$conn->query("
SELECT up.birthDate,r.name religion,pa.country,pa.city,ul.diet,ul.smoke,ul.drinks
FROM users u
LEFT JOIN userpersonaldetail up ON u.id=up.userid
LEFT JOIN religion r ON up.religionId=r.id
LEFT JOIN permanent_address pa ON u.id=pa.userid
LEFT JOIN user_lifestyle ul ON u.id=ul.userid
WHERE u.id=$myid
")->fetch_assoc();

function age($dob){
 if(empty($dob)) return 0;
 return (new DateTime())->diff(new DateTime($dob))->y;
}

$current_age=age($currentUser['birthDate']);

$partner_match=[
 "age"=>($current_age>=$row['minage'] && $current_age<=$row['maxage']),
 "religion"=>($row['partnerReligion']=="Any" || $row['partnerReligion']==$currentUser['religion']),
 "country"=>($row['partnerCountry']=="Any" || $row['partnerCountry']==$currentUser['country']),
 "city"=>($row['partnerCity']=="Any" || $row['partnerCity']==$currentUser['city']),
 "diet"=>($row['partnerDiet']=="Any" || $row['partnerDiet']==$currentUser['diet'])
];

$total_preferences=count($partner_match);
$matched_preferences=count(array_filter($partner_match));

/* =============================
   GALLERY
============================= */

$gallery=[];
if($can_view_photo){
 $g=$conn->prepare("SELECT id,imageurl,status,reject_reason FROM user_gallery WHERE userid=? AND status='approved'");
 $g->bind_param("i",$userid);
 $g->execute();
 $gr=$g->get_result();
 while($img=$gr->fetch_assoc()){
  $gallery[]=[
   "id"=>$img['id'],
   "imageurl"=>$base_url.$img['imageurl'],
   "status"=>$img['status'],
   "reject_reason"=>$img['reject_reason']
  ];
 }
 $g->close();
}

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
        "minweight" => $row['minweight'] ?? $default,
        "maxweight" => $row['maxweight'] ?? $default,
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
  "can_send_requests"=>($current_plan=="paid")
 ]
]);

$stmt->close();
$conn->close();
?> 