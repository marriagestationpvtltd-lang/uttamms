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

    $myid    = isset($input['myid'])    ? intval($input['myid'])    : 0;
    $otherid = isset($input['other_id']) ? intval($input['other_id']) : 0;

    $user1_name  = isset($input['user1_name'])  ? trim($input['user1_name'])  : '';
    $user2_name  = isset($input['user2_name'])  ? trim($input['user2_name'])  : '';
    $user1_image = isset($input['user1_image']) ? trim($input['user1_image']) : '';
    $user2_image = isset($input['user2_image']) ? trim($input['user2_image']) : '';

    if ($myid <= 0 || $otherid <= 0) {
        echo json_encode(['success' => false, 'message' => 'myid and other_id are required']);
        exit;
    }

    if ($myid === $otherid) {
        echo json_encode(['success' => false, 'message' => 'Cannot start a conversation with yourself']);
        exit;
    }

    // Check sender has an active (non-expired) package
    $pkgStmt = $pdo->prepare("
        SELECT id FROM user_package
        WHERE userid = ? AND expiredate > NOW()
        LIMIT 1
    ");
    $pkgStmt->execute([$myid]);

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
    $reqStmt->execute([$myid, $otherid, $otherid, $myid]);

    if ($reqStmt->rowCount() === 0) {
        echo json_encode([
            'success'    => false,
            'message'    => 'Chat request not accepted',
            'error_code' => 'REQUEST_NOT_ACCEPTED',
        ]);
        exit;
    }

    // Derive a deterministic chat room ID from the two user IDs
    $roomId = min($myid, $otherid) . '_' . max($myid, $otherid);

    // Ensure the chat room exists (INSERT IGNORE is safe to call multiple times)
    $participants = json_encode([(string)$myid, (string)$otherid]);
    $names        = json_encode([(string)$myid => $user1_name, (string)$otherid => $user2_name]);
    $images       = json_encode([(string)$myid => $user1_image, (string)$otherid => $user2_image]);

    $pdo->prepare("
        INSERT IGNORE INTO chat_rooms
          (id, participants, participant_names, participant_images,
           last_message, last_message_type, last_message_time, last_message_sender_id)
        VALUES (?, ?, ?, ?, '', 'text', UTC_TIMESTAMP(), '')
    ")->execute([$roomId, $participants, $names, $images]);

    // Initialise unread counters if not already present
    $pdo->prepare("
        INSERT IGNORE INTO chat_unread_counts (chat_room_id, user_id, unread_count)
        VALUES (?,?,0),(?,?,0)
    ")->execute([$roomId, $myid, $roomId, $otherid]);

    echo json_encode([
        'success'      => true,
        'message'      => 'Conversation started',
        'chat_room_id' => $roomId,
    ]);

} catch (PDOException $e) {
    error_log('start_conversation.php DB error: ' . $e->getMessage());
    echo json_encode(['success' => false, 'message' => 'Server error. Please try again.']);
}
?>
