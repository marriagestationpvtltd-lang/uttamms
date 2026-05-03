<?php
/**
 * get_profile_field_options.php  (Api2 — all-fields version)
 *
 * Returns ALL dynamic dropdown option lists in one response so the Flutter
 * ProfileFieldOptionsService can populate its session cache in a single call.
 *
 * Response shape:
 *   {
 *     "status": "success",
 *     "data": {
 *       "annualincome":    ["No Income", "Below 1 Lakh", ...],
 *       "educationtype":   ["School", "Diploma", ...],
 *       "degree":          ["SEE/SLC", "+2 / Intermediate", ...],
 *       "faculty":         ["Science", "Management", ...],
 *       "educationmedium": ["English", "Nepali", ...],
 *       "occupationtype":  ["Private Job", "Government Job", ...],
 *       "workingwith":     ["Private Company", "Government Sector", ...]
 *     }
 *   }
 */

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

// ── Default (built-in) master data ──────────────────────────────────────────
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
    'educationtype'   => ['School', 'Diploma', 'Bachelor', 'Master', 'PhD'],
    'degree'          => ['SEE/SLC', '+2 / Intermediate', 'Bachelor', 'Master', 'PhD'],
    'faculty'         => ['Science', 'Management', 'Humanities', 'Education', 'Engineering', 'Medical', 'IT'],
    'educationmedium' => ['English', 'Nepali', 'Hindi', 'Other'],
    'occupationtype'  => ['Private Job', 'Government Job', 'Business', 'Self Employed', 'Professional', 'Student', 'Not Working'],
    'workingwith'     => ['Private Company', 'Government Sector', 'Own Business', 'NGO/INGO', 'Startup', 'Freelance', 'Other'],
];

$masterOptions = $defaultMaster;

// ── Attempt to load admin-customised values from DB ──────────────────────────
$conn = @new mysqli('localhost', 'root', '', 'ms');
if (!$conn->connect_error) {
    $conn->set_charset('utf8mb4');

    $stmt = $conn->prepare(
        'SELECT setting_value FROM app_settings WHERE setting_key = ? LIMIT 1'
    );
    if ($stmt) {
        $key = 'profile_dropdown_master_json';
        $stmt->bind_param('s', $key);
        $stmt->execute();
        $res = $stmt->get_result();
        $row = $res ? $res->fetch_assoc() : null;
        $stmt->close();

        if ($row && !empty($row['setting_value'])) {
            $decoded = json_decode((string)$row['setting_value'], true);
            if (is_array($decoded)) {
                foreach ($defaultMaster as $field => $fallback) {
                    $fromDb = [];
                    if (isset($decoded[$field]) && is_array($decoded[$field])) {
                        foreach ($decoded[$field] as $item) {
                            $text = trim((string)$item);
                            if ($text !== '') {
                                $fromDb[] = $text;
                            }
                        }
                        $fromDb = array_values(array_unique($fromDb));
                    }
                    $masterOptions[$field] = !empty($fromDb) ? $fromDb : $fallback;
                }
            }
        }
    }
    $conn->close();
}

// ── Return all fields ────────────────────────────────────────────────────────
echo json_encode([
    'status' => 'success',
    'data'   => $masterOptions,
], JSON_UNESCAPED_UNICODE);
