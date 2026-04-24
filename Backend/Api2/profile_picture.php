<?php
header('Content-Type: application/json');

require_once __DIR__ . '/db_config.php';

// Check if user ID is provided
$userid = isset($_POST['userid']) ? intval($_POST['userid']) : 0;
if ($userid <= 0) {
    echo json_encode([
        "status" => "error",
        "message" => "Invalid user ID"
    ]);
    exit;
}

// Check if file is uploaded
if (!isset($_FILES['profile_picture']) || $_FILES['profile_picture']['error'] !== UPLOAD_ERR_OK) {
    $uploadErrors = [
        UPLOAD_ERR_INI_SIZE  => 'File exceeds server upload limit',
        UPLOAD_ERR_FORM_SIZE => 'File exceeds form upload limit',
        UPLOAD_ERR_PARTIAL   => 'File only partially uploaded',
        UPLOAD_ERR_NO_FILE   => 'No file was uploaded',
    ];
    $code = $_FILES['profile_picture']['error'] ?? UPLOAD_ERR_NO_FILE;
    echo json_encode([
        "status"  => "error",
        "message" => $uploadErrors[$code] ?? 'File upload error'
    ]);
    exit;
}

$file = $_FILES['profile_picture'];

// File size limit: 5 MB
if ($file['size'] > 5 * 1024 * 1024) {
    echo json_encode(["status" => "error", "message" => "File too large. Maximum size is 5 MB."]);
    exit;
}

// MIME type whitelist (images only)
$allowedMimes = [
    'image/jpeg' => 'jpg',
    'image/png'  => 'png',
    'image/webp' => 'webp',
];

$finfo    = new finfo(FILEINFO_MIME_TYPE);
$fileMime = $finfo->file($file['tmp_name']);

if (!array_key_exists($fileMime, $allowedMimes)) {
    echo json_encode(["status" => "error", "message" => "Invalid file type. Only JPG, PNG, or WebP allowed."]);
    exit;
}

$safeExt = $allowedMimes[$fileMime];

// Create uploads directory if not exists
$uploadDir = __DIR__ . '/uploads/profile_pictures/';
if (!is_dir($uploadDir)) {
    mkdir($uploadDir, 0755, true);
}

// Generate unique file name to avoid overwriting
$newFileName = 'profilepicture_' . $userid . '_' . bin2hex(random_bytes(4)) . '.' . $safeExt;
$destPath    = $uploadDir . $newFileName;

// Move uploaded file
if (move_uploaded_file($file['tmp_name'], $destPath)) {
    // Store relative path in DB
    $relativePath = 'uploads/profile_pictures/' . $newFileName;

    try {
        $stmt = $pdo->prepare("UPDATE users SET profile_picture = ? WHERE id = ?");
        $stmt->execute([$relativePath, $userid]);

        echo json_encode([
            "status"  => "success",
            "message" => "Profile picture updated successfully",
            "path"    => $relativePath
        ]);
    } catch (PDOException $e) {
        // Clean up uploaded file on DB failure
        @unlink($destPath);
        echo json_encode(["status" => "error", "message" => "Failed to update database"]);
    }
} else {
    echo json_encode([
        "status"  => "error",
        "message" => "Failed to move uploaded file"
    ]);
}
?>
