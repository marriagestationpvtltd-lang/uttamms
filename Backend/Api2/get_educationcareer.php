<?php
header("Content-Type: application/json");
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: GET, POST");
header("Access-Control-Allow-Headers: Content-Type");

// ----------------- DATABASE CONNECTION -----------------
$host = "localhost";
$user = "root";
$pass = "";
$dbname = "ms";

$conn = new mysqli($host, $user, $pass, $dbname);
if ($conn->connect_error) {
    echo json_encode(["status" => "error", "message" => "DB connect failed"]);
    exit;
}

// Check if it's a GET request
if ($_SERVER['REQUEST_METHOD'] === 'GET') {
    // Get userid from query parameters
    $userid = isset($_GET['userid']) ? intval($_GET['userid']) : 0;
    
    if ($userid <= 0) {
        echo json_encode(["status" => "error", "message" => "Missing or invalid userid"]);
        exit;
    }
    
    // Prepare and execute query
    $stmt = $conn->prepare("SELECT * FROM educationcareer WHERE userid = ?");
    $stmt->bind_param("i", $userid);
    $stmt->execute();
    $result = $stmt->get_result();
    
    if ($result->num_rows > 0) {
        $data = $result->fetch_assoc();
        echo json_encode([
            "status" => "success",
            "data" => $data
        ]);
    } else {
        echo json_encode([
            "status" => "success",
            "data" => null,
            "message" => "No education/career data found for this user"
        ]);
    }
    
    $stmt->close();
} else {
    echo json_encode(["status" => "error", "message" => "Invalid request method"]);
}

$conn->close();
?>