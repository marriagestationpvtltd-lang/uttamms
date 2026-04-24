<?php
// ================= CORS =================
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: GET, POST, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type, Authorization");
header("Access-Control-Max-Age: 86400");
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

// ================= GET ID =================
$id = null;

// Allow GET (?id=5)
if ($_SERVER['REQUEST_METHOD'] === 'GET') {
    $id = $_GET['id'] ?? null;
}

// Allow POST JSON
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $input = json_decode(file_get_contents("php://input"), true);
    $id = $input['id'] ?? null;
}

if (!$id || !is_numeric($id)) {
    http_response_code(422);
    echo json_encode([
        'success' => false,
        'message' => 'Package id is required'
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

    // Check package exists
    $check = $pdo->prepare("SELECT id FROM packagelist WHERE id = ?");
    $check->execute([$id]);

    if (!$check->fetch()) {
        http_response_code(404);
        echo json_encode([
            'success' => false,
            'message' => 'Package not found'
        ]);
        exit;
    }

    // Delete
    $stmt = $pdo->prepare("DELETE FROM packagelist WHERE id = ?");
    $stmt->execute([$id]);

    echo json_encode([
        'success' => true,
        'message' => 'Package deleted successfully'
    ]);

} catch (Exception $e) {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'message' => 'Server error'
    ]);
}
