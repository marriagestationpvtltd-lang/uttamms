<?php
header("Content-Type: application/json");
header("Access-Control-Allow-Origin: *");

require_once __DIR__ . '/db_config.php';
require_once __DIR__ . '/activity_helper.php';

$myid         = isset($_POST['myid'])         ? intval($_POST['myid'])         : 0;
$sender_id    = isset($_POST['sender_id'])    ? intval($_POST['sender_id'])    : 0;
$request_type = isset($_POST['request_type']) ? $_POST['request_type']         : '';

if ($myid <= 0 || $sender_id <= 0 || empty($request_type)) {
    echo json_encode(["status" => "error", "message" => "Invalid params"]);
    exit;
}

try {
    // 🔥 Only receiver can accept
    $stmt = $pdo->prepare("
        UPDATE proposals
        SET status = 'accepted', updated_at = NOW()
        WHERE sender_id = ? AND receiver_id = ?
          AND request_type = ? AND status = 'pending'
        ORDER BY id DESC LIMIT 1
    ");
    $stmt->execute([$sender_id, $myid, $request_type]);

    if ($stmt->rowCount() > 0) {
        logActivity($myid, 'request_accepted', "$request_type request accepted", $sender_id);
        echo json_encode([
            "status"  => "success",
            "message" => "Request accepted successfully",
        ]);
    } else {
        echo json_encode([
            "status"  => "error",
            "message" => "No pending request found",
        ]);
    }
} catch (PDOException $e) {
    error_log('accept_request.php DB error: ' . $e->getMessage());
    echo json_encode(["status" => "error", "message" => "Failed to update request"]);
}
?>