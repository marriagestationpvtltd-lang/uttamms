<?php
/**
 * activity_helper.php
 *
 * Lightweight helper to insert a row into user_activities.
 * Call this after every successful user action so the admin
 * Activity Feed shows real-time updates.
 *
 * Usage:
 *   require_once __DIR__ . '/activity_helper.php';
 *   logActivity($userId, 'message_sent', 'Message sent to Sita', $targetUserId);
 *
 * The function is intentionally fire-and-forget: any DB error is
 * silently logged so it never breaks the calling endpoint.
 */

if (!function_exists('logActivity')) {
    /**
     * @param int         $userId        The user performing the action.
     * @param string      $activityType  Must be one of the ENUM values in user_activities.
     * @param string      $description   Human-readable detail (optional).
     * @param int|null    $targetUserId  The other user involved (optional).
     * @param string|null $deviceInfo    Device / OS string (optional).
     */
    function logActivity(
        int    $userId,
        string $activityType,
        string $description   = '',
        ?int   $targetUserId  = null,
        ?string $deviceInfo   = null
    ): void {
        // Valid ENUM values – anything else falls back to 'other'
        static $validTypes = [
            'login', 'logout', 'profile_view', 'search',
            'proposal_sent', 'proposal_accepted', 'proposal_rejected',
            'call_initiated', 'call_received', 'call_ended',
            'custom_tone_set', 'custom_tone_removed', 'settings_changed',
            'like_sent', 'like_removed', 'message_sent',
            'request_sent', 'request_accepted', 'request_rejected',
            'call_made', 'photo_uploaded', 'package_bought', 'other',
        ];

        if (!in_array($activityType, $validTypes, true)) {
            $activityType = 'other';
        }

        $targetUserId = ($targetUserId !== null && $targetUserId > 0) ? $targetUserId : null;
        $ipAddress    = $_SERVER['REMOTE_ADDR'] ?? null;
        // Prefer the forwarded IP when behind a trusted proxy
        if (!empty($_SERVER['HTTP_X_FORWARDED_FOR'])) {
            $forwarded = trim(explode(',', $_SERVER['HTTP_X_FORWARDED_FOR'])[0]);
            if (filter_var($forwarded, FILTER_VALIDATE_IP)) {
                $ipAddress = $forwarded;
            }
        }

        try {
            // Reuse an existing PDO connection when available so we avoid
            // opening a second connection for every logged event.
            global $pdo;
            $db = ($pdo instanceof PDO) ? $pdo : null;

            if ($db === null) {
                // Fall back to the shared db_config constants when available,
                // otherwise use built-in defaults.
                $host = defined('DB_HOST') ? DB_HOST : '127.0.0.1';
                $name = defined('DB_NAME') ? DB_NAME : 'ms';
                $user = defined('DB_USER') ? DB_USER : 'ms';
                $pass = defined('DB_PASS') ? DB_PASS : 'ms';
                $db = new PDO(
                    "mysql:host=$host;dbname=$name;charset=utf8mb4",
                    $user,
                    $pass,
                    [
                        PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
                        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
                        PDO::ATTR_EMULATE_PREPARES   => false,
                    ]
                );
            }

            // Resolve display names in a single query to keep things simple
            $userIds = array_filter([$userId, $targetUserId], fn($id) => $id !== null);
            $names   = [];
            if ($userIds) {
                $placeholders = implode(',', array_fill(0, count($userIds), '?'));
                $nameStmt = $db->prepare(
                    "SELECT id, CONCAT_WS(' ', firstName, lastName) AS full_name
                       FROM users WHERE id IN ($placeholders)"
                );
                $nameStmt->execute(array_values($userIds));
                foreach ($nameStmt->fetchAll() as $row) {
                    $names[(int)$row['id']] = $row['full_name'];
                }
            }

            $userName   = $names[$userId]       ?? null;
            $targetName = ($targetUserId !== null) ? ($names[$targetUserId] ?? null) : null;

            $stmt = $db->prepare("
                INSERT INTO user_activities
                    (user_id, activity_type, description,
                     target_user_id, target_name, user_name,
                     ip_address, device_info)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ");
            $stmt->execute([
                $userId,
                $activityType,
                $description !== '' ? $description : null,
                $targetUserId,
                $targetName,
                $userName,
                $ipAddress,
                $deviceInfo,
            ]);

        } catch (Throwable $e) {
            // Non-fatal – log to PHP error log and continue
            error_log('logActivity failed: ' . $e->getMessage());
        }
    }
}
