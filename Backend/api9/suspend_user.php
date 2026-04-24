<?php
/**
 * suspend_user.php
 *
 * Admin endpoint to suspend or unsuspend one or more users.
 *
 * POST body (JSON):
 *   user_ids (int[]) – required – array of user IDs to act on
 *   action   (string) – required – "suspend" or "unsuspend"
 *
 * Response:
 *   { "success": true,  "message": "N user(s) suspended successfully" }
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
$input   = json_decode(file_get_contents('php://input'), true) ?? [];
$userIds = isset($input['user_ids']) && is_array($input['user_ids']) ? $input['user_ids'] : [];
$action  = isset($input['action']) ? strtolower(trim((string) $input['action'])) : '';

if (empty($userIds)) {
    http_response_code(422);
    echo json_encode(['success' => false, 'message' => 'user_ids array is required and must not be empty']);
    exit;
}

if (!in_array($action, ['suspend', 'unsuspend'], true)) {
    http_response_code(422);
    echo json_encode(['success' => false, 'message' => "action must be 'suspend' or 'unsuspend'"]);
    exit;
}

// Sanitise IDs to integers and filter out invalid ones
$cleanIds = array_values(array_filter(array_map('intval', $userIds), fn($id) => $id > 0));

if (empty($cleanIds)) {
    http_response_code(422);
    echo json_encode(['success' => false, 'message' => 'No valid user IDs provided']);
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

// ── Perform update ────────────────────────────────────────────────────────────
try {
    $newIsActive = ($action === 'unsuspend') ? 1 : 0;

    $placeholders = implode(',', array_fill(0, count($cleanIds), '?'));
    $stmt = $pdo->prepare(
        "UPDATE users SET isActive = ? WHERE id IN ($placeholders) AND isDelete = 0"
    );
    $stmt->execute(array_merge([$newIsActive], $cleanIds));
    $affected = $stmt->rowCount();

    $verb    = ($action === 'suspend') ? 'suspended' : 'unsuspended';
    $message = "$affected user(s) $verb successfully";

    echo json_encode(['success' => true, 'message' => $message, 'affected' => $affected]);

} catch (PDOException $e) {
    error_log('suspend_user error: ' . $e->getMessage());
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Server error']);
}
