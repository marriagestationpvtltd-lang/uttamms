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

require_once __DIR__ . '/db_config.php';

$body    = (string)file_get_contents('php://input');
$data    = json_decode($body, true);
$userId  = (int)($data['user_id'] ?? 0);
$reelId  = (int)($data['reel_id'] ?? 0);
$watched = max(0, min(255, (int)($data['watched_seconds'] ?? 0)));

if ($userId <= 0 || $reelId <= 0) {
    http_response_code(422);
    echo json_encode(['success' => false, 'message' => 'user_id and reel_id are required']);
    exit;
}

try {
    // Upsert into reel_views (prevents duplicate counting per user)
    $stmt = $pdo->prepare(
        "INSERT INTO reel_views (reel_id, user_id, watched_seconds, created_at)
         VALUES (?, ?, ?, NOW())
         ON DUPLICATE KEY UPDATE watched_seconds = GREATEST(watched_seconds, VALUES(watched_seconds))"
    );
    $isNew = $stmt->execute([$reelId, $userId, $watched]);
    $affected = $stmt->rowCount();

    // rowCount() = 1 → new row inserted (first view by this user)
    // rowCount() = 2 → existing row updated
    // rowCount() = 0 → no change (same watched_seconds value)
    if ($affected === 1) {
        // First time this user views this reel — increment counter
        $pdo->prepare("UPDATE user_reels SET view_count = view_count + 1 WHERE id = ?")
            ->execute([$reelId]);
    }

    // Return new view count
    $row = $pdo->prepare("SELECT COALESCE(view_count, 0) AS view_count FROM user_reels WHERE id = ?");
    $row->execute([$reelId]);
    $count = (int)(($row->fetch()['view_count'] ?? 0));

    echo json_encode(['success' => true, 'view_count' => $count]);
} catch (Throwable $e) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Server error']);
    error_log('[reel_view] ' . $e->getMessage());
}
