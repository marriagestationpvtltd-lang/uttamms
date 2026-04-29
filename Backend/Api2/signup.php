<?php
// signup.php
header('Content-Type: application/json; charset=utf-8');

// ==== CONFIG - update these ====
$dbHost = 'localhost';
$dbUser = 'ms';
$dbPass = 'ms';
$dbName = 'ms';
// ================================

$uploadDir = __DIR__ . '/uploads/profile_pictures/';
if (!is_dir($uploadDir)) mkdir($uploadDir, 0755, true);

function respond($code, $payload) {
    http_response_code($code);
    echo json_encode($payload, JSON_UNESCAPED_UNICODE);
    exit;
}

// Only POST
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    respond(405, ['success' => false, 'message' => 'Only POST allowed']);
}

// Expected fields
$expected = ['profileforId','firstName','lastName','email','password','contactNo','gender','Languages','Nationality','dateofbirth'];
$input = [];
$contentType = $_SERVER['CONTENT_TYPE'] ?? '';
if (stripos($contentType, 'application/json') !== false) {
    $raw = file_get_contents('php://input');
    $json = json_decode($raw, true);
    if (!is_array($json)) respond(400, ['success'=>false, 'message'=>'Invalid JSON']);
    foreach ($expected as $k) $input[$k] = $json[$k] ?? null;
} else {
    foreach ($expected as $k) $input[$k] = isset($_POST[$k]) ? trim($_POST[$k]) : null;
}

// Basic required validation
$requiredNow = ['firstName','email','password','contactNo','dateofbirth'];
foreach ($requiredNow as $k) {
    if (empty($input[$k])) respond(400, ['success'=>false, 'message'=>"$k is required"]);
}
if (!filter_var($input['email'], FILTER_VALIDATE_EMAIL)) {
    respond(400, ['success' => false, 'message' => "Invalid email"]);
}

// DB connection
$mysqli = new mysqli($dbHost, $dbUser, $dbPass, $dbName);
if ($mysqli->connect_errno) {
    error_log('signup.php: DB connection failed: ' . $mysqli->connect_error);
    respond(500, ['success'=>false, 'message'=>'Database connection failed']);
}
$mysqli->set_charset('utf8mb4');
$mysqli->begin_transaction();

try {
    // 1) Check duplicate email
    $stmt = $mysqli->prepare("SELECT id FROM users WHERE email = ? LIMIT 1");
    if (!$stmt) throw new Exception("Prepare failed: ".$mysqli->error);
    $stmt->bind_param('s', $input['email']);
    $stmt->execute();
    $stmt->store_result();
    if ($stmt->num_rows > 0) {
        $stmt->close();
        $mysqli->rollback();
        respond(409, ['success' => false, 'message' => 'Email already registered']);
    }
    $stmt->close();

    // 2) Handle profile picture upload (optional)
    $profilePicturePath = null;
    if (!empty($_FILES['profile_picture']) && $_FILES['profile_picture']['error'] !== UPLOAD_ERR_NO_FILE) {
        $file = $_FILES['profile_picture'];
        if ($file['error'] !== UPLOAD_ERR_OK) throw new Exception('Profile picture upload error: '.$file['error']);
        if ($file['size'] > 5 * 1024 * 1024) throw new Exception('Profile picture too large (max 5MB)');

        $finfo = new finfo(FILEINFO_MIME_TYPE);
        $mime = $finfo->file($file['tmp_name']);
        $allowed = ['image/jpeg'=>'jpg','image/png'=>'png','image/webp'=>'webp','image/gif'=>'gif'];
        if (!array_key_exists($mime, $allowed)) throw new Exception('Unsupported image type: ' . $mime);

        $ext = $allowed[$mime];
        $newName = 'pp_' . time() . '_' . bin2hex(random_bytes(6)) . '.' . $ext;
        $dest = $uploadDir . $newName;
        if (!move_uploaded_file($file['tmp_name'], $dest)) throw new Exception('Failed to move uploaded file');
        $profilePicturePath = 'uploads/profile_pictures/' . $newName;
    }

    // 3) Insert into users (explicit column names: firstName, lastName)
    $hashed = password_hash($input['password'], PASSWORD_DEFAULT);

    // Prepare insert - include profile_picture if uploaded
    $cols = "firstName, lastName, email, password, contactNo, gender, languages, nationality";
    $placeholders = "?, ?, ?, ?, ?, ?, ?, ?";
    $types = "ssssssss";
    $values = [
        $input['firstName'],
        $input['lastName'] ?? null,
        $input['email'],
        $hashed,
        $input['contactNo'] ?? null,
        $input['gender'] ?? null,
        $input['Languages'] ?? null,
        $input['Nationality'] ?? null
    ];

    if ($profilePicturePath !== null) {
        $cols .= ", profile_picture";
        $placeholders .= ", ?";
        $types .= "s";
        $values[] = $profilePicturePath;
    }

    $sql = "INSERT INTO users ($cols) VALUES ($placeholders)";
    $stmt = $mysqli->prepare($sql);
    if (!$stmt) throw new Exception("Prepare failed (users insert): " . $mysqli->error);

    // bind params dynamically
    $bind = [];
    $bind[] = $types;
    for ($i = 0; $i < count($values); $i++) $bind[] = &$values[$i];
    call_user_func_array([$stmt, 'bind_param'], $bind);

    if (!$stmt->execute()) throw new Exception("Execute failed (users insert): " . $stmt->error);
    $userid = $stmt->insert_id;
    $stmt->close();

    // 4) Insert into userpersonaldetail (user_id, birthDate, profileForId)
    $birthDate = $input['dateofbirth'];
    $profileForId = isset($input['profileforId']) && $input['profileforId'] !== '' ? $input['profileforId'] : null;

    // If you may have existing row, consider ON DUPLICATE KEY UPDATE; here we assume fresh insert
    $stmt = $mysqli->prepare("INSERT INTO userpersonaldetail (userid, birthDate, profileForId) VALUES (?, ?, ?)");
    if (!$stmt) throw new Exception("Prepare failed (userpersonaldetail): " . $mysqli->error);
    $stmt->bind_param('iss', $userid, $birthDate, $profileForId);
    if (!$stmt->execute()) throw new Exception("Execute failed (userpersonaldetail): " . $stmt->error);
    $stmt->close();

    // 5) Ensure and insert token into user_tokens
    $createTokensSql = "
        CREATE TABLE IF NOT EXISTS user_tokens (
            id INT AUTO_INCREMENT PRIMARY KEY,
            userid INT NOT NULL,
            token VARCHAR(255) NOT NULL,
            created_at DATETIME NOT NULL, 
            INDEX (userid),
            INDEX (token)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ";
    if (!$mysqli->query($createTokensSql)) throw new Exception("Failed ensuring tokens table: " . $mysqli->error);

    $token = bin2hex(random_bytes(30));
    $createdAt = date('Y-m-d H:i:s');
    $stmt = $mysqli->prepare("INSERT INTO user_tokens (userid, token, created_at) VALUES (?, ?, ?)");
    if (!$stmt) throw new Exception("Prepare failed (token insert): " . $mysqli->error);
    $stmt->bind_param('iss', $userid, $token, $createdAt);
    if (!$stmt->execute()) throw new Exception("Execute failed (token insert): " . $stmt->error);
    $stmt->close();

    $mysqli->commit();

    // 6) Fetch user row + associated userpersonaldetail
    $stmt = $mysqli->prepare("
        SELECT u.id, u.firstName, u.lastName, u.email, u.contactNo, u.gender, u.languages, u.nationality, u.profile_picture,
               up.birthDate, up.profileForId
        FROM users u
        LEFT JOIN userpersonaldetail up ON up.userid = u.id
        WHERE u.id = ? LIMIT 1
    ");
    if (!$stmt) throw new Exception("Prepare failed (fetch): " . $mysqli->error);
    $stmt->bind_param('i', $userid);
    $stmt->execute();
    $res = $stmt->get_result();
    $userRow = $res->fetch_assoc();
    $stmt->close();

    if (isset($userRow['password'])) unset($userRow['password']);

    respond(201, [
        'success' => true,
        'message' => 'Signup successful',
        'data' => $userRow,
        'bearer_token' => $token
    ]);

} catch (Exception $e) {
    $mysqli->rollback();
    // remove uploaded file if error
    if (!empty($profilePicturePath) && file_exists(__DIR__ . '/' . $profilePicturePath)) {
        @unlink(__DIR__ . '/' . $profilePicturePath);
    }
    error_log('signup.php error: ' . $e->getMessage());
    respond(500, ['success' => false, 'message' => 'Signup failed. Please try again.']);
}
