<?php
/**
 * upload_sound_tone.php
 *
 * Admin endpoint to upload custom app sound tones (incoming call / message / typing).
 *
 * POST multipart/form-data:
 *   tone      (audio file) - required - mp3, mp4, aac, ogg, wav, m4a, webm (max 5 MB)
 *   tone_type (string)     - required - incoming_call | message | typing
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

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['success' => false, 'message' => 'Method not allowed']);
    exit;
}

define('DB_HOST', 'localhost');
define('DB_NAME', 'ms');
define('DB_USER', 'root');
define('DB_PASS', '');

$toneType = isset($_POST['tone_type']) ? trim((string) $_POST['tone_type']) : '';
$allowedTypes = ['incoming_call', 'message', 'typing'];

if (!in_array($toneType, $allowedTypes, true)) {
    http_response_code(422);
    echo json_encode([
        'success' => false,
        'message' => 'Invalid tone_type. Allowed: incoming_call, message, typing',
    ]);
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
    http_response_code(422);
    echo json_encode(['success' => false, 'message' => $message]);
    exit;
}

$allowedMimes = [
    'audio/mpeg', 'audio/mp3', 'audio/aac', 'audio/ogg',
    'audio/wav', 'audio/x-wav', 'audio/mp4', 'audio/x-m4a', 'audio/m4a',
    'audio/webm', 'video/webm', 'application/octet-stream',
];

$fileMime = null;
$tmpName = $_FILES['tone']['tmp_name'] ?? '';

if ($tmpName !== '' && function_exists('mime_content_type')) {
    $detected = @mime_content_type($tmpName);
    if (is_string($detected) && $detected !== '') {
        $fileMime = $detected;
    }
}

if (($fileMime === null || $fileMime === '') && function_exists('finfo_open') && $tmpName !== '') {
    $finfo = @finfo_open(FILEINFO_MIME_TYPE);
    if ($finfo !== false) {
        $detected = @finfo_file($finfo, $tmpName);
        @finfo_close($finfo);
        if (is_string($detected) && $detected !== '') {
            $fileMime = $detected;
        }
    }
}

if ($fileMime === null || $fileMime === '') {
    $reportedMime = $_FILES['tone']['type'] ?? null;
    if (is_string($reportedMime) && $reportedMime !== '') {
        $fileMime = $reportedMime;
    }
}

if (!in_array($fileMime, $allowedMimes, true)) {
    http_response_code(422);
    echo json_encode(['success' => false, 'message' => 'Invalid file type. Allowed: mp3, mp4, aac, ogg, wav, m4a, webm']);
    exit;
}

if ($_FILES['tone']['size'] > 5 * 1024 * 1024) {
    http_response_code(422);
    echo json_encode(['success' => false, 'message' => 'File too large. Maximum size is 5 MB.']);
    exit;
}

$uploadDir = __DIR__ . '/../../uploads/ringtones/';
if (!is_dir($uploadDir)) {
    if (!@mkdir($uploadDir, 0755, true) && !is_dir($uploadDir)) {
        error_log('upload_sound_tone: failed to create directory ' . $uploadDir);
        http_response_code(500);
        echo json_encode(['success' => false, 'message' => 'Server configuration error. Please contact support.']);
        exit;
    }
}

$originalName = basename($_FILES['tone']['name']);
$ext = strtolower(pathinfo($originalName, PATHINFO_EXTENSION));
$allowedExts = ['mp3', 'mp4', 'aac', 'ogg', 'wav', 'm4a', 'webm'];
if (!in_array($ext, $allowedExts, true)) {
    $ext = 'mp3';
}

$filename = 'admin_' . $toneType . '_tone_' . time() . '.' . $ext;
$destPath = $uploadDir . $filename;

if (!move_uploaded_file($_FILES['tone']['tmp_name'], $destPath)) {
    error_log('upload_sound_tone: failed to move file to ' . $destPath);
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Failed to save file. Please try again.']);
    exit;
}

$fileUrl = '/uploads/ringtones/' . $filename;
$toneName = pathinfo($originalName, PATHINFO_FILENAME);

$settingMap = [
    'incoming_call' => [
        'tone_id'    => 'incoming_tone_id',
        'url'        => 'custom_incoming_tone_url',
        'name'       => 'custom_incoming_tone_name',
        'label'      => 'incoming_call',
    ],
    'message' => [
        'tone_id'    => 'message_tone_id',
        'url'        => 'custom_message_tone_url',
        'name'       => 'custom_message_tone_name',
        'label'      => 'message',
    ],
    'typing' => [
        'tone_id'    => 'typing_tone_id',
        'url'        => 'custom_typing_tone_url',
        'name'       => 'custom_typing_tone_name',
        'label'      => 'typing',
    ],
];

$keys = $settingMap[$toneType];

try {
    $pdo = new PDO(
        'mysql:host=' . DB_HOST . ';dbname=' . DB_NAME . ';charset=utf8mb4',
        DB_USER,
        DB_PASS,
        [
            PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES   => false,
        ]
    );
} catch (PDOException $e) {
    error_log('upload_sound_tone DB connect error: ' . $e->getMessage());
    @unlink($destPath);
    http_response_code(503);
    echo json_encode(['success' => false, 'message' => 'Database connection failed']);
    exit;
}

try {
    $pdo->exec("CREATE TABLE IF NOT EXISTS app_settings (
        `setting_key`   VARCHAR(100) NOT NULL PRIMARY KEY,
        `setting_value` TEXT,
        updated_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

    $upsert = $pdo->prepare(
        "INSERT INTO app_settings (setting_key, setting_value) VALUES (?, ?)
         ON DUPLICATE KEY UPDATE setting_value = VALUES(setting_value)"
    );

    $upsert->execute([$keys['tone_id'], 'custom']);
    $upsert->execute([$keys['url'], $fileUrl]);
    $upsert->execute([$keys['name'], $toneName]);

    echo json_encode([
        'success' => true,
        'message' => 'Custom ' . $keys['label'] . ' tone uploaded successfully',
        'data'    => [
            $keys['tone_id'] => 'custom',
            $keys['url']     => $fileUrl,
            $keys['name']    => $toneName,
            'tone_type'      => $toneType,
        ],
    ]);
} catch (Throwable $e) {
    error_log('upload_sound_tone DB error: ' . $e->getMessage());
    @unlink($destPath);
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Server error. Please try again.']);
}