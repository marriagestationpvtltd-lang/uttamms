<?php
/**
 * Shared helpers for blocking access when an account has a pending
 * deletion request.
 */

if (!function_exists('isUserPendingDeletionPdo')) {
    function isUserPendingDeletionPdo(PDO $pdo, int $userId): bool
    {
        if ($userId <= 0) {
            return false;
        }

        $stmt = $pdo->prepare(
            "SELECT 1 FROM delete_request WHERE userid = ? AND status = 'pending' LIMIT 1"
        );
        $stmt->execute([$userId]);
        return (bool)$stmt->fetchColumn();
    }
}

if (!function_exists('isUserPendingDeletionMysqli')) {
    function isUserPendingDeletionMysqli(mysqli $conn, int $userId): bool
    {
        if ($userId <= 0) {
            return false;
        }

        $stmt = $conn->prepare(
            "SELECT 1 FROM delete_request WHERE userid = ? AND status = 'pending' LIMIT 1"
        );
        if (!$stmt) {
            return false;
        }
        $stmt->bind_param('i', $userId);
        $stmt->execute();
        $result = $stmt->get_result();
        $isPending = $result && $result->num_rows > 0;
        $stmt->close();
        return $isPending;
    }
}

if (!function_exists('deletionPendingResponse')) {
    function deletionPendingResponse(string $message = 'Account deletion request is pending'): array
    {
        return [
            'success' => false,
            'status' => 'error',
            'message' => $message,
            'error_code' => 'ACCOUNT_DELETION_PENDING',
        ];
    }
}
