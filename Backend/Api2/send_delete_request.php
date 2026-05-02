<?php
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');

$conn = new mysqli("localhost", "root", "", "ms");
if ($conn->connect_error) {
    echo json_encode(["status" => "error", "message" => "DB Connection failed"]);
    exit;
}

$input = file_get_contents('php://input');
$data = json_decode($input, true);
if (empty($data)) {
    $data = $_POST;
}

$userid = intval($data['userid'] ?? 0);
$delete_reason = trim($data['delete_reason'] ?? '');
$feedback = trim($data['feedback'] ?? '');

if ($userid <= 0) {
    echo json_encode(["status" => "error", "message" => "Invalid user ID"]);
    exit;
}

try {
    // Disable foreign key checks
    $conn->query("SET FOREIGN_KEY_CHECKS = 0");
    
    // Log deletion
    $conn->query("INSERT INTO deletion_log (userid, reason, feedback, deleted_at) VALUES ($userid, '$delete_reason', '$feedback', NOW())");
    
    // Delete from userblock
    $conn->query("DELETE FROM userblock WHERE userId = $userid OR userBlockId = $userid");
    
    // Delete the user
    $conn->query("DELETE FROM users WHERE id = $userid");
    
    // Re-enable foreign key checks
    $conn->query("SET FOREIGN_KEY_CHECKS = 1");
    
    echo json_encode([
        "status" => "success",
        "message" => "Your account has been permanently deleted"
    ]);
    
} catch (Exception $e) {
    $conn->query("SET FOREIGN_KEY_CHECKS = 1");
    echo json_encode([
        "status" => "error",
        "message" => "Failed to delete account: " . $e->getMessage()
    ]);
}

$conn->close();
?>