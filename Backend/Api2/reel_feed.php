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

// Build media base URL: http://host/uttamms/
$_scheme   = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') ? 'https' : 'http';
$_host     = $_SERVER['HTTP_HOST'] ?? '192.168.18.208';
$_spath    = parse_url($_SERVER['REQUEST_URI'] ?? '/uttamms/Backend/Api2/reel_feed.php', PHP_URL_PATH);
$_sdir     = dirname($_spath ?: '/uttamms/Backend/Api2/reel_feed.php'); // /uttamms/Backend/Api2
$_appRoot  = rtrim(dirname(dirname($_sdir)), '/');                       // /uttamms
$_mediaBase = $_scheme . '://' . $_host . $_appRoot . '/';               // http://host/uttamms/

function _reelMediaUrl(string $stored, string $base): string {
    if ($stored === '') return '';
    if (preg_match('#^https?://#i', $stored)) return $stored;
    return $base . ltrim($stored, '/');
}

$userId   = isset($_GET['user_id'])   ? (int)$_GET['user_id']   : 0;
$asAdmin  = !empty($_GET['as_admin']) && (string)($_GET['as_admin'] ?? '') === '1';
$cursorId  = isset($_GET['cursor_id'])  ? (int)$_GET['cursor_id']  : 0;
$offset    = isset($_GET['offset'])     ? (int)$_GET['offset']     : 0;
$sort      = in_array($_GET['sort'] ?? '', ['trending', 'recent'], true) ? $_GET['sort'] : 'recent';
$limit     = isset($_GET['limit'])      ? (int)$_GET['limit']      : 20;
if ($limit <= 0) $limit = 20;
if ($limit > 50) $limit = 50;

$viewerIsPaid = false;
$viewerIsVerified = false;
if ($userId > 0) {
    $viewerStmt = $pdo->prepare('SELECT usertype, isVerified FROM users WHERE id = ? LIMIT 1');
    $viewerStmt->execute([$userId]);
    $viewer = $viewerStmt->fetch();
    if ($viewer) {
        $viewerType = strtolower(trim((string)($viewer['usertype'] ?? '')));
        $viewerIsPaid = $viewerType === 'paid' || $viewerType === 'premium' || $viewerType === 'gold' || $viewerType === 'platinum';
        $viewerIsVerified = !empty($viewer['isVerified']);
    }
}

$whereParts = ["r.status = 'active'"];
$params = [];

// Cursor only used for 'recent' sort
if ($sort === 'recent' && $cursorId > 0) {
    $whereParts[] = 'r.id < ?';
    $params[] = $cursorId;
}

if (!$asAdmin) {
    if ($userId > 0) {
        // Exclude blocked users in both directions.
        $whereParts[] = 'NOT EXISTS (
            SELECT 1 FROM blocks b
            WHERE (b.blocker_id = ? AND b.blocked_id = r.user_id)
               OR (b.blocker_id = r.user_id AND b.blocked_id = ?)
        )';
        $params[] = $userId;
        $params[] = $userId;

        // Privacy visibility.
        $whereParts[] = "(
            r.user_id = ?
            OR r.privacy = 'public'
            OR (
                r.privacy = 'matches_only' AND EXISTS (
                    SELECT 1 FROM proposals p
                    WHERE (
                        (p.sender_id = ? AND p.receiver_id = r.user_id)
                        OR
                        (p.sender_id = r.user_id AND p.receiver_id = ?)
                    )
                    AND p.status = 'accepted'
                )
            )
            OR ((r.privacy = 'paid_only' OR r.privacy = 'paid') AND ? = 1)
            OR ((r.privacy = 'verified_only' OR r.privacy = 'verified') AND ? = 1)
        )";
        $params[] = $userId;
        $params[] = $userId;
        $params[] = $userId;
        $params[] = $viewerIsPaid ? 1 : 0;
        $params[] = $viewerIsVerified ? 1 : 0;
    } else {
        $whereParts[] = "r.privacy = 'public'";
    }
    // When $asAdmin=true: no block/privacy filter — admin sees everything.
}

$whereSql = implode(' AND ', $whereParts);

$sql = "SELECT
            r.id,
            r.user_id,
            r.video_url,
            r.thumbnail_url,
            COALESCE(r.sound_url, '') AS sound_url,
            COALESCE(r.sound_title, '') AS sound_title,
            r.caption,
            r.privacy,
            r.allow_comments,
            r.allow_duet,
            r.allow_download,
            r.created_at,
            u.firstName,
            u.lastName,
            u.profile_picture,
            COALESCE((SELECT COUNT(*) FROM reel_likes rl WHERE rl.reel_id = r.id), 0) AS like_count,
            COALESCE((SELECT COUNT(*) FROM reel_comments rc WHERE rc.reel_id = r.id AND rc.status = 'active'), 0) AS comment_count,
            COALESCE(r.view_count, 0) AS view_count,
            COALESCE((SELECT COUNT(*) FROM reel_shares rs WHERE rs.reel_id = r.id), 0) AS share_count";

if ($userId > 0) {
    $sql .= ", CASE WHEN EXISTS (
                SELECT 1 FROM reel_likes mrl WHERE mrl.reel_id = r.id AND mrl.user_id = ?
            ) THEN 1 ELSE 0 END AS my_like";
}

$_orderBy = $sort === 'trending'
    ? '(like_count * 3 + share_count * 2 + comment_count) DESC, r.id DESC'
    : 'r.id DESC';

// For trending we use OFFSET; for recent we used cursor above.
$_pagination = $sort === 'trending'
    ? "LIMIT $limit OFFSET $offset"
    : "LIMIT $limit";

$sql .= "
        FROM user_reels r
        INNER JOIN users u ON u.id = r.user_id
        WHERE $whereSql
        ORDER BY $_orderBy
        $_pagination";

if ($userId > 0) {
    array_unshift($params, $userId);
}

$stmt = $pdo->prepare($sql);
$stmt->execute($params);
$rows = $stmt->fetchAll();

$nextCursor = null;
$nextOffset = null;
if (!empty($rows)) {
    if ($sort === 'recent') {
        $last = end($rows);
        $nextCursor = (int)($last['id'] ?? 0);
    } else {
        $nextOffset = $offset + count($rows);
    }
}

$data = array_map(static function(array $r) {
    return [
        'id' => (int)$r['id'],
        'user_id' => (int)$r['user_id'],
        'user_name' => trim('ID ' . (int)$r['user_id'] . ' ' . ($r['lastName'] ?? '')),
        'profile_picture' => (string)($r['profile_picture'] ?? ''),
        'video_url' => _reelMediaUrl((string)($r['video_url'] ?? ''), $GLOBALS['_mediaBase']),
        'thumbnail_url' => _reelMediaUrl((string)($r['thumbnail_url'] ?? ''), $GLOBALS['_mediaBase']),
        'sound_url' => _reelMediaUrl((string)($r['sound_url'] ?? ''), $GLOBALS['_mediaBase']),
        'sound_title' => (string)($r['sound_title'] ?? ''),
        'caption' => (string)($r['caption'] ?? ''),
        'privacy' => (string)($r['privacy'] ?? 'public'),
        'allow_comments' => (int)($r['allow_comments'] ?? 1) === 1,
        'allow_duet' => (int)($r['allow_duet'] ?? 0) === 1,
        'allow_download' => (int)($r['allow_download'] ?? 0) === 1,
        'like_count' => (int)($r['like_count'] ?? 0),
        'comment_count' => (int)($r['comment_count'] ?? 0),
        'view_count'   => (int)($r['view_count']  ?? 0),
        'share_count'  => (int)($r['share_count'] ?? 0),
        'my_like'      => (int)($r['my_like']     ?? 0) === 1,
        'created_at' => (string)($r['created_at'] ?? ''),
    ];
}, $rows);

echo json_encode([
    'success' => true,
    'data' => $data,
    'sort' => $sort,
    'next_cursor' => $nextCursor,
    'next_offset' => $nextOffset,
    'count' => count($data),
]);
