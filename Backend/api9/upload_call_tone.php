<?php
/**
 * upload_call_tone.php
 *
 * Admin endpoint to upload a custom call ringtone for the entire application.
 * The file is stored on the server and the global app_settings table is updated
 * with the new custom tone URL.
 *
 * POST multipart/form-data:
 *   file (audio file) – required – mp3, aac, ogg, wav, m4a, webm (max 5 MB)
 *
 * Response:
 *   {
 *     "success": true,
 *     "data": {
 *       "call_tone_id":         "custom",
 *       "custom_call_tone_url":  "/uploads/admin_tones/tone_<timestamp>.<ext>",
 *       "custom_call_tone_name": "<original filename without extension>"
 *     }
 *   }
 */

ini_set('display_errors', 1);
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

require_once __DIR__ . '/auth.php';
requireAdminAuth();

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['success' => false, 'message' => 'Method not allowed']);
    exit;
}

// ── DB credentials ────────────────────────────────────────────────────────────
$dbHost = 'localhost';
$dbName = 'ms';
$dbUser = 'ms';
$dbPass = 'ms';

// ── Validate uploaded file ────────────────────────────────────────────────────
if (!isset($_FILES['file']) || $_FILES['file']['error'] !== UPLOAD_ERR_OK) {
    $uploadErrors = [
        UPLOAD_ERR_INI_SIZE   => 'File exceeds server upload limit',
        UPLOAD_ERR_FORM_SIZE  => 'File exceeds form upload limit',
        UPLOAD_ERR_PARTIAL    => 'File only partially uploaded',
        UPLOAD_ERR_NO_FILE    => 'No file was uploaded',
        UPLOAD_ERR_NO_TMP_DIR => 'Server tmp directory missing',
        UPLOAD_ERR_CANT_WRITE => 'Failed to write file to disk',
        UPLOAD_ERR_EXTENSION  => 'Upload stopped by PHP extension',
    ];
    $code    = isset($_FILES['file']['error']) ? $_FILES['file']['error'] : UPLOAD_ERR_NO_FILE;
    $message = isset($uploadErrors[$code])     ? $uploadErrors[$code]     : 'Upload error';
    http_response_code(422);
    echo json_encode(['success' => false, 'message' => $message]);
    exit;
}

// Allowed MIME types (includes webm for Flutter Web compatibility)
$allowedMimes = [
    'audio/mpeg', 'audio/mp3', 'audio/aac', 'audio/ogg',
    'audio/wav', 'audio/x-wav', 'audio/mp4', 'audio/x-m4a', 'audio/m4a',
    'audio/webm', 'audio/x-ms-wma',
];

// Derive extension early so we can use it as a fallback for MIME detection
$originalName = basename($_FILES['file']['name']);
$ext          = strtolower(pathinfo($originalName, PATHINFO_EXTENSION));
$allowedExts  = ['mp3', 'aac', 'ogg', 'wav', 'm4a', 'webm', 'mp4'];

// Use mime_content_type() when available; fall back to extension-based check
if (function_exists('mime_content_type')) {
    $fileMime = mime_content_type($_FILES['file']['tmp_name']);
    if ($fileMime === false || !in_array($fileMime, $allowedMimes, true)) {
        error_log('upload_call_tone: rejected MIME type: ' . var_export($fileMime, true));
        http_response_code(422);
        echo json_encode(['success' => false, 'message' => 'Invalid file type. Allowed: mp3, aac, ogg, wav, m4a, webm']);
        exit;
    }
} else {
    error_log('upload_call_tone: mime_content_type() unavailable, falling back to extension check');
    if (!in_array($ext, $allowedExts, true)) {
        http_response_code(422);
        echo json_encode(['success' => false, 'message' => 'Invalid file type. Allowed: mp3, aac, ogg, wav, m4a, webm']);
        exit;
    }
}

// Max 5 MB
if ($_FILES['file']['size'] > 5 * 1024 * 1024) {
    http_response_code(422);
    echo json_encode(['success' => false, 'message' => 'File too large. Maximum size is 5 MB.']);
    exit;
}

// ── Connect to DB first (before moving file to avoid orphaned uploads) ────────
try {
    $pdo = new PDO(
        'mysql:host=' . $dbHost . ';dbname=' . $dbName . ';charset=utf8mb4',
        $dbUser,
        $dbPass,
        [
            PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES   => false,
        ]
    );
} catch (PDOException $e) {
    error_log('upload_call_tone DB connect error: ' . $e->getMessage());
    http_response_code(503);
    echo json_encode(['success' => false, 'message' => 'Database connection failed. Please try again.']);
    exit;
}

// ── Save file ─────────────────────────────────────────────────────────────────
$uploadDir = __DIR__ . '/../../uploads/admin_tones/';
if (!is_dir($uploadDir)) {
    if (!mkdir($uploadDir, 0755, true) && !is_dir($uploadDir)) {
        error_log('upload_call_tone: failed to create upload directory: ' . $uploadDir);
        http_response_code(500);
        echo json_encode(['success' => false, 'message' => 'Server configuration error. Please contact support.']);
        exit;
    }
}

if (!in_array($ext, $allowedExts, true)) {
    $ext = 'mp3';
}

$filename = 'admin_tone_' . time() . '_' . bin2hex(random_bytes(4)) . '.' . $ext;
$destPath = $uploadDir . $filename;

if (!move_uploaded_file($_FILES['file']['tmp_name'], $destPath)) {
    error_log('upload_call_tone: failed to move file to ' . $destPath);
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Failed to save file. Please try again.']);
    exit;
}

$fileUrl   = '/uploads/admin_tones/' . $filename;
$toneName  = pathinfo($originalName, PATHINFO_FILENAME);

// ── Persist settings in DB ────────────────────────────────────────────────────
try {
    $pdo->exec("
        CREATE TABLE IF NOT EXISTS app_settings (
            `setting_key`   VARCHAR(100) NOT NULL PRIMARY KEY,
            `setting_value` TEXT,
            updated_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ");

    $upsert = $pdo->prepare(
        "INSERT INTO app_settings (setting_key, setting_value) VALUES (?, ?)
         ON DUPLICATE KEY UPDATE setting_value = VALUES(setting_value)"
    );
    $upsert->execute(['call_tone_id',          'custom']);
    $upsert->execute(['custom_call_tone_url',   $fileUrl]);
    $upsert->execute(['custom_call_tone_name',  $toneName]);

    echo json_encode([
        'success' => true,
        'message' => 'Custom call tone uploaded successfully',
        'data'    => [
            'call_tone_id'          => 'custom',
            'custom_call_tone_url'  => $fileUrl,
            'custom_call_tone_name' => $toneName,
        ],
    ]);

} catch (PDOException $e) {
    error_log('upload_call_tone DB error: ' . $e->getMessage());
    // Roll back the file we just saved to avoid orphaned files
    @unlink($destPath);
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Server error. Please try again.']);
}
