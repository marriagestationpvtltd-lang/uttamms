<?php
header("Content-Type: application/json");

// Database connection
$host = "localhost";
$user = "root";
$pass = "";
$db   = "ms";

$conn = new mysqli($host, $user, $pass, $db);

// Check connection
if ($conn->connect_error) {
    die(json_encode([
        "status" => "error",
        "message" => "Database connection failed"
    ]));
}

// Validate input
if (!isset($_GET['user_id']) || !isset($_GET['pageno'])) {
    echo json_encode([
        "status" => "error",
        "message" => "Missing user_id or pageno parameter"
    ]);
    exit;
}

$user_id = intval($_GET['user_id']);
$pageno  = intval($_GET['pageno']);

// Update query
$sql = "UPDATE users SET pageno = ? WHERE id = ?";
$stmt = $conn->prepare($sql);
$stmt->bind_param("ii", $pageno, $user_id);

if ($stmt->execute()) {
    echo json_encode([
        "status" => "success",
        "message" => "Page number updated successfully",
        "user_id" => $user_id,
        "pageno" => $pageno
    ]);
} else {
    echo json_encode([
        "status" => "error",
        "message" => "Failed to update page number"
    ]);
}

$stmt->close();
$conn->close();
?>
