<?php
header('Content-Type: application/json');
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: GET, POST, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type, Authorization");
include 'db_connect.php';

/* ----------------------------------------------------------
   STEP 0: Get user_id from POST
---------------------------------------------------------- */
$postData = json_decode(file_get_contents("php://input"), true);

if (!isset($postData['user_id'])) {
    echo json_encode(["status" => "error", "message" => "user_id is required"]);
    exit;
}

$user_id = intval($postData['user_id']);

/* ----------------------------------------------------------
   STEP 1: Get current user gender
---------------------------------------------------------- */
$userQuery = $conn->prepare("SELECT id, gender FROM users WHERE id = ?");
$userQuery->bind_param("i", $user_id);
$userQuery->execute();
$userResult = $userQuery->get_result();

if ($userResult->num_rows === 0) {
    echo json_encode(["status" => "error", "message" => "User not found"]);
    exit;
}

$user = $userResult->fetch_assoc();
$userGender = $user['gender'];
$oppositeGender = ($userGender === 'Male') ? 'Female' : 'Male';

/* ----------------------------------------------------------
   STEP 2: Get user's partner preferences (optional – may not exist)
---------------------------------------------------------- */
$prefQuery = $conn->prepare("SELECT * FROM userpartnerpreferences WHERE userId = ?");
$prefQuery->bind_param("i", $user_id);
$prefQuery->execute();
$prefResult = $prefQuery->get_result();
$pref = ($prefResult->num_rows > 0) ? $prefResult->fetch_assoc() : null;

/* ----------------------------------------------------------
   STEP 3: Get all opposite gender users
---------------------------------------------------------- */
$matchQuery = $conn->prepare("
    SELECT 
        u.id, u.firstName, u.lastName, u.gender, u.isOnline,
        upd.memberid, upd.occupationId, upd.birthDate,
        upd.heightId, upd.maritalStatusId, upd.religionId, upd.communityId,
        upd.educationId, upd.annualIncomeId, upd.addressId
    FROM users u
    JOIN userpersonaldetail upd ON u.id = upd.userId
    WHERE u.gender = ? AND u.id != ?
    ORDER BY u.isOnline DESC, u.id DESC
    LIMIT 100
");
$matchQuery->bind_param("si", $oppositeGender, $user_id);
$matchQuery->execute();
$matches = $matchQuery->get_result();

/* ----------------------------------------------------------
   STEP 4: Compare preferences & build response
---------------------------------------------------------- */
$responseData = [];

while ($row = $matches->fetch_assoc()) {
    // Calculate age, matching percentage, etc.
    $totalFactors = $matchedFactors = 0;

    // AGE
    $age = null;
    if (!empty($row['birthDate'])) {
        $birth = new DateTime($row['birthDate']);
        $age = (new DateTime())->diff($birth)->y;
        if ($pref !== null) {
            $totalFactors++;
            if ($age >= intval($pref['pFromAge']) && $age <= intval($pref['pToAge'])) {
                $matchedFactors++;
            }
        }
    }

    // HEIGHT
    if ($pref !== null && !empty($row['heightId']) && !empty($pref['pFromHeight']) && !empty($pref['pToHeight'])) {
        $totalFactors++;
        if ($row['heightId'] >= intval($pref['pFromHeight']) && $row['heightId'] <= intval($pref['pToHeight'])) {
            $matchedFactors++;
        }
    }

    // MARITAL STATUS
    if ($pref !== null && !empty($row['maritalStatusId']) && !empty($pref['pMaritalStatusId'])) {
        $totalFactors++;
        if ($row['maritalStatusId'] == $pref['pMaritalStatusId']) $matchedFactors++;
    }

    // RELIGION
    if ($pref !== null && !empty($row['religionId']) && !empty($pref['pReligionId'])) {
        $totalFactors++;
        if ($row['religionId'] == $pref['pReligionId']) $matchedFactors++;
    }

    // COMMUNITY
    if ($pref !== null && !empty($row['communityId']) && !empty($pref['pCommunityId'])) {
        $totalFactors++;
        if ($row['communityId'] == $pref['pCommunityId']) $matchedFactors++;
    }

    // EDUCATION
    if ($pref !== null && !empty($row['educationId']) && !empty($pref['pEducationTypeId'])) {
        $totalFactors++;
        if ($row['educationId'] == $pref['pEducationTypeId']) $matchedFactors++;
    }

    // INCOME
    if ($pref !== null && !empty($row['annualIncomeId']) && !empty($pref['pAnnualIncomeId'])) {
        $totalFactors++;
        if ($row['annualIncomeId'] == $pref['pAnnualIncomeId']) $matchedFactors++;
    }

    $matchPercent = ($totalFactors > 0) ? round(($matchedFactors / $totalFactors) * 100, 1) : 0;

    // is_paid
    $paidQuery = $conn->prepare("SELECT netAmount FROM userpackage WHERE userId = ?");
    $paidQuery->bind_param("i", $row['id']);
    $paidQuery->execute();
    $paidResult = $paidQuery->get_result();
    $is_paid = 0;
    if ($paidResult->num_rows > 0) {
        $paid = $paidResult->fetch_assoc();
        $is_paid = (floatval($paid['netAmount']) > 0) ? 1 : 0;
    }

    // Occupation
    $occupation = "";
    if (!empty($row['occupationId'])) {
        $occQuery = $conn->prepare("SELECT name FROM occupation WHERE id = ?");
        $occQuery->bind_param("i", $row['occupationId']);
        $occQuery->execute();
        $occRes = $occQuery->get_result();
        if ($occRes->num_rows > 0) {
            $occ = $occRes->fetch_assoc();
            $occupation = $occ['name'];
        }
    }

    // Marital Status
    $maritalStatusName = "";
    if (!empty($row['maritalStatusId'])) {
        $msQuery = $conn->prepare("SELECT name FROM maritalstatus WHERE id = ?");
        $msQuery->bind_param("i", $row['maritalStatusId']);
        $msQuery->execute();
        $msRes = $msQuery->get_result();
        if ($msRes && $msRes->num_rows > 0) {
            $ms = $msRes->fetch_assoc();
            $maritalStatusName = $ms['name'];
        }
    }

    // Education
    $educationName = "";
    if (!empty($row['educationId'])) {
        $eduQuery = $conn->prepare("SELECT name FROM education WHERE id = ?");
        $eduQuery->bind_param("i", $row['educationId']);
        $eduQuery->execute();
        $eduRes = $eduQuery->get_result();
        if ($eduRes && $eduRes->num_rows > 0) {
            $edu = $eduRes->fetch_assoc();
            $educationName = $edu['name'];
        }
    }

    // Country
    $countryName = "";
    if (!empty($row['addressId'])) {
        $addrQuery = $conn->prepare("SELECT countryId FROM addresses WHERE id = ?");
        $addrQuery->bind_param("i", $row['addressId']);
        $addrQuery->execute();
        $addrRes = $addrQuery->get_result();
        if ($addrRes && $addrRes->num_rows > 0) {
            $addr = $addrRes->fetch_assoc();
            $countryId = $addr['countryId'];
            if (!empty($countryId)) {
                $countryQuery = $conn->prepare("SELECT name FROM countries WHERE id = ?");
                $countryQuery->bind_param("i", $countryId);
                $countryQuery->execute();
                $countryRes = $countryQuery->get_result();
                if ($countryRes && $countryRes->num_rows > 0) {
                    $country = $countryRes->fetch_assoc();
                    $countryName = $country['name'];
                }
            }
        }
    }

    // Profile picture
    $profilePicBase = "https://digitallami.com/Api2/";
    $profilePicture = "";
    $picQuery = $conn->prepare("SELECT profile_picture FROM users WHERE id = ?");
    $picQuery->bind_param("i", $row['id']);
    $picQuery->execute();
    $picRes = $picQuery->get_result();
    if ($picRes && $picRes->num_rows > 0) {
        $picRow = $picRes->fetch_assoc();
        $rawPic = $picRow['profile_picture'] ?? '';
        if (!empty($rawPic)) {
            $profilePicture = (strpos($rawPic, 'http') === 0) ? $rawPic : $profilePicBase . $rawPic;
        }
    }

    $responseData[] = [
        "id" => intval($row['id']),
        "memberid" => $row['memberid'],
        "first_name" => $row['firstName'],
        "last_name" => $row['lastName'],
        "matching_percentage" => $matchPercent,
        "is_paid" => $is_paid,
        "is_online" => intval($row['isOnline']),
        "gender" => $row['gender'],
        "occupation" => $occupation,
        "age" => $age,
        "education" => $educationName,
        "marital_status" => $maritalStatusName,
        "country" => $countryName,
        "profile_picture" => $profilePicture
    ];
}

/* ----------------------------------------------------------
   Final Output
---------------------------------------------------------- */
echo json_encode([
    "status" => "success",
    "message" => "Matched profiles fetched successfully.",
    "data" => $responseData
], JSON_PRETTY_PRINT);

$conn->close();
?>
