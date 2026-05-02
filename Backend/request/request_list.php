<?php

header("Content-Type: application/json");
header("Access-Control-Allow-Origin: *");

// DB Config
$host = "localhost";
$db_name = "ms";
$username = "root";
$password = "";

try {
    $conn = new PDO(
        "mysql:host=$host;dbname=$db_name;charset=utf8",
        $username,
        $password
    );
    $conn->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);

    // ✅ Validate input
    if (!isset($_GET['receiver_id']) || empty($_GET['receiver_id'])) {
        echo json_encode([
            "status" => false,
            "message" => "receiver_id is required"
        ]);
        exit;
    }

    $receiver_id = intval($_GET['receiver_id']);

    // ===============================
    // 📸 1. PHOTO REQUEST NOTIFICATIONS
    // ===============================
    $photoQuery = "
        SELECT 
            p.id,
            p.sender_id,
            u.lastName,
            'photo_request' AS type,
            p.created_at AS created_at
        FROM proposals p
        LEFT JOIN users u ON p.sender_id = u.id
        WHERE p.receiver_id = :receiver_id
        AND p.request_type = 'Photo'
        AND p.status = 'pending'
    ";

    // ===============================
    // 👀 2. PROFILE VIEW NOTIFICATIONS (FIXED)
    // ===============================
    $viewQuery = "
        SELECT 
            MAX(pv.id) AS id,                         -- latest view only
            pv.userid AS sender_id,                  -- 👈 viewer
            u.lastName,
            'profile_view' AS type,
            MAX(pv.view_date) AS created_at
        FROM profile_view pv
        LEFT JOIN users u ON pv.userid = u.id
        WHERE pv.viewuserid = :receiver_id          -- 👈 current user
        AND (pv.expire_date IS NULL OR pv.expire_date >= NOW())
        GROUP BY pv.userid                         -- 👈 avoid duplicate spam
    ";

    // ===============================
    // 🔥 MERGE BOTH
    // ===============================
    $query = "
        ($photoQuery)
        UNION ALL
        ($viewQuery)
        ORDER BY created_at DESC
    ";

    $stmt = $conn->prepare($query);
    $stmt->bindParam(':receiver_id', $receiver_id, PDO::PARAM_INT);
    $stmt->execute();

    $results = $stmt->fetchAll(PDO::FETCH_ASSOC);

    // ===============================
    // ✅ FINAL RESPONSE
    // ===============================
    echo json_encode([
        "status" => true,
        "count" => count($results),
        "data" => $results
    ]);

} catch (PDOException $e) {
    echo json_encode([
        "status" => false,
        "message" => $e->getMessage()
    ]);
}