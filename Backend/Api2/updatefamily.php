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

// ----------------- USER FAMILY PARAMS -----------------
$familytype          = $_POST['familytype'] ?? '';
$familybackground    = $_POST['familybackground'] ?? '';
$fatherstatus        = $_POST['fatherstatus'] ?? '';
$fathername          = $_POST['fathername'] ?? '';
$fathereducation     = $_POST['fathereducation'] ?? '';
$fatheroccupation    = $_POST['fatheroccupation'] ?? '';
$motherstatus        = $_POST['motherstatus'] ?? '';
$mothercaste         = $_POST['mothercaste'] ?? '';
$mothereducation     = $_POST['mothereducation'] ?? '';
$motheroccupation    = $_POST['motheroccupation'] ?? '';
$familyorigin        = $_POST['familyorigin'] ?? '';

// ----------------- USER FAMILY MEMBERS PARAMS -----------------
$membersJson = $_POST['members'] ?? '[]';
$members = json_decode($membersJson, true);

// ----------------- FUNCTION TO UPSERT user_family -----------------
function upsertUserFamily($conn, $userid, $familytype, $familybackground, $fatherstatus, $fathername, $fathereducation, $fatheroccupation, $motherstatus, $mothercaste, $mothereducation, $motheroccupation, $familyorigin) {
    $check = $conn->prepare("SELECT id FROM user_family WHERE userid = ?");
    $check->bind_param("i", $userid);
    $check->execute();
    $check->store_result();

    if ($check->num_rows > 0) {
        // UPDATE
        $stmt = $conn->prepare("
            UPDATE user_family SET
                familytype = ?,
                familybackground = ?,
                fatherstatus = ?,
                fathername = ?,
                fathereducation = ?,
                fatheroccupation = ?,
                motherstatus = ?,
                mothercaste = ?,
                mothereducation = ?,
                motheroccupation = ?,
                familyorigin = ?
            WHERE userid = ?
        ");
        $stmt->bind_param("sssssssssssi", $familytype, $familybackground, $fatherstatus, $fathername, $fathereducation, $fatheroccupation, $motherstatus, $mothercaste, $mothereducation, $motheroccupation, $familyorigin, $userid);
    } else {
        // INSERT
        $stmt = $conn->prepare("
            INSERT INTO user_family
            (userid, familytype, familybackground, fatherstatus, fathername, fathereducation, fatheroccupation, motherstatus, mothercaste, mothereducation, motheroccupation, familyorigin)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ");
        $stmt->bind_param("isssssssssss", $userid, $familytype, $familybackground, $fatherstatus, $fathername, $fathereducation, $fatheroccupation, $motherstatus, $mothercaste, $mothereducation, $motheroccupation, $familyorigin);
    }

    return $stmt->execute();
}

// ----------------- FUNCTION TO HANDLE MULTIPLE FAMILY MEMBERS -----------------
function upsertUserFamilyMembers($conn, $userid, $members) {
    // First, delete existing members for this user
    $deleteStmt = $conn->prepare("DELETE FROM user_family_members WHERE userid = ?");
    $deleteStmt->bind_param("i", $userid);
    $deleteStmt->execute();
    $deleteStmt->close();

    // If no members to insert, return success
    if (empty($members)) {
        return true;
    }

    // Insert all new members
    $insertStmt = $conn->prepare("
        INSERT INTO user_family_members 
        (userid, membertype, maritalstatus, livestatus) 
        VALUES (?, ?, ?, ?)
    ");

    $success = true;
    foreach ($members as $member) {
        $membertype = $member['membertype'] ?? '';
        $maritalstatus = $member['maritalstatus'] ?? '';
        $livestatus = $member['livestatus'] ?? '';
        
        $insertStmt->bind_param("isss", $userid, $membertype, $maritalstatus, $livestatus);
        if (!$insertStmt->execute()) {
            $success = false;
        }
    }
    $insertStmt->close();
    
    return $success;
}

// ----------------- TRANSACTION START -----------------
$conn->begin_transaction();

try {
    // Upsert user_family
    $familyResult = upsertUserFamily($conn, $userid, $familytype, $familybackground, $fatherstatus, $fathername, $fathereducation, $fatheroccupation, $motherstatus, $mothercaste, $mothereducation, $motheroccupation, $familyorigin);
    
    // Upsert user_family_members
    $membersResult = upsertUserFamilyMembers($conn, $userid, $members);

    if ($familyResult && $membersResult) {
        $conn->commit();
        echo json_encode(["status" => "success", "message" => "Family details saved successfully"]);
    } else {
        $conn->rollback();
        echo json_encode(["status" => "error", "message" => "Failed to save family details"]);
    }
} catch (Exception $e) {
    $conn->rollback();
    echo json_encode(["status" => "error", "message" => "Database error: " . $e->getMessage()]);
}

$conn->close();
?>