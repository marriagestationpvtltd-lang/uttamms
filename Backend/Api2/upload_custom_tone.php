<?php
/**
 * upload_custom_tone.php
 *
 * Let a user upload their own ringtone file.
 * The file is saved on the server and the user's call settings row is
 * updated (or created) to point to the new custom tone.
 *
 * POST multipart/form-data:
 *   user_id  (int)  – required
 *   tone     (file) – required  audio file (mp3, aac, ogg, wav, m4a)
 *
 * The endpoint automatically sets is_custom = 1 after a successful upload.
 *
 * To delete the custom tone the client should call call_settings.php with
 * is_custom=false, then optionally call this endpoint again with a new file.
 */

ini_set('display_errors', 0);
ini_set('log_errors', 1);
error_reporting(E_ALL);

header('Content-Type: application/json');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

require_once __DIR__ . '/db_config.php';

// --------------------------------------------------------------------------
// Validation
// --------------------------------------------------------------------------

$user_id = isset($_POST['user_id']) ? (int) $_POST['user_id'] : 0;

if ($user_id <= 0) {
    echo json_encode(['success' => false, 'message' => 'user_id is required']);
    exit;
}

if (empty($_FILES['tone']) || $_FILES['tone']['error'] !== UPLOAD_ERR_OK) {
    $uploadErrors = [
        UPLOAD_ERR_INI_SIZE   => 'File exceeds server upload limit',
        UPLOAD_ERR_FORM_SIZE  => 'File exceeds form upload limit',
        UPLOAD_ERR_PARTIAL    => 'File only partially uploaded',
        UPLOAD_ERR_NO_FILE    => 'No file was uploaded',
        UPLOAD_ERR_NO_TMP_DIR => 'Server tmp directory missing',
        UPLOAD_ERR_CANT_WRITE => 'Failed to write file to disk',
        UPLOAD_ERR_EXTENSION  => 'Upload stopped by PHP extension',
    ];
    $code    = $_FILES['tone']['error'] ?? UPLOAD_ERR_NO_FILE;
    $message = $uploadErrors[$code] ?? 'Upload error';
    echo json_encode(['success' => false, 'message' => $message]);
    exit;
}

// Allowed audio MIME types
$allowedMimes = ['audio/mpeg', 'audio/mp3', 'audio/aac', 'audio/ogg', 'audio/wav',
                 'audio/x-wav', 'audio/mp4', 'audio/x-m4a', 'audio/m4a'];

$fileMime = mime_content_type($_FILES['tone']['tmp_name']);
if (!in_array($fileMime, $allowedMimes, true)) {
    echo json_encode(['success' => false, 'message' => 'Invalid file type. Allowed: mp3, aac, ogg, wav, m4a']);
    exit;
}

// Max 5 MB
$maxSize = 5 * 1024 * 1024;
if ($_FILES['tone']['size'] > $maxSize) {
    echo json_encode(['success' => false, 'message' => 'File too large. Maximum size is 5 MB.']);
    exit;
}

// --------------------------------------------------------------------------
// Save file
// --------------------------------------------------------------------------

$uploadDir = __DIR__ . '/../../uploads/custom_tones/';
if (!is_dir($uploadDir)) {
    mkdir($uploadDir, 0755, true);
}

// Derive a safe extension from the original name
$originalName = basename($_FILES['tone']['name']);
$ext          = strtolower(pathinfo($originalName, PATHINFO_EXTENSION));
$allowedExts  = ['mp3', 'aac', 'ogg', 'wav', 'm4a'];
if (!in_array($ext, $allowedExts, true)) {
    $ext = 'mp3'; // fallback
}

// Unique filename: user_<id>_<timestamp>.<ext>
$filename = 'user_' . $user_id . '_' . time() . '.' . $ext;
$destPath = $uploadDir . $filename;

if (!move_uploaded_file($_FILES['tone']['tmp_name'], $destPath)) {
    error_log('upload_custom_tone: failed to move file to ' . $destPath);
    echo json_encode(['success' => false, 'message' => 'Failed to save file. Please try again.']);
    exit;
}

$fileUrl  = '/uploads/custom_tones/' . $filename;
$toneName = pathinfo($originalName, PATHINFO_FILENAME);

// --------------------------------------------------------------------------
// Update user_call_settings
// --------------------------------------------------------------------------

try {
    $stmt = $pdo->prepare("
        INSERT INTO user_call_settings
            (user_id, custom_tone_url, custom_tone_name, is_custom)
        VALUES
            (:user_id, :url, :name, 1)
        ON DUPLICATE KEY UPDATE
            custom_tone_url  = :url,
            custom_tone_name = :name,
            is_custom        = 1,
            updated_at       = NOW()
    ");
    $stmt->execute([
        ':user_id' => $user_id,
        ':url'     => $fileUrl,
        ':name'    => $toneName,
    ]);

    echo json_encode([
        'success'          => true,
        'message'          => 'Custom tone uploaded successfully',
        'custom_tone_url'  => $fileUrl,
        'custom_tone_name' => $toneName,
    ]);

} catch (PDOException $e) {
    error_log('upload_custom_tone DB error: ' . $e->getMessage());
    // Roll back the file we just saved to avoid orphaned files
    @unlink($destPath);
    echo json_encode(['success' => false, 'message' => 'Server error. Please try again.']);
}
