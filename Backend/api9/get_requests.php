<?php
// ================= CORS =================
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: GET, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type, Authorization");
header("Content-Type: application/json");

ini_set('display_errors', 0);
ini_set('log_errors', 1);
error_reporting(E_ALL);

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

    // ================= PAGINATION =================
    $page     = max(1, (int)($_GET['page']     ?? 1));
    $per_page = min(100, max(1, (int)($_GET['per_page'] ?? 20)));
    $offset   = ($page - 1) * $per_page;

    // ================= FILTERS =================
    $status = trim($_GET['status'] ?? 'all');
    $search = trim($_GET['search'] ?? '');

    $validStatuses = ['pending', 'accepted', 'rejected', 'cancelled'];

    $whereClauses = [];
    $params       = [];

    if ($status !== 'all' && in_array($status, $validStatuses)) {
        $whereClauses[] = "p.status = :status";
        $params[':status'] = $status;
    }

    if ($search !== '') {
        $whereClauses[] = "(
            sender.firstName  LIKE :search OR
            sender.lastName   LIKE :search OR
            sender.email      LIKE :search OR
            receiver.firstName LIKE :search OR
            receiver.lastName  LIKE :search OR
            receiver.email     LIKE :search
        )";
        $params[':search'] = '%' . $search . '%';
    }

    $whereSQL = $whereClauses ? 'WHERE ' . implode(' AND ', $whereClauses) : '';

    // ================= TOTAL COUNT =================
    $countStmt = $pdo->prepare("
        SELECT COUNT(*) AS total
        FROM proposals p
        INNER JOIN users sender   ON sender.id   = p.sender_id
        INNER JOIN users receiver ON receiver.id = p.receiver_id
        $whereSQL
    ");
    $countStmt->execute($params);
    $total = (int)$countStmt->fetchColumn();

    // ================= PAGINATED DATA =================
    $dataStmt = $pdo->prepare("
        SELECT
            p.id,
            p.sender_id,
            CONCAT(sender.firstName, ' ', sender.lastName) AS sender_name,
            sender.email                                    AS sender_email,
            sender.profile_picture                         AS sender_photo,
            p.receiver_id,
            CONCAT(receiver.firstName, ' ', receiver.lastName) AS receiver_name,
            receiver.email                                      AS receiver_email,
            receiver.profile_picture                            AS receiver_photo,
            p.request_type,
            p.status,
            p.created_at,
            p.updated_at
        FROM proposals p
        INNER JOIN users sender   ON sender.id   = p.sender_id
        INNER JOIN users receiver ON receiver.id = p.receiver_id
        $whereSQL
        ORDER BY p.created_at DESC
        LIMIT :limit OFFSET :offset
    ");

    foreach ($params as $key => $value) {
        $dataStmt->bindValue($key, $value);
    }
    $dataStmt->bindValue(':limit',  $per_page, PDO::PARAM_INT);
    $dataStmt->bindValue(':offset', $offset,   PDO::PARAM_INT);
    $dataStmt->execute();
    $requests = $dataStmt->fetchAll(PDO::FETCH_ASSOC);

    // 🔥 ADD BASE URL TO PROFILE PICTURES
    foreach ($requests as &$row) {
        if (!empty($row['sender_photo'])) {
            $row['sender_photo'] = PROFILE_BASE_URL . ltrim($row['sender_photo'], '/');
        } else {
            $row['sender_photo'] = null;
        }
        if (!empty($row['receiver_photo'])) {
            $row['receiver_photo'] = PROFILE_BASE_URL . ltrim($row['receiver_photo'], '/');
        } else {
            $row['receiver_photo'] = null;
        }
    }

    // ================= STATS =================
    $statsStmt = $pdo->prepare("
        SELECT
            COUNT(*)                                          AS total,
            SUM(p.status = 'pending')                        AS pending,
            SUM(p.status = 'accepted')                       AS accepted,
            SUM(p.status = 'rejected')                       AS rejected,
            SUM(p.status = 'cancelled')                      AS cancelled
        FROM proposals p
    ");
    $statsStmt->execute();
    $statsRow = $statsStmt->fetch(PDO::FETCH_ASSOC);

    $stats = [
        'total'     => (int)$statsRow['total'],
        'pending'   => (int)$statsRow['pending'],
        'accepted'  => (int)$statsRow['accepted'],
        'rejected'  => (int)$statsRow['rejected'],
        'cancelled' => (int)$statsRow['cancelled'],
    ];

    echo json_encode([
        'success'    => true,
        'data'       => $requests,
        'pagination' => [
            'total'       => $total,
            'page'        => $page,
            'per_page'    => $per_page,
            'total_pages' => (int)ceil($total / $per_page),
        ],
        'stats' => $stats,
    ]);

} catch (Exception $e) {
    error_log('get_requests error: ' . $e->getMessage() . ' | params: ' . json_encode($_GET));
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'message' => 'Server error'
    ]);
}
