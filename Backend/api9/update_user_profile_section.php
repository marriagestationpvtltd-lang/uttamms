<?php
/**
 * update_user_profile_section.php
 *
 * Updates multiple profile fields for a single section in one request.
 *
 * POST body (JSON):
 *   userid  (int)               required
 *   section (string)            required: personal, family, lifestyle, partner
 *   fields  (object<string,mixed>) required: field => value map
 *
 * Response:
 *   { "success": true,  "message": "Section updated successfully" }
 *   { "success": false, "message": "<reason>" }
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

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['success' => false, 'message' => 'Method not allowed']);
    exit;
}

define('DB_HOST', 'localhost');
define('DB_NAME', 'ms');
define('DB_USER', 'root');
define('DB_PASS', '');

$input = json_decode(file_get_contents('php://input'), true) ?? [];
$userId = isset($input['userid']) ? (int) $input['userid'] : 0;
$section = isset($input['section']) ? trim((string) $input['section']) : '';
$fieldsInput = $input['fields'] ?? null;

if ($userId <= 0 || $section === '' || !is_array($fieldsInput) || empty($fieldsInput)) {
    http_response_code(422);
    echo json_encode([
        'success' => false,
        'message' => 'userid, section, and non-empty fields are required',
    ]);
    exit;
}

$fieldMap = [
    'personal' => [
        'firstName' => 'users',
        'lastName' => 'users',
        'privacy' => 'users',
        'gender' => 'users',
        'country' => 'permanent_address',
        'state' => 'permanent_address',
        'city' => 'permanent_address',
        'height_name' => 'userpersonaldetail',
        'maritalStatusId' => 'userpersonaldetail',
        'religionId' => 'userpersonaldetail',
        'communityId' => 'userpersonaldetail',
        'subCommunityId' => 'userpersonaldetail',
        'motherTongue' => 'userpersonaldetail',
        'aboutMe' => 'userpersonaldetail',
        'birthDate' => 'userpersonaldetail',
        'Disability' => 'userpersonaldetail',
        'bloodGroup' => 'userpersonaldetail',
        'complexion' => 'userpersonaldetail',
        'bodyType' => 'userpersonaldetail',
        'childStatus' => 'userpersonaldetail',
        'educationtype' => 'educationcareer',
        'educationmedium' => 'educationcareer',
        'faculty' => 'educationcareer',
        'degree' => 'educationcareer',
        'areyouworking' => 'educationcareer',
        'occupationtype' => 'educationcareer',
        'companyname' => 'educationcareer',
        'designation' => 'educationcareer',
        'workingwith' => 'educationcareer',
        'annualincome' => 'educationcareer',
        'businessname' => 'educationcareer',
        'manglik' => 'user_astrologic',
        'birthtime' => 'user_astrologic',
        'birthcity' => 'user_astrologic',
    ],
    'family' => [
        'familytype' => 'user_family',
        'familybackground' => 'user_family',
        'fatherstatus' => 'user_family',
        'fathername' => 'user_family',
        'fathereducation' => 'user_family',
        'fatheroccupation' => 'user_family',
        'motherstatus' => 'user_family',
        'mothercaste' => 'user_family',
        'mothereducation' => 'user_family',
        'motheroccupation' => 'user_family',
        'familyorigin' => 'user_family',
    ],
    'lifestyle' => [
        'smoketype' => 'user_lifestyle',
        'diet' => 'user_lifestyle',
        'drinks' => 'user_lifestyle',
        'drinktype' => 'user_lifestyle',
        'smoke' => 'user_lifestyle',
    ],
    'partner' => [
        'minage' => 'user_partner',
        'maxage' => 'user_partner',
        'minheight' => 'user_partner',
        'maxheight' => 'user_partner',
        'maritalstatus' => 'user_partner',
        'profilewithchild' => 'user_partner',
        'familytype' => 'user_partner',
        'religion' => 'user_partner',
        'caste' => 'user_partner',
        'mothertoungue' => 'user_partner',
        'herscopeblief' => 'user_partner',
        'manglik' => 'user_partner',
        'country' => 'user_partner',
        'state' => 'user_partner',
        'city' => 'user_partner',
        'qualification' => 'user_partner',
        'educationmedium' => 'user_partner',
        'proffession' => 'user_partner',
        'workingwith' => 'user_partner',
        'annualincome' => 'user_partner',
        'diet' => 'user_partner',
        'smokeaccept' => 'user_partner',
        'drinkaccept' => 'user_partner',
        'disabilityaccept' => 'user_partner',
        'complexion' => 'user_partner',
        'bodytype' => 'user_partner',
        'otherexpectation' => 'user_partner',
    ],
];

$allowedTableColumns = [
    'users' => ['firstName', 'lastName', 'privacy', 'gender'],
    'permanent_address' => ['country', 'state', 'city'],
    'userpersonaldetail' => ['height_name', 'maritalStatusId', 'religionId', 'communityId', 'subCommunityId', 'motherTongue', 'aboutMe', 'birthDate', 'Disability', 'bloodGroup', 'complexion', 'bodyType', 'childStatus'],
    'educationcareer' => ['educationtype', 'educationmedium', 'faculty', 'degree', 'areyouworking', 'occupationtype', 'companyname', 'designation', 'workingwith', 'annualincome', 'businessname'],
    'user_astrologic' => ['manglik', 'birthtime', 'birthcity'],
    'user_family' => ['familytype', 'familybackground', 'fatherstatus', 'fathername', 'fathereducation', 'fatheroccupation', 'motherstatus', 'mothercaste', 'mothereducation', 'motheroccupation', 'familyorigin'],
    'user_lifestyle' => ['smoketype', 'diet', 'drinks', 'drinktype', 'smoke'],
    'user_partner' => ['minage', 'maxage', 'minheight', 'maxheight', 'maritalstatus', 'profilewithchild', 'familytype', 'religion', 'caste', 'mothertoungue', 'herscopeblief', 'manglik', 'country', 'state', 'city', 'qualification', 'educationmedium', 'proffession', 'workingwith', 'annualincome', 'diet', 'smokeaccept', 'drinkaccept', 'disabilityaccept', 'complexion', 'bodytype', 'otherexpectation'],
];

if (!isset($fieldMap[$section])) {
    http_response_code(422);
    echo json_encode(['success' => false, 'message' => "Unknown section: $section"]);
    exit;
}

$updatesByTable = [];
foreach ($fieldsInput as $field => $rawValue) {
    $field = trim((string) $field);
    if ($field === '') {
        continue;
    }

    if (!array_key_exists($field, $fieldMap[$section])) {
        http_response_code(422);
        echo json_encode([
            'success' => false,
            'message' => "Unknown field '$field' in section '$section'",
        ]);
        exit;
    }

    $table = $fieldMap[$section][$field];
    if (!isset($allowedTableColumns[$table]) || !in_array($field, $allowedTableColumns[$table], true)) {
        http_response_code(422);
        echo json_encode([
            'success' => false,
            'message' => "Field '$field' is not allowed in table '$table'",
        ]);
        exit;
    }

    if (!is_scalar($rawValue) && $rawValue !== null) {
        $value = json_encode($rawValue);
    } else {
        $value = (string) ($rawValue ?? '');
    }

    if (!isset($updatesByTable[$table])) {
        $updatesByTable[$table] = [];
    }
    $updatesByTable[$table][$field] = $value;
}

if (empty($updatesByTable)) {
    http_response_code(422);
    echo json_encode(['success' => false, 'message' => 'No valid fields to update']);
    exit;
}

try {
    $pdo = new PDO(
        'mysql:host=' . DB_HOST . ';dbname=' . DB_NAME . ';charset=utf8mb4',
        DB_USER,
        DB_PASS,
        [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES => false,
        ]
    );
} catch (PDOException $e) {
    http_response_code(503);
    echo json_encode(['success' => false, 'message' => 'Database connection failed']);
    exit;
}

$check = $pdo->prepare('SELECT id FROM users WHERE id = ? LIMIT 1');
$check->execute([$userId]);
if (!$check->fetch()) {
    http_response_code(404);
    echo json_encode(['success' => false, 'message' => 'User not found']);
    exit;
}

try {
    $pdo->beginTransaction();

    foreach ($updatesByTable as $table => $pairs) {
        $columns = array_keys($pairs);
        $values = array_values($pairs);

        if ($table === 'users') {
            $setParts = [];
            foreach ($columns as $col) {
                $setParts[] = '`' . $col . '` = ?';
            }
            $sql = 'UPDATE `users` SET ' . implode(', ', $setParts) . ' WHERE id = ?';
            $stmt = $pdo->prepare($sql);
            $stmt->execute(array_merge($values, [$userId]));
            continue;
        }

        $columnList = '`userid`, ' . implode(', ', array_map(static function ($c) {
            return '`' . $c . '`';
        }, $columns));

        $insertPlaceholders = implode(', ', array_fill(0, count($columns) + 1, '?'));

        $updateParts = implode(', ', array_map(static function ($c) {
            return '`' . $c . '` = VALUES(`' . $c . '`)';
        }, $columns));

        $sql = 'INSERT INTO `' . $table . '` (' . $columnList . ') VALUES (' . $insertPlaceholders . ') '
             . 'ON DUPLICATE KEY UPDATE ' . $updateParts;

        $stmt = $pdo->prepare($sql);
        $stmt->execute(array_merge([$userId], $values));
    }

    $pdo->commit();

    echo json_encode([
        'success' => true,
        'message' => 'Section updated successfully',
        'section' => $section,
        'updated_fields' => count($fieldsInput),
    ]);
} catch (PDOException $e) {
    if ($pdo->inTransaction()) {
        $pdo->rollBack();
    }
    error_log('update_user_profile_section error: ' . $e->getMessage());
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Server error']);
}
