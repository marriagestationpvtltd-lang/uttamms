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
            id,
            firstName,
            lastName,
            email,
            isVerified,
            status,
            privacy,
            usertype,
            lastLogin,
            profile_picture,
            isOnline,
            isActive,
            pageno,
            gender
        FROM users
        ORDER BY id DESC
    ");

    $stmt->execute();
    $users = $stmt->fetchAll(PDO::FETCH_ASSOC);

    // 🔥 ADD BASE URL TO PROFILE PICTURE
    foreach ($users as &$user) {
        if (!empty($user['profile_picture'])) {
            $user['profile_picture'] =
                PROFILE_BASE_URL . ltrim($user['profile_picture'], '/');
        } else {
            $user['profile_picture'] = null;
        }
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
