<?php
/**
 * update_app_settings.php
 *
 * Admin endpoint to update global application call-tone settings.
 * Settings are persisted in the `app_settings` table (key/value store).
 *
 * POST body (JSON):
 *   call_tone_id          (string) – optional – ID of the selected built-in tone
 *   clear_custom_call_tone (bool)  – optional – when true, removes the custom tone
 *
 * Response:
 *   {
 *     "success": true,
 *     "data": {
 *       "call_tone_id":         "classic",
 *       "custom_call_tone_url":  "",
 *       "custom_call_tone_name": ""
 *     }
 *   }
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

require_once __DIR__ . '/auth.php';
requireAdminAuth();

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['success' => false, 'message' => 'Method not allowed']);
    exit;
}

// ── DB credentials ────────────────────────────────────────────────────────────
define('DB_HOST', 'localhost');
define('DB_NAME', 'ms');
define('DB_USER', 'ms');
define('DB_PASS', 'ms');

// ── Valid built-in tone IDs ───────────────────────────────────────────────────
$validToneIds = ['classic', 'soft', 'modern', 'default', 'custom'];

// ── Input ─────────────────────────────────────────────────────────────────────
$input = json_decode(file_get_contents('php://input'), true) ?? [];

$newToneId         = isset($input['call_tone_id'])           ? trim((string) $input['call_tone_id']) : null;
$clearCustomTone   = isset($input['clear_custom_call_tone']) ? filter_var($input['clear_custom_call_tone'], FILTER_VALIDATE_BOOLEAN) : false;

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
    http_response_code(503);
    echo json_encode(['success' => false, 'message' => 'Database connection failed']);
    exit;
}

// ── Ensure app_settings table exists ─────────────────────────────────────────
$pdo->exec("
    CREATE TABLE IF NOT EXISTS app_settings (
        `setting_key`   VARCHAR(100) NOT NULL PRIMARY KEY,
        `setting_value` TEXT,
        updated_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
");

// ── Helper: upsert a setting ──────────────────────────────────────────────────
function upsertSetting(PDO $pdo, string $key, ?string $value): void {
    $pdo->prepare(
        "INSERT INTO app_settings (setting_key, setting_value) VALUES (?, ?)
         ON DUPLICATE KEY UPDATE setting_value = VALUES(setting_value)"
    )->execute([$key, $value]);
}

// ── Helper: read a setting ────────────────────────────────────────────────────
function readSetting(PDO $pdo, string $key, ?string $default = null): ?string {
    $stmt = $pdo->prepare('SELECT setting_value FROM app_settings WHERE setting_key = ? LIMIT 1');
    $stmt->execute([$key]);
    $row = $stmt->fetch();
    return $row !== false ? $row['setting_value'] : $default;
}

try {
    // ── Apply requested changes ───────────────────────────────────────────────
    if ($clearCustomTone) {
        upsertSetting($pdo, 'custom_call_tone_url', '');
        upsertSetting($pdo, 'custom_call_tone_name', '');
        // Revert tone ID to default when custom tone is cleared
        $currentToneId = readSetting($pdo, 'call_tone_id', 'default');
        if ($currentToneId === 'custom') {
            upsertSetting($pdo, 'call_tone_id', 'default');
        }
    }

    if ($newToneId !== null) {
        // Accept any value from the valid list (or 'custom' set by upload)
        if (in_array($newToneId, $validToneIds, true)) {
            upsertSetting($pdo, 'call_tone_id', $newToneId);
        }
    }

    // ── Return current state ──────────────────────────────────────────────────
    $toneId          = readSetting($pdo, 'call_tone_id', 'default');
    $customToneUrl   = readSetting($pdo, 'custom_call_tone_url', '');
    $customToneName  = readSetting($pdo, 'custom_call_tone_name', '');

    echo json_encode([
        'success' => true,
        'data'    => [
            'call_tone_id'          => $toneId ?? 'default',
            'custom_call_tone_url'  => $customToneUrl  ?? '',
            'custom_call_tone_name' => $customToneName ?? '',
        ],
    ]);

} catch (PDOException $e) {
    error_log('update_app_settings error: ' . $e->getMessage());
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Server error']);
}
