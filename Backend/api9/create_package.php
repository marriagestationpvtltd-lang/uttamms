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

// ================= READ INPUT =================
$input = json_decode(file_get_contents("php://input"), true);

$name        = trim($input['name'] ?? '');
$duration    = $input['duration'] ?? null;
$description = trim($input['description'] ?? '');
$price       = $input['price'] ?? null;

// ================= VALIDATION =================
if ($name === '' || $duration === null || $price === null) {
    http_response_code(422);
    echo json_encode([
        'success' => false,
        'message' => 'Name, duration and price are required'
    ]);
    exit;
}

if (!is_numeric($duration) || $duration <= 0) {
    http_response_code(422);
    echo json_encode([
        'success' => false,
        'message' => 'Duration must be a valid number'
    ]);
    exit;
}

if (!is_numeric($price) || $price <= 0) {
    http_response_code(422);
    echo json_encode([
        'success' => false,
        'message' => 'Price must be a valid number'
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

    // ================= INSERT PACKAGE =================
    $stmt = $pdo->prepare("
        INSERT INTO packagelist (name, duration, description, price)
        VALUES (?, ?, ?, ?)
    ");

    $stmt->execute([
        $name,
        (int)$duration,
        $description,
        number_format((float)$price, 2, '.', '')
    ]);

    echo json_encode([
        'success' => true,
        'message' => 'Package created successfully',
        'package_id' => $pdo->lastInsertId()
    ]);

} catch (Exception $e) {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'message' => 'Server error'
    ]);
}
