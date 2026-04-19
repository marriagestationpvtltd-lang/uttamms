<?php
/**
 * user_activity.php  (admin)
 *
 * Paginated, filterable list of user activity records for the admin panel.
 *
 * GET params (all optional except none required):
 *   user_id       (int)    – filter to one user
 *   activity_type (string) – filter to one activity type
 *   date_from     (date)   – ISO-8601 date  e.g. 2024-01-01
 *   date_to       (date)   – ISO-8601 date  e.g. 2024-01-31
 *   search        (string) – full-name or email substring search
 *   page          (int)    – default 1
 *   limit         (int)    – default 20, max 100
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

require_once __DIR__ . '/../Api2/db_config.php';
require_once __DIR__ . '/auth.php';

// --------------------------------------------------------------------------
// Filters
// --------------------------------------------------------------------------

$user_id       = isset($_GET['user_id'])       ? (int)   $_GET['user_id']       : 0;
$activity_type = isset($_GET['activity_type']) ? trim($_GET['activity_type'])   : '';
$date_from     = isset($_GET['date_from'])     ? trim($_GET['date_from'])       : '';
$date_to       = isset($_GET['date_to'])       ? trim($_GET['date_to'])         : '';
$search        = isset($_GET['search'])        ? trim($_GET['search'])          : '';
$page          = max(1, (int) ($_GET['page']  ?? 1));
$limit         = min(100, max(1, (int) ($_GET['limit'] ?? 20)));
$offset        = ($page - 1) * $limit;

// Validate dates
$date_from_valid = preg_match('/^\d{4}-\d{2}-\d{2}$/', $date_from) ? $date_from : '';
$date_to_valid   = preg_match('/^\d{4}-\d{2}-\d{2}$/', $date_to)   ? $date_to   : '';

// --------------------------------------------------------------------------
// Build query
// --------------------------------------------------------------------------

$where  = [];
$params = [];

if ($user_id > 0) {
    $where[]  = 'ua.user_id = ?';
    $params[] = $user_id;
}

if ($activity_type !== '') {
    $where[]  = 'ua.activity_type = ?';
    $params[] = $activity_type;
}

if ($date_from_valid !== '') {
    $where[]  = 'ua.created_at >= ?';
    $params[] = $date_from_valid . ' 00:00:00';
}

if ($date_to_valid !== '') {
    $where[]  = 'ua.created_at <= ?';
    $params[] = $date_to_valid . ' 23:59:59';
}

if ($search !== '') {
    $like     = '%' . $search . '%';
    $where[]  = "(CONCAT(u.firstName, ' ', u.lastName) LIKE ? OR u.email LIKE ?)";
    $params[] = $like;
    $params[] = $like;
}

$whereSQL = $where ? ('WHERE ' . implode(' AND ', $where)) : '';

// --------------------------------------------------------------------------
// Execute
// --------------------------------------------------------------------------

try {
    // Total count
    $countStmt = $pdo->prepare("
        SELECT COUNT(*) AS total
        FROM   user_activities ua
        JOIN   users u ON u.id = ua.user_id
        $whereSQL
    ");
    $countStmt->execute($params);
    $total = (int) $countStmt->fetchColumn();

    // Data page
    $dataStmt = $pdo->prepare("
        SELECT
            ua.id,
            ua.user_id,
            CONCAT(u.firstName, ' ', u.lastName) AS user_name,
            u.email                               AS user_email,
            ua.activity_type,
            ua.description,
            ua.target_user_id,
            CONCAT(t.firstName, ' ', t.lastName) AS target_user_name,
            ua.ip_address,
            ua.device_info,
            ua.created_at
        FROM user_activities ua
        JOIN users u ON u.id = ua.user_id
        LEFT JOIN users t ON t.id = ua.target_user_id
        $whereSQL
        ORDER BY ua.created_at DESC
        LIMIT ? OFFSET ?
    ");

    $dataStmt->execute(array_merge($params, [$limit, $offset]));
    $rows = $dataStmt->fetchAll();

    echo json_encode([
        'status' => 'success',
        'total'  => $total,
        'page'   => $page,
        'limit'  => $limit,
        'pages'  => (int) ceil($total / $limit),
        'data'   => $rows,
    ]);

} catch (PDOException $e) {
    error_log('admin/user_activity error: ' . $e->getMessage());
    echo json_encode(['status' => 'error', 'message' => 'Server error. Please try again.']);
}
