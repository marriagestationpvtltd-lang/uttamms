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
    
    // Prepare response array
    $response = [
        "status" => "success",
        "data" => [
            "family" => null,
            "members" => []
        ]
    ];
    
    // Get family details
    $stmt = $conn->prepare("SELECT * FROM user_family WHERE userid = ?");
    $stmt->bind_param("i", $userid);
    $stmt->execute();
    $result = $stmt->get_result();
    
    if ($result->num_rows > 0) {
        $familyData = $result->fetch_assoc();
        $response["data"]["family"] = $familyData;
    }
    $stmt->close();
    
    // Get family members
    $stmt2 = $conn->prepare("SELECT * FROM user_family_members WHERE userid = ?");
    $stmt2->bind_param("i", $userid);
    $stmt2->execute();
    $result2 = $stmt2->get_result();
    
    if ($result2->num_rows > 0) {
        while ($row = $result2->fetch_assoc()) {
            $response["data"]["members"][] = $row;
        }
    }
    $stmt2->close();
    
    echo json_encode($response);
} else {
    echo json_encode(["status" => "error", "message" => "Invalid request method"]);
}

$conn->close();
?>