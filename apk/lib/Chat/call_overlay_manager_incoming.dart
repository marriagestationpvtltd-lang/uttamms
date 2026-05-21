// ignore_for_file: use_string_in_part_of_directives, invalid_use_of_protected_member
part of 'call_overlay_manager.dart';

extension _CallOverlayIncomingHandlers on _CallOverlayWrapperState {
  /// Reads any incoming-call data that was saved by the background isolate
  /// and navigates to the appropriate call screen.
  Future<void> _checkPendingIncomingCall() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingStr = prefs.getString('pending_incoming_call');
      if (pendingStr == null) return;

      final data = json.decode(pendingStr) as Map<String, dynamic>;
      final receivedAt = data['_receivedAt'] as int?;
      final now = DateTime.now().millisecondsSinceEpoch;

      // Discard stale entries (> 60 s – after which the call would time out)
      if (receivedAt == null ||
          now - receivedAt > _CallOverlayWrapperState._kIncomingCallExpiryMs) {
        await prefs.remove('pending_incoming_call');
        return;
      }

      // Remove before navigating to prevent re-processing
      await prefs.remove('pending_incoming_call');

      final isVideoCall =
          data['type'] == 'video_call' || data['isVideoCall'] == 'true';
      // Guard: if banner or full-screen already open (e.g. notification action fired first)
      if (IncomingCallOverlayManager().isVisible ||
          CallManager().isCallScreenShowing) {
        return;
      }
      // Background-resume path (user tapped the notification or returned to
      // the app while a call push was pending): go straight to the FULL-
      // SCREEN incoming-call UI. The compact minimized banner is only used
      // for purely in-foreground socket-delivered calls — opening both
      // would stack two receive-call screens on the user.
      _showIncomingOverlay(data, isVideoCall, forceFullScreen: true);
    } catch (e) {
      debugPrint('❌ Error checking pending incoming call: $e');
    }
  }

  void _setupCallCancelledListener() {
    _callCancelledSubscription?.cancel();
    _callCancelledSubscription = SocketService().onCallCancelled.listen((data) {
      // If the overlay is showing and belongs to this cancelled call, dismiss it
      if (IncomingCallOverlayManager().isVisible) {
        final overlayChannel =
            IncomingCallOverlayManager().callData?['channelName']?.toString();
        final cancelledChannel = data['channelName']?.toString();
        if (overlayChannel == null ||
            cancelledChannel == null ||
            overlayChannel == cancelledChannel) {
          IncomingCallOverlayManager().dismiss();
          CallManager().clearCallData();
        }
      }
    });
  }

  void _setupIncomingCallListener() {
    // Cancel any existing subscription before creating a new one
    _incomingCallSubscription?.cancel();
    _incomingCallSubscription = NotificationService.incomingCalls.listen(
      (data) {
        debugPrint('📱 CallOverlayWrapper: Incoming call received: $data');
        final isVideoCall =
            data['type'] == 'video_call' || data['isVideoCall'] == 'true';
        final lifecycle = WidgetsBinding.instance.lifecycleState;
        final appInForeground = lifecycle == AppLifecycleState.resumed;
        // Dismiss keyboard so the call overlay is not hidden behind it.
        FocusManager.instance.primaryFocus?.unfocus();
        WidgetsBinding.instance.scheduleFrame();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showIncomingOverlay(
            data,
            isVideoCall,
            // WhatsApp-like behavior: when app is backgrounded but alive,
            // go to full-screen incoming call flow instead of compact banner.
            forceFullScreen: !appInForeground,
          );
        });
      },
      onError: (error, stackTrace) {
        debugPrint('❌ Error in incoming call stream: $error');
        debugPrint('Stack trace: $stackTrace');
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) _setupIncomingCallListener();
        });
      },
      cancelOnError: false,
    );
  }

  /// Shows the compact WhatsApp-style incoming-call banner overlay.
  /// Falls back to full-screen when the app is being resumed from background
  /// (called from _checkPendingIncomingCall).
  void _showIncomingOverlay(
    Map<String, dynamic> data,
    bool isVideoCall, {
    bool forceFullScreen = false,
    int retryCount = 0,
    int maxRetries = 3,
  }) {
    // Guard: don't show if already in an active call -> auto-reject as busy
    if (CallOverlayManager().isCallActive) {
      final callerId = data['callerId']?.toString() ?? '';
      final currentUserId = CallOverlayManager()._currentUserId ?? '';
      final channelName = data['channelName']?.toString() ?? '';
      if (callerId.isNotEmpty && currentUserId.isNotEmpty) {
        SocketService().emitCallReject(
          callerId: callerId,
          recipientId: currentUserId,
          recipientName: CallOverlayManager()._currentUserName ?? '',
          channelName: channelName,
          callType: isVideoCall ? 'video' : 'audio',
        );
      }
      CallManager().clearCallData();
      return;
    }

    // Guard: don't show if call screen already visible
    if (CallManager().isCallScreenShowing) return;

    // Guard: don't show if overlay already visible for this channel
    if (IncomingCallOverlayManager().isVisible) {
      final existingChannel =
          IncomingCallOverlayManager().callData?['channelName']?.toString();
      final newChannel = data['channelName']?.toString();
      if (existingChannel == newChannel) return;
      // Different call -> dismiss old and show new
      IncomingCallOverlayManager().dismiss();
    }

    if (forceFullScreen) {
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      if (lifecycle != AppLifecycleState.resumed) {
        // If the app is currently backgrounded, persist payload so it can be
        // opened as soon as we resume (e.g. notification tap / full-screen intent).
        unawaited(() async {
          try {
            final prefs = await SharedPreferences.getInstance();
            final payload = {
              ...data,
              '_receivedAt': DateTime.now().millisecondsSinceEpoch,
            };
            await prefs.setString('pending_incoming_call', json.encode(payload));
          } catch (_) {}
        }());
        return;
      }
      // Background-resume path: go directly to full-screen incoming call screen
      _pushCallScreen(data, isVideoCall,
          retryCount: retryCount, maxRetries: maxRetries);
      return;
    }

    // Show the compact overlay banner (foreground / active app)
    IncomingCallOverlayManager().show(data, isVideo: isVideoCall);
  }

  /// Pushes the incoming call full-screen. Used by _showIncomingOverlay
  /// (force path) and from IncomingCallOverlay when user taps Accept.
  void _pushCallScreen(
    Map<String, dynamic> data,
    bool isVideoCall, {
    int retryCount = 0,
    int maxRetries = 3,
  }) {
    if (_isNavigatingToCall) return;
    if (CallManager().isCallScreenShowing) return;

    final currentState = navigatorKey.currentState;
    if (currentState == null) {
      if (retryCount < maxRetries) {
        Future.delayed(Duration(milliseconds: 400 * (retryCount + 1)), () {
          if (mounted) {
            _pushCallScreen(data, isVideoCall,
                retryCount: retryCount + 1, maxRetries: maxRetries);
          }
        });
      } else {
        debugPrint('❌ Navigator state unavailable after $maxRetries retries');
      }
      return;
    }

    _isNavigatingToCall = true;
    CallManager().isCallScreenShowing = true;
    // Dismiss the compact banner before pushing full-screen so both UIs
    // are never visible at the same time.
    IncomingCallOverlayManager().dismiss();
    final route = MaterialPageRoute(
      settings: RouteSettings(name: activeCallRouteName),
      fullscreenDialog: true,
      builder: (context) => isVideoCall
          ? IncomingVideoCallScreen(callData: data)
          : IncomingCallScreen(callData: data),
    );
    try {
      currentState.push(route).whenComplete(() {
        _isNavigatingToCall = false;
        CallManager().isCallScreenShowing = false;
      });
    } catch (_) {
      _isNavigatingToCall = false;
      CallManager().isCallScreenShowing = false;
    }
  }
}
