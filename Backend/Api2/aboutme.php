<?php
header('Content-Type: application/json');

// Database configuration
$host = "localhost";
$db_name = "ms";
$username = "root";
$password = "";

// Create connection
$conn = new mysqli($host, $username, $password, $db_name);

// Check connection
if ($conn->connect_error) {
    die(json_encode([
        "status" => "error",
        "message" => "Database connection failed: " . $conn->connect_error
    ]));
}

// Get POST data
$userid = isset($_POST['userid']) ? intval($_POST['userid']) : 0;
$aboutMe = isset($_POST['aboutMe']) ? trim($_POST['aboutMe']) : '';

if ($userid <= 0 || $aboutMe === '') {
    echo json_encode([
        "status" => "error",
        "message" => "Invalid user ID or aboutMe is empty"
    ]);
    exit;
}

// Check if record exists
$checkSql = "SELECT userid FROM userpersonaldetail WHERE userid = ?";
$stmt = $conn->prepare($checkSql);
$stmt->bind_param("i", $userid);
$stmt->execute();
$result = $stmt->get_result();

if ($result->num_rows > 0) {
    // Update existing record
    $updateSql = "UPDATE userpersonaldetail SET aboutMe = ? WHERE userid = ?";
    $stmt = $conn->prepare($updateSql);
    $stmt->bind_param("si", $aboutMe, $userid);
    if ($stmt->execute()) {
        echo json_encode([
            "status" => "success",
            "message" => "AboutMe updated successfully"
        ]);
    } else {
        echo json_encode([
            "status" => "error",
            "message" => "Failed to update AboutMe"
        ]);
    }
} else {
    // Insert new record
    $insertSql = "INSERT INTO userpersonaldetail (userid, aboutMe) VALUES (?, ?)";
    $stmt = $conn->prepare($insertSql);
    $stmt->bind_param("is", $userid, $aboutMe);
    if ($stmt->execute()) {
        echo json_encode([
            "status" => "success",
            "message" => "AboutMe inserted successfully"
        ]);
    } else {
        echo json_encode([
            "status" => "error",
            "message" => "Failed to insert AboutMe"
        ]);
    }
}

// Close connection
$stmt->close();
$conn->close();
?>
