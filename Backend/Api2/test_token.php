<?php
// agora_token_api.php
// CORS headers are set by Api2/.htaccess (Access-Control-Allow-Origin/Methods/Headers).
// Do not duplicate them here — Apache + PHP merging causes "multiple values" CORS errors.
header("Content-Type: application/json");

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(204);
    exit(0);
}

// ✅ Set your Agora App ID and Certificate
$appId = "7750d283e6794eebba06e7d021e8a01c";
$appCertificate = "71dff01f0cb348469672d4eb27197fb8";

// Include official Agora PHP RTC token builder
require_once __DIR__ . "/RtcTokenBuilder.php"; // Must be the RTC version
// Make sure AccessToken.php is also in the same folder

// Get parameters safely
$channelName = $_GET['channelName'] ?? $_POST['channelName'] ?? '';
$uid = $_GET['uid'] ?? $_POST['uid'] ?? 0;
$expireTime = intval($_GET['expireTime'] ?? $_POST['expireTime'] ?? 3600);
$isStringUid = ($_GET['isStringUid'] ?? $_POST['isStringUid'] ?? '0') === '1';

// Validate channel name
if (empty($channelName)) {
    http_response_code(400);
    echo json_encode([
        "success" => false,
        "statusCode" => 400,
        "message" => "channelName is required",
        "data" => "",
        "error" => "channelName missing"
    ]);
    exit;
}

try {
    $currentTimestamp = time();
    $privilegeExpiredTs = $currentTimestamp + $expireTime;

    // ✅ Generate RTC token (starts with 007)
    if ($isStringUid) {
        $uidStr = strval($uid);
        $token = RtcTokenBuilder::buildTokenWithUserAccount(
            $appId,
            $appCertificate,
            $channelName,
            $uidStr,
            RtcTokenBuilder::RolePublisher,
            $privilegeExpiredTs
        );
    } else {
        $uidInt = intval($uid);
        $token = RtcTokenBuilder::buildTokenWithUid(
            $appId,
            $appCertificate,
            $channelName,
            $uidInt,
            RtcTokenBuilder::RolePublisher,
            $privilegeExpiredTs
        );
    }

    echo json_encode([
        "success" => true,
        "statusCode" => 200,
        "message" => "Access Token",
        "data" => $token,
        "count" => 1,
        "error" => ""
    ]);

} catch (Exception $e) {
    http_response_code(500);
    echo json_encode([
        "success" => false,
        "statusCode" => 500,
        "message" => "Failed to generate token",
        "data" => "",
        "error" => $e->getMessage()
    ]);
}
?>
