<?php
require_once __DIR__ . '/../cors_headers.php';
header("Content-Type: application/json");

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    http_response_code(405);
    echo json_encode([
        'success' => false,
        'message' => 'Method not allowed'
    ]);
    exit;
}

// ================= DB CONFIG =================
define('DB_HOST', 'localhost');
define('DB_NAME', 'ms');
define('DB_USER', 'root');
define('DB_PASS', '');

function getProfileBaseUrl(): string {
    $isHttps = (
        (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') ||
        ((int)($_SERVER['SERVER_PORT'] ?? 80) === 443)
    );
    $scheme = $isHttps ? 'https' : 'http';
    $host = $_SERVER['HTTP_HOST'] ?? 'localhost';

    // Example script dir: /uttamms/Backend/api9  =>  /uttamms/Backend
    $scriptDir = rtrim(str_replace('\\', '/', dirname($_SERVER['SCRIPT_NAME'] ?? '')), '/');
    $backendBasePath = preg_replace('#/api9$#i', '', $scriptDir);

    return $scheme . '://' . $host . $backendBasePath . '/Api2/';
}

try {
    $pdo = new PDO(
        "mysql:host=" . DB_HOST . ";dbname=" . DB_NAME,
        DB_USER,
        DB_PASS,
        [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]
    );

    $stmt = $pdo->prepare("
        SELECT
            u.id,
            u.firstName,
            u.lastName,
            u.email,
            u.isVerified,
            u.status AS account_status,
            CASE
                WHEN u.profile_picture IS NULL OR TRIM(u.profile_picture) = '' THEN 'not_uploaded'
                WHEN u.profile_photo_status IS NOT NULL AND TRIM(u.profile_photo_status) <> '' THEN u.profile_photo_status
                WHEN u.status IN ('pending', 'approved', 'rejected', 'not_uploaded') THEN u.status
                ELSE 'pending'
            END AS status,
            u.privacy,
            u.usertype,
            u.lastLogin,
            u.createdDate AS registration_date,
            NULLIF(TRIM(u.contactNo), '') AS phone,
            u.isVerified AS email_verified,
            u.isVerified AS phone_verified,
            u.profile_picture,
            u.modifiedDate AS photo_updated_at,
            u.isOnline,
            u.isActive,
            u.pageno,
            u.gender,
            up_latest.expiredate AS expiry_date,
            CASE
                WHEN up_latest.expiredate IS NOT NULL AND up_latest.expiredate >= NOW() THEN 'paid'
                ELSE u.usertype
            END AS payment_status,
            COALESCE(uos.is_online, u.isOnline) AS isOnlineRealtime,
            COALESCE(uos.last_seen, u.lastLogin) AS lastSeen
        FROM users u
        LEFT JOIN user_online_status uos ON u.id = uos.user_id
        LEFT JOIN (
            SELECT up1.userid, up1.expiredate
            FROM user_package up1
            INNER JOIN (
                SELECT userid, MAX(expiredate) AS max_expire
                FROM user_package
                GROUP BY userid
            ) up2
            ON up1.userid = up2.userid AND up1.expiredate = up2.max_expire
        ) up_latest ON up_latest.userid = u.id
        WHERE COALESCE(u.isDelete, 0) = 0
        ORDER BY u.id DESC
    ");

    $stmt->execute();
    $users = $stmt->fetchAll(PDO::FETCH_ASSOC);

    $profileBaseUrl = getProfileBaseUrl();

    // Add stable local profile URL + normalise online/status payload.
    foreach ($users as &$user) {
        $rawPic = trim((string)($user['profile_picture'] ?? ''));
        if ($rawPic !== '') {
            if (preg_match('#^https?://#i', $rawPic)) {
                $photoUrl = $rawPic;
            } else {
                $photoUrl = $profileBaseUrl . ltrim($rawPic, '/');
            }

            // Cache-busting for updated photos.
            $cacheToken = null;
            if (!empty($user['photo_updated_at'])) {
                $ts = strtotime((string)$user['photo_updated_at']);
                if ($ts !== false) {
                    $cacheToken = (string)$ts;
                }
            }
            if ($cacheToken !== null) {
                $sep = (strpos($photoUrl, '?') !== false) ? '&' : '?';
                $photoUrl .= $sep . 'v=' . $cacheToken;
            }

            $user['profile_picture'] = $photoUrl;
        } else {
            $user['profile_picture'] = null;
        }

        // Prefer real-time online status over the legacy isOnline column
        $user['isOnline'] = (int) $user['isOnlineRealtime'];
        $user['lastSeen'] = $user['lastSeen'] ?? null;
        $user['phone_verified'] = (int)($user['phone_verified'] ?? 0);
        $user['email_verified'] = (int)($user['email_verified'] ?? 0);
        unset($user['isOnlineRealtime']);
    }

    echo json_encode([
        'success' => true,
        'count' => count($users),
        'data' => $users
    ]);

} catch (Throwable $e) {
    error_log('get_users.php error: ' . $e->getMessage());
    $remoteAddr = $_SERVER['REMOTE_ADDR'] ?? '';
    $isLocal = in_array($remoteAddr, ['127.0.0.1', '::1'], true);
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'message' => $isLocal ? $e->getMessage() : 'Server error'
    ]);
}
