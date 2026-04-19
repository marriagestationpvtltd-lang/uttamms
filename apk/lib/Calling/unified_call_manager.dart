import 'dart:async';
import 'package:flutter/material.dart';
import 'call_state_persistence.dart';
import '../pushnotification/pushservice.dart';

/// Unified call manager that combines CallManager and CallOverlayManager
/// with persistent state management
class UnifiedCallManager extends ChangeNotifier {
  static final UnifiedCallManager _instance = UnifiedCallManager._internal();
  factory UnifiedCallManager() => _instance;
  UnifiedCallManager._internal();

  // Stream controllers for call events
  final StreamController<Map<String, dynamic>> _incomingCallController =
      StreamController.broadcast();
  final StreamController<Map<String, dynamic>> _callResponseController =
      StreamController.broadcast();

  Stream<Map<String, dynamic>> get incomingCalls =>
      _incomingCallController.stream;
  Stream<Map<String, dynamic>> get callResponses =>
      _callResponseController.stream;

  // Current call state
  CallStateData? _currentCallState;
  Timer? _callDurationTimer;
  Timer? _callTimeoutTimer;
  Timer? _persistenceTimer;

  // UI callbacks
  VoidCallback? _onMaximize;
  VoidCallback? _onEnd;

  // Getters for compatibility with existing code
  bool get isCallActive => _currentCallState?.isActive ?? false;
  bool get isMinimized => _currentCallState?.isMinimized ?? false;
  String? get callType => _currentCallState?.callType;
  String? get otherUserName => _currentCallState?.isIncoming == true
      ? _currentCallState?.callerName
      : _currentCallState?.receiverName;
  String? get otherUserId => _currentCallState?.isIncoming == true
      ? _currentCallState?.callerId
      : _currentCallState?.receiverId;
  String get statusText => _getStatusText();
  Duration get duration =>
      _currentCallState?.duration != null
          ? Duration(seconds: _currentCallState!.duration!)
          : Duration.zero;
  bool get isConnected =>
      _currentCallState?.status == CallStatus.active ||
      (_currentCallState?.duration ?? 0) > 0;

  CallStateData? get currentCallState => _currentCallState;
  Map<String, dynamic>? get currentCallData => _currentCallState != null ? {
    'caller_id': _currentCallState!.callerId,
    'caller_name': _currentCallState!.callerName,
    'caller_image': _currentCallState!.callerImage,
    'receiver_id': _currentCallState!.receiverId,
    'receiver_name': _currentCallState!.receiverName,
    'receiver_image': _currentCallState!.receiverImage,
    'channel_name': _currentCallState!.channelName,
    'call_type': _currentCallState!.callType,
  } : null;

  /// Initialize and restore any persisted call state
  Future<void> initialize() async {
    print('[UnifiedCallManager] Initializing...');

    // Try to restore call state from storage
    final savedState = await CallStatePersistence.loadCallState();
    if (savedState != null && savedState.isActive) {
      print('[UnifiedCallManager] Restoring saved call state: ${savedState.callId}');

      // Check if call should have timed out
      if (savedState.shouldTimeout(const Duration(seconds: 60))) {
        print('[UnifiedCallManager] Saved call timed out, clearing...');
        await CallStatePersistence.clearCallState();
        return;
      }

      _currentCallState = savedState;

      // Restart timers if call is active
      if (savedState.status == CallStatus.active) {
        _startCallDurationTimer();
      } else if (savedState.status == CallStatus.ringing) {
        _startTimeoutTimer();
      }

      notifyListeners();
    }

    // Process any pending call history updates
    await _processPendingCallHistory();

    print('[UnifiedCallManager] Initialization complete');
  }

  /// Start a new call
  Future<void> startCall({
    required String callId,
    String? callHistoryId,
    required String channelName,
    required String callerId,
    required String callerName,
    required String callerImage,
    required String receiverId,
    required String receiverName,
    required String receiverImage,
    required String callType,
    required bool isIncoming,
    required VoidCallback onMaximize,
    required VoidCallback onEnd,
    Map<String, dynamic>? extraData,
  }) async {
    print('[UnifiedCallManager] Starting call: $callId');

    // Cancel any existing timers
    _cancelAllTimers();

    _currentCallState = CallStateData(
      callId: callId,
      callHistoryId: callHistoryId,
      channelName: channelName,
      callerId: callerId,
      callerName: callerName,
      callerImage: callerImage,
      receiverId: receiverId,
      receiverName: receiverName,
      receiverImage: receiverImage,
      callType: callType,
      status: CallStatus.ringing,
      startTime: DateTime.now(),
      isIncoming: isIncoming,
      extraData: extraData,
    );

    _onMaximize = onMaximize;
    _onEnd = onEnd;

    // Save to persistent storage
    await CallStatePersistence.saveCallState(_currentCallState!);

    // Start timeout timer for ringing state
    _startTimeoutTimer();

    // Start periodic persistence
    _startPersistenceTimer();

    notifyListeners();
  }

  /// Accept incoming call
  Future<void> acceptCall() async {
    if (_currentCallState == null) return;

    print('[UnifiedCallManager] Accepting call: ${_currentCallState!.callId}');

    _currentCallState = _currentCallState!.copyWith(
      status: CallStatus.connecting,
      connectTime: DateTime.now(),
    );

    await CallStatePersistence.saveCallState(_currentCallState!);

    // Cancel timeout timer
    _callTimeoutTimer?.cancel();
    _callTimeoutTimer = null;

    notifyListeners();
  }

  /// Mark call as connected/active
  Future<void> markCallActive() async {
    if (_currentCallState == null) return;

    print('[UnifiedCallManager] Call active: ${_currentCallState!.callId}');

    _currentCallState = _currentCallState!.copyWith(
      status: CallStatus.active,
      connectTime: _currentCallState!.connectTime ?? DateTime.now(),
      duration: 0,
    );

    await CallStatePersistence.saveCallState(_currentCallState!);

    // Start duration timer
    _startCallDurationTimer();

    notifyListeners();
  }

  /// Update call duration
  void updateDuration(int seconds) {
    if (_currentCallState == null) return;

    _currentCallState = _currentCallState!.copyWith(duration: seconds);
    notifyListeners();
  }

  /// Minimize call
  Future<void> minimizeCall() async {
    if (_currentCallState == null || !isCallActive) return;

    if (!_currentCallState!.isMinimized) {
      print('[UnifiedCallManager] Minimizing call');

      _currentCallState = _currentCallState!.copyWith(isMinimized: true);
      await CallStatePersistence.saveCallState(_currentCallState!);

      notifyListeners();
    }
  }

  /// Maximize call
  void maximizeCall() {
    if (_currentCallState == null || !isCallActive) return;

    if (_currentCallState!.isMinimized) {
      print('[UnifiedCallManager] Maximizing call');

      _currentCallState = _currentCallState!.copyWith(isMinimized: false);
      // Don't await to keep it synchronous for UI
      CallStatePersistence.saveCallState(_currentCallState!);

      notifyListeners();
      _onMaximize?.call();
    }
  }

  /// End call
  Future<void> endCall({CallStatus endStatus = CallStatus.ended}) async {
    if (_currentCallState == null) return;

    print('[UnifiedCallManager] Ending call: ${_currentCallState!.callId}, status: ${endStatus.name}');

    // Update status
    _currentCallState = _currentCallState!.copyWith(status: endStatus);

    // Save final state briefly for recovery
    await CallStatePersistence.saveCallState(_currentCallState!);

    // Save pending call history update for retry
    if (_currentCallState!.callHistoryId != null) {
      await CallStatePersistence.savePendingCallHistory(
        _currentCallState!.callHistoryId!,
        {
          'status': endStatus.name,
          'duration': _currentCallState!.duration ?? 0,
          'endTime': DateTime.now().toIso8601String(),
        },
      );
    }

    // Trigger onEnd callback
    final onEnd = _onEnd;
    if (onEnd != null) {
      onEnd();
    }

    // Clean up after a brief delay to allow cleanup operations
    Future.delayed(const Duration(seconds: 2), () {
      reset();
    });
  }

  /// Decline call
  Future<void> declineCall() async {
    await endCall(endStatus: CallStatus.declined);
  }

  /// Mark call as missed
  Future<void> missedCall() async {
    await endCall(endStatus: CallStatus.missed);
  }

  /// Mark call as cancelled
  Future<void> cancelCall() async {
    await endCall(endStatus: CallStatus.cancelled);
  }

  /// Mark call as dropped
  Future<void> dropCall() async {
    await endCall(endStatus: CallStatus.dropped);
  }

  /// Mark call as failed
  Future<void> failCall() async {
    await endCall(endStatus: CallStatus.failed);
  }

  /// Reset all call state
  Future<void> reset() async {
    print('[UnifiedCallManager] Resetting call manager');

    _cancelAllTimers();

    _currentCallState = null;
    _onMaximize = null;
    _onEnd = null;

    await CallStatePersistence.clearCallState();

    notifyListeners();
  }

  /// Trigger incoming call event
  void triggerIncomingCall(Map<String, dynamic> data) {
    print('[UnifiedCallManager] Incoming call triggered: $data');
    _incomingCallController.add(data);
  }

  /// Trigger call response event
  void triggerCallResponse(Map<String, dynamic> data) {
    print('[UnifiedCallManager] Call response triggered: $data');
    _callResponseController.add(data);
  }

  /// Check if there's an active incoming call
  bool hasActiveIncomingCall() =>
      _currentCallState != null &&
      _currentCallState!.isIncoming &&
      _currentCallState!.status == CallStatus.ringing;

  /// Clear call data (for compatibility)
  void clearCallData() {
    reset();
  }

  // Private helper methods

  void _startCallDurationTimer() {
    _callDurationTimer?.cancel();
    _callDurationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_currentCallState != null && _currentCallState!.status == CallStatus.active) {
        final elapsed = _currentCallState!.duration ?? 0;
        updateDuration(elapsed + 1);
      }
    });
  }

  void _startTimeoutTimer() {
    _callTimeoutTimer?.cancel();
    _callTimeoutTimer = Timer(const Duration(seconds: 60), () {
      print('[UnifiedCallManager] Call timeout');
      missedCall();
    });
  }

  void _startPersistenceTimer() {
    _persistenceTimer?.cancel();
    // Save state every 5 seconds for recovery
    _persistenceTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_currentCallState != null && _currentCallState!.isActive) {
        CallStatePersistence.saveCallState(_currentCallState!);
      }
    });
  }

  void _cancelAllTimers() {
    _callDurationTimer?.cancel();
    _callDurationTimer = null;

    _callTimeoutTimer?.cancel();
    _callTimeoutTimer = null;

    _persistenceTimer?.cancel();
    _persistenceTimer = null;
  }

  String _getStatusText() {
    if (_currentCallState == null) return 'No call';

    switch (_currentCallState!.status) {
      case CallStatus.ringing:
        return 'Ringing...';
      case CallStatus.connecting:
        return 'Connecting...';
      case CallStatus.active:
        return 'Connected';
      case CallStatus.ending:
        return 'Ending...';
      case CallStatus.ended:
        return 'Call ended';
      case CallStatus.missed:
        return 'Missed call';
      case CallStatus.declined:
        return 'Call declined';
      case CallStatus.cancelled:
        return 'Call cancelled';
      case CallStatus.failed:
        return 'Call failed';
      case CallStatus.dropped:
        return 'Call dropped';
    }
  }

  Future<void> _processPendingCallHistory() async {
    final pending = await CallStatePersistence.loadPendingCallHistory();
    if (pending != null) {
      print('[UnifiedCallManager] Found pending call history update, processing...');
      // This will be handled by the call history service
      // For now just clear it - the actual retry logic should be in CallHistoryService
      await CallStatePersistence.clearPendingCallHistory();
    }
  }

  @override
  void dispose() {
    _cancelAllTimers();
    _incomingCallController.close();
    _callResponseController.close();
    super.dispose();
  }
}
