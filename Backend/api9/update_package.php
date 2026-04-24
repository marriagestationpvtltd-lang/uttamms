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

$id          = $input['id'] ?? null;
$name        = trim($input['name'] ?? '');
$duration    = $input['duration'] ?? null;
$description = trim($input['description'] ?? '');
$price       = $input['price'] ?? null;

// ================= VALIDATION =================
if (!$id || $name === '' || $duration === null || $price === null) {
    http_response_code(422);
    echo json_encode([
        'success' => false,
        'message' => 'id, name, duration and price are required'
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

    // ================= CHECK PACKAGE EXISTS =================
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

    // ================= UPDATE PACKAGE =================
    $stmt = $pdo->prepare("
        UPDATE packagelist
        SET
            name = ?,
            duration = ?,
            description = ?,
            price = ?
        WHERE id = ?
    ");

    $stmt->execute([
        $name,
        (int)$duration,
        $description,
        number_format((float)$price, 2, '.', ''),
        $id
    ]);

    echo json_encode([
        'success' => true,
        'message' => 'Package updated successfully'
    ]);

} catch (Exception $e) {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'message' => 'Server error'
    ]);
}
