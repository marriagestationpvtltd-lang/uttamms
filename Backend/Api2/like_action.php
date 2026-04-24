<?php
header("Content-Type: application/json; charset=utf-8");

try {
    /* ================= DB CONFIG ================= */
    $dbHost = "127.0.0.1";
    $dbName = "ms";
    $dbUser = "ms";
    $dbPass = "ms";

    $pdo = new PDO(
        "mysql:host=$dbHost;dbname=$dbName;charset=utf8mb4",
        $dbUser,
        $dbPass,
        [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC
        ]
    );

    require_once __DIR__ . '/activity_helper.php';

    /* ================= INPUT ================= */
    $sender_id   = isset($_REQUEST['sender_id']) ? intval($_REQUEST['sender_id']) : 0;
    $receiver_id = isset($_REQUEST['receiver_id']) ? intval($_REQUEST['receiver_id']) : 0;
    $action      = isset($_REQUEST['action']) ? strtolower(trim($_REQUEST['action'])) : '';

    if ($sender_id <= 0 || $receiver_id <= 0) {
        echo json_encode([
            "success" => false,
            "message" => "Invalid sender_id or receiver_id"
        ]);
        exit;
    }

    if (!in_array($action, ['add', 'delete'])) {
        echo json_encode([
            "success" => false,
            "message" => "Invalid action. Use add or delete"
        ]);
        exit;
    }

    /* ================= ADD LIKE ================= */
    if ($action === 'add') {

        // Prevent duplicate likes
        $stmtCheck = $pdo->prepare("
            SELECT id FROM likes 
            WHERE sender_id = :sender AND receiver_id = :receiver
            LIMIT 1
        ");
        $stmtCheck->execute([
            ":sender" => $sender_id,
            ":receiver" => $receiver_id
        ]);

        if ($stmtCheck->fetch()) {
            echo json_encode([
                "success" => true,
                "message" => "Already liked",
                "like" => true
            ]);
            exit;
        }

        $stmtInsert = $pdo->prepare("
            INSERT INTO likes (sender_id, receiver_id)
            VALUES (:sender, :receiver)
        ");
        $stmtInsert->execute([
            ":sender" => $sender_id,
            ":receiver" => $receiver_id
        ]);

        logActivity($sender_id, 'like_sent', 'Liked a profile', $receiver_id);

        echo json_encode([
            "success" => true,
            "message" => "Liked successfully",
            "like" => true
        ]);
        exit;
    }

    /* ================= DELETE LIKE ================= */
    if ($action === 'delete') {

        $stmtDelete = $pdo->prepare("
            DELETE FROM likes 
            WHERE sender_id = :sender AND receiver_id = :receiver
        ");
        $stmtDelete->execute([
            ":sender" => $sender_id,
            ":receiver" => $receiver_id
        ]);

        logActivity($sender_id, 'like_removed', 'Removed like from a profile', $receiver_id);

        echo json_encode([
            "success" => true,
            "message" => "Like removed",
            "like" => false
        ]);
        exit;
    }

} catch (Exception $e) {
    echo json_encode([
        "success" => false,
        "message" => $e->getMessage()
    ]);
}
