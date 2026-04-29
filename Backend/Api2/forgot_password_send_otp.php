<?php
header('Content-Type: application/json; charset=utf-8');

// DB CONFIG
$dbHost = 'localhost';
$dbUser = 'ms';
$dbPass = 'ms';
$dbName = 'ms';

// BREVO API KEY
$brevoApiKey = "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";

function respond($code, $msg) {
    http_response_code($code);
    echo json_encode($msg);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    respond(405, ['success'=>false,'message'=>'Only POST allowed']);
}

$email = trim($_POST['email'] ?? '');

if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
    respond(400, ['success'=>false,'message'=>'Invalid email']);
}

// DB
$mysqli = new mysqli($dbHost,$dbUser,$dbPass,$dbName);

if ($mysqli->connect_errno) {
    respond(500, ['success'=>false,'message'=>'DB connection failed']);
}

$mysqli->set_charset('utf8mb4');

// check user
$stmt = $mysqli->prepare("SELECT id FROM users WHERE email = ? LIMIT 1");
$stmt->bind_param('s', $email);
$stmt->execute();
$res = $stmt->get_result();
$user = $res->fetch_assoc();
$stmt->close();

if (!$user) {
    respond(404, ['success'=>false,'message'=>'Email not registered']);
}

// delete old OTP
$stmt = $mysqli->prepare("DELETE FROM password_resets WHERE email = ?");
$stmt->bind_param('s', $email);
$stmt->execute();
$stmt->close();

// generate OTP
$otp = random_int(100000,999999);
$expires = date('Y-m-d H:i:s', time()+600);

// store OTP
$stmt = $mysqli->prepare("
INSERT INTO password_resets (userid,email,otp,expires_at,verified)
VALUES (?,?,?,?,0)
");

$stmt->bind_param('isss',$user['id'],$email,$otp,$expires);
$stmt->execute();
$stmt->close();


// EMAIL BODY
$data = [
    "sender"=>[
        "name"=>"no-reply",
        "email"=>"no-reply@digitallami.com"
    ],
    "to"=>[
        [
            "email"=>$email
        ]
    ],
    "subject"=>"Password Reset OTP",
    "htmlContent"=>"<h2>Your OTP: $otp</h2>
    <p>This OTP is valid for 10 minutes, Marriage Station App.</p>"
];

// SEND EMAIL USING BREVO
$ch = curl_init();

curl_setopt_array($ch,[
    CURLOPT_URL => "https://api.brevo.com/v3/smtp/email",
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_POST => true,
    CURLOPT_POSTFIELDS => json_encode($data),
    CURLOPT_HTTPHEADER => [
        "accept: application/json",
        "api-key: $brevoApiKey",
        "content-type: application/json"
    ]
]);

$response = curl_exec($ch);
$httpcode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
curl_close($ch);

if($httpcode != 201){
    respond(500,['success'=>false,'message'=>'Email sending failed']);
}

respond(200,['success'=>true,'message'=>'OTP sent to email']);