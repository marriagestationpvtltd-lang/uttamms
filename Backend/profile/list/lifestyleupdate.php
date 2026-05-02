<?php
error_reporting(E_ALL);
ini_set('display_errors', 1);

header('Content-Type: application/json');
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: POST");
header("Access-Control-Allow-Headers: Content-Type");

// Database connection
$host = "localhost";
$user = "root";
$pass = "";
$dbname = "ms";

$conn = new mysqli($host, $user, $pass, $dbname);
if ($conn->connect_error) {
    echo json_encode(["success" => false, "message" => "Database connection failed: " . $conn->connect_error]);
    exit;
}

// Read JSON input
$rawData = file_get_contents("php://input");
$data = json_decode($rawData, true);

// Validate JSON
if (json_last_error() !== JSON_ERROR_NONE) {
    echo json_encode(["success" => false, "message" => "Invalid JSON format"]);
    exit;
}

if (!$data || !isset($data['userId'])) {
    echo json_encode(["success" => false, "message" => "Missing required parameter: userId"]);
    exit;
}

// Sanitize input
$userId = intval($data['userId']);
$dietId = isset($data['dietId']) ? intval($data['dietId']) : null;
$smoking = isset($data['smoking']) ? $data['smoking'] : null;
$drinking = isset($data['drinking']) ? $data['drinking'] : null;

// Convert willingToGoAbroad to INT (1 or 0)
if (isset($data['willingToGoAbroad'])) {
    $val = strtolower(trim($data['willingToGoAbroad']));
    if ($val === "yes" || $val === "1" || $val === "true") {
        $willingToGoAbroad = 1;
    } elseif ($val === "no" || $val === "0" || $val === "false") {
        $willingToGoAbroad = 0;
    } else {
        $willingToGoAbroad = null;
    }
} else {
    $willingToGoAbroad = null;
}

// Validate dietId if provided (check if it exists in the 'diet' table)
if ($dietId !== null) {
    $checkDietQuery = "SELECT id FROM diet WHERE id = ?";
    $checkDietStmt = $conn->prepare($checkDietQuery);
    if (!$checkDietStmt) {
        echo json_encode(["success" => false, "message" => "SQL error (diet check): " . $conn->error]);
        exit;
    }

    $checkDietStmt->bind_param("i", $dietId);
    $checkDietStmt->execute();
    $dietResult = $checkDietStmt->get_result();

    if ($dietResult->num_rows == 0) {
        echo json_encode(["success" => false, "message" => "Invalid dietId: Diet does not exist"]);
        exit;
    }

    $checkDietStmt->close();
}

// Check if record exists
$checkQuery = "SELECT userId FROM userpersonaldetail WHERE userId = ?";
$checkStmt = $conn->prepare($checkQuery);
if (!$checkStmt) {
    echo json_encode(["success" => false, "message" => "SQL error (check): " . $conn->error]);
    exit;
}

$checkStmt->bind_param("i", $userId);
$checkStmt->execute();
$result = $checkStmt->get_result();

if ($result && $result->num_rows > 0) {
    // UPDATE existing record
    $sql = "
        UPDATE userpersonaldetail
        SET 
            dietId = ?, 
            smoking = ?, 
            drinking = ?, 
            willingToGoAbroad = ?
        WHERE userId = ?
    ";

    $stmt = $conn->prepare($sql);
    if (!$stmt) {
        echo json_encode(["success" => false, "message" => "SQL error (update): " . $conn->error]);
        exit;
    }

    $stmt->bind_param("issii", $dietId, $smoking, $drinking, $willingToGoAbroad, $userId);

    if ($stmt->execute()) {
        echo json_encode(["success" => true, "message" => "Lifestyle details updated successfully"]);
    } else {
        echo json_encode(["success" => false, "message" => "Failed to update record: " . $stmt->error]);
    }

    $stmt->close();
} else {
    // INSERT new record
    $sql = "
        INSERT INTO userpersonaldetail 
        (userId, dietId, smoking, drinking, willingToGoAbroad) 
        VALUES (?, ?, ?, ?, ?)
    ";

    $stmt = $conn->prepare($sql);
    if (!$stmt) {
        echo json_encode(["success" => false, "message" => "SQL error (insert): " . $conn->error]);
        exit;
    }

    $stmt->bind_param("iissi", $userId, $dietId, $smoking, $drinking, $willingToGoAbroad);

    if ($stmt->execute()) {
        echo json_encode(["success" => true, "message" => "Lifestyle details inserted successfully"]);
    } else {
        echo json_encode(["success" => false, "message" => "Failed to insert record: " . $stmt->error]);
    }

    $stmt->close();
}

$checkStmt->close();
$conn->close();
?>