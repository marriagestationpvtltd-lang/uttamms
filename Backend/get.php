<?php
header('Content-Type: application/json');
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: GET, POST, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type, Authorization");

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    exit(0);
}

date_default_timezone_set('Asia/Kathmandu');
include 'db_connect.php';
$conn->query("SET time_zone = '+05:45'");

$base_url = "https://digitallami.com/Api2/";

// Admin user ID (excluded from list; used to build chat_room_id)
define('ADMIN_ID', 1);

// ── Paid usertype values ─────────────────────────────────────────────────────
$paidUsertypes = ['paid', 'premium', 'vip', 'gold', 'member', 'subscribed', 'active', 'pro', 'plus', 'elite'];

// ── Parameters ───────────────────────────────────────────────────────────────
$singleUserId = isset($_GET['userId']) ? intval($_GET['userId']) : 0;
$page         = max(1, intval($_GET['page']  ?? 1));
$limit        = max(1, min(100, intval($_GET['limit'] ?? 50)));
$offset       = ($page - 1) * $limit;
$search       = trim($_GET['search'] ?? '');

// ── Pre-compute opposite-gender counts (for match count field) ────────────────
// This replaces one per-user COUNT query with a single aggregation.
$genderCounts = ['Male' => 0, 'Female' => 0];
$gcStmt = $conn->prepare("SELECT gender, COUNT(*) AS cnt FROM users WHERE id != ? GROUP BY gender");
$adminId = ADMIN_ID;
$gcStmt->bind_param("i", $adminId);
$gcStmt->execute();
$gcRes = $gcStmt->get_result();
while ($r = $gcRes->fetch_assoc()) {
    $genderCounts[$r['gender']] = intval($r['cnt']);
}

// ── Build WHERE clause ────────────────────────────────────────────────────────
$whereParts = ["u.id != ?"];
$params     = [ADMIN_ID];
$types      = 'i';

if ($singleUserId > 0) {
    $whereParts[] = "u.id = ?";
    $params[]     = $singleUserId;
    $types       .= 'i';
} elseif ($search !== '') {
    $like          = '%' . $search . '%';
    $whereParts[]  = "(u.firstName LIKE ? OR u.lastName LIKE ? OR CONCAT(u.firstName,' ',u.lastName) LIKE ?)";
    $params        = array_merge($params, [$like, $like, $like]);
    $types        .= 'sss';
}

$whereSQL = 'WHERE ' . implode(' AND ', $whereParts);

// ── Count total matching rows (pagination meta) ───────────────────────────────
$countSQL  = "SELECT COUNT(*) AS total FROM users u $whereSQL";
$countStmt = $conn->prepare($countSQL);
if (!$countStmt) {
    echo json_encode(['status' => false, 'message' => 'Count query prepare failed: ' . $conn->error, 'data' => [], 'totalRecords' => 0]);
    exit;
}
if ($params) {
    $countStmt->bind_param($types, ...$params);
}
$countStmt->execute();
$totalRecords = intval($countStmt->get_result()->fetch_assoc()['total'] ?? 0);

// ── Detect whether the is_unsent column exists (added by the socket server) ───
$unsentCheck = $conn->query(
    "SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
     WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'chat_messages' AND COLUMN_NAME = 'is_unsent'
     LIMIT 1"
);
$hasUnsentCol = $unsentCheck && $unsentCheck->num_rows > 0;

// ── Main query — single round-trip, no N+1 ────────────────────────────────────
// chat_room_id between admin (id=1) and any user (id > 1) is always "1_<userId>"
// because string sort("1","N") = ["1","N"] for any N whose string > "1".
// We use this to query chat_messages with the idx_chat_room_time index.
$unsentFilter  = $hasUnsentCol ? 'AND  cm.is_unsent  = 0' : '';
$unsentFilter2 = $hasUnsentCol ? 'AND  cm2.is_unsent = 0' : '';
$unsentFilter3 = $hasUnsentCol ? 'AND  cm3.is_unsent = 0' : '';

$mainSQL = "
    SELECT
        u.id,
        u.firstName,
        u.lastName,
        u.gender,
        u.profile_picture,
        u.lastLogin,
        u.isOnline,
        u.usertype,
        u.isVerified,
        (
            SELECT cm.message
            FROM   chat_messages cm
            WHERE  cm.chat_room_id = CONCAT('1_', u.id)
              $unsentFilter
            ORDER  BY cm.created_at DESC
            LIMIT  1
        ) AS chat_message,
        (
            SELECT cm2.created_at
            FROM   chat_messages cm2
            WHERE  cm2.chat_room_id = CONCAT('1_', u.id)
              $unsentFilter2
            ORDER  BY cm2.created_at DESC
            LIMIT  1
        ) AS last_message_at,
        (
            SELECT cm3.sender_id
            FROM   chat_messages cm3
            WHERE  cm3.chat_room_id = CONCAT('1_', u.id)
              $unsentFilter3
            ORDER  BY cm3.created_at DESC
            LIMIT  1
        ) AS last_sender_id
    FROM  users u
    $whereSQL
    ORDER BY
        CASE WHEN u.isOnline = 1 THEN 0 ELSE 1 END ASC,
        last_message_at DESC,
        u.lastLogin DESC
";

// Append LIMIT/OFFSET only for list queries (not single-user lookup)
$listParams = $params;
$listTypes  = $types;
if ($singleUserId <= 0) {
    $mainSQL   .= " LIMIT ? OFFSET ?";
    $listParams = array_merge($listParams, [$limit, $offset]);
    $listTypes .= 'ii';
}

$stmt = $conn->prepare($mainSQL);
if (!$stmt) {
    echo json_encode(['status' => false, 'message' => 'Main query prepare failed: ' . $conn->error, 'data' => [], 'totalRecords' => 0]);
    exit;
}
if ($listParams) {
    $stmt->bind_param($listTypes, ...$listParams);
}
$stmt->execute();
$result = $stmt->get_result();
if (!$result) {
    echo json_encode(['status' => false, 'message' => 'Main query execute failed: ' . $stmt->error, 'data' => [], 'totalRecords' => 0]);
    exit;
}

// ── Build response ────────────────────────────────────────────────────────────
$responseData = [];
while ($user = $result->fetch_assoc()) {
    $userId = $user['id'];

    // Profile picture
    if (!empty($user['profile_picture'])) {
        $profile_picture = (strpos($user['profile_picture'], 'http') === 0)
            ? $user['profile_picture']
            : $base_url . $user['profile_picture'];
    } else {
        $profile_picture = $base_url . "default.png";
    }

    // Match count: number of opposite-gender users in the system
    $gender       = $user['gender'] ?? 'Male';
    $matchesCount = ($gender === 'Male')
        ? ($genderCounts['Female'] ?? 0)
        : ($genderCounts['Male']   ?? 0);

    // Paid status (from usertype column)
    $usertype = strtolower(trim($user['usertype'] ?? ''));
    $is_paid  = in_array($usertype, $paidUsertypes);

    // Online / last-seen
    $last_seen      = $user['lastLogin'] ?? null;
    $is_online      = false;
    $last_seen_text = '';
    if ($last_seen) {
        $diffMinutes = (time() - strtotime($last_seen)) / 60;
        if ($diffMinutes <= 10) {
            $is_online      = true;
            $last_seen_text = 'Online';
        } elseif ($diffMinutes < 60) {
            $last_seen_text = 'Last seen ' . intval($diffMinutes) . ' min ago';
        } elseif ($diffMinutes < 1440) {
            $last_seen_text = 'Last seen ' . intval($diffMinutes / 60) . ' hr ago';
        } else {
            $last_seen_text = 'Last seen ' . intval($diffMinutes / 1440) . ' day ago';
        }
    }

    // Format last_message_time as ISO-8601 UTC so Flutter can parse it reliably.
    $lastMsgAt = $user['last_message_at'] ?? null;
    $lastMsgTimeIso = null;
    if ($lastMsgAt) {
        // MySQL session is set to Asia/Kathmandu (+05:45); convert explicitly to UTC.
        $dt = new DateTime($lastMsgAt, new DateTimeZone('Asia/Kathmandu'));
        $dt->setTimezone(new DateTimeZone('UTC'));
        $lastMsgTimeIso = $dt->format('Y-m-d\TH:i:s\Z');
    }

    $responseData[] = [
        'id'                => (string)$userId,
        'name'              => trim(($user['firstName'] ?? '') . ' ' . ($user['lastName'] ?? '')),
        'gender'            => $gender,
        'usertype'          => $user['usertype'] ?? '',
        'profile_picture'   => $profile_picture,
        'chat_message'      => $user['chat_message'] ?? '',
        'last_message_time' => $lastMsgTimeIso,
        'last_sender_id'    => $user['last_sender_id'] !== null ? (string)$user['last_sender_id'] : null,
        'matches'           => $matchesCount,
        'last_seen'         => $last_seen,
        'last_seen_text'    => $last_seen_text,
        'is_paid'           => $is_paid,
        'is_online'         => $is_online,
        'is_verified'       => !empty($user['isVerified']),
    ];
}

echo json_encode([
    'status'       => true,
    'data'         => $responseData,
    'totalRecords' => $totalRecords,
    'page'         => $page,
    'limit'        => $limit,
], JSON_PRETTY_PRINT);

$conn->close();
?>