part of 'main.dart';

bool _isChatNotificationType(String type) {
  return type == 'chat' ||
      type == 'chat_message' ||
      type == 'message' ||
      type == 'new_message' ||
      type == 'admin_message';
}

bool _isRequestNotificationType(String type) {
  return type == 'request' ||
      type == 'request_sent' ||
      type == 'request_reminder' ||
      type == 'request_reminder_sent' ||
      type == 'request_accepted' ||
      type == 'request_rejected';
}

// Returns true when the notification was sent by the admin (senderId == '1').
// NOTE: '1' matches AdminChatScreen._adminUserId which is a fixed constant in this app.
bool _isAdminMessage(Map<String, dynamic> data) {
  const adminUserId = '1'; // Same constant as AdminChatScreen._adminUserId
  final senderId =
      data['senderId']?.toString() ?? data['sender_id']?.toString() ?? '';
  return senderId == adminUserId;
}

// Navigate to AdminChatScreen when an admin-sent message notification arrives.
Future<void> _navigateToAdminChatFromNotification(
    Map<String, dynamic> data) async {
  debugPrint('🔔 Admin message notification – opening AdminChatScreen');
  try {
    final currentUser = await CurrentUserInfo.fromPrefs();
    final currentUserId =
        currentUser.userId > 0 ? currentUser.userId.toString() : '';
    if (currentUserId.isEmpty) {
      debugPrint('⚠️ Admin chat navigation: currentUserId is empty');
      return;
    }

    final currentUserName = currentUser.fullName.trim();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final currentState = navigatorKey.currentState;
      if (currentState != null) {
        currentState.push(MaterialPageRoute(
          builder: (context) => AdminChatScreen(
            senderID: currentUserId,
            userName: currentUserName.isEmpty ? 'User' : currentUserName,
            isAdmin: false,
          ),
        ));
      }
    });
  } catch (e) {
    debugPrint('❌ Error navigating to admin chat from notification: $e');
  }
}
