<?php
header("Content-Type: application/json");

// DB CONFIG
$host = "localhost";
$db   = "ms";
$user = "root";
$pass = "";

$conn = new mysqli($host, $user, $pass, $db);

if ($conn->connect_error) {
    echo json_encode([
        "status" => false,
        "message" => "Database connection failed"
    ]);
    exit;
}

// POST DATA
$user_id   = $_POST['user_id'] ?? '';
$fcm_token = $_POST['fcm_token'] ?? '';

if (empty($user_id) || empty($fcm_token)) {
    echo json_encode([
        "status" => false,
        "message" => "Missing parameters"
    ]);
    exit;
}

// UPDATE TOKEN
$stmt = $conn->prepare("UPDATE users SET fcm_token = ? WHERE id = ?");
$stmt->bind_param("si", $fcm_token, $user_id);

if ($stmt->execute()) {
    echo json_encode([
        "status" => true,
        "message" => "FCM token updated successfully"
    ]);
} else {
    echo json_encode([
        "status" => false,
        "message" => "Failed to update token"
    ]);
}

$stmt->close();
$conn->close();
