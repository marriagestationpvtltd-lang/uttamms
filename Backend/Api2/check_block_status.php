<?php
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');

$conn = new mysqli("localhost", "root", "", "ms");

$input = json_decode(file_get_contents('php://input'), true);
$myId = intval($input['my_id'] ?? 0);
$userId = intval($input['user_id'] ?? 0);

if ($myId <= 0 || $userId <= 0) {
    echo json_encode([
        "status" => "error",
        "is_blocked" => false,
        "is_blocked_by" => false,
        "either_blocked" => false,
    ]);
    exit;
}

$stmt = $conn->prepare(
    "SELECT blocker_id, blocked_id FROM blocks
      WHERE (blocker_id = ? AND blocked_id = ?)
         OR (blocker_id = ? AND blocked_id = ?)
      LIMIT 1"
);
$stmt->bind_param("iiii", $myId, $userId, $userId, $myId);
$stmt->execute();
$result = $stmt->get_result();
$row = $result->fetch_assoc();

$isBlocked = false;
$isBlockedBy = false;
if ($row) {
    $isBlocked = ((int)$row['blocker_id'] === $myId && (int)$row['blocked_id'] === $userId);
    $isBlockedBy = ((int)$row['blocker_id'] === $userId && (int)$row['blocked_id'] === $myId);
}

echo json_encode([
    "status" => "success",
    "is_blocked" => $isBlocked,
    "is_blocked_by" => $isBlockedBy,
    "either_blocked" => ($isBlocked || $isBlockedBy),
]);

$stmt->close();
$conn->close();
?>