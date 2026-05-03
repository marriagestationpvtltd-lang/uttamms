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
$shareType = trim((string)($input['share_type'] ?? 'copy_link'));

if ($userId <= 0 || $reelId <= 0) {
    http_response_code(422);
    echo json_encode(['success' => false, 'message' => 'user_id and reel_id are required']);
    exit;
}

$allowedTypes = ['copy_link', 'chat', 'external'];
if (!in_array($shareType, $allowedTypes, true)) {
    $shareType = 'copy_link';
}

$stmt = $pdo->prepare('INSERT INTO reel_shares (reel_id, user_id, share_type, created_at) VALUES (?, ?, ?, NOW())');
$stmt->execute([$reelId, $userId, $shareType]);

$countStmt = $pdo->prepare('SELECT COUNT(*) AS cnt FROM reel_shares WHERE reel_id = ?');
$countStmt->execute([$reelId]);
$shareCount = (int)($countStmt->fetch()['cnt'] ?? 0);

echo json_encode([
    'success' => true,
    'message' => 'Share recorded',
    'share_count' => $shareCount,
]);
