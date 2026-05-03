<?php
/**
 * delete_user.php
 *
 * Admin endpoint to create pending delete requests for one or more users.
 * Accounts are not removed immediately; final deletion must be completed from
 * the Delete Requests section via resolve_delete_request.php.
 *
 * POST body (JSON):
 *   user_ids (int[]) – required – array of user IDs
 *
 * Response:
 *   { "success": true,  "message": "N user(s) sent to Delete Requests" }
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
define('DB_USER', 'root');
define('DB_PASS', '');

// ── Input ─────────────────────────────────────────────────────────────────────
$input   = json_decode(file_get_contents('php://input'), true) ?? [];
$userIds = isset($input['user_ids']) && is_array($input['user_ids']) ? $input['user_ids'] : [];

if (empty($userIds)) {
    http_response_code(422);
    echo json_encode(['success' => false, 'message' => 'user_ids array is required and must not be empty']);
    exit;
}

// Sanitise IDs to integers and filter out invalid ones
$cleanIds = array_values(array_filter(array_map('intval', $userIds), fn($id) => $id > 0));

if (empty($cleanIds)) {
    http_response_code(422);
    echo json_encode(['success' => false, 'message' => 'No valid user IDs provided']);
    exit;
}

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

// ── Create pending delete requests ─────────────────────────────────────────────
try {
    $pdo->beginTransaction();

    // Accept any user that still exists in the table, regardless of isDelete flag.
    // isDelete=1 means soft-deleted but not yet fully cleaned up — we still want
    // to send them through the Delete Requests flow for permanent cleanup.
    $checkUserStmt = $pdo->prepare("SELECT id FROM users WHERE id = ?");
    $pendingStmt = $pdo->prepare("SELECT id FROM delete_request WHERE userid = ? AND status = 'pending' LIMIT 1");
    $insertStmt = $pdo->prepare(
        "INSERT INTO delete_request (userid, delete_reason, feedback, status, created_at)
         VALUES (?, ?, ?, 'pending', NOW())"
    );
    $deleteTokenStmt = $pdo->prepare("DELETE FROM user_tokens WHERE userid = ?");

    $hasRefreshTable = false;
    try {
        $hasRefreshTable = (bool)$pdo->query("SHOW TABLES LIKE 'userrefreshtoken'")->fetchColumn();
    } catch (Throwable $ignored) {
        $hasRefreshTable = false;
    }
    $deleteRefreshStmt = $hasRefreshTable
        ? $pdo->prepare("DELETE FROM userrefreshtoken WHERE userId = ?")
        : null;

    $createdCount = 0;
    $alreadyPendingCount = 0;
    $missingCount = 0;

    foreach ($cleanIds as $userId) {
        $checkUserStmt->execute([$userId]);
        if (!$checkUserStmt->fetch()) {
            $missingCount++;
            continue;
        }

        $pendingStmt->execute([$userId]);
        if ($pendingStmt->fetch()) {
            $alreadyPendingCount++;
            $deleteTokenStmt->execute([$userId]);
            if ($deleteRefreshStmt !== null) {
                $deleteRefreshStmt->execute([$userId]);
            }
            continue;
        }

        $insertStmt->execute([
            $userId,
            'Requested by admin from Members section',
            'Admin initiated this deletion flow. Complete review from Delete Requests section.',
        ]);
        $deleteTokenStmt->execute([$userId]);
        if ($deleteRefreshStmt !== null) {
            $deleteRefreshStmt->execute([$userId]);
        }
        $createdCount++;
    }

    $pdo->commit();

    if ($createdCount === 0 && $alreadyPendingCount === 0) {
        echo json_encode([
            'success' => false,
            'message' => 'No valid users were sent to Delete Requests',
            'created' => 0,
            'already_pending' => 0,
            'missing' => $missingCount,
        ]);
        exit;
    }

    $messageParts = [];
    if ($createdCount > 0) {
        $messageParts[] = "$createdCount user(s) sent to Delete Requests";
    }
    if ($alreadyPendingCount > 0) {
        $messageParts[] = "$alreadyPendingCount already pending";
    }
    if ($missingCount > 0) {
        $messageParts[] = "$missingCount skipped";
    }

    echo json_encode([
        'success'  => true,
        'message'  => implode(', ', $messageParts) . '. Complete the process from Delete Requests.',
        'created'  => $createdCount,
        'already_pending' => $alreadyPendingCount,
        'missing' => $missingCount,
    ]);

} catch (PDOException $e) {
    if ($pdo->inTransaction()) {
        $pdo->rollBack();
    }
    error_log('delete_user error: ' . $e->getMessage());
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Server error']);
}
