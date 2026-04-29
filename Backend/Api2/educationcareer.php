<?php
header("Content-Type: application/json");

// ----------------- DATABASE CONNECTION -----------------
$host = "localhost";
$user = "ms";
$pass = "ms";
$dbname = "ms";

$conn = new mysqli($host, $user, $pass, $dbname);
if ($conn->connect_error) {
    echo json_encode(["status" => "error", "message" => "DB connect failed"]);
    exit;
}

// ----------------- REQUIRED PARAM -----------------
$userid = isset($_POST['userid']) ? intval($_POST['userid']) : 0;
if ($userid <= 0) {
    echo json_encode(["status" => "error", "message" => "Missing or invalid userid"]);
    exit;
}

// ----------------- OTHER PARAMS -----------------
$educationmedium = $_POST['educationmedium'] ?? null;
$educationtype   = $_POST['educationtype'] ?? null;
$faculty         = $_POST['faculty'] ?? null;
$degree          = $_POST['degree'] ?? null;
$areyouworking   = $_POST['areyouworking'] ?? null;
$occupationtype  = $_POST['occupationtype'] ?? null;
$companyname     = $_POST['companyname'] ?? null;
$designation     = $_POST['designation'] ?? null;
$workingwith     = $_POST['workingwith'] ?? null;
$annualincome    = $_POST['annualincome'] ?? null;
$businessname    = $_POST['businessname'] ?? null;

// ----------------- UPSERT FUNCTION -----------------
function upsertEducationCareer($conn, $userid, $educationmedium, $educationtype, $faculty, $degree, $areyouworking, $occupationtype, $companyname, $designation, $workingwith, $annualincome, $businessname) {
    // Check if record exists
    $check = $conn->prepare("SELECT id FROM educationcareer WHERE userid = ?");
    $check->bind_param("i", $userid);
    $check->execute();
    $check->store_result();

    if ($check->num_rows > 0) {
        // UPDATE
        $stmt = $conn->prepare("
            UPDATE educationcareer SET
                educationmedium = ?,
                educationtype = ?,
                faculty = ?,
                degree = ?,
                areyouworking = ?,
                occupationtype = ?,
                companyname = ?,
                designation = ?,
                workingwith = ?,
                annualincome = ?,
                businessname = ?
            WHERE userid = ?
        ");
        $stmt->bind_param(
            "sssssssssssi",
            $educationmedium,
            $educationtype,
            $faculty,
            $degree,
            $areyouworking,
            $occupationtype,
            $companyname,
            $designation,
            $workingwith,
            $annualincome,
            $businessname,
            $userid
        );
    } else {
        // INSERT
        $stmt = $conn->prepare("
            INSERT INTO educationcareer
            (userid, educationmedium, educationtype, faculty, degree, areyouworking, occupationtype, companyname, designation, workingwith, annualincome, businessname)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ");
        $stmt->bind_param(
            "isssssssssss",
            $userid,
            $educationmedium,
            $educationtype,
            $faculty,
            $degree,
            $areyouworking,
            $occupationtype,
            $companyname,
            $designation,
            $workingwith,
            $annualincome,
            $businessname
        );
    }

    return $stmt->execute();
}

// ----------------- EXECUTE UPSERT -----------------
$result = upsertEducationCareer(
    $conn,
    $userid,
    $educationmedium,
    $educationtype,
    $faculty,
    $degree,
    $areyouworking,
    $occupationtype,
    $companyname,
    $designation,
    $workingwith,
    $annualincome,
    $businessname
);

// ----------------- RESPONSE -----------------
if ($result) {
    echo json_encode(["status" => "success", "message" => "Education/Career info saved successfully"]);
} else {
    echo json_encode(["status" => "error", "message" => "Failed to save data"]);
}

$conn->close();
?>
