<?php
header('Content-Type: application/json');
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: GET");

// Database Connection
$host = "localhost";
$user = "root";
$pass = "";
$dbname = "ms";

$conn = new mysqli($host, $user, $pass, $dbname);

if ($conn->connect_error) {
    echo json_encode(["status" => false, "message" => "Database connection failed"]);
    exit;
}

// Fetch all occupation types
$sql = "SELECT id, name, isActive, createdDate FROM occupationtype";
$result = $conn->query($sql);

if (!$result) {
    echo json_encode(["status" => false, "message" => "Query failed"]);
    exit;
}

$data = [];

while ($row = $result->fetch_assoc()) {
    $data[] = [
        "id" => (int)$row["id"],
        "name" => $row["name"],
        "isActive" => (int)$row["isActive"],
        "createdDate" => $row["createdDate"],
    ];
}

// Return final JSON response
if (count($data) > 0) {
    echo json_encode([
        "status" => true,
        "data" => $data
    ]);
} else {
    echo json_encode([
        "status" => false,
        "message" => "No records found"
    ]);
}

$conn->close();
?>
