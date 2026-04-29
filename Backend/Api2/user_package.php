<?php
header("Content-Type: application/json");
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    http_response_code(200);
    exit();
}

require_once __DIR__ . '/db_config.php';

try {
    // Get userid from GET parameters
    $userid = isset($_GET['userid']) ? intval($_GET['userid']) : 0;

    if (!$userid) {
        echo json_encode(["success" => false, "message" => "Missing userid parameter"]);
        exit;
    }

    // Query to get user packages with package details
    $stmt = $pdo->prepare("
        SELECT 
            up.id AS user_package_id,
            up.userid,
            up.packageid,
            up.purchasedate,
            up.expiredate,
            up.paidby,
            pl.name AS package_name,
            pl.duration,
            pl.description,
            pl.price
        FROM user_package up
        LEFT JOIN packagelist pl ON up.packageid = pl.id
        WHERE up.userid = :userid
        ORDER BY up.purchasedate DESC
    ");

    $stmt->execute(['userid' => $userid]);
    $packages = $stmt->fetchAll(PDO::FETCH_ASSOC);

    if (!$packages) {
        echo json_encode(["success" => true, "message" => "No packages found for this user", "data" => []]);
        exit;
    }

    echo json_encode([
        "success" => true,
        "message" => "User packages retrieved successfully",
        "data"    => $packages,
    ]);

} catch (PDOException $e) {
    error_log('user_package.php DB error: ' . $e->getMessage());
    echo json_encode([
        "success" => false,
        "message" => "Server error. Please try again."
    ]);
}
?>
