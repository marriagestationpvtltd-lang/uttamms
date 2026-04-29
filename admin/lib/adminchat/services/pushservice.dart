import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:async';

import 'callmanager.dart';
import 'package:adminmrz/config/app_endpoints.dart';


class NotificationService {
  static final CallManager _callManager = CallManager();

  static Stream<Map<String, dynamic>> get incomingCalls => _callManager.incomingCalls;
  static Stream<Map<String, dynamic>> get callResponses => _callManager.callResponses;

  static void triggerIncomingCall(Map<String, dynamic> data) {
    _callManager.triggerIncomingCall(data);
  }


  // Your existing PHP API endpoint
  static const String _notificationUrl = '${kAdminApiBaseUrl}/Api2/send_notification.php';

  // Stream for call responses (listen in outgoing call screen)
  static final StreamController<Map<String, dynamic>> _callResponseController = StreamController.broadcast();

  // Trigger response event (call this from FCM onMessage handler)
  static void triggerCallResponse(Map<String, dynamic> data) {
    if (data['type'] == 'call_response') {
      _callResponseController.add(data);
    }
  }



  /// Send request notification
  static Future<bool> sendRequestNotification({
    required String recipientUserId,
    required String senderName,
    required String senderId,
    Map<String, dynamic>? extraData,
  }) async {
    return await sendNotification(
      userId: recipientUserId,
      title: '📨 New Request',
      body: '$senderName sent you a request',
      data: {
        'type': 'request',
        'senderId': senderId,
        'senderName': senderName,
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
    return await sendNotification(
      userId: recipientUserId,
      title: '💬 New Message',
      body: '$senderName: $message',
      data: {
        'type': 'chat',
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
    Map<String, dynamic>? extraData,
  }) async {
    return await sendNotification(
      userId: recipientUserId,
      title: '❌ Request Rejected',
      body: '$senderName rejected your request',
      data: {
        'type': 'request_rejected',
        'senderId': senderId,
        'senderName': senderName,
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
    Map<String, dynamic>? extraData,
  }) async {
    return await sendNotification(
      userId: recipientUserId,
      title: '✅ Request Accepted',
      body: '$senderName accepted your request',
      data: {
        'type': 'request_accepted',
        'senderId': senderId,
        'senderName': senderName,
        'timestamp': DateTime.now().toIso8601String(),
        ...?extraData,
      },
    );
  }









// Send any notification using your existing PHP API
  static Future<bool> sendNotification({
    required String userId,
    required String title,
    required String body,
    required Map<String, dynamic> data,
  }) async {
    try {
      final response = await http.post(
        Uri.parse(_notificationUrl),
        body: {
          'user_id': userId,
          'title': title,
          'body': body,
          'data': json.encode(data),
        },
      );

      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        return result['status'] == true;
      }
      return false;
    } catch (e) {
      print('❌ Error sending notification: $e');
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
  }) async {
    return await sendNotification(
      userId: recipientUserId,
      title: '📞 Incoming Call',
      body: '$callerName is calling you',
      data: {
        // 🔥 MUST BE EXACT
        'type': 'call',

        'channelName': channelName,
        'callerId': callerId,
        'callerName': callerName,
        'callerUid': callerUid,

        'agoraAppId': agoraAppId,
        'agoraCertificate': agoraCertificate,

        // ✅ ADD THIS (IMPORTANT FOR YOUR LOGIC)
        'isVideoCall': 'false',
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
    return await sendNotification(
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
        'timestamp': DateTime.now().toIso8601String(),
        'click_action': 'FLUTTER_NOTIFICATION_CLICK',
      },
    );
  }

  // Send missed call notification
  static Future<bool> sendMissedCallNotification({
    required String callerId,
    required String callerName,
  }) async {
    return await sendNotification(
      userId: callerId,
      title: '⏰ Missed Call',
      body: 'Missed call from $callerName',
      data: {
        'type': 'missed_call',
        'callerName': callerName,
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
  }) async {
    return await sendNotification(
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

// Add these video call notification methods to your existing NotificationService class

// Send video call notification (OUTGOING)
  static Future<bool> sendVideoCallNotification({
    required String recipientUserId,
    required String callerName,
    required String channelName,
    required String callerId,
    required String callerUid,
    required String agoraAppId,
    required String agoraCertificate,
  }) async {
    return await sendNotification(
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
      },
    );
  }

  /// Send a group audio-call invitation push notification.
  /// Includes callerRole and isConferenceCall so the mobile IncomingCallScreen
  /// handles it correctly (skips paid-plan check and uses conference accept/reject).
  static Future<bool> sendGroupCallNotification({
    required String recipientUserId,
    required String callerName,
    required String channelName,
    required String callerId,
    required String callerUid,
    required String agoraAppId,
  }) async {
    return await sendNotification(
      userId: recipientUserId,
      title: '📞 Incoming Group Call',
      body: '$callerName is inviting you to a group call',
      data: {
        'type': 'call',
        'channelName': channelName,
        'callerId': callerId,
        'callerName': callerName,
        'callerUid': callerUid,
        'agoraAppId': agoraAppId,
        'isVideoCall': 'false',
        'callerRole': 'admin',
        'isConferenceCall': 'true',
        'timestamp': DateTime.now().toIso8601String(),
        'click_action': 'FLUTTER_NOTIFICATION_CLICK',
        'sound': 'default',
      },
    );
  }

  /// Send a group video-call invitation push notification.
  /// Includes callerRole and isConferenceCall so the mobile IncomingVideoCallScreen
  /// handles it correctly (skips paid-plan check and uses conference accept/reject).
  static Future<bool> sendGroupVideoCallNotification({
    required String recipientUserId,
    required String callerName,
    required String channelName,
    required String callerId,
    required String callerUid,
    required String agoraAppId,
    required String agoraCertificate,
  }) async {
    return await sendNotification(
      userId: recipientUserId,
      title: '📹 Incoming Group Video Call',
      body: '$callerName is inviting you to a group video call',
      data: {
        'type': 'video_call',
        'channelName': channelName,
        'callerId': callerId,
        'callerName': callerName,
        'callerUid': callerUid,
        'agoraAppId': agoraAppId,
        'agoraCertificate': agoraCertificate,
        'isVideoCall': 'true',
        'callerRole': 'admin',
        'isConferenceCall': 'true',
        'timestamp': DateTime.now().toIso8601String(),
        'click_action': 'FLUTTER_NOTIFICATION_CLICK',
        'sound': 'default',
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
    return await sendNotification(
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
  }) async {
    return await sendNotification(
      userId: callerId,
      title: '⏰ Missed Video Call',
      body: 'Missed video call from $callerName',
      data: {
        'type': 'missed_video_call',
        'callerName': callerName,
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
  }) async {
    return await sendNotification(
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
        'isVideoCall': 'true',
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
  }

}
