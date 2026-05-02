<?php
header("Content-Type: application/json");

// ✅ Nepal timezone for PHP
date_default_timezone_set('Asia/Kathmandu');

// DB config
$host = "localhost";
$db_name = "ms";
$username = "root";
$password = "";

try {
    $pdo = new PDO(
        "mysql:host=$host;dbname=$db_name;charset=utf8",
        $username,
        $password
    );
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);

    // ✅ Force MySQL timezone to Nepal (+05:45)
    $pdo->exec("SET time_zone = '+05:45'");

    // Support JSON + POST
    $input = json_decode(file_get_contents("php://input"), true);
    if (!$input) $input = $_POST;

    if (!isset($input['user_id'])) {
        echo json_encode([
            "status" => false,
            "message" => "user_id required"
        ]);
        exit;
    }

    $user_id = intval($input['user_id']);

    // ✅ Use PHP time (Nepal)
    $currentTime = date('Y-m-d H:i:s');

    // Debug (optional)
    // echo $currentTime; exit;

    $stmt = $pdo->prepare("
        UPDATE users 
        SET lastLogin = :time 
        WHERE id = :user_id
    ");

    $stmt->execute([
        ':time' => $currentTime,
        ':user_id' => $user_id
    ]);

    echo json_encode([
        "status" => true,
        "message" => "lastLogin updated",
        "time" => $currentTime
    ]);

} catch (PDOException $e) {
    echo json_encode([
        "status" => false,
        "message" => $e->getMessage()
    ]);
}