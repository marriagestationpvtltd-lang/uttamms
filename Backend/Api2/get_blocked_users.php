<?php
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');

$conn = new mysqli("localhost", "root", "", "ms");

$input = json_decode(file_get_contents('php://input'), true);
$myId = intval($input['my_id'] ?? 0);

if ($myId <= 0) {
    echo json_encode(["status" => "error", "users" => []]);
    exit;
}

$stmt = $conn->prepare("
    SELECT u.id, u.firstName as first_name, u.lastName as last_name, u.profile_picture as photo, b.created_at as blocked_date
    FROM blocks b
    JOIN users u ON b.blocked_id = u.id
    WHERE b.blocker_id = ?
    ORDER BY b.created_at DESC
");
$stmt->bind_param("i", $myId);
$stmt->execute();
$result = $stmt->get_result();

$users = [];
while ($row = $result->fetch_assoc()) {
    $users[] = $row;
}

echo json_encode([
    "status" => "success",
    "users" => $users
]);

$stmt->close();
$conn->close();
?>