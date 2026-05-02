<?php
// Add this at the very top to prevent any output before JSON
ob_start(); // Start output buffering

header("Content-Type: application/json");

// ----------------- DATABASE CONNECTION -----------------
$host = "localhost";
$user = "root";
$pass = "";
$dbname = "ms";

$conn = new mysqli($host, $user, $pass, $dbname);
if ($conn->connect_error) {
    // Clean any output before sending JSON
    ob_clean();
    echo json_encode(["status" => "error", "message" => "DB connect failed"]);
    exit;
}

// ----------------- REQUIRED PARAM -----------------
$userid = isset($_POST['userid']) ? intval($_POST['userid']) : 0;
if ($userid <= 0) {
    ob_clean();
    echo json_encode(["status" => "error", "message" => "Missing or invalid userid"]);
    exit;
}

// ----------------- OPTIONAL PARAMS -----------------
$belief       = $_POST['belief'] ?? null;
$birthcountry = $_POST['birthcountry'] ?? null;
$birthcity    = $_POST['birthcity'] ?? null;
$zodiacsign   = $_POST['zodiacsign'] ?? null;
$birthtime    = $_POST['birthtime'] ?? null;
$birthdate    = $_POST['birthdate'] ?? null;
$manglik      = $_POST['manglik'] ?? null;

// Debug logging (remove in production)
error_log("Received data: " . print_r($_POST, true));

// ----------------- CHECK IF RECORD EXISTS -----------------
$check = $conn->prepare("SELECT id FROM user_astrologic WHERE userid = ?");
if (!$check) {
    ob_clean();
    echo json_encode(["status" => "error", "message" => "Prepare failed: " . $conn->error]);
    exit;
}

$check->bind_param("i", $userid);
if (!$check->execute()) {
    ob_clean();
    echo json_encode(["status" => "error", "message" => "Execute failed: " . $check->error]);
    exit;
}
$check->store_result();

$response = [];

try {
    if ($check->num_rows > 0) {
        // UPDATE
        if ($belief === 'Yes') {
            $stmt = $conn->prepare("UPDATE user_astrologic SET belief=?, birthcountry=?, birthcity=?, zodiacsign=?, birthtime=?, birthdate=?, manglik=? WHERE userid=?");
            if ($stmt) {
                $stmt->bind_param("sssssssi", $belief, $birthcountry, $birthcity, $zodiacsign, $birthtime, $birthdate, $manglik, $userid);
            }
        } else {
            $stmt = $conn->prepare("UPDATE user_astrologic SET belief=?, birthcountry=NULL, birthcity=NULL, zodiacsign=NULL, birthtime=NULL, birthdate=NULL, manglik=NULL WHERE userid=?");
            if ($stmt) {
                $stmt->bind_param("si", $belief, $userid);
            }
        }
    } else {
        // INSERT
        if ($belief === 'Yes') {
            $stmt = $conn->prepare("INSERT INTO user_astrologic (userid, belief, birthcountry, birthcity, zodiacsign, birthtime, birthdate, manglik) VALUES (?, ?, ?, ?, ?, ?, ?, ?)");
            if ($stmt) {
                $stmt->bind_param("isssssss", $userid, $belief, $birthcountry, $birthcity, $zodiacsign, $birthtime, $birthdate, $manglik);
            }
        } else {
            $stmt = $conn->prepare("INSERT INTO user_astrologic (userid, belief) VALUES (?, ?)");
            if ($stmt) {
                $stmt->bind_param("is", $userid, $belief);
            }
        }
    }

    if (isset($stmt) && $stmt) {
        if ($stmt->execute()) {
            $response = ["status" => "success", "message" => "Astrologic details saved successfully"];
        } else {
            $response = ["status" => "error", "message" => "Execute failed: " . $stmt->error];
        }
        $stmt->close();
    } else {
        $response = ["status" => "error", "message" => "Statement preparation failed"];
    }
} catch (Exception $e) {
    $response = ["status" => "error", "message" => "Exception: " . $e->getMessage()];
}

$check->close();
$conn->close();

// Clean any output and send JSON
ob_clean();
echo json_encode($response);
exit;
?>