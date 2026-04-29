<?php
// google_auth_mobile.php - Simplified for mobile app
header('Content-Type: application/json; charset=utf-8');

// ==== CONFIG ====
$dbHost = 'localhost';
$dbUser = 'ms';
$dbPass = 'ms';
$dbName = 'ms';
// ================

function respond($code, $payload) {
    http_response_code($code);
    echo json_encode($payload, JSON_UNESCAPED_UNICODE);
    exit;
}

// Only POST
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    respond(405, ['success' => false, 'message' => 'Only POST allowed']);
}

// Get input
$contentType = $_SERVER['CONTENT_TYPE'] ?? '';
$input = [];

if (stripos($contentType, 'application/json') !== false) {
    $raw = file_get_contents('php://input');
    $json = json_decode($raw, true);
    if (!is_array($json)) respond(400, ['success'=>false, 'message'=>'Invalid JSON']);
    
    // Mobile app sends these fields
    $input['email'] = $json['email'] ?? null;
    $input['google_id'] = $json['google_id'] ?? null;
    $input['name'] = $json['name'] ?? '';
    $input['photo_url'] = $json['photo_url'] ?? null;
    $input['access_token'] = $json['access_token'] ?? null;
} else {
    respond(400, ['success' => false, 'message' => 'JSON content required']);
}

// Validate email
if (empty($input['email'])) {
    respond(400, ['success' => false, 'message' => 'Email is required']);
}

// DB connection
$mysqli = new mysqli($dbHost, $dbUser, $dbPass, $dbName);
if ($mysqli->connect_errno) {
    error_log('google_auth.php: DB connection failed: ' . $mysqli->connect_error);
    respond(500, ['success'=>false, 'message'=>'Database connection failed']);
}
$mysqli->set_charset('utf8mb4');

try {
    // 1) Check if user exists by email
    $stmt = $mysqli->prepare("
        SELECT u.id, u.firstName, u.lastName, u.email, u.profile_picture,
               up.birthDate, up.profileForId,
               CASE WHEN u.google_id IS NOT NULL THEN 1 ELSE 0 END as is_google_user
        FROM users u
        LEFT JOIN userpersonaldetail up ON up.userid = u.id
        WHERE u.email = ? LIMIT 1
    ");
    
    if (!$stmt) throw new Exception("Prepare failed: ".$mysqli->error);
    
    $stmt->bind_param('s', $input['email']);
    $stmt->execute();
    $result = $stmt->get_result();
    
    if ($result->num_rows > 0) {
        // User exists - LOGIN
        $user = $result->fetch_assoc();
        $stmt->close();
        
        // Update google_id if not set
        if (empty($user['is_google_user']) && !empty($input['google_id'])) {
            $updateStmt = $mysqli->prepare("UPDATE users SET google_id = ? WHERE email = ?");
            if ($updateStmt) {
                $updateStmt->bind_param('ss', $input['google_id'], $input['email']);
                $updateStmt->execute();
                $updateStmt->close();
            }
        }
        
        // Update profile picture if from Google
        if (!empty($input['photo_url']) && empty($user['profile_picture'])) {
            $updatePic = $mysqli->prepare("UPDATE users SET profile_picture = ? WHERE email = ?");
            if ($updatePic) {
                $updatePic->bind_param('ss', $input['photo_url'], $input['email']);
                $updatePic->execute();
                $updatePic->close();
            }
        }
        
    } else {
        // User doesn't exist - SIGNUP
        $stmt->close();
        
        // Parse name
        $nameParts = explode(' ', $input['name'], 2);
        $firstName = $nameParts[0] ?? 'User';
        $lastName = $nameParts[1] ?? '';
        
        // Generate random password for Google users
        $randomPassword = bin2hex(random_bytes(16));
        $hashedPassword = password_hash($randomPassword, PASSWORD_DEFAULT);
        
        // Insert new user
        $stmt = $mysqli->prepare("
            INSERT INTO users (firstName, lastName, email, password, google_id, profile_picture) 
            VALUES (?, ?, ?, ?, ?, ?)
        ");
        
        if (!$stmt) throw new Exception("Prepare failed (user insert): " . $mysqli->error);
        
        $stmt->bind_param('ssssss', 
            $firstName, 
            $lastName, 
            $input['email'], 
            $hashedPassword,
            $input['google_id'] ?? null,
            $input['photo_url'] ?? null
        );
        
        if (!$stmt->execute()) {
            throw new Exception("Execute failed (user insert): " . $stmt->error);
        }
        
        $userId = $stmt->insert_id;
        $stmt->close();
        
        // Insert into userpersonaldetail
        $stmt = $mysqli->prepare("INSERT INTO userpersonaldetail (userid) VALUES (?)");
        if ($stmt) {
            $stmt->bind_param('i', $userId);
            $stmt->execute();
            $stmt->close();
        }
        
        // Fetch newly created user
        $stmt = $mysqli->prepare("
            SELECT u.id, u.firstName, u.lastName, u.email, u.profile_picture,
                   up.birthDate, up.profileForId,
                   1 as is_google_user
            FROM users u
            LEFT JOIN userpersonaldetail up ON up.userid = u.id
            WHERE u.id = ? LIMIT 1
        ");
        
        if (!$stmt) throw new Exception("Prepare failed (fetch user): " . $mysqli->error);
        
        $stmt->bind_param('i', $userId);
        $stmt->execute();
        $result = $stmt->get_result();
        $user = $result->fetch_assoc();
        $stmt->close();
    }
    
    // 2) Generate or get existing token
    $token = bin2hex(random_bytes(30));
    $createdAt = date('Y-m-d H:i:s');
    $expiresAt = date('Y-m-d H:i:s', strtotime('+30 days'));
    
    // Ensure tokens table exists
    $createTokensSql = "
        CREATE TABLE IF NOT EXISTS user_tokens (
            id INT AUTO_INCREMENT PRIMARY KEY,
            userid INT NOT NULL,
            token VARCHAR(255) NOT NULL,
            created_at DATETIME NOT NULL,
            expires_at DATETIME NULL,
            platform VARCHAR(50) DEFAULT 'mobile',
            INDEX (userid),
            INDEX (token)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ";
    
    if (!$mysqli->query($createTokensSql)) {
        throw new Exception("Failed ensuring tokens table: " . $mysqli->error);
    }
    
    // Clean old tokens for this user
    $deleteOld = $mysqli->prepare("
        DELETE FROM user_tokens 
        WHERE userid = ? AND created_at < DATE_SUB(NOW(), INTERVAL 30 DAY)
    ");
    if ($deleteOld) {
        $deleteOld->bind_param('i', $user['id']);
        $deleteOld->execute();
        $deleteOld->close();
    }
    
    // Insert new token
    $stmt = $mysqli->prepare("
        INSERT INTO user_tokens (userid, token, created_at, expires_at, platform) 
        VALUES (?, ?, ?, ?, 'mobile')
    ");
    
    if (!$stmt) {
        $stmt = $mysqli->prepare("
            INSERT INTO user_tokens (userid, token, created_at, platform) 
            VALUES (?, ?, ?, 'mobile')
        ");
        if (!$stmt) throw new Exception("Prepare failed (token insert): " . $mysqli->error);
        $stmt->bind_param('iss', $user['id'], $token, $createdAt);
        $expiresAt = null;
    } else {
        $stmt->bind_param('isss', $user['id'], $token, $createdAt, $expiresAt);
    }
    
    if (!$stmt->execute()) {
        throw new Exception("Execute failed (token insert): " . $stmt->error);
    }
    $stmt->close();
    
    // 3) Update last login
    $checkLastLogin = $mysqli->query("SHOW COLUMNS FROM users LIKE 'last_login'");
    if ($checkLastLogin->num_rows === 0) {
        $mysqli->query("ALTER TABLE users ADD COLUMN last_login DATETIME NULL");
    }
    
    $updateLogin = $mysqli->prepare("UPDATE users SET last_login = NOW() WHERE id = ?");
    if ($updateLogin) {
        $updateLogin->bind_param('i', $user['id']);
        $updateLogin->execute();
        $updateLogin->close();
    }
    
    // 4) Prepare response
    $response = [
        'success' => true,
        'message' => isset($user['is_google_user']) ? 'Google login successful' : 'Account created successfully',
        'data' => $user,
        'bearer_token' => $token,
    ];
    
    if ($expiresAt) {
        $response['token_expires'] = $expiresAt;
    }
    
    respond(200, $response);
    
} catch (Exception $e) {
    respond(500, ['success' => false, 'message' => 'Authentication failed: ' . $e->getMessage()]);
}
?>