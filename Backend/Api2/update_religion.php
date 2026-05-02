<?php
declare(strict_types=1);
header("Content-Type: application/json; charset=UTF-8");

// Disable notices/warnings to avoid HTML output
error_reporting(E_ERROR | E_PARSE);

// DATABASE CONNECTION
$host = "localhost";
$user = "root";
$pass = "";
$dbname = "ms";

$conn = new mysqli($host, $user, $pass, $dbname);
if ($conn->connect_error) {
    echo json_encode(["status" => "error", "message" => "DB connect failed"]);
    exit;
}

// CHECK REQUIRED PARAM
$user_id = isset($_POST['user_id']) ? intval($_POST['user_id']) : 0;
if ($user_id <= 0) {
    echo json_encode(["status" => "error", "message" => "Missing or invalid user_id"]);
    exit;
}

// OPTIONAL FIELDS
$religionId    = isset($_POST['religionId']) ? intval($_POST['religionId']) : null;
$communityId   = isset($_POST['communityId']) ? intval($_POST['communityId']) : null;
$subCommunityId= isset($_POST['subCommunityId']) ? intval($_POST['subCommunityId']) : null;
$castlanguage  = $_POST['castlanguage'] ?? null;

// CHECK IF USER ALREADY HAS A RECORD
$check = $conn->prepare("SELECT id FROM userpersonaldetail WHERE userid = ?");
$check->bind_param("i", $user_id);
$check->execute();
$check->store_result();

try {
    if ($check->num_rows > 0) {
        // ---------------------- UPDATE ----------------------
        $stmt = $conn->prepare("
            UPDATE userpersonaldetail SET
                religionId = ?,
                communityId = ?,
                subCommunityId = ?,
                castlanguage = ?
            WHERE userid = ?
        ");

        $stmt->bind_param(
            "iiiis",
            $religionId,
            $communityId,
            $subCommunityId,
            $castlanguage,
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
                userid, religionId, communityId, subCommunityId, castlanguage
            ) VALUES (?, ?, ?, ?, ?)
        ");

        $stmt->bind_param(
            "iiiss",
            $user_id,
            $religionId,
            $communityId,
            $subCommunityId,
            $castlanguage
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
exit;
