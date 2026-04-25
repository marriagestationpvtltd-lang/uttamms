<?php
header('Content-Type: application/json');
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: GET, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type, Authorization");
header("Content-Type: application/json");

// Base URL for profile pictures
$base_url = "https://digitallami.com/Api2/";

// Database configuration
$host = "localhost"; 
$db_name = "ms";
$username = "ms";
$password = "ms";

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
if ($userid <= 0 || $myid <= 0) {
    echo json_encode([
        "status" => "error",
        "message" => "Invalid user ID"
    ]);
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
    u.id, u.firstName, u.lastName, u.email, u.contactNo,
    u.profile_picture, u.usertype, u.isVerified,
    u.privacy,  -- added privacy

    -- Permanent address
    pa.city, pa.country,

    -- Education career / Profession
    ec.educationmedium AS ec_educationmedium,
    ec.educationtype, ec.faculty, ec.degree,
    ec.areyouworking, ec.occupationtype, ec.companyname,
    ec.designation AS ec_designation,
    ec.workingwith AS ec_workingwith, ec.annualincome AS ec_annualincome, ec.businessname,

    -- Personal details
    up.memberid, up.height_name, up.maritalStatusId, ms.name AS maritalStatusName,
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

    // Prefix profile picture with base URL if not empty
    $profile_picture = !empty($row['profile_picture']) ? $base_url . $row['profile_picture'] : "";

    // Restructure JSON into sections
   // Prefix profile picture with base URL if not empty
$profile_picture = !empty($row['profile_picture']) ? $base_url . $row['profile_picture'] : "";

// Define a default value
$default = "Not available"; // You can change this to any default value you like

// Restructure JSON into sections with null coalescing
$data = [
    "personalDetail" => [
        "photo_request" => $photo_request, // ✅ INCLUDED

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
    ],
    "contactDetail" => [
        "email" => $row['email'] ?? '',
        // contactNo is the single contact number stored in the users table.
        // It is used for both the phone and whatsapp fields since there is
        // no separate whatsapp column in the database schema.
        "phone" => $row['contactNo'] ?? '',
        "whatsapp" => $row['contactNo'] ?? '',
        "country_code" => ''
    ]
];

    echo json_encode([
        "status" => "success",
        "data" => $data
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
