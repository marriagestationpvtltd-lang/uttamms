<?php
header('Content-Type: application/json; charset=utf-8');

try {
    // === DATABASE CONFIG ===
    $dbHost = "127.0.0.1";
    $dbName = "ms"; 
    $dbUser = "ms"; 
    $dbPass = "ms"; 

    $pdo = new PDO(
        "mysql:host=$dbHost;dbname=$dbName;charset=utf8mb4",
        $dbUser,
        $dbPass,
        [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION, PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC]
    );

    // === INPUT CHECK ===
    if (!isset($_GET['user_id']) || !is_numeric($_GET['user_id'])) {
        echo json_encode(["success" => false, "message" => "user_id is required and must be numeric"]);
        exit;
    }
    $userId = (int) $_GET['user_id'];

    // Optional filters
    $minAge = isset($_GET['minage']) ? (int)$_GET['minage'] : null;
    $maxAge = isset($_GET['maxage']) ? (int)$_GET['maxage'] : null;
    $minHeight = isset($_GET['minheight']) ? (int)$_GET['minheight'] : null;
    $maxHeight = isset($_GET['maxheight']) ? (int)$_GET['maxheight'] : null;
    $religion = isset($_GET['religion']) ? (int)$_GET['religion'] : null;

    // === GET USER GENDER ===
    $stmt = $pdo->prepare("SELECT gender FROM users WHERE id = ?");
    $stmt->execute([$userId]);
    $user = $stmt->fetch();

    if (!$user) {
        echo json_encode(["success" => false, "message" => "User not found"]);
        exit;
    }

    $gender = strtolower(trim($user['gender']));
    $oppositeGender = ($gender === 'male') ? 'female' : 'male';

    // === FETCH OPPOSITE GENDER USERS ===
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
            pa.city,
            ud.height_name,
            ud.religionId,
            ec.degree AS education,
            ec.annualincome,
            ul.drinks,
            ul.smoke
        FROM users u
        LEFT JOIN userpersonaldetail ud ON ud.userId = u.id
        LEFT JOIN permanent_address pa ON pa.userId = u.id
        LEFT JOIN educationcareer ec ON ec.userId = u.id
        LEFT JOIN user_lifestyle ul ON ul.userId = u.id
        WHERE TRIM(LOWER(u.gender)) = :opp_gender
          AND TRIM(LOWER(u.usertype)) = 'paid'
          AND u.id != :me
    ";

    $params = [
        ':opp_gender' => $oppositeGender,
        ':me' => $userId
    ];

    // === APPLY FILTERS ===
    if ($minAge !== null) {
        $sql .= " AND TIMESTAMPDIFF(YEAR, ud.birthDate, CURDATE()) >= :minAge";
        $params[':minAge'] = $minAge;
    }
    if ($maxAge !== null) {
        $sql .= " AND TIMESTAMPDIFF(YEAR, ud.birthDate, CURDATE()) <= :maxAge";
        $params[':maxAge'] = $maxAge;
    }
    if ($minHeight !== null) {
        $sql .= " AND CAST(SUBSTRING_INDEX(ud.height_name, ' ', 1) AS UNSIGNED) >= :minHeight";
        $params[':minHeight'] = $minHeight;
    }
    if ($maxHeight !== null) {
        $sql .= " AND CAST(SUBSTRING_INDEX(ud.height_name, ' ', 1) AS UNSIGNED) <= :maxHeight";
        $params[':maxHeight'] = $maxHeight;
    }
    if ($religion !== null) {
        $sql .= " AND ud.religionId = :religion";
        $params[':religion'] = $religion;
    }

    $sql .= " ORDER BY u.id DESC";

    $stmt2 = $pdo->prepare($sql);
    $stmt2->execute($params);

    $rows = $stmt2->fetchAll();

    $imageBaseUrl = 'https://digitallami.com/Api2/';

    foreach ($rows as &$row) {
        // Prepend base URL to profile picture
        if (!empty($row['profile_picture']) && !preg_match('/^https?:\/\//', $row['profile_picture'])) {
            $row['profile_picture'] = $imageBaseUrl . $row['profile_picture'];
        }

        // === PHOTO REQUEST LOGIC ===
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
            ":me"=>$userId,
            ":other"=>$row['id']
        ]);
        $photo_request = "not sent";
        $can_view_photo = false;
        if($r = $stmtPhoto->fetch()){
            $photo_request = ($r['status'] === 'accepted') ? 'accepted' : 'pending';
        }
        // Photo access ONLY granted when photo request is accepted
        if($photo_request === 'accepted'){
            $can_view_photo = true;
        }
        $row['photo_request'] = $photo_request;
        $row['can_view_photo'] = $can_view_photo;
    }

    $totalCount = count($rows);

    echo json_encode([
        "success" => true,
        "message" => "Opposite gender users fetched successfully",
        "total_count" => $totalCount,
        "data" => $rows
    ], JSON_PRETTY_PRINT);

} catch (Exception $e) {
    echo json_encode([
        "success" => false,
        "message" => "Server error: " . $e->getMessage()
    ]);
}
?>
