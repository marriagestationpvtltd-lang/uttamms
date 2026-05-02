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

$stmt = $conn->prepare("DELETE FROM blocks WHERE blocker_id = ? AND blocked_id = ?");
$stmt->bind_param("ii", $myId, $userId);

if ($stmt->execute()) {
    echo json_encode(["status" => "success", "message" => "User unblocked"]);
} else {
    echo json_encode(["status" => "error", "message" => "Failed to unblock user"]);
}

$stmt->close();
$conn->close();
?>