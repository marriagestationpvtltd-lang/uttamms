<?php
/**
 * Admin authentication helper for api9 endpoints.
 *
 * Usage:
 *   require_once __DIR__ . '/auth.php';
 *   $adminData = requireAdminAuth(); // exits with 401 JSON on failure
 */

require_once __DIR__ . '/config.php';

/**
 * Verify the Bearer token from the Authorization header.
 * Returns the decoded admin payload array on success, or null on failure.
 */
function verifyAdminToken(): ?array {
    $authHeader = $_SERVER['HTTP_AUTHORIZATION']
        ?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION']
        ?? '';

    if (empty($authHeader) || strncmp($authHeader, 'Bearer ', 7) !== 0) {
        return null;
    }

    $token = substr($authHeader, 7);
    $parts = explode('.', $token, 2);
    if (count($parts) !== 2) {
        return null;
    }

    [$payloadB64, $sig] = $parts;

    $secret = ADMIN_JWT_SECRET;
    $expectedSig = hash_hmac('sha256', $payloadB64, $secret);

    // Constant-time comparison to prevent timing attacks
    if (!hash_equals($expectedSig, $sig)) {
        return null;
    }

    $payload = json_decode(base64_decode($payloadB64), true);
    if (!is_array($payload)) {
        return null;
    }

    // Check expiry
    if (!isset($payload['exp']) || $payload['exp'] < time()) {
        return null;
    }

    return $payload;
}

/**
 * Require a valid admin token; exit with 401 JSON if missing/invalid.
 */
function requireAdminAuth(): array {
    $data = verifyAdminToken();
    if ($data === null) {
        http_response_code(401);
        echo json_encode(['success' => false, 'message' => 'Unauthorized']);
        exit;
    }
    return $data;
}
