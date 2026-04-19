<?php
/**
 * upload_ringtone.php  (admin)
 *
 * Admin uploads a ringtone audio file.
 * Returns the saved file URL; the admin then calls ringtones.php (POST)
 * with that URL to create the ringtone record.
 *
 * POST multipart/form-data:
 *   ringtone (file) – required  audio file (mp3, aac, ogg, wav, m4a)
 */

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

require_once __DIR__ . '/../Api2/db_config.php';
require_once __DIR__ . '/auth.php';

// --------------------------------------------------------------------------
// Validation
// --------------------------------------------------------------------------

if (empty($_FILES['ringtone']) || $_FILES['ringtone']['error'] !== UPLOAD_ERR_OK) {
    $uploadErrors = [
        UPLOAD_ERR_INI_SIZE   => 'File exceeds server upload limit',
        UPLOAD_ERR_FORM_SIZE  => 'File exceeds form upload limit',
        UPLOAD_ERR_PARTIAL    => 'File only partially uploaded',
        UPLOAD_ERR_NO_FILE    => 'No file was uploaded',
        UPLOAD_ERR_NO_TMP_DIR => 'Server tmp directory missing',
        UPLOAD_ERR_CANT_WRITE => 'Failed to write file to disk',
        UPLOAD_ERR_EXTENSION  => 'Upload stopped by PHP extension',
    ];
    $code    = $_FILES['ringtone']['error'] ?? UPLOAD_ERR_NO_FILE;
    $message = $uploadErrors[$code] ?? 'Upload error';
    echo json_encode(['success' => false, 'message' => $message]);
    exit;
}

// Allowed MIME types
$allowedMimes = ['audio/mpeg', 'audio/mp3', 'audio/aac', 'audio/ogg', 'audio/wav',
                 'audio/x-wav', 'audio/mp4', 'audio/x-m4a', 'audio/m4a'];

$fileMime = mime_content_type($_FILES['ringtone']['tmp_name']);
if (!in_array($fileMime, $allowedMimes, true)) {
    echo json_encode(['success' => false, 'message' => 'Invalid file type. Allowed: mp3, aac, ogg, wav, m4a']);
    exit;
}

// Max 10 MB for admin uploads
$maxSize = 10 * 1024 * 1024;
if ($_FILES['ringtone']['size'] > $maxSize) {
    echo json_encode(['success' => false, 'message' => 'File too large. Maximum size is 10 MB.']);
    exit;
}

// --------------------------------------------------------------------------
// Save file
// --------------------------------------------------------------------------

$uploadDir = __DIR__ . '/../../uploads/ringtones/';
if (!is_dir($uploadDir)) {
    mkdir($uploadDir, 0755, true);
}

$originalName = basename($_FILES['ringtone']['name']);
$ext          = strtolower(pathinfo($originalName, PATHINFO_EXTENSION));
$allowedExts  = ['mp3', 'aac', 'ogg', 'wav', 'm4a'];
if (!in_array($ext, $allowedExts, true)) {
    $ext = 'mp3';
}

// Keep a sanitised version of the original name in the filename
$safeName = preg_replace('/[^a-zA-Z0-9_-]/', '_', pathinfo($originalName, PATHINFO_FILENAME));
$safeName = substr($safeName, 0, 50);
$filename = $safeName . '_' . time() . '.' . $ext;
$destPath = $uploadDir . $filename;

if (!move_uploaded_file($_FILES['ringtone']['tmp_name'], $destPath)) {
    error_log('admin/upload_ringtone: failed to move file to ' . $destPath);
    echo json_encode(['success' => false, 'message' => 'Failed to save file. Please try again.']);
    exit;
}

$fileUrl = '/uploads/ringtones/' . $filename;

echo json_encode([
    'success'      => true,
    'message'      => 'File uploaded successfully',
    'file_url'     => $fileUrl,
    'original_name'=> pathinfo($originalName, PATHINFO_FILENAME),
]);
