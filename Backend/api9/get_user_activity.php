<?php
/**
 * get_user_activity.php
 *
 * Returns per-user activity statistics for the admin panel.
 *
 * GET parameters:
 *   userid (int) – required – the user whose stats to return
 *
 * Response (JSON):
 *   {
 *     "success": true,
 *     "data": {
 *       "requests_sent":          5,
 *       "requests_received":      3,
 *       "chat_requests_sent":     2,
 *       "chat_requests_accepted": 1,
 *       "profile_views":          10,
 *       "matches_count":          4
 *     }
 *   }
 */

ini_set('display_errors', 0);
ini_set('log_errors', 1);
error_reporting(E_ALL);

header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

require_once __DIR__ . '/auth.php';
requireAdminAuth();

// ── DB credentials ────────────────────────────────────────────────────────────
define('DB_HOST', 'localhost');
define('DB_NAME', 'ms');
define('DB_USER', 'ms');
define('DB_PASS', 'ms');

// ── Input ─────────────────────────────────────────────────────────────────────
$userId = isset($_GET['userid']) ? (int) $_GET['userid'] : 0;

if ($userId <= 0) {
    http_response_code(422);
    echo json_encode(['success' => false, 'message' => 'userid is required']);
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

// ── Helper: safe COUNT fetch ──────────────────────────────────────────────────
function queryCount(PDO $pdo, string $sql, array $params): int {
    $stmt = $pdo->prepare($sql);
    $stmt->execute($params);
    return (int) $stmt->fetchColumn();
}

try {
    // 1. Profile-type requests sent by this user
    $requestsSent = queryCount($pdo,
        "SELECT COUNT(*) FROM proposals WHERE sender_id = ? AND request_type = 'Profile'",
        [$userId]
    );

    // 2. Any requests received by this user
    $requestsReceived = queryCount($pdo,
        "SELECT COUNT(*) FROM proposals WHERE receiver_id = ?",
        [$userId]
    );

    // 3. Chat requests sent by this user
    $chatRequestsSent = queryCount($pdo,
        "SELECT COUNT(*) FROM proposals WHERE sender_id = ? AND request_type = 'Chat'",
        [$userId]
    );

    // 4. Accepted chat requests (where user is sender or receiver)
    $chatRequestsAccepted = queryCount($pdo,
        "SELECT COUNT(*) FROM proposals
         WHERE (sender_id = ? OR receiver_id = ?)
           AND request_type = 'Chat'
           AND status = 'accepted'",
        [$userId, $userId]
    );

    // 5. Profile views of this user (from user_activities log)
    $profileViews = queryCount($pdo,
        "SELECT COUNT(*) FROM user_activities
         WHERE target_user_id = ?
           AND activity_type IN ('profile_view', 'profile_viewed')",
        [$userId]
    );

    // 6. Accepted proposals (matches) for this user
    $matchesCount = queryCount($pdo,
        "SELECT COUNT(*) FROM proposals
         WHERE (sender_id = ? OR receiver_id = ?)
           AND status = 'accepted'",
        [$userId, $userId]
    );

    echo json_encode([
        'success' => true,
        'data'    => [
            'requests_sent'          => $requestsSent,
            'requests_received'      => $requestsReceived,
            'chat_requests_sent'     => $chatRequestsSent,
            'chat_requests_accepted' => $chatRequestsAccepted,
            'profile_views'          => $profileViews,
            'matches_count'          => $matchesCount,
        ],
    ]);

} catch (PDOException $e) {
    error_log('get_user_activity error: ' . $e->getMessage());
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Server error']);
}
