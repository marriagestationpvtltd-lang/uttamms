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

try {
    $pdo = new PDO(
        "mysql:host=" . DB_HOST . ";dbname=" . DB_NAME,
        DB_USER,
        DB_PASS,
        [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]
    );

    $today = date('Y-m-d');
    $monthStart = date('Y-m-01');

    // ================= USERS =================
    $users = [];

    $users['total'] = (int)$pdo->query("
        SELECT COUNT(*) FROM users WHERE isDelete = 0
    ")->fetchColumn();

    $stmt = $pdo->prepare("
        SELECT COUNT(*) FROM users
        WHERE DATE(createdDate) = ? AND isDelete = 0
    ");
    $stmt->execute([$today]);
    $users['today_registered'] = (int)$stmt->fetchColumn();

    $stmt = $pdo->prepare("
        SELECT COUNT(*) FROM users
        WHERE createdDate >= ? AND isDelete = 0
    ");
    $stmt->execute([$monthStart]);
    $users['this_month_registered'] = (int)$stmt->fetchColumn();

    $users['verified'] = (int)$pdo->query("
        SELECT COUNT(*) FROM users WHERE isVerified = 1 AND isDelete = 0
    ")->fetchColumn();

    $users['unverified'] = (int)$pdo->query("
        SELECT COUNT(*) FROM users WHERE isVerified = 0 AND isDelete = 0
    ")->fetchColumn();

    $users['active'] = (int)$pdo->query("
        SELECT COUNT(*) FROM users WHERE isActive = 1 AND isDelete = 0
    ")->fetchColumn();

    $users['online'] = (int)$pdo->query("
        SELECT COUNT(*) FROM users WHERE isOnline = 1 AND isDelete = 0
    ")->fetchColumn();

    $users['by_type'] = $pdo->query("
        SELECT usertype, COUNT(*) total
        FROM users WHERE isDelete = 0
        GROUP BY usertype
    ")->fetchAll(PDO::FETCH_ASSOC);

    $users['by_gender'] = $pdo->query("
        SELECT gender, COUNT(*) total
        FROM users WHERE isDelete = 0
        GROUP BY gender
    ")->fetchAll(PDO::FETCH_ASSOC);

    $users['by_pageno'] = $pdo->query("
        SELECT pageno, COUNT(*) total
        FROM users
        WHERE isDelete = 0 AND pageno IS NOT NULL AND pageno != ''
        GROUP BY pageno
        ORDER BY total DESC
    ")->fetchAll(PDO::FETCH_ASSOC);

    // ================= PERMANENT ADDRESS =================
    $address = [];

    $address['total_with_address'] = (int)$pdo->query("
        SELECT COUNT(DISTINCT userid) FROM permanent_address
    ")->fetchColumn();

    $address['by_country'] = $pdo->query("
        SELECT country, COUNT(*) total
        FROM permanent_address
        WHERE country IS NOT NULL AND country != ''
        GROUP BY country
        ORDER BY total DESC
    ")->fetchAll(PDO::FETCH_ASSOC);

    $address['by_state'] = $pdo->query("
        SELECT state, COUNT(*) total
        FROM permanent_address
        WHERE state IS NOT NULL AND state != ''
        GROUP BY state
        ORDER BY total DESC
    ")->fetchAll(PDO::FETCH_ASSOC);

    $address['by_city'] = $pdo->query("
        SELECT city, COUNT(*) total
        FROM permanent_address
        WHERE city IS NOT NULL AND city != ''
        GROUP BY city
        ORDER BY total DESC
    ")->fetchAll(PDO::FETCH_ASSOC);

    $address['by_residential_status'] = $pdo->query("
        SELECT residentalstatus, COUNT(*) total
        FROM permanent_address
        WHERE residentalstatus IS NOT NULL AND residentalstatus != ''
        GROUP BY residentalstatus
        ORDER BY total DESC
    ")->fetchAll(PDO::FETCH_ASSOC);

    // ================= PAYMENTS =================
    $payments = [];

    $payments['total_sold'] = (int)$pdo->query("
        SELECT COUNT(*) FROM user_package
    ")->fetchColumn();

    $payments['active_packages'] = (int)$pdo->query("
        SELECT COUNT(*) FROM user_package WHERE expiredate >= CURDATE()
    ")->fetchColumn();

    $payments['expired_packages'] = (int)$pdo->query("
        SELECT COUNT(*) FROM user_package WHERE expiredate < CURDATE()
    ")->fetchColumn();

    $payments['total_earning'] = (float)$pdo->query("
        SELECT SUM(p.price)
        FROM user_package up
        JOIN packagelist p ON p.id = up.packageid
    ")->fetchColumn();

    $stmt = $pdo->prepare("
        SELECT SUM(p.price)
        FROM user_package up
        JOIN packagelist p ON p.id = up.packageid
        WHERE DATE(up.purchasedate) = ?
    ");
    $stmt->execute([$today]);
    $payments['today_earning'] = (float)$stmt->fetchColumn();

    $stmt = $pdo->prepare("
        SELECT SUM(p.price)
        FROM user_package up
        JOIN packagelist p ON p.id = up.packageid
        WHERE up.purchasedate >= ?
    ");
    $stmt->execute([$monthStart]);
    $payments['this_month_earning'] = (float)$stmt->fetchColumn();

    $payments['by_method'] = $pdo->query("
        SELECT paidby, COUNT(*) total
        FROM user_package
        GROUP BY paidby
    ")->fetchAll(PDO::FETCH_ASSOC);

    $payments['best_selling_package'] = $pdo->query("
        SELECT p.name, COUNT(*) total
        FROM user_package up
        JOIN packagelist p ON p.id = up.packageid
        GROUP BY p.id
        ORDER BY total DESC
        LIMIT 1
    ")->fetch(PDO::FETCH_ASSOC);

    // ================= RESPONSE =================
    echo json_encode([
        'success' => true,
        'dashboard' => [
            'users' => $users,
            'permanent_address' => $address,
            'payments' => [
                'total_sold' => $payments['total_sold'],
                'active_packages' => $payments['active_packages'],
                'expired_packages' => $payments['expired_packages'],
                'total_earning' => 'Rs ' . number_format($payments['total_earning'], 2),
                'today_earning' => 'Rs ' . number_format($payments['today_earning'], 2),
                'this_month_earning' => 'Rs ' . number_format($payments['this_month_earning'], 2),
                'by_method' => $payments['by_method'],
                'best_selling_package' => $payments['best_selling_package']
            ]
        ]
    ]);

} catch (Exception $e) {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'message' => 'Server error'
    ]);
}
