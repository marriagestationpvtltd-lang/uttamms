<?php
/**
 * get_profile_field_options.php
 * Returns selectable options for admin profile edit dropdowns.
 *
 * Query params:
 *   field=maritalStatusId|religionId|communityId|subCommunityId|
 *         religion|community|castgroup|caste|
 *         annualincome|educationtype|degree|faculty|
 *         educationmedium|occupationtype|workingwith (required)
 *   religion_id=int (optional, for community/subCommunity filter)
 *   community_id=int (optional, for subCommunity filter)
 */

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

$field = isset($_GET['field']) ? trim((string)$_GET['field']) : '';
$religionId = isset($_GET['religion_id']) ? (int)$_GET['religion_id'] : 0;
$communityId = isset($_GET['community_id']) ? (int)$_GET['community_id'] : 0;

if ($field === '') {
    http_response_code(422);
    echo json_encode(['success' => false, 'message' => 'field is required']);
    exit;
}

$allowed = [
    'maritalStatusId',
    'religionId',
    'communityId',
    'subCommunityId',
    'religion',
    'community',
    'castgroup',
    'caste',
    'annualincome',
    'educationtype',
    'degree',
    'faculty',
    'educationmedium',
    'occupationtype',
    'workingwith',
];
if (!in_array($field, $allowed, true)) {
    http_response_code(422);
    echo json_encode(['success' => false, 'message' => 'Unsupported field']);
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

function fetchOptions(mysqli $conn, string $sql, string $types = '', array $params = []): array {
    $stmt = $conn->prepare($sql);
    if (!$stmt) {
        return [];
    }
    if ($types !== '' && !empty($params)) {
        $stmt->bind_param($types, ...$params);
    }
    $stmt->execute();
    $result = $stmt->get_result();
    $rows = [];
    while ($row = $result->fetch_assoc()) {
        $rows[] = [
            'value' => (string)($row['id'] ?? ''),
            'label' => (string)($row['name'] ?? ''),
        ];
    }
    $stmt->close();
    return $rows;
}

function normalizeStringList($value): array {
    if (!is_array($value)) {
        return [];
    }
    $out = [];
    foreach ($value as $item) {
        $text = trim((string)$item);
        if ($text !== '') {
            $out[] = $text;
        }
    }
    return array_values(array_unique($out));
}

function buildSimpleOptions(array $items): array {
    $rows = [];
    foreach ($items as $item) {
        $rows[] = ['value' => $item, 'label' => $item];
    }
    return $rows;
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

$masterOptions = $defaultMaster;

$stmtMaster = $conn->prepare('SELECT setting_value FROM app_settings WHERE setting_key = ? LIMIT 1');
if ($stmtMaster) {
    $settingsKey = 'profile_dropdown_master_json';
    $stmtMaster->bind_param('s', $settingsKey);
    $stmtMaster->execute();
    $resMaster = $stmtMaster->get_result();
    $rowMaster = $resMaster ? $resMaster->fetch_assoc() : null;
    $stmtMaster->close();

    if ($rowMaster && isset($rowMaster['setting_value'])) {
        $decoded = json_decode((string)$rowMaster['setting_value'], true);
        if (is_array($decoded)) {
            foreach ($defaultMaster as $key => $fallback) {
                $fromDb = normalizeStringList($decoded[$key] ?? null);
                $masterOptions[$key] = !empty($fromDb) ? $fromDb : $fallback;
            }
        }
    }
}

$options = [];

if ($field === 'maritalStatusId') {
    $options = fetchOptions(
        $conn,
        'SELECT id, name FROM maritalstatus WHERE (isDelete = 0 OR isDelete IS NULL) ORDER BY name ASC'
    );
} elseif ($field === 'religionId') {
    $options = fetchOptions(
        $conn,
        'SELECT id, name FROM religion WHERE (isDelete = 0 OR isDelete IS NULL) ORDER BY name ASC'
    );
} elseif ($field === 'communityId') {
    if ($religionId > 0) {
        $options = fetchOptions(
            $conn,
            'SELECT id, name FROM community WHERE (isDelete = 0 OR isDelete IS NULL) AND (religionId = ? OR religionId IS NULL) ORDER BY name ASC',
            'i',
            [$religionId]
        );
    } else {
        $options = fetchOptions(
            $conn,
            'SELECT id, name FROM community WHERE (isDelete = 0 OR isDelete IS NULL) ORDER BY name ASC'
        );
    }
} elseif ($field === 'subCommunityId') {
    if ($communityId > 0) {
        $options = fetchOptions(
            $conn,
            'SELECT id, name FROM subcommunity WHERE (isDelete = 0 OR isDelete IS NULL) AND communityId = ? ORDER BY name ASC',
            'i',
            [$communityId]
        );
    } elseif ($religionId > 0) {
        $options = fetchOptions(
            $conn,
            'SELECT id, name FROM subcommunity WHERE (isDelete = 0 OR isDelete IS NULL) AND religionId = ? ORDER BY name ASC',
            'i',
            [$religionId]
        );
    } else {
        $options = fetchOptions(
            $conn,
            'SELECT id, name FROM subcommunity WHERE (isDelete = 0 OR isDelete IS NULL) ORDER BY name ASC'
        );
    }
} elseif (isset($masterOptions[$field])) {
    $options = buildSimpleOptions($masterOptions[$field]);
}

$conn->close();

echo json_encode([
    'success' => true,
    'field' => $field,
    'data' => $options,
]);
