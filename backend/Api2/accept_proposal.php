<?php
/**
 * accept_proposal.php
 *
 * Accept a pending proposal. Only the receiver may accept.
 *
 * POST body (JSON or form-encoded):
 *   proposal_id (int) – ID of the proposal to accept
 *   user_id     (int) – ID of the currently logged-in user (must be the receiver)
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
// Accept logic
// --------------------------------------------------------------------------

try {
    // Fetch the proposal in one query — get both sender and receiver
    $stmt = $pdo->prepare("
        SELECT id, sender_id, receiver_id
        FROM   proposals
        WHERE  id = ? AND status = 'pending'
        LIMIT 1
    ");
    $stmt->execute([$proposalId]);
    $proposal = $stmt->fetch();

    if (!$proposal) {
        echo json_encode(['success' => false, 'message' => 'Proposal not found or already processed']);
        exit;
    }

    if ((int) $proposal['receiver_id'] !== $userId) {
        echo json_encode(['success' => false, 'message' => 'You are not authorized to accept this proposal']);
        exit;
    }

    // Update status
    $update = $pdo->prepare("UPDATE proposals SET status = 'accepted', updated_at = NOW() WHERE id = ?");
    $update->execute([$proposalId]);

    // Notify the sender (silently skip if notifications table doesn't exist)
    try {
        $notify = $pdo->prepare("
            INSERT INTO notifications (user_id, title, message, type, reference_id, created_at)
            VALUES (?, 'Proposal Accepted', 'Your proposal has been accepted', 'proposal', ?, NOW())
        ");
        $notify->execute([$proposal['sender_id'], $proposalId]);
    } catch (PDOException $e) {
        // Notifications table may not exist – non-fatal
        error_log('accept_proposal notification error: ' . $e->getMessage());
    }

    echo json_encode(['success' => true, 'message' => 'Proposal accepted successfully']);

} catch (PDOException $e) {
    error_log('accept_proposal error: ' . $e->getMessage());
    echo json_encode(['success' => false, 'message' => 'Server error. Please try again.']);
}

