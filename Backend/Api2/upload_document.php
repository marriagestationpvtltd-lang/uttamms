<?php
header("Content-Type: application/json");

require_once __DIR__ . '/db_config.php';

// ---------------- REQUIRED PARAMS ----------------
$userid       = isset($_POST['userid'])       ? intval($_POST['userid'])       : 0;
$documenttype = isset($_POST['documenttype']) ? trim($_POST['documenttype'])   : '';

if ($userid <= 0) {
    echo json_encode(["status" => "error", "message" => "Invalid userid"]);
    exit;
}
if ($documenttype === '') {
    echo json_encode(["status" => "error", "message" => "documenttype is required"]);
    exit;
}

// ---------------- OPTIONAL PARAMS ----------------
$documentidnumber = isset($_POST['documentidnumber']) ? trim($_POST['documentidnumber']) : null;

// ---------------- FILE UPLOAD ----------------
$photoPath = null;

if (isset($_FILES['photo']) && $_FILES['photo']['error'] === UPLOAD_ERR_OK) {

    // Size limit: 5 MB
    if ($_FILES['photo']['size'] > 5 * 1024 * 1024) {
        echo json_encode(["status" => "error", "message" => "File too large. Maximum size is 5 MB."]);
        exit;
    }

    // MIME type whitelist (images and PDF only)
    $allowedMimes = [
        'image/jpeg' => 'jpg',
        'image/png'  => 'png',
        'image/webp' => 'webp',
        'application/pdf' => 'pdf',
    ];

    $finfo    = new finfo(FILEINFO_MIME_TYPE);
    $fileMime = $finfo->file($_FILES['photo']['tmp_name']);

    if (!array_key_exists($fileMime, $allowedMimes)) {
        echo json_encode(["status" => "error", "message" => "Invalid file type. Only JPG, PNG, WebP, or PDF allowed."]);
        exit;
    }

    $safeExt = $allowedMimes[$fileMime];

    $folder = __DIR__ . "/uploads/user_documents/";
    if (!is_dir($folder)) {
        mkdir($folder, 0755, true);
    }

    // Use random suffix to prevent filename enumeration
    $filename = "doc_" . $userid . "_" . time() . "_" . bin2hex(random_bytes(4)) . "." . $safeExt;
    $filepath = $folder . $filename;

    if (move_uploaded_file($_FILES['photo']['tmp_name'], $filepath)) {
        $photoPath = "uploads/user_documents/" . $filename;
    }
}

// ---------------- LOCK CHECK: reject re-upload of verified documents ----------------
$lockCheck = $pdo->prepare(
    "SELECT status FROM user_documents WHERE userid = ? AND documenttype = ? LIMIT 1"
);
$lockCheck->execute([$userid, $documenttype]);
$existingStatus = $lockCheck->fetchColumn();

if ($existingStatus === 'approved') {
    http_response_code(403);
    echo json_encode([
        "status"  => "error",
        "message" => "This document has already been verified and is permanently locked. It cannot be replaced or re-uploaded."
    ]);
    exit;
}

// ---------------- UPSERT: one row per (userid, documenttype) ----------------
// On duplicate key reset status to pending and clear reject_reason so the
// admin re-reviews the freshly uploaded document.
$sql = "INSERT INTO user_documents
            (userid, documenttype, documentidnumber, photo, status, reject_reason)
        VALUES (?, ?, ?, ?, 'pending', NULL)
        ON DUPLICATE KEY UPDATE
            documentidnumber = VALUES(documentidnumber),
            photo            = IFNULL(VALUES(photo), photo),
            status           = 'pending',
            reject_reason    = NULL,
            updated_at       = NOW()";

$stmt = $pdo->prepare($sql);

if ($stmt->execute([$userid, $documenttype, $documentidnumber, $photoPath])) {
    echo json_encode([
        "status"  => "success",
        "message" => "Document uploaded and set to pending review"
    ]);
} else {
    echo json_encode(["status" => "error", "message" => "Database error"]);
}
?>
