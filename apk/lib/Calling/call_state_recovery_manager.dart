import 'dart:async';
import 'package:flutter/material.dart';
import '../navigation/app_navigation.dart';
import 'call_state_persistence.dart';
import 'unified_call_manager.dart';
import 'incommingcall.dart';
import 'incomingvideocall.dart';
import 'activecall.dart';
import 'videocall.dart';
import 'call_foreground_service.dart';

/// Manages call state recovery when app launches
class CallStateRecoveryManager {
  static final CallStateRecoveryManager _instance = CallStateRecoveryManager._internal();
  factory CallStateRecoveryManager() => _instance;
  CallStateRecoveryManager._internal();

  final UnifiedCallManager _callManager = UnifiedCallManager();
  bool _hasRecovered = false;
  final List<VoidCallback> _pendingActions = [];

  /// Initialize and attempt to recover any active calls
  Future<void> initialize() async {
    if (_hasRecovered) {
      print('[CallStateRecovery] Already recovered, skipping');
      return;
    }

    print('[CallStateRecovery] Initializing...');

    // Initialize unified call manager first
    await _callManager.initialize();

    // Check for active call state
    final callState = _callManager.currentCallState;
    if (callState != null && callState.isActive) {
      print('[CallStateRecovery] Found active call state, recovering...');
      await _recoverCall(callState);
    } else {
      print('[CallStateRecovery] No active call to recover');

      // Check for stale/old call states and clean them
      final savedState = await CallStatePersistence.loadCallState();
      if (savedState != null && !savedState.isActive) {
        print('[CallStateRecovery] Cleaning stale call state');
        await CallStatePersistence.clearCallState();
        await CallForegroundServiceManager.stopCallService();
      }
    }

    _hasRecovered = true;

    // Execute any pending actions
    _executePendingActions();
  }

  /// Recover an active call
  Future<void> _recoverCall(CallStateData callState) async {
    print('[CallStateRecovery] Recovering call: ${callState.callId}');
    print('[CallStateRecovery] Status: ${callState.status.name}');
    print('[CallStateRecovery] Type: ${callState.callType}');
    print('[CallStateRecovery] Incoming: ${callState.isIncoming}');

    // Restart foreground service if needed
    if (callState.status == CallStatus.active) {
      await CallForegroundServiceManager.startCallService(
        callType: callState.callType,
        callerName: callState.isIncoming ? callState.callerName : callState.receiverName,
        callId: callState.callId,
        isIncoming: false, // It's already accepted
      );
    }

    // Navigate to appropriate call screen based on state and type
    _queueNavigation(() {
      _navigateToCallScreen(callState);
    });
  }

  /// Navigate to appropriate call screen
  void _navigateToCallScreen(CallStateData callState) {
    final context = navigatorKey.currentContext;
    if (context == null) {
      print('[CallStateRecovery] Navigator context not ready, queueing...');
      _queueNavigation(() => _navigateToCallScreen(callState));
      return;
    }

    print('[CallStateRecovery] Navigating to call screen');

    // Use camelCase keys to match what IncomingCallScreen._parseData expects
    final callData = {
      'callerId': callState.callerId,
      'callerName': callState.callerName,
      'callerImage': callState.callerImage,
      'recipientName': callState.receiverName,
      'channelName': callState.channelName,
      'type': callState.callType == 'video' ? 'video_call' : 'call',
      'isVideoCall': callState.callType == 'video' ? 'true' : 'false',
    };

    // Determine which screen to navigate to
    Widget callScreen;

    if (callState.status == CallStatus.ringing && callState.isIncoming) {
      // Incoming call still ringing - navigate to incoming call screen
      if (callState.callType == 'video') {
        callScreen = IncomingVideoCallScreen(
          callData: callData,
        );
      } else {
        callScreen = IncomingCallScreen(
          callData: callData,
        );
      }
    } else if (callState.status == CallStatus.active || callState.status == CallStatus.connecting) {
      // Call is already active/connecting — reconnect to the live call screen
      final currentUserId = callState.isIncoming ? callState.receiverId : callState.callerId;
      final currentUserName = callState.isIncoming ? callState.receiverName : callState.callerName;
      final currentUserImage = callState.isIncoming ? callState.receiverImage : callState.callerImage;
      final otherUserId = callState.isIncoming ? callState.callerId : callState.receiverId;
      final otherUserName = callState.isIncoming ? callState.callerName : callState.receiverName;
      final otherUserImage = callState.isIncoming ? callState.callerImage : callState.receiverImage;

      if (callState.callType == 'video') {
        callScreen = VideoCallScreen(
          currentUserId: currentUserId,
          currentUserName: currentUserName,
          currentUserImage: currentUserImage,
          otherUserId: otherUserId,
          otherUserName: otherUserName,
          otherUserImage: otherUserImage,
          isOutgoingCall: !callState.isIncoming,
        );
      } else {
        callScreen = ActiveCallScreen(
          channel: callState.channelName,
          localUid: 0,
          remoteUid: 0,
          currentUserId: currentUserId,
          otherUserId: otherUserId,
          callerName: currentUserName,
          recipientName: otherUserName,
        );
      }
    } else {
      // Call ended or invalid state - just clean up
      print('[CallStateRecovery] Call in ended state, cleaning up');
      _callManager.reset();
      return;
    }

    // Navigate to call screen
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => callScreen,
        settings: const RouteSettings(name: '/active-call'),
      ),
    );
  }

  /// Queue a navigation action to be executed when context is ready
  void _queueNavigation(VoidCallback action) {
    if (_hasRecovered) {
      // If already recovered, try to execute immediately
      final context = navigatorKey.currentContext;
      if (context != null && context.mounted) {
        action();
      } else {
        // Wait a bit and retry
        Future.delayed(const Duration(milliseconds: 500), () {
          final context = navigatorKey.currentContext;
          if (context != null && context.mounted) {
            action();
          } else {
            print('[CallStateRecovery] Failed to execute navigation, context unavailable');
          }
        });
      }
    } else {
      _pendingActions.add(action);
    }
  }

  /// Execute all pending navigation actions
  void _executePendingActions() {
    if (_pendingActions.isEmpty) return;

    print('[CallStateRecovery] Executing ${_pendingActions.length} pending actions');

    final context = navigatorKey.currentContext;
    if (context != null && context.mounted) {
      for (final action in _pendingActions) {
        try {
          action();
        } catch (e) {
          print('[CallStateRecovery] Error executing pending action: $e');
        }
      }
      _pendingActions.clear();
    } else {
      // Context not ready yet, wait and retry
      Future.delayed(const Duration(milliseconds: 500), _executePendingActions);
    }
  }

  /// Handle notification tap when app is in background/terminated
  Future<void> handleNotificationTap(Map<String, dynamic> data) async {
    print('[CallStateRecovery] Handling notification tap: $data');

    final callType = data['type'];
    if (callType != 'call' && callType != 'video_call') {
      print('[CallStateRecovery] Not a call notification, ignoring');
      return;
    }

    // Check if there's already an active call state
    final currentState = _callManager.currentCallState;
    if (currentState != null && currentState.isActive) {
      print('[CallStateRecovery] Active call exists, navigating to it');
      _navigateToCallScreen(currentState);
      return;
    }

    // Check if we should create a new call from the notification
    // (This handles the case where notification arrived but app was killed before state saved)
    // Support both camelCase keys (from sendCallNotification) and underscore keys (legacy)
    final callerId = data['callerId'] ?? data['caller_id'] ?? data['senderId'];
    final channelName = data['channelName'] ?? data['channel_name'];

    if (callerId == null || channelName == null) {
      print('[CallStateRecovery] Incomplete call data in notification');
      return;
    }

    // Create new call state from notification data
    final callState = CallStateData(
      callId: channelName, // Use channel as call ID
      channelName: channelName,
      callerId: callerId,
      callerName: data['callerName'] ?? data['caller_name'] ?? data['senderName'] ?? 'Unknown',
      callerImage: data['callerImage'] ?? data['caller_image'] ?? data['senderImage'] ?? '',
      receiverId: data['receiverId'] ?? data['receiver_id'] ?? data['myId'] ?? '',
      receiverName: data['recipientName'] ?? data['receiverName'] ?? data['receiver_name'] ?? data['myName'] ?? '',
      receiverImage: data['receiverImage'] ?? data['receiver_image'] ?? data['myImage'] ?? '',
      callType: callType == 'video_call' ? 'video' : 'audio',
      status: CallStatus.ringing,
      startTime: DateTime.now(),
      isIncoming: true,
    );

    // Save state and navigate
    await CallStatePersistence.saveCallState(callState);
    _queueNavigation(() => _navigateToCallScreen(callState));
  }

  /// Reset recovery state (for testing)
  void reset() {
    _hasRecovered = false;
    _pendingActions.clear();
  }
}
