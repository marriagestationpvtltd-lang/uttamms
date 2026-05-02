<?php
header("Content-Type: application/json");
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: GET");
header("Access-Control-Allow-Headers: Content-Type");

// Database connection
$host = "localhost";
$user = "root";
$pass = "";
$dbname = "ms";

$conn = new mysqli($host, $user, $pass, $dbname);

// Check connection
if ($conn->connect_error) {
    echo json_encode(["status" => false, "message" => "Database connection failed"]);
    exit;
}

// Optional: fetch by ID
$id = isset($_GET['id']) ? intval($_GET['id']) : null;

function formatEducationType($row) {
    return [
        'id' => isset($row['id']) ? intval($row['id']) : 0,
        'name' => isset($row['name']) && $row['name'] !== "" ? $row['name'] : 'Unknown',
        'isActive' => isset($row['isActive']) ? intval($row['isActive']) : 0,
        'isDelete' => isset($row['isDelete']) ? intval($row['isDelete']) : 0,
        'createdDate' => isset($row['createdDate']) ? $row['createdDate'] : '',
        'modifiedDate' => isset($row['modifiedDate']) ? $row['modifiedDate'] : '',
        'createdBy' => isset($row['createdBy']) ? strval($row['createdBy']) : '',
        'modifiedBy' => isset($row['modifiedBy']) ? strval($row['modifiedBy']) : ''
    ];
}

if ($id) {
    // Single record
    $stmt = $conn->prepare("SELECT * FROM educationtype WHERE id = ?");
    $stmt->bind_param("i", $id);
    $stmt->execute();
    $result = $stmt->get_result();

    if ($row = $result->fetch_assoc()) {
        echo json_encode(["status" => true, "data" => formatEducationType($row)]);
    } else {
        echo json_encode(["status" => false, "message" => "No record found"]);
    }

    $stmt->close();
} else {
    // All records
    $result = $conn->query("SELECT * FROM educationtype");
    $data = [];

    while ($row = $result->fetch_assoc()) {
        $data[] = formatEducationType($row);
    }

    echo json_encode([
        "status" => true,
        "data" => $data
    ]);
}

$conn->close();
?>
