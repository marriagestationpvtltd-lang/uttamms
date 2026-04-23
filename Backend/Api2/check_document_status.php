<?php
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');

$host     = 'localhost';
$dbname   = 'ms';
$username = 'ms';
$password = 'ms';

try {
    $pdo = new PDO("mysql:host=$host;dbname=$dbname;charset=utf8mb4", $username, $password);
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
} catch (PDOException $e) {
    echo json_encode(['success' => false, 'message' => 'Database connection failed']);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    echo json_encode(['success' => false, 'message' => 'Invalid request method']);
    exit;
}

$input  = json_decode(file_get_contents('php://input'), true);
$userId = isset($input['user_id']) ? intval($input['user_id']) : null;

if (!$userId) {
    echo json_encode(['success' => false, 'message' => 'User ID is required']);
    exit;
}

// Document types that belong to the marital-status KYC section.
// All other document types are treated as identity documents.
$maritalDocTypes = [
    'Death Certificate',
    'Marriage Certificate',
    'Divorce Decree',
    'Court Order',
    'Separation Document',
];

try {
    // Return one row per uploaded document for this user, including per-doc status.
    // Order newest-first so we pick up the latest upload for each type below.
    $stmt = $pdo->prepare("
        SELECT
            documenttype,
            status,
            reject_reason
        FROM user_documents
        WHERE userid = :user_id
        ORDER BY created_at DESC
    ");
    $stmt->execute([':user_id' => $userId]);
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

    $documents    = [];
    $identityStatus = 'not_uploaded'; // status of the most-recently uploaded identity doc
    $isVerified   = false;

    foreach ($rows as $row) {
        $documents[] = [
            'documenttype'  => $row['documenttype'],
            'status'        => $row['status'],
            'reject_reason' => $row['reject_reason'] ?? '',
        ];

        // Determine the effective identity-document status.
        // We use the first (newest) identity document we encounter because
        // the rows are ordered newest-first.
        if (!in_array($row['documenttype'], $maritalDocTypes, true)) {
            if ($identityStatus === 'not_uploaded') {
                // First identity doc found – capture its status.
                $identityStatus = $row['status'];
                if ($row['status'] === 'approved') {
                    $isVerified = true;
                }
            } elseif ($row['status'] === 'approved' && !$isVerified) {
                // An older approved document – the newest entry already set
                // $identityStatus, but this older approved doc means the user
                // is verified overall.
                $isVerified = true;
            }
        }
    }

    echo json_encode([
        'success'         => true,
        'documents'       => $documents,
        'identity_status' => $identityStatus,
        'is_verified'     => $isVerified,
    ]);

} catch (PDOException $e) {
    echo json_encode(['success' => false, 'message' => 'Database error']);
}
?>