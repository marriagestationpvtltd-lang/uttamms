// ignore_for_file: use_string_in_part_of_directives, invalid_use_of_protected_member
part of 'call_overlay_manager.dart';

extension _CallOverlayActionHandlers on IncomingCallOverlay {
  void _reject(Map<String, dynamic> data, bool isVideo) {
    IncomingCallOverlayManager().dismiss();
    CallManager().clearCallData();

    final callerId = data['callerId']?.toString() ?? '';
    final channelName = data['channelName']?.toString() ?? '';
    // Read current user from socket service
    final currentUserId = SocketService().currentUserId ?? '';

    if (callerId.isNotEmpty && currentUserId.isNotEmpty) {
      SocketService().emitCallReject(
        callerId: callerId,
        recipientId: currentUserId,
        recipientName: '',
        channelName: channelName,
        callType: isVideo ? 'video' : 'audio',
      );
    }
    NotificationService.sendCallResponseNotification(
      callerId: callerId,
      recipientName: '',
      accepted: false,
      recipientUid: '0',
      channelName: channelName,
    ).catchError((_) => false);
  }

  void _accept(BuildContext context, Map<String, dynamic> data, bool isVideo) {
    IncomingCallOverlayManager().dismiss();
    _openFullScreen(context, data, isVideo);
  }

  void _openFullScreen(
      BuildContext context, Map<String, dynamic> data, bool isVideo) {
    // Dismiss the compact banner first so it doesn't coexist with the full-screen.
    IncomingCallOverlayManager().dismiss();
    if (CallManager().isCallScreenShowing) return;
    CallManager().isCallScreenShowing = true;

    // Wait one frame so the overlay widget rebuilds to hidden before pushing
    // the fullscreen route — otherwise the banner renders on top of the call UI.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final currentState = navigatorKey.currentState;
      if (currentState == null) {
        CallManager().isCallScreenShowing = false;
        return;
      }
      final route = MaterialPageRoute(
        settings: RouteSettings(name: activeCallRouteName),
        fullscreenDialog: true,
        builder: (_) => isVideo
            ? IncomingVideoCallScreen(callData: data)
            : IncomingCallScreen(callData: data),
      );
      currentState.push(route).whenComplete(() {
        CallManager().isCallScreenShowing = false;
      });
    });
  }
}
