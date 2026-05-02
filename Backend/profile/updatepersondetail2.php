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
$gender = isset($input['gender']) ? $input['gender'] : null;
$email = isset($input['email']) ? $input['email'] : null;
$contactNo = isset($input['contactNo']) ? $input['contactNo'] : null;
$maritalStatusId = isset($input['maritalStatusId']) ? intval($input['maritalStatusId']) : null;
$religionId = isset($input['religionId']) ? intval($input['religionId']) : null;
$subCommunityId = isset($input['subCommunityId']) ? intval($input['subCommunityId']) : null;
$motherTongue = isset($input['motherTongue']) ? $input['motherTongue'] : null;
$languages = isset($input['languages']) ? $input['languages'] : null;
$birthDate = isset($input['birthDate']) ? $input['birthDate'] : null;
$citizenship = isset($input['citizenship']) ? $input['citizenship'] : null;
$visaStatus = isset($input['visaStatus']) ? $input['visaStatus'] : null;

// Update basic info in users table
if ($gender || $email || $contactNo) {
    $updateUser = $conn->prepare("UPDATE users SET gender = ?, email = ?, contactNo = ? WHERE id = ?");
    $updateUser->bind_param("sssi", $gender, $email, $contactNo, $userId);
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
        SET maritalStatusId = ?, religionId = ?, subCommunityId = ?, motherTongue = ?, 
            languages = ?, birthDate = ?, citizenship = ?, visaStatus = ?
        WHERE userId = ?
    ";
    $stmt = $conn->prepare($updateSql);
    $stmt->bind_param(
        "iiisssssi",
        $maritalStatusId,
        $religionId,
        $subCommunityId,
        $motherTongue,
        $languages,
        $birthDate,
        $citizenship,
        $visaStatus,
        $userId
    );
    $success = $stmt->execute();
    $message = $success ? "User personal details updated successfully" : "Failed to update user details";
    $stmt->close();
} else {
    // Insert new record
    $insertSql = "
        INSERT INTO userpersonaldetail (
            userId, maritalStatusId, religionId, subCommunityId, 
            motherTongue, languages, birthDate, citizenship, visaStatus
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ";
    $stmt = $conn->prepare($insertSql);
    $stmt->bind_param(
        "iiiisssss",
        $userId,
        $maritalStatusId,
        $religionId,
        $subCommunityId,
        $motherTongue,
        $languages,
        $birthDate,
        $citizenship,
        $visaStatus
    );
    $success = $stmt->execute();
    $message = $success ? "User personal details inserted successfully" : "Failed to insert user details";
    $stmt->close();
}

$checkStmt->close();
$conn->close();

echo json_encode(["success" => $success, "message" => $message], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
?>
