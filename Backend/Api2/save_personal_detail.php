<?php
declare(strict_types=1);
header("Content-Type: application/json; charset=UTF-8");

// Disable notices/warnings to avoid HTML in output
error_reporting(E_ERROR | E_PARSE);

// DATABASE CONNECTION --------------------
$host = "localhost";
$user = "root";
$pass = "";
$dbname = "ms";

$conn = new mysqli($host, $user, $pass, $dbname);

if ($conn->connect_error) {
    echo json_encode(["status" => "error", "message" => "DB connect failed"]);
    exit;
}

// CHECK REQUIRED PARAM ---------------------
$user_id = isset($_POST['user_id']) ? intval($_POST['user_id']) : 0;

if ($user_id <= 0) {
    echo json_encode(["status" => "error", "message" => "Missing or invalid user_id"]);
    exit;
}

// OPTIONAL FIELDS --------------------------
$maritalStatusId = isset($_POST['maritalStatusId']) ? intval($_POST['maritalStatusId']) : null;
$height_name     = $_POST['height_name'] ?? null;
$weight_name     = $_POST['weight_name'] ?? null;
$haveSpecs       = isset($_POST['haveSpecs']) ? intval($_POST['haveSpecs']) : null;
$anyDisability   = isset($_POST['anyDisability']) ? intval($_POST['anyDisability']) : null;
$Disability      = $_POST['Disability'] ?? null;
$bloodGroup      = $_POST['bloodGroup'] ?? null;
$complexion      = $_POST['complexion'] ?? null;
$bodyType        = $_POST['bodyType'] ?? null;
$aboutMe         = $_POST['aboutMe'] ?? null;
$childStatus     = $_POST['childStatus'] ?? null;
$childLiveWith   = $_POST['childLiveWith'] ?? null;

// CHECK IF USER ALREADY HAS A RECORD ---------------------
$check = $conn->prepare("SELECT id FROM userpersonaldetail WHERE userid = ?");
$check->bind_param("i", $user_id);
$check->execute();
$check->store_result();
$hasRecord = $check->num_rows > 0;
$check->close(); // Close before re-using the connection for UPDATE/INSERT

try {
    if ($hasRecord) {
        // ---------------------- UPDATE ----------------------
        $stmt = $conn->prepare("
            UPDATE userpersonaldetail SET
                maritalStatusId = ?,
                height_name = ?,
                weight_name = ?,
                haveSpecs = ?,
                anyDisability = ?,
                Disability = ?,
                bloodGroup = ?,
                complexion = ?,
                bodyType = ?,
                aboutMe = ?,
                childStatus = ?,
                childLiveWith = ?
            WHERE userid = ?
        ");

        $stmt->bind_param(
            "issiiissssssi",
            $maritalStatusId,
            $height_name,
            $weight_name,
            $haveSpecs,
            $anyDisability,
            $Disability,
            $bloodGroup,
            $complexion,
            $bodyType,
            $aboutMe,
            $childStatus,
            $childLiveWith,
            $user_id
        );

        if ($stmt->execute()) {
            echo json_encode(["status" => "success", "message" => "Updated successfully"]);
        } else {
            echo json_encode(["status" => "error", "message" => "Update failed"]);
        }

    } else {
        // ---------------------- INSERT ----------------------
        $stmt = $conn->prepare("
            INSERT INTO userpersonaldetail (
                userid, maritalStatusId, height_name, weight_name,
                haveSpecs, anyDisability, Disability, bloodGroup,
                complexion, bodyType, aboutMe, childStatus, childLiveWith
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ");

        $stmt->bind_param(
            "iissiiissssss",
            $user_id,
            $maritalStatusId,
            $height_name,
            $weight_name,
            $haveSpecs,
            $anyDisability,
            $Disability,
            $bloodGroup,
            $complexion,
            $bodyType,
            $aboutMe,
            $childStatus,
            $childLiveWith
        );

        if ($stmt->execute()) {
            echo json_encode(["status" => "success", "message" => "Inserted successfully"]);
        } else {
            echo json_encode(["status" => "error", "message" => "Insert failed"]);
        }
    }
} catch (Exception $e) {
    echo json_encode(["status" => "error", "message" => $e->getMessage()]);
}

$conn->close();
exit; // ensure no extra output
