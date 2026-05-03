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
    $rawInput = file_get_contents('php://input');
    $input = json_decode($rawInput, true);

    $userid = 0;
    $galleryId = 0;

    if (is_array($input)) {
        $userid = isset($input['userid']) ? (int) $input['userid'] : 0;
        $galleryId = isset($input['gallery_id']) ? (int) $input['gallery_id'] : 0;
    }

    if ($userid <= 0) {
        $userid = isset($_POST['userid']) ? (int) $_POST['userid'] : 0;
    }
    if ($galleryId <= 0) {
        $galleryId = isset($_POST['gallery_id']) ? (int) $_POST['gallery_id'] : 0;
    }

    if ($userid <= 0 || $galleryId <= 0) {
        http_response_code(422);
        echo json_encode([
            'status' => 'error',
            'message' => 'userid and gallery_id are required',
        ]);
        exit;
    }

    $findStmt = $pdo->prepare(
        'SELECT id, imageurl FROM user_gallery WHERE id = ? AND userid = ? LIMIT 1'
    );
    $findStmt->execute([$galleryId, $userid]);
    $photo = $findStmt->fetch(PDO::FETCH_ASSOC);

    if (!$photo) {
        http_response_code(404);
        echo json_encode([
            'status' => 'error',
            'message' => 'Gallery photo not found',
        ]);
        exit;
    }

    $deleteStmt = $pdo->prepare('DELETE FROM user_gallery WHERE id = ? AND userid = ?');
    $deleteStmt->execute([$galleryId, $userid]);

    if ($deleteStmt->rowCount() <= 0) {
        http_response_code(500);
        echo json_encode([
            'status' => 'error',
            'message' => 'Could not delete gallery photo',
        ]);
        exit;
    }

    $rawImage = (string) ($photo['imageurl'] ?? '');
    if ($rawImage !== '' && !preg_match('#^https?://#i', $rawImage)) {
        $safeRelative = ltrim(str_replace('\\', '/', $rawImage), '/');
        if (strpos($safeRelative, 'uploads/gallery/') === 0) {
            $fullPath = __DIR__ . '/' . $safeRelative;
            if (is_file($fullPath)) {
                @unlink($fullPath);
            }
        }
    }

    echo json_encode([
        'status' => 'success',
        'message' => 'Gallery photo deleted successfully',
        'gallery_id' => $galleryId,
    ]);
} catch (Throwable $e) {
    error_log('delete_gallery_photo fatal: ' . $e->getMessage());
    http_response_code(500);
    echo json_encode([
        'status' => 'error',
        'message' => 'Server error while deleting gallery photo',
    ]);
}
