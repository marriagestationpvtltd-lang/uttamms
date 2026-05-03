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
require_once __DIR__ . '/media_moderation_helper.php';

function ensure_admin_shadow_user(PDO $pdo, int $adminId, array $adminRow): int
{
    $markerEmail = '__admin_' . $adminId . '@admin.local';

    $findStmt = $pdo->prepare('SELECT id FROM users WHERE email = ? LIMIT 1');
    $findStmt->execute([$markerEmail]);
    $existing = $findStmt->fetch();
    if ($existing && isset($existing['id'])) {
        return (int)$existing['id'];
    }

    $displayName = trim((string)($adminRow['name'] ?? ('Admin ' . $adminId)));
    $parts = preg_split('/\s+/', $displayName) ?: [];
    $firstName = trim((string)($parts[0] ?? ('Admin' . $adminId)));
    $lastName = trim((string)implode(' ', array_slice($parts, 1)));

    $insertStmt = $pdo->prepare('INSERT INTO users (firstName, lastName, email, password, isDisable, isVerified) VALUES (?, ?, ?, ?, 0, 1)');
    $insertStmt->execute([$firstName, $lastName, $markerEmail, password_hash(bin2hex(random_bytes(8)), PASSWORD_BCRYPT)]);

    return (int)$pdo->lastInsertId();
}

$userId = isset($_POST['user_id']) ? (int)$_POST['user_id'] : 0;
$caption = trim((string)($_POST['caption'] ?? ''));
$privacy = trim((string)($_POST['privacy'] ?? 'public'));
$allowComments = isset($_POST['allow_comments']) ? (int)$_POST['allow_comments'] : 1;
$allowDownload = isset($_POST['allow_download']) ? (int)$_POST['allow_download'] : 0;
$allowDuet = isset($_POST['allow_duet']) ? (int)$_POST['allow_duet'] : 0;
$soundUrl   = trim((string)($_POST['sound_url'] ?? ''));
$soundTitle = substr(trim((string)($_POST['sound_title'] ?? '')), 0, 200);
$adminId = isset($_POST['admin_id']) ? (int)$_POST['admin_id'] : 0;
$asAdmin = isset($_POST['as_admin'])
    ? in_array(strtolower(trim((string)$_POST['as_admin'])), ['1', 'true', 'yes'], true)
    : ($adminId > 0);
$postAsAdminSelf = isset($_POST['post_as_admin_self'])
    ? in_array(strtolower(trim((string)$_POST['post_as_admin_self'])), ['1', 'true', 'yes'], true)
    : false;

if ($userId <= 0 && !$postAsAdminSelf) {
    http_response_code(422);
    echo json_encode(['success' => false, 'message' => 'user_id is required']);
    exit;
}

$allowedPrivacy = ['public', 'matches_only', 'private', 'paid_only', 'verified_only', 'paid', 'verified'];
if (!in_array($privacy, $allowedPrivacy, true)) {
    $privacy = 'public';
}

if ($asAdmin) {
    if ($adminId <= 0) {
        http_response_code(422);
        echo json_encode(['success' => false, 'message' => 'admin_id is required for admin upload']);
        exit;
    }

    $adminStmt = $pdo->prepare('SELECT id, name, email, is_active FROM admins WHERE id = ? LIMIT 1');
    $adminStmt->execute([$adminId]);
    $admin = $adminStmt->fetch();
    if (!$admin || (int)($admin['is_active'] ?? 0) !== 1) {
        http_response_code(403);
        echo json_encode(['success' => false, 'message' => 'Invalid or inactive admin']);
        exit;
    }

    if ($postAsAdminSelf) {
        $userId = ensure_admin_shadow_user($pdo, $adminId, $admin);
    }

    // Admin-uploaded reels must always be publicly visible.
    $privacy = 'public';
}

if (empty($_FILES['reel']) || $_FILES['reel']['error'] !== UPLOAD_ERR_OK) {
    http_response_code(422);
    echo json_encode(['success' => false, 'message' => 'reel video file is required']);
    exit;
}

$mime = mime_content_type($_FILES['reel']['tmp_name']);
$allowedMimes = [
    'video/mp4',
    'video/quicktime',   // iOS .mov
    'video/webm',
    'video/x-msvideo',   // .avi
    'video/x-matroska',  // .mkv
    'video/3gpp',        // Android 3GP
    'video/3gpp2',       // Android 3GP2
    'video/mpeg',        // MPEG
    'video/x-m4v',       // Apple M4V
    'video/mp2t',        // MPEG-TS
    'video/ogg',
    'application/octet-stream', // some devices/libs send generic binary
];
// Also allow by file extension as fallback (some servers return wrong MIME)
$ext = strtolower(pathinfo($_FILES['reel']['name'] ?? '', PATHINFO_EXTENSION));
$allowedExts = ['mp4', 'mov', 'webm', 'avi', 'mkv', '3gp', '3g2', 'mpeg', 'mpg', 'm4v', 'ts', 'ogg'];
if (!in_array($mime, $allowedMimes, true) && !in_array($ext, $allowedExts, true)) {
    http_response_code(422);
    echo json_encode(['success' => false, 'message' => 'Invalid video format. Supported: mp4, mov, webm, avi, mkv, 3gp']);
    exit;
}

$maxSize = 80 * 1024 * 1024; // 80MB
if (($_FILES['reel']['size'] ?? 0) > $maxSize) {
    http_response_code(422);
    echo json_encode(['success' => false, 'message' => 'Video too large (max 80MB)']);
    exit;
}

$userStmt = $pdo->prepare('SELECT id FROM users WHERE id = ? LIMIT 1');
$userStmt->execute([$userId]);
if (!$userStmt->fetch()) {
    http_response_code(422);
    echo json_encode([
        'success' => false,
        'message' => $asAdmin
            ? 'user_id must be a valid user ID from the users table (admin IDs are not valid here)'
            : 'User not found',
    ]);
    exit;
}

$matchedWords = [];
if (moderation_contains_prohibited_text($caption, $matchedWords)) {
    http_response_code(422);
    echo json_encode([
        'success' => false,
        'message' => 'Upload blocked by content safety policy',
        'reason' => 'sexual_text_detected',
        'matched_terms' => $matchedWords,
    ]);
    exit;
}

$uploadDir = __DIR__ . '/../../uploads/reels/';
if (!is_dir($uploadDir) && !mkdir($uploadDir, 0755, true) && !is_dir($uploadDir)) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Failed to create upload directory']);
    exit;
}

$ext = strtolower(pathinfo((string)($_FILES['reel']['name'] ?? ''), PATHINFO_EXTENSION));
if ($ext === '') {
    $ext = 'mp4';
}
$filename = 'reel_' . $userId . '_' . time() . '_' . mt_rand(1000, 9999) . '.' . $ext;
$destPath = $uploadDir . $filename;
$fileUrl = 'uploads/reels/' . $filename;  // relative to app root (no leading slash)

if (!move_uploaded_file($_FILES['reel']['tmp_name'], $destPath)) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Failed to save video']);
    exit;
}

try {
    $pdo->beginTransaction();

    $stmt = $pdo->prepare('INSERT INTO user_reels
        (user_id, video_url, thumbnail_url, sound_url, sound_title, caption, privacy, status, allow_comments, allow_duet, allow_download, moderation_status, moderation_confidence, created_at, updated_at)
        VALUES
        (:user_id, :video_url, :thumbnail_url, :sound_url, :sound_title, :caption, :privacy, :status, :allow_comments, :allow_duet, :allow_download, :moderation_status, :moderation_confidence, NOW(), NOW())');

    $stmt->execute([
        ':user_id' => $userId,
        ':video_url' => $fileUrl,
        ':thumbnail_url' => '',
        ':sound_url' => $soundUrl !== '' ? $soundUrl : null,
        ':sound_title' => $soundTitle !== '' ? $soundTitle : null,
        ':caption' => $caption,
        ':privacy' => $privacy,
        ':status' => 'active',
        ':allow_comments' => $allowComments ? 1 : 0,
        ':allow_duet' => $allowDuet ? 1 : 0,
        ':allow_download' => $allowDownload ? 1 : 0,
        ':moderation_status' => 'approved',
        ':moderation_confidence' => 0.99,
    ]);

    $reelId = (int)$pdo->lastInsertId();

    moderation_record_job(
        $pdo,
        'reel',
        $reelId,
        $userId,
        'approved',
        'approved',
        0.99,
        'local_text_filter',
        ['caption_length' => mb_strlen($caption)]
    );

    $pdo->commit();

    echo json_encode([
        'success' => true,
        'message' => 'Reel uploaded successfully',
        'data' => [
            'id' => $reelId,
            'video_url' => $fileUrl,
            'caption' => $caption,
            'privacy' => $privacy,
            'uploaded_by_admin' => $asAdmin,
            'status' => 'active',
        ],
    ]);
} catch (Throwable $e) {
    if ($pdo->inTransaction()) {
        $pdo->rollBack();
    }
    @unlink($destPath);
    error_log('upload_reel error: ' . $e->getMessage());
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Server error while uploading reel']);
}
