<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

require_once __DIR__ . '/db_config.php';

try {
    $input = json_decode(file_get_contents('php://input'), true);
    if (!$input) {
        $input = $_POST;
    }

    $sender_id   = isset($input['myid'])        ? intval($input['myid'])        : 0;
    $receiver_id = isset($input['receiver_id'])  ? intval($input['receiver_id'])  : 0;
    $message     = isset($input['message'])      ? trim($input['message'])        : '';
    $chat_room_id = isset($input['chat_room_id']) ? trim($input['chat_room_id'])  : '';
    $message_type = isset($input['message_type'])
        ? $input['message_type']
        : 'text';

    $allowed_types = ['text', 'image', 'voice', 'video', 'file', 'doc'];
    if (!in_array($message_type, $allowed_types, true)) {
        $message_type = 'text';
    }

    if ($sender_id <= 0 || $receiver_id <= 0) {
        echo json_encode(['success' => false, 'message' => 'myid and receiver_id are required']);
        exit;
    }

    if ($message_type === 'text' && $message === '') {
        echo json_encode(['success' => false, 'message' => 'Message text is required']);
        exit;
    }

    // Check sender has an active (non-expired) package
    $pkgStmt = $pdo->prepare("
        SELECT id FROM user_package
        WHERE userid = ? AND expiredate > NOW()
        LIMIT 1
    ");
    $pkgStmt->execute([$sender_id]);

    if ($pkgStmt->rowCount() === 0) {
        echo json_encode([
            'success'    => false,
            'message'    => 'Upgrade membership required',
            'error_code' => 'PACKAGE_REQUIRED',
        ]);
        exit;
    }

    // Check there is an accepted Chat request between the two users
    $reqStmt = $pdo->prepare("
        SELECT id FROM proposals
        WHERE request_type = 'Chat'
          AND status = 'accepted'
          AND (
            (sender_id = ? AND receiver_id = ?)
            OR
            (sender_id = ? AND receiver_id = ?)
          )
        LIMIT 1
    ");
    $reqStmt->execute([$sender_id, $receiver_id, $receiver_id, $sender_id]);

    if ($reqStmt->rowCount() === 0) {
        echo json_encode([
            'success'    => false,
            'message'    => 'Chat request not accepted',
            'error_code' => 'REQUEST_NOT_ACCEPTED',
        ]);
        exit;
    }

    // Derive the deterministic chat room ID if not supplied
    if ($chat_room_id === '') {
        $chat_room_id = min($sender_id, $receiver_id) . '_' . max($sender_id, $receiver_id);
    }

    // Enforce message length limit (64 KB)
    $message = mb_substr($message, 0, 65536);

    // Generate a unique message ID
    $message_id = $chat_room_id . '-' . uniqid('', true);

    $pdo->prepare("
        INSERT INTO chat_messages
          (message_id, chat_room_id, sender_id, receiver_id, message, message_type,
           is_read, is_delivered, created_at)
        VALUES (?, ?, ?, ?, ?, ?, 0, 0, UTC_TIMESTAMP())
    ")->execute([
        $message_id,
        $chat_room_id,
        (string)$sender_id,
        (string)$receiver_id,
        $message,
        $message_type,
    ]);

    // Update the chat room's last message
    $pdo->prepare("
        UPDATE chat_rooms
           SET last_message         = ?,
               last_message_type    = ?,
               last_message_time    = UTC_TIMESTAMP(),
               last_message_sender_id = ?
         WHERE id = ?
    ")->execute([$message, $message_type, (string)$sender_id, $chat_room_id]);

    // Increment unread counter for the receiver
    $pdo->prepare("
        INSERT INTO chat_unread_counts (chat_room_id, user_id, unread_count)
        VALUES (?, ?, 1)
        ON DUPLICATE KEY UPDATE unread_count = unread_count + 1
    ")->execute([$chat_room_id, (string)$receiver_id]);

    echo json_encode([
        'success'    => true,
        'message'    => 'Message sent',
        'message_id' => $message_id,
    ]);

} catch (PDOException $e) {
    error_log('send_message.php DB error: ' . $e->getMessage());
    echo json_encode(['success' => false, 'message' => 'Server error. Please try again.']);
}
?>
