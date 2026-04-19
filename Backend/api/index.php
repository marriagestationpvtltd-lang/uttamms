<?php
// Memorial Chat API - Complete Database Version
error_reporting(E_ALL);
ini_set('display_errors', 1);

// CORS headers
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With");
header("Access-Control-Allow-Credentials: true");
header("Access-Control-Max-Age: 3600");

// Handle preflight OPTIONS request
if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    http_response_code(200);
    exit();
}

header('Content-Type: application/json');
session_start();

// Database configuration
define('DB_HOST', 'localhost');
define('DB_NAME', 'ms');
define('DB_USER', 'ms');
define('DB_PASS', 'ms');

// Database connection
function getDB() {
    static $db = null;
    if ($db === null) {
        try {
            $db = new PDO(
                'mysql:host=' . DB_HOST . ';dbname=' . DB_NAME . ';charset=utf8mb4',
                DB_USER,
                DB_PASS
            );
            $db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
            $db->setAttribute(PDO::ATTR_DEFAULT_FETCH_MODE, PDO::FETCH_ASSOC);
        } catch (PDOException $e) {
            http_response_code(500);
            echo json_encode([
                'success' => false,
                'message' => 'Database connection failed',
                'error' => $e->getMessage()
            ]);
            exit;
        }
    }
    return $db;
}

// Response helper
function jsonResponse($success, $data = null, $message = '', $statusCode = 200) {
    http_response_code($statusCode);
    echo json_encode([
        'success' => $success,
        'message' => $message,
        'data' => $data,
        'timestamp' => time()
    ], JSON_PRETTY_PRINT);
    exit;
}

// Get JSON input
function getJsonInput() {
    $input = json_decode(file_get_contents('php://input'), true);
    return json_last_error() === JSON_ERROR_NONE ? $input : null;
}

// Database functions
function getAllChats() {
    $db = getDB();
    
    $query = "SELECT 
                c.id,
                c.name,
                c.avatar_url,
                c.last_message,
                c.last_message_time as time,
                c.is_pinned,
                c.is_unread,
                c.is_group,
                c.has_file,
                c.membership_status,
                COUNT(DISTINCT ps.id) as shared_profiles_count,
                c.created_at
              FROM ac_chats c
              LEFT JOIN profile_shares ps ON c.id = ps.chat_id
              GROUP BY c.id
              ORDER BY c.is_pinned DESC, c.updated_at DESC";
    
    $stmt = $db->prepare($query);
    $stmt->execute();
    
    $chats = $stmt->fetchAll(PDO::FETCH_ASSOC);
    
    // Format the response
    $formattedChats = [];
    foreach ($chats as $chat) {
        $formattedChats[] = [
            'id' => $chat['id'],
            'name' => $chat['name'],
            'avatar_url' => $chat['avatar_url'] ?? '',
            'last_message' => $chat['last_message'] ?? '',
            'time' => $chat['time'] ?? '',
            'is_pinned' => (bool)$chat['is_pinned'],
            'is_unread' => (bool)$chat['is_unread'],
            'is_group' => (bool)$chat['is_group'],
            'has_file' => (bool)$chat['has_file'],
            'membership_status' => $chat['membership_status'] ?? 'free',
            'shared_profiles_count' => (int)$chat['shared_profiles_count'],
            'created_at' => $chat['created_at']
        ];
    }
    
    return $formattedChats;
}

function getAllProfiles($filters = []) {
    $db = getDB();
    
    $query = "SELECT 
                id,
                name,
                avatar_url,
                match_percentage,
                membership_status,
                status as status,
                created_at
              FROM ac_memorial_profiles
              WHERE 1=1";
    
    $params = [];
    
    // Apply filters
    if (!empty($filters['membership_status']) && $filters['membership_status'] != 'all') {
        $query .= " AND membership_status = :status";
        $params[':status'] = $filters['membership_status'];
    }
    
    if (!empty($filters['search'])) {
        $query .= " AND (name LIKE :search OR id LIKE :search)";
        $params[':search'] = '%' . $filters['search'] . '%';
    }
    
    $query .= " ORDER BY match_percentage DESC";
    
    // Apply pagination
    $page = isset($filters['page']) ? max(1, (int)$filters['page']) : 1;
    $perPage = isset($filters['per_page']) ? max(1, (int)$filters['per_page']) : 20;
    $offset = ($page - 1) * $perPage;
    
    $query .= " LIMIT :limit OFFSET :offset";
    
    $stmt = $db->prepare($query);
    
    // Bind parameters
    foreach ($params as $key => $value) {
        $stmt->bindValue($key, $value);
    }
    $stmt->bindValue(':limit', $perPage, PDO::PARAM_INT);
    $stmt->bindValue(':offset', $offset, PDO::PARAM_INT);
    
    $stmt->execute();
    
    $profiles = $stmt->fetchAll(PDO::FETCH_ASSOC);
    
    // Get total count for pagination
    $countQuery = "SELECT COUNT(*) as total FROM ac_memorial_profiles WHERE 1=1";
    $countParams = [];
    
    if (!empty($filters['membership_status']) && $filters['membership_status'] != 'all') {
        $countQuery .= " AND membership_status = :status";
        $countParams[':status'] = $filters['membership_status'];
    }
    
    if (!empty($filters['search'])) {
        $countQuery .= " AND (name LIKE :search OR id LIKE :search)";
        $countParams[':search'] = '%' . $filters['search'] . '%';
    }
    
    $countStmt = $db->prepare($countQuery);
    $countStmt->execute($countParams);
    $totalResult = $countStmt->fetch();
    $total = $totalResult['total'] ?? 0;
    
    // Format response
    $formattedProfiles = [];
    foreach ($profiles as $profile) {
        $formattedProfiles[] = [
            'id' => $profile['id'],
            'name' => $profile['name'],
            'avatar_url' => $profile['avatar_url'] ?? '',
            'match_percentage' => (int)$profile['match_percentage'],
            'membership_status' => $profile['membership_status'] ?? 'free',
            'status' => $profile['status'] == 'alreadySent' ? 'alreadySent' : 'newProfile',
            'created_at' => $profile['created_at']
        ];
    }
    
    return [
        'profiles' => $formattedProfiles,
        'total' => $total,
        'page' => $page,
        'per_page' => $perPage,
        'total_pages' => ceil($total / $perPage)
    ];
}

function getChatMessages($chatId, $page = 1, $perPage = 50) {
    $db = getDB();
    
    $offset = ($page - 1) * $perPage;
    
    $query = "SELECT 
                m.id,
                m.chat_id,
                m.sender_id,
                m.sender_type,
                m.message_type,
                m.text_content as text,
                m.shared_profile_id,
                m.is_read,
                DATE_FORMAT(m.created_at, '%h:%i %p') as time,
                m.created_at,
                u.username as sender_name,
                u.avatar_url as sender_avatar,
                mp.name as shared_profile_name,
                mp.avatar_url as shared_profile_avatar
              FROM ac_messages m
              LEFT JOIN agent_users u ON m.sender_id = u.id
              LEFT JOIN memorial_profiles mp ON m.shared_profile_id = mp.id
              WHERE m.chat_id = :chat_id
              ORDER BY m.created_at DESC
              LIMIT :limit OFFSET :offset";
    
    $stmt = $db->prepare($query);
    $stmt->bindValue(':chat_id', $chatId);
    $stmt->bindValue(':limit', $perPage, PDO::PARAM_INT);
    $stmt->bindValue(':offset', $offset, PDO::PARAM_INT);
    $stmt->execute();
    
    $messages = $stmt->fetchAll(PDO::FETCH_ASSOC);
    
    // Format messages
    $formattedMessages = [];
    foreach ($messages as $message) {
        $formattedMessage = [
            'id' => $message['id'],
            'chat_id' => $message['chat_id'],
            'text' => $message['text'],
            'time' => $message['time'],
            'is_sent_by_me' => $message['sender_type'] == 'agent',
            'sender_type' => $message['sender_type'],
            'message_type' => $message['message_type'],
            'is_read' => (bool)$message['is_read'],
            'created_at' => $message['created_at']
        ];
        
        if ($message['sender_name']) {
            $formattedMessage['sender'] = [
                'id' => $message['sender_id'],
                'name' => $message['sender_name'],
                'avatar_url' => $message['sender_avatar']
            ];
        }
        
        if ($message['shared_profile_id']) {
            $formattedMessage['shared_profile'] = [
                'id' => $message['shared_profile_id'],
                'name' => $message['shared_profile_name'],
                'avatar_url' => $message['shared_profile_avatar']
            ];
        }
        
        $formattedMessages[] = $formattedMessage;
    }
    
    // Get total count
    $countQuery = "SELECT COUNT(*) as total FROM ac_messages WHERE chat_id = :chat_id";
    $countStmt = $db->prepare($countQuery);
    $countStmt->execute([':chat_id' => $chatId]);
    $totalResult = $countStmt->fetch();
    $total = $totalResult['total'] ?? 0;
    
    return [
        'messages' => $formattedMessages,
        'total' => $total,
        'page' => $page,
        'per_page' => $perPage,
        'total_pages' => ceil($total / $perPage)
    ];
}

function sendMessageToChat($chatId, $text, $senderId = null) {
    $db = getDB();
    
    // Generate message ID
    $messageId = $chatId . '-msg-' . time() . '-' . rand(1000, 9999);
    
    $query = "INSERT INTO ac_messages 
              (id, chat_id, sender_id, sender_type, text_content, message_type) 
              VALUES (:id, :chat_id, :sender_id, :sender_type, :text, 'text')";
    
    $stmt = $db->prepare($query);
    $result = $stmt->execute([
        ':id' => $messageId,
        ':chat_id' => $chatId,
        ':sender_id' => $senderId,
        ':sender_type' => $senderId ? 'agent' : 'contact',
        ':text' => $text
    ]);
    
    if ($result) {
        // Update chat's last message
        $updateQuery = "UPDATE ac_chats 
                       SET last_message = :last_message, 
                           last_message_time = :time,
                           updated_at = NOW()
                       WHERE id = :chat_id";
        
        $time = date('h:i A');
        $updateStmt = $db->prepare($updateQuery);
        $updateStmt->execute([
            ':last_message' => $text,
            ':time' => $time,
            ':chat_id' => $chatId
        ]);
        
        return [
            'id' => $messageId,
            'chat_id' => $chatId,
            'text' => $text,
            'time' => $time,
            'is_sent_by_me' => (bool)$senderId,
            'message_type' => 'text',
            'created_at' => date('Y-m-d H:i:s')
        ];
    }
    
    return false;
}

function shareProfile($chatId, $profileId, $senderId = null) {
    $db = getDB();
    
    // Check if already shared
    $checkQuery = "SELECT id FROM ac_profile_shares 
                   WHERE chat_id = :chat_id AND profile_id = :profile_id 
                   LIMIT 1";
    $checkStmt = $db->prepare($checkQuery);
    $checkStmt->execute([
        ':chat_id' => $chatId,
        ':profile_id' => $profileId
    ]);
    
    if ($checkStmt->fetch()) {
        return false; // Already shared
    }
    
    // Insert share record
    $shareQuery = "INSERT INTO ac_profile_shares (chat_id, profile_id, shared_by) 
                   VALUES (:chat_id, :profile_id, :shared_by)";
    $shareStmt = $db->prepare($shareQuery);
    $shareResult = $shareStmt->execute([
        ':chat_id' => $chatId,
        ':profile_id' => $profileId,
        ':shared_by' => $senderId
    ]);
    
    if ($shareResult) {
        // Create a message about the share
        $profile = getProfileById($profileId);
        $messageText = "Shared profile: " . ($profile['name'] ?? 'Unknown Profile');
        
        $messageId = $chatId . '-share-' . time() . '-' . rand(1000, 9999);
        
        $messageQuery = "INSERT INTO ac_messages 
                        (id, chat_id, sender_id, sender_type, text_content, message_type, shared_profile_id) 
                        VALUES (:id, :chat_id, :sender_id, :sender_type, :text, 'profile', :profile_id)";
        
        $messageStmt = $db->prepare($messageQuery);
        $messageStmt->execute([
            ':id' => $messageId,
            ':chat_id' => $chatId,
            ':sender_id' => $senderId,
            ':sender_type' => $senderId ? 'agent' : 'contact',
            ':text' => $messageText,
            ':profile_id' => $profileId
        ]);
        
        // Update chat's last message
        $updateQuery = "UPDATE ac_chats 
                       SET last_message = :last_message, 
                           last_message_time = :time,
                           updated_at = NOW()
                       WHERE id = :chat_id";
        
        $time = date('h:i A');
        $updateStmt = $db->prepare($updateQuery);
        $updateStmt->execute([
            ':last_message' => $messageText,
            ':time' => $time,
            ':chat_id' => $chatId
        ]);
        
        // Update profile status
        $profileQuery = "UPDATE ac_memorial_profiles 
                        SET profile_status = 'alreadySent'
                        WHERE id = :profile_id";
        $profileStmt = $db->prepare($profileQuery);
        $profileStmt->execute([':profile_id' => $profileId]);
        
        return true;
    }
    
    return false;
}

function getProfileById($profileId) {
    $db = getDB();
    
    $query = "SELECT id, name, avatar_url, match_percentage, membership_status 
              FROM ac_memorial_profiles 
              WHERE id = :id LIMIT 1";
    
    $stmt = $db->prepare($query);
    $stmt->execute([':id' => $profileId]);
    
    return $stmt->fetch();
}

function loginUser($email, $password) {
    $db = getDB();
    
    $query = "SELECT id, username, email, avatar_url, role 
              FROM agent_users 
              WHERE email = :email LIMIT 1";
    
    $stmt = $db->prepare($query);
    $stmt->execute([':email' => $email]);
    $user = $stmt->fetch();
    
    if (!$user) {
        return false;
    }
    
    // In a real app, verify password_hash here
    // For now, we'll return the user without password verification
    return $user;
}

// Get request path
$requestUri = $_SERVER['REQUEST_URI'];
$scriptName = $_SERVER['SCRIPT_NAME'];

// Extract clean path
$path = str_replace(dirname($scriptName), '', $requestUri);
$path = trim($path, '/');
$path = explode('?', $path)[0];

// Remove index.php prefix
if (strpos($path, 'index.php/') === 0) {
    $path = substr($path, 10);
}

$method = $_SERVER['REQUEST_METHOD'];
$queryParams = $_GET;

// Simple router
switch (true) {
    // API Info
    case ($path === '' || $path === 'index.php'):
        $db = getDB();
        $stats = [];
        
        try {
            // Get database stats
            $tables = ['agent_users', 'ac_chats', 'ac_memorial_profiles', 'ac_messages', 'ac_profile_shares'];
            foreach ($tables as $table) {
                $stmt = $db->query("SELECT COUNT(*) as count FROM $table");
                $result = $stmt->fetch();
                $stats[$table] = $result['count'] ?? 0;
            }
        } catch (Exception $e) {
            $stats['error'] = $e->getMessage();
        }
        
        jsonResponse(true, [
            'api' => 'Memorial Chat API',
            'version' => '2.0.0',
            'status' => 'online',
            'database' => 'Connected',
            'database_stats' => $stats,
            'endpoints' => [
                'GET /' => 'API Information',
                'GET /chats' => 'Get all chats',
                'GET /chats/{id}/messages' => 'Get chat messages',
                'POST /chats/{id}/messages' => 'Send message to chat',
                'POST /chats/{id}/share-profile' => 'Share profile in chat',
                'GET /profiles' => 'Get all profiles',
                'POST /login' => 'User login',
                'POST /register' => 'User registration'
            ]
        ], 'API is running');
        break;
    
    // Get all chats
    case ($path === 'chats' && $method === 'GET'):
        $chats = getAllChats();
        jsonResponse(true, ['chats' => $chats], 'Chats retrieved successfully');
        break;
    
    // Get chat messages
    case (preg_match('#^chats/([^/]+)/messages$#', $path, $matches) && $method === 'GET'):
        $chatId = $matches[1];
        $page = $queryParams['page'] ?? 1;
        $perPage = $queryParams['per_page'] ?? 50;
        
        $result = getChatMessages($chatId, $page, $perPage);
        jsonResponse(true, $result, 'Messages retrieved');
        break;
    
    // Send message to chat
    case (preg_match('#^chats/([^/]+)/messages$#', $path, $matches) && $method === 'POST'):
        $chatId = $matches[1];
        $input = getJsonInput();
        
        if (!$input || !isset($input['text']) || empty(trim($input['text']))) {
            jsonResponse(false, null, 'Message text is required', 400);
        }
        
        $senderId = $input['sender_id'] ?? null;
        $message = sendMessageToChat($chatId, trim($input['text']), $senderId);
        
        if ($message) {
            jsonResponse(true, ['message' => $message], 'Message sent successfully', 201);
        } else {
            jsonResponse(false, null, 'Failed to send message', 500);
        }
        break;
    
    // Share profile in chat
    case (preg_match('#^chats/([^/]+)/share-profile$#', $path, $matches) && $method === 'POST'):
        $chatId = $matches[1];
        $input = getJsonInput();
        
        if (!$input || !isset($input['profile_id']) || empty($input['profile_id'])) {
            jsonResponse(false, null, 'Profile ID is required', 400);
        }
        
        $senderId = $input['sender_id'] ?? null;
        $success = shareProfile($chatId, $input['profile_id'], $senderId);
        
        if ($success) {
            jsonResponse(true, null, 'Profile shared successfully', 201);
        } else {
            jsonResponse(false, null, 'Failed to share profile', 500);
        }
        break;
    
    // Get all profiles
    case ($path === 'profiles' && $method === 'GET'):
        $filters = [
            'membership_status' => $queryParams['filter'] ?? 'all',
            'search' => $queryParams['search'] ?? '',
            'page' => $queryParams['page'] ?? 1,
            'per_page' => $queryParams['per_page'] ?? 20
        ];
        
        $result = getAllProfiles($filters);
        jsonResponse(true, $result, 'Profiles retrieved successfully');
        break;
    
    // User login
    case ($path === 'login' && $method === 'POST'):
        $input = getJsonInput();
        
        if (!$input || !isset($input['email']) || !isset($input['password'])) {
            jsonResponse(false, null, 'Email and password are required', 400);
        }
        
        $user = loginUser($input['email'], $input['password']);
        
        if ($user) {
            // In a real app, generate JWT token here
            jsonResponse(true, [
                'user' => $user,
                'message' => 'Login successful'
            ], 'Login successful');
        } else {
            jsonResponse(false, null, 'Invalid credentials', 401);
        }
        break;
    
    // User registration
    case ($path === 'register' && $method === 'POST'):
        $input = getJsonInput();
        
        if (!$input || !isset($input['email']) || !isset($input['password']) || !isset($input['username'])) {
            jsonResponse(false, null, 'Email, password and username are required', 400);
        }
        
        $db = getDB();
        
        // Check if user exists
        $checkQuery = "SELECT id FROM agent_users WHERE email = :email OR username = :username";
        $checkStmt = $db->prepare($checkQuery);
        $checkStmt->execute([
            ':email' => $input['email'],
            ':username' => $input['username']
        ]);
        
        if ($checkStmt->fetch()) {
            jsonResponse(false, null, 'User already exists', 409);
        }
        
        // Create user (without password hash for simplicity)
        $insertQuery = "INSERT INTO agent_users (username, email, password_hash, role) 
                       VALUES (:username, :email, :password_hash, 'agent')";
        
        $passwordHash = password_hash($input['password'], PASSWORD_DEFAULT);
        
        $insertStmt = $db->prepare($insertQuery);
        $success = $insertStmt->execute([
            ':username' => $input['username'],
            ':email' => $input['email'],
            ':password_hash' => $passwordHash
        ]);
        
        if ($success) {
            $userId = $db->lastInsertId();
            
            // Get the created user
            $userQuery = "SELECT id, username, email, avatar_url, role 
                         FROM agent_users WHERE id = :id";
            $userStmt = $db->prepare($userQuery);
            $userStmt->execute([':id' => $userId]);
            $user = $userStmt->fetch();
            
            jsonResponse(true, [
                'user' => $user,
                'message' => 'Registration successful'
            ], 'Registration successful', 201);
        } else {
            jsonResponse(false, null, 'Registration failed', 500);
        }
        break;
    
    // Get database stats (for debugging)
    case ($path === 'stats' && $method === 'GET'):
        $db = getDB();
        $stats = [];
        
        try {
            $tables = ['agent_users', 'ac_chats', 'ac_memorial_profiles', 'ac_messages', 'ac_profile_shares'];
            foreach ($tables as $table) {
                $stmt = $db->query("SELECT COUNT(*) as count FROM $table");
                $result = $stmt->fetch();
                $stats[$table] = $result['count'] ?? 0;
                
                // Get sample data for each table
                $sampleStmt = $db->query("SELECT * FROM $table ORDER BY id DESC LIMIT 3");
                $stats[$table . '_sample'] = $sampleStmt->fetchAll(PDO::FETCH_ASSOC);
            }
            
            jsonResponse(true, $stats, 'Database statistics');
        } catch (Exception $e) {
            jsonResponse(false, null, 'Error getting stats: ' . $e->getMessage(), 500);
        }
        break;
    
    // Create test data (for development)
    case ($path === 'create-test-data' && $method === 'POST'):
        // This endpoint creates test data if tables are empty
        $db = getDB();
        
        try {
            // Check if we have data
            $chatsStmt = $db->query("SELECT COUNT(*) as count FROM ac_chats");
            $chatsCount = $chatsStmt->fetch()['count'];
            
            if ($chatsCount == 0) {
                // Insert test chats
                $testChats = [
                    ['ms001', 'Phone Contact 1', 'contact_001', 'https://via.placeholder.com/150/FF6347/FFFFFF?text=P1', '✓ Hello sir, this is my site...', 'Tuesday', 1, 1, 'paid', 1],
                    ['ms002', 'Sumit', 'contact_002', 'https://via.placeholder.com/150/4682B4/FFFFFF?text=S', '✓ myprofile.txt', '10:28 AM', 0, 0, 'free', 1],
                    ['ms003', 'Kapada Station', 'contact_003', 'https://via.placeholder.com/150/3CB371/FFFFFF?text=KS', 'Looking for memorial services', 'Yesterday', 0, 0, 'expired', 1]
                ];
                
                foreach ($testChats as $chat) {
                    $stmt = $db->prepare("INSERT INTO ac_chats (id, name, contact_id, avatar_url, last_message, last_message_time, is_pinned, is_unread, membership_status, assigned_to) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)");
                    $stmt->execute($chat);
                }
                
                jsonResponse(true, null, 'Test chats created', 201);
            } else {
                jsonResponse(true, ['chats_count' => $chatsCount], 'Data already exists');
            }
        } catch (Exception $e) {
            jsonResponse(false, null, 'Error creating test data: ' . $e->getMessage(), 500);
        }
        break;
    
    // Default - Not Found
    default:
        jsonResponse(false, null, "Endpoint not found: $path", 404);
        break;
}
?>