<?php
header('Content-Type: application/json');
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: GET");
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

// Get userId
if (!isset($_GET['userId'])) {
    echo json_encode(["success" => false, "message" => "Missing userId"]);
    exit;
}

$userId = intval($_GET['userId']);

$sql = "
SELECT 
    upd.userId,

    upd.educationId,
    e.name AS educationName,
    
    upd.educationTypeId,
    et.name AS educationTypeName,
    
    upd.educationMediumId,
    em.name AS educationMediumName,
    
    upd.occupationId,
    o.name AS occupationName,
    
    upd.designation,
    upd.employmentTypeId,
    emp.name AS employmentTypeName,
    
    upd.companyName,
    upd.businessName,
    
    upd.annualIncomeId,
    ai.value AS annualIncomeValue

FROM userpersonaldetail upd
LEFT JOIN education e ON upd.educationId = e.id
LEFT JOIN educationtype et ON upd.educationTypeId = et.id
LEFT JOIN educationmedium em ON upd.educationMediumId = em.id
LEFT JOIN occupation o ON upd.occupationId = o.id
LEFT JOIN employmenttype emp ON upd.employmentTypeId = emp.id
LEFT JOIN annualincome ai ON upd.annualIncomeId = ai.id
WHERE upd.userId = ?
";

$stmt = $conn->prepare($sql);
$stmt->bind_param("i", $userId);
$stmt->execute();
$result = $stmt->get_result();

if ($result->num_rows > 0) {
    $data = $result->fetch_assoc();
    echo json_encode([
        "success" => true,
        "data" => $data,
        "message" => "Education and occupation details fetched successfully"
    ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
} else {
    echo json_encode([
        "success" => false,
        "message" => "No education or occupation details found"
    ]);
}

$stmt->close();
$conn->close();
?>
