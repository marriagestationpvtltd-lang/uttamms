<?php
header('Content-Type: application/json');

// Database connection
$host = "localhost";
$db_name = "ms";
$username = "ms";
$password = "ms";

$conn = new mysqli($host, $username, $password, $db_name);
if ($conn->connect_error) {
    echo json_encode(['status' => 'error', 'message' => 'Database connection failed']);
    exit;
}

// Base URL for profile pictures
$imageurl = 'https://digitallami.com/Api2/';

// Logged-in user
$user_id = isset($_GET['user_id']) ? intval($_GET['user_id']) : 0;
if ($user_id <= 0) {
    echo json_encode(['status' => 'error', 'message' => 'Invalid user_id']);
    exit;
}

/* ================= DELETE LIKE ================= */
if (isset($_GET['action']) && $_GET['action'] === 'delete') {
    $receiver_id = intval($_GET['receiver_id'] ?? 0);

    if ($receiver_id <= 0) {
        echo json_encode(['status' => 'error', 'message' => 'Invalid receiver_id']);
        exit;
    }

    $stmt = $conn->prepare("DELETE FROM likes WHERE sender_id = ? AND receiver_id = ?");
    $stmt->bind_param("ii", $user_id, $receiver_id);

    if ($stmt->execute()) {
        echo json_encode(['status' => 'success', 'message' => 'Like deleted successfully']);
    } else {
        echo json_encode(['status' => 'error', 'message' => 'Failed to delete like']);
    }

    $stmt->close();
    $conn->close();
    exit;
}

/* ================= FETCH LIKED USERS ================= */
$stmt = $conn->prepare("SELECT receiver_id FROM likes WHERE sender_id = ?");
$stmt->bind_param("i", $user_id);
$stmt->execute();
$res = $stmt->get_result();

$receiver_ids = [];
while ($row = $res->fetch_assoc()) {
    $receiver_ids[] = $row['receiver_id'];
}
$stmt->close();

if (empty($receiver_ids)) {
    echo json_encode(['status' => 'success', 'data' => []]);
    exit;
}

$ids = implode(',', array_map('intval', $receiver_ids));

/* ================= FETCH USERS + PRIVACY ================= */
$sql = "
    SELECT id, firstName, lastName, profile_picture, isVerified, privacy
    FROM users
    WHERE id IN ($ids)
";
$result = $conn->query($sql);

$users_data = [];

while ($user = $result->fetch_assoc()) {

    $uid = (int)$user['id'];

    /* -------- PHOTO REQUEST -------- */
    $photo_request = "not sent";

    $stmtPhoto = $conn->prepare("
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
    ");
    $stmtPhoto->bind_param("iiii", $user_id, $uid, $uid, $user_id);
    $stmtPhoto->execute();
    $resPhoto = $stmtPhoto->get_result();

    if ($row = $resPhoto->fetch_assoc()) {
        $photo_request = ($row['status'] === 'accepted') ? 'accepted' : 'pending';
    }
    $stmtPhoto->close();

    /* -------- CITY -------- */
    $stmtAddr = $conn->prepare("SELECT city FROM permanent_address WHERE userid = ?");
    $stmtAddr->bind_param("i", $uid);
    $stmtAddr->execute();
    $addr = $stmtAddr->get_result()->fetch_assoc();
    $stmtAddr->close();

    /* -------- DESIGNATION -------- */
    $stmtEdu = $conn->prepare("SELECT designation FROM educationcareer WHERE userid = ?");
    $stmtEdu->bind_param("i", $uid);
    $stmtEdu->execute();
    $edu = $stmtEdu->get_result()->fetch_assoc();
    $stmtEdu->close();

    /* -------- FINAL USER OBJECT -------- */
    $users_data[] = [
        "userid" => $uid,
        "firstName" => "MS:" . $uid,
        "lastName" => $user['lastName'],
        "isVerified" => (int)$user['isVerified'],
        "privacy" => (string)$user['privacy'],
        "profile_picture" => $imageurl . ($user['profile_picture'] ?? 'default.jpg'),
        "city" => $addr['city'] ?? null,
        "designation" => $edu['designation'] ?? null,
        "photo_request" => $photo_request            // ✅ ADDED
    ];
}

echo json_encode([
    "status" => "success",
    "data" => $users_data
]);

$conn->close();
?>
