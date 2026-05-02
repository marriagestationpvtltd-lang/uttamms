<?php
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');

$conn = new mysqli("localhost", "root", "", "ms");

$input = json_decode(file_get_contents('php://input'), true);
$myId = intval($input['my_id'] ?? 0);
$userId = intval($input['user_id'] ?? 0);

if ($myId <= 0 || $userId <= 0) {
    echo json_encode(["status" => "error", "message" => "Invalid user ID"]);
    exit;
}

if ($myId === $userId) {
    echo json_encode(["status" => "error", "message" => "You cannot block yourself"]);
    exit;
}

// Check if already blocked
$check = $conn->prepare("SELECT id FROM blocks WHERE blocker_id = ? AND blocked_id = ?");
$check->bind_param("ii", $myId, $userId);
$check->execute();
$result = $check->get_result();

if ($result->num_rows > 0) {
    echo json_encode(["status" => "error", "message" => "User already blocked"]);
    exit;
}

$stmt = $conn->prepare("INSERT INTO blocks (blocker_id, blocked_id, created_at) VALUES (?, ?, NOW())");
$stmt->bind_param("ii", $myId, $userId);

if ($stmt->execute()) {
    // Facebook-like behavior: hide/remove conversation data after block.
    $roomId = min($myId, $userId) . '_' . max($myId, $userId);
    try {
        $conn->begin_transaction();

        $q1 = $conn->prepare("DELETE FROM chat_unread_counts WHERE chat_room_id = ?");
        $q1->bind_param("s", $roomId);
        $q1->execute();

        $q2 = $conn->prepare("DELETE FROM chat_messages WHERE chat_room_id = ?");
        $q2->bind_param("s", $roomId);
        $q2->execute();

        $q3 = $conn->prepare("DELETE FROM chat_rooms WHERE id = ?");
        $q3->bind_param("s", $roomId);
        $q3->execute();

        $conn->commit();
    } catch (Throwable $e) {
        $conn->rollback();
        error_log('block_user.php cleanup error: ' . $e->getMessage());
    }

    echo json_encode([
        "status" => "success",
        "message" => "User blocked",
        "conversation_hidden" => true,
    ]);
} else {
    echo json_encode(["status" => "error", "message" => "Failed to block user"]);
}

$stmt->close();
$conn->close();
?>