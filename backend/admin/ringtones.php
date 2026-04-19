<?php
/**
 * ringtones.php  (admin)
 *
 * Admin CRUD for system ringtones.
 *
 * GET  – list all ringtones (active only by default, pass ?all=1 for all)
 *
 * POST body (JSON or form-encoded) – add / update a ringtone record.
 *   (File upload is handled separately by upload_ringtone.php which returns
 *    a file_url; that URL is then POSTed here to create the record.)
 *   name       (string) – required
 *   file_url   (string) – required
 *   is_default (bool)   – optional, default false
 *   id         (int)    – optional; if provided, UPDATE instead of INSERT
 *
 * DELETE body (JSON) or ?id=<int> – soft-delete (set is_active = 0)
 *   id (int) – required
 */

ini_set('display_errors', 0);
ini_set('log_errors', 1);
error_reporting(E_ALL);

header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, DELETE, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

require_once __DIR__ . '/../Api2/db_config.php';

$method = $_SERVER['REQUEST_METHOD'];

// --------------------------------------------------------------------------
// GET – list
// --------------------------------------------------------------------------

if ($method === 'GET') {
    $showAll = isset($_GET['all']) && $_GET['all'] === '1';

    try {
        $sql = $showAll
            ? "SELECT id, name, file_url, is_default, is_active, created_at, updated_at FROM ringtones ORDER BY is_default DESC, name ASC"
            : "SELECT id, name, file_url, is_default, is_active, created_at, updated_at FROM ringtones WHERE is_active = 1 ORDER BY is_default DESC, name ASC";

        $stmt = $pdo->query($sql);
        $rows = $stmt->fetchAll();

        echo json_encode(['status' => 'success', 'count' => count($rows), 'data' => $rows]);
    } catch (PDOException $e) {
        error_log('admin/ringtones GET error: ' . $e->getMessage());
        echo json_encode(['status' => 'error', 'message' => 'Server error.']);
    }
    exit;
}

// --------------------------------------------------------------------------
// POST – insert or update
// --------------------------------------------------------------------------

if ($method === 'POST') {
    $input = json_decode(file_get_contents('php://input'), true);
    if (empty($input)) {
        $input = $_POST;
    }

    $name       = isset($input['name'])       ? trim($input['name'])       : '';
    $file_url   = isset($input['file_url'])   ? trim($input['file_url'])   : '';
    $is_default = isset($input['is_default']) ? (int) filter_var($input['is_default'], FILTER_VALIDATE_BOOLEAN) : 0;
    $id         = isset($input['id'])         ? (int) $input['id']         : 0;

    if ($name === '' || $file_url === '') {
        echo json_encode(['status' => 'error', 'message' => 'name and file_url are required']);
        exit;
    }

    try {
        $pdo->beginTransaction();

        // If this ringtone is being set as default, clear any existing default
        if ($is_default) {
            $pdo->exec("UPDATE ringtones SET is_default = 0");
        }

        if ($id > 0) {
            // Update existing
            $stmt = $pdo->prepare("
                UPDATE ringtones
                SET name = ?, file_url = ?, is_default = ?, updated_at = NOW()
                WHERE id = ?
            ");
            $stmt->execute([$name, $file_url, $is_default, $id]);
        } else {
            // Insert new
            $stmt = $pdo->prepare("
                INSERT INTO ringtones (name, file_url, is_default, is_active)
                VALUES (?, ?, ?, 1)
            ");
            $stmt->execute([$name, $file_url, $is_default]);
            $id = (int) $pdo->lastInsertId();
        }

        $pdo->commit();

        echo json_encode(['status' => 'success', 'message' => 'Ringtone saved', 'id' => $id]);

    } catch (PDOException $e) {
        $pdo->rollBack();
        error_log('admin/ringtones POST error: ' . $e->getMessage());
        echo json_encode(['status' => 'error', 'message' => 'Server error.']);
    }
    exit;
}

// --------------------------------------------------------------------------
// DELETE – soft-delete
// --------------------------------------------------------------------------

if ($method === 'DELETE') {
    $input = json_decode(file_get_contents('php://input'), true);
    $id    = isset($input['id'])   ? (int) $input['id']   :
            (isset($_GET['id'])    ? (int) $_GET['id']    : 0);

    if ($id <= 0) {
        echo json_encode(['status' => 'error', 'message' => 'id is required']);
        exit;
    }

    try {
        // Do not allow deleting the last active default ringtone
        $defaultCheck = $pdo->prepare("SELECT is_default FROM ringtones WHERE id = ? LIMIT 1");
        $defaultCheck->execute([$id]);
        $row = $defaultCheck->fetch();

        if (!$row) {
            echo json_encode(['status' => 'error', 'message' => 'Ringtone not found']);
            exit;
        }

        if ($row['is_default']) {
            echo json_encode(['status' => 'error', 'message' => 'Cannot delete the default ringtone. Set another ringtone as default first.']);
            exit;
        }

        $stmt = $pdo->prepare("UPDATE ringtones SET is_active = 0, updated_at = NOW() WHERE id = ?");
        $stmt->execute([$id]);

        echo json_encode(['status' => 'success', 'message' => 'Ringtone deactivated']);

    } catch (PDOException $e) {
        error_log('admin/ringtones DELETE error: ' . $e->getMessage());
        echo json_encode(['status' => 'error', 'message' => 'Server error.']);
    }
    exit;
}

// --------------------------------------------------------------------------
// Unsupported method
// --------------------------------------------------------------------------

http_response_code(405);
echo json_encode(['status' => 'error', 'message' => 'Method not allowed']);
