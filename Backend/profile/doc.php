<?php
header("Content-Type: application/json");
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: GET, POST, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type, Authorization");

$servername = "localhost";
$username = "root"; // change
$password = ""; // change
$dbname = "ms"; // change

$conn = new mysqli($servername, $username, $password, $dbname);
if ($conn->connect_error) {
    die(json_encode(["error" => "Database connection failed: " . $conn->connect_error]));
}

$method = $_SERVER['REQUEST_METHOD'];

if ($method == 'GET') {

    // Optional filters (?status=pending or ?userId=10)
    $where = [];
    if (isset($_GET['status'])) {
        $status = $conn->real_escape_string($_GET['status']);
        $where[] = "ud.status = '$status'";
    }
    if (isset($_GET['userId'])) {
        $userId = intval($_GET['userId']);
        $where[] = "ud.userId = $userId";
    }

    $whereClause = "";
    if (!empty($where)) {
        $whereClause = "WHERE " . implode(" AND ", $where);
    }

    // 🔥 Main Query with All Joins
    $sql = "
        SELECT 
            ud.id,
            ud.userId,
            u.firstName,
            u.lastName,
            u.email,
            u.contactNo,
            i.imageUrl,
            ud.documentTypeId,
            dt.name AS documentTypeName,
            ud.documentUrl,
            ud.isVerified,
            ud.status,
            ud.reject_reason,

            upd.educationId,
            e.name AS educationName,

            upd.occupationId,
            o.name AS occupationName,

            upd.maritalStatusId,
            m.name AS maritalStatusName,
            upd.familyType,

            upd.addressId,
            a.countryId,
            c.name AS countryName

        FROM userdocument ud
        LEFT JOIN users u ON ud.userId = u.id
        LEFT JOIN documenttype dt ON ud.documentTypeId = dt.id
        LEFT JOIN userpersonaldetail upd ON ud.userId = upd.userId
        LEFT JOIN education e ON upd.educationId = e.id
        LEFT JOIN occupation o ON upd.occupationId = o.id
        LEFT JOIN maritalstatus m ON upd.maritalStatusId = m.id
        LEFT JOIN addresses a ON upd.addressId = a.id
        LEFT JOIN countries c ON a.countryId = c.id
        LEFT JOIN images i ON i.createdBy = u.id
        $whereClause
        ORDER BY ud.id DESC
    ";

    $result = $conn->query($sql);

    $documents = [];
    $baseUploadUrl = "https://api.digitallami.com/"; // change this to your upload directory

    while ($row = $result->fetch_assoc()) {
        $documents[] = [
            "id" => $row['id'],
            "userId" => $row['userId'],

            // 🧍‍♂️ User Info
            "firstName" => $row['firstName'],
            "lastName" => $row['lastName'],
            "email" => $row['email'],
            "contactNo" => $row['contactNo'],
            "imageUrl" => $row['imageUrl'] ? $baseUploadUrl . $row['imageUrl'] : null,

            // 📄 Document Info
            "documentTypeId" => $row['documentTypeId'],
            "documentTypeName" => $row['documentTypeName'],
            "documentUrl" => $row['documentUrl'] ? $baseUploadUrl . $row['documentUrl'] : null,
            "status" => $row['status'],
            "isVerified" => (bool)$row['isVerified'],
            "reject_reason" => $row['reject_reason'],

            // 🎓 Personal Info
            "educationId" => $row['educationId'],
            "educationName" => $row['educationName'],

            "occupationId" => $row['occupationId'],
            "occupationName" => $row['occupationName'],

            "maritalStatusId" => $row['maritalStatusId'],
            "maritalStatusName" => $row['maritalStatusName'],
            "familyType" => $row['familyType'],

            // 🌍 Address & Country
            "addressId" => $row['addressId'],
            "countryId" => $row['countryId'],
            "countryName" => $row['countryName']
        ];
    }

    echo json_encode(["success" => true, "data" => $documents]);
}

elseif ($method == 'POST') {
    // Update document status and verification
    $input = json_decode(file_get_contents("php://input"), true);

    if (!isset($input['id']) || !isset($input['status'])) {
        echo json_encode(["success" => false, "message" => "Missing required fields"]);
        exit;
    }

    $id = intval($input['id']);
    $status = $conn->real_escape_string($input['status']);
    $reject_reason = isset($input['reject_reason']) ? $conn->real_escape_string($input['reject_reason']) : null;
    $isVerified = ($status == 'approved') ? 1 : 0;

    $sql = "UPDATE userdocument 
            SET status='$status',
                reject_reason=" . ($reject_reason ? "'$reject_reason'" : "NULL") . ",
                isVerified=$isVerified
            WHERE id=$id";

    if ($conn->query($sql)) {
        echo json_encode(["success" => true, "message" => "Document updated successfully"]);
    } else {
        echo json_encode(["success" => false, "message" => "Error updating document: " . $conn->error]);
    }
}

else {
    echo json_encode(["error" => "Invalid request method"]);
}

$conn->close();
?>
