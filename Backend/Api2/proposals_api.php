<?php
// Turn off error reporting to avoid HTML output
error_reporting(0);
ini_set('display_errors', 0);

header("Content-Type: application/json");

// ---------------- DB CONNECTION ----------------
$conn = new mysqli("localhost", "root", "", "ms");

if ($conn->connect_error) {
    echo json_encode([
        "status" => "error",
        "message" => "Database connection failed"
    ]);
    exit;
}

// ---------------- PARAMS ----------------
if (!isset($_GET['user_id'], $_GET['type'])) {
    echo json_encode([
        "status" => "error",
        "message" => "Missing parameters"
    ]);
    exit;
}

$user_id = (int) $_GET['user_id'];
$type    = $_GET['type'];

$validTypes = ["received", "sent", "accepted"];
if (!in_array($type, $validTypes)) {
    echo json_encode([
        "status" => "error",
        "message" => "Invalid type"
    ]);
    exit;
}

try {

    // ---------------- SQL QUERY ----------------
    $sql = "
    SELECT 
        p.*,

        -- SENDER
        us.id AS senderId,
        us.firstName AS senderFirst,
        us.lastName AS senderLast,
        us.profile_picture AS senderPic,
        us.status AS senderVerified,
        us.id AS senderMemberId,

        ec_sender.designation AS senderDesignation,
        pa_sender.city AS senderCity,
        ms_sender.name AS senderMaritalStatus,

        -- RECEIVER
        ur.id AS receiverId,
        ur.firstName AS receiverFirst,
        ur.lastName AS receiverLast,
        ur.profile_picture AS receiverPic,
        ur.status AS receiverVerified,
        ur.id AS receiverMemberId,

        ec_receiver.designation AS receiverDesignation,
        pa_receiver.city AS receiverCity,
        ms_receiver.name AS receiverMaritalStatus

    FROM proposals p

    -- SENDER JOINS
    JOIN users us ON us.id = p.sender_id
    LEFT JOIN educationcareer ec_sender ON ec_sender.userid = us.id
    LEFT JOIN permanent_address pa_sender ON pa_sender.userid = us.id
    LEFT JOIN userpersonaldetail upd_sender ON upd_sender.userid = us.id
    LEFT JOIN maritalstatus ms_sender ON ms_sender.id = upd_sender.maritalStatusId

    -- RECEIVER JOINS
    JOIN users ur ON ur.id = p.receiver_id
    LEFT JOIN educationcareer ec_receiver ON ec_receiver.userid = ur.id
    LEFT JOIN permanent_address pa_receiver ON pa_receiver.userid = ur.id
    LEFT JOIN userpersonaldetail upd_receiver ON upd_receiver.userid = ur.id
    LEFT JOIN maritalstatus ms_receiver ON ms_receiver.id = upd_receiver.maritalStatusId

    WHERE
    ";

    if ($type === "received") {
        $sql .= " p.receiver_id = $user_id AND p.status = 'pending' ";
    } elseif ($type === "sent") {
        $sql .= " p.sender_id = $user_id AND p.status = 'pending' ";
    } else {
        $sql .= " (p.sender_id = $user_id OR p.receiver_id = $user_id)
                  AND p.status IN ('accepted','rejected') ";
    }

    $sql .= " ORDER BY p.created_at DESC";

    $result = $conn->query($sql);
    if ($result === false) {
        throw new Exception($conn->error);
    }

    $data = [];

    while ($row = $result->fetch_assoc()) {

        $isSender = ($row['sender_id'] == $user_id);

        $data[] = [
            "proposalId"     => (string) $row["id"],
            "senderId"       => (string) $row["sender_id"],
            "receiverId"     => (string) $row["receiver_id"],
            "requestType"    => $row["request_type"],
            "status"         => $row["status"],

            "firstName"      => $isSender ? $row["receiverFirst"] : $row["senderFirst"],
            "lastName"       => $isSender ? $row["receiverLast"]  : $row["senderLast"],
            "profilePicture"=> $isSender ? $row["receiverPic"]   : $row["senderPic"],
            "verified"       => (($isSender ? $row["receiverVerified"] : $row["senderVerified"]) === "verified"),

            "occupation"     => $isSender ? ($row["receiverDesignation"] ?? "") : ($row["senderDesignation"] ?? ""),
            "city"           => $isSender ? ($row["receiverCity"] ?? "")        : ($row["senderCity"] ?? ""),
            "maritalstatus"  => $isSender ? ($row["receiverMaritalStatus"] ?? "") : ($row["senderMaritalStatus"] ?? ""),

            // ✅ MEMBER ID FROM users.id
            "memberid"       => (string) ($isSender ? $row["receiverMemberId"] : $row["senderMemberId"]),

            "type"           => $type
        ];
    }

    echo json_encode([
        "status" => "success",
        "count"  => count($data),
        "data"   => $data
    ]);

} catch (Exception $e) {
    echo json_encode([
        "status" => "error",
        "message" => "Server error",
        "debug" => $e->getMessage()
    ]);
}

$conn->close();
?>
