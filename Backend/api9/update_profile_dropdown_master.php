<?php
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['success' => false, 'message' => 'Method not allowed']);
    exit;
}

$defaultMaster = [
    'religion' => ['Hindu', 'Buddhist', 'Muslim', 'Christian', 'Kirat', 'Other'],
    'community' => ['Brahmin', 'Chhetri', 'Newar', 'Gurung', 'Rai', 'Limbu', 'Other'],
    'castgroup' => ['Khas', 'Janajati', 'Madhesi', 'Dalit', 'Tharu', 'Muslim', 'Other'],
    'caste' => ['Bahun', 'Chhetri', 'Newar', 'Gurung', 'Magar', 'Tamang', 'Other'],
    'annualincome' => [
        'No Income', 'Below 1 Lakh', '1-2 Lakhs', '2-3 Lakhs', '3-5 Lakhs',
        '5-7 Lakhs', '7-10 Lakhs', '10-15 Lakhs', '15-20 Lakhs', '20-30 Lakhs',
        '30-50 Lakhs', '50 Lakhs - 1 Crore', 'Above 1 Crore',
    ],
    'educationtype' => ['School', 'Diploma', 'Bachelor', 'Master', 'PhD'],
    'degree' => ['SEE/SLC', '+2 / Intermediate', 'Bachelor', 'Master', 'PhD'],
    'faculty' => ['Science', 'Management', 'Humanities', 'Education', 'Engineering', 'Medical', 'IT'],
    'educationmedium' => ['English', 'Nepali', 'Hindi', 'Other'],
    'occupationtype' => ['Private Job', 'Government Job', 'Business', 'Self Employed', 'Professional', 'Student', 'Not Working'],
    'workingwith' => ['Private Company', 'Government Sector', 'Own Business', 'NGO/INGO', 'Startup', 'Freelance', 'Other'],
];

function normalizeStringList($value): array {
    if (!is_array($value)) return [];
    $out = [];
    foreach ($value as $item) {
        $text = trim((string)$item);
        if ($text !== '') $out[] = $text;
    }
    return array_values(array_unique($out));
}

$input = json_decode(file_get_contents('php://input'), true) ?? [];
$field = isset($input['field']) ? trim((string)$input['field']) : '';
$options = $input['options'] ?? null;

if ($field === '' || !array_key_exists($field, $defaultMaster)) {
    http_response_code(422);
    echo json_encode(['success' => false, 'message' => 'Invalid field']);
    exit;
}

$normalized = normalizeStringList($options);
if (empty($normalized)) {
    http_response_code(422);
    echo json_encode(['success' => false, 'message' => 'At least one option is required']);
    exit;
}

$host = 'localhost';
$dbName = 'ms';
$user = 'root';
$pass = '';

$conn = new mysqli($host, $user, $pass, $dbName);
if ($conn->connect_error) {
    http_response_code(503);
    echo json_encode(['success' => false, 'message' => 'Database connection failed']);
    exit;
}
$conn->set_charset('utf8mb4');

$merged = $defaultMaster;
$stmtRead = $conn->prepare('SELECT setting_value FROM app_settings WHERE setting_key = ? LIMIT 1');
if ($stmtRead) {
    $settingsKey = 'profile_dropdown_master_json';
    $stmtRead->bind_param('s', $settingsKey);
    $stmtRead->execute();
    $res = $stmtRead->get_result();
    $row = $res ? $res->fetch_assoc() : null;
    $stmtRead->close();

    if ($row && isset($row['setting_value'])) {
        $decoded = json_decode((string)$row['setting_value'], true);
        if (is_array($decoded)) {
            foreach ($defaultMaster as $k => $fallback) {
                $items = normalizeStringList($decoded[$k] ?? null);
                $merged[$k] = !empty($items) ? $items : $fallback;
            }
        }
    }
}

$merged[$field] = $normalized;
$json = json_encode($merged, JSON_UNESCAPED_UNICODE);
if ($json === false) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Failed to encode settings']);
    $conn->close();
    exit;
}

$stmtWrite = $conn->prepare(
    'INSERT INTO app_settings (setting_key, setting_value) VALUES (?, ?) ON DUPLICATE KEY UPDATE setting_value = VALUES(setting_value)'
);
if (!$stmtWrite) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Failed to prepare update']);
    $conn->close();
    exit;
}

$settingsKey = 'profile_dropdown_master_json';
$stmtWrite->bind_param('ss', $settingsKey, $json);
$ok = $stmtWrite->execute();
$stmtWrite->close();
$conn->close();

if (!$ok) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Failed to save options']);
    exit;
}

echo json_encode([
    'success' => true,
    'field' => $field,
    'data' => $merged[$field],
]);
