<?php
/**
 * call_settings.php
 *
 * Read or update the call settings (ringtone preference) for a user.
 *
 * GET  ?user_id=123
 *   Returns the user's current call settings plus the full list of active
 *   system ringtones so the app can populate its picker in one round-trip.
 *
 * POST body (JSON or form-encoded):
 *   user_id     (int)     – required
 *   ringtone_id (int)     – optional  system ringtone to use (NULL = system default)
 *   is_custom   (bool)    – optional  true = play custom tone; false = play system tone
 *
 * Notes:
 *   • To clear the custom tone and revert to a system ringtone send is_custom=false.
 *   • The custom tone URL itself is set via upload_custom_tone.php.
 */

ini_set('display_errors', 0);
ini_set('log_errors', 1);
error_reporting(E_ALL);

header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

require_once __DIR__ . '/db_config.php';

// --------------------------------------------------------------------------
// GET – fetch settings
// --------------------------------------------------------------------------

if ($_SERVER['REQUEST_METHOD'] === 'GET') {
    $user_id = isset($_GET['user_id']) ? (int) $_GET['user_id'] : 0;

    if ($user_id <= 0) {
        echo json_encode(['success' => false, 'message' => 'user_id is required']);
        exit;
    }

    try {
        // User's current settings (may not exist yet → all nulls/defaults)
        $settingsStmt = $pdo->prepare("
            SELECT ucs.ringtone_id, ucs.custom_tone_url, ucs.custom_tone_name, ucs.is_custom,
                   rt.name AS ringtone_name, rt.file_url AS ringtone_url
            FROM   user_call_settings ucs
            LEFT JOIN ringtones rt ON rt.id = ucs.ringtone_id AND rt.is_active = 1
            WHERE  ucs.user_id = ?
            LIMIT 1
        ");
        $settingsStmt->execute([$user_id]);
        $settings = $settingsStmt->fetch();

        // If no row yet, return defaults
        if (!$settings) {
            $settings = [
                'ringtone_id'      => null,
                'ringtone_name'    => null,
                'ringtone_url'     => null,
                'custom_tone_url'  => null,
                'custom_tone_name' => null,
                'is_custom'        => false,
            ];
        } else {
            $settings['is_custom'] = (bool) $settings['is_custom'];
        }

        // System default ringtone
        $defaultStmt = $pdo->prepare("
            SELECT id, name, file_url
            FROM   ringtones
            WHERE  is_default = 1 AND is_active = 1
            LIMIT 1
        ");
        $defaultStmt->execute();
        $defaultTone = $defaultStmt->fetch() ?: null;

        // All active system ringtones for the picker
        $listStmt = $pdo->prepare("
            SELECT id, name, file_url
            FROM   ringtones
            WHERE  is_active = 1
            ORDER BY is_default DESC, name ASC
        ");
        $listStmt->execute();
        $ringtones = $listStmt->fetchAll();

        echo json_encode([
            'success'       => true,
            'settings'      => $settings,
            'default_tone'  => $defaultTone,
            'ringtones'     => $ringtones,
        ]);

    } catch (PDOException $e) {
        error_log('call_settings GET error: ' . $e->getMessage());
        echo json_encode(['success' => false, 'message' => 'Server error. Please try again.']);
    }
    exit;
}

// --------------------------------------------------------------------------
// POST – update settings
// --------------------------------------------------------------------------

$input = json_decode(file_get_contents('php://input'), true);
if (empty($input)) {
    $input = $_POST;
}

$user_id     = isset($input['user_id'])     ? (int)   $input['user_id']    : 0;
$ringtone_id = isset($input['ringtone_id']) ? (int)   $input['ringtone_id']: 0;
$is_custom   = isset($input['is_custom'])
    ? filter_var($input['is_custom'], FILTER_VALIDATE_BOOLEAN)
    : null;

if ($user_id <= 0) {
    echo json_encode(['success' => false, 'message' => 'user_id is required']);
    exit;
}

try {
    // Check the ringtone_id is valid if provided
    $ringtone_id_val = ($ringtone_id > 0) ? $ringtone_id : null;
    if ($ringtone_id_val !== null) {
        $rtCheck = $pdo->prepare("SELECT id FROM ringtones WHERE id = ? AND is_active = 1 LIMIT 1");
        $rtCheck->execute([$ringtone_id_val]);
        if (!$rtCheck->fetch()) {
            echo json_encode(['success' => false, 'message' => 'Ringtone not found or inactive']);
            exit;
        }
    }

    // Build the upsert SET clause dynamically based on what was provided
    $setClauses = ['ringtone_id = :ringtone_id'];
    $params     = [':ringtone_id' => $ringtone_id_val, ':user_id' => $user_id];

    if ($is_custom !== null) {
        $setClauses[]        = 'is_custom = :is_custom';
        $params[':is_custom'] = (int) $is_custom;
    }

    $setSQL = implode(', ', $setClauses);

    $stmt = $pdo->prepare("
        INSERT INTO user_call_settings (user_id, ringtone_id, is_custom)
        VALUES (:user_id, :ringtone_id, :is_custom_ins)
        ON DUPLICATE KEY UPDATE $setSQL, updated_at = NOW()
    ");

    $params[':is_custom_ins'] = ($is_custom !== null) ? (int) $is_custom : 0;
    $stmt->execute($params);

    echo json_encode(['success' => true, 'message' => 'Call settings updated']);

} catch (PDOException $e) {
    error_log('call_settings POST error: ' . $e->getMessage());
    echo json_encode(['success' => false, 'message' => 'Server error. Please try again.']);
}
