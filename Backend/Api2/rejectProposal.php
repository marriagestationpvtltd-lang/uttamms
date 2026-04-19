<?php
// NOTE: This file uses the older mysqli driver.
// Use reject_proposal.php instead — it uses PDO, supports JSON request bodies,
// and has cleaner error handling.
header("Content-Type: application/json");

// ---------------- DB CONNECTION ----------------
$conn = new mysqli("localhost", "ms", "ms", "ms");
if ($conn->connect_error) {
    echo json_encode(["success" => false, "message" => "DB connection failed"]);
    exit;
}

// ---------------- PARAMS ----------------
if (!isset($_POST['proposal_id'], $_POST['user_id'])) {
    echo json_encode(["success" => false, "message" => "Missing parameters"]);
    exit;
}

$proposalId = (int) $_POST['proposal_id'];
$userId     = (int) $_POST['user_id'];

try {

    // ---------------- FETCH PROPOSAL ----------------
    $sql = "
        SELECT id, sender_id, receiver_id, status 
        FROM proposals 
        WHERE id = ?
    ";
    $stmt = $conn->prepare($sql);
    $stmt->bind_param("i", $proposalId);
    $stmt->execute();
    $result = $stmt->get_result();

    if ($result->num_rows === 0) {
        echo json_encode(["success" => false, "message" => "Proposal not found"]);
        exit;
    }

    $proposal = $result->fetch_assoc();

    // ---------------- CHECK STATUS ----------------
    if ($proposal['status'] !== 'pending') {
        echo json_encode([
            "success" => false,
            "message" => "Proposal already processed"
        ]);
        exit;
    }

    // ---------------- AUTHORIZATION ----------------
    if ($proposal['sender_id'] != $userId && $proposal['receiver_id'] != $userId) {
        echo json_encode([
            "success" => false,
            "message" => "You are not authorized to reject this proposal"
        ]);
        exit;
    }

    // ---------------- REJECT PROPOSAL ----------------
    $updateSql = "UPDATE proposals SET status = 'rejected' WHERE id = ?";
    $updateStmt = $conn->prepare($updateSql);
    $updateStmt->bind_param("i", $proposalId);

    if (!$updateStmt->execute()) {
        echo json_encode(["success" => false, "message" => "Failed to reject proposal"]);
        exit;
    }

    // ---------------- SEND NOTIFICATION (OPTIONAL) ----------------
    $otherUserId = ($proposal['sender_id'] == $userId)
        ? $proposal['receiver_id']
        : $proposal['sender_id'];

    try {
        $notifSql = "
            INSERT INTO notifications 
            (user_id, title, message, type, reference_id, created_at)
            VALUES (?, 'Proposal Rejected', 'Your proposal has been rejected', 'proposal', ?, NOW())
        ";
        $notifStmt = $conn->prepare($notifSql);
        $notifStmt->bind_param("ii", $otherUserId, $proposalId);
        $notifStmt->execute();
    } catch (Exception $e) {
        // Ignore notification failure
    }

    echo json_encode([
        "success" => true,
        "message" => "Proposal rejected successfully"
    ]);

} catch (Exception $e) {
    echo json_encode([
        "success" => false,
        "message" => "Server error",
        "debug"   => $e->getMessage()
    ]);
}

$conn->close();
?>
