<?php
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

require_once __DIR__ . '/../Api2/db_config.php';

$userId = isset($_GET['userid']) ? (int)$_GET['userid'] : 0;
if ($userId <= 0) {
    http_response_code(422);
    echo json_encode(['success' => false, 'message' => 'userid is required']);
    exit;
}

$reelStmt = $pdo->prepare("SELECT id, video_url, thumbnail_url, caption, privacy, status, moderation_status, created_at
                           FROM user_reels
                           WHERE user_id = ?
                           ORDER BY id DESC
                           LIMIT 200");
$reelStmt->execute([$userId]);
$reels = $reelStmt->fetchAll();

$storyStmt = $pdo->prepare("SELECT id, media_type, media_url, caption, privacy, status, moderation_status, expires_at, created_at
                            FROM user_stories
                            WHERE user_id = ?
                            ORDER BY id DESC
                            LIMIT 200");
$storyStmt->execute([$userId]);
$stories = $storyStmt->fetchAll();

echo json_encode([
    'success' => true,
    'data' => [
        'user_id' => $userId,
        'reels' => $reels,
        'stories' => $stories,
        'reel_count' => count($reels),
        'story_count' => count($stories),
    ],
]);
