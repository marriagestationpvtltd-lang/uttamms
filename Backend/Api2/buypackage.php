<?php
header('Content-Type: application/json; charset=utf-8');

require_once __DIR__ . '/db_config.php';

try {
    // Get input data
    $data = json_decode(file_get_contents("php://input"), true);

    if (!isset($data['userid'], $data['packageid'], $data['paidby'])) {
        echo json_encode([
            "success" => false,
            "message" => "Missing required fields."
        ]);
        exit;
    }

    $userid    = intval($data['userid']);
    $packageid = intval($data['packageid']);
    $paidby    = trim($data['paidby']);

    if ($userid <= 0 || $packageid <= 0) {
        echo json_encode(["success" => false, "message" => "Invalid userid or packageid."]);
        exit;
    }

    // Get package duration from packagelist table
    $stmt = $pdo->prepare("SELECT duration FROM packagelist WHERE id = :packageid");
    $stmt->execute(['packageid' => $packageid]);
    $package = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$package) {
        echo json_encode([
            "success" => false,
            "message" => "Package not found."
        ]);
        exit;
    }

    $durationMonths = (int)$package['duration'];
    $purchasedate   = date('Y-m-d H:i:s');
    $expiredate     = date('Y-m-d H:i:s', strtotime("+$durationMonths months"));

    // Insert into user_package
    $pdo->beginTransaction();

    $stmt = $pdo->prepare("
        INSERT INTO user_package (userid, packageid, purchasedate, expiredate, paidby)
        VALUES (:userid, :packageid, :purchasedate, :expiredate, :paidby)
    ");
    $stmt->execute([
        'userid'       => $userid,
        'packageid'    => $packageid,
        'purchasedate' => $purchasedate,
        'expiredate'   => $expiredate,
        'paidby'       => $paidby,
    ]);

    // Update users.usertype to 'paid' so the user can send requests
    $pdo->prepare("UPDATE users SET usertype = 'paid' WHERE id = ?")->execute([$userid]);

    $pdo->commit();

    echo json_encode([
        "success" => true,
        "message" => "Package purchased successfully.",
        "data"    => [
            "userid"       => $userid,
            "packageid"    => $packageid,
            "purchasedate" => $purchasedate,
            "expiredate"   => $expiredate,
            "paidby"       => $paidby,
        ],
    ]);

} catch (PDOException $e) {
    if (isset($pdo) && $pdo->inTransaction()) {
        $pdo->rollBack();
    }
    error_log('buypackage.php DB error: ' . $e->getMessage());
    echo json_encode([
        "success" => false,
        "message" => "Server error. Please try again."
    ]);
}
?>
