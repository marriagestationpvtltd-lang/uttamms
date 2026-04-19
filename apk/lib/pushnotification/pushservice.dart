import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../Notification/notification_inbox_service.dart';
import '../Calling/callmanager.dart';
import 'package:ms2026/config/app_endpoints.dart';

/// Notification Service
///
/// Handles sending push notifications with proper classification:
///
/// Type 1: Real-time Interactive (call, video_call)
///   - Require immediate user action
///   - Always show notification with sound/vibration
///
/// Type 2: Silent Data Messages (call_response, call_ended, etc.)
///   - No user alert needed, only update app state
///   - Backend should send data-only payload (no notification key)
///
/// Type 3: Context-Aware (chat_message)
///   - Suppress when user is viewing that chat
///   - Show notification otherwise
///
/// Type 4: Standard (request, profile_view, etc.)
///   - Always show notification
///
class NotificationService {
  static final CallManager _callManager = CallManager();

  // Queue for notification requests to prevent race conditions
  static final List<_NotificationRequest> _notificationQueue = [];
  static bool _isProcessingQueue = false;
  static const int _maxQueueSize = 100;
  static const Duration _requestTimeout = Duration(seconds: 30);

  static Stream<Map<String, dynamic>> get incomingCalls => _callManager.incomingCalls;
  static Stream<Map<String, dynamic>> get callResponses => _callManager.callResponses;

  static void triggerIncomingCall(Map<String, dynamic> data) {
    _callManager.triggerIncomingCall(data);
  }


  // Your existing PHP API endpoint
  static const String _notificationUrl = '${kApiBaseUrl}/Api2/send_notification.php';

  // Stream for call responses (listen in outgoing call screen)
  static void triggerCallResponse(Map<String, dynamic> data) {
    const callEventTypes = {
      'call_response',
      'video_call_response',
      'call_ended',
      'video_call_ended',
      'missed_call',
      'missed_video_call',
      'call_cancelled',
      'video_call_cancelled',
    };

    if (callEventTypes.contains(data['type'])) {
      _callManager.triggerCallResponse(data);
    }
  }



  /// Send request notification
  static Future<bool> sendRequestNotification({
    required String recipientUserId,
    required String senderName,
    required String senderId,
    String requestType = 'Profile',
    bool isReminder = false,
    Map<String, dynamic>? extraData,
  }) async {
    final normalizedRequestType = NotificationInboxService.normalizeRequestType(requestType);
    final content = NotificationInboxService.buildNotificationContent(
      type: isReminder ? 'request_reminder' : 'request',
      actorName: senderName,
      requestType: normalizedRequestType,
    );

    return await sendNotification(
      userId: recipientUserId,
      title: content['title'] ?? 'Request update',
      body: content['body'] ?? '$senderName sent you a request',
      data: {
        'type': isReminder ? 'request_reminder' : 'request',
        'senderId': senderId,
        'senderName': senderName,
        'requestType': normalizedRequestType,
        'timestamp': DateTime.now().toIso8601String(),
        ...?extraData,
      },
    );
  }

  /// Send chat message notification
  static Future<bool> sendChatNotification({
    required String recipientUserId,
    required String senderName,
    required String senderId,
    required String message,
    Map<String, dynamic>? extraData,
  }) async {
    final content = NotificationInboxService.buildNotificationContent(
      type: 'chat_message',
      actorName: senderName,
      messagePreview: message,
    );

    return await sendNotification(
      userId: recipientUserId,
      title: content['title'] ?? 'New chat message',
      body: content['body'] ?? '$senderName: $message',
      data: {
        'type': 'chat_message',
        'senderId': senderId,
        'senderName': senderName,
        'message': message,
        'timestamp': DateTime.now().toIso8601String(),
        ...?extraData,
      },
    );
  }

  /// Send request rejected notification
  static Future<bool> sendRequestRejected({
    required String recipientUserId,
    required String senderName,
    required String senderId,
    String requestType = 'Request',
    Map<String, dynamic>? extraData,
  }) async {
    final normalizedRequestType = NotificationInboxService.normalizeRequestType(requestType);
    final content = NotificationInboxService.buildNotificationContent(
      type: 'request_rejected',
      actorName: senderName,
      requestType: normalizedRequestType,
    );

    return await sendNotification(
      userId: recipientUserId,
      title: content['title'] ?? 'Request rejected',
      body: content['body'] ?? '$senderName rejected your request',
      data: {
        'type': 'request_rejected',
        'senderId': senderId,
        'senderName': senderName,
        'requestType': normalizedRequestType,
        'timestamp': DateTime.now().toIso8601String(),
        ...?extraData,
      },
    );
  }

  /// Send request accepted notification
  static Future<bool> sendRequestAccepted({
    required String recipientUserId,
    required String senderName,
    required String senderId,
    String requestType = 'Request',
    Map<String, dynamic>? extraData,
  }) async {
    final normalizedRequestType = NotificationInboxService.normalizeRequestType(requestType);
    final content = NotificationInboxService.buildNotificationContent(
      type: 'request_accepted',
      actorName: senderName,
      requestType: normalizedRequestType,
    );

    return await sendNotification(
      userId: recipientUserId,
      title: content['title'] ?? 'Request accepted',
      body: content['body'] ?? '$senderName accepted your request',
      data: {
        'type': 'request_accepted',
        'senderId': senderId,
        'senderName': senderName,
        'requestType': normalizedRequestType,
        'timestamp': DateTime.now().toIso8601String(),
        ...?extraData,
      },
    );
  }









// Send any notification using your existing PHP API with queue and retry
  static Future<bool> sendNotification({
    required String userId,
    required String title,
    required String body,
    required Map<String, dynamic> data,
  }) async {
    // Validate inputs
    if (userId.isEmpty || userId.length > 100) {
      print('❌ Invalid userId: must be non-empty and <= 100 chars');
      return false;
    }
    if (title.length > 100) {
      print('❌ Invalid title: must be <= 100 chars');
      return false;
    }
    if (body.length > 500) {
      print('❌ Invalid body: must be <= 500 chars');
      return false;
    }

    // Check queue size limit
    if (_notificationQueue.length >= _maxQueueSize) {
      print('❌ Notification queue full (${_notificationQueue.length}/$_maxQueueSize), dropping request');
      return false;
    }

    final request = _NotificationRequest(
      userId: userId,
      title: title,
      body: body,
      data: data,
    );

    // Add to queue
    _notificationQueue.add(request);

    // Start queue processor if not already running
    _processQueueSequentially();

    // Wait for this request to be processed with timeout
    try {
      return await request.completer.future.timeout(
        _requestTimeout,
        onTimeout: () {
          print('⏰ Notification request timeout for user: $userId');
          return false;
        },
      );
    } catch (e) {
      print('❌ Error waiting for notification result: $e');
      return false;
    }
  }

  // Process queue sequentially to avoid race conditions
  static Future<void> _processQueueSequentially() async {
    if (_isProcessingQueue) return;

    _isProcessingQueue = true;

    while (_notificationQueue.isNotEmpty) {
      final request = _notificationQueue.removeAt(0);

      // Throttle: wait 300ms between requests
      await Future.delayed(const Duration(milliseconds: 300));

      // Send notification
      final success = await _sendNotificationDirect(
        userId: request.userId,
        title: request.title,
        body: request.body,
        data: request.data,
        retryCount: 0,
      );

      // Complete the request
      if (!request.completer.isCompleted) {
        request.completer.complete(success);
      }
    }

    _isProcessingQueue = false;
  }

  // Direct notification send with retry logic
  static Future<bool> _sendNotificationDirect({
    required String userId,
    required String title,
    required String body,
    required Map<String, dynamic> data,
    int retryCount = 0,
  }) async {
    const maxRetries = 3;
    const timeoutDuration = Duration(seconds: 10);

    try {
      final response = await http.post(
        Uri.parse(_notificationUrl),
        body: {
          'user_id': userId,
          'title': title,
          'body': body,
          'data': json.encode(data),
        },
      ).timeout(timeoutDuration);

      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        if (result['status'] == true) {
          print('✅ Notification sent successfully to user: $userId');
          return true;
        }
      }

      // Retry on failure
      if (retryCount < maxRetries) {
        print('⚠️ Notification failed, retrying (${retryCount + 1}/$maxRetries)...');
        await Future.delayed(Duration(milliseconds: 500 * (retryCount + 1)));
        return await _sendNotificationDirect(
          userId: userId,
          title: title,
          body: body,
          data: data,
          retryCount: retryCount + 1,
        );
      }

      print('❌ Notification failed after $maxRetries retries');
      return false;
    } catch (e) {
      print('❌ Error sending notification: $e');

      // Retry on exception
      if (retryCount < maxRetries) {
        print('⚠️ Retrying after error (${retryCount + 1}/$maxRetries)...');
        await Future.delayed(Duration(milliseconds: 500 * (retryCount + 1)));
        return await _sendNotificationDirect(
          userId: userId,
          title: title,
          body: body,
          data: data,
          retryCount: retryCount + 1,
        );
      }

      return false;
    }
  }

  // Clear the queue if needed
  static void clearQueue() {
    // Complete all pending requests with false
    for (final request in _notificationQueue) {
      if (!request.completer.isCompleted) {
        request.completer.complete(false);
      }
    }
    _notificationQueue.clear();
    _isProcessingQueue = false;
  }

  static Future<bool> sendProfileViewNotification({
    required String recipientUserId,
    required String viewerName,
    required String viewerId,
    Map<String, dynamic>? extraData,
  }) async {
    final content = NotificationInboxService.buildNotificationContent(
      type: 'profile_view',
      actorName: viewerName,
    );

    return await sendNotification(
      userId: recipientUserId,
      title: content['title'] ?? 'Profile viewed',
      body: content['body'] ?? '$viewerName viewed your profile.',
      data: {
        'type': 'profile_view',
        'viewerId': viewerId,
        'viewerName': viewerName,
        'senderId': viewerId,
        'senderName': viewerName,
        'timestamp': DateTime.now().toIso8601String(),
        ...?extraData,
      },
    );
  }

  // ─── Priority direct-send for time-critical call signalling ──────────────
  // Bypasses the sequential queue and 300 ms throttle so that call
  // notifications reach FCM as fast as possible.
  static Future<bool> _sendCallNotificationFast({
    required String userId,
    required String title,
    required String body,
    required Map<String, dynamic> data,
  }) async {
    const timeoutDuration = Duration(seconds: 8);
    try {
      final response = await http.post(
        Uri.parse(_notificationUrl),
        body: {
          'user_id': userId,
          'title': title,
          'body': body,
          'data': json.encode(data),
        },
      ).timeout(timeoutDuration);

      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        if (result['status'] == true) {
          print('✅ Call notification sent fast to user: $userId');
          return true;
        }
      }
      print('⚠️ Fast call notification failed for user: $userId');
      return false;
    } catch (e) {
      print('❌ Fast call notification error: $e');
      return false;
    }
  }

  // Send call notification (OUTGOING)
  static Future<bool> sendCallNotification({
    required String recipientUserId,
    required String callerName,
    required String channelName,
    required String callerId,
    required String callerUid,
    required String agoraAppId,
    required String agoraCertificate,
    String? chatRoomId,
  }) async {
    return await _sendCallNotificationFast(
      userId: recipientUserId,
      title: '📞 Incoming Call',
      body: '$callerName is calling you',
      data: {
        'type': 'call',
        'channelName': channelName,
        'callerId': callerId,
        'callerName': callerName,
        'callerUid': callerUid,
        'agoraAppId': agoraAppId,
        'agoraCertificate': agoraCertificate,
        'timestamp': DateTime.now().toIso8601String(),
        'click_action': 'FLUTTER_NOTIFICATION_CLICK',
        'sound': 'default',
        if (chatRoomId != null && chatRoomId.isNotEmpty) 'chatRoomId': chatRoomId,
      },
    );
  }

  // Send call response (INCOMING - Accept/Reject)
  static Future<bool> sendCallResponseNotification({
    required String callerId,
    required String recipientName,
    required bool accepted,
    required String recipientUid,
    String? channelName,
  }) async {
    return await _sendCallNotificationFast(
      userId: callerId, // Send back to the CALLER
      title: accepted ? '✅ Call Accepted' : '❌ Call Rejected',
      body: accepted
          ? '$recipientName accepted your call'
          : '$recipientName rejected your call',
      data: {
        'type': 'call_response',
        'accepted': accepted.toString(),
        'recipientName': recipientName,
        'recipientUid': recipientUid,
        if (channelName != null) 'channelName': channelName,
        'timestamp': DateTime.now().toIso8601String(),
        'click_action': 'FLUTTER_NOTIFICATION_CLICK',
      },
    );
  }

  // Send missed call notification
  static Future<bool> sendMissedCallNotification({
    required String callerId,
    required String callerName,
    String? senderId,
  }) async {
    return await _sendCallNotificationFast(
      userId: callerId,
      title: '⏰ Missed Call',
      body: 'Missed call from $callerName',
      data: {
        'type': 'missed_call',
        'callerName': callerName,
        if (senderId != null) 'senderId': senderId,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
  }

  // Send call ended notification
  static Future<bool> sendCallEndedNotification({
    required String recipientUserId,
    required String callerName,
    required String reason,
    required int duration,
    String? channelName,
  }) async {
    return await _sendCallNotificationFast(
      userId: recipientUserId,
      title: reason == 'timeout' ? '⏰ Missed Call' : '📞 Call Ended',
      body: reason == 'timeout'
          ? 'You missed a call from $callerName'
          : 'Call with $callerName ended (${_formatDuration(duration)})',
      data: {
        'type': 'call_ended',
        'callerName': callerName,
        'reason': reason,
        'duration': duration.toString(),
        if (channelName != null) 'channelName': channelName,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
  }

  static String _formatDuration(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes}m ${remainingSeconds}s';
  }

// Video call notification methods — all use priority fast-send path

// Send video call notification (OUTGOING)
  static Future<bool> sendVideoCallNotification({
    required String recipientUserId,
    required String callerName,
    required String channelName,
    required String callerId,
    required String callerUid,
    required String agoraAppId,
    required String agoraCertificate,
    String? chatRoomId,
  }) async {
    return await _sendCallNotificationFast(
      userId: recipientUserId,
      title: '📹 Incoming Video Call',
      body: '$callerName is calling you with video',
      data: {
        'type': 'video_call',
        'channelName': channelName,
        'callerId': callerId,
        'callerName': callerName,
        'callerUid': callerUid,
        'agoraAppId': agoraAppId,
        'agoraCertificate': agoraCertificate,
        'isVideoCall': 'true',
        'timestamp': DateTime.now().toIso8601String(),
        'click_action': 'FLUTTER_NOTIFICATION_CLICK',
        'sound': 'default',
        if (chatRoomId != null && chatRoomId.isNotEmpty) 'chatRoomId': chatRoomId,
      },
    );
  }

// Send video call response (INCOMING - Accept/Reject)
  static Future<bool> sendVideoCallResponseNotification({
    required String callerId,
    required String recipientName,
    required bool accepted,
    required String recipientUid,
    String? channelName,
  }) async {
    return await _sendCallNotificationFast(
      userId: callerId, // Send back to the CALLER
      title: accepted ? '✅ Video Call Accepted' : '❌ Video Call Rejected',
      body: accepted
          ? '$recipientName accepted your video call'
          : '$recipientName rejected your video call',
      data: {
        'type': 'video_call_response',
        'accepted': accepted.toString(),
        'recipientName': recipientName,
        'recipientUid': recipientUid,
        if (channelName != null) 'channelName': channelName,
        'isVideoCall': 'true',
        'timestamp': DateTime.now().toIso8601String(),
        'click_action': 'FLUTTER_NOTIFICATION_CLICK',
      },
    );
  }

// Send missed video call notification
  static Future<bool> sendMissedVideoCallNotification({
    required String callerId,
    required String callerName,
    String? senderId,
  }) async {
    return await _sendCallNotificationFast(
      userId: callerId,
      title: '⏰ Missed Video Call',
      body: 'Missed video call from $callerName',
      data: {
        'type': 'missed_video_call',
        'callerName': callerName,
        if (senderId != null) 'senderId': senderId,
        'isVideoCall': 'true',
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
  }

// Send video call ended notification
  static Future<bool> sendVideoCallEndedNotification({
    required String recipientUserId,
    required String callerName,
    required String reason,
    required int duration,
    String? channelName,
  }) async {
    return await _sendCallNotificationFast(
      userId: recipientUserId,
      title: reason == 'timeout' ? '⏰ Missed Video Call' : '📹 Video Call Ended',
      body: reason == 'timeout'
          ? 'You missed a video call from $callerName'
          : 'Video call with $callerName ended (${_formatDuration(duration)})',
      data: {
        'type': 'video_call_ended',
        'callerName': callerName,
        'reason': reason,
        'duration': duration.toString(),
        if (channelName != null) 'channelName': channelName,
        'isVideoCall': 'true',
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
  }

  // Send call cancelled notification (caller hung up before receiver answered)
  static Future<bool> sendCallCancelledNotification({
    required String recipientUserId,
    required String callerName,
    required String channelName,
    String? callerId,
  }) async {
    return await _sendCallNotificationFast(
      userId: recipientUserId,
      title: '📞 Call Cancelled',
      body: '$callerName cancelled the call',
      data: {
        'type': 'call_cancelled',
        'callerName': callerName,
        'channelName': channelName,
        if (callerId != null) 'senderId': callerId,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
  }

  // Send video call cancelled notification (caller hung up before receiver answered)
  static Future<bool> sendVideoCallCancelledNotification({
    required String recipientUserId,
    required String callerName,
    required String channelName,
    String? callerId,
  }) async {
    return await _sendCallNotificationFast(
      userId: recipientUserId,
      title: '📹 Video Call Cancelled',
      body: '$callerName cancelled the video call',
      data: {
        'type': 'video_call_cancelled',
        'callerName': callerName,
        'channelName': channelName,
        if (callerId != null) 'senderId': callerId,
        'isVideoCall': 'true',
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
  }

}

// Internal class for queuing notification requests
class _NotificationRequest {
  final String userId;
  final String title;
  final String body;
  final Map<String, dynamic> data;
  final Completer<bool> completer = Completer<bool>();

  _NotificationRequest({
    required this.userId,
    required this.title,
    required this.body,
    required this.data,
  });
}
