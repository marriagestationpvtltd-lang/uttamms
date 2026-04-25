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

// ================= DB CONFIG =================
define('DB_HOST', 'localhost');
define('DB_NAME', 'ms');
define('DB_USER', 'ms');
define('DB_PASS', 'ms');

try {
    // ================= PARSE REQUEST BODY =================
    $body = json_decode(file_get_contents('php://input'), true);

    $request_id = isset($body['request_id']) ? (int)$body['request_id'] : 0;
    $action     = isset($body['action'])     ? trim($body['action'])     : '';

    if ($request_id <= 0) {
        http_response_code(400);
        echo json_encode(['success' => false, 'message' => 'Invalid request_id']);
        exit;
    }

    $validActions = ['accept' => 'accepted', 'reject' => 'rejected'];

    if (!array_key_exists($action, $validActions)) {
        http_response_code(400);
        echo json_encode(['success' => false, 'message' => 'Invalid action. Use "accept" or "reject"']);
        exit;
    }

    $newStatus = $validActions[$action];

    $pdo = new PDO(
        "mysql:host=" . DB_HOST . ";dbname=" . DB_NAME,
        DB_USER,
        DB_PASS,
        [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]
    );

    // ================= VERIFY PROPOSAL EXISTS =================
    $checkStmt = $pdo->prepare("SELECT id FROM proposals WHERE id = :id");
    $checkStmt->execute([':id' => $request_id]);

    if (!$checkStmt->fetch()) {
        http_response_code(404);
        echo json_encode(['success' => false, 'message' => 'Request not found']);
        exit;
    }

    // ================= UPDATE STATUS =================
    $updateStmt = $pdo->prepare("
        UPDATE proposals
        SET status = :status, updated_at = NOW()
        WHERE id = :id
    ");
    $updateStmt->execute([
        ':status' => $newStatus,
        ':id'     => $request_id,
    ]);

    $label = $action === 'accept' ? 'accepted' : 'rejected';
    echo json_encode([
        'success' => true,
        'message' => "Request {$label} successfully",
    ]);

} catch (Exception $e) {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'message' => 'Server error'
    ]);
}
