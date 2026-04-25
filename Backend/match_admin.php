<?php
header('Content-Type: application/json');
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: GET, POST, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type, Authorization");

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    exit(0);
}

include 'db_connect.php';

date_default_timezone_set('Asia/Kathmandu');
$conn->query("SET time_zone = '+05:45'");

$base_url = "https://digitallami.com/Api2/";

/* ----------------------------------------------------------
   STEP 0: Parse POST body
---------------------------------------------------------- */
$postData = json_decode(file_get_contents("php://input"), true);

if (!isset($postData['user_id'])) {
    echo json_encode(["status" => "error", "message" => "user_id is required"]);
    exit;
}

$user_id    = intval($postData['user_id']);
$page       = max(1, intval($postData['page']     ?? 1));
$per_page   = max(1, min(100, intval($postData['per_page'] ?? 20)));
$offset     = ($page - 1) * $per_page;
$search     = trim($postData['search']      ?? '');
$filterType = trim($postData['filter_type'] ?? 'all'); // 'matched' | 'all'

/* ----------------------------------------------------------
   STEP 1: Get current user details and gender
---------------------------------------------------------- */
$userQuery = $conn->prepare("
    SELECT u.id, u.gender,
           upd.birthDate, upd.maritalStatusId, upd.religionId,
           upd.communityId, upd.educationId, upd.annualIncomeId,
           upd.heightId, upd.occupationId
    FROM   users u
    JOIN   userpersonaldetail upd ON u.id = upd.userId
    WHERE  u.id = ?
");
$userQuery->bind_param("i", $user_id);
$userQuery->execute();
$userResult = $userQuery->get_result();

if ($userResult->num_rows === 0) {
    // Try without personal detail join (user might not have preferences yet)
    $userQuery2 = $conn->prepare("SELECT id, gender FROM users WHERE id = ?");
    $userQuery2->bind_param("i", $user_id);
    $userQuery2->execute();
    $userResult2 = $userQuery2->get_result();
    if ($userResult2->num_rows === 0) {
        echo json_encode(["status" => "error", "message" => "User not found"]);
        exit;
    }
    $user = $userResult2->fetch_assoc();
    $user['birthDate']        = null;
    $user['maritalStatusId']  = null;
    $user['religionId']       = null;
    $user['communityId']      = null;
    $user['educationId']      = null;
    $user['annualIncomeId']   = null;
    $user['heightId']         = null;
    $user['occupationId']     = null;
} else {
    $user = $userResult->fetch_assoc();
}

$oppositeGender = ($user['gender'] === 'Male') ? 'Female' : 'Male';

/* ----------------------------------------------------------
   STEP 2: Get partner preferences
---------------------------------------------------------- */
$hasPreference = false;
$pref          = [];
$prefQuery     = $conn->prepare("SELECT * FROM userpartnerpreferences WHERE userId = ?");
$prefQuery->bind_param("i", $user_id);
$prefQuery->execute();
$prefResult = $prefQuery->get_result();
if ($prefResult->num_rows > 0) {
    $pref          = $prefResult->fetch_assoc();
    $hasPreference = true;
}

/* ----------------------------------------------------------
   STEP 3: Build the main query with JOINs (replaces N+1 lookups)
   — occupation, education, marital status, country, paid status
     are all resolved in a single SQL round-trip.
---------------------------------------------------------- */
$whereClauses = ["u.gender = ?", "u.id != ?"];
$bindTypes    = "si";
$bindParams   = [$oppositeGender, $user_id];

if ($search !== '') {
    $like           = '%' . $search . '%';
    $whereClauses[] = "(u.firstName LIKE ? OR u.lastName LIKE ? OR CONCAT(u.firstName,' ',u.lastName) LIKE ?)";
    $bindTypes     .= 'sss';
    $bindParams     = array_merge($bindParams, [$like, $like, $like]);
}

$whereSQL = 'WHERE ' . implode(' AND ', $whereClauses);

// Count total for pagination
$countSQL  = "
    SELECT COUNT(*) AS total
    FROM   users u
    JOIN   userpersonaldetail upd ON u.id = upd.userId
    $whereSQL
";
$countStmt = $conn->prepare($countSQL);
$countStmt->bind_param($bindTypes, ...$bindParams);
$countStmt->execute();
$totalCount = intval($countStmt->get_result()->fetch_assoc()['total'] ?? 0);

// Main JOIN query — all lookup tables resolved in one pass
$mainSQL = "
    SELECT
        u.id, u.firstName, u.lastName, u.gender,
        u.isOnline, u.profile_picture,
        upd.memberid, upd.birthDate,
        upd.heightId, upd.maritalStatusId, upd.religionId,
        upd.communityId, upd.educationId, upd.annualIncomeId,
        upd.occupationId, upd.addressId,
        occ.name  AS occupation_name,
        edu.name  AS education_name,
        ms.name   AS marital_status_name,
        co.name   AS country_name,
        CASE WHEN MAX(up.netAmount) > 0 THEN 1 ELSE 0 END AS is_paid_int
    FROM   users u
    JOIN   userpersonaldetail upd ON u.id = upd.userId
    LEFT   JOIN occupation   occ  ON upd.occupationId   = occ.id
    LEFT   JOIN education    edu  ON upd.educationId    = edu.id
    LEFT   JOIN maritalstatus ms  ON upd.maritalStatusId = ms.id
    LEFT   JOIN addresses    addr ON upd.addressId      = addr.id
    LEFT   JOIN countries    co   ON addr.countryId     = co.id
    LEFT   JOIN userpackage  up   ON u.id               = up.userId
    $whereSQL
    GROUP  BY u.id
    ORDER  BY u.isOnline DESC, u.id ASC
    LIMIT  ? OFFSET ?
";
$listTypes  = $bindTypes . 'ii';
$listParams = array_merge($bindParams, [$per_page, $offset]);

$stmt = $conn->prepare($mainSQL);
$stmt->bind_param($listTypes, ...$listParams);
$stmt->execute();
$matches = $stmt->get_result();

/* ----------------------------------------------------------
   STEP 4: Calculate match percentage and build response
   (pure PHP — no further DB queries needed)
---------------------------------------------------------- */
$responseData = [];

while ($row = $matches->fetch_assoc()) {
    $matchedWeight = 0;
    $totalWeight   = 0;

    // Age (20%)
    $age = null;
    if (!empty($row['birthDate'])) {
        $birth = new DateTime($row['birthDate']);
        $age   = (new DateTime())->diff($birth)->y;
        if ($hasPreference && !empty($pref['pFromAge']) && !empty($pref['pToAge'])) {
            $totalWeight += 20;
            if ($age >= $pref['pFromAge'] && $age <= $pref['pToAge']) {
                $matchedWeight += 20;
            }
        }
    } elseif ($hasPreference && !empty($pref['pFromAge']) && !empty($pref['pToAge'])) {
        $totalWeight += 20;
    }

    // Height (15%)
    if ($hasPreference && !empty($pref['pFromHeight']) && !empty($pref['pToHeight'])) {
        $totalWeight += 15;
        if (!empty($row['heightId']) &&
            $row['heightId'] >= $pref['pFromHeight'] &&
            $row['heightId'] <= $pref['pToHeight']) {
            $matchedWeight += 15;
        }
    }

    // Marital status (15%)
    if ($hasPreference && !empty($pref['pMaritalStatusId'])) {
        $totalWeight += 15;
        if (!empty($row['maritalStatusId']) && $row['maritalStatusId'] == $pref['pMaritalStatusId']) {
            $matchedWeight += 15;
        }
    }

    // Religion (15%)
    if ($hasPreference && !empty($pref['pReligionId'])) {
        $totalWeight += 15;
        if (!empty($row['religionId']) && $row['religionId'] == $pref['pReligionId']) {
            $matchedWeight += 15;
        }
    }

    // Community (10%)
    if ($hasPreference && !empty($pref['pCommunityId'])) {
        $totalWeight += 10;
        if (!empty($row['communityId']) && $row['communityId'] == $pref['pCommunityId']) {
            $matchedWeight += 10;
        }
    }

    // Education (10%)
    if ($hasPreference && !empty($pref['pEducationTypeId'])) {
        $totalWeight += 10;
        if (!empty($row['educationId']) && $row['educationId'] == $pref['pEducationTypeId']) {
            $matchedWeight += 10;
        }
    }

    // Income (10%)
    if ($hasPreference && !empty($pref['pAnnualIncomeId'])) {
        $totalWeight += 10;
        if (!empty($row['annualIncomeId']) && $row['annualIncomeId'] == $pref['pAnnualIncomeId']) {
            $matchedWeight += 10;
        }
    }

    // Occupation (5%)
    if ($hasPreference && !empty($pref['pOccupationId'])) {
        $totalWeight += 5;
        if (!empty($row['occupationId']) && $row['occupationId'] == $pref['pOccupationId']) {
            $matchedWeight += 5;
        }
    }

    $matchPercent = ($totalWeight > 0)
        ? round(($matchedWeight / $totalWeight) * 100)
        : 50;

    // Apply filter_type='matched' (only users with >0% match)
    if ($filterType === 'matched' && $hasPreference && $matchPercent === 0) {
        continue;
    }

    // Profile picture
    $profile_picture = '';
    if (!empty($row['profile_picture'])) {
        $profile_picture = (strpos($row['profile_picture'], 'http') === 0)
            ? $row['profile_picture']
            : $base_url . $row['profile_picture'];
    }

    $responseData[] = [
        'id'                 => intval($row['id']),
        'member_id'          => $row['memberid'] ?? '',
        'first_name'         => $row['firstName'] ?? '',
        'last_name'          => $row['lastName']  ?? '',
        'full_name'          => trim(($row['firstName'] ?? '') . ' ' . ($row['lastName'] ?? '')),
        'gender'             => $row['gender']    ?? '',
        'age'                => $age,
        'profile_picture'    => $profile_picture,
        'occupation'         => $row['occupation_name']    ?? '',
        'education'          => $row['education_name']     ?? '',
        'marital_status'     => $row['marital_status_name'] ?? '',
        'country'            => $row['country_name']       ?? '',
        'matching_percentage' => $matchPercent,
        'is_paid'            => (bool)$row['is_paid_int'],
        'is_online'          => (bool)$row['isOnline'],
        'has_preference'     => $hasPreference,
    ];
}

echo json_encode([
    'status'  => 'success',
    'message' => 'Matched profiles fetched successfully',
    'data'    => $responseData,
    'total'   => $totalCount,
    'page'    => $page,
    'per_page' => $per_page,
], JSON_PRETTY_PRINT);

$conn->close();
?>
