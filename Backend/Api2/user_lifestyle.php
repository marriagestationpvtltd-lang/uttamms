<?php
header("Content-Type: application/json");

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

// GET POST DATA
$userid = isset($_POST['userid']) ? intval($_POST['userid']) : null;
$diet = isset($_POST['diet']) ? $_POST['diet'] : null;
$drinks = isset($_POST['drinks']) ? $_POST['drinks'] : null;
$drinktype = isset($_POST['drinktype']) ? $_POST['drinktype'] : null;
$smoke = isset($_POST['smoke']) ? $_POST['smoke'] : null;
$smoketype = isset($_POST['smoketype']) ? $_POST['smoketype'] : null;

// VALIDATION
if (!$userid) {
    echo json_encode(["status" => "error", "message" => "userid is required"]);
    exit;
}

// CHECK IF RECORD EXISTS
$check = $conn->prepare("SELECT id FROM user_lifestyle WHERE userid = ?");
$check->bind_param("i", $userid);
$check->execute();
$check->store_result();

if ($check->num_rows > 0) {
    // UPDATE EXISTING RECORD
    $update = $conn->prepare("UPDATE user_lifestyle SET diet=?, drinks=?, drinktype=?, smoke=?, smoketype=? WHERE userid=?");
    $update->bind_param("sssssi", $diet, $drinks, $drinktype, $smoke, $smoketype, $userid);
    if ($update->execute()) {
        echo json_encode(["status" => "success", "message" => "Lifestyle updated successfully"]);
    } else {
        echo json_encode(["status" => "error", "message" => "Update failed"]);
    }
    $update->close();
} else {
    // INSERT NEW RECORD
    $insert = $conn->prepare("INSERT INTO user_lifestyle (userid, diet, drinks, drinktype, smoke, smoketype) VALUES (?, ?, ?, ?, ?, ?)");
    $insert->bind_param("isssss", $userid, $diet, $drinks, $drinktype, $smoke, $smoketype);
    if ($insert->execute()) {
        echo json_encode(["status" => "success", "message" => "Lifestyle added successfully"]);
    } else {
        echo json_encode(["status" => "error", "message" => "Insert failed"]);
    }
    $insert->close();
}

$check->close();
$conn->close();
?>
