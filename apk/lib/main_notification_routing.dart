part of 'main.dart';

void _navigateToChatFromCallNotification(Map<String, dynamic> data) async {
  debugPrint('🚀 Navigating to chat from call notification');

  try {
    final currentUser = await CurrentUserInfo.fromPrefs();
    final currentUserId =
        currentUser.userId > 0 ? currentUser.userId.toString() : '';
    final currentUserName =
        currentUser.fullName.trim().isEmpty ? 'User' : currentUser.fullName;
    final currentUserImage = currentUser.profilePicture;

    if (currentUserId.isEmpty) {
      debugPrint('❌ Current user ID is empty');
      return;
    }

    // Extract caller/recipient info from notification
    final callerId = data['callerId'] ?? data['senderId'] ?? '';
    final callerName = data['callerName'] ?? data['senderName'] ?? 'Unknown';
    final callerImage = data['callerImage'] ?? '';

    if (callerId.isEmpty) {
      debugPrint('❌ Caller ID is empty');
      return;
    }

    // Generate chat room ID
    final chatRoomId = currentUserId.compareTo(callerId) < 0
        ? '${currentUserId}_$callerId'
        : '${callerId}_$currentUserId';

    debugPrint('💬 Opening chat with: $callerName (ID: $callerId)');
    debugPrint('💬 Chat room ID: $chatRoomId');

    // Navigate to chat screen
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final currentState = navigatorKey.currentState;
      final ctx = navigatorKey.currentContext;
      if (currentState == null || ctx == null) {
        debugPrint('❌ Navigator state is null, cannot navigate');
        return;
      }
      if (!await app_access.requireChatPackage(ctx)) return;
      currentState.push(
        MaterialPageRoute(
          builder: (context) => ChatDetailScreen(
            chatRoomId: chatRoomId,
            receiverId: callerId,
            receiverName: callerName,
            receiverImage: callerImage,
            currentUserId: currentUserId,
            currentUserName: currentUserName,
            currentUserImage: currentUserImage,
          ),
        ),
      );
    });
  } catch (e) {
    debugPrint('❌ Error navigating to chat from call notification: $e');
  }
}

void _navigateToChatFromMessageNotification(Map<String, dynamic> data) async {
  debugPrint('🚀 Navigating to chat from message notification');
  try {
    final currentUser = await CurrentUserInfo.fromPrefs();
    final currentUserId =
        currentUser.userId > 0 ? currentUser.userId.toString() : '';
    final currentUserName = currentUser.fullName.trim();

    if (currentUserId.isEmpty) return;

    final senderId = data['senderId']?.toString() ??
        data['sender_id']?.toString() ??
        data['related_user_id']?.toString() ??
        '';
    if (senderId.isEmpty) return;

    final chatRoomId = currentUserId.compareTo(senderId) < 0
        ? '${currentUserId}_$senderId'
        : '${senderId}_$currentUserId';

    final senderName = data['senderName']?.toString() ??
        data['peer_name']?.toString() ??
        data['sender_name']?.toString() ??
        'User';

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final currentState = navigatorKey.currentState;
      final ctx = navigatorKey.currentContext;
      if (currentState == null || ctx == null) {
        debugPrint('❌ Navigator state is null, cannot navigate to chat');
        return;
      }
      if (!await app_access.requireChatPackage(ctx)) return;
      currentState.push(MaterialPageRoute(
        builder: (context) => ChatDetailScreen(
          chatRoomId: chatRoomId,
          receiverId: senderId,
          receiverName: senderName,
          receiverImage: '',
          currentUserId: currentUserId,
          currentUserName: currentUserName.isEmpty ? 'User' : currentUserName,
          currentUserImage: currentUser.profilePicture,
        ),
      ));
    });
  } catch (e) {
    debugPrint('❌ Error navigating to chat from message notification: $e');
  }
}

void _navigateToUserProfileFromNotification(Map<String, dynamic> data) {
  final userId = data['sender_id']?.toString() ??
      data['related_user_id']?.toString() ??
      data['recipient_id']?.toString() ??
      '';
  if (userId.isEmpty) {
    debugPrint('❌ User ID is empty, cannot navigate to profile');
    return;
  }
  debugPrint('🚀 Navigating to user profile: $userId');
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    final currentState = navigatorKey.currentState;
    final currentContext = navigatorKey.currentContext;
    if (currentState != null && currentContext != null) {
      if (!await VerificationService.requireVerification(currentContext)) {
        debugPrint('⛔ Profile navigation blocked: user is not verified');
        return;
      }
      currentState.push(MaterialPageRoute(
        builder: (context) => ProfileScreen(userId: userId),
      ));
    } else {
      debugPrint('❌ Navigator state is null, cannot navigate to profile');
    }
  });
}

void _navigateToCallPage(Map<String, dynamic> data, {int navRetry = 0}) {
  final isVideoCall =
      data['isVideoCall'] == 'true' || data['type'] == 'video_call';

  debugPrint('🚀 Navigating to ${isVideoCall ? 'Video' : 'Voice'} Call Page');

  // Always dismiss the compact overlay banner before opening the full-screen
  // call UI. This prevents both UIs from being visible at the same time when
  // the notification is tapped while the in-app banner is already showing.
  if (IncomingCallOverlayManager().isVisible) {
    IncomingCallOverlayManager().dismiss();
  }

  WidgetsBinding.instance.addPostFrameCallback((_) {
    // Guard: a call screen is already on the stack — do not push a duplicate.
    // This is the same guard used by _pushCallScreen in the overlay manager.
    if (CallManager().isCallScreenShowing) {
      debugPrint('⚠️ Call screen already showing, skipping navigation');
      return;
    }

    final currentState = navigatorKey.currentState;
    if (currentState == null) {
      // Navigator not ready yet (app resuming from background). Retry with
      // increasing delay so notification-tap call screens reliably appear
      // even when the Flutter engine is still warming up after backgrounding.
      if (navRetry < 6) {
        debugPrint(
            '⚠️ Navigator null — retrying call navigation (attempt ${navRetry + 1})');
        Future.delayed(Duration(milliseconds: 250 * (navRetry + 1)), () {
          _navigateToCallPage(data, navRetry: navRetry + 1);
        });
      } else {
        debugPrint('❌ Navigator unavailable after $navRetry retries, giving up');
      }
      return;
    }

    CallManager().isCallScreenShowing = true;
    currentState
        .push(
          MaterialPageRoute(
            settings: RouteSettings(name: activeCallRouteName),
            fullscreenDialog: true,
            builder: (context) => isVideoCall
                ? IncomingVideoCallScreen(callData: data)
                : IncomingCallScreen(callData: data),
          ),
        )
        .whenComplete(() => CallManager().isCallScreenShowing = false);
  });
}
