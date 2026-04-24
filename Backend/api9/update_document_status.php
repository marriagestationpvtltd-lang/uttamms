<?php
// ================= CORS =================
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: POST, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type, Authorization");
header("Content-Type: application/json");

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

require_once __DIR__ . '/auth.php';
requireAdminAuth();

// ================= DB CONFIG =================
define('DB_HOST', 'localhost');
define('DB_NAME', 'ms');
define('DB_USER', 'ms');
define('DB_PASS', 'ms');

$input       = json_decode(file_get_contents("php://input"), true);
$documentId  = isset($input['document_id']) ? intval($input['document_id']) : null;
$action      = $input['action'] ?? null;
$rejectReason = trim($input['reject_reason'] ?? '');

if (!$documentId || !$action) {
    http_response_code(422);
    echo json_encode([
        'success' => false,
        'message' => 'document_id and action are required'
    ]);
    exit;
}

try {
    $pdo = new PDO(
        "mysql:host=" . DB_HOST . ";dbname=" . DB_NAME,
        DB_USER,
        DB_PASS,
        [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]
    );

    // Check document exists and fetch current status
    $check = $pdo->prepare("SELECT id, status FROM user_documents WHERE id = ?");
    $check->execute([$documentId]);
    $existingDoc = $check->fetch(PDO::FETCH_ASSOC);

    if (!$existingDoc) {
        http_response_code(404);
        echo json_encode([
            'success' => false,
            'message' => 'Document not found'
        ]);
        exit;
    }

    // Lock check: once approved, a document cannot be modified
    if ($existingDoc['status'] === 'approved') {
        http_response_code(403);
        echo json_encode([
            'success' => false,
            'message' => 'This document has already been verified and is permanently locked. No further status changes are allowed.'
        ]);
        exit;
    }

    // ================= APPROVE =================
    if ($action === 'approve') {

        $stmt = $pdo->prepare("
            UPDATE user_documents
            SET
                status        = 'approved',
                reject_reason = NULL
            WHERE id = ?
        ");
        $stmt->execute([$documentId]);

        echo json_encode([
            'success' => true,
            'message' => 'Document approved successfully'
        ]);
        exit;
    }

    // ================= REJECT =================
    if ($action === 'reject') {

        if ($rejectReason === '') {
            http_response_code(422);
            echo json_encode([
                'success' => false,
                'message' => 'Reject reason is required'
            ]);
            exit;
        }

        $stmt = $pdo->prepare("
            UPDATE user_documents
            SET
                status        = 'rejected',
                reject_reason = ?
            WHERE id = ?
        ");
        $stmt->execute([$rejectReason, $documentId]);

        echo json_encode([
            'success' => true,
            'message' => 'Document rejected successfully'
        ]);
        exit;
    }

    // ================= INVALID =================
    http_response_code(400);
    echo json_encode([
        'success' => false,
        'message' => 'Invalid action'
    ]);

} catch (Exception $e) {
    error_log('[update_document_status] ' . $e->getMessage());
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'message' => 'Server error'
    ]);
}
