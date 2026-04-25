<?php
header('Content-Type: application/json');
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: GET, POST, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type, Authorization");

include 'db_connect.php';

// ✅ Set Nepal timezone
date_default_timezone_set('Asia/Kathmandu');
$conn->query("SET time_zone = '+05:45'");

// ✅ Base URL for images
$base_url = "https://digitallami.com/Api2/";

/* ----------------------------------------------------------
   STEP 0: Get user_id from POST
---------------------------------------------------------- */
$postData = json_decode(file_get_contents("php://input"), true);

if (!isset($postData['user_id'])) {
    echo json_encode(["status" => "error", "message" => "user_id is required"]);
    exit;
}

$user_id = intval($postData['user_id']);

// Pagination parameters
$page     = max(1, intval($postData['page']     ?? 1));
$per_page = min(100, max(1, intval($postData['per_page'] ?? 20)));
$offset   = ($page - 1) * $per_page;

// Filter and search parameters
$filter_type = isset($postData['filter_type']) ? trim($postData['filter_type']) : 'all';
$search      = isset($postData['search'])      ? trim($postData['search'])      : '';

/* ----------------------------------------------------------
   STEP 1: Get current user details and gender
---------------------------------------------------------- */
$userQuery = $conn->prepare("
    SELECT u.id, u.gender, u.firstName, u.lastName,
           upd.birthDate, upd.maritalStatusId, upd.religionId, 
           upd.communityId, upd.educationId, upd.annualIncomeId,
           upd.heightId, upd.occupationId
    FROM users u
    JOIN userpersonaldetail upd ON u.id = upd.userId
    WHERE u.id = ?
");
$userQuery->bind_param("i", $user_id);
$userQuery->execute();
$userResult = $userQuery->get_result();

if ($userResult->num_rows === 0) {
    echo json_encode(["status" => "error", "message" => "User not found"]);
    exit;
}

$user = $userResult->fetch_assoc();
$oppositeGender = ($user['gender'] === 'Male') ? 'Female' : 'Male';

// Calculate current user's age
$userAge = null;
if (!empty($user['birthDate'])) {
    $birth = new DateTime($user['birthDate']);
    $userAge = (new DateTime())->diff($birth)->y;
}

/* ----------------------------------------------------------
   STEP 2: Get partner preferences
---------------------------------------------------------- */
$prefQuery = $conn->prepare("SELECT * FROM userpartnerpreferences WHERE userId = ?");
$prefQuery->bind_param("i", $user_id);
$prefQuery->execute();
$prefResult = $prefQuery->get_result();

$hasPreference = false;
$pref = [];

if ($prefResult->num_rows > 0) {
    $pref = $prefResult->fetch_assoc();
    $hasPreference = true;
}

/* ----------------------------------------------------------
   STEP 3: Build WHERE clause based on filter_type and search
---------------------------------------------------------- */
$whereParts = ["u.gender = ? AND u.id != ?"];
$bindTypes  = "si";
$bindValues = [$oppositeGender, $user_id];

if ($filter_type === 'matched') {
    // Only users who have an accepted proposal with the current user
    $whereParts[] = "u.id IN (
        SELECT CASE WHEN p.sender_id = ? THEN p.receiver_id ELSE p.sender_id END
        FROM proposals p
        WHERE (p.sender_id = ? OR p.receiver_id = ?) AND p.status = 'accepted'
    )";
    $bindTypes  .= "iii";
    $bindValues[] = $user_id;
    $bindValues[] = $user_id;
    $bindValues[] = $user_id;
}

if ($search !== '') {
    $escapedSearch = '%' . str_replace(['\\', '%', '_'], ['\\\\', '\\%', '\\_'], $search) . '%';
    $whereParts[] = "(u.firstName LIKE ? OR u.lastName LIKE ? OR upd.memberid LIKE ?)";
    $bindTypes  .= "sss";
    $bindValues[] = $escapedSearch;
    $bindValues[] = $escapedSearch;
    $bindValues[] = $escapedSearch;
}

$whereClause = 'WHERE ' . implode(' AND ', $whereParts);

/* ----------------------------------------------------------
   STEP 4: Count total matching records
---------------------------------------------------------- */
$countSql = "
    SELECT COUNT(DISTINCT u.id)
    FROM users u
    JOIN userpersonaldetail upd ON u.id = upd.userId
    $whereClause
";
$countStmt = $conn->prepare($countSql);
if (!empty($bindValues)) {
    $countStmt->bind_param($bindTypes, ...$bindValues);
}
$countStmt->execute();
$countStmt->bind_result($total_count);
$countStmt->fetch();
$countStmt->close();

/* ----------------------------------------------------------
   STEP 5: Get paginated opposite gender users
---------------------------------------------------------- */
$matchQuery = $conn->prepare("
    SELECT 
        u.id, u.firstName, u.lastName, u.gender, u.isOnline, u.profile_picture,
        upd.memberid, upd.occupationId, upd.birthDate,
        upd.heightId, upd.maritalStatusId, upd.religionId,
        upd.communityId, upd.educationId, upd.annualIncomeId,
        upd.addressId
    FROM users u
    JOIN userpersonaldetail upd ON u.id = upd.userId
    $whereClause
    ORDER BY u.id DESC
    LIMIT ? OFFSET ?
");
$paginatedTypes  = $bindTypes . "ii";
$paginatedValues = array_merge($bindValues, [$per_page, $offset]);
$matchQuery->bind_param($paginatedTypes, ...$paginatedValues);
$matchQuery->execute();
$matches = $matchQuery->get_result();

/* ----------------------------------------------------------
   STEP 6: Calculate match percentage for each result
---------------------------------------------------------- */
$responseData = [];

while ($row = $matches->fetch_assoc()) {
    $matchedFactors = [];
    $totalFactors = [];
    
    // Calculate match percentage
    $matchPercent = 0;
    
    // 1. AGE MATCH (20% weight)
    if ($hasPreference && !empty($pref['pFromAge']) && !empty($pref['pToAge']) && !empty($row['birthDate'])) {
        $birth = new DateTime($row['birthDate']);
        $age = (new DateTime())->diff($birth)->y;
        
        if ($age >= $pref['pFromAge'] && $age <= $pref['pToAge']) {
            $matchedFactors[] = 20;
        }
        $totalFactors[] = 20;
    } elseif ($hasPreference && !empty($pref['pFromAge']) && !empty($pref['pToAge'])) {
        $totalFactors[] = 20; // User has age preference but profile has no age
    }
    
    // 2. HEIGHT MATCH (15% weight)
    if ($hasPreference && !empty($pref['pFromHeight']) && !empty($pref['pToHeight']) && !empty($row['heightId'])) {
        if ($row['heightId'] >= $pref['pFromHeight'] && $row['heightId'] <= $pref['pToHeight']) {
            $matchedFactors[] = 15;
        }
        $totalFactors[] = 15;
    } elseif ($hasPreference && (!empty($pref['pFromHeight']) || !empty($pref['pToHeight']))) {
        $totalFactors[] = 15;
    }
    
    // 3. MARITAL STATUS MATCH (15% weight)
    if ($hasPreference && !empty($pref['pMaritalStatusId']) && !empty($row['maritalStatusId'])) {
        if ($row['maritalStatusId'] == $pref['pMaritalStatusId']) {
            $matchedFactors[] = 15;
        }
        $totalFactors[] = 15;
    } elseif ($hasPreference && !empty($pref['pMaritalStatusId'])) {
        $totalFactors[] = 15;
    }
    
    // 4. RELIGION MATCH (15% weight)
    if ($hasPreference && !empty($pref['pReligionId']) && !empty($row['religionId'])) {
        if ($row['religionId'] == $pref['pReligionId']) {
            $matchedFactors[] = 15;
        }
        $totalFactors[] = 15;
    } elseif ($hasPreference && !empty($pref['pReligionId'])) {
        $totalFactors[] = 15;
    }
    
    // 5. COMMUNITY MATCH (10% weight)
    if ($hasPreference && !empty($pref['pCommunityId']) && !empty($row['communityId'])) {
        if ($row['communityId'] == $pref['pCommunityId']) {
            $matchedFactors[] = 10;
        }
        $totalFactors[] = 10;
    } elseif ($hasPreference && !empty($pref['pCommunityId'])) {
        $totalFactors[] = 10;
    }
    
    // 6. EDUCATION MATCH (10% weight)
    if ($hasPreference && !empty($pref['pEducationTypeId']) && !empty($row['educationId'])) {
        if ($row['educationId'] == $pref['pEducationTypeId']) {
            $matchedFactors[] = 10;
        }
        $totalFactors[] = 10;
    } elseif ($hasPreference && !empty($pref['pEducationTypeId'])) {
        $totalFactors[] = 10;
    }
    
    // 7. INCOME MATCH (10% weight)
    if ($hasPreference && !empty($pref['pAnnualIncomeId']) && !empty($row['annualIncomeId'])) {
        if ($row['annualIncomeId'] == $pref['pAnnualIncomeId']) {
            $matchedFactors[] = 10;
        }
        $totalFactors[] = 10;
    } elseif ($hasPreference && !empty($pref['pAnnualIncomeId'])) {
        $totalFactors[] = 10;
    }
    
    // 8. OCCUPATION SIMILARITY (5% weight) - if occupations are similar
    if ($hasPreference && !empty($pref['pOccupationId']) && !empty($row['occupationId'])) {
        if ($row['occupationId'] == $pref['pOccupationId']) {
            $matchedFactors[] = 5;
        }
        $totalFactors[] = 5;
    }
    
    // Calculate total match percentage
    $totalMatched = array_sum($matchedFactors);
    $totalPossible = array_sum($totalFactors);
    
    if ($totalPossible > 0) {
        $matchPercent = round(($totalMatched / $totalPossible) * 100);
    } else {
        // If no preferences set, calculate based on basic compatibility
        $matchPercent = 50; // Default 50% if no preferences
    }
    
    // Age calculation for display
    $age = null;
    if (!empty($row['birthDate'])) {
        $birth = new DateTime($row['birthDate']);
        $age = (new DateTime())->diff($birth)->y;
    }
    
    /* -------- Paid User -------- */
    $paidQuery = $conn->prepare("SELECT netAmount FROM userpackage WHERE userId = ?");
    $paidQuery->bind_param("i", $row['id']);
    $paidQuery->execute();
    $paidRes = $paidQuery->get_result();
    $is_paid = ($paidRes->num_rows > 0 && $paidRes->fetch_assoc()['netAmount'] > 0) ? true : false;
    
    /* -------- Profile Picture -------- */
    $profile_picture = "";
    if (!empty($row['profile_picture'])) {
        if (strpos($row['profile_picture'], 'http') === 0) {
            $profile_picture = $row['profile_picture'];
        } else {
            $profile_picture = $base_url . $row['profile_picture'];
        }
    }
    
    /* -------- Occupation -------- */
    $occupation = "";
    if (!empty($row['occupationId'])) {
        $q = $conn->prepare("SELECT name FROM occupation WHERE id=?");
        $q->bind_param("i", $row['occupationId']);
        $q->execute();
        $r = $q->get_result();
        if ($r->num_rows) $occupation = $r->fetch_assoc()['name'];
    }
    
    /* -------- Education -------- */
    $education = "";
    if (!empty($row['educationId'])) {
        $q = $conn->prepare("SELECT name FROM education WHERE id=?");
        $q->bind_param("i", $row['educationId']);
        $q->execute();
        $r = $q->get_result();
        if ($r->num_rows) $education = $r->fetch_assoc()['name'];
    }
    
    /* -------- Marital Status -------- */
    $marital = "";
    if (!empty($row['maritalStatusId'])) {
        $q = $conn->prepare("SELECT name FROM maritalstatus WHERE id=?");
        $q->bind_param("i", $row['maritalStatusId']);
        $q->execute();
        $r = $q->get_result();
        if ($r->num_rows) $marital = $r->fetch_assoc()['name'];
    }
    
    /* -------- Country -------- */
    $country = "";
    if (!empty($row['addressId'])) {
        $q = $conn->prepare("
            SELECT c.name FROM addresses a
            JOIN countries c ON a.countryId = c.id
            WHERE a.id=?
        ");
        $q->bind_param("i", $row['addressId']);
        $q->execute();
        $r = $q->get_result();
        if ($r->num_rows) $country = $r->fetch_assoc()['name'];
    }
    
    /* -------- Online Status -------- */
    $is_online = false;
    if (isset($row['isOnline'])) {
        $is_online = (bool)$row['isOnline'];
    }
    
    $responseData[] = [
        "id" => (int)$row['id'],
        "member_id" => $row['memberid'],
        "first_name" => $row['firstName'],
        "last_name" => $row['lastName'],
        "full_name" => trim($row['firstName'] . ' ' . $row['lastName']),
        "gender" => $row['gender'],
        "age" => $age,
        "profile_picture" => $profile_picture,
        "occupation" => $occupation,
        "education" => $education,
        "marital_status" => $marital,
        "country" => $country,
        "matching_percentage" => $matchPercent,
        "is_paid" => $is_paid,
        "is_online" => $is_online,
        "has_preference" => $hasPreference
    ];
}

/* ----------------------------------------------------------
   FINAL OUTPUT
---------------------------------------------------------- */
echo json_encode([
    "status" => "success",
    "message" => "Matched profiles fetched successfully",
    "data" => $responseData,
    "total" => (int)$total_count,
    "page" => $page,
    "per_page" => $per_page,
    "total_pages" => (int)ceil($total_count / $per_page),
], JSON_PRETTY_PRINT);

$conn->close();
?>