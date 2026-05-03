<?php
/**
 * send_delete_request.php
 *
 * Creates a PENDING account-deletion request.
 * The account is NOT deleted immediately — it is hidden from other users and
 * blocked from logging in until an admin approves (permanent deletion) or
 * rejects (restore) the request.
 *
 * POST body (form-data or JSON):
 *   userid        int    – required
 *   delete_reason string – required
 *   feedback      string – optional
 */
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

ini_set('display_errors', 0);
ini_set('log_errors', 1);

try {
    $pdo = new PDO("mysql:host=localhost;dbname=ms;charset=utf8mb4", "root", "",
        [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);

    // Accept both JSON and form-data
    $raw = file_get_contents('php://input');
    $json = json_decode($raw, true);
    $data = is_array($json) ? $json : $_POST;

    $userid        = intval($data['userid'] ?? 0);
    $delete_reason = trim($data['delete_reason'] ?? '');
    $feedback      = trim($data['feedback'] ?? '');

    if ($userid <= 0) {
        http_response_code(422);
        echo json_encode(["status" => "error", "message" => "Invalid user ID"]);
        exit;
    }
    if ($delete_reason === '') {
        http_response_code(422);
        echo json_encode(["status" => "error", "message" => "Delete reason is required"]);
        exit;
    }

    // Check user exists
    $chk = $pdo->prepare("SELECT id FROM users WHERE id = ? LIMIT 1");
    $chk->execute([$userid]);
    if (!$chk->fetch()) {
        http_response_code(404);
        echo json_encode(["status" => "error", "message" => "User not found"]);
        exit;
    }

    // Check for existing pending request
    $existing = $pdo->prepare(
        "SELECT id FROM delete_request WHERE userid = ? AND status = 'pending' LIMIT 1");
    $existing->execute([$userid]);
    if ($existing->fetch()) {
        // Already has a pending request — still log out the user
        $pdo->prepare("DELETE FROM user_tokens WHERE userid = ?")->execute([$userid]);
        echo json_encode([
            "status"  => "success",
            "message" => "Your account deletion request is already pending admin review."
        ]);
        exit;
    }

    // Insert pending delete request
    $ins = $pdo->prepare(
        "INSERT INTO delete_request (userid, delete_reason, feedback, status, created_at)
         VALUES (?, ?, ?, 'pending', NOW())"
    );
    $ins->execute([$userid, $delete_reason, $feedback]);

    // Invalidate all auth tokens so the user is immediately logged out everywhere
    $pdo->prepare("DELETE FROM user_tokens WHERE userid = ?")->execute([$userid]);
    // Also invalidate refresh tokens if the table exists
    $refreshTableExists = $pdo->query("SHOW TABLES LIKE 'userrefreshtoken'")->fetchColumn();
    if ($refreshTableExists) {
        $pdo->prepare("DELETE FROM userrefreshtoken WHERE userId = ?")->execute([$userid]);
    }

    echo json_encode([
        "status"  => "success",
        "message" => "Your account deletion request has been submitted and is pending admin approval. You have been logged out."
    ]);
} catch (Throwable $e) {
    error_log('send_delete_request.php error: ' . $e->getMessage());
    http_response_code(500);
    echo json_encode([
        "status" => "error",
        "message" => "Server error. Please try again later."
    ]);
}