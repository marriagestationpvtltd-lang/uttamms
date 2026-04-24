<?php
/**
 * get_user_activities.php
 *
 * Returns a paginated, filterable list of user activities for the admin panel.
 *
 * GET parameters:
 *   page          (int)    – page number, default 1
 *   limit         (int)    – records per page, default 50, max 200
 *   user_id       (int)    – filter by a specific user
 *   activity_type (string) – filter by activity type
 *   date_from     (string) – YYYY-MM-DD
 *   date_to       (string) – YYYY-MM-DD
 *   search        (string) – partial match on user name or description
 *
 * Response (JSON):
 *   {
 *     "success":     true,
 *     "activities":  [ { id, user_id, user_name, target_id, target_name,
 *                         activity_type, description, created_at } ],
 *     "total":       120,
 *     "page":        1,
 *     "limit":       50,
 *     "total_pages": 3
 *   }
 */

ini_set('display_errors', 0);
ini_set('log_errors', 1);
error_reporting(E_ALL);

header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

require_once __DIR__ . '/auth.php';
requireAdminAuth();

// ── DB connection ────────────────────────────────────────────────────────────

define('DB_HOST', 'localhost');
define('DB_NAME', 'ms');
define('DB_USER', 'ms');
define('DB_PASS', 'ms');

try {
    $pdo = new PDO(
        'mysql:host=' . DB_HOST . ';dbname=' . DB_NAME . ';charset=utf8mb4',
        DB_USER,
        DB_PASS,
        [
            PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES   => false,
        ]
    );
} catch (PDOException $e) {
    http_response_code(503);
    echo json_encode(['success' => false, 'message' => 'Database connection failed']);
    exit;
}

// ── Input sanitisation ───────────────────────────────────────────────────────

$page    = max(1, (int) ($_GET['page']  ?? 1));
$limit   = min(200, max(1, (int) ($_GET['limit'] ?? 50)));
$offset  = ($page - 1) * $limit;

$userId       = isset($_GET['user_id']) && $_GET['user_id'] !== ''
                    ? (int) $_GET['user_id'] : null;
$activityType = isset($_GET['activity_type']) && $_GET['activity_type'] !== ''
                    ? trim($_GET['activity_type']) : null;
$dateFrom     = isset($_GET['date_from']) && $_GET['date_from'] !== ''
                    ? trim($_GET['date_from']) : null;
$dateTo       = isset($_GET['date_to']) && $_GET['date_to'] !== ''
                    ? trim($_GET['date_to']) : null;
$search       = isset($_GET['search']) && $_GET['search'] !== ''
                    ? trim($_GET['search']) : null;

// ── Build WHERE clause ───────────────────────────────────────────────────────

$where  = [];
$params = [];

if ($userId !== null) {
    $where[]  = 'ua.user_id = ?';
    $params[] = $userId;
}

if ($activityType !== null) {
    $where[]  = 'ua.activity_type = ?';
    $params[] = $activityType;
}

if ($dateFrom !== null) {
    $where[]  = 'DATE(ua.created_at) >= ?';
    $params[] = $dateFrom;
}

if ($dateTo !== null) {
    $where[]  = 'DATE(ua.created_at) <= ?';
    $params[] = $dateTo;
}

if ($search !== null) {
    $like     = '%' . $search . '%';
    $where[]  = '(ua.user_name LIKE ? OR ua.description LIKE ? OR u.firstName LIKE ? OR u.lastName LIKE ?)';
    $params[] = $like;
    $params[] = $like;
    $params[] = $like;
    $params[] = $like;
}

$whereSql = $where ? ('WHERE ' . implode(' AND ', $where)) : '';

// ── Count total rows ─────────────────────────────────────────────────────────

try {
    $countSql = "
        SELECT COUNT(*) AS total
        FROM user_activities ua
        LEFT JOIN users u ON u.id = ua.user_id
        $whereSql
    ";
    $countStmt = $pdo->prepare($countSql);
    $countStmt->execute($params);
    $total = (int) $countStmt->fetchColumn();

} catch (PDOException $e) {
    error_log('get_user_activities count error: ' . $e->getMessage());
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Server error']);
    exit;
}

// ── Fetch page of rows ───────────────────────────────────────────────────────

try {
    $dataSql = "
        SELECT
            ua.id,
            ua.user_id,
            COALESCE(
                ua.user_name,
                CONCAT_WS(' ', u.firstName, u.lastName)
            )                                AS user_name,
            ua.target_user_id                AS target_id,
            ua.target_name,
            ua.activity_type,
            ua.description,
            ua.ip_address,
            ua.device_info,
            ua.created_at
        FROM user_activities ua
        LEFT JOIN users u ON u.id = ua.user_id
        $whereSql
        ORDER BY ua.created_at DESC
        LIMIT ? OFFSET ?
    ";

    $dataParams   = $params;
    $dataParams[] = $limit;
    $dataParams[] = $offset;

    $dataStmt = $pdo->prepare($dataSql);
    $dataStmt->execute($dataParams);
    $activities = $dataStmt->fetchAll();

    // Ensure numeric fields are ints / null
    foreach ($activities as &$row) {
        $row['id']        = (int) $row['id'];
        $row['user_id']   = (int) $row['user_id'];
        $row['target_id'] = $row['target_id'] !== null ? (int) $row['target_id'] : null;
    }
    unset($row);

} catch (PDOException $e) {
    error_log('get_user_activities fetch error: ' . $e->getMessage());
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Server error']);
    exit;
}

// ── Response ─────────────────────────────────────────────────────────────────

$totalPages = $total > 0 ? (int) ceil($total / $limit) : 1;

echo json_encode([
    'success'     => true,
    'activities'  => $activities,
    'total'       => $total,
    'page'        => $page,
    'limit'       => $limit,
    'total_pages' => $totalPages,
]);
