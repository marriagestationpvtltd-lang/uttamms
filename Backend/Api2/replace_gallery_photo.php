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

try {
    $userid = isset($_POST['userid']) ? (int) $_POST['userid'] : 0;
    $galleryId = isset($_POST['gallery_id']) ? (int) $_POST['gallery_id'] : 0;

    if ($userid <= 0 || $galleryId <= 0) {
        http_response_code(422);
        echo json_encode([
            'status' => 'error',
            'message' => 'userid and gallery_id are required',
        ]);
        exit;
    }

    if (!isset($_FILES['gallery_photo']) || ($_FILES['gallery_photo']['error'] ?? UPLOAD_ERR_NO_FILE) !== UPLOAD_ERR_OK) {
        http_response_code(422);
        echo json_encode([
            'status' => 'error',
            'message' => 'gallery_photo file is required',
        ]);
        exit;
    }

    $findStmt = $pdo->prepare('SELECT id, imageurl FROM user_gallery WHERE id = ? AND userid = ? LIMIT 1');
    $findStmt->execute([$galleryId, $userid]);
    $existing = $findStmt->fetch(PDO::FETCH_ASSOC);

    if (!$existing) {
        http_response_code(404);
        echo json_encode([
            'status' => 'error',
            'message' => 'Gallery photo not found',
        ]);
        exit;
    }

    $file = $_FILES['gallery_photo'];
    $size = (int) ($file['size'] ?? 0);
    if ($size <= 0 || $size > (8 * 1024 * 1024)) {
        http_response_code(422);
        echo json_encode([
            'status' => 'error',
            'message' => 'Invalid file size. Max size is 8MB.',
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

    $detectMime = static function (array $f) use ($extensionToMime): string {
        $tmp = (string) ($f['tmp_name'] ?? '');

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

        $ext = strtolower(pathinfo((string) ($f['name'] ?? ''), PATHINFO_EXTENSION));
        return $extensionToMime[$ext] ?? '';
    };

    $mime = $detectMime($file);
    if (!isset($allowedMimes[$mime])) {
        http_response_code(422);
        echo json_encode([
            'status' => 'error',
            'message' => 'Unsupported file format. Please upload JPG, PNG, WebP, HEIC or HEIF.',
        ]);
        exit;
    }

    $uploadDir = __DIR__ . '/uploads/gallery/';
    if (!is_dir($uploadDir)) {
        mkdir($uploadDir, 0750, true);
    }

    if (function_exists('random_bytes')) {
        $safeToken = bin2hex(random_bytes(6));
    } elseif (function_exists('openssl_random_pseudo_bytes')) {
        $bytes = openssl_random_pseudo_bytes(6);
        $safeToken = $bytes !== false ? bin2hex($bytes) : uniqid('', true);
    } else {
        $safeToken = uniqid('', true);
    }

    $safeExt = $allowedMimes[$mime];
    $newFileName = sprintf('gallery_%d_%s.%s', $userid, $safeToken, $safeExt);
    $destPath = $uploadDir . $newFileName;

    if (!move_uploaded_file((string) $file['tmp_name'], $destPath)) {
        http_response_code(500);
        echo json_encode([
            'status' => 'error',
            'message' => 'Failed to save uploaded file',
        ]);
        exit;
    }

    $newRelativePath = 'uploads/gallery/' . $newFileName;

    $hasUpdatedAt = false;
    $columnStmt = $pdo->prepare(
        "SELECT 1 FROM information_schema.columns WHERE table_schema = DATABASE() AND table_name = 'user_gallery' AND column_name = 'updated_at' LIMIT 1"
    );
    $columnStmt->execute();
    $hasUpdatedAt = (bool) $columnStmt->fetchColumn();

    if ($hasUpdatedAt) {
        $updateStmt = $pdo->prepare(
            'UPDATE user_gallery
             SET imageurl = ?, status = ?, reject_reason = NULL, updated_at = NOW()
             WHERE id = ? AND userid = ?'
        );
        $updateStmt->execute([$newRelativePath, 'pending', $galleryId, $userid]);
    } else {
        $updateStmt = $pdo->prepare(
            'UPDATE user_gallery
             SET imageurl = ?, status = ?, reject_reason = NULL
             WHERE id = ? AND userid = ?'
        );
        $updateStmt->execute([$newRelativePath, 'pending', $galleryId, $userid]);
    }

    if ($updateStmt->rowCount() <= 0) {
        @unlink($destPath);
        http_response_code(500);
        echo json_encode([
            'status' => 'error',
            'message' => 'Could not update gallery photo',
        ]);
        exit;
    }

    $oldPath = (string) ($existing['imageurl'] ?? '');
    if ($oldPath !== '' && !preg_match('#^https?://#i', $oldPath)) {
        $safeRelative = ltrim(str_replace('\\', '/', $oldPath), '/');
        if (strpos($safeRelative, 'uploads/gallery/') === 0) {
            $fullPath = __DIR__ . '/' . $safeRelative;
            if (is_file($fullPath)) {
                @unlink($fullPath);
            }
        }
    }

    echo json_encode([
        'status' => 'success',
        'message' => 'Gallery photo replaced. Waiting for admin approval.',
        'gallery_id' => $galleryId,
        'assigned_status' => 'pending',
        'imageurl' => $newRelativePath,
    ]);
} catch (Throwable $e) {
    error_log('replace_gallery_photo fatal: ' . $e->getMessage());
    http_response_code(500);
    echo json_encode([
        'status' => 'error',
        'message' => 'Server error while replacing gallery photo',
    ]);
}
