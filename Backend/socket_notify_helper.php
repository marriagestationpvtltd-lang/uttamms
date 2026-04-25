<?php
/**
 * socket_notify_helper.php
 *
 * Fire-and-forget helper: tell the Socket.IO server to push a real-time
 * request event to connected admin panels and affected users.
 *
 * Usage (after a successful DB write):
 *   require_once __DIR__ . '/socket_notify_helper.php';
 *   notifyRequestEvent([
 *       'event'        => 'request_sent',   // 'request_sent'|'request_accepted'|'request_rejected'
 *       'proposalId'   => $proposalId,
 *       'senderId'     => $senderId,
 *       'receiverId'   => $receiverId,
 *       'senderName'   => $senderName,
 *       'receiverName' => $receiverName,
 *       'requestType'  => $requestType,
 *       'status'       => 'pending',        // new status
 *   ]);
 *
 * The call returns immediately — any socket-server error is logged silently so
 * it never blocks or breaks the calling API endpoint.
 *
 * Configuration (via server environment or define() before including):
 *   SOCKET_SERVER_INTERNAL_URL   — base URL of the socket server visible from
 *                                   this PHP host. Defaults to http://127.0.0.1:3001
 *   SOCKET_INTERNAL_SECRET       — shared secret matching server.js env var.
 *                                   When empty the notification is skipped.
 */

if (!function_exists('notifyRequestEvent')) {
    function notifyRequestEvent(array $data): void
    {
        // Resolve configuration from environment or compile-time constants.
        $socketUrl = defined('SOCKET_SERVER_INTERNAL_URL')
            ? SOCKET_SERVER_INTERNAL_URL
            : (getenv('SOCKET_SERVER_INTERNAL_URL') ?: 'http://127.0.0.1:3001');

        $secret = defined('SOCKET_INTERNAL_SECRET')
            ? SOCKET_INTERNAL_SECRET
            : (getenv('SOCKET_INTERNAL_SECRET') ?: '');

        // Skip silently when the secret is not configured — prevents accidental
        // unauthenticated calls if the server is also not configured yet.
        if ($secret === '') {
            return;
        }

        $endpoint = rtrim($socketUrl, '/') . '/api/notify-request';
        $payload  = json_encode($data);

        if ($payload === false) {
            error_log('notifyRequestEvent: json_encode failed');
            return;
        }

        $ch = curl_init($endpoint);
        if ($ch === false) {
            error_log('notifyRequestEvent: curl_init failed');
            return;
        }

        curl_setopt_array($ch, [
            CURLOPT_POST           => true,
            CURLOPT_POSTFIELDS     => $payload,
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT        => 2,          // 2-second hard cap — fire-and-forget
            CURLOPT_CONNECTTIMEOUT => 1,
            CURLOPT_HTTPHEADER     => [
                'Content-Type: application/json',
                'Content-Length: ' . strlen($payload),
                'X-Internal-Secret: ' . $secret,
            ],
        ]);

        $response = curl_exec($ch);
        $errno    = curl_errno($ch);
        curl_close($ch);

        if ($errno !== CURLE_OK) {
            // Non-fatal — real-time notification is best-effort
            error_log("notifyRequestEvent: curl error {$errno} calling {$endpoint}");
        }
    }
}
