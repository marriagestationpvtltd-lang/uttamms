<?php
/**
 * send_admin_notification.php
 *
 * Sends a notification to a user from the admin panel.
 * Stores the notification in the database and fires an FCM push if
 * the user has a registered FCM token.
 *
 * POST body (JSON):
 *   userid  (int)    – required – target user ID
 *   title   (string) – required – notification title
 *   message (string) – required – notification body
 *
 * Response:
 *   { "success": true,  "message": "Notification sent" }
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

// ── FCM helper (optional – only loaded when vendor autoload exists) ────────────
$fcmAvailable = false;
$vendorAutoload = __DIR__ . '/../Api2/vendor/autoload.php';
if (file_exists($vendorAutoload)) {
    require_once $vendorAutoload;
    $fcmAvailable = true;
}

// ── Input ─────────────────────────────────────────────────────────────────────
$input   = json_decode(file_get_contents('php://input'), true) ?? [];
$userId  = isset($input['userid'])  ? (int)    $input['userid']  : 0;
$title   = isset($input['title'])   ? trim((string) $input['title'])   : '';
$message = isset($input['message']) ? trim((string) $input['message']) : '';

if ($userId <= 0 || $title === '' || $message === '') {
    http_response_code(422);
    echo json_encode(['success' => false, 'message' => 'userid, title, and message are required']);
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

// ── Verify user exists and fetch FCM token ────────────────────────────────────
$userStmt = $pdo->prepare('SELECT id, fcm_token FROM users WHERE id = ? LIMIT 1');
$userStmt->execute([$userId]);
$user = $userStmt->fetch();

if (!$user) {
    http_response_code(404);
    echo json_encode(['success' => false, 'message' => 'User not found']);
    exit;
}

try {
    // ── Persist notification in DB ────────────────────────────────────────────
    $insertStmt = $pdo->prepare(
        "INSERT INTO notifications (user_id, title, message, type, is_read, created_at)
         VALUES (?, ?, ?, 'admin', 0, NOW())"
    );
    $insertStmt->execute([$userId, $title, $message]);

    // ── Send FCM push if token available ──────────────────────────────────────
    $fcmToken = !empty($user['fcm_token']) ? $user['fcm_token'] : null;
    $fcmResult = null;

    if ($fcmToken && $fcmAvailable && function_exists('sendFCM')) {
        try {
            // Re-use the sendFCM helper from Api2/common_fcm.php
            $serviceKeyPath = __DIR__ . '/../Api2/service-account-key.json';
            if (file_exists($serviceKeyPath)) {
                require_once __DIR__ . '/../Api2/common_fcm.php';
                $fcmResult = sendFCM($fcmToken, $title, $message, [
                    'type'    => 'admin_notification',
                    'user_id' => (string) $userId,
                ]);
            }
        } catch (Exception $fcmEx) {
            error_log('send_admin_notification FCM error: ' . $fcmEx->getMessage());
            // FCM failure should not fail the whole request
        }
    }

    echo json_encode([
        'success' => true,
        'message' => 'Notification sent',
        'fcm_sent' => $fcmResult !== null,
    ]);

} catch (PDOException $e) {
    error_log('send_admin_notification error: ' . $e->getMessage());
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Server error']);
}
