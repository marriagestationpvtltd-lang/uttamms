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
    // First, fetch the user's marital status to determine required documents
    $maritalStatusStmt = $pdo->prepare("
        SELECT ms.name as marital_status_name
        FROM users u
        LEFT JOIN userpersonaldetail upd ON u.id = upd.userid
        LEFT JOIN maritalstatus ms ON upd.maritalStatusId = ms.id
        WHERE u.id = :user_id
    ");
    $maritalStatusStmt->execute([':user_id' => $userId]);
    $maritalStatusRow = $maritalStatusStmt->fetch(PDO::FETCH_ASSOC);
    $maritalStatusName = $maritalStatusRow['marital_status_name'] ?? null;

    // Determine which marital document types are required based on marital status
    $requiredMaritalDocs = [];
    switch ($maritalStatusName) {
        case 'Widowed':
            $requiredMaritalDocs = ['Death Certificate'];
            break;
        case 'Divorced':
            $requiredMaritalDocs = ['Divorce Decree'];
            break;
        case 'Awaiting Divorce':
        case 'Waiting Divorce':
            $requiredMaritalDocs = ['Separation Document'];
            break;
        // 'Never Married' and 'Still Unmarried' don't require marital documents
    }

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
    $hasApprovedIdentity = false;

    // Track marital document statuses
    $maritalDocStatuses = [];
    foreach ($requiredMaritalDocs as $docType) {
        $maritalDocStatuses[$docType] = 'not_uploaded';
    }

    foreach ($rows as $row) {
        $documents[] = [
            'documenttype'  => $row['documenttype'],
            'status'        => $row['status'],
            'reject_reason' => $row['reject_reason'] ?? '',
        ];

        // Check if this is an identity document
        if (!in_array($row['documenttype'], $maritalDocTypes, true)) {
            if ($identityStatus === 'not_uploaded') {
                // First identity doc found – capture its status.
                $identityStatus = $row['status'];
            }
            if ($row['status'] === 'approved') {
                $hasApprovedIdentity = true;
            }
        }

        // Check if this is a required marital document
        if (in_array($row['documenttype'], $requiredMaritalDocs, true)) {
            // Update status for this marital document type (newest first due to ORDER BY)
            if ($maritalDocStatuses[$row['documenttype']] === 'not_uploaded') {
                $maritalDocStatuses[$row['documenttype']] = $row['status'];
            }
        }
    }

    // User is only verified if:
    // 1. They have at least one approved identity document, AND
    // 2. ALL required marital documents are approved
    $allMaritalDocsApproved = true;
    foreach ($requiredMaritalDocs as $docType) {
        if ($maritalDocStatuses[$docType] !== 'approved') {
            $allMaritalDocsApproved = false;
            break;
        }
    }

    $isVerified = $hasApprovedIdentity && $allMaritalDocsApproved;

    echo json_encode([
        'success'         => true,
        'documents'       => $documents,
        'identity_status' => $identityStatus,
        'is_verified'     => $isVerified,
        'marital_status'  => $maritalStatusName,
        'required_marital_documents' => $requiredMaritalDocs,
    ]);

} catch (PDOException $e) {
    echo json_encode(['success' => false, 'message' => 'Database error']);
}
?>