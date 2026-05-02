<?php
/**
 * app_settings.php
 *
 * Public GET endpoint that returns global sound settings used by the app.
 * This includes outgoing call tone plus incoming/message/typing tone files
 * that can be controlled by admin.
 *
 * GET (no parameters required)
 *
 * Response:
 *   {
 *     "success": true,
 *     "data": {
 *       "call_tone_id":            "classic",
 *       "custom_call_tone_url":    "",
 *       "custom_call_tone_name":   "",
 *       "incoming_tone_id":        "default",
 *       "custom_incoming_tone_url": "",
 *       "custom_incoming_tone_name": "",
 *       "message_tone_id":         "default",
 *       "custom_message_tone_url": "",
 *       "custom_message_tone_name": "",
 *       "typing_tone_id":          "default",
 *       "custom_typing_tone_url":  "",
 *       "custom_typing_tone_name": ""
 *     }
 *   }
 */

ini_set('display_errors', 0);
ini_set('log_errors', 1);
error_reporting(E_ALL);

header('Content-Type: application/json');

$defaultSettings = [
    'call_tone_id' => 'default',
    'custom_call_tone_url' => '',
    'custom_call_tone_name' => '',
    'incoming_tone_id' => 'default',
    'custom_incoming_tone_url' => '',
    'custom_incoming_tone_name' => '',
    'message_tone_id' => 'default',
    'custom_message_tone_url' => '',
    'custom_message_tone_name' => '',
    'typing_tone_id' => 'default',
    'custom_typing_tone_url' => '',
    'custom_typing_tone_name' => '',
];

// ── DB credentials ────────────────────────────────────────────────────────────
define('DB_HOST', 'localhost');
define('DB_NAME', 'ms');
define('DB_USER', 'root');
define('DB_PASS', '');

// ── Connect ───────────────────────────────────────────────────────────────────
try {
    $pdo = new PDO(
        'mysql:host=' . DB_HOST . ';dbname=' . DB_NAME . ';charset=utf8mb4',
        DB_USER,
        DB_PASS,
        [
            PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES   => false,
        ]
    );
} catch (PDOException $e) {
    // Return sensible defaults if DB is unreachable so the app still starts
    echo json_encode([
        'success' => true,
        'data'    => $defaultSettings,
    ]);
    exit;
}

try {
    // Ensure table exists before querying
    $pdo->exec("
        CREATE TABLE IF NOT EXISTS app_settings (
            `setting_key`   VARCHAR(100) NOT NULL PRIMARY KEY,
            `setting_value` TEXT,
            updated_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ");

    // Fetch all relevant keys in one query
    $settingKeys = array_keys($defaultSettings);
    $placeholders = implode(',', array_fill(0, count($settingKeys), '?'));
    $stmt = $pdo->prepare(
        "SELECT setting_key, setting_value FROM app_settings
         WHERE setting_key IN ($placeholders)"
    );
    $stmt->execute($settingKeys);
    $rows = $stmt->fetchAll();

    $settings = [];
    foreach ($rows as $row) {
        $settings[$row['setting_key']] = $row['setting_value'];
    }

    $responseData = $defaultSettings;
    foreach ($settings as $key => $value) {
        if (array_key_exists($key, $responseData)) {
            $responseData[$key] = $value;
        }
    }

    echo json_encode([
        'success' => true,
        'data'    => $responseData,
    ]);

} catch (PDOException $e) {
    error_log('app_settings error: ' . $e->getMessage());
    // Return defaults on error so the app can still start
    echo json_encode([
        'success' => true,
        'data'    => $defaultSettings,
    ]);
}
