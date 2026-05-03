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

$input = json_decode(file_get_contents('php://input'), true) ?? [];
$userId = (int)($input['user_id'] ?? 0);
$reelId = (int)($input['reel_id'] ?? 0);
$action = trim((string)($input['action'] ?? 'toggle'));

if ($userId <= 0 || $reelId <= 0) {
    http_response_code(422);
    echo json_encode(['success' => false, 'message' => 'user_id and reel_id are required']);
    exit;
}

$reelStmt = $pdo->prepare("SELECT id FROM user_reels WHERE id = ? AND status = 'active' LIMIT 1");
$reelStmt->execute([$reelId]);
if (!$reelStmt->fetch()) {
    http_response_code(404);
    echo json_encode(['success' => false, 'message' => 'Reel not found']);
    exit;
}

$existsStmt = $pdo->prepare('SELECT id FROM reel_likes WHERE reel_id = ? AND user_id = ? LIMIT 1');
$existsStmt->execute([$reelId, $userId]);
$existing = $existsStmt->fetch();

$liked = false;
if ($action === 'unlike') {
    $pdo->prepare('DELETE FROM reel_likes WHERE reel_id = ? AND user_id = ?')->execute([$reelId, $userId]);
    $liked = false;
} elseif ($action === 'like') {
    $pdo->prepare('INSERT IGNORE INTO reel_likes (reel_id, user_id, created_at) VALUES (?, ?, NOW())')->execute([$reelId, $userId]);
    $liked = true;
} else {
    if ($existing) {
        $pdo->prepare('DELETE FROM reel_likes WHERE reel_id = ? AND user_id = ?')->execute([$reelId, $userId]);
        $liked = false;
    } else {
        $pdo->prepare('INSERT IGNORE INTO reel_likes (reel_id, user_id, created_at) VALUES (?, ?, NOW())')->execute([$reelId, $userId]);
        $liked = true;
    }
}

$countStmt = $pdo->prepare('SELECT COUNT(*) AS cnt FROM reel_likes WHERE reel_id = ?');
$countStmt->execute([$reelId]);
$likeCount = (int)($countStmt->fetch()['cnt'] ?? 0);

echo json_encode([
    'success' => true,
    'liked' => $liked,
    'like_count' => $likeCount,
]);
