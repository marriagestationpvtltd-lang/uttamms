<?php
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

require_once __DIR__ . '/db_config.php';

$raw = json_decode(file_get_contents('php://input') ?: '{}', true);
if (!is_array($raw)) $raw = [];

$userId = isset($raw['user_id']) ? (int)$raw['user_id'] : (isset($_POST['user_id']) ? (int)$_POST['user_id'] : 0);
$storyId = isset($raw['story_id']) ? (int)$raw['story_id'] : (isset($_POST['story_id']) ? (int)$_POST['story_id'] : 0);
$adminId = isset($raw['admin_id']) ? (int)$raw['admin_id'] : (isset($_POST['admin_id']) ? (int)$_POST['admin_id'] : 0);
$asAdmin = isset($raw['as_admin'])
    ? in_array(strtolower(trim((string)$raw['as_admin'])), ['1', 'true', 'yes'], true)
    : (isset($_POST['as_admin'])
        ? in_array(strtolower(trim((string)$_POST['as_admin'])), ['1', 'true', 'yes'], true)
        : ($adminId > 0));

if ($userId <= 0 || $storyId <= 0) {
    http_response_code(422);
    echo json_encode(['success' => false, 'message' => 'user_id and story_id are required']);
    exit;
}

if ($asAdmin) {
    if ($adminId <= 0) {
        http_response_code(422);
        echo json_encode(['success' => false, 'message' => 'admin_id is required for admin action']);
        exit;
    }
    $adminStmt = $pdo->prepare('SELECT id, is_active FROM admins WHERE id = ? LIMIT 1');
    $adminStmt->execute([$adminId]);
    $admin = $adminStmt->fetch();
    if (!$admin || (int)($admin['is_active'] ?? 0) !== 1) {
        http_response_code(403);
        echo json_encode(['success' => false, 'message' => 'Invalid or inactive admin']);
        exit;
    }
}

$check = $asAdmin
    ? $pdo->prepare('SELECT id FROM user_stories WHERE id = ? AND status = "active" LIMIT 1')
    : $pdo->prepare('SELECT id FROM user_stories WHERE id = ? AND user_id = ? AND status = "active" LIMIT 1');
if ($asAdmin) {
    $check->execute([$storyId]);
} else {
    $check->execute([$storyId, $userId]);
}
if (!$check->fetch()) {
    http_response_code(404);
    echo json_encode(['success' => false, 'message' => 'Story not found or access denied']);
    exit;
}

$upd = $asAdmin
    ? $pdo->prepare('UPDATE user_stories SET status = "deleted", updated_at = NOW() WHERE id = ? LIMIT 1')
    : $pdo->prepare('UPDATE user_stories SET status = "deleted", updated_at = NOW() WHERE id = ? AND user_id = ? LIMIT 1');
if ($asAdmin) {
    $upd->execute([$storyId]);
} else {
    $upd->execute([$storyId, $userId]);
}

echo json_encode([
    'success' => true,
    'message' => 'Story deleted successfully',
    'data' => [
        'story_id' => $storyId,
    ],
]);
