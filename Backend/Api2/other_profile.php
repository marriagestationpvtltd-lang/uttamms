<?php
header('Content-Type: application/json');

// Build Api2 base URL dynamically from current host/path.
$isHttps = (
    (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off')
    || (isset($_SERVER['SERVER_PORT']) && (int) $_SERVER['SERVER_PORT'] === 443)
);
$scheme = $isHttps ? 'https' : 'http';
$host = $_SERVER['HTTP_HOST'] ?? 'localhost';
$scriptDir = str_replace('\\', '/', dirname($_SERVER['SCRIPT_NAME'] ?? ''));
$scriptDir = rtrim($scriptDir, '/');
$base_url = $scheme . '://' . $host . $scriptDir . '/';

// Database configuration
$host = "localhost"; 
$db_name = "ms";
$username = "root";
$password = "";

// Create connection
$conn = new mysqli($host, $username, $password, $db_name);

// Check connection
if ($conn->connect_error) {
    die(json_encode([
        "status" => "error",
        "message" => "Database connection failed: " . $conn->connect_error
    ]));
}

// Get userid from GET or POST
$userid = isset($_GET['userid']) ? intval($_GET['userid']) : 0;
$myid   = isset($_GET['myid']) ? intval($_GET['myid']) : 0;
$includeAllGallery = isset($_GET['include_all_gallery']) && $_GET['include_all_gallery'] === '1';
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


$photo_request = "not sent";

$photoSql = "
SELECT status 
FROM proposals
WHERE request_type = 'Photo'
AND (
    (sender_id = ? AND receiver_id = ?)
    OR
    (sender_id = ? AND receiver_id = ?)
)
ORDER BY id DESC
LIMIT 1
";

$photoStmt = $conn->prepare($photoSql);
$photoStmt->bind_param("iiii", $myid, $userid, $userid, $myid);
$photoStmt->execute();
$photoResult = $photoStmt->get_result();

if ($photoResult->num_rows > 0) {
    $photoRow = $photoResult->fetch_assoc();
    $photo_request = ($photoRow['status'] === 'accepted') ? 'accepted' : 'pending';
}
$photoStmt->close();

// Prepare SQL statement for full profile including partner preferences
$sql = "
SELECT 
    u.firstName, u.lastName, u.profile_picture, u.profile_photo_status, u.usertype, u.isVerified,
    u.privacy,  -- added privacy
    u.email, u.contactNo,

    -- Permanent address
    pa.city, pa.country,

    -- Education career / Profession
    ec.educationmedium AS ec_educationmedium,
    ec.educationtype, ec.faculty, ec.degree,
    ec.areyouworking, ec.occupationtype, ec.companyname,
    ec.designation AS ec_designation,
    ec.workingwith AS ec_workingwith, ec.annualincome AS ec_annualincome, ec.businessname,

    -- Personal details
    up.memberid, up.height_name, up.maritalStatusId, up.religionId, up.communityId, up.subCommunityId, ms.name AS maritalStatusName,
    up.motherTongue, up.aboutMe, up.birthDate, up.Disability, up.bloodGroup,
    r.name AS religionName,
    c.name AS communityName,
    sc.name AS subCommunityName,

    -- Astrologic details
    ua.manglik, ua.birthtime, ua.birthcity,

    -- Family details
    uf.id AS familyId, uf.familytype, uf.familybackground,
    uf.fatherstatus, uf.fathername, uf.fathereducation, uf.fatheroccupation,
    uf.motherstatus, uf.mothercaste, uf.mothereducation, uf.motheroccupation, uf.familyorigin,

    -- Lifestyle details
    ul.id AS lifestyleId, ul.smoketype, ul.diet, ul.drinks, ul.drinktype, ul.smoke,

    -- Partner preferences
    upa.minage, upa.maxage, upa.maritalstatus, upa.profilewithchild,
        upa.minheight, upa.maxheight,
    upa.familytype AS partnerFamilyType, upa.religion AS partnerReligion, upa.caste AS partnerCaste,
    upa.mothertoungue AS partnerMotherTongue, upa.herscopeblief, upa.manglik AS partnerManglik,
    upa.country AS partnerCountry, upa.state AS partnerState, upa.city AS partnerCity,
    upa.qualification AS partnerQualification, upa.educationmedium AS partnerEducationMedium,
    upa.proffession AS partnerProfession, upa.workingwith AS partnerWorkingWith, upa.annualincome AS partnerAnnualIncome,
    upa.diet AS partnerDiet, upa.smokeaccept, upa.drinkaccept, upa.disabilityaccept,
    upa.complexion AS partnerComplexion, upa.bodytype AS partnerBodyType, upa.otherexpectation AS partnerOtherExpectation

FROM users u
LEFT JOIN permanent_address pa ON u.id = pa.userid
LEFT JOIN educationcareer ec ON u.id = ec.userid
LEFT JOIN userpersonaldetail up ON u.id = up.userid
LEFT JOIN maritalstatus ms ON up.maritalStatusId = ms.id
LEFT JOIN religion r ON up.religionId = r.id
LEFT JOIN community c ON up.communityId = c.id
LEFT JOIN subcommunity sc ON up.subCommunityId = sc.id
LEFT JOIN user_astrologic ua ON u.id = ua.userid
LEFT JOIN user_family uf ON u.id = uf.userid
LEFT JOIN user_lifestyle ul ON u.id = ul.userid
LEFT JOIN user_partner upa ON u.id = upa.userid
WHERE u.id = ?
";

$stmt = $conn->prepare($sql);
$stmt->bind_param("i", $userid);
$stmt->execute();
$result = $stmt->get_result();

if ($result->num_rows > 0) {
    $row = $result->fetch_assoc();

    // Mandatory photo-request gating: reveal profile photo only after accepted
    // photo request AND admin-approved status.
    $can_view_photo = ($photo_request === 'accepted');
    $rawProfilePicture = (string)($row['profile_picture'] ?? '');
    $resolvedProfilePicture = '';
    if ($rawProfilePicture !== '') {
        $resolvedProfilePicture = preg_match('#^https?://#i', $rawProfilePicture)
            ? $rawProfilePicture
            : $base_url . ltrim($rawProfilePicture, '/');
    }
    $profile_photo_status = (string)($row['profile_photo_status'] ?? 'pending');

    // Admin/details screens can request include_all_gallery=1 and still receive images.
    $profile_picture = $includeAllGallery
        ? $resolvedProfilePicture
        : (($can_view_photo && $profile_photo_status === 'approved') ? $resolvedProfilePicture : '');

// Define a default value
$default = "Not available"; // You can change this to any default value you like

// Restructure JSON into sections with null coalescing
$data = [
    "personalDetail" => [
        // For admin (include_all_gallery=1) return admin-approval status;
        // for regular viewers return the photo-access request status.
        "photo_request" => $includeAllGallery ? $profile_photo_status : $photo_request,

        "firstName" => $row['firstName'] ?? $default,
        "lastName" => $row['lastName'] ?? $default,
        "profile_picture" => $profile_picture,
        "usertype" => $row['usertype'] ?? $default,
        "isVerified" => $row['isVerified'] ?? $default,
        "privacy" => $row['privacy'] ?? $default, 
        "city" => $row['city'] ?? $default,
        "country" => $row['country'] ?? $default,
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
        "religionId" => $row['religionId'] ?? $default,
        "communityId" => $row['communityId'] ?? $default,
        "subCommunityId" => $row['subCommunityId'] ?? $default,
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
    ],
    "contactDetail" => [
        "email" => $row['email'] ?? "",
        "phone" => $row['contactNo'] ?? "",
        "whatsapp" => $row['contactNo'] ?? "",
        "country_code" => ""
    ]
];

    $gallery = [];
    if ($includeAllGallery) {
        // Admin detail screen: return all gallery rows (pending/approved/rejected)
        // so review actions are available.
        $galleryStmt = $conn->prepare(
            'SELECT id, imageurl, status, reject_reason, created_at
             FROM user_gallery
             WHERE userid = ?
             ORDER BY id DESC'
        );
    } else {
        // Public/user profile view: return only approved gallery photos.
        $galleryStmt = $conn->prepare(
            'SELECT id, imageurl, status, reject_reason, created_at
             FROM user_gallery
             WHERE userid = ? AND status = "approved"
             ORDER BY id DESC'
        );
    }

    $galleryStmt->bind_param('i', $userid);
    $galleryStmt->execute();
    $galleryResult = $galleryStmt->get_result();

    while ($img = $galleryResult->fetch_assoc()) {
        $rawImageUrl = (string) ($img['imageurl'] ?? '');
        $imageUrl = preg_match('#^https?://#i', $rawImageUrl)
            ? $rawImageUrl
            : $base_url . ltrim($rawImageUrl, '/');

        $gallery[] = [
            'id' => (int) ($img['id'] ?? 0),
            'imageurl' => $imageUrl,
            'status' => (string) ($img['status'] ?? 'pending'),
            'reject_reason' => $img['reject_reason'] ?? null,
            'created_at' => $img['created_at'] ?? null,
        ];
    }
    $galleryStmt->close();

        // ── Admin partner_match: count DB users who satisfy this user's partner preferences ──
        // Helper: add an IN-condition for comma-separated prefs (skips if empty / Any / 0)
        function addPrefCond(&$conds, &$dets, $conn, $pref, $col, $key) {
            $p = trim($pref ?? '');
            if ($p === '' || $p === 'Not available' || $p === '0') return;
            $items = array_filter(array_map('trim', explode(',', $p)));
            if (empty($items) || in_array('Any', $items)) return;
            $esc = array_map(function($v) use ($conn) {
                return "'" . $conn->real_escape_string($v) . "'";
            }, $items);
            $conds[] = "$col IN (" . implode(',', $esc) . ")";
            $dets[$key] = $p;
        }

        $pmJoins = "users u2
            LEFT JOIN userpersonaldetail up2 ON u2.id = up2.userid
            LEFT JOIN religion r2 ON up2.religionId = r2.id
            LEFT JOIN maritalstatus ms2 ON up2.maritalStatusId = ms2.id
            LEFT JOIN permanent_address pa2 ON u2.id = pa2.userid
            LEFT JOIN user_lifestyle ul2 ON u2.id = ul2.userid
            LEFT JOIN user_family uf2 ON u2.id = uf2.userid
            LEFT JOIN educationcareer ec2 ON u2.id = ec2.userid";

        $pmConds  = ["u2.id != $userid"];
        $pmDetail = [];

        // Age
        $pmMinage = (int)($row['minage'] ?? 0);
        $pmMaxage = (int)($row['maxage'] ?? 0);
        if ($pmMinage > 0 || $pmMaxage > 0) {
            $ac = [];
            if ($pmMinage > 0) $ac[] = "TIMESTAMPDIFF(YEAR, up2.birthDate, CURDATE()) >= $pmMinage";
            if ($pmMaxage > 0) $ac[] = "TIMESTAMPDIFF(YEAR, up2.birthDate, CURDATE()) <= $pmMaxage";
            $pmConds[]           = '(' . implode(' AND ', $ac) . ')';
            $pmDetail['age']     = "$pmMinage - $pmMaxage yrs";
        }

        // Height (stored as "170 cm"; strip the " cm" suffix for numeric comparison)
        $pmMinH = (int)preg_replace('/\D+/', '', $row['minheight'] ?? '');
        $pmMaxH = (int)preg_replace('/\D+/', '', $row['maxheight'] ?? '');
        if ($pmMinH > 0 || $pmMaxH > 0) {
            $hc = [];
            if ($pmMinH > 0) $hc[] = "TRIM(SUBSTRING_INDEX(up2.height_name,' cm',1)) + 0 >= $pmMinH";
            if ($pmMaxH > 0) $hc[] = "TRIM(SUBSTRING_INDEX(up2.height_name,' cm',1)) + 0 <= $pmMaxH";
            $pmConds[]            = '(' . implode(' AND ', $hc) . ')';
            $pmDetail['height']   = "$pmMinH - $pmMaxH cm";
        }

        // Multi-value preference criteria
        addPrefCond($pmConds, $pmDetail, $conn, $row['partnerReligion'],      'r2.name',          'religion');
        addPrefCond($pmConds, $pmDetail, $conn, $row['maritalstatus'],        'ms2.name',         'marital_status');
        addPrefCond($pmConds, $pmDetail, $conn, $row['partnerCountry'],       'pa2.country',      'country');
        addPrefCond($pmConds, $pmDetail, $conn, $row['partnerState'],         'pa2.state',        'state');
        addPrefCond($pmConds, $pmDetail, $conn, $row['partnerCity'],          'pa2.city',         'city');
        addPrefCond($pmConds, $pmDetail, $conn, $row['partnerDiet'],          'ul2.diet',         'diet');
        addPrefCond($pmConds, $pmDetail, $conn, $row['partnerFamilyType'],    'uf2.familytype',   'family_type');
        addPrefCond($pmConds, $pmDetail, $conn, $row['partnerQualification'], 'ec2.degree',       'qualification');
        addPrefCond($pmConds, $pmDetail, $conn, $row['partnerProfession'],    'ec2.occupationtype','profession');

        $pmWhere = implode(' AND ', $pmConds);

        $pmTotalRes = $conn->query("SELECT COUNT(DISTINCT u2.id) AS cnt FROM $pmJoins WHERE u2.id != $userid");
        $pmTotal    = (int)(($pmTotalRes ? $pmTotalRes->fetch_assoc() : [])['cnt'] ?? 0);

        $pmMatchRes = $conn->query("SELECT COUNT(DISTINCT u2.id) AS cnt FROM $pmJoins WHERE $pmWhere");
        $pmMatched  = (int)(($pmMatchRes ? $pmMatchRes->fetch_assoc() : [])['cnt'] ?? 0);

        $partner_match = [
            "matched_count" => $pmMatched,
            "total_count"   => $pmTotal,
            "details"       => $pmDetail,
        ];

    echo json_encode([
        "status" => "success",
        "data" => $data,
        "gallery" => $gallery,
            "partner_match" => $partner_match,
        "access_control" => [
            "can_view_photo" => $can_view_photo
        ]
    ]);
} else {
    echo json_encode([
        "status" => "error",
        "message" => "User not found"
    ]);
}

$stmt->close();
$conn->close();
?>
