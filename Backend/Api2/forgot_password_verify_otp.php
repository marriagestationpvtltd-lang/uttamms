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
$otp   = $_POST['otp'] ?? '';

if (!$email || !$otp) {
    respond(400, ['success'=>false,'message'=>'Email and OTP required']);
}

$mysqli = new mysqli($dbHost,$dbUser,$dbPass,$dbName);
$mysqli->set_charset('utf8mb4');

$stmt = $mysqli->prepare("
    SELECT id FROM password_resets
    WHERE email = ? AND otp = ?
      AND expires_at > NOW()
      AND verified = 0
    LIMIT 1
");
$stmt->bind_param('ss', $email, $otp);
$stmt->execute();
$res = $stmt->get_result();
$row = $res->fetch_assoc();
$stmt->close();

if (!$row) {
    respond(401, ['success'=>false,'message'=>'Invalid or expired OTP']);
}

// mark verified
$stmt = $mysqli->prepare("UPDATE password_resets SET verified = 1 WHERE id = ?");
$stmt->bind_param('i', $row['id']);
$stmt->execute();
$stmt->close();

respond(200, ['success'=>true,'message'=>'OTP verified']);
