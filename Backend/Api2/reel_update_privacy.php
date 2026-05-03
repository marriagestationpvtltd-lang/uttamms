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
$reelId = isset($raw['reel_id']) ? (int)$raw['reel_id'] : (isset($_POST['reel_id']) ? (int)$_POST['reel_id'] : 0);
$privacy = trim((string)($raw['privacy'] ?? ($_POST['privacy'] ?? '')));
$adminId = isset($raw['admin_id']) ? (int)$raw['admin_id'] : (isset($_POST['admin_id']) ? (int)$_POST['admin_id'] : 0);
$asAdmin = isset($raw['as_admin'])
    ? in_array(strtolower(trim((string)$raw['as_admin'])), ['1', 'true', 'yes'], true)
    : (isset($_POST['as_admin'])
        ? in_array(strtolower(trim((string)$_POST['as_admin'])), ['1', 'true', 'yes'], true)
        : ($adminId > 0));

if ($userId <= 0 || $reelId <= 0 || $privacy === '') {
    http_response_code(422);
    echo json_encode(['success' => false, 'message' => 'user_id, reel_id and privacy are required']);
    exit;
}

$allowedPrivacy = ['public', 'matches_only', 'private', 'paid_only', 'verified_only', 'paid', 'verified'];
if (!in_array($privacy, $allowedPrivacy, true)) {
    http_response_code(422);
    echo json_encode(['success' => false, 'message' => 'Invalid privacy value']);
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
    ? $pdo->prepare('SELECT id, user_id FROM user_reels WHERE id = ? AND status = "active" LIMIT 1')
    : $pdo->prepare('SELECT id, user_id FROM user_reels WHERE id = ? AND user_id = ? AND status = "active" LIMIT 1');
if ($asAdmin) {
    $check->execute([$reelId]);
} else {
    $check->execute([$reelId, $userId]);
}
if (!$check->fetch()) {
    http_response_code(404);
    echo json_encode(['success' => false, 'message' => 'Reel not found or access denied']);
    exit;
}

$upd = $asAdmin
    ? $pdo->prepare('UPDATE user_reels SET privacy = ?, updated_at = NOW() WHERE id = ? LIMIT 1')
    : $pdo->prepare('UPDATE user_reels SET privacy = ?, updated_at = NOW() WHERE id = ? AND user_id = ? LIMIT 1');
if ($asAdmin) {
    $upd->execute([$privacy, $reelId]);
} else {
    $upd->execute([$privacy, $reelId, $userId]);
}

echo json_encode([
    'success' => true,
    'message' => 'Reel privacy updated',
    'data' => [
        'reel_id' => $reelId,
        'privacy' => $privacy,
    ],
]);
