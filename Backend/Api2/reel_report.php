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
$reason = trim((string)($input['reason'] ?? 'other'));
$note = trim((string)($input['note'] ?? ''));

if ($userId <= 0 || $reelId <= 0) {
    http_response_code(422);
    echo json_encode(['success' => false, 'message' => 'user_id and reel_id are required']);
    exit;
}

if (mb_strlen($note) > 1000) {
    $note = mb_substr($note, 0, 1000);
}

$allowedReasons = ['sexual', 'violence', 'hate', 'harassment', 'spam', 'other'];
if (!in_array($reason, $allowedReasons, true)) {
    $reason = 'other';
}

$pdo->beginTransaction();

$insert = $pdo->prepare("INSERT INTO media_reports (entity_type, entity_id, reported_by, reason, note, status, created_at, updated_at)
                         VALUES ('reel', ?, ?, ?, ?, 'open', NOW(), NOW())");
$insert->execute([$reelId, $userId, $reason, $note]);

$countStmt = $pdo->prepare("SELECT COUNT(*) AS cnt FROM media_reports WHERE entity_type = 'reel' AND entity_id = ? AND status = 'open'");
$countStmt->execute([$reelId]);
$openReports = (int)($countStmt->fetch()['cnt'] ?? 0);

// Auto-escalate for admin review after repeated reports.
if ($openReports >= 3) {
    $pdo->prepare("UPDATE user_reels SET moderation_status = 'manual_review', updated_at = NOW() WHERE id = ?")
        ->execute([$reelId]);
}

$pdo->commit();

echo json_encode([
    'success' => true,
    'message' => 'Report submitted',
    'open_reports' => $openReports,
]);
