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

require_once __DIR__ . '/db_config.php';

$_scheme   = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') ? 'https' : 'http';
$_host     = $_SERVER['HTTP_HOST'] ?? '192.168.18.208';
$_spath    = parse_url($_SERVER['REQUEST_URI'] ?? '/uttamms/Backend/Api2/get_user_stories.php', PHP_URL_PATH);
$_sdir     = dirname($_spath ?: '/uttamms/Backend/Api2/get_user_stories.php');
$_appRoot  = rtrim(dirname(dirname($_sdir)), '/');
$_mediaBase = $_scheme . '://' . $_host . $_appRoot . '/';

function _storyMediaUrl(string $stored, string $base): string {
    if ($stored === '') return '';
    if (preg_match('#^https?://#i', $stored)) return $stored;
    return $base . ltrim($stored, '/');
}

$viewerId     = isset($_GET['user_id'])        ? (int)$_GET['user_id']        : 0;
$targetUserId = isset($_GET['target_user_id']) ? (int)$_GET['target_user_id'] : 0;
$asAdmin      = !empty($_GET['as_admin'])      && (string)($_GET['as_admin'] ?? '') === '1';

if ($targetUserId <= 0) {
    $targetUserId = $viewerId;
}

// Admin mode with no specific user: return all recent stories across all users.
if ($asAdmin && $targetUserId <= 0) {
    $allStmt = $pdo->prepare(
        "SELECT s.id, s.user_id, s.media_type, s.media_url,
                COALESCE(s.thumbnail_url, '') AS thumbnail_url,
                COALESCE(s.caption, '') AS caption,
                COALESCE(s.privacy, 'public') AS privacy,
                s.created_at, s.expires_at
         FROM user_stories s
         WHERE s.status = 'active'
         ORDER BY s.created_at DESC
         LIMIT 50"
    );
    $allStmt->execute();
    $allRows = $allStmt->fetchAll();
    $allData = array_map(static function(array $r) use ($_mediaBase) {
        return [
            'id'            => (int)$r['id'],
            'user_id'       => (int)$r['user_id'],
            'media_type'    => (string)($r['media_type']    ?? 'image'),
            'media_url'     => _storyMediaUrl((string)($r['media_url']     ?? ''), $_mediaBase),
            'thumbnail_url' => _storyMediaUrl((string)($r['thumbnail_url'] ?? ''), $_mediaBase),
            'caption'       => (string)($r['caption']  ?? ''),
            'privacy'       => (string)($r['privacy']  ?? 'public'),
            'created_at'    => (string)($r['created_at'] ?? ''),
            'expires_at'    => (string)($r['expires_at']  ?? ''),
        ];
    }, $allRows);
    echo json_encode(['success' => true, 'data' => ['stories' => $allData]]);
    exit;
}

if ($targetUserId <= 0) {
    http_response_code(422);
    echo json_encode(['success' => false, 'message' => 'target_user_id is required']);
    exit;
}

$targetStmt = $pdo->prepare('SELECT id, firstName, lastName, profile_picture FROM users WHERE id = ? LIMIT 1');
$targetStmt->execute([$targetUserId]);
$target = $targetStmt->fetch();
if (!$target) {
    http_response_code(404);
    echo json_encode(['success' => false, 'message' => 'User not found']);
    exit;
}

$viewerIsPaid = false;
$viewerIsVerified = false;
if ($viewerId > 0) {
    $viewerStmt = $pdo->prepare('SELECT usertype, isVerified FROM users WHERE id = ? LIMIT 1');
    $viewerStmt->execute([$viewerId]);
    $viewer = $viewerStmt->fetch();
    if ($viewer) {
        $viewerType = strtolower(trim((string)($viewer['usertype'] ?? '')));
        $viewerIsPaid = $viewerType === 'paid' || $viewerType === 'premium' || $viewerType === 'gold' || $viewerType === 'platinum';
        $viewerIsVerified = !empty($viewer['isVerified']);
    }
}

$where = [
    's.user_id = ?',
    "s.status = 'active'",
    's.expires_at > NOW()',
];
$params = [$targetUserId];

if ($viewerId === $targetUserId && $viewerId > 0) {
    // Owner can see own active stories regardless of privacy.
} elseif ($asAdmin) {
    // Admin bypass: no privacy filter.
} elseif ($viewerId > 0) {
    $where[] = "(
        s.privacy = 'public'
        OR (
            s.privacy = 'matches_only' AND EXISTS (
                SELECT 1 FROM proposals p
                WHERE (
                    (p.sender_id = ? AND p.receiver_id = s.user_id)
                    OR
                    (p.sender_id = s.user_id AND p.receiver_id = ?)
                )
                AND p.status = 'accepted'
            )
        )
        OR ((s.privacy = 'paid_only' OR s.privacy = 'paid') AND ? = 1)
        OR ((s.privacy = 'verified_only' OR s.privacy = 'verified') AND ? = 1)
    )";
    $params[] = $viewerId;
    $params[] = $viewerId;
    $params[] = $viewerIsPaid ? 1 : 0;
    $params[] = $viewerIsVerified ? 1 : 0;
} else {
    $where[] = "s.privacy = 'public'";
}

$sql = "SELECT
            s.id,
            s.user_id,
            s.media_type,
            s.media_url,
            COALESCE(s.thumbnail_url, '') AS thumbnail_url,
            COALESCE(s.caption, '') AS caption,
            COALESCE(s.privacy, 'public') AS privacy,
            s.created_at,
            s.expires_at
        FROM user_stories s
        WHERE " . implode(' AND ', $where) . "
        ORDER BY s.created_at DESC
        LIMIT 30";

$stmt = $pdo->prepare($sql);
$stmt->execute($params);
$rows = $stmt->fetchAll();

$data = array_map(static function(array $r) {
    return [
        'id' => (int)$r['id'],
        'user_id' => (int)$r['user_id'],
        'media_type' => (string)($r['media_type'] ?? 'image'),
        'media_url' => _storyMediaUrl((string)($r['media_url'] ?? ''), $GLOBALS['_mediaBase']),
        'thumbnail_url' => _storyMediaUrl((string)($r['thumbnail_url'] ?? ''), $GLOBALS['_mediaBase']),
        'caption' => (string)($r['caption'] ?? ''),
        'privacy' => (string)($r['privacy'] ?? 'public'),
        'created_at' => (string)($r['created_at'] ?? ''),
        'expires_at' => (string)($r['expires_at'] ?? ''),
    ];
}, $rows);

echo json_encode([
    'success' => true,
    'data' => [
        'user' => [
            'id' => (int)$target['id'],
            'name' => trim((string)($target['firstName'] ?? '') . ' ' . (string)($target['lastName'] ?? '')),
            'profile_picture' => _storyMediaUrl((string)($target['profile_picture'] ?? ''), $GLOBALS['_mediaBase']),
        ],
        'stories' => $data,
    ],
]);
