<?php
// NOTE: This file uses the older mysqli driver and raw SQL (SQL-injection risk).
// Use delete_proposal.php instead — it uses PDO prepared statements, supports
// JSON request bodies, and has proper security checks.
header("Content-Type: application/json");

// DB CONNECTION
$host = "localhost";
$user = "ms";
$pass = "ms";
$dbname = "ms";

$conn = new mysqli($host, $user, $pass, $dbname);
if ($conn->connect_error) {
    echo json_encode(["status" => "error", "message" => "DB connection failed"]);
    exit;
}

// CHECK REQUIRED PARAMS
if (!isset($_POST['user_id']) || !isset($_POST['proposal_id'])) {
    echo json_encode(["status" => "error", "message" => "Missing parameters"]);
    exit;
}

$user_id = intval($_POST['user_id']);
$proposal_id = intval($_POST['proposal_id']);

// CHECK IF PROPOSAL EXISTS AND BELONGS TO USER
$sql_check = "SELECT * FROM proposals 
              WHERE id = $proposal_id 
              AND (
                    sender_id = $user_id 
                    OR receiver_id = $user_id
                  )
              AND status IN ('pending','rejected')"; // Only pending or rejected

$result = $conn->query($sql_check);

if ($result->num_rows == 0) {
    echo json_encode(["status" => "error", "message" => "Proposal not found or cannot be deleted"]);
    exit;
}

// DELETE PROPOSAL
$sql_delete = "DELETE FROM proposals WHERE id = $proposal_id";
if ($conn->query($sql_delete)) {
    echo json_encode(["status" => "success", "message" => "Proposal deleted successfully"]);
} else {
    echo json_encode(["status" => "error", "message" => "Failed to delete proposal"]);
}
