<?php
/**
 * resolve_delete_request.php
 *
 * Admin endpoint: approve or reject an account-deletion request.
 *
 * POST body (JSON):
 *   request_id  int     – required – ID of the delete_request row
 *   action      string  – required – "approve" | "reject"
 *   admin_note  string  – optional – admin comment
 *
 * On "approve":
 *   - Permanently deletes all user data (same pattern as old send_delete_request.php)
 *   - Marks request status = 'approved'
 *
 * On "reject":
 *   - Marks request status = 'rejected'
 *   - User can log in again (tokens were cleared on request submission;
 *     user must reset password or log in normally — no automatic token restore)
 */

ini_set('display_errors', 0);
ini_set('log_errors', 1);
error_reporting(E_ALL);

header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['success' => false, 'message' => 'Method not allowed']);
    exit;
}

define('DB_HOST', 'localhost');
define('DB_NAME', 'ms');
define('DB_USER', 'root');
define('DB_PASS', '');

$input = json_decode(file_get_contents('php://input'), true) ?? [];

$requestId = intval($input['request_id'] ?? 0);
$action    = trim($input['action']     ?? '');
$adminNote = trim($input['admin_note'] ?? '');

if ($requestId <= 0) {
    http_response_code(422);
    echo json_encode(['success' => false, 'message' => 'request_id is required']);
    exit;
}

if (!in_array($action, ['approve', 'reject'], true)) {
    http_response_code(422);
    echo json_encode(['success' => false, 'message' => 'action must be "approve" or "reject"']);
    exit;
}

try {
    $pdo = new PDO(
        "mysql:host=" . DB_HOST . ";dbname=" . DB_NAME . ";charset=utf8mb4",
        DB_USER, DB_PASS,
        [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]
    );

    $tableExists = function (string $table) use ($pdo): bool {
        $q = $pdo->prepare("SELECT 1 FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = ? LIMIT 1");
        $q->execute([$table]);
        return (bool)$q->fetchColumn();
    };

    $columnExists = function (string $table, string $column) use ($pdo): bool {
        $q = $pdo->prepare("SELECT 1 FROM information_schema.columns WHERE table_schema = DATABASE() AND table_name = ? AND column_name = ? LIMIT 1");
        $q->execute([$table, $column]);
        return (bool)$q->fetchColumn();
    };

    $firstExistingColumn = function (string $table, array $candidates) use ($columnExists): ?string {
        foreach ($candidates as $candidate) {
            if ($columnExists($table, $candidate)) {
                return $candidate;
            }
        }
        return null;
    };

    $deleteByUserColumns = function (string $table, array $candidates, int $userId) use ($pdo, $tableExists, $columnExists): void {
        if (!$tableExists($table)) {
            return;
        }

        $existingColumns = [];
        foreach ($candidates as $candidate) {
            if ($columnExists($table, $candidate)) {
                $existingColumns[] = $candidate;
            }
        }

        if (empty($existingColumns)) {
            return;
        }

        $conditions = array_map(static fn(string $column): string => "`$column` = ?", $existingColumns);
        $sql = "DELETE FROM `$table` WHERE " . implode(' OR ', $conditions);
        $pdo->prepare($sql)->execute(array_fill(0, count($existingColumns), $userId));
    };

    $approvedStatusValue = 'approved';
    $statusMetaStmt = $pdo->query("SELECT COLUMN_TYPE FROM information_schema.columns WHERE table_schema = DATABASE() AND table_name = 'delete_request' AND column_name = 'status' LIMIT 1");
    $statusMeta = $statusMetaStmt ? $statusMetaStmt->fetch(PDO::FETCH_ASSOC) : null;
    $columnType = strtolower((string)($statusMeta['COLUMN_TYPE'] ?? ''));
    if (strpos($columnType, "'approved'") === false && strpos($columnType, "'accepted'") !== false) {
        $approvedStatusValue = 'accepted';
    }

    // Fetch the request
    $stmt = $pdo->prepare(
        "SELECT dr.*, u.firstName, u.email
         FROM delete_request dr
         JOIN users u ON u.id = dr.userid
         WHERE dr.id = ? LIMIT 1"
    );
    $stmt->execute([$requestId]);
    $req = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$req) {
        http_response_code(404);
        echo json_encode(['success' => false, 'message' => 'Delete request not found']);
        exit;
    }

    if ($req['status'] !== 'pending') {
        echo json_encode([
            'success' => false,
            'message' => "Request is already {$req['status']} and cannot be changed"
        ]);
        exit;
    }

    $userId = (int)$req['userid'];

    if ($action === 'approve') {
        // ── Permanently delete user data ─────────────────────────────────────
        $pdo->beginTransaction();

        $pdo->exec("SET FOREIGN_KEY_CHECKS = 0");

        // Archive to deletion_log first (if table/required columns exist)
        if ($tableExists('deletion_log')) {
            $deletionLogUserColumn = $firstExistingColumn('deletion_log', ['userid', 'userId']);
            $deletionLogReasonColumn = $firstExistingColumn('deletion_log', ['reason', 'delete_reason']);
            $deletionLogFeedbackColumn = $firstExistingColumn('deletion_log', ['feedback']);
            $deletionLogDateColumn = $firstExistingColumn('deletion_log', ['deleted_at', 'created_at']);

            if ($deletionLogUserColumn !== null && $deletionLogDateColumn !== null) {
                $columns = [$deletionLogUserColumn];
                $placeholders = ['?'];
                $values = [$userId];

                if ($deletionLogReasonColumn !== null) {
                    $columns[] = $deletionLogReasonColumn;
                    $placeholders[] = '?';
                    $values[] = $req['delete_reason'];
                }
                if ($deletionLogFeedbackColumn !== null) {
                    $columns[] = $deletionLogFeedbackColumn;
                    $placeholders[] = '?';
                    $values[] = $req['feedback'];
                }

                $columns[] = $deletionLogDateColumn;
                $placeholders[] = 'NOW()';

                $pdo->prepare(
                    "INSERT IGNORE INTO deletion_log (`" . implode('`, `', $columns) . "`) VALUES (" . implode(', ', $placeholders) . ")"
                )->execute($values);
            }
        }

        // Delete user-related rows
        $deleteOps = [
            ['userblock', ['userId', 'userid', 'userBlockId', 'blockRequestUserId']],
            ['user_tokens', ['userid', 'userId']],
            ['userrefreshtoken', ['userId', 'userid']],
            ['user_activities', ['userid', 'userId']],
            ['user_documents', ['userid', 'userId']],
            ['user_gallery', ['userid', 'userId']],
            ['userimagegallery', ['userid', 'userId']],
            ['user_package', ['userid', 'userId']],
            ['userpackage', ['userid', 'userId']],
            ['usernotifications', ['userid', 'userId']],
            ['user_notifications', ['userId', 'userid']],
            ['user_notification_settings', ['userid', 'userId']],
            ['user_online_status', ['userid', 'userId']],
            ['likes', ['sender_id', 'receiver_id']],
            ['proposals', ['sender_id', 'receiver_id']],
            ['userproposals', ['userid', 'userId', 'targetuserid', 'targetUserId', 'proposalUserId']],
            ['userfavourites', ['userid', 'userId', 'targetuserid', 'targetUserId', 'favUserId']],
            ['matches', ['user1id', 'user2id', 'user1Id', 'user2Id']],
            ['contact_request', ['sender_id', 'receiver_id', 'senderUserId', 'receiverUserId']],
            ['profile_views', ['viewer_id', 'viewed_id', 'viewProfileByUserId']],
            ['profile_view', ['viewer_id', 'viewed_id', 'viewProfileByUserId', 'userId']],
            ['userpersonaldetail', ['userid', 'userId']],
            ['permanent_address', ['userid', 'userId']],
            ['educationcareer', ['userid', 'userId']],
            ['user_lifestyle', ['userid', 'userId']],
            ['user_partner', ['userid', 'userId']],
            ['user_family', ['userid', 'userId']],
            ['user_astrologic', ['userid', 'userId']],
            ['userdevicedetail', ['userid', 'userId']],
        ];

        foreach ($deleteOps as [$table, $columns]) {
            $deleteByUserColumns($table, $columns, $userId);
        }

        // Mark the delete request as approved (keep for audit)
        $setParts = ["status = ?"];
        $setParams = [$approvedStatusValue];
        if ($columnExists('delete_request', 'reviewed_at')) {
            $setParts[] = "reviewed_at = NOW()";
        }
        if ($columnExists('delete_request', 'admin_note')) {
            $setParts[] = "admin_note = ?";
            $setParams[] = $adminNote;
        }
        $setParams[] = $requestId;
        $pdo->prepare(
            "UPDATE delete_request SET " . implode(', ', $setParts) . " WHERE id = ?"
        )->execute($setParams);

        // Finally delete the user record
        $pdo->prepare("DELETE FROM users WHERE id = ?")->execute([$userId]);

        $pdo->exec("SET FOREIGN_KEY_CHECKS = 1");
        $pdo->commit();

        echo json_encode([
            'success' => true,
            'message' => "Account for user #{$userId} has been permanently deleted."
        ]);

    } else {
        // ── Reject: just update status ───────────────────────────────────────
        $setParts = ["status = ?"];
        $setParams = ['rejected'];
        if ($columnExists('delete_request', 'reviewed_at')) {
            $setParts[] = "reviewed_at = NOW()";
        }
        if ($columnExists('delete_request', 'admin_note')) {
            $setParts[] = "admin_note = ?";
            $setParams[] = $adminNote;
        }
        $setParams[] = $requestId;
        $pdo->prepare(
            "UPDATE delete_request SET " . implode(', ', $setParts) . " WHERE id = ?"
        )->execute($setParams);

        echo json_encode([
            'success' => true,
            'message' => "Delete request rejected. The user account has been restored."
        ]);
    }

} catch (Throwable $e) {
    if (isset($pdo) && $pdo->inTransaction()) {
        try { $pdo->exec("SET FOREIGN_KEY_CHECKS = 1"); } catch (Throwable $ignored) {}
        $pdo->rollBack();
    }
    error_log('resolve_delete_request.php error: ' . $e->getMessage());
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Server error: ' . $e->getMessage()]);
}
