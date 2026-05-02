<?php
declare(strict_types=1);
header("Content-Type: application/json; charset=UTF-8");
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: GET, POST, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type, Authorization");

// Enable CORS for preflight requests
if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    http_response_code(200);
    exit();
}

// DATABASE CONNECTION --------------------
$host = "localhost";
$user = "root";
$pass = "";
$dbname = "ms";

$conn = new mysqli($host, $user, $pass, $dbname);

if ($conn->connect_error) {
    http_response_code(500);
    echo json_encode([
        "status" => "error", 
        "message" => "Database connection failed: " . $conn->connect_error
    ]);
    exit();
}

// Set charset to UTF-8
$conn->set_charset("utf8mb4");

// CHECK REQUEST METHOD ---------------------
if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    http_response_code(405);
    echo json_encode([
        "status" => "error", 
        "message" => "Method not allowed. Use GET method."
    ]);
    exit();
}

// GET USER ID FROM QUERY PARAMETERS ---------------------
$user_id = isset($_GET['user_id']) ? intval($_GET['user_id']) : 0;

// Also check POST for backward compatibility
if ($user_id <= 0 && isset($_POST['user_id'])) {
    $user_id = intval($_POST['user_id']);
}

if ($user_id <= 0) {
    http_response_code(400);
    echo json_encode([
        "status" => "error", 
        "message" => "Missing or invalid user_id parameter"
    ]);
    exit();
}

try {
    // SQL query to fetch personal details with marital status name
    $sql = "
        SELECT 
            up.id,
            up.userid,
            up.maritalStatusId,
            ms.name as marital_status_name,
            up.height_name,
            up.weight_name,
            up.haveSpecs,
            up.anyDisability,
            up.Disability,
            up.bloodGroup,
            up.complexion,
            up.bodyType,
            up.aboutMe,
            up.childStatus,
            up.childLiveWith,
            up.createdDate,
            up.modifiedDate
        FROM userpersonaldetail up
        LEFT JOIN maritalstatus ms ON up.maritalStatusId = ms.id
        WHERE up.userid = ?
    ";
    
    $stmt = $conn->prepare($sql);
    
    if (!$stmt) {
        throw new Exception("SQL prepare failed: " . $conn->error);
    }
    
    $stmt->bind_param("i", $user_id);
    $stmt->execute();
    $result = $stmt->get_result();
    
    if ($result->num_rows > 0) {
        $data = $result->fetch_assoc();
        
        // Convert boolean values from database (0/1) to actual booleans
        $data['haveSpecs'] = (int)$data['haveSpecs'] === 1;
        $data['anyDisability'] = (int)$data['anyDisability'] === 1;
        
        // Prepare the response
        $response = [
            "status" => "success",
            "message" => "Personal details found",
            "data" => [
                "userid" => (int)$data['userid'],
                "maritalStatusId" => $data['maritalStatusId'] !== null ? (int)$data['maritalStatusId'] : null,
                "marital_status_name" => $data['marital_status_name'],
                "height_name" => $data['height_name'],
                "weight_name" => $data['weight_name'],
                "haveSpecs" => $data['haveSpecs'],
                "anyDisability" => $data['anyDisability'],
                "Disability" => $data['Disability'],
                "bloodGroup" => $data['bloodGroup'],
                "complexion" => $data['complexion'],
                "bodyType" => $data['bodyType'],
                "aboutMe" => $data['aboutMe'],
                "childStatus" => $data['childStatus'],
                "childLiveWith" => $data['childLiveWith'],
                "created_at" => $data['createdDate'],
                "updated_at" => $data['modifiedDate']
            ]
        ];
        
        http_response_code(200);
        echo json_encode($response, JSON_PRETTY_PRINT);
        
    } else {
        // No data found for this user
        $response = [
            "status" => "success",
            "message" => "No personal details found for this user",
            "data" => null
        ];
        
        http_response_code(200);
        echo json_encode($response, JSON_PRETTY_PRINT);
    }
    
    $stmt->close();
    
} catch (Exception $e) {
    http_response_code(500);
    echo json_encode([
        "status" => "error", 
        "message" => "Server error: " . $e->getMessage(),
        "trace" => $e->getTraceAsString()
    ], JSON_PRETTY_PRINT);
    
    // Log the error for debugging (optional)
    error_log("Personal Details API Error: " . $e->getMessage());
}

$conn->close();
exit();