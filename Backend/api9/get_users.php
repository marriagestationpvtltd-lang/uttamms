<?php
// ================= CORS =================
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: GET, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type, Authorization");
header("Content-Type: application/json");

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

// ================= DB CONFIG =================
define('DB_HOST', 'localhost');
define('DB_NAME', 'ms');
define('DB_USER', 'ms');
define('DB_PASS', 'ms');

// ✅ BASE URL FOR PROFILE PICTURES
define('PROFILE_BASE_URL', 'https://digitallami.com/Api2/');

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
            u.status,
            u.privacy,
            u.usertype,
            u.lastLogin,
            u.profile_picture,
            u.isOnline,
            u.isActive,
            u.pageno,
            u.gender,
            COALESCE(uos.is_online, u.isOnline) AS isOnlineRealtime,
            COALESCE(uos.last_seen, u.lastLogin) AS lastSeen
        FROM users u
        LEFT JOIN user_online_status uos ON u.id = uos.user_id
        ORDER BY u.id DESC
    ");

    $stmt->execute();
    $users = $stmt->fetchAll(PDO::FETCH_ASSOC);

    // 🔥 ADD BASE URL TO PROFILE PICTURE + normalise real-time online fields
    foreach ($users as &$user) {
        if (!empty($user['profile_picture'])) {
            $user['profile_picture'] =
                PROFILE_BASE_URL . ltrim($user['profile_picture'], '/');
        } else {
            $user['profile_picture'] = null;
        }
        // Prefer real-time online status over the legacy isOnline column
        $user['isOnline'] = (int) $user['isOnlineRealtime'];
        $user['lastSeen'] = $user['lastSeen'] ?? null;
        unset($user['isOnlineRealtime']);
    }

    echo json_encode([
        'success' => true,
        'count' => count($users),
        'data' => $users
    ]);

} catch (Exception $e) {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'message' => 'Server error'
    ]);
}
