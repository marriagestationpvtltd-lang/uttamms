<?php
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
    echo json_encode(["success" => false, "message" => "Database connection failed"]);
    exit;
}

// Read JSON input
$input = json_decode(file_get_contents('php://input'), true);

// Validate required fields
if (!isset($input['userId'])) {
    echo json_encode(["success" => false, "message" => "Missing userId"]);
    exit;
}

$userId = intval($input['userId']);
$heightid = isset($input['heightId']) ? $input['heightId'] : null;
$weight = isset($input['weight']) ? $input['weight'] : null;
$bodyType = isset($input['bodyType']) ? $input['bodyType'] : null;
$complexion = isset($input['complexion']) ? intval($input['complexion']) : null;
$bloodGroup = isset($input['bloodGroup']) ? intval($input['bloodGroup']) : null;
$eyeColor = isset($input['eyeColor']) ? intval($input['eyeColor']) : null;
$anyDisability = isset($input['anyDisability']) ? $input['anyDisability'] : null;

// Update basic info in users table
if ($heightid || $weight || $bodyType || $complexion || $bloodGroup || $eyeColor || $anyDisability) {
    $updateUser = $conn->prepare("UPDATE userpersonaldetail SET heightId = ?, weight = ?, bodyType = ?, complexion = ?, bloodGroup = ?, eyeColor =?, anyDisability = ? WHERE id = ?");
    $updateUser->bind_param("sssi", $heightid, $weight, $bodyType, $complexion, $bloodGroup, $eyeColor, $anyDisability);
    $updateUser->execute();
    $updateUser->close();
}

// Check if record exists in userpersonaldetail
$checkSql = "SELECT id FROM userpersonaldetail WHERE userId = ?";
$checkStmt = $conn->prepare($checkSql);
$checkStmt->bind_param("i", $userId);
$checkStmt->execute();
$checkResult = $checkStmt->get_result();

if ($checkResult->num_rows > 0) {
    // Update existing record
    $updateSql = "
        UPDATE userpersonaldetail 
        SET heightId = ?, weight = ?, bodyType = ?, complexion = ?, 
            bloodGroup = ?, eyeColor = ?, anyDisability = ? 
        WHERE userId = ?
    ";
    $stmt = $conn->prepare($updateSql);
    $stmt->bind_param(
        "iiisssssi",
        $heightid,
        $weight,
        $bodyType,
        $complexion,
        $bloodGroup,
        $eyeColor,
        $anyDisability
      
    );
    $success = $stmt->execute();
    $message = $success ? "User personal details updated successfully" : "Failed to update user details";
    $stmt->close();
} else {
    // Insert new record
    $insertSql = "
        INSERT INTO userpersonaldetail (
            userId, heightId, weight, bodyType, 
            complexion, bloodGroup, eyeColor, anyDisability, 
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ";
    $stmt = $conn->prepare($insertSql);
    $stmt->bind_param(
        "iiiisssss",
        $userId,
        $heightid,
        $weight,
        $bodyType,
        $complexion,
        $bloodGroup,
        $eyeColor,
        $anyDisability
       
    );
    $success = $stmt->execute();
    $message = $success ? "User personal details inserted successfully" : "Failed to insert user details";
    $stmt->close();
}

$checkStmt->close();
$conn->close();

echo json_encode(["success" => $success, "message" => $message], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
?>
