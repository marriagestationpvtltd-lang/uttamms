<?php
require_once __DIR__ . '/../cors_headers.php';
header("Content-Type: application/json; charset=UTF-8");

define('DB_HOST', 'localhost');
define('DB_NAME', 'ms');
define('DB_USER', 'root');
define('DB_PASS', '');

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
        "mysql:host=" . DB_HOST . ";dbname=" . DB_NAME . ";charset=utf8mb4",
        DB_USER,
        DB_PASS,
        [
            PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES   => false,
        ]
    );

    $stmt = $pdo->prepare("
        SELECT id, name, email, password, role, is_active
        FROM admins
        WHERE email = :email
        LIMIT 1
    ");
    $stmt->execute(['email' => $email]);
    $admin = $stmt->fetch();

    if (!$admin) {
        response(false, 'Invalid credentials', [], 401);
    }

    if (!$admin['is_active']) {
        response(false, 'Admin account disabled', [], 403);
    }

    if (!password_verify($password, $admin['password'])) {
        response(false, 'Invalid credentials', [], 401);
    }

    // Generate a secure random token (96 hex chars, fits in admin_tokens.token VARCHAR(128))
    $token     = bin2hex(random_bytes(48));
    $expiresAt = date('Y-m-d H:i:s', strtotime('+24 hours'));

    // Remove expired tokens for this admin to keep the table clean
    $pdo->prepare("DELETE FROM admin_tokens WHERE admin_id = ? AND expires_at < NOW()")
        ->execute([$admin['id']]);

    // Store token in admin_tokens so the socket server can validate it
    $pdo->prepare("INSERT INTO admin_tokens (admin_id, token, expires_at) VALUES (?, ?, ?)")
        ->execute([$admin['id'], $token, $expiresAt]);

    // Update last login
    $pdo->prepare("UPDATE admins SET last_login = NOW() WHERE id = ?")
        ->execute([$admin['id']]);

    response(true, 'Login successful', [
        'token' => $token,
        'admin' => [
            'id'   => $admin['id'],
            'name' => $admin['name'],
            'email' => $admin['email'],
            'role' => $admin['role']
        ]
    ]);

} catch (Exception $e) {
    response(false, 'Server error', ['error' => $e->getMessage()], 500);
}
