<?php
/**
 * get_admin_call_history.php
 *
 * Admin-only endpoint: returns a paginated, filterable list of all calls
 * stored in the call_history table (managed by the Node.js socket server).
 *
 * GET parameters:
 *   page      (int)    – page number, default 1
 *   limit     (int)    – records per page, default 50, max 100
 *   search    (string) – partial match on caller_name or recipient_name
 *   call_type (string) – 'audio', 'video', or 'group'
 *   status    (string) – 'completed' | 'missed' | 'declined' | 'cancelled' | 'ended' | 'rejected'
 *   date_from (string) – YYYY-MM-DD
 *   date_to   (string) – YYYY-MM-DD
 *
 * Response (JSON):
 *   {
 *     "success":     true,
 *     "calls":       [ { callId, roomId, callerId, callerName, callerImage,
 *                         recipientId, recipientName, recipientImage,
 *                         callType, participants, startTime, endTime, duration,
 *                         status, initiatedBy, endedBy, recordingUrl } ],
 *     "total":       42,
 *     "page":        1,
 *     "limit":       50,
 *     "total_pages": 1
 *   }
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

// ── DB connection (same credentials as api9 / socket server) ─────────────────
define('DB_HOST', 'localhost');
define('DB_NAME', 'ms');
define('DB_USER', 'ms');
define('DB_PASS', 'ms');

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

// ── Input ─────────────────────────────────────────────────────────────────────
$page     = max(1, (int) ($_GET['page']  ?? 1));
$limit    = min(100, max(1, (int) ($_GET['limit'] ?? 50)));
$offset   = ($page - 1) * $limit;

$search   = isset($_GET['search'])    && $_GET['search']    !== '' ? trim($_GET['search'])    : null;
$callType = isset($_GET['call_type']) && $_GET['call_type'] !== '' ? trim($_GET['call_type']) : null;
$status   = isset($_GET['status'])    && $_GET['status']    !== '' ? trim($_GET['status'])    : null;
$dateFrom = isset($_GET['date_from']) && $_GET['date_from'] !== '' ? trim($_GET['date_from']) : null;
$dateTo   = isset($_GET['date_to'])   && $_GET['date_to']   !== '' ? trim($_GET['date_to'])   : null;

// Validate enums
$allowedTypes    = ['audio', 'video', 'group'];
$allowedStatuses = ['completed', 'missed', 'declined', 'cancelled', 'ended', 'rejected'];
if ($callType !== null && !in_array($callType, $allowedTypes, true))    $callType = null;
if ($status   !== null && !in_array($status,   $allowedStatuses, true)) $status   = null;

// ── WHERE clause ──────────────────────────────────────────────────────────────
$where  = [];
$params = [];

if ($search !== null) {
    $like     = '%' . $search . '%';
    $where[]  = '(caller_name LIKE ? OR recipient_name LIKE ? OR caller_id = ? OR recipient_id = ?)';
    $params[] = $like;
    $params[] = $like;
    $params[] = $search;
    $params[] = $search;
}
if ($callType !== null) { $where[] = 'call_type = ?'; $params[] = $callType; }
if ($status   !== null) { $where[] = 'status = ?';    $params[] = $status;   }
if ($dateFrom !== null) { $where[] = 'DATE(start_time) >= ?'; $params[] = $dateFrom; }
if ($dateTo   !== null) { $where[] = 'DATE(start_time) <= ?'; $params[] = $dateTo;   }

$whereSql = $where ? ('WHERE ' . implode(' AND ', $where)) : '';

// ── Count ─────────────────────────────────────────────────────────────────────
try {
    $countStmt = $pdo->prepare("SELECT COUNT(*) AS total FROM call_history $whereSql");
    $countStmt->execute($params);
    $total = (int) $countStmt->fetchColumn();
} catch (PDOException $e) {
    error_log('get_admin_call_history count error: ' . $e->getMessage());
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Server error']);
    exit;
}

// ── Fetch ─────────────────────────────────────────────────────────────────────
try {
    $dataParams   = $params;
    $dataParams[] = $limit;
    $dataParams[] = $offset;

    $dataStmt = $pdo->prepare("
        SELECT call_id, room_id, caller_id, caller_name, caller_image,
               recipient_id, recipient_name, recipient_image,
               call_type, participants, start_time, end_time, duration,
               status, initiated_by, ended_by, recording_url
          FROM call_history
         $whereSql
         ORDER BY start_time DESC
         LIMIT ? OFFSET ?
    ");
    $dataStmt->execute($dataParams);
    $rows = $dataStmt->fetchAll();

    $calls = [];
    foreach ($rows as $r) {
        // Decode participants JSON array; fall back to empty array on error.
        $participantsRaw = $r['participants'] ?? '[]';
        $participants = [];
        if ($participantsRaw !== null && $participantsRaw !== '') {
            $decoded = json_decode($participantsRaw, true);
            $participants = is_array($decoded) ? $decoded : [];
        }

        $calls[] = [
            'callId'        => $r['call_id'],
            'roomId'        => $r['room_id']        ?? null,
            'callerId'      => $r['caller_id'],
            'callerName'    => $r['caller_name']     ?? '',
            'callerImage'   => $r['caller_image']    ?? '',
            'recipientId'   => $r['recipient_id'],
            'recipientName' => $r['recipient_name']  ?? '',
            'recipientImage'=> $r['recipient_image'] ?? '',
            'callType'      => $r['call_type'],
            'participants'  => $participants,
            'startTime'     => $r['start_time'],
            'endTime'       => $r['end_time'],
            'duration'      => (int) $r['duration'],
            'status'        => $r['status'],
            'initiatedBy'   => $r['initiated_by'],
            'endedBy'       => $r['ended_by']        ?? null,
            'recordingUrl'  => $r['recording_url']   ?? null,
        ];
    }
} catch (PDOException $e) {
    error_log('get_admin_call_history fetch error: ' . $e->getMessage());
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Server error']);
    exit;
}

// ── Response ──────────────────────────────────────────────────────────────────
$totalPages = $total > 0 ? (int) ceil($total / $limit) : 1;

echo json_encode([
    'success'     => true,
    'calls'       => $calls,
    'total'       => $total,
    'page'        => $page,
    'limit'       => $limit,
    'total_pages' => $totalPages,
]);
