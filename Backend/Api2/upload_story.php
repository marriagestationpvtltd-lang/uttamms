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
    // Admin-uploaded stories are always public.
    $privacy = 'public';
}

// Validate that user_id exists in users (required by FK constraint).
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

if (empty($_FILES['story']) || $_FILES['story']['error'] !== UPLOAD_ERR_OK) {
    http_response_code(422);
    echo json_encode(['success' => false, 'message' => 'story file is required']);
    exit;
}

$mime = mime_content_type($_FILES['story']['tmp_name']);
$imageMimes = ['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif'];
$videoMimes = [
    'video/mp4', 'video/quicktime', 'video/webm',
    'video/x-msvideo', 'video/x-matroska',
    'video/3gpp', 'video/3gpp2', 'video/mpeg',
    'video/x-m4v', 'application/octet-stream',
];
$ext = strtolower(pathinfo($_FILES['story']['name'] ?? '', PATHINFO_EXTENSION));
$imageExts = ['jpg', 'jpeg', 'png', 'webp', 'heic', 'heif'];
$videoExts = ['mp4', 'mov', 'webm', 'avi', 'mkv', '3gp', '3g2', 'mpeg', 'mpg', 'm4v'];
$isImage = in_array($mime, $imageMimes, true) || in_array($ext, $imageExts, true);
$isVideo = in_array($mime, $videoMimes, true) || in_array($ext, $videoExts, true);

if (!$isImage && !$isVideo) {
    http_response_code(422);
    echo json_encode(['success' => false, 'message' => 'Invalid story file type. Supported: jpg, png, webp, mp4, mov, webm, 3gp']);
    exit;
}

$maxSize = $isImage ? (15 * 1024 * 1024) : (60 * 1024 * 1024);
if (($_FILES['story']['size'] ?? 0) > $maxSize) {
    http_response_code(422);
    echo json_encode(['success' => false, 'message' => 'Story file too large']);
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

$subDir = $isImage ? 'stories/images/' : 'stories/videos/';
$uploadDir = __DIR__ . '/../../uploads/' . $subDir;
if (!is_dir($uploadDir) && !mkdir($uploadDir, 0755, true) && !is_dir($uploadDir)) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Failed to create upload directory']);
    exit;
}

$ext = strtolower(pathinfo((string)($_FILES['story']['name'] ?? ''), PATHINFO_EXTENSION));
if ($ext === '') {
    $ext = $isImage ? 'jpg' : 'mp4';
}
$filename = 'story_' . $userId . '_' . time() . '_' . mt_rand(1000, 9999) . '.' . $ext;
$destPath = $uploadDir . $filename;
$fileUrl = 'uploads/' . $subDir . $filename;  // relative to app root (no leading slash)

if (!move_uploaded_file($_FILES['story']['tmp_name'], $destPath)) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Failed to save story file']);
    exit;
}

try {
    $pdo->beginTransaction();

    $stmt = $pdo->prepare('INSERT INTO user_stories
        (user_id, media_type, media_url, thumbnail_url, caption, privacy, status, moderation_status, moderation_confidence, expires_at, created_at, updated_at)
        VALUES
        (:user_id, :media_type, :media_url, :thumbnail_url, :caption, :privacy, :status, :moderation_status, :moderation_confidence, DATE_ADD(NOW(), INTERVAL 24 HOUR), NOW(), NOW())');

    $stmt->execute([
        ':user_id' => $userId,
        ':media_type' => $isImage ? 'image' : 'video',
        ':media_url' => $fileUrl,
        ':thumbnail_url' => '',
        ':caption' => $caption,
        ':privacy' => $privacy,
        ':status' => 'active',
        ':moderation_status' => 'approved',
        ':moderation_confidence' => 0.99,
    ]);

    $storyId = (int)$pdo->lastInsertId();

    moderation_record_job(
        $pdo,
        'story',
        $storyId,
        $userId,
        'approved',
        'approved',
        0.99,
        'local_text_filter',
        ['media_type' => $isImage ? 'image' : 'video']
    );

    $pdo->commit();

    echo json_encode([
        'success' => true,
        'message' => 'Story uploaded successfully',
        'data' => [
            'id' => $storyId,
            'media_url' => $fileUrl,
            'media_type' => $isImage ? 'image' : 'video',
            'expires_in_hours' => 24,
            'status' => 'active',
        ],
    ]);
} catch (Throwable $e) {
    if ($pdo->inTransaction()) {
        $pdo->rollBack();
    }
    @unlink($destPath);
    error_log('upload_story error: ' . $e->getMessage());
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Server error while uploading story']);
}
