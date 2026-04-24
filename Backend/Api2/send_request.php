<?php
header('Content-Type: application/json; charset=utf-8');

require_once __DIR__ . '/db_config.php';

try {
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
    // 🔒 REQUIRE FULL SENDER VERIFICATION
    // (identity doc + all required marital docs)
    // ===============================
    $maritalDocTypes = ['Death Certificate', 'Marriage Certificate', 'Divorce Decree', 'Court Order', 'Separation Document'];

    // Fetch sender's marital status to determine required documents
    $msStmt = $pdo->prepare("
        SELECT upd.maritalStatusId, ms.name AS marital_status_name
        FROM users u
        LEFT JOIN userpersonaldetail upd ON u.id = upd.userid
        LEFT JOIN maritalstatus ms ON upd.maritalStatusId = ms.id
        WHERE u.id = ?
    ");
    $msStmt->execute([$sender_id]);
    $msRow             = $msStmt->fetch(PDO::FETCH_ASSOC);
    $maritalStatusName = $msRow['marital_status_name'] ?? '';
    $maritalStatusId   = (int)($msRow['maritalStatusId'] ?? 0);
    $nameIsEmpty       = ($maritalStatusName === '');

    // Determine required marital documents
    $requiredMaritalDocs = [];
    if ($maritalStatusName === 'Widowed' || ($nameIsEmpty && $maritalStatusId === 2)) {
        $requiredMaritalDocs = ['Death Certificate'];
    } elseif ($maritalStatusName === 'Divorced' || ($nameIsEmpty && $maritalStatusId === 3)) {
        $requiredMaritalDocs = ['Divorce Decree'];
    } elseif (in_array($maritalStatusName, ['Awaiting Divorce', 'Waiting Divorce'], true)
           || ($nameIsEmpty && $maritalStatusId === 4)) {
        $requiredMaritalDocs = ['Separation Document'];
    }

    // Fetch all approved documents for the sender
    $docsStmt = $pdo->prepare("
        SELECT documenttype FROM user_documents
        WHERE userid = ? AND status = 'approved'
    ");
    $docsStmt->execute([$sender_id]);
    $approvedDocs = $docsStmt->fetchAll(PDO::FETCH_COLUMN);

    // Check: at least one approved identity document (not a marital doc type)
    $hasApprovedIdentity = false;
    foreach ($approvedDocs as $docType) {
        if (!in_array($docType, $maritalDocTypes, true)) {
            $hasApprovedIdentity = true;
            break;
        }
    }

    if (!$hasApprovedIdentity) {
        echo json_encode([
            "success"    => false,
            "message"    => "Identity verification required to send requests. Please upload and get your identity document approved first.",
            "error_code" => "VERIFICATION_REQUIRED",
        ]);
        exit;
    }

    // Check: all required marital documents are approved
    foreach ($requiredMaritalDocs as $requiredDoc) {
        if (!in_array($requiredDoc, $approvedDocs, true)) {
            echo json_encode([
                "success"    => false,
                "message"    => "Full verification required. Please upload and get your $requiredDoc approved.",
                "error_code" => "VERIFICATION_REQUIRED",
            ]);
            exit;
        }
    }

    // ===============================
    // 🔒 REQUIRE SENDER TO HAVE AN ACTIVE (NON-EXPIRED) PAID PACKAGE
    // ===============================
    $paidStmt = $pdo->prepare("
        SELECT up.id
        FROM user_package up
        WHERE up.userid = ?
          AND up.expiredate > NOW()
        LIMIT 1
    ");
    $paidStmt->execute([$sender_id]);

    if ($paidStmt->rowCount() === 0) {
        echo json_encode([
            "success"    => false,
            "message"    => "Package purchase required to send requests. Please purchase a package to continue.",
            "error_code" => "PACKAGE_REQUIRED",
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
    error_log('send_request.php DB error: ' . $e->getMessage());
    echo json_encode([
        "success" => false,
        "message" => "Server error. Please try again."
    ]);
}
?>