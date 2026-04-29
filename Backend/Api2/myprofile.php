<?php
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');

// Handle preflight OPTIONS request
if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    http_response_code(200);
    exit();
}

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

if ($userid <= 0) {
    echo json_encode([
        "status" => "error",
        "message" => "Invalid user ID"
    ]);
    exit;
}

// Prepare SQL statement for full profile including partner preferences
$sql = "
SELECT 
    -- Users table
    u.firstName, u.lastName, u.profile_picture, u.usertype, u.isVerified,

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

    // Restructure JSON into sections
    $data = [
        "personalDetail" => [
            "firstName" => $row['firstName'],
            "lastName" => $row['lastName'],
            "profile_picture" => $row['profile_picture'],
            "usertype" => $row['usertype'],
            "isVerified" => $row['isVerified'],
            "city" => $row['city'],
            "country" => $row['country'],

            // Profession/Education career
            "educationmedium" => $row['ec_educationmedium'],
            "educationtype" => $row['educationtype'],
            "faculty" => $row['faculty'],
            "degree" => $row['degree'],
            "areyouworking" => $row['areyouworking'],
            "occupationtype" => $row['occupationtype'],
            "companyname" => $row['companyname'],
            "designation" => $row['ec_designation'],
            "workingwith" => $row['ec_workingwith'],
            "annualincome" => $row['ec_annualincome'],
            "businessname" => $row['businessname'],

            // Personal details
            "memberid" => $row['memberid'],
            "height_name" => $row['height_name'],
            "maritalStatusId" => $row['maritalStatusId'],
            "maritalStatusName" => $row['maritalStatusName'],
            "motherTongue" => $row['motherTongue'],
            "aboutMe" => $row['aboutMe'],
            "birthDate" => $row['birthDate'],
            "Disability" => $row['Disability'],
            "bloodGroup" => $row['bloodGroup'],
            "religionName" => $row['religionName'],
            "communityName" => $row['communityName'],
            "subCommunityName" => $row['subCommunityName'],
            "manglik" => $row['manglik'],
            "birthtime" => $row['birthtime'],
            "birthcity" => $row['birthcity']
        ],
        "familyDetail" => [
            "familyId" => $row['familyId'],
            "familytype" => $row['familytype'],
            "familybackground" => $row['familybackground'],
            "fatherstatus" => $row['fatherstatus'],
            "fathername" => $row['fathername'],
            "fathereducation" => $row['fathereducation'],
            "fatheroccupation" => $row['fatheroccupation'],
            "motherstatus" => $row['motherstatus'],
            "mothercaste" => $row['mothercaste'],
            "mothereducation" => $row['mothereducation'],
            "motheroccupation" => $row['motheroccupation'],
            "familyorigin" => $row['familyorigin']
        ],
        "lifestyle" => [
            "lifestyleId" => $row['lifestyleId'],
            "smoketype" => $row['smoketype'],
            "diet" => $row['diet'],
            "drinks" => $row['drinks'],
            "drinktype" => $row['drinktype'],
            "smoke" => $row['smoke']
        ],
        "partner" => [
            "minage" => $row['minage'],
            "maxage" => $row['maxage'],
           // "minweight" => $row['minweight'],
           // "maxweight" => $row['maxweight'],
            "maritalstatus" => $row['maritalstatus'],
            "profilewithchild" => $row['profilewithchild'],
            "familytype" => $row['partnerFamilyType'],
            "religion" => $row['partnerReligion'],
            "caste" => $row['partnerCaste'],
            "mothertoungue" => $row['partnerMotherTongue'],
            "herscopeblief" => $row['herscopeblief'],
            "manglik" => $row['partnerManglik'],
            "country" => $row['partnerCountry'],
            "state" => $row['partnerState'],
            "city" => $row['partnerCity'],
            "qualification" => $row['partnerQualification'],
            "educationmedium" => $row['partnerEducationMedium'],
            "proffession" => $row['partnerProfession'],
            "workingwith" => $row['partnerWorkingWith'],
            "annualincome" => $row['partnerAnnualIncome'],
            "diet" => $row['partnerDiet'],
            "smokeaccept" => $row['smokeaccept'],
            "drinkaccept" => $row['drinkaccept'],
            "disabilityaccept" => $row['disabilityaccept'],
            "complexion" => $row['partnerComplexion'],
            "bodytype" => $row['partnerBodyType'],
            "otherexpectation" => $row['partnerOtherExpectation']
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
