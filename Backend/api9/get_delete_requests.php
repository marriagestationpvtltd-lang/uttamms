<?php
/**
 * get_delete_requests.php
 *
 * Admin endpoint: list account-deletion requests.
 *
 * GET params:
 *   status   string  – "pending" | "approved" | "rejected" | "all"  (default: "all")
 *   search   string  – filter by user name or email
 *   page     int     – default 1
 *   per_page int     – default 20, max 100
 */

ini_set('display_errors', 0);
ini_set('log_errors', 1);
error_reporting(E_ALL);

header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

define('DB_HOST', 'localhost');
define('DB_NAME', 'ms');
define('DB_USER', 'root');
define('DB_PASS', '');
define('PROFILE_BASE_URL', 'https://digitallami.com/Api2/');

try {
    $pdo = new PDO(
        "mysql:host=" . DB_HOST . ";dbname=" . DB_NAME . ";charset=utf8mb4",
        DB_USER, DB_PASS,
        [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION, PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC]
    );

    $page     = max(1, (int)($_GET['page']     ?? 1));
    $per_page = min(100, max(1, (int)($_GET['per_page'] ?? 20)));
    $offset   = ($page - 1) * $per_page;

    $status   = trim($_GET['status'] ?? 'all');
    $search   = trim($_GET['search'] ?? '');

    $statusMetaStmt = $pdo->query("SELECT COLUMN_TYPE FROM information_schema.columns WHERE table_schema = DATABASE() AND table_name = 'delete_request' AND column_name = 'status' LIMIT 1");
    $statusMeta = $statusMetaStmt ? $statusMetaStmt->fetch(PDO::FETCH_ASSOC) : null;
    $columnType = strtolower((string)($statusMeta['COLUMN_TYPE'] ?? ''));
    $approvedStatusValue = (strpos($columnType, "'approved'") !== false) ? 'approved' : 'accepted';

    $validStatuses = ['pending', 'approved', 'rejected'];

    $where  = [];
    $params = [];

    if ($status !== 'all' && in_array($status, $validStatuses, true)) {
        $mappedStatus = ($status === 'approved') ? $approvedStatusValue : $status;
        $where[]            = "dr.status = :status";
        $params[':status']  = $mappedStatus;
    }

    if ($search !== '') {
        $where[]           = "(u.firstName LIKE :s OR u.lastName LIKE :s OR u.email LIKE :s)";
        $params[':s']      = '%' . $search . '%';
    }

    $whereSQL = $where ? ('WHERE ' . implode(' AND ', $where)) : '';

    // Total count
    $countSql = "
        SELECT COUNT(*) FROM delete_request dr
        JOIN users u ON u.id = dr.userid
        $whereSQL
    ";
    $countStmt = $pdo->prepare($countSql);
    $countStmt->execute($params);
    $total = (int)$countStmt->fetchColumn();

    // Fetch rows
    $dataSql = "
        SELECT
            dr.id,
            dr.userid,
            dr.delete_reason,
            dr.feedback,
            dr.status,
            dr.created_at,
            dr.reviewed_at,
            dr.admin_note,
            CONCAT(u.firstName, ' ', COALESCE(u.lastName, '')) AS user_name,
            u.email                                              AS user_email,
            u.profile_picture                                    AS user_photo,
            u.contactNo                                          AS user_phone
        FROM delete_request dr
        JOIN users u ON u.id = dr.userid
        $whereSQL
        ORDER BY
            CASE dr.status WHEN 'pending' THEN 0 ELSE 1 END,
            dr.created_at DESC
        LIMIT :limit OFFSET :offset
    ";

    $dataStmt = $pdo->prepare($dataSql);
    foreach ($params as $k => $v) {
        $dataStmt->bindValue($k, $v);
    }
    $dataStmt->bindValue(':limit',  $per_page, PDO::PARAM_INT);
    $dataStmt->bindValue(':offset', $offset,   PDO::PARAM_INT);
    $dataStmt->execute();
    $rows = $dataStmt->fetchAll();

    // Normalise photo URLs
    foreach ($rows as &$row) {
        if (!empty($row['user_photo']) && !preg_match('/^https?:\/\//', $row['user_photo'])) {
            $row['user_photo'] = PROFILE_BASE_URL . $row['user_photo'];
        }
    }
    unset($row);

    // Status summary counts
    $summary = [];
    $summaryStmt = $pdo->query(
        "SELECT status, COUNT(*) AS cnt FROM delete_request GROUP BY status"
    );
    foreach ($summaryStmt->fetchAll() as $s) {
        $summary[$s['status']] = (int)$s['cnt'];
    }

    echo json_encode([
        'success' => true,
        'data' => [
            'requests'   => $rows,
            'pagination' => [
                'total'       => $total,
                'page'        => $page,
                'per_page'    => $per_page,
                'total_pages' => $per_page > 0 ? (int)ceil($total / $per_page) : 1,
            ],
            'stats' => [
                'pending'  => $summary['pending']  ?? 0,
                'approved' => ($summary['approved'] ?? 0) + ($summary['accepted'] ?? 0),
                'rejected' => $summary['rejected'] ?? 0,
                'total'    => array_sum($summary),
            ],
        ],
    ]);

} catch (Throwable $e) {
    error_log('get_delete_requests.php error: ' . $e->getMessage());
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Server error']);
}
