<?php
/**
 * get_user_package_history.php
 *
 * Returns all package purchases for a specific user, newest first.
 *
 * GET  ?userid=<int>
 *
 * Response:
 *   {
 *     "success": true,
 *     "active": { ... } | null,
 *     "history": [ { id, package_name, amount, payment_method, purchasedate, expiredate, status, is_admin_assigned } ... ]
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

$userId = isset($_GET['userid']) ? (int) $_GET['userid'] : 0;
if ($userId <= 0) {
    http_response_code(422);
    echo json_encode(['success' => false, 'message' => 'userid is required']);
    exit;
}

define('DB_HOST', 'localhost');
define('DB_NAME', 'ms');
define('DB_USER', 'root');
define('DB_PASS', '');

try {
    $pdo = new PDO(
        'mysql:host=' . DB_HOST . ';dbname=' . DB_NAME . ';charset=utf8mb4',
        DB_USER,
        DB_PASS,
        [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION, PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC]
    );
} catch (PDOException $e) {
    http_response_code(503);
    echo json_encode(['success' => false, 'message' => 'Database connection failed']);
    exit;
}

// Backward compatibility: some DBs don't have user_package.netAmount yet.
$hasNetAmount = false;
try {
    $colCheck = $pdo->prepare("SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = ? AND TABLE_NAME = 'user_package' AND COLUMN_NAME = 'netAmount' LIMIT 1");
    $colCheck->execute([DB_NAME]);
    $hasNetAmount = (bool) $colCheck->fetchColumn();
} catch (Throwable $e) {
    $hasNetAmount = false;
}

$amountSelect = $hasNetAmount ? 'up.netAmount' : 'NULL AS netAmount';

$stmt = $pdo->prepare("
    SELECT
        up.id,
        up.userid,
        up.packageid,
        up.purchasedate,
        up.expiredate,
        up.paidby,
        $amountSelect,
        p.name  AS package_name,
        p.price AS package_price,
        p.duration AS package_duration
    FROM user_package up
    INNER JOIN packagelist p ON p.id = up.packageid
    WHERE up.userid = ?
    ORDER BY up.id DESC
");
$stmt->execute([$userId]);
$rows = $stmt->fetchAll();

$now    = new DateTime();
$active = null;
$history = [];

foreach ($rows as $r) {
    $expireDt = new DateTime($r['expiredate']);
    $isActive = $expireDt >= $now;

    // Detect admin-assigned: paidby contains "[Admin"
    $isAdminAssigned = strpos($r['paidby'] ?? '', '[Admin') !== false;

    // Extract clean payment method and note
    $paymentMethod = $r['paidby'] ?? '';
    $note = '';
    if ($isAdminAssigned) {
        // Format: "Cash [Admin: some note]" or "Cash [Admin]"
        if (preg_match('/^(.*?)\s*\[Admin(?::\s*(.*?))?\]$/', $paymentMethod, $m)) {
            $paymentMethod = trim($m[1]);
            $note = isset($m[2]) ? trim($m[2]) : '';
        }
    }

    // Amount: use netAmount if set, otherwise fall back to packagelist price
    $displayAmount = '';
    if (!empty($r['netAmount']) && is_numeric($r['netAmount'])) {
        $displayAmount = 'Rs ' . number_format((float) $r['netAmount'], 2);
    } else {
        $price = preg_replace('/[^0-9.]/', '', $r['package_price']);
        $displayAmount = 'Rs ' . number_format((float) $price, 2);
    }

    $rawAmount = !empty($r['netAmount']) && is_numeric($r['netAmount'])
        ? (float) $r['netAmount']
        : (float) preg_replace('/[^0-9.]/', '', $r['package_price']);

    $item = [
        'id'               => (int) $r['id'],
        'packageid'        => (int) $r['packageid'],
        'package_name'     => $r['package_name'],
        'package_duration' => $r['package_duration'] . ' Month',
        'amount'           => $rawAmount,
        'amount_display'   => $displayAmount,
        'payment_method'   => $paymentMethod,
        'note'             => $note,
        'purchasedate'     => $r['purchasedate'],
        'expiredate'       => $r['expiredate'],
        'status'           => $isActive ? 'active' : 'expired',
        'is_admin_assigned'=> $isAdminAssigned,
    ];

    if ($isActive && $active === null) {
        $active = $item;
    }
    $history[] = $item;
}

echo json_encode([
    'success' => true,
    'active'  => $active,
    'history' => $history,
    'count'   => count($history),
]);
