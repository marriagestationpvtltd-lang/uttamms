<?php

header("Content-Type: application/json");
header("Access-Control-Allow-Origin: *");

// DB Config
$host = "localhost";
$db_name = "ms";
$username = "root";
$password = "";

try {
    $conn = new PDO(
        "mysql:host=$host;dbname=$db_name;charset=utf8",
        $username,
        $password
    );
    $conn->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);

    // ✅ Get POST data
    $data = json_decode(file_get_contents("php://input"), true);

    if (!isset($data['userid']) || !isset($data['viewuserid'])) {
        echo json_encode([
            "status" => false,
            "message" => "userid and viewuserid required"
        ]);
        exit;
    }

    $userid = intval($data['userid']);         // viewer
    $viewuserid = intval($data['viewuserid']); // profile owner

    // ❌ Prevent self-view
    if ($userid == $viewuserid) {
        echo json_encode([
            "status" => false,
            "message" => "Cannot view your own profile"
        ]);
        exit;
    }

    // 🔥 Check if already viewed in last 24 hours
    $checkQuery = "
        SELECT id FROM profile_view
        WHERE userid = :userid
        AND viewuserid = :viewuserid
        AND view_date >= NOW() - INTERVAL 1 DAY
        LIMIT 1
    ";

    $stmt = $conn->prepare($checkQuery);
    $stmt->execute([
        ':userid' => $userid,
        ':viewuserid' => $viewuserid
    ]);

    if ($stmt->rowCount() > 0) {
        echo json_encode([
            "status" => true,
            "message" => "Already viewed recently"
        ]);
        exit;
    }

    // ✅ Insert view
    $insertQuery = "
        INSERT INTO profile_view (userid, viewuserid, view_date, expire_date)
        VALUES (:userid, :viewuserid, NOW(), DATE_ADD(NOW(), INTERVAL 1 DAY))
    ";

    $stmt = $conn->prepare($insertQuery);
    $stmt->execute([
        ':userid' => $userid,
        ':viewuserid' => $viewuserid
    ]);

    echo json_encode([
        "status" => true,
        "message" => "Profile view recorded"
    ]);

} catch (PDOException $e) {
    echo json_encode([
        "status" => false,
        "message" => $e->getMessage()
    ]);
}