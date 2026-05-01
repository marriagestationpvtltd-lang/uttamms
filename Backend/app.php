<?php
// CORS headers - echo the request origin for allowed origins so credentials work
$allowedOrigins = [
    'https://digitallami.com',
    'https://adminnew.marriagestation.com.np',
    'https://adminmrz.marriagestation.com.np',
];
$requestOrigin = isset($_SERVER['HTTP_ORIGIN']) ? $_SERVER['HTTP_ORIGIN'] : '';
$isLocalhost   = (bool) preg_match('#^https?://(localhost|127\.0\.0\.1)(:\d+)?$#i', $requestOrigin);
if ($requestOrigin && (in_array($requestOrigin, $allowedOrigins, true) || $isLocalhost)) {
    header("Access-Control-Allow-Origin: {$requestOrigin}");
    header("Access-Control-Allow-Credentials: true");
    header("Vary: Origin");
} else {
    header("Access-Control-Allow-Origin: *");
}
header("Access-Control-Allow-Methods: GET, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type, Authorization");
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit();
}

header('Content-Type: application/json');

// Database configuration
define('DB_HOST', 'localhost');
define('DB_NAME', 'ms');
define('DB_USER', 'ms');
define('DB_PASS', 'ms');

try {
    // Create PDO connection
    $pdo = new PDO(
        "mysql:host=" . DB_HOST . ";dbname=" . DB_NAME . ";charset=utf8mb4",
        DB_USER,
        DB_PASS,
        [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC
        ]
    );
    
    // Get platform from query parameter (optional)
    $platform = isset($_GET['platform']) ? $_GET['platform'] : null;
    
    // Build query
    $query = "SELECT 
                android_version,
                ios_version,
                force_update,
                description,
                app_link,
                updated_at
              FROM app_versions 
              WHERE is_active = 1 
              ORDER BY created_at DESC 
              LIMIT 1";
    
    $stmt = $pdo->query($query);
    $version = $stmt->fetch();
    
    if ($version) {
        // Format response based on platform if specified
        $response = [
            'success' => true,
            'data' => [
                'android_version' => $version['android_version'],
                'ios_version' => $version['ios_version'],
                'force_update' => (bool)$version['force_update'],
                'description' => $version['description'],
                'app_link' => $version['app_link'],
                'last_updated' => $version['updated_at']
            ]
        ];
        
        // If platform is specified, return platform-specific info
        if ($platform === 'android') {
            $response['data']['current_version'] = $version['android_version'];
            $response['data']['store_link'] = $version['app_link'];
        } elseif ($platform === 'ios') {
            $response['data']['current_version'] = $version['ios_version'];
            $response['data']['store_link'] = $version['app_link'];
        }
        
        echo json_encode($response);
    } else {
        echo json_encode([
            'success' => false,
            'message' => 'No version information found'
        ]);
    }
    
} catch (PDOException $e) {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'message' => 'Database error: ' . $e->getMessage()
    ]);
}
?>