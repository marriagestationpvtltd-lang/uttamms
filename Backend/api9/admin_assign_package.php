<?php
/**
 * admin_assign_package.php
 *
 * Admin-only endpoint to manually assign a package to a user.
 *
 * POST body (JSON):
 *   userid         (int)    required
 *   packageid      (int)    required
 *   amount         (float)  required – actual amount paid
 *   payment_method (string) required – e.g. Cash, eSewa, Khalti, Bank Transfer
 *   note           (string) optional
 *
 * Response:
 *   { "success": true, "message": "...", "data": { ... } }
 */

ini_set('display_errors', 0);
ini_set('log_errors', 1);
error_reporting(E_ALL);

header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['success' => false, 'message' => 'Method not allowed']);
    exit;
}

define('DB_HOST', 'localhost');
define('DB_NAME', 'ms');
define('DB_USER', 'root');
define('DB_PASS', '');

$input = json_decode(file_get_contents('php://input'), true) ?? [];

$userId        = isset($input['userid'])         ? (int)   $input['userid']         : 0;
$packageId     = isset($input['packageid'])      ? (int)   $input['packageid']      : 0;
$amount        = isset($input['amount'])         ? (float) $input['amount']         : -1;
$paymentMethod = isset($input['payment_method']) ? trim((string) $input['payment_method']) : '';
$note          = isset($input['note'])           ? trim((string) $input['note'])           : '';

if ($userId <= 0 || $packageId <= 0 || $amount < 0 || $paymentMethod === '') {
    http_response_code(422);
    echo json_encode([
        'success' => false,
        'message' => 'userid, packageid, amount, and payment_method are required',
    ]);
    exit;
}

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

// Some live DBs still don't have user_package.netAmount. Detect once and branch safely.
$hasNetAmount = false;
try {
    $colCheck = $pdo->prepare("SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = ? AND TABLE_NAME = 'user_package' AND COLUMN_NAME = 'netAmount' LIMIT 1");
    $colCheck->execute([DB_NAME]);
    $hasNetAmount = (bool) $colCheck->fetchColumn();
} catch (Throwable $e) {
    $hasNetAmount = false;
}

// Verify user exists
$userCheck = $pdo->prepare('SELECT id, firstName, lastName FROM users WHERE id = ? LIMIT 1');
$userCheck->execute([$userId]);
$user = $userCheck->fetch();
if (!$user) {
    http_response_code(404);
    echo json_encode(['success' => false, 'message' => 'User not found']);
    exit;
}

// Get package details
$pkgCheck = $pdo->prepare('SELECT id, name, duration, price FROM packagelist WHERE id = ? LIMIT 1');
$pkgCheck->execute([$packageId]);
$package = $pkgCheck->fetch();
if (!$package) {
    http_response_code(404);
    echo json_encode(['success' => false, 'message' => 'Package not found']);
    exit;
}

$durationMonths = (int) $package['duration'];
$purchasedate   = date('Y-m-d H:i:s');
$expiredate     = date('Y-m-d H:i:s', strtotime("+$durationMonths months"));

// note is appended to paidby for traceability: "Cash [Admin]" or "Cash [Admin: note]"
$paidbyValue = $paymentMethod . ' [Admin' . ($note !== '' ? ': ' . mb_substr($note, 0, 80) : '') . ']';

try {
    $pdo->beginTransaction();

    // Insert package assignment
    if ($hasNetAmount) {
        $stmt = $pdo->prepare(" 
            INSERT INTO user_package (userid, packageid, purchasedate, expiredate, paidby, netAmount)
            VALUES (?, ?, ?, ?, ?, ?)
        ");
        $stmt->execute([
            $userId,
            $packageId,
            $purchasedate,
            $expiredate,
            $paidbyValue,
            number_format($amount, 2, '.', ''),
        ]);
    } else {
        $stmt = $pdo->prepare(" 
            INSERT INTO user_package (userid, packageid, purchasedate, expiredate, paidby)
            VALUES (?, ?, ?, ?, ?)
        ");
        $stmt->execute([
            $userId,
            $packageId,
            $purchasedate,
            $expiredate,
            $paidbyValue,
        ]);
    }

    $insertedId = (int) $pdo->lastInsertId();

    // Upgrade user to 'paid'
    $pdo->prepare("UPDATE users SET usertype = 'paid' WHERE id = ?")->execute([$userId]);

    $pdo->commit();

    echo json_encode([
        'success' => true,
        'message' => 'Package assigned successfully',
        'data' => [
            'id'             => $insertedId,
            'userid'         => $userId,
            'user_name'      => trim($user['firstName'] . ' ' . $user['lastName']),
            'packageid'      => $packageId,
            'package_name'   => $package['name'],
            'amount'         => number_format($amount, 2, '.', ''),
            'payment_method' => $paymentMethod,
            'note'           => $note,
            'purchasedate'   => $purchasedate,
            'expiredate'     => $expiredate,
        ],
    ]);

} catch (PDOException $e) {
    if ($pdo->inTransaction()) $pdo->rollBack();
    error_log('admin_assign_package.php error: ' . $e->getMessage());
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Server error while assigning package']);
}
