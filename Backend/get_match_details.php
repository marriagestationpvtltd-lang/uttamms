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
   STEP 0: Get user_id from GET request
---------------------------------------------------------- */
$user_id = isset($_GET['user_id']) ? intval($_GET['user_id']) : 0;

if ($user_id == 0) {
    echo json_encode(["status" => "error", "message" => "user_id is required"]);
    exit;
}

/* ----------------------------------------------------------
   STEP 1: Get user details
---------------------------------------------------------- */
$userQuery = $conn->prepare("
    SELECT u.id, u.firstName, u.lastName, u.gender, u.profile_picture,
           upd.birthDate, upd.memberid, upd.occupationId, upd.educationId,
           upd.maritalStatusId, upd.religionId, upd.communityId
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

// Calculate user age
$age = null;
if (!empty($user['birthDate'])) {
    $birth = new DateTime($user['birthDate']);
    $age = (new DateTime())->diff($birth)->y;
}

// Get profile picture URL
$profile_picture = "";
if (!empty($user['profile_picture'])) {
    if (strpos($user['profile_picture'], 'http') === 0) {
        $profile_picture = $user['profile_picture'];
    } else {
        $profile_picture = $base_url . $user['profile_picture'];
    }
}

/* ----------------------------------------------------------
   STEP 2: Get matched users (from matches table) OR fallback to opposite gender
   matches table columns: userId1, userId2 (not user_id/matched_id)
---------------------------------------------------------- */

// First try to get users from matches table (accepted matches)
$matchQuery = $conn->prepare("
    SELECT 
        u.id, u.firstName, u.lastName, u.profile_picture, u.isOnline,
        upd.memberid, upd.birthDate, upd.occupationId
    FROM users u
    JOIN userpersonaldetail upd ON u.id = upd.userId
    WHERE u.id IN (
        SELECT userId2 FROM matches WHERE userId1 = ? AND status = 'accepted'
        UNION
        SELECT userId1 FROM matches WHERE userId2 = ? AND status = 'accepted'
    )
    LIMIT 50
");
$matchQuery->bind_param("ii", $user_id, $user_id);
$matchQuery->execute();
$matchResult = $matchQuery->get_result();

$mutualMatches = [];
while ($match = $matchResult->fetch_assoc()) {
    $matchAge = null;
    if (!empty($match['birthDate'])) {
        $birth = new DateTime($match['birthDate']);
        $matchAge = (new DateTime())->diff($birth)->y;
    }
    $matchPicture = "";
    if (!empty($match['profile_picture'])) {
        $matchPicture = (strpos($match['profile_picture'], 'http') === 0)
            ? $match['profile_picture']
            : $base_url . $match['profile_picture'];
    }
    $occupation = "";
    if (!empty($match['occupationId'])) {
        $occQuery = $conn->prepare("SELECT name FROM occupation WHERE id=?");
        $occQuery->bind_param("i", $match['occupationId']);
        $occQuery->execute();
        $occResult = $occQuery->get_result();
        if ($occResult->num_rows) $occupation = $occResult->fetch_assoc()['name'];
    }
    $isOnline = intval($match['isOnline'] ?? 0);
    $mutualMatches[] = [
        'id'              => intval($match['id']),
        'name'            => trim($match['firstName'] . ' ' . $match['lastName']),
        'member_id'       => $match['memberid'],
        'profile_picture' => $matchPicture,
        'age'             => $matchAge,
        'occupation'      => $occupation,
        'is_online'       => $isOnline,
        'percentage'      => 75
    ];
}

// Fallback: if no accepted matches, show all opposite-gender users
if (empty($mutualMatches)) {
    $oppositeGender = ($user['gender'] === 'Male') ? 'Female' : 'Male';
    $fallbackQuery = $conn->prepare("
        SELECT 
            u.id, u.firstName, u.lastName, u.profile_picture, u.isOnline,
            upd.memberid, upd.birthDate, upd.occupationId
        FROM users u
        JOIN userpersonaldetail upd ON u.id = upd.userId
        WHERE u.gender = ? AND u.id != ?
        ORDER BY u.isOnline DESC, u.id DESC
        LIMIT 50
    ");
    $fallbackQuery->bind_param("si", $oppositeGender, $user_id);
    $fallbackQuery->execute();
    $fallbackResult = $fallbackQuery->get_result();

    while ($match = $fallbackResult->fetch_assoc()) {
        $matchAge = null;
        if (!empty($match['birthDate'])) {
            $birth = new DateTime($match['birthDate']);
            $matchAge = (new DateTime())->diff($birth)->y;
        }
        $matchPicture = "";
        if (!empty($match['profile_picture'])) {
            $matchPicture = (strpos($match['profile_picture'], 'http') === 0)
                ? $match['profile_picture']
                : $base_url . $match['profile_picture'];
        }
        $occupation = "";
        if (!empty($match['occupationId'])) {
            $occQuery = $conn->prepare("SELECT name FROM occupation WHERE id=?");
            $occQuery->bind_param("i", $match['occupationId']);
            $occQuery->execute();
            $occResult = $occQuery->get_result();
            if ($occResult->num_rows) $occupation = $occResult->fetch_assoc()['name'];
        }

        // Check is_paid
        $isPaid = 0;
        $paidQ = $conn->prepare("SELECT netAmount FROM userpackage WHERE userId = ? LIMIT 1");
        $paidQ->bind_param("i", $match['id']);
        $paidQ->execute();
        $paidRes = $paidQ->get_result();
        if ($paidRes && $paidRes->num_rows > 0) {
            $paidRow = $paidRes->fetch_assoc();
            $isPaid = (floatval($paidRow['netAmount']) > 0) ? 1 : 0;
        }

        $isOnline = intval($match['isOnline'] ?? 0);
        $mutualMatches[] = [
            'id'              => intval($match['id']),
            'name'            => trim($match['firstName'] . ' ' . $match['lastName']),
            'member_id'       => $match['memberid'],
            'profile_picture' => $matchPicture,
            'age'             => $matchAge,
            'occupation'      => $occupation,
            'is_online'       => $isOnline,
            'is_paid'         => $isPaid,
            'percentage'      => 0
        ];
    }
}

/* ----------------------------------------------------------
   STEP 3: Get common interests (simplified - based on matching criteria)
---------------------------------------------------------- */
$commonInterests = [];

// Check for matching preferences (you can expand this based on your data)
$prefQuery = $conn->prepare("SELECT * FROM userpartnerpreferences WHERE userId = ?");
$prefQuery->bind_param("i", $user_id);
$prefQuery->execute();
$prefResult = $prefQuery->get_result();

if ($prefResult->num_rows > 0) {
    $pref = $prefResult->fetch_assoc();
    
    // Add interests based on preferences
    if (!empty($pref['pReligionId'])) {
        $relQuery = $conn->prepare("SELECT name FROM religion WHERE id=?");
        $relQuery->bind_param("i", $pref['pReligionId']);
        $relQuery->execute();
        $relResult = $relQuery->get_result();
        if ($relResult->num_rows) {
            $commonInterests[] = $relResult->fetch_assoc()['name'];
        }
    }
    
    if (!empty($pref['pCommunityId'])) {
        $comQuery = $conn->prepare("SELECT name FROM community WHERE id=?");
        $comQuery->bind_param("i", $pref['pCommunityId']);
        $comQuery->execute();
        $comResult = $comQuery->get_result();
        if ($comResult->num_rows) {
            $commonInterests[] = $comResult->fetch_assoc()['name'];
        }
    }
    
    if (!empty($pref['pEducationTypeId'])) {
        $eduQuery = $conn->prepare("SELECT name FROM education WHERE id=?");
        $eduQuery->bind_param("i", $pref['pEducationTypeId']);
        $eduQuery->execute();
        $eduResult = $eduQuery->get_result();
        if ($eduResult->num_rows) {
            $commonInterests[] = $eduResult->fetch_assoc()['name'];
        }
    }
}

// Add default interests if none found
if (empty($commonInterests)) {
    $commonInterests = ['Finding meaningful connections', 'Building relationships'];
}

/* ----------------------------------------------------------
   STEP 4: Calculate match percentage (simplified)
---------------------------------------------------------- */
$matchPercentage = 75; // Default percentage
// You can implement more complex matching logic here

/* ----------------------------------------------------------
   STEP 5: Return response
---------------------------------------------------------- */
echo json_encode([
    "status" => "success",
    "message" => "Match details fetched successfully",
    "match_details" => [
        "percentage" => $matchPercentage,
        "commonInterests" => $commonInterests,
        "age" => $age,
        "member_id" => $user['memberid'],
        "name" => trim($user['firstName'] . ' ' . $user['lastName']),
        "profile_picture" => $profile_picture,
        "gender" => $user['gender']
    ],
    "mutual_matches" => $mutualMatches
], JSON_PRETTY_PRINT);

$conn->close();
?>