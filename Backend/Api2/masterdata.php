<?php
// get_master_data.php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

$resp = [
    'success' => false,
    'message' => '',
    'data' => null
];

try {
    $dbHost = 'localhost';
    $dbName = 'ms';
    $dbUser = 'ms';
    $dbPass = 'ms';
    $dbCharset = 'utf8mb4';

    if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
        http_response_code(405);
        $resp['message'] = 'Method not allowed — use GET';
        echo json_encode($resp, JSON_UNESCAPED_UNICODE);
        exit;
    }

    if (!isset($_GET['userid']) || trim($_GET['userid']) === '') {
        http_response_code(400);
        $resp['message'] = 'Missing required parameter: userid';
        echo json_encode($resp, JSON_UNESCAPED_UNICODE);
        exit;
    }

    $userid = $_GET['userid'];

    $dsn = "mysql:host={$dbHost};dbname={$dbName};charset={$dbCharset}";
    $options = [
        PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        PDO::ATTR_EMULATE_PREPARES   => false,
    ];
    $pdo = new PDO($dsn, $dbUser, $dbPass, $options);

    // Fetch user data.
    // docstatus is derived from user_documents.status (identity docs only, excluding
    // marital-status supporting documents).  Priority: approved > rejected > pending >
    // not_uploaded.  This matches the logic used by check_document_status.php so that
    // UserState.refresh() always receives a value the Flutter app understands.
    $sql = "
        SELECT
            u.id,
            u.email,
            u.firstName,
            u.lastName,
            u.profile_picture,
            u.usertype,
            u.pageno,
            u.createdDate,
            ms.name AS marital_status_name,
            COALESCE(
                (
                    SELECT
                        CASE
                            WHEN SUM(status = 'approved') > 0 THEN 'approved'
                            WHEN SUM(status = 'rejected') > 0 THEN 'rejected'
                            WHEN SUM(status = 'pending')  > 0 THEN 'pending'
                            ELSE 'not_uploaded'
                        END
                    FROM user_documents
                    WHERE userid = u.id
                      AND documenttype NOT IN (
                          'Death Certificate',
                          'Divorce Decree',
                          'Separation Document',
                          'Marriage Certificate',
                          'Court Order'
                      )
                ),
                'not_uploaded'
            ) AS docstatus
        FROM users u
        LEFT JOIN userpersonaldetail upd ON u.id = upd.userid
        LEFT JOIN maritalstatus ms ON upd.maritalStatusId = ms.id
        WHERE u.id = :userid
        LIMIT 1
    ";

    $stmt = $pdo->prepare($sql);
    $stmt->bindValue(':userid', $userid);
    $stmt->execute();
    $user = $stmt->fetch();

    if (!$user) {
        http_response_code(404);
        $resp['message'] = 'User not found';
        echo json_encode($resp, JSON_UNESCAPED_UNICODE);
        exit;
    }

    // Determine which marital documents are required based on marital status
    $maritalStatusName = $user['marital_status_name'];
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
        // 'Never Married' and other statuses don't require marital documents
    }

    // Check if user has approved identity document
    $hasApprovedIdentity = $user['docstatus'] === 'approved';

    // Check if all required marital documents are approved
    $allMaritalDocsApproved = true;
    if (!empty($requiredMaritalDocs)) {
        $placeholders = implode(',', array_fill(0, count($requiredMaritalDocs), '?'));
        $maritalDocStmt = $pdo->prepare("
            SELECT documenttype, status
            FROM user_documents
            WHERE userid = ? AND documenttype IN ($placeholders)
            ORDER BY created_at DESC
        ");
        $params = array_merge([$userid], $requiredMaritalDocs);
        $maritalDocStmt->execute($params);
        $maritalDocs = $maritalDocStmt->fetchAll();

        // Track which required docs are approved
        $approvedMaritalDocs = [];
        foreach ($maritalDocs as $doc) {
            if ($doc['status'] === 'approved' && !in_array($doc['documenttype'], $approvedMaritalDocs)) {
                $approvedMaritalDocs[] = $doc['documenttype'];
            }
        }

        // Check if all required marital documents are in the approved list
        foreach ($requiredMaritalDocs as $docType) {
            if (!in_array($docType, $approvedMaritalDocs)) {
                $allMaritalDocsApproved = false;
                break;
            }
        }
    }

    // User is verified only if they have approved identity AND all required marital docs
    $isVerified = $hasApprovedIdentity && $allMaritalDocsApproved;

    // Add is_verified to the user data
    $user['is_verified'] = $isVerified;

    $resp['success'] = true;
    $resp['message'] = 'User master data retrieved';
    $resp['data'] = $user;

    echo json_encode($resp, JSON_UNESCAPED_UNICODE);

} catch (PDOException $e) {
    http_response_code(500);
    $resp['message'] = 'Database error: ' . $e->getMessage();
    echo json_encode($resp, JSON_UNESCAPED_UNICODE);
    exit;
} catch (Throwable $t) {
    http_response_code(500);
    $resp['message'] = 'Server error: ' . $t->getMessage();
    echo json_encode($resp, JSON_UNESCAPED_UNICODE);
    exit;
}
