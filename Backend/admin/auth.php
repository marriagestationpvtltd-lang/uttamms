<?php
/**
 * auth.php  (admin)
 *
 * Shared authentication middleware for admin API endpoints.
 *
 * Include this file at the top of every admin endpoint that requires
 * authentication:
 *
 *   require_once __DIR__ . '/auth.php';
 *
 * This file expects $pdo to already exist (i.e. db_config.php must have
 * been required before this file, or it will require it itself).
 *
 * On success:  $currentAdmin is set to the admin row array.
 * On failure:  a 401 JSON response is sent and execution stops.
 *
 * The caller passes the token as a standard HTTP Authorization header:
 *   Authorization: Bearer <token>
 */

if (!isset($pdo)) {
    require_once __DIR__ . '/../Api2/db_config.php';
}

// --------------------------------------------------------------------------
// Extract bearer token from the Authorization header
// --------------------------------------------------------------------------

$authHeader = '';
if (function_exists('getallheaders')) {
    $headers = getallheaders();
    foreach ($headers as $k => $v) {
        if (strtolower($k) === 'authorization') {
            $authHeader = $v;
            break;
        }
    }
}

// Fallback: Apache / nginx server variable
if ($authHeader === '' && isset($_SERVER['HTTP_AUTHORIZATION'])) {
    $authHeader = $_SERVER['HTTP_AUTHORIZATION'];
}

$token = '';
if (preg_match('/^Bearer\s+(\S+)$/i', trim($authHeader), $m)) {
    $token = $m[1];
}

if ($token === '') {
    http_response_code(401);
    echo json_encode(['status' => 'error', 'message' => 'Authorization token required']);
    exit;
}

// --------------------------------------------------------------------------
// Validate token against admin_tokens table
// --------------------------------------------------------------------------

try {
    $stmt = $pdo->prepare("
        SELECT a.id, a.username, a.email, a.name, a.is_active
        FROM   admin_tokens t
        JOIN   admins a ON a.id = t.admin_id
        WHERE  t.token = ?
          AND  t.expires_at > NOW()
        LIMIT 1
    ");
    $stmt->execute([$token]);
    $currentAdmin = $stmt->fetch();

    if (!$currentAdmin) {
        http_response_code(401);
        echo json_encode(['status' => 'error', 'message' => 'Invalid or expired token']);
        exit;
    }

    if (!(int) $currentAdmin['is_active']) {
        http_response_code(403);
        echo json_encode(['status' => 'error', 'message' => 'Admin account is disabled']);
        exit;
    }

} catch (PDOException $e) {
    error_log('admin/auth error: ' . $e->getMessage());
    http_response_code(500);
    echo json_encode(['status' => 'error', 'message' => 'Server error. Please try again.']);
    exit;
}
