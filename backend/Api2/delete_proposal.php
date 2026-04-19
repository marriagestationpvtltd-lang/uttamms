<?php
/**
 * delete_proposal.php
 *
 * Delete a pending or rejected proposal.
 * Only the sender or receiver of the proposal may delete it.
 * Accepted proposals cannot be deleted (they are part of the history).
 *
 * POST body (JSON or form-encoded):
 *   proposal_id (int) – ID of the proposal to delete
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
// Delete logic
// --------------------------------------------------------------------------

try {
    // Verify the proposal exists, belongs to this user, and is in a deletable state
    $checkStmt = $pdo->prepare("
        SELECT id FROM proposals
        WHERE  id          = ?
          AND  (sender_id = ? OR receiver_id = ?)
          AND  status IN ('pending', 'rejected')
        LIMIT 1
    ");
    $checkStmt->execute([$proposalId, $userId, $userId]);

    if (!$checkStmt->fetch()) {
        echo json_encode(['success' => false, 'message' => 'Proposal not found or cannot be deleted']);
        exit;
    }

    $deleteStmt = $pdo->prepare("DELETE FROM proposals WHERE id = ?");
    $deleteStmt->execute([$proposalId]);

    echo json_encode(['success' => true, 'message' => 'Proposal deleted successfully']);

} catch (PDOException $e) {
    error_log('delete_proposal error: ' . $e->getMessage());
    echo json_encode(['success' => false, 'message' => 'Server error. Please try again.']);
}

