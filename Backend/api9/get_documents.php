<?php
require_once __DIR__ . '/../cors_headers.php';
header("Content-Type: application/json");

// ================= CONFIG =================
define('DB_HOST', 'localhost');
define('DB_NAME', 'ms');
define('DB_USER', 'root');
define('DB_PASS', '');

// âœ… BASE URL FOR PHOTOS
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

    // ðŸ”¥ ADD BASE URL TO PHOTO
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
