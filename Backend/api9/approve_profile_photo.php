<?php
/**
 * approve_profile_photo.php
 *
 * Admin endpoint to approve or reject a user's pending profile photo.
 * Updates the user's latest pending photo in user_gallery to 'approved' or
 * 'rejected'.  If no pending gallery photo exists the call still succeeds so
 * the admin panel can proceed.
 *
 * POST body (JSON):
 *   userid  (int)    – required – target user ID
 *   action  (string) – required – "approve" or "reject"
 *   reason  (string) – optional – rejection reason (required when action = reject)
 *
 * Response:
 *   { "success": true,  "message": "..." }
 *   { "success": false, "message": "<reason>" }
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

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['success' => false, 'message' => 'Method not allowed']);
    exit;
}

// ── DB credentials ────────────────────────────────────────────────────────────
define('DB_HOST', 'localhost');
define('DB_NAME', 'ms');
define('DB_USER', 'ms');
define('DB_PASS', 'ms');

// ── Input ─────────────────────────────────────────────────────────────────────
$input  = json_decode(file_get_contents('php://input'), true) ?? [];
$userId = isset($input['userid']) ? (int)    $input['userid'] : 0;
$action = isset($input['action']) ? strtolower(trim((string) $input['action'])) : '';
$reason = isset($input['reason']) ? trim((string) $input['reason']) : '';

if ($userId <= 0 || !in_array($action, ['approve', 'reject'], true)) {
    http_response_code(422);
    echo json_encode(['success' => false, 'message' => "userid and action ('approve' or 'reject') are required"]);
    exit;
}

if ($action === 'reject' && $reason === '') {
    http_response_code(422);
    echo json_encode(['success' => false, 'message' => 'reason is required when action is reject']);
    exit;
}

// ── Connect ───────────────────────────────────────────────────────────────────
try {
    $pdo = new PDO(
        'mysql:host=' . DB_HOST . ';dbname=' . DB_NAME . ';charset=utf8mb4',
        DB_USER,
        DB_PASS,
        [
            PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES   => false,
        ]
    );
} catch (PDOException $e) {
    http_response_code(503);
    echo json_encode(['success' => false, 'message' => 'Database connection failed']);
    exit;
}

// ── Verify user exists ────────────────────────────────────────────────────────
$check = $pdo->prepare('SELECT id FROM users WHERE id = ? LIMIT 1');
$check->execute([$userId]);
if (!$check->fetch()) {
    http_response_code(404);
    echo json_encode(['success' => false, 'message' => 'User not found']);
    exit;
}

try {
    $newStatus    = ($action === 'approve') ? 'approved' : 'rejected';
    $rejectReason = ($action === 'reject')  ? $reason    : null;

    // ── Update all pending gallery photos for the user ─────────────────────────
    $stmt = $pdo->prepare(
        "UPDATE user_gallery
         SET status = ?, reject_reason = ?, updated_at = NOW()
         WHERE userid = ? AND status = 'pending'"
    );
    $stmt->execute([$newStatus, $rejectReason, $userId]);
    $affectedGallery = $stmt->rowCount();

    // ── Reflect approval in the users table status when approving ──────────────
    // Only promote to 'approved' if currently pending; do not demote verified users.
    if ($action === 'approve') {
        $pdo->prepare(
            "UPDATE users SET status = 'approved' WHERE id = ? AND status = 'pending'"
        )->execute([$userId]);
    }

    $message = $affectedGallery > 0
        ? "Photo {$newStatus} successfully"
        : "No pending photos found, but action recorded";

    echo json_encode(['success' => true, 'message' => $message]);

} catch (PDOException $e) {
    error_log('approve_profile_photo error: ' . $e->getMessage());
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Server error']);
}
