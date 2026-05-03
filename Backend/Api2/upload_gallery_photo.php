<?php
ini_set('display_errors', 0);
ini_set('log_errors', 1);
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
    echo json_encode([
        'status' => 'error',
        'message' => 'Method not allowed',
    ]);
    exit;
}

require_once __DIR__ . '/db_config.php';
require_once __DIR__ . '/activity_helper.php';

try {

$userid = isset($_POST['userid']) ? (int) $_POST['userid'] : 0;
if ($userid <= 0) {
    http_response_code(422);
    echo json_encode([
        'status' => 'error',
        'message' => 'Invalid user ID',
    ]);
    exit;
}

$check = $pdo->prepare('SELECT id FROM users WHERE id = ? LIMIT 1');
$check->execute([$userid]);
if (!$check->fetch()) {
    http_response_code(404);
    echo json_encode([
        'status' => 'error',
        'message' => 'User not found',
    ]);
    exit;
}

$files = [];

if (isset($_FILES['gallery_photos'])) {
    $galleryPhotos = $_FILES['gallery_photos'];

    if (is_array($galleryPhotos['name'])) {
        $count = count($galleryPhotos['name']);
        for ($i = 0; $i < $count; $i++) {
            $files[] = [
                'name' => $galleryPhotos['name'][$i] ?? '',
                'type' => $galleryPhotos['type'][$i] ?? '',
                'tmp_name' => $galleryPhotos['tmp_name'][$i] ?? '',
                'error' => $galleryPhotos['error'][$i] ?? UPLOAD_ERR_NO_FILE,
                'size' => $galleryPhotos['size'][$i] ?? 0,
            ];
        }
    } else {
        $files[] = $galleryPhotos;
    }
}

if (empty($files) && isset($_FILES['gallery_photo'])) {
    $files[] = $_FILES['gallery_photo'];
}

$files = array_values(array_filter($files, static function ($file) {
    return ($file['error'] ?? UPLOAD_ERR_NO_FILE) !== UPLOAD_ERR_NO_FILE;
}));

if (empty($files)) {
    http_response_code(422);
    echo json_encode([
        'status' => 'error',
        'message' => 'No gallery photos uploaded',
    ]);
    exit;
}

$allowedMimes = [
    'image/jpeg' => 'jpg',
    'image/jpg' => 'jpg',
    'image/pjpeg' => 'jpg',
    'image/png' => 'png',
    'image/x-png' => 'png',
    'image/webp' => 'webp',
    'image/heic' => 'heic',
    'image/heif' => 'heif',
];

$extensionToMime = [
    'jpg' => 'image/jpeg',
    'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'webp' => 'image/webp',
    'heic' => 'image/heic',
    'heif' => 'image/heif',
];

$uploadDir = __DIR__ . '/uploads/gallery/';
if (!is_dir($uploadDir)) {
    mkdir($uploadDir, 0750, true);
}

$hasTable = static function (PDO $pdo, string $table): bool {
    $stmt = $pdo->prepare(
        "SELECT 1 FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = ? LIMIT 1"
    );
    $stmt->execute([$table]);
    return (bool) $stmt->fetchColumn();
};

$hasColumn = static function (PDO $pdo, string $table, string $column): bool {
    $stmt = $pdo->prepare(
        "SELECT 1 FROM information_schema.columns WHERE table_schema = DATABASE() AND table_name = ? AND column_name = ? LIMIT 1"
    );
    $stmt->execute([$table, $column]);
    return (bool) $stmt->fetchColumn();
};

if (!$hasTable($pdo, 'user_gallery')) {
    http_response_code(500);
    echo json_encode([
        'status' => 'error',
        'message' => 'Database table user_gallery is missing',
    ]);
    exit;
}

$assignedStatus = 'pending';

$insertColumns = ['userid', 'imageurl'];
$insertValuesSql = ['?', '?'];
$bindFactory = static function (int $uid, string $path): array {
    return [$uid, $path];
};

if ($hasColumn($pdo, 'user_gallery', 'status')) {
    $insertColumns[] = 'status';
    $insertValuesSql[] = '?';
    $prevFactory = $bindFactory;
    $bindFactory = static function (int $uid, string $path) use ($prevFactory, $assignedStatus): array {
        $values = $prevFactory($uid, $path);
        $values[] = $assignedStatus;
        return $values;
    };
}

if ($hasColumn($pdo, 'user_gallery', 'reject_reason')) {
    $insertColumns[] = 'reject_reason';
    $insertValuesSql[] = 'NULL';
}

if ($hasColumn($pdo, 'user_gallery', 'created_at')) {
    $insertColumns[] = 'created_at';
    $insertValuesSql[] = 'NOW()';
}

if ($hasColumn($pdo, 'user_gallery', 'updated_at')) {
    $insertColumns[] = 'updated_at';
    $insertValuesSql[] = 'NOW()';
}

$insertStmt = $pdo->prepare(
    'INSERT INTO user_gallery (' . implode(', ', $insertColumns) . ')
     VALUES (' . implode(', ', $insertValuesSql) . ')'
);

$inserted = [];
$rejectedBySize = 0;
$rejectedByFormat = 0;
$rejectedByUpload = 0;
$rejectedByMove = 0;

$detectMime = static function (array $file) use ($extensionToMime): string {
    $tmp = (string) ($file['tmp_name'] ?? '');

    if ($tmp !== '' && class_exists('finfo')) {
        $finfo = new finfo(FILEINFO_MIME_TYPE);
        $detected = (string) $finfo->file($tmp);
        if ($detected !== '') {
            return strtolower($detected);
        }
    }

    if ($tmp !== '' && function_exists('mime_content_type')) {
        $detected = (string) mime_content_type($tmp);
        if ($detected !== '') {
            return strtolower($detected);
        }
    }

    $ext = strtolower(pathinfo((string) ($file['name'] ?? ''), PATHINFO_EXTENSION));
    return $extensionToMime[$ext] ?? '';
};

foreach ($files as $file) {
    $error = $file['error'] ?? UPLOAD_ERR_NO_FILE;
    if ($error !== UPLOAD_ERR_OK) {
        $rejectedByUpload++;
        continue;
    }

    $size = (int) ($file['size'] ?? 0);
    if ($size <= 0 || $size > (8 * 1024 * 1024)) {
        $rejectedBySize++;
        continue;
    }

    $tmp = $file['tmp_name'] ?? '';
    if ($tmp === '' || !is_uploaded_file($tmp)) {
        $rejectedByUpload++;
        continue;
    }

    $mime = $detectMime($file);
    if (!isset($allowedMimes[$mime])) {
        $rejectedByFormat++;
        continue;
    }

    $safeExt = $allowedMimes[$mime];
    if (function_exists('random_bytes')) {
        $safeToken = bin2hex(random_bytes(6));
    } elseif (function_exists('openssl_random_pseudo_bytes')) {
        $bytes = openssl_random_pseudo_bytes(6);
        $safeToken = $bytes !== false ? bin2hex($bytes) : uniqid('', true);
    } else {
        $safeToken = uniqid('', true);
    }
    $newFileName = sprintf(
        'gallery_%d_%s.%s',
        $userid,
        $safeToken,
        $safeExt
    );

    $destPath = $uploadDir . $newFileName;
    if (!move_uploaded_file($tmp, $destPath)) {
        $rejectedByMove++;
        continue;
    }

    $relativePath = 'uploads/gallery/' . $newFileName;
    $insertStmt->execute($bindFactory($userid, $relativePath));

    $inserted[] = [
        'id' => (int) $pdo->lastInsertId(),
        'imageurl' => $relativePath,
        'status' => $assignedStatus,
    ];
}

if (empty($inserted)) {
    $detailParts = [];
    if ($rejectedByFormat > 0) {
        $detailParts[] = $rejectedByFormat . ' file format not supported';
    }
    if ($rejectedBySize > 0) {
        $detailParts[] = $rejectedBySize . ' file exceeded 8MB limit';
    }
    if ($rejectedByUpload > 0) {
        $detailParts[] = $rejectedByUpload . ' upload(s) were incomplete';
    }
    if ($rejectedByMove > 0) {
        $detailParts[] = $rejectedByMove . ' file(s) could not be saved';
    }

    $detailMessage = empty($detailParts)
        ? 'No valid photos were uploaded. Please use JPG, PNG, WebP, HEIC or HEIF under 8MB.'
        : ('No valid photos were uploaded: ' . implode(', ', $detailParts) . '.');

    http_response_code(422);
    echo json_encode([
        'status' => 'error',
        'message' => $detailMessage,
    ]);
    exit;
}

try {
    logActivity($userid, 'photo_uploaded', 'Gallery photo uploaded');
} catch (Throwable $e) {
    error_log('upload_gallery_photo activity log error: ' . $e->getMessage());
}

echo json_encode([
    'status' => 'success',
    'message' => 'Gallery photos uploaded and sent for admin approval',
    'auto_approved' => false,
    'assigned_status' => $assignedStatus,
    'count' => count($inserted),
    'gallery' => $inserted,
]);

} catch (Throwable $e) {
    error_log('upload_gallery_photo fatal: ' . $e->getMessage());
    http_response_code(500);
    echo json_encode([
        'status' => 'error',
        'message' => 'Gallery upload failed due to server error',
        'debug_hint' => 'Check PHP error log for upload_gallery_photo fatal details',
    ]);
}
