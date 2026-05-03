<?php
/**
 * user_search.php  (admin)
 *
 * Quick user lookup for admin panel — e.g. to find a target user ID
 * when uploading reels/stories on behalf of a user.
 *
 * GET params:
 *   q      (string) – search by firstName, lastName, or email (min 2 chars)
 *   limit  (int)    – max results, default 15, max 50
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

require_once __DIR__ . '/../Api2/db_config.php';
require_once __DIR__ . '/auth.php';

$q     = trim((string)($_GET['q'] ?? ''));
$limit = min(50, max(1, (int)($_GET['limit'] ?? 15)));

if (mb_strlen($q) < 2) {
    http_response_code(422);
    echo json_encode(['success' => false, 'message' => 'Query must be at least 2 characters']);
    exit;
}

$like = '%' . $q . '%';

$stmt = $pdo->prepare(
    "SELECT id,
            TRIM(CONCAT_WS(' ', firstName, middleName, lastName)) AS display_name,
            email
     FROM users
     WHERE isDisable IS NULL OR isDisable = 0
       AND (
           firstName  LIKE ?
        OR lastName   LIKE ?
        OR middleName LIKE ?
        OR email      LIKE ?
       )
     ORDER BY firstName, lastName
     LIMIT ?"
);
$stmt->execute([$like, $like, $like, $like, $limit]);
$rows = $stmt->fetchAll();

echo json_encode([
    'success' => true,
    'users'   => array_map(fn($r) => [
        'id'           => (int)$r['id'],
        'display_name' => $r['display_name'] ?: ('User #' . $r['id']),
        'email'        => $r['email'] ?? '',
    ], $rows),
]);
