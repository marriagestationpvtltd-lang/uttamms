<?php
header("Content-Type: application/json");

// ----------------- DATABASE CONNECTION -----------------
$host = "localhost";
$user = "root";
$pass = "";
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

// ----------------- CURRENT ADDRESS PARAMS -----------------
$current_country           = $_POST['current_country'] ?? null;
$current_state             = $_POST['current_state'] ?? null;
$current_city              = $_POST['current_city'] ?? null;
$current_tole              = $_POST['current_tole'] ?? null;
$current_residentalstatus  = $_POST['current_residentalstatus'] ?? null;
$current_willingtogoabroad = isset($_POST['current_willingtogoabroad']) ? intval($_POST['current_willingtogoabroad']) : 0;
$current_visastatus        = $_POST['current_visastatus'] ?? null;

// ----------------- PERMANENT ADDRESS PARAMS -----------------
$permanent_country         = $_POST['permanent_country'] ?? null;
$permanent_state           = $_POST['permanent_state'] ?? null;
$permanent_city            = $_POST['permanent_city'] ?? null;
$permanent_tole            = $_POST['permanent_tole'] ?? null;
$permanent_residentalstatus= $_POST['permanent_residentalstatus'] ?? null;

// ----------------- FUNCTION TO INSERT/UPDATE -----------------
function upsertAddress($conn, $table, $userid, $country, $state, $city, $tole, $residentalstatus, $willingtogoabroad = null, $visastatus = null) {
    // Check if record exists
    $check = $conn->prepare("SELECT id FROM $table WHERE userid = ?");
    $check->bind_param("i", $userid);
    $check->execute();
    $check->store_result();

    if ($check->num_rows > 0) {
        // UPDATE
        if($table == 'current_address') {
            $stmt = $conn->prepare("
                UPDATE $table SET
                    country = ?,
                    state = ?,
                    city = ?,
                    tole = ?,
                    residentalstatus = ?,
                    willingtogoabroad = ?,
                    visastatus = ?
                WHERE userid = ?
            ");
            $stmt->bind_param("sssssiis", $country, $state, $city, $tole, $residentalstatus, $willingtogoabroad, $visastatus, $userid);
        } else {
            // permanent_address
            $stmt = $conn->prepare("
                UPDATE $table SET
                    country = ?,
                    state = ?,
                    city = ?,
                    tole = ?,
                    residentalstatus = ?
                WHERE userid = ?
            ");
            $stmt->bind_param("sssssi", $country, $state, $city, $tole, $residentalstatus, $userid);
        }
        return $stmt->execute();
    } else {
        // INSERT
        if($table == 'current_address') {
            $stmt = $conn->prepare("
                INSERT INTO $table
                (userid, country, state, city, tole, residentalstatus, willingtogoabroad, visastatus)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ");
            $stmt->bind_param("isssssis", $userid, $country, $state, $city, $tole, $residentalstatus, $willingtogoabroad, $visastatus);
        } else {
            // permanent_address
            $stmt = $conn->prepare("
                INSERT INTO $table
                (userid, country, state, city, tole, residentalstatus)
                VALUES (?, ?, ?, ?, ?, ?)
            ");
            $stmt->bind_param("isssss", $userid, $country, $state, $city, $tole, $residentalstatus);
        }
        return $stmt->execute();
    }
}

// ----------------- UPSERT BOTH TABLES -----------------
$currentResult = upsertAddress($conn, "current_address", $userid, $current_country, $current_state, $current_city, $current_tole, $current_residentalstatus, $current_willingtogoabroad, $current_visastatus);
$permanentResult = upsertAddress($conn, "permanent_address", $userid, $permanent_country, $permanent_state, $permanent_city, $permanent_tole, $permanent_residentalstatus);

// ----------------- RESPONSE -----------------
if($currentResult && $permanentResult) {
    echo json_encode(["status" => "success", "message" => "Addresses saved successfully"]);
} else {
    echo json_encode(["status" => "error", "message" => "Failed to save addresses"]);
}

$conn->close();
?>
