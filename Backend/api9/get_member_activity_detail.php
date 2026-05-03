<?php
/**
 * get_member_activity_detail.php
 *
 * Returns paginated per-section activity details for a member.
 *
 * GET parameters:
 *   userid  (int)    – required – member whose activity to show
 *   section (string) – required – one of:
 *                        requests_sent | requests_received |
 *                        chats | calls | likes | profile_views | logins
 *   page    (int)    – default 1
 *   limit   (int)    – default 30, max 100
 *
 * Response:
 *   { "success": true, "section": "...", "total": N, "page": 1,
 *     "total_pages": M, "items": [ { ... } ] }
 *
 * Each item always contains: id, other_user_id, other_user_name, date, description
 * Plus section-specific fields:
 *   requests_*  → request_type (Photo|Profile|Chat), status
 *   calls       → call_type (made|received)
 *   likes       → like_action (sent|removed)
 *   profile_views → viewer_id, viewer_name
 */

ini_set('display_errors', 0);
ini_set('log_errors', 1);
error_reporting(E_ALL);

header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }
if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    http_response_code(405);
    echo json_encode(['success' => false, 'message' => 'Method not allowed']);
    exit;
}

// ── DB ────────────────────────────────────────────────────────────────────────
try {
    $pdo = new PDO('mysql:host=localhost;dbname=ms;charset=utf8mb4', 'root', '', [
        PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        PDO::ATTR_EMULATE_PREPARES   => false,
    ]);
} catch (PDOException $e) {
    http_response_code(503);
    echo json_encode(['success' => false, 'message' => 'Database connection failed']);
    exit;
}

// ── Input ─────────────────────────────────────────────────────────────────────
$userId  = isset($_GET['userid'])  ? (int) $_GET['userid']  : 0;
$section = isset($_GET['section']) ? trim($_GET['section'])  : '';
$page    = max(1, (int) ($_GET['page']  ?? 1));
$limit   = min(100, max(1, (int) ($_GET['limit'] ?? 30)));
$offset  = ($page - 1) * $limit;

$validSections = [
    'requests_sent', 'requests_received',
    'chats', 'calls', 'likes', 'profile_views', 'logins',
];

if ($userId <= 0 || !in_array($section, $validSections, true)) {
    http_response_code(422);
    echo json_encode([
        'success' => false,
        'message' => 'userid and a valid section are required. Valid sections: ' . implode(', ', $validSections),
    ]);
    exit;
}

// ── Section queries ───────────────────────────────────────────────────────────
try {
    $items = [];
    $total = 0;

    switch ($section) {

        // ── Requests sent by this user ─────────────────────────────────────
        case 'requests_sent':
            $countStmt = $pdo->prepare("
                SELECT COUNT(*)
                FROM proposals p
                WHERE p.sender_id = ?
            ");
            $countStmt->execute([$userId]);
            $total = (int) $countStmt->fetchColumn();

            $stmt = $pdo->prepare("
                SELECT
                    p.id,
                    p.receiver_id                                   AS other_user_id,
                    CONCAT_WS(' ', u.firstName, u.lastName)         AS other_user_name,
                    p.request_type,
                    p.status,
                    p.created_at                                    AS date,
                    CONCAT(p.request_type, ' request → ',
                           u.firstName, ' ', u.lastName,
                           ' (', p.status, ')')                     AS description
                FROM proposals p
                LEFT JOIN users u ON u.id = p.receiver_id
                WHERE p.sender_id = ?
                ORDER BY p.created_at DESC
                LIMIT ? OFFSET ?
            ");
            $stmt->execute([$userId, $limit, $offset]);
            $items = $stmt->fetchAll();
            break;

        // ── Requests received by this user ────────────────────────────────
        case 'requests_received':
            $countStmt = $pdo->prepare("
                SELECT COUNT(*) FROM proposals p WHERE p.receiver_id = ?
            ");
            $countStmt->execute([$userId]);
            $total = (int) $countStmt->fetchColumn();

            $stmt = $pdo->prepare("
                SELECT
                    p.id,
                    p.sender_id                                     AS other_user_id,
                    CONCAT_WS(' ', u.firstName, u.lastName)         AS other_user_name,
                    p.request_type,
                    p.status,
                    p.created_at                                    AS date,
                    CONCAT(u.firstName, ' ', u.lastName,
                           ' sent ', p.request_type, ' request',
                           ' (', p.status, ')')                     AS description
                FROM proposals p
                LEFT JOIN users u ON u.id = p.sender_id
                WHERE p.receiver_id = ?
                ORDER BY p.created_at DESC
                LIMIT ? OFFSET ?
            ");
            $stmt->execute([$userId, $limit, $offset]);
            $items = $stmt->fetchAll();
            break;

        // ── Chat messages sent or received ────────────────────────────────
        case 'chats':
            $countStmt = $pdo->prepare("
                SELECT COUNT(*) FROM user_activities
                WHERE user_id = ? AND activity_type = 'message_sent'
            ");
            $countStmt->execute([$userId]);
            $total = (int) $countStmt->fetchColumn();

            $stmt = $pdo->prepare("
                SELECT
                    ua.id,
                    ua.target_id                                    AS other_user_id,
                    COALESCE(ua.target_name,
                             CONCAT_WS(' ', u2.firstName, u2.lastName)) AS other_user_name,
                    'message_sent'                                  AS activity_type,
                    ua.description,
                    ua.created_at                                   AS date
                FROM user_activities ua
                LEFT JOIN users u2 ON u2.id = ua.target_id
                WHERE ua.user_id = ? AND ua.activity_type = 'message_sent'
                ORDER BY ua.created_at DESC
                LIMIT ? OFFSET ?
            ");
            $stmt->execute([$userId, $limit, $offset]);
            $items = $stmt->fetchAll();
            break;

        // ── Calls made and received ───────────────────────────────────────
        case 'calls':
            $countStmt = $pdo->prepare("
                SELECT COUNT(*) FROM user_activities
                WHERE user_id = ? AND activity_type IN ('call_made','call_received')
            ");
            $countStmt->execute([$userId]);
            $total = (int) $countStmt->fetchColumn();

            $stmt = $pdo->prepare("
                SELECT
                    ua.id,
                    ua.target_id                                    AS other_user_id,
                    COALESCE(ua.target_name,
                             CONCAT_WS(' ', u2.firstName, u2.lastName)) AS other_user_name,
                    ua.activity_type                                AS call_type,
                    ua.description,
                    ua.created_at                                   AS date
                FROM user_activities ua
                LEFT JOIN users u2 ON u2.id = ua.target_id
                WHERE ua.user_id = ? AND ua.activity_type IN ('call_made','call_received')
                ORDER BY ua.created_at DESC
                LIMIT ? OFFSET ?
            ");
            $stmt->execute([$userId, $limit, $offset]);
            $items = $stmt->fetchAll();
            break;

        // ── Likes sent ────────────────────────────────────────────────────
        case 'likes':
            $countStmt = $pdo->prepare("
                SELECT COUNT(*) FROM user_activities
                WHERE user_id = ? AND activity_type IN ('like_sent','like_removed')
            ");
            $countStmt->execute([$userId]);
            $total = (int) $countStmt->fetchColumn();

            $stmt = $pdo->prepare("
                SELECT
                    ua.id,
                    ua.target_id                                    AS other_user_id,
                    COALESCE(ua.target_name,
                             CONCAT_WS(' ', u2.firstName, u2.lastName)) AS other_user_name,
                    ua.activity_type                                AS like_action,
                    ua.description,
                    ua.created_at                                   AS date
                FROM user_activities ua
                LEFT JOIN users u2 ON u2.id = ua.target_id
                WHERE ua.user_id = ? AND ua.activity_type IN ('like_sent','like_removed')
                ORDER BY ua.created_at DESC
                LIMIT ? OFFSET ?
            ");
            $stmt->execute([$userId, $limit, $offset]);
            $items = $stmt->fetchAll();
            break;

        // ── Profile views (who viewed this user) ──────────────────────────
        case 'profile_views':
            $countStmt = $pdo->prepare("
                SELECT COUNT(*) FROM user_activities
                WHERE target_id = ? AND activity_type IN ('profile_view','profile_viewed','profile_viewed')
            ");
            $countStmt->execute([$userId]);
            $total = (int) $countStmt->fetchColumn();

            $stmt = $pdo->prepare("
                SELECT
                    ua.id,
                    ua.user_id                                      AS other_user_id,
                    COALESCE(ua.user_name,
                             CONCAT_WS(' ', u.firstName, u.lastName)) AS other_user_name,
                    ua.activity_type,
                    ua.description,
                    ua.created_at                                   AS date
                FROM user_activities ua
                LEFT JOIN users u ON u.id = ua.user_id
                WHERE ua.target_id = ? AND ua.activity_type IN ('profile_view','profile_viewed')
                ORDER BY ua.created_at DESC
                LIMIT ? OFFSET ?
            ");
            $stmt->execute([$userId, $limit, $offset]);
            $items = $stmt->fetchAll();
            break;

        // ── Logins ────────────────────────────────────────────────────────
        case 'logins':
            $countStmt = $pdo->prepare("
                SELECT COUNT(*) FROM user_activities
                WHERE user_id = ? AND activity_type = 'login'
            ");
            $countStmt->execute([$userId]);
            $total = (int) $countStmt->fetchColumn();

            $stmt = $pdo->prepare("
                SELECT
                    ua.id,
                    NULL                                            AS other_user_id,
                    NULL                                            AS other_user_name,
                    'login'                                         AS activity_type,
                    COALESCE(ua.description, 'Login')              AS description,
                    ua.created_at                                   AS date
                FROM user_activities ua
                WHERE ua.user_id = ? AND ua.activity_type = 'login'
                ORDER BY ua.created_at DESC
                LIMIT ? OFFSET ?
            ");
            $stmt->execute([$userId, $limit, $offset]);
            $items = $stmt->fetchAll();
            break;
    }

    // Normalise types
    foreach ($items as &$row) {
        $row['id']            = (int) ($row['id'] ?? 0);
        $row['other_user_id'] = isset($row['other_user_id']) && $row['other_user_id'] !== null
                                    ? (int) $row['other_user_id'] : null;
    }
    unset($row);

    $totalPages = $total > 0 ? (int) ceil($total / $limit) : 1;

    echo json_encode([
        'success'     => true,
        'section'     => $section,
        'total'       => $total,
        'page'        => $page,
        'limit'       => $limit,
        'total_pages' => $totalPages,
        'items'       => $items,
    ]);

} catch (PDOException $e) {
    error_log('get_member_activity_detail error: ' . $e->getMessage());
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Server error']);
}
