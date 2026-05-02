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
    upd.dietId,
    d.name AS dietName,
    upd.smoking,
    upd.drinking,
    upd.willingToGoAbroad
FROM userpersonaldetail upd
LEFT JOIN diet d ON upd.dietId = d.id
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
        "message" => "Lifestyle details fetched successfully"
    ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
} else {
    echo json_encode([
        "success" => false,
        "message" => "No lifestyle details found"
    ]);
}

$stmt->close();
$conn->close();
?>
