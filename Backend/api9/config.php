<?php
/**
 * Shared configuration for api9 endpoints.
 *
 * Provides getAdminJwtSecret() which resolves the JWT signing secret in order:
 *   1. ADMIN_JWT_SECRET environment variable (recommended for production)
 *   2. A persistent secret stored in .jwt_secret file (auto-generated on first use)
 *
 * Both login.php and auth.php must use this function so that tokens signed
 * during login can always be verified.
 */

/**
 * Returns the admin JWT secret, generating and persisting one if necessary.
 * Returns null (and logs an error) only if neither the env var nor file
 * storage is available.
 */
function getAdminJwtSecret(): ?string {
    // 1. Prefer the environment variable (production / CI)
    $envSecret = getenv('ADMIN_JWT_SECRET');
    if ($envSecret !== false && $envSecret !== '') {
        return $envSecret;
    }

    // 2. Fall back to a file-based persistent secret
    $secretFile = __DIR__ . '/.jwt_secret';

    if (file_exists($secretFile) && is_readable($secretFile)) {
        $fileSecret = trim((string) file_get_contents($secretFile));
        if ($fileSecret !== '') {
            return $fileSecret;
        }
    }

    // 3. Generate a new secret, persist it, and return it
    $newSecret = bin2hex(random_bytes(32));
    $bytesWritten = file_put_contents($secretFile, $newSecret, LOCK_EX);
    if ($bytesWritten !== false) {
        @chmod($secretFile, 0600);
        return $newSecret;
    }

    error_log('[getAdminJwtSecret] ADMIN_JWT_SECRET env var is not set and cannot write to ' . $secretFile . ': ' . error_get_last()['message']);
    return null;
}
