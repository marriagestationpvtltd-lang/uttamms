<?php
/**
 * get_call_ringtone.php
 *
 * Return the ringtone that should play when caller_id calls receiver_id.
 *
 * The priority order is:
 *   1. Receiver's custom tone (if receiver has uploaded one and is_custom = 1)
 *   2. Receiver's chosen system ringtone (if receiver has selected one)
 *   3. System-wide default ringtone
 *   4. Built-in fallback (empty string – app plays its own default)
 *
 * GET params:
 *   caller_id   (int) – required
 *   receiver_id (int) – required
 */

ini_set('display_errors', 0);
ini_set('log_errors', 1);
error_reporting(E_ALL);

header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

require_once __DIR__ . '/db_config.php';

// --------------------------------------------------------------------------
// Input
// --------------------------------------------------------------------------

$caller_id   = isset($_GET['caller_id'])   ? (int) $_GET['caller_id']   : 0;
$receiver_id = isset($_GET['receiver_id']) ? (int) $_GET['receiver_id'] : 0;

if ($caller_id <= 0 || $receiver_id <= 0) {
    echo json_encode(['success' => false, 'message' => 'caller_id and receiver_id are required']);
    exit;
}

// --------------------------------------------------------------------------
// Resolve ringtone
// --------------------------------------------------------------------------

try {
    // 1 & 2 – check receiver's settings
    $settingsStmt = $pdo->prepare("
        SELECT ucs.is_custom, ucs.custom_tone_url, ucs.custom_tone_name,
               rt.id AS ringtone_id, rt.name AS ringtone_name, rt.file_url AS ringtone_url
        FROM   user_call_settings ucs
        LEFT JOIN ringtones rt ON rt.id = ucs.ringtone_id AND rt.is_active = 1
        WHERE  ucs.user_id = ?
        LIMIT 1
    ");
    $settingsStmt->execute([$receiver_id]);
    $settings = $settingsStmt->fetch();

    if ($settings) {
        if ($settings['is_custom'] && !empty($settings['custom_tone_url'])) {
            // Priority 1 – custom tone
            echo json_encode([
                'success'       => true,
                'type'          => 'custom',
                'ringtone_id'   => null,
                'ringtone_name' => $settings['custom_tone_name'] ?? 'Custom',
                'ringtone_url'  => $settings['custom_tone_url'],
            ]);
            exit;
        }

        if (!empty($settings['ringtone_url'])) {
            // Priority 2 – chosen system ringtone
            echo json_encode([
                'success'       => true,
                'type'          => 'system',
                'ringtone_id'   => (string) $settings['ringtone_id'],
                'ringtone_name' => $settings['ringtone_name'],
                'ringtone_url'  => $settings['ringtone_url'],
            ]);
            exit;
        }
    }

    // Priority 3 – system default ringtone
    $defaultStmt = $pdo->prepare("
        SELECT id, name, file_url
        FROM   ringtones
        WHERE  is_default = 1 AND is_active = 1
        LIMIT 1
    ");
    $defaultStmt->execute();
    $default = $defaultStmt->fetch();

    if ($default) {
        echo json_encode([
            'success'       => true,
            'type'          => 'default',
            'ringtone_id'   => (string) $default['id'],
            'ringtone_name' => $default['name'],
            'ringtone_url'  => $default['file_url'],
        ]);
        exit;
    }

    // Priority 4 – no ringtone configured at all (app uses its built-in default)
    echo json_encode([
        'success'       => true,
        'type'          => 'builtin',
        'ringtone_id'   => null,
        'ringtone_name' => null,
        'ringtone_url'  => null,
    ]);

} catch (PDOException $e) {
    error_log('get_call_ringtone error: ' . $e->getMessage());
    echo json_encode(['success' => false, 'message' => 'Server error. Please try again.']);
}
