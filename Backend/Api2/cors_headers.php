<?php
/**
 * CORS Headers Configuration
 *
 * Include this file at the top of every API endpoint to enable CORS
 * and handle preflight OPTIONS requests.
 *
 * Usage: require_once __DIR__ . '/cors_headers.php';
 */

// Set CORS headers to allow cross-origin requests
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Headers: *");
header("Access-Control-Allow-Methods: GET, POST, OPTIONS");

// Handle preflight OPTIONS request
if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    http_response_code(200);
    exit();
}
