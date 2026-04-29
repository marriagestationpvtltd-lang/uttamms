<?php
/**
 * Shared PDO database connection.
 *
 * Include this file in every API endpoint instead of creating individual
 * connections.  All endpoints then use the same driver (PDO) and the
 * credentials live in exactly one place.
 *
 * Usage:
 *   require_once __DIR__ . '/db_config.php';
 *   // $pdo is now available
 */

define('DB_HOST', '127.0.0.1');
define('DB_NAME', 'ms');
define('DB_USER', 'ms');
define('DB_PASS', 'ms');

// Base URL of the Socket.IO / Node.js server used for real-time event delivery.
// Override this in your server environment if the socket server runs on a
// different host or port.
if (!defined('SOCKET_SERVER_URL')) {
    define('SOCKET_SERVER_URL', getenv('SOCKET_SERVER_URL') ?: 'http://localhost:3001');
}

try {
    $pdo = new PDO(
        'mysql:host=' . DB_HOST . ';dbname=' . DB_NAME . ';charset=utf8mb4',
        DB_USER,
        DB_PASS
    );
    $pdo->setAttribute(PDO::ATTR_ERRMODE,       PDO::ERRMODE_EXCEPTION);
    $pdo->setAttribute(PDO::ATTR_DEFAULT_FETCH_MODE, PDO::FETCH_ASSOC);
    $pdo->setAttribute(PDO::ATTR_EMULATE_PREPARES, false);
} catch (PDOException $e) {
    header('Content-Type: application/json');
    http_response_code(503);
    echo json_encode(['success' => false, 'message' => 'Database connection failed']);
    exit;
}
