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

    // ================= FETCH PAYMENTS =================
    $stmt = $pdo->prepare("
        SELECT
            up.id,
            up.paidby,
            up.userid,
            up.packageid,
            up.purchasedate,
            up.expiredate,

            u.firstName,
            u.lastName,
            u.email,

            p.name  AS package_name,
            p.price AS package_price

        FROM user_package up
        INNER JOIN users u ON u.id = up.userid
        INNER JOIN packagelist p ON p.id = up.packageid
        ORDER BY up.id DESC
    ");

    $stmt->execute();
    $payments = $stmt->fetchAll(PDO::FETCH_ASSOC);

    // ================= CALCULATIONS =================
    $today = new DateTime();

    $totalSold = 0;
    $totalEarning = 0;
    $activeCount = 0;
    $expiredCount = 0;
    $paymentMethodCount = [];

    foreach ($payments as &$p) {

        // ---- Package status ----
        $expireDate = new DateTime($p['expiredate']);
        if ($expireDate >= $today) {
            $p['package_status'] = 'active';
            $activeCount++;
        } else {
            $p['package_status'] = 'expired';
            $expiredCount++;
        }

        // ---- Count sold ----
        $totalSold++;

        // ---- Sum earning ----
        $price = (float)$p['package_price'];
        $totalEarning += $price;

        // ---- Payment method stats ----
        $method = $p['paidby'];
        $paymentMethodCount[$method] =
            ($paymentMethodCount[$method] ?? 0) + 1;

        // ---- Format price for frontend ----
        $p['package_price'] = 'Rs ' . number_format($price, 2);
    }

    // ================= TOP PAYMENT METHOD =================
    arsort($paymentMethodCount);
    $topPaymentMethod = !empty($paymentMethodCount)
        ? array_key_first($paymentMethodCount)
        : null;

    // ================= RESPONSE =================
    echo json_encode([
        'success' => true,
        'summary' => [
            'total_packages_sold' => $totalSold,
            'total_earning' => 'Rs ' . number_format($totalEarning, 2),
            'top_payment_method' => $topPaymentMethod,
            'active_packages' => $activeCount,
            'expired_packages' => $expiredCount
        ],
        'data' => $payments
    ]);

} catch (Exception $e) {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'message' => 'Server error'
    ]);
}
