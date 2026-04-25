<?php
header("Content-Type: application/json");
header("Access-Control-Allow-Origin: *");

require_once __DIR__ . '/db_config.php';
require_once __DIR__ . '/activity_helper.php';
require_once __DIR__ . '/../socket_notify_helper.php';

$myid         = isset($_POST['myid'])         ? intval($_POST['myid'])         : 0;
$sender_id    = isset($_POST['sender_id'])    ? intval($_POST['sender_id'])    : 0;
$request_type = isset($_POST['request_type']) ? $_POST['request_type']         : '';

if ($myid <= 0 || $sender_id <= 0 || empty($request_type)) {
    echo json_encode(["status" => "error", "message" => "Invalid params"]);
    exit;
}

try {
    // 🔥 Only receiver can reject
    $stmt = $pdo->prepare("
        UPDATE proposals
        SET status = 'rejected', updated_at = NOW()
        WHERE sender_id = ? AND receiver_id = ?
          AND request_type = ? AND status = 'pending'
        ORDER BY id DESC LIMIT 1
    ");
    $stmt->execute([$sender_id, $myid, $request_type]);

    if ($stmt->rowCount() > 0) {
        logActivity($myid, 'request_rejected', "$request_type request rejected", $sender_id);

        // Push real-time notification so sender's app and admin panel update instantly.
        $nameStmt = $pdo->prepare(
            "SELECT id, CONCAT_WS(' ', firstName, lastName) AS full_name FROM users WHERE id IN (?, ?) LIMIT 2"
        );
        $nameStmt->execute([$sender_id, $myid]);
        $names = [];
        foreach ($nameStmt->fetchAll(PDO::FETCH_ASSOC) as $row) {
            $names[(int)$row['id']] = $row['full_name'];
        }
        notifyRequestEvent([
            'event'        => 'request_rejected',
            'senderId'     => $sender_id,
            'receiverId'   => $myid,
            'senderName'   => $names[$sender_id] ?? '',
            'receiverName' => $names[$myid]      ?? '',
            'requestType'  => $request_type,
            'status'       => 'rejected',
        ]);

        echo json_encode([
            "status"  => "success",
            "message" => "Request rejected successfully",
        ]);
    } else {
        echo json_encode([
            "status"  => "error",
            "message" => "No pending request found",
        ]);
    }
} catch (PDOException $e) {
    error_log('reject_request.php DB error: ' . $e->getMessage());
    echo json_encode(["status" => "error", "message" => "Failed to update request"]);
}
?>