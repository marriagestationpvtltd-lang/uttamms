<?php
header('Content-Type: application/json; charset=utf-8');

try {
    // === CONFIG ===
    $dbHost = "127.0.0.1";
    $dbName = "ms";
    $dbUser = "ms";
    $dbPass = "ms";

    $pdo = new PDO("mysql:host=$dbHost;dbname=$dbName;charset=utf8mb4", $dbUser, $dbPass, [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION
    ]);

    // INPUT CHECK
    if (!isset($_GET['user_id']) || !is_numeric($_GET['user_id'])) {
        echo json_encode(["success" => false, "message" => "user_id is required and must be numeric"]);
        exit;
    }
    $userId = (int) $_GET['user_id'];

    // GET REQUESTING USER
    $stmt = $pdo->prepare("SELECT id, gender FROM users WHERE id = ?");
    $stmt->execute([$userId]);
    $me = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$me) {
        echo json_encode(["success" => false, "message" => "User not found"]);
        exit;
    }

    // Normalize gender
    $rawGender = $me['gender'];
    $norm = strtolower(trim($rawGender));
    $opposite = ($norm === 'male') ? 'female' : 'male';

    // FETCH OPPOSITE GENDER + PAID + INCLUDE isVerified + AGE + CITY + PRIVACY
    $sql = "
        SELECT
            u.id,
            u.firstName,
            u.lastName,
            u.email,
            u.gender,
            u.usertype,
            u.isVerified,
            u.profile_picture,
            u.privacy,
            ud.birthDate,
            TIMESTAMPDIFF(YEAR, ud.birthDate, CURDATE()) AS age,
            pa.city
        FROM users u
        LEFT JOIN userpersonaldetail ud ON ud.userId = u.id
        LEFT JOIN permanent_address pa ON pa.userId = u.id
        WHERE TRIM(LOWER(u.gender)) = :opp_gender
          AND TRIM(LOWER(u.usertype)) = 'paid'
          AND u.id != :me
        ORDER BY u.id DESC
    ";

    $stmt2 = $pdo->prepare($sql);
    $stmt2->execute([
        ':opp_gender' => $opposite,
        ':me' => $userId
    ]);

    $rows = $stmt2->fetchAll(PDO::FETCH_ASSOC);

    // Enrich each row with photo_request and can_view_photo
    $enrichedRows = [];
    foreach ($rows as $row) {
        $photo_request = "not sent";
        $can_view_photo = false;

        // Check proposals table for photo request status
        $stmtPhoto = $pdo->prepare("
            SELECT status
            FROM proposals
            WHERE request_type = 'Photo'
            AND (
                (sender_id = :me AND receiver_id = :other)
                OR
                (sender_id = :other AND receiver_id = :me)
            )
            ORDER BY id DESC
            LIMIT 1
        ");
        $stmtPhoto->execute([
            ":me" => $userId,
            ":other" => $row['id']
        ]);

        if ($photoRow = $stmtPhoto->fetch(PDO::FETCH_ASSOC)) {
            $photo_request = ($photoRow['status'] === 'accepted') ? 'accepted' : 'pending';
        }

        // Determine can_view_photo based on privacy and photo_request
        $privacy = strtolower(trim($row['privacy'] ?? ''));
        if ($privacy === 'public') {
            $can_view_photo = true;
        } elseif ($photo_request === 'accepted') {
            $can_view_photo = true;
        }

        $row['photo_request'] = $photo_request;
        $row['can_view_photo'] = $can_view_photo;

        $enrichedRows[] = $row;
    }

    // Add debug info
    error_log("Premium members API - User ID: $userId, Total premium users: " . count($enrichedRows));

    echo json_encode([
        "success" => true,
        "message" => "fetched successfully",
        "data" => $enrichedRows,
        "debug" => [
            "total_users" => count($enrichedRows),
            "user_id" => $userId
        ]
    ]);

} catch (Exception $e) {
    echo json_encode(["success" => false, "message" => "Server error: " . $e->getMessage()]);
}
