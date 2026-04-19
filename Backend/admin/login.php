<?php
/**
 * login.php  (admin)
 *
 * Authenticates an admin user and returns a bearer token.
 *
 * POST body (JSON or form-encoded):
 *   username  (string) – admin username  OR
 *   email     (string) – admin e-mail address
 *   password  (string) – plain-text password
 *
 * Response (200):
 *   { "status": "success", "token": "<bearer-token>", "expires_at": "<datetime>",
 *     "admin": { "id": ..., "username": ..., "email": ..., "name": ... } }
 *
 * Response (401):
 *   { "status": "error", "message": "Invalid credentials" }
 */

ini_set('display_errors', 0);
ini_set('log_errors', 1);
error_reporting(E_ALL);

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
    echo json_encode(['status' => 'error', 'message' => 'Method not allowed']);
    exit;
}

require_once __DIR__ . '/../Api2/db_config.php';

// --------------------------------------------------------------------------
// Parse input
// --------------------------------------------------------------------------

$contentType = $_SERVER['CONTENT_TYPE'] ?? '';
if (stripos($contentType, 'application/json') !== false) {
    $input = json_decode(file_get_contents('php://input'), true) ?: [];
} else {
    $input = $_POST;
}

$username = isset($input['username']) ? trim($input['username']) : '';
$email    = isset($input['email'])    ? trim($input['email'])    : '';
$password = isset($input['password']) ? $input['password']       : '';

if ($password === '' || ($username === '' && $email === '')) {
    http_response_code(400);
    echo json_encode(['status' => 'error', 'message' => 'username (or email) and password are required']);
    exit;
}

// --------------------------------------------------------------------------
// Look up admin
// --------------------------------------------------------------------------

try {
    if ($username !== '') {
        $stmt = $pdo->prepare("SELECT id, username, email, password, name, is_active FROM admins WHERE username = ? LIMIT 1");
        $stmt->execute([$username]);
    } else {
        $stmt = $pdo->prepare("SELECT id, username, email, password, name, is_active FROM admins WHERE email = ? LIMIT 1");
        $stmt->execute([$email]);
    }

    $admin = $stmt->fetch();

    if (!$admin || !password_verify($password, $admin['password'])) {
        http_response_code(401);
        echo json_encode(['status' => 'error', 'message' => 'Invalid credentials']);
        exit;
    }

    if (!(int) $admin['is_active']) {
        http_response_code(403);
        echo json_encode(['status' => 'error', 'message' => 'Admin account is disabled']);
        exit;
    }

    // --------------------------------------------------------------------------
    // Issue token (valid for 24 hours)
    // --------------------------------------------------------------------------

    $token     = bin2hex(random_bytes(48));   // 96 hex chars
    $expiresAt = date('Y-m-d H:i:s', strtotime('+24 hours'));

    // Remove expired tokens for this admin
    $pdo->prepare("DELETE FROM admin_tokens WHERE admin_id = ? AND expires_at < NOW()")->execute([$admin['id']]);

    $ins = $pdo->prepare("INSERT INTO admin_tokens (admin_id, token, expires_at) VALUES (?, ?, ?)");
    $ins->execute([$admin['id'], $token, $expiresAt]);

    // Update last_login
    $pdo->prepare("UPDATE admins SET last_login = NOW() WHERE id = ?")->execute([$admin['id']]);

    echo json_encode([
        'status'     => 'success',
        'token'      => $token,
        'expires_at' => $expiresAt,
        'admin'      => [
            'id'       => (int) $admin['id'],
            'username' => $admin['username'],
            'email'    => $admin['email'],
            'name'     => $admin['name'],
        ],
    ]);

} catch (PDOException $e) {
    error_log('admin/login error: ' . $e->getMessage());
    http_response_code(500);
    echo json_encode(['status' => 'error', 'message' => 'Server error. Please try again.']);
}
