<?php
header("Content-Type: application/json; charset=UTF-8");
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: POST");
header("Access-Control-Allow-Headers: Content-Type");

// Database connection
$host = "localhost";
$user = "root";
$pass = "";
$dbname = "ms";

$conn = new mysqli($host, $user, $pass, $dbname);

// ✅ Show DB connection errors
if ($conn->connect_error) {
    http_response_code(500);
    echo json_encode(["error" => "Database connection failed", "details" => $conn->connect_error]);
    exit;
}

// ✅ Read and decode JSON input
$raw = file_get_contents("php://input");
if (!$raw) {
    echo json_encode(["error" => "No input data received"]);
    exit;
}

$data = json_decode($raw, true);

// ✅ Check JSON parse errors
if ($data === null) {
    echo json_encode(["error" => "Invalid JSON format"]);
    exit;
}

// ✅ Validate userId
if (empty($data['userId'])) {
    echo json_encode(["error" => "Missing required field: userId"]);
    exit;
}

// ✅ Sanitize inputs
$userId = $conn->real_escape_string($data['userId']);
$firstName = isset($data['firstName']) ? $conn->real_escape_string($data['firstName']) : null;
$middleName = isset($data['middleName']) ? $conn->real_escape_string($data['middleName']) : null;
$lastName = isset($data['lastName']) ? $conn->real_escape_string($data['lastName']) : null;
$imageUrl = isset($data['imageUrl']) ? $conn->real_escape_string($data['imageUrl']) : null;

// ✅ Begin transaction
$conn->begin_transaction();

try {
    // Update users table
    $sqlUser = "UPDATE users SET 
                    firstName = IFNULL('$firstName', firstName),
                    middleName = IFNULL('$middleName', middleName),
                    lastName = IFNULL('$lastName', lastName)
                WHERE id = '$userId'";
    $userUpdate = $conn->query($sqlUser);

    if (!$userUpdate) {
        throw new Exception("Failed to update users table: " . $conn->error);
    }

    // Update image if provided
    if ($imageUrl !== null && $imageUrl !== '') {
        $sqlImage = "UPDATE images SET imageUrl = '$imageUrl' WHERE createdBy = '$userId'";
        $imgUpdate = $conn->query($sqlImage);

        if (!$imgUpdate) {
            throw new Exception("Failed to update images table: " . $conn->error);
        }
    }

    // ✅ Commit transaction
    $conn->commit();

    // ✅ Fetch updated data
    $sqlSelect = "SELECT 
                    u.id,
                    u.firstName,
                    u.middleName,
                    u.lastName,
                    i.imageUrl
                  FROM users u
                  LEFT JOIN images i ON i.createdBy = u.id
                  WHERE u.id = '$userId'";

    $result = $conn->query($sqlSelect);

    if ($result && $result->num_rows > 0) {
        $user = $result->fetch_assoc();
        echo json_encode(["success" => true, "user" => $user]);
    } else {
        echo json_encode(["error" => "User not found"]);
    }

} catch (Exception $e) {
    $conn->rollback();
    http_response_code(500);
    echo json_encode(["error" => "Update failed", "details" => $e->getMessage()]);
}

$conn->close();
?>
