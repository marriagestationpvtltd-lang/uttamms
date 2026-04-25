<?php
header('Content-Type: application/json');

header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: GET, POST, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type, Authorization");

// ✅ Nepal timezone
date_default_timezone_set('Asia/Kathmandu');

include 'db_connect.php';

// ✅ Ensure MySQL also uses Nepal time
$conn->query("SET time_zone = '+05:45'");

// ✅ Base URL for images
$base_url = "https://digitallami.com/Api2/";

// ✅ Usertype values that indicate a paid subscription
$paidUsertypes = ['paid', 'premium', 'vip', 'gold', 'member', 'subscribed', 'active', 'pro', 'plus', 'elite'];

/* ----------------------------------------------------------
   STEP 1: Parse request parameters
---------------------------------------------------------- */

// Pagination
$page   = max(1, intval($_GET['page']  ?? 1));
$limit  = max(1, min(100, intval($_GET['limit'] ?? 30)));
$offset = ($page - 1) * $limit;

// Optional filters
$search = trim($_GET['search'] ?? '');
$userId = trim($_GET['userId'] ?? '');

/* ----------------------------------------------------------
   STEP 2: Build dynamic WHERE clause
---------------------------------------------------------- */

$whereParts  = ['u.id != 1'];
$bindTypes   = '';
$bindValues  = [];

if ($userId !== '') {
    // Single-user fetch (used by the sidebar for on-demand profile loads)
    $whereParts[]  = 'u.id = ?';
    $bindTypes    .= 'i';
    $bindValues[]  = intval($userId);
} elseif ($search !== '') {
    // Escape LIKE wildcard characters so the search is treated as a literal string
    $escapedSearch = str_replace(['\\', '%', '_'], ['\\\\', '\\%', '\\_'], $search);
    $whereParts[]  = "CONCAT(TRIM(u.firstName), ' ', TRIM(u.lastName)) LIKE ?";
    $bindTypes    .= 's';
    $bindValues[]  = '%' . $escapedSearch . '%';
}

$whereClause = 'WHERE ' . implode(' AND ', $whereParts);

/* ----------------------------------------------------------
   STEP 3: Count total matching records for pagination metadata
---------------------------------------------------------- */

$countSql  = "SELECT COUNT(*) AS total FROM users u $whereClause";
$countStmt = $conn->prepare($countSql);
if ($bindTypes !== '') {
    $countStmt->bind_param($bindTypes, ...$bindValues);
}
$countStmt->execute();
$totalRecords = intval($countStmt->get_result()->fetch_assoc()['total'] ?? 0);
$countStmt->close();

/* ----------------------------------------------------------
   STEP 3b: Pre-compute opposite-gender counts per gender value.

   Because "matches" is purely gender-based (count of users whose
   gender differs from the current user's), the value is identical
   for every user of the same gender.  Computing it once here and
   applying it in PHP removes the per-row correlated subquery
   entirely.
---------------------------------------------------------- */

$genderCountMap = [];
$gcStmt = $conn->query(
    "SELECT gender, COUNT(*) AS cnt FROM users WHERE id != 1 GROUP BY gender"
);
if ($gcStmt) {
    $genderRows = $gcStmt->fetch_all(MYSQLI_ASSOC);
    $totalByGender = [];
    foreach ($genderRows as $row) {
        $totalByGender[$row['gender']] = intval($row['cnt']);
    }
    $grandTotal = array_sum($totalByGender);
    foreach ($totalByGender as $g => $cnt) {
        // Opposite-gender count = total users – same-gender users
        $genderCountMap[$g] = $grandTotal - $cnt;
    }
}

/* ----------------------------------------------------------
   STEP 4: Fetch one page of users with a single SQL round-trip.

   Correlated subqueries replace the previous N+1 PHP loop:
     • latest chat message + type → chat_messages table (two subqueries
       share the same indexed column lookups, keeping scans per page
       to 2 × page_size indexed reads)

   This reduces database round-trips from  2N + 1  →  3
   (count + gender-counts + paginated data query), regardless of
   how many total users exist.
---------------------------------------------------------- */

$sql = "
    SELECT
        u.id,
        TRIM(CONCAT(TRIM(u.firstName), ' ', TRIM(u.lastName))) AS name,
        u.profile_picture,
        u.usertype,
        u.isVerified,
        u.gender,
        u.lastLogin,
        (
            SELECT cm.message
            FROM   chat_messages cm
            WHERE  cm.sender_id   = CAST(u.id AS CHAR)
                OR cm.receiver_id = CAST(u.id AS CHAR)
            ORDER  BY cm.created_at DESC
            LIMIT  1
        ) AS chat_message,
        (
            SELECT cm.message_type
            FROM   chat_messages cm
            WHERE  cm.sender_id   = CAST(u.id AS CHAR)
                OR cm.receiver_id = CAST(u.id AS CHAR)
            ORDER  BY cm.created_at DESC
            LIMIT  1
        ) AS chat_message_type
    FROM  users u
    $whereClause
    ORDER BY u.id DESC
    LIMIT ? OFFSET ?
";

// Append LIMIT / OFFSET bind params
$allTypes  = $bindTypes . 'ii';
$allValues = array_merge($bindValues, [$limit, $offset]);

$stmt = $conn->prepare($sql);
$stmt->bind_param($allTypes, ...$allValues);
$stmt->execute();
$result = $stmt->get_result();

/* ----------------------------------------------------------
   STEP 5: Build response array
---------------------------------------------------------- */

$responseData = [];

while ($user = $result->fetch_assoc()) {
    // ── Profile picture ───────────────────────────────────
    $pp = $user['profile_picture'] ?? '';
    if (!empty($pp)) {
        $profile_picture = (strpos($pp, 'http') === 0) ? $pp : $base_url . $pp;
    } else {
        $profile_picture = $base_url . 'default.png';
    }

    // ── Paid status ───────────────────────────────────────
    $usertype = strtolower(trim($user['usertype'] ?? ''));
    $is_paid  = in_array($usertype, $paidUsertypes);

    // ── Online / last-seen ────────────────────────────────
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

    // ── Assemble record ───────────────────────────────────
    $userGender   = $user['gender'] ?? '';
    $matchesCount = $genderCountMap[$userGender] ?? 0;

    $responseData[] = [
        'id'                => (string)$user['id'],
        'name'              => $user['name'],
        'usertype'          => $user['usertype'] ?? '',
        'profile_picture'   => $profile_picture,
        'chat_message'      => $user['chat_message']      ?? '',
        'chat_message_type' => $user['chat_message_type'] ?? null,
        'matches'           => $matchesCount,
        'last_seen'         => $last_seen,
        'last_seen_text'    => $last_seen_text,
        'is_paid'           => $is_paid,
        'is_online'         => $is_online,
        'is_verified'       => (bool)($user['isVerified'] ?? false),
    ];
}

$stmt->close();

/* ----------------------------------------------------------
   STEP 6: Return response
---------------------------------------------------------- */

echo json_encode([
    'status'       => true,
    'data'         => $responseData,
    'totalRecords' => $totalRecords,
    'page'         => $page,
    'limit'        => $limit,
], JSON_PRETTY_PRINT);

$conn->close();
?>