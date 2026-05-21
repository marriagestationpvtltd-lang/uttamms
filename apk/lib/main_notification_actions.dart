part of 'main.dart';

// Handle notification actions (Accept/Decline from notification)
Future<void> _handleNotificationAction(NotificationResponse response) async {
  final payload = response.payload;
  final actionId = response.actionId;

  if (payload == null) return;

  try {
    final data = json.decode(payload);
    final type = data['type'];
    final isVideoCall = type == 'video_call' || data['isVideoCall'] == 'true';
    final notificationId = isVideoCall ? 1002 : 1001;

    debugPrint('📱 Notification action: $actionId');
    debugPrint('📱 Payload data: $data');

    if (actionId == 'accept_call') {
      debugPrint('✅ Call accepted from notification');

      // Clear the SharedPrefs key so _checkPendingIncomingCall doesn't also show banner
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('pending_incoming_call');
      } catch (_) {}

      // Dismiss compact banner if showing (prevents coexistence with full-screen)
      IncomingCallOverlayManager().dismiss();

      // Navigate to full-screen call page directly (user already pressed Accept)
      _navigateToCallPage(data);

      // Delay notification cancellation to ensure call screen is visible
      Future.delayed(const Duration(milliseconds: 800), () {
        flutterLocalNotificationsPlugin.cancel(notificationId);
      });
    } else if (actionId == 'decline_call') {
      debugPrint('❌ Call declined from notification');

      // Cancel the ringing notification
      flutterLocalNotificationsPlugin.cancel(notificationId);

      final callerId = data['callerId']?.toString();
      if (callerId != null && callerId.isNotEmpty) {
        final recipientName = await _resolveCurrentUserName();
        if (isVideoCall) {
          await NotificationService.sendVideoCallResponseNotification(
            callerId: callerId,
            recipientName: recipientName,
            accepted: false,
            recipientUid: '0',
            channelName: data['channelName']?.toString(),
          );
        } else {
          await NotificationService.sendCallResponseNotification(
            callerId: callerId,
            recipientName: recipientName,
            accepted: false,
            recipientUid: '0',
            channelName: data['channelName']?.toString(),
          );
        }
      }
    } else if (type == 'call' || type == 'video_call') {
      // User tapped the notification body (not Accept/Decline action).
      // Open the full-screen incoming-call UI so the user can accept / reject.
      //
      // IMPORTANT: We cannot rely on in-memory singletons
      // (`IncomingCallOverlayManager.isVisible`, `CallManager.isCallScreenShowing`,
      // `CallManager.hasActiveIncomingCall()`) to decide whether the call is
      // still live, because when the app was backgrounded / killed those
      // singletons were never populated — the FCM push was processed in the
      // background isolate. Instead use the `pending_incoming_call` prefs key
      // (written by the background handler) with a 60-second answerable
      // window. Inside the window → open the call screen. Outside → it is a
      // missed call, route to chat. This matches the `onMessageOpenedApp`
      // behaviour for the same payload.
      bool callStillActive = false;
      try {
        final prefs = await SharedPreferences.getInstance();
        final pendingStr = prefs.getString('pending_incoming_call');
        if (pendingStr != null) {
          final pendingData = json.decode(pendingStr) as Map<String, dynamic>;
          final receivedAt = pendingData['_receivedAt'] as int?;
          final now = DateTime.now().millisecondsSinceEpoch;
          callStillActive = receivedAt != null && now - receivedAt <= 60000;
        }
        // Consume the key whether we open the call or not — prevents the
        // CallOverlayWrapper._checkPendingIncomingCall path from also pushing
        // a duplicate full-screen call once the app finishes mounting.
        await prefs.remove('pending_incoming_call');
      } catch (_) {}

      // Also accept the tap as "call active" if the in-memory singletons say
      // so (covers the foreground tap case where the FCM arrived while the
      // app was open and the singletons WERE populated).
      callStillActive = callStillActive ||
          IncomingCallOverlayManager().isVisible ||
          CallManager().isCallScreenShowing ||
          CallManager().hasActiveIncomingCall();

      // Cancel the ringing notification — the call is either being opened
      // or has already expired.
      flutterLocalNotificationsPlugin.cancel(notificationId);

      if (callStillActive) {
        // Dismiss compact banner if any, then open the full-screen UI.
        if (IncomingCallOverlayManager().isVisible) {
          IncomingCallOverlayManager().dismiss();
        }
        _navigateToCallPage(data);
      } else {
        _navigateToChatFromCallNotification(data);
      }
    } else {
      // Regular notification tap (chat messages, requests, profile views, etc.)
      _handleNotificationTap(payload);
    }
  } catch (e) {
    debugPrint('❌ Error handling notification action: $e');
  }
}

void _handleNotificationTap(String? payload) {
  if (payload == null) return;

  try {
    final data = json.decode(payload);
    final type = data['type'];

    debugPrint('📱 Notification tapped with type: $type');
    debugPrint('📱 Payload data: $data');

    // Navigate based on notification type
    if (type == 'call' ||
        type == 'video_call' ||
        type == 'missed_call' ||
        type == 'missed_video_call' ||
        type == 'call_ended' ||
        type == 'video_call_ended' ||
        type == 'call_response' ||
        type == 'video_call_response' ||
        type == 'call_cancelled' ||
        type == 'video_call_cancelled') {
      // For all call-related notifications open the chat conversation
      _navigateToChatFromCallNotification(data);
    } else if (type == 'chat_message' || type == 'chat') {
      _navigateToChatFromMessageNotification(data);
    } else {
      // profile_like, shortlist, profile_view, request*, reel_*, story_* → profile
      _navigateToUserProfileFromNotification(data);
    }
  } catch (e) {
    debugPrint('❌ Error handling notification tap: $e');
  }
}
