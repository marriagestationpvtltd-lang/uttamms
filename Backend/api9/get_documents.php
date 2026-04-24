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

require_once __DIR__ . '/auth.php';
requireAdminAuth();

// ================= CONFIG =================
define('DB_HOST', 'localhost');
define('DB_NAME', 'ms');
define('DB_USER', 'ms');
define('DB_PASS', 'ms');

// ✅ BASE URL FOR PHOTOS
define('PHOTO_BASE_URL', 'https://digitallami.com/Api2/');

try {
    $pdo = new PDO(
        "mysql:host=" . DB_HOST . ";dbname=" . DB_NAME,
        DB_USER,
        DB_PASS,
        [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]
    );

    // Filter by per-document status (not global users.status)
    $stmt = $pdo->prepare("
        SELECT
            u.id AS user_id,
            u.email,
            u.firstName,
            u.lastName,
            u.gender,
            u.isVerified,

            d.id AS document_id,
            d.documenttype,
            d.documentidnumber,
            d.photo,
            d.status,
            d.reject_reason

        FROM users u
        INNER JOIN user_documents d ON d.userid = u.id
        ORDER BY d.updated_at DESC
    ");

    $stmt->execute();
    $documents = $stmt->fetchAll(PDO::FETCH_ASSOC);

    // 🔥 ADD BASE URL TO PHOTO
    foreach ($documents as &$doc) {
        if (!empty($doc['photo'])) {
            $doc['photo'] = PHOTO_BASE_URL . ltrim($doc['photo'], '/');
        }
    }

    echo json_encode([
        'success' => true,
        'data'    => $documents
    ]);

} catch (Exception $e) {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'message' => 'Server error'
    ]);
}
