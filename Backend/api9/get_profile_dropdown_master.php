<?php
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
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

$stmt = $conn->prepare('SELECT setting_value FROM app_settings WHERE setting_key = ? LIMIT 1');
if ($stmt) {
    $key = 'profile_dropdown_master_json';
    $stmt->bind_param('s', $key);
    $stmt->execute();
    $res = $stmt->get_result();
    $row = $res ? $res->fetch_assoc() : null;
    $stmt->close();

    if ($row && isset($row['setting_value'])) {
        $decoded = json_decode((string)$row['setting_value'], true);
        if (is_array($decoded)) {
            foreach ($defaultMaster as $field => $fallback) {
                $items = normalizeStringList($decoded[$field] ?? null);
                $merged[$field] = !empty($items) ? $items : $fallback;
            }
        }
    }
}

$conn->close();

echo json_encode([
    'success' => true,
    'data' => $merged,
]);
