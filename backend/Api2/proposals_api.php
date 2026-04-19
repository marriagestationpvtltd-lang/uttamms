<?php
/**
 * proposals_api.php
 *
 * Fetch proposals for the current user.
 *
 * GET params:
 *   user_id  (int)    – ID of the logged-in user
 *   type     (string) – "received" | "sent" | "history"
 *                       "history" returns both accepted and rejected proposals.
 */

ini_set('display_errors', 0);
ini_set('log_errors', 1);
error_reporting(E_ALL);

header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

require_once __DIR__ . '/db_config.php';

// --------------------------------------------------------------------------
// Input validation
// --------------------------------------------------------------------------

if (!isset($_GET['user_id'], $_GET['type'])) {
    echo json_encode(['status' => 'error', 'message' => 'Missing parameters: user_id and type are required']);
    exit;
}

$user_id = (int) $_GET['user_id'];
$type    = $_GET['type'];

if ($user_id <= 0) {
    echo json_encode(['status' => 'error', 'message' => 'Invalid user_id']);
    exit;
}

$validTypes = ['received', 'sent', 'history'];
if (!in_array($type, $validTypes, true)) {
    echo json_encode(['status' => 'error', 'message' => 'Invalid type. Must be one of: received, sent, history']);
    exit;
}

// --------------------------------------------------------------------------
// Query
// --------------------------------------------------------------------------
//
// Fetches the proposal rows plus:
//   • sender.privacy / receiver.privacy  → "privacy" in the response
//     (privacy setting of the OTHER party shown to the current user)
//   • photo_request_status               → "photo_request" in the response
//     (most-recent Photo-type proposal between the same two people,
//      via a correlated sub-query to avoid fan-out duplicate rows)

$sql = "
SELECT
    p.id,
    p.sender_id,
    p.receiver_id,
    p.request_type,
    p.status,
    p.created_at,

    -- Sender profile
    us.firstName       AS senderFirst,
    us.lastName        AS senderLast,
    us.profile_picture AS senderPic,
    us.status          AS senderVerified,
    us.privacy         AS senderPrivacy,

    -- Sender extra details
    ec_s.designation   AS senderDesignation,
    pa_s.city          AS senderCity,
    ms_s.name          AS senderMaritalStatus,

    -- Receiver profile
    ur.firstName       AS receiverFirst,
    ur.lastName        AS receiverLast,
    ur.profile_picture AS receiverPic,
    ur.status          AS receiverVerified,
    ur.privacy         AS receiverPrivacy,

    -- Receiver extra details
    ec_r.designation   AS receiverDesignation,
    pa_r.city          AS receiverCity,
    ms_r.name          AS receiverMaritalStatus,

    -- Most-recent Photo request between these two users
    (
        SELECT pr.status
        FROM   proposals pr
        WHERE  pr.request_type = 'Photo'
          AND  (
                   (pr.sender_id = p.sender_id   AND pr.receiver_id = p.receiver_id)
                OR (pr.sender_id = p.receiver_id AND pr.receiver_id = p.sender_id)
               )
        ORDER BY pr.id DESC
        LIMIT 1
    ) AS photo_request_status

FROM proposals p

JOIN users us ON us.id = p.sender_id
LEFT JOIN educationcareer    ec_s  ON ec_s.userid  = us.id
LEFT JOIN permanent_address  pa_s  ON pa_s.userid  = us.id
LEFT JOIN userpersonaldetail upd_s ON upd_s.userid = us.id
LEFT JOIN maritalstatus      ms_s  ON ms_s.id      = upd_s.maritalStatusId

JOIN users ur ON ur.id = p.receiver_id
LEFT JOIN educationcareer    ec_r  ON ec_r.userid  = ur.id
LEFT JOIN permanent_address  pa_r  ON pa_r.userid  = ur.id
LEFT JOIN userpersonaldetail upd_r ON upd_r.userid = ur.id
LEFT JOIN maritalstatus      ms_r  ON ms_r.id      = upd_r.maritalStatusId

WHERE
";

// Append the type-specific WHERE clause
if ($type === 'received') {
    $sql .= 'p.receiver_id = ? AND p.status = \'pending\' ';
    $params = [$user_id];
} elseif ($type === 'sent') {
    $sql .= 'p.sender_id = ? AND p.status = \'pending\' ';
    $params = [$user_id];
} else {
    // history – both accepted and rejected
    $sql .= '(p.sender_id = ? OR p.receiver_id = ?) AND p.status IN (\'accepted\', \'rejected\') ';
    $params = [$user_id, $user_id];
}

$sql .= 'ORDER BY p.created_at DESC';

// --------------------------------------------------------------------------
// Execute & build response
// --------------------------------------------------------------------------

try {
    $stmt = $pdo->prepare($sql);
    $stmt->execute($params);
    $rows = $stmt->fetchAll();

    $data = [];
    foreach ($rows as $row) {
        $isSender = ((int) $row['sender_id'] === $user_id);

        $data[] = [
            'proposalId'     => (string) $row['id'],
            'senderId'       => (string) $row['sender_id'],
            'receiverId'     => (string) $row['receiver_id'],
            'requestType'    => $row['request_type'],
            'status'         => $row['status'],

            'firstName'      => $isSender ? $row['receiverFirst']        : $row['senderFirst'],
            'lastName'       => $isSender ? $row['receiverLast']         : $row['senderLast'],
            'profilePicture' => $isSender ? $row['receiverPic']          : $row['senderPic'],
            'verified'       => ($isSender ? $row['receiverVerified']    : $row['senderVerified']) === 'verified',

            'occupation'     => $isSender ? ($row['receiverDesignation']    ?? '') : ($row['senderDesignation']    ?? ''),
            'city'           => $isSender ? ($row['receiverCity']           ?? '') : ($row['senderCity']           ?? ''),
            'maritalstatus'  => $isSender ? ($row['receiverMaritalStatus']  ?? '') : ($row['senderMaritalStatus']  ?? ''),

            // The "other" user's ID shown on the card
            'memberid'       => (string) ($isSender ? $row['receiver_id'] : $row['sender_id']),

            'type'           => $type,

            // Privacy setting of the OTHER user
            'privacy'        => $isSender ? ($row['receiverPrivacy'] ?? null) : ($row['senderPrivacy'] ?? null),

            // Status of the Photo request between these two users
            'photo_request'  => $row['photo_request_status'] ?? null,
        ];
    }

    echo json_encode([
        'status' => 'success',
        'count'  => count($data),
        'data'   => $data,
    ]);

} catch (PDOException $e) {
    error_log('proposals_api error: ' . $e->getMessage());
    echo json_encode(['status' => 'error', 'message' => 'Server error. Please try again.']);
}

