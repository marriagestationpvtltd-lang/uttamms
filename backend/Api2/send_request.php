<?php
/**
 * send_request.php
 *
 * Send (or re-send) a connection request.
 *
 * POST body (JSON or form-encoded):
 *   sender_id    / myid    (int)    – ID of the requesting user
 *   receiver_id  / userid  (int)    – ID of the target user
 *   request_type           (string) – "Photo" | "Profile" | "Chat"
 *
 * If a request of the same type already exists between these two users,
 * it is reset to "pending" and updated_at is refreshed.
 */

ini_set('display_errors', 0);
ini_set('log_errors', 1);
error_reporting(E_ALL);

header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

require_once __DIR__ . '/db_config.php';

// --------------------------------------------------------------------------
// Input parsing — accept JSON body or form-encoded POST
// --------------------------------------------------------------------------

$input = json_decode(file_get_contents('php://input'), true);
if (empty($input)) {
    $input = $_POST;
}

// Support both naming conventions (myid/userid from older clients)
$sender_id    = isset($input['sender_id'])   ? (int) $input['sender_id']   :
               (isset($input['myid'])        ? (int) $input['myid']        : 0);
$receiver_id  = isset($input['receiver_id']) ? (int) $input['receiver_id'] :
               (isset($input['userid'])      ? (int) $input['userid']      : 0);
$request_type = isset($input['request_type']) ? trim($input['request_type']) : 'Photo';

// --------------------------------------------------------------------------
// Validation
// --------------------------------------------------------------------------

$valid_types = ['Photo', 'Profile', 'Chat'];

if ($sender_id <= 0 || $receiver_id <= 0) {
    echo json_encode(['success' => false, 'message' => 'sender_id and receiver_id are required']);
    exit;
}

if (!in_array($request_type, $valid_types, true)) {
    echo json_encode(['success' => false, 'message' => 'Invalid request_type. Must be one of: Photo, Profile, Chat']);
    exit;
}

if ($sender_id === $receiver_id) {
    echo json_encode(['success' => false, 'message' => 'You cannot send a request to yourself']);
    exit;
}

// --------------------------------------------------------------------------
// Upsert logic
// --------------------------------------------------------------------------

try {
    // Check for an existing request of the same type in either direction
    $checkStmt = $pdo->prepare("
        SELECT id
        FROM   proposals
        WHERE  sender_id    = :sender_id
          AND  receiver_id  = :receiver_id
          AND  request_type = :request_type
        LIMIT 1
    ");
    $checkStmt->execute([
        ':sender_id'    => $sender_id,
        ':receiver_id'  => $receiver_id,
        ':request_type' => $request_type,
    ]);
    $existing = $checkStmt->fetch();

    if ($existing) {
        // Re-send: reset status to pending and refresh timestamps
        $updateStmt = $pdo->prepare("
            UPDATE proposals
            SET    status     = 'pending',
                   updated_at = NOW()
            WHERE  id = :id
        ");
        $updateStmt->execute([':id' => $existing['id']]);

        echo json_encode([
            'success'     => true,
            'message'     => '',
            'proposal_id' => (string) $existing['id'],
        ]);
    } else {
        // New request
        $insertStmt = $pdo->prepare("
            INSERT INTO proposals (sender_id, receiver_id, request_type, status, created_at, updated_at)
            VALUES (:sender_id, :receiver_id, :request_type, 'pending', NOW(), NOW())
        ");
        $insertStmt->execute([
            ':sender_id'    => $sender_id,
            ':receiver_id'  => $receiver_id,
            ':request_type' => $request_type,
        ]);

        echo json_encode([
            'success'     => true,
            'message'     => '',
            'proposal_id' => (string) $pdo->lastInsertId(),
        ]);
    }

} catch (PDOException $e) {
    error_log('send_request error: ' . $e->getMessage());
    echo json_encode(['success' => false, 'message' => 'Server error. Please try again.']);
}

