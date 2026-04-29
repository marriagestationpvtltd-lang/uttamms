<?php
header('Content-Type: application/json; charset=utf-8');

$dbHost = 'localhost';
$dbUser = 'ms';
$dbPass = 'ms';
$dbName = 'ms';

function respond($code, $msg) {
    http_response_code($code);
    echo json_encode($msg);
    exit;
}

$email = $_POST['email'] ?? '';
$newPassword = $_POST['password'] ?? '';

if (!$email || strlen($newPassword) < 6) {
    respond(400, ['success'=>false,'message'=>'Invalid input']);
}

$mysqli = new mysqli($dbHost,$dbUser,$dbPass,$dbName);
$mysqli->set_charset('utf8mb4');

// check verified OTP
$stmt = $mysqli->prepare("
    SELECT userid FROM password_resets
    WHERE email = ? AND verified = 1
    ORDER BY created_at DESC LIMIT 1
");
$stmt->bind_param('s', $email);
$stmt->execute();
$res = $stmt->get_result();
$row = $res->fetch_assoc();
$stmt->close();

if (!$row) {
    respond(403, ['success'=>false,'message'=>'OTP not verified']);
}

// hash password (same as signup)
$hashed = password_hash($newPassword, PASSWORD_DEFAULT);

// update password
$stmt = $mysqli->prepare("UPDATE users SET password = ? WHERE id = ?");
$stmt->bind_param('si', $hashed, $row['userid']);
$stmt->execute();
$stmt->close();

// cleanup
$stmt = $mysqli->prepare("DELETE FROM password_resets WHERE email = ?");
$stmt->bind_param('s', $email);
$stmt->execute();
$stmt->close();

respond(200, ['success'=>true,'message'=>'Password reset successful']);
