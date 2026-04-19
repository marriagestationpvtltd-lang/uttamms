<?php
/**
 * log_activity.php
 *
 * Record a user action from the mobile app.  Called fire-and-forget style
 * (the app does not need to wait for the response).
 *
 * POST body (JSON or form-encoded):
 *   user_id       (int)    – required
 *   activity_type (string) – required  (see ENUM in user_activities table)
 *   description   (string) – optional  human-readable detail
 *   target_user_id(int)    – optional  other user involved in the action
 *   device_info   (string) – optional  device / OS string sent by the client
 */

ini_set('display_errors', 0);
ini_set('log_errors', 1);
error_reporting(E_ALL);

header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

require_once __DIR__ . '/db_config.php';

// --------------------------------------------------------------------------
// Input
// --------------------------------------------------------------------------

$input = json_decode(file_get_contents('php://input'), true);
if (empty($input)) {
    $input = $_POST;
}

$user_id       = isset($input['user_id'])       ? (int)   $input['user_id']       : 0;
$activity_type = isset($input['activity_type']) ? trim($input['activity_type'])   : '';
$description   = isset($input['description'])   ? trim($input['description'])     : null;
$target_user_id= isset($input['target_user_id'])? (int)   $input['target_user_id']: null;
$device_info   = isset($input['device_info'])   ? substr(trim($input['device_info']), 0, 255) : null;
$ip_address    = $_SERVER['REMOTE_ADDR'] ?? null;

if ($user_id <= 0 || $activity_type === '') {
    echo json_encode(['success' => false, 'message' => 'user_id and activity_type are required']);
    exit;
}

// Accepted activity types (mirrors the ENUM in the DB)
$valid_types = [
    'login', 'logout', 'profile_view', 'search',
    'proposal_sent', 'proposal_accepted', 'proposal_rejected',
    'call_initiated', 'call_received', 'call_ended',
    'custom_tone_set', 'custom_tone_removed', 'settings_changed', 'other',
];

if (!in_array($activity_type, $valid_types, true)) {
    $activity_type = 'other';
}

$target_user_id = ($target_user_id > 0) ? $target_user_id : null;

// --------------------------------------------------------------------------
// Insert
// --------------------------------------------------------------------------

try {
    $stmt = $pdo->prepare("
        INSERT INTO user_activities
            (user_id, activity_type, description, target_user_id, ip_address, device_info)
        VALUES
            (?, ?, ?, ?, ?, ?)
    ");
    $stmt->execute([
        $user_id,
        $activity_type,
        $description,
        $target_user_id,
        $ip_address,
        $device_info,
    ]);

    echo json_encode(['success' => true]);

} catch (PDOException $e) {
    error_log('log_activity error: ' . $e->getMessage());
    echo json_encode(['success' => false, 'message' => 'Server error. Please try again.']);
}
