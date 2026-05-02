<?php
header("Content-Type: application/json");
require 'common_fcm.php';

// Database connection
$host = "localhost";
$db   = "ms";
$user = "root";
$pass = "";

$conn = new mysqli($host, $user, $pass, $db);
if ($conn->connect_error) {
    echo json_encode(["status"=>false,"message"=>"DB connection failed"]);
    exit;
}

// Get parameters for call notification
$user_id = $_POST['user_id'] ?? '';
$title   = $_POST['title'] ?? 'Incoming Call';
$body    = $_POST['body'] ?? '';
$data_json = $_POST['data'] ?? '{}';
$data = json_decode($data_json, true);

// Validate
if (empty($user_id)) {
    echo json_encode(["status"=>false,"message"=>"user_id required"]);
    exit;
}

// Fetch FCM token from users table
$stmt = $conn->prepare("SELECT fcm_token FROM users WHERE id=?");
$stmt->bind_param("i", $user_id);
$stmt->execute();
$stmt->bind_result($fcm_token);
$stmt->fetch();
$stmt->close();

if (empty($fcm_token)) {
    echo json_encode(["status"=>false,"message"=>"FCM token not found for user"]);
    exit;
}

// Prepare notification data
// Prepare notification data
$notification_data = array_merge($data, [
    "click_action" => "FLUTTER_NOTIFICATION_CLICK",
    "sound" => "default",
]);

// Send FCM with specific configuration for calls
try {
    // Custom FCM payload for calls
    $payload = [
        'to' => $fcm_token,
        'priority' => 'high',
        'content_available' => true,
        'notification' => [
            'title' => $title,
            'body' => $body,
            'sound' => 'default',
            'badge' => '1',
        ],
        'data' => $notification_data, // keep data for foreground
        'android' => [
            'priority' => 'high',
            'notification' => [
                'channel_id' => 'calls_channel_high', // full-screen intent channel
                'sound' => 'ringtone',
                'priority' => 'max',
                'visibility' => 'public',
                'notification_count' => 1,
                'fullScreenIntent' => true,  // ⚡ important for background/killed
            ],
        ],
        'apns' => [
            'payload' => [
                'aps' => [
                    'alert' => [
                        'title' => $title,
                        'body' => $body,
                    ],
                    'sound' => 'ringtone.aiff',
                    'badge' => 1,
                    'content-available' => 1,  // ⚡ important for background/killed
                    'mutable-content' => 1,
                ],
            ],
            'headers' => [
                'apns-priority' => '10',
            ],
        ],
    ];

    // Send using your existing sendFCM function
    $response = sendFCM($fcm_token, $title, $body, $notification_data);

    echo json_encode([
        "status" => true,
        "response" => $response,
        "data_sent" => $notification_data
    ]);

} catch(Exception $e) {
    echo json_encode(["status"=>false,"error"=>$e->getMessage()]);
}


$conn->close();
?>