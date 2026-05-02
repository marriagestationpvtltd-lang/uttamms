<?php
header('Content-Type: application/json');
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: GET");

// Database connection
$host = "localhost";
$user = "root";
$pass = "";
$dbname = "ms";

$conn = new mysqli($host, $user, $pass, $dbname);
if ($conn->connect_error) {
    echo json_encode([
        "success" => false,
        "message" => "Database connection failed"
    ]);
    exit;
}

// Get userId from query parameter
$userId = isset($_GET['userId']) ? intval($_GET['userId']) : 0;

if ($userId <= 0) {
    echo json_encode([
        "success" => false,
        "message" => "Invalid or missing userId"
    ]);
    exit;
}

// Fetch user personal details with joins
$sql = "
    SELECT 
        u.gender,
        u.email,
        u.contactNo,
        upd.maritalStatusId,
        ms.name AS maritalStatusName,
        upd.religionId,
        r.name AS religionName,
        upd.subCommunityId,
        sc.name AS subCommunityName,
        upd.motherTongue,
        upd.languages,
        upd.birthDate,
        upd.citizenship,
        upd.visaStatus
    FROM users u
    LEFT JOIN userpersonaldetail upd ON u.id = upd.userId
    LEFT JOIN maritalstatus ms ON upd.maritalStatusId = ms.id
    LEFT JOIN religion r ON upd.religionId = r.id
    LEFT JOIN subcommunity sc ON upd.subCommunityId = sc.id
    WHERE u.id = ?
";

$stmt = $conn->prepare($sql);
$stmt->bind_param("i", $userId);
$stmt->execute();
$result = $stmt->get_result();

if ($result->num_rows > 0) {
    $data = $result->fetch_assoc();
    echo json_encode([
        "success" => true,
        "data" => [
            "gender" => $data["gender"],
            "email" => $data["email"],
            "contactNo" => $data["contactNo"],
            "maritalStatusId" => $data["maritalStatusId"],
            "maritalStatusName" => $data["maritalStatusName"],
            "religionId" => $data["religionId"],
            "religionName" => $data["religionName"],
            "subCommunityId" => $data["subCommunityId"],
            "subCommunityName" => $data["subCommunityName"],
            "motherTongue" => $data["motherTongue"],
            "languages" => $data["languages"],
            "birthDate" => $data["birthDate"],
            "citizenship" => $data["citizenship"],
            "visaStatus" => $data["visaStatus"]
        ],
        "message" => "User personal details fetched successfully"
    ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
} else {
    echo json_encode([
        "success" => false,
        "message" => "User not found"
    ]);
}

$stmt->close();
$conn->close();
?>
