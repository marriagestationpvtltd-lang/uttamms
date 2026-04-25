<?php
/**
 * reject_proposal.php
 *
 * Reject a pending proposal. Both the sender AND the receiver may reject.
 *
 * POST body (JSON or form-encoded):
 *   proposal_id (int) – ID of the proposal to reject
 *   user_id     (int) – ID of the currently logged-in user
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
require_once __DIR__ . '/../socket_notify_helper.php';

// --------------------------------------------------------------------------
// Input
// --------------------------------------------------------------------------

$input = json_decode(file_get_contents('php://input'), true);
if (empty($input)) {
    $input = $_POST;
}

if (empty($input['proposal_id']) || empty($input['user_id'])) {
    echo json_encode(['success' => false, 'message' => 'Missing parameters: proposal_id and user_id are required']);
    exit;
}

$proposalId = (int) $input['proposal_id'];
$userId     = (int) $input['user_id'];

// --------------------------------------------------------------------------
// Reject logic
// --------------------------------------------------------------------------

try {
    $stmt = $pdo->prepare("
        SELECT id, sender_id, receiver_id, status
        FROM   proposals
        WHERE  id = ?
        LIMIT 1
    ");
    $stmt->execute([$proposalId]);
    $proposal = $stmt->fetch();

    if (!$proposal) {
        echo json_encode(['success' => false, 'message' => 'Proposal not found']);
        exit;
    }

    if ($proposal['status'] !== 'pending') {
        echo json_encode(['success' => false, 'message' => 'Proposal already processed']);
        exit;
    }

    // Both sender and receiver may reject
    if ((int) $proposal['sender_id'] !== $userId && (int) $proposal['receiver_id'] !== $userId) {
        echo json_encode(['success' => false, 'message' => 'You are not authorized to reject this proposal']);
        exit;
    }

    $update = $pdo->prepare("UPDATE proposals SET status = 'rejected', updated_at = NOW() WHERE id = ?");
    $update->execute([$proposalId]);

    // Notify the other party (silently skip if notifications table doesn't exist)
    $otherUserId = ((int) $proposal['sender_id'] === $userId)
        ? $proposal['receiver_id']
        : $proposal['sender_id'];

    try {
        $notify = $pdo->prepare("
            INSERT INTO notifications (user_id, title, message, type, reference_id, created_at)
            VALUES (?, 'Proposal Rejected', 'Your proposal has been rejected', 'proposal', ?, NOW())
        ");
        $notify->execute([$otherUserId, $proposalId]);
    } catch (PDOException $e) {
        error_log('reject_proposal notification error: ' . $e->getMessage());
    }

    // Push real-time notification to the other party and admin panel.
    $nameStmt = $pdo->prepare(
        "SELECT id, CONCAT_WS(' ', firstName, lastName) AS full_name FROM users WHERE id IN (?, ?) LIMIT 2"
    );
    $nameStmt->execute([$proposal['sender_id'], $proposal['receiver_id']]);
    $names = [];
    foreach ($nameStmt->fetchAll(PDO::FETCH_ASSOC) as $row) {
        $names[(int)$row['id']] = $row['full_name'];
    }
    notifyRequestEvent([
        'event'        => 'request_rejected',
        'proposalId'   => $proposalId,
        'senderId'     => (int)$proposal['sender_id'],
        'receiverId'   => (int)$proposal['receiver_id'],
        'senderName'   => $names[(int)$proposal['sender_id']]   ?? '',
        'receiverName' => $names[(int)$proposal['receiver_id']] ?? '',
        'requestType'  => 'Profile',
        'status'       => 'rejected',
    ]);

    echo json_encode(['success' => true, 'message' => 'Proposal rejected successfully']);

} catch (PDOException $e) {
    error_log('reject_proposal error: ' . $e->getMessage());
    echo json_encode(['success' => false, 'message' => 'Server error. Please try again.']);
}

