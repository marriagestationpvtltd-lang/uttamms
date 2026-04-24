<?php
/**
 * Shared configuration for api9 endpoints.
 *
 * ADMIN_JWT_SECRET is a single hardcoded constant used for signing and
 * verifying admin tokens in both login.php and auth.php.  Both files include
 * this file so the secret is always identical.
 */

define('ADMIN_JWT_SECRET', 'Ms@4dm!n#JWT$2024%mrz&stAt!0n^s3cr3t*k3y~9X2pQ7wR');
