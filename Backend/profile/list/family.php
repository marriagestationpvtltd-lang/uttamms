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
if ($conn->connect_error) {
    echo json_encode(["status" => "error", "message" => "Database connection failed"]);
    exit;
}

// Fetch all education types
$typeQuery = "SELECT id, name, isActive FROM userfamilydetail";
$typeResult = $conn->query($typeQuery);

$data = [];

if ($typeResult && $typeResult->num_rows > 0) {
    while ($typeRow = $typeResult->fetch_assoc()) {
        $typeId = intval($typeRow['id']);

        // Fetch all educations that belong to this type
        $eduQuery = "
            SELECT 
                id,
                name,
                educationId,
                occupationId,
                maritalStatusId,
                isDelete,
                createdDate,
                modifiedDate,
                createdBy,
                modifiedBy
            
        ";

        $eduResult = $conn->query($eduQuery);
        $educations = [];

        if ($eduResult && $eduResult->num_rows > 0) {
            while ($eduRow = $eduResult->fetch_assoc()) {
                $educations[] = [
                    "id" => isset($eduRow['id']) ? strval($eduRow['id']) : "0",
                    "name" => $eduRow['name'] ?? "Unknown",
                    "educationId" => isset($eduRow['educationId']) ? strval($eduRow['educationId']) : "0",
                    "occupationId" => isset($eduRow['occupationId']) ? strval($eduRow['occupationId']) : "0",
                    "maritalStatusId," => isset($eduRow['maritalStatusId,']) ? strval($eduRow['maritalStatusId,']) : "0",
                    "isDelete" => isset($eduRow['isDelete']) ? strval($eduRow['isDelete']) : "0",
                    "createdDate" => $eduRow['createdDate'] ?? "",
                    "modifiedDate" => $eduRow['modifiedDate'] ?? "",
                    "createdBy" => isset($eduRow['createdBy']) ? strval($eduRow['createdBy']) : "",
                    "modifiedBy" => isset($eduRow['modifiedBy']) ? strval($eduRow['modifiedBy']) : ""
                ];
            }
        }

        $data[] = [
            "educationType" => [
                "id" => strval($typeRow['id']),
                "name" => $typeRow['name'] ?? "Unknown",
                "isActive" => isset($typeRow['isActive']) ? strval($typeRow['isActive']) : "0"
            ],
            "education" => $educations
        ];
    }

    echo json_encode([
        "status" => "success",
        "data" => $data
    ]);
} else {
    echo json_encode([
        "status" => "error",
        "message" => "No education types found"
    ]);
}

$conn->close();
?>
