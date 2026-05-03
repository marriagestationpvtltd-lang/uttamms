<?php
ini_set('display_errors', 0);
ini_set('log_errors', 1);
error_reporting(E_ALL);

header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

require_once __DIR__ . '/db_config.php';
require_once __DIR__ . '/media_moderation_helper.php';

if ($_SERVER['REQUEST_METHOD'] === 'GET') {
    $reelId = (int)($_GET['reel_id'] ?? 0);
    $cursorId = (int)($_GET['cursor_id'] ?? 0);
    $limit = (int)($_GET['limit'] ?? 30);
    if ($limit <= 0) $limit = 30;
    if ($limit > 100) $limit = 100;

    if ($reelId <= 0) {
        http_response_code(422);
        echo json_encode(['success' => false, 'message' => 'reel_id is required']);
        exit;
    }

    $sql = "SELECT c.id, c.reel_id, c.user_id, c.comment, c.created_at, u.firstName, u.lastName, u.profile_picture
            FROM reel_comments c
            INNER JOIN users u ON u.id = c.user_id
            WHERE c.reel_id = ? AND c.status = 'active'";

    $params = [$reelId];
    if ($cursorId > 0) {
        $sql .= ' AND c.id < ?';
        $params[] = $cursorId;
    }

    $sql .= ' ORDER BY c.id DESC LIMIT ' . $limit;

    $stmt = $pdo->prepare($sql);
    $stmt->execute($params);
    $rows = $stmt->fetchAll();

    $nextCursor = null;
    if (!empty($rows)) {
        $last = end($rows);
        $nextCursor = (int)($last['id'] ?? 0);
    }

    $data = array_map(static function(array $r) {
        return [
            'id' => (int)$r['id'],
            'reel_id' => (int)$r['reel_id'],
            'user_id' => (int)$r['user_id'],
            'user_name' => trim(($r['firstName'] ?? '') . ' ' . ($r['lastName'] ?? '')),
            'profile_picture' => (string)($r['profile_picture'] ?? ''),
            'comment' => (string)($r['comment'] ?? ''),
            'created_at' => (string)($r['created_at'] ?? ''),
        ];
    }, $rows);

    echo json_encode(['success' => true, 'data' => $data, 'next_cursor' => $nextCursor]);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['success' => false, 'message' => 'Method not allowed']);
    exit;
}

$input = json_decode(file_get_contents('php://input'), true) ?? [];
$userId = (int)($input['user_id'] ?? 0);
$reelId = (int)($input['reel_id'] ?? 0);
$comment = trim((string)($input['comment'] ?? ''));

if ($userId <= 0 || $reelId <= 0 || $comment === '') {
    http_response_code(422);
    echo json_encode(['success' => false, 'message' => 'user_id, reel_id and comment are required']);
    exit;
}

if (mb_strlen($comment) > 500) {
    http_response_code(422);
    echo json_encode(['success' => false, 'message' => 'Comment too long']);
    exit;
}

$matchedWords = [];
if (moderation_contains_prohibited_text($comment, $matchedWords)) {
    http_response_code(422);
    echo json_encode([
        'success' => false,
        'message' => 'Comment blocked by content safety policy',
        'reason' => 'sexual_text_detected',
        'matched_terms' => $matchedWords,
    ]);
    exit;
}

$stmt = $pdo->prepare("INSERT INTO reel_comments (reel_id, user_id, comment, status, created_at, updated_at) VALUES (?, ?, ?, 'active', NOW(), NOW())");
$stmt->execute([$reelId, $userId, $comment]);
$commentId = (int)$pdo->lastInsertId();

$countStmt = $pdo->prepare("SELECT COUNT(*) AS cnt FROM reel_comments WHERE reel_id = ? AND status = 'active'");
$countStmt->execute([$reelId]);
$commentCount = (int)($countStmt->fetch()['cnt'] ?? 0);

echo json_encode([
    'success' => true,
    'message' => 'Comment added',
    'data' => [
        'id' => $commentId,
        'reel_id' => $reelId,
        'user_id' => $userId,
        'comment' => $comment,
    ],
    'comment_count' => $commentCount,
]);
