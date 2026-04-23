<?php
header('Content-Type: application/json; charset=utf-8');

// Database configuration
$dbHost = "127.0.0.1";
$dbName = "ms";
$dbUser = "ms";
$dbPass = "ms";

try {
    $pdo = new PDO(
        "mysql:host=$dbHost;dbname=$dbName;charset=utf8",
        $dbUser,
        $dbPass
    );
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);

    // ===============================
    // 🔥 SUPPORT JSON + FORM DATA
    // ===============================
    $input = json_decode(file_get_contents('php://input'), true);
    if (!$input) {
        $input = $_POST;
    }

    // ===============================
    // 🔥 MAP KEYS
    // ===============================
    $sender_id = isset($input['sender_id']) 
        ? intval($input['sender_id']) 
        : (isset($input['myid']) ? intval($input['myid']) : null);

    $receiver_id = isset($input['receiver_id']) 
        ? intval($input['receiver_id']) 
        : (isset($input['userid']) ? intval($input['userid']) : null);

    $request_type = isset($input['request_type']) 
        ? $input['request_type'] 
        : 'Photo';

    // ===============================
    // ✅ VALIDATION
    // ===============================
    $valid_types = ['Photo', 'Profile', 'Chat'];

    if (!$sender_id || !$receiver_id || !in_array($request_type, $valid_types)) {
        echo json_encode([
            "success" => false,
            "message" => "Invalid input. sender_id, receiver_id, and valid request_type required."
        ]);
        exit;
    }

    // ❌ Prevent self request
    if ($sender_id == $receiver_id) {
        echo json_encode([
            "success" => false,
            "message" => "You cannot send request to yourself"
        ]);
        exit;
    }

    // ===============================
    // 🔒 REQUIRE SENDER IDENTITY VERIFICATION
    // ===============================
    $maritalDocTypes = ['Death Certificate', 'Marriage Certificate', 'Divorce Decree', 'Court Order', 'Separation Document'];
    $placeholders    = implode(',', array_fill(0, count($maritalDocTypes), '?'));

    $verifyStmt = $pdo->prepare("
        SELECT id
        FROM user_documents
        WHERE userid = ?
          AND status = 'approved'
          AND documenttype NOT IN ($placeholders)
        LIMIT 1
    ");
    $verifyParams = array_merge([$sender_id], $maritalDocTypes);
    $verifyStmt->execute($verifyParams);

    if ($verifyStmt->rowCount() === 0) {
        echo json_encode([
            "success"    => false,
            "message"    => "Identity verification required to send requests. Please upload and get your identity document approved first.",
            "error_code" => "VERIFICATION_REQUIRED",
        ]);
        exit;
    }

    $status = 'pending';
    $created_at = date('Y-m-d H:i:s');

    // ===============================
    // 🔍 CHECK ONLY SAME TYPE
    // ===============================
    $checkStmt = $pdo->prepare("
        SELECT id 
        FROM proposals 
        WHERE sender_id = :sender_id 
        AND receiver_id = :receiver_id 
        AND request_type = :request_type
        LIMIT 1
    ");

    $checkStmt->execute([
        ':sender_id' => $sender_id,
        ':receiver_id' => $receiver_id,
        ':request_type' => $request_type
    ]);

    // ===============================
    // 🔄 IF SAME TYPE → UPDATE
    // ===============================
    if ($checkStmt->rowCount() > 0) {
        $row = $checkStmt->fetch(PDO::FETCH_ASSOC);

        $updateStmt = $pdo->prepare("
            UPDATE proposals 
            SET status = :status, created_at = :created_at 
            WHERE id = :id
        ");

        $updateStmt->execute([
            ':status' => $status,
            ':created_at' => $created_at,
            ':id' => $row['id']
        ]);

        echo json_encode([
            "success" => true,
            "message" => "",
            "proposal_id" => $row['id']
        ]);

    } else {
        // ===============================
        // ➕ DIFFERENT TYPE → INSERT NEW
        // ===============================
        $insertStmt = $pdo->prepare("
            INSERT INTO proposals 
            (sender_id, receiver_id, request_type, status, created_at) 
            VALUES 
            (:sender_id, :receiver_id, :request_type, :status, :created_at)
        ");

        $insertStmt->execute([
            ':sender_id' => $sender_id,
            ':receiver_id' => $receiver_id,
            ':request_type' => $request_type,
            ':status' => $status,
            ':created_at' => $created_at
        ]);

        echo json_encode([
            "success" => true,
            "message" => "",
            "proposal_id" => $pdo->lastInsertId()
        ]);
    }

} catch (PDOException $e) {
    echo json_encode([
        "success" => false,
        "message" => "Database error: " . $e->getMessage()
    ]);
}
?>