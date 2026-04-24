<?php
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: POST, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With");
header("Access-Control-Max-Age: 86400");
header("Content-Type: application/json; charset=UTF-8");

// ================== PREFLIGHT ==================
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    echo json_encode(['success' => true]);
    exit;
}

define('DB_HOST', 'localhost');
define('DB_NAME', 'ms');
define('DB_USER', 'ms');
define('DB_PASS', 'ms');

function response($success, $message, $data = [], $code = 200) {
    http_response_code($code);
    echo json_encode([
        'success' => $success,
        'message' => $message,
        'data' => $data
    ]);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    response(false, 'Invalid request method', [], 405);
}

$input = json_decode(file_get_contents("php://input"), true);

$email = trim($input['email'] ?? '');
$password = $input['password'] ?? '';

if (!$email || !$password) {
    response(false, 'Email and password required', [], 422);
}

try {
    $pdo = new PDO(
        "mysql:host=" . DB_HOST . ";dbname=" . DB_NAME,
        DB_USER,
        DB_PASS,
        [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]
    );

    $stmt = $pdo->prepare("
        SELECT id, name, email, password, role, is_active
        FROM admins
        WHERE email = :email
        LIMIT 1
    ");
    $stmt->execute(['email' => $email]);
    $admin = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$admin) {
        response(false, 'Invalid credentials', [], 401);
    }

    if (!$admin['is_active']) {
        response(false, 'Admin account disabled', [], 403);
    }

    if (!password_verify($password, $admin['password'])) {
        response(false, 'Invalid credentials', [], 401);
    }

    // 🔐 Simple Token (JWT-like)
    $payload = [
        'admin_id' => $admin['id'],
        'email' => $admin['email'],
        'role' => $admin['role'],
        'iat' => time(),
        'exp' => time() + (60 * 60 * 24) // 24 hours
    ];

    $secret = 'CHANGE_THIS_SECRET_KEY';
    $token = base64_encode(json_encode($payload)) . '.' . hash_hmac('sha256', json_encode($payload), $secret);

    // Update last login
    $pdo->prepare("UPDATE admins SET last_login = NOW() WHERE id = ?")
        ->execute([$admin['id']]);

    response(true, 'Login successful', [
        'token' => $token,
        'admin' => [
            'id' => $admin['id'],
            'name' => $admin['name'],
            'email' => $admin['email'],
            'role' => $admin['role']
        ]
    ]);

} catch (Exception $e) {
    response(false, 'Server error', ['error' => $e->getMessage()], 500);
}
