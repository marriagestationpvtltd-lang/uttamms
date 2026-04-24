<?php
/**
 * update_user_profile.php
 *
 * Updates a single field of a user's profile from the admin panel.
 *
 * POST body (JSON):
 *   userid  (int)    – required – target user's ID
 *   section (string) – required – one of: personal, family, lifestyle, partner
 *   field   (string) – required – snake_case column name (matched against whitelist)
 *   value   (string) – required – new value
 *
 * Response:
 *   { "success": true,  "message": "Profile updated successfully" }
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

// ── DB credentials ────────────────────────────────────────────────────────────
define('DB_HOST', 'localhost');
define('DB_NAME', 'ms');
define('DB_USER', 'ms');
define('DB_PASS', 'ms');

// ── Input ─────────────────────────────────────────────────────────────────────
$input   = json_decode(file_get_contents('php://input'), true) ?? [];
$userId  = isset($input['userid'])  ? (int)   $input['userid']  : 0;
$section = isset($input['section']) ? trim((string) $input['section']) : '';
$field   = isset($input['field'])   ? trim((string) $input['field'])   : '';
$value   = isset($input['value'])   ? $input['value']                  : '';

if ($userId <= 0 || $section === '' || $field === '') {
    http_response_code(422);
    echo json_encode(['success' => false, 'message' => 'userid, section, and field are required']);
    exit;
}

// ── Whitelisted field maps ────────────────────────────────────────────────────
// Maps section → [ field => table ]
$fieldMap = [
    'personal' => [
        // users table
        'firstName'     => 'users',
        'lastName'      => 'users',
        'privacy'       => 'users',
        'gender'        => 'users',
        // userpersonaldetail table
        'height_name'      => 'userpersonaldetail',
        'maritalStatusId'  => 'userpersonaldetail',
        'motherTongue'     => 'userpersonaldetail',
        'aboutMe'          => 'userpersonaldetail',
        'birthDate'        => 'userpersonaldetail',
        'Disability'       => 'userpersonaldetail',
        'bloodGroup'       => 'userpersonaldetail',
        'complexion'       => 'userpersonaldetail',
        'bodyType'         => 'userpersonaldetail',
        'childStatus'      => 'userpersonaldetail',
        // educationcareer table
        'educationtype'    => 'educationcareer',
        'educationmedium'  => 'educationcareer',
        'faculty'          => 'educationcareer',
        'degree'           => 'educationcareer',
        'areyouworking'    => 'educationcareer',
        'occupationtype'   => 'educationcareer',
        'companyname'      => 'educationcareer',
        'designation'      => 'educationcareer',
        'workingwith'      => 'educationcareer',
        'annualincome'     => 'educationcareer',
        'businessname'     => 'educationcareer',
        // user_astrologic table
        'manglik'          => 'user_astrologic',
        'birthtime'        => 'user_astrologic',
        'birthcity'        => 'user_astrologic',
    ],
    'family' => [
        'familytype'       => 'user_family',
        'familybackground' => 'user_family',
        'fatherstatus'     => 'user_family',
        'fathername'       => 'user_family',
        'fathereducation'  => 'user_family',
        'fatheroccupation' => 'user_family',
        'motherstatus'     => 'user_family',
        'mothercaste'      => 'user_family',
        'mothereducation'  => 'user_family',
        'motheroccupation' => 'user_family',
        'familyorigin'     => 'user_family',
    ],
    'lifestyle' => [
        'smoketype' => 'user_lifestyle',
        'diet'      => 'user_lifestyle',
        'drinks'    => 'user_lifestyle',
        'drinktype' => 'user_lifestyle',
        'smoke'     => 'user_lifestyle',
    ],
    'partner' => [
        'minage'           => 'user_partner',
        'maxage'           => 'user_partner',
        'minheight'        => 'user_partner',
        'maxheight'        => 'user_partner',
        'maritalstatus'    => 'user_partner',
        'profilewithchild' => 'user_partner',
        'familytype'       => 'user_partner',
        'religion'         => 'user_partner',
        'caste'            => 'user_partner',
        'mothertoungue'    => 'user_partner',
        'herscopeblief'    => 'user_partner',
        'manglik'          => 'user_partner',
        'country'          => 'user_partner',
        'state'            => 'user_partner',
        'city'             => 'user_partner',
        'qualification'    => 'user_partner',
        'educationmedium'  => 'user_partner',
        'proffession'      => 'user_partner',
        'workingwith'      => 'user_partner',
        'annualincome'     => 'user_partner',
        'diet'             => 'user_partner',
        'smokeaccept'      => 'user_partner',
        'drinkaccept'      => 'user_partner',
        'disabilityaccept' => 'user_partner',
        'complexion'       => 'user_partner',
        'bodytype'         => 'user_partner',
        'otherexpectation' => 'user_partner',
    ],
];

// ── Validate section & field ───────────────────────────────────────────────────
if (!isset($fieldMap[$section])) {
    http_response_code(422);
    echo json_encode(['success' => false, 'message' => "Unknown section: $section"]);
    exit;
}

if (!array_key_exists($field, $fieldMap[$section])) {
    http_response_code(422);
    echo json_encode(['success' => false, 'message' => "Unknown field '$field' in section '$section'"]);
    exit;
}

$table = $fieldMap[$section][$field];

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

// ── Verify user exists ────────────────────────────────────────────────────────
$check = $pdo->prepare('SELECT id FROM users WHERE id = ? LIMIT 1');
$check->execute([$userId]);
if (!$check->fetch()) {
    http_response_code(404);
    echo json_encode(['success' => false, 'message' => 'User not found']);
    exit;
}

// ── Build explicit SQL from whitelisted table+field ───────────────────────────
// The $table and $field values are exclusively sourced from $fieldMap (not from
// user input), but we construct the SQL here to make that provenance explicit.
$allowedTableColumns = [
    'users'               => ['firstName','lastName','privacy','gender'],
    'userpersonaldetail'  => ['height_name','maritalStatusId','motherTongue','aboutMe','birthDate','Disability','bloodGroup','complexion','bodyType','childStatus'],
    'educationcareer'     => ['educationtype','educationmedium','faculty','degree','areyouworking','occupationtype','companyname','designation','workingwith','annualincome','businessname'],
    'user_astrologic'     => ['manglik','birthtime','birthcity'],
    'user_family'         => ['familytype','familybackground','fatherstatus','fathername','fathereducation','fatheroccupation','motherstatus','mothercaste','mothereducation','motheroccupation','familyorigin'],
    'user_lifestyle'      => ['smoketype','diet','drinks','drinktype','smoke'],
    'user_partner'        => ['minage','maxage','minheight','maxheight','maritalstatus','profilewithchild','familytype','religion','caste','mothertoungue','herscopeblief','manglik','country','state','city','qualification','educationmedium','proffession','workingwith','annualincome','diet','smokeaccept','drinkaccept','disabilityaccept','complexion','bodytype','otherexpectation'],
];

// Secondary whitelist check (belt-and-suspenders)
if (!isset($allowedTableColumns[$table]) || !in_array($field, $allowedTableColumns[$table], true)) {
    http_response_code(422);
    echo json_encode(['success' => false, 'message' => "Field '$field' is not allowed in table '$table'"]);
    exit;
}

// ── Perform update ────────────────────────────────────────────────────────────
try {
    if ($table === 'users') {
        // Simple UPDATE – row always exists for users table.
        // Column name comes from the whitelist above, not from user input.
        $sql  = 'UPDATE users SET `' . $field . '` = ? WHERE id = ?';
        $stmt = $pdo->prepare($sql);
        $stmt->execute([$value, $userId]);
    } else {
        // Tables keyed by userid – use UPSERT so missing rows are created.
        // Both table and column names are sourced exclusively from the whitelist.
        $sql  = 'INSERT INTO `' . $table . '` (userid, `' . $field . '`) VALUES (?, ?) '
              . 'ON DUPLICATE KEY UPDATE `' . $field . '` = VALUES(`' . $field . '`)';
        $stmt = $pdo->prepare($sql);
        $stmt->execute([$userId, $value]);
    }

    echo json_encode(['success' => true, 'message' => 'Profile updated successfully']);

} catch (PDOException $e) {
    error_log('update_user_profile error: ' . $e->getMessage());
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Server error']);
}
