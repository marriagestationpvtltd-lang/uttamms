// call_manager.dart
import 'dart:async';
import 'package:flutter/material.dart';

enum CallType { video, audio }

/// Tracks the state of an active (possibly minimized) call so any widget in
/// the tree can react to call lifecycle events.
class CallManager extends ChangeNotifier {
  static final CallManager _instance = CallManager._internal();
  factory CallManager() => _instance;
  CallManager._internal();

  // ── Incoming / response streams (used by push-notification handler) ────────
  final StreamController<Map<String, dynamic>> _incomingCallController =
      StreamController.broadcast();
  Stream<Map<String, dynamic>> get incomingCalls =>
      _incomingCallController.stream;

  final StreamController<Map<String, dynamic>> _callResponseController =
      StreamController.broadcast();
  Stream<Map<String, dynamic>> get callResponses =>
      _callResponseController.stream;

  // ── Active overlay call state ───────────────────────────────────────────────
  bool _isCallActive = false;
  bool _isMinimized = false;
  CallType _callType = CallType.video;
  String _callUserId = '';
  String _callUserName = '';

  bool get isCallActive => _isCallActive;
  bool get isMinimized => _isMinimized;
  CallType get callType => _callType;
  String get callUserId => _callUserId;
  String get callUserName => _callUserName;

  /// Called by the chat window when the admin taps video / audio call.
  void beginCall({
    required String userId,
    required String userName,
    required CallType type,
  }) {
    _isCallActive = true;
    _isMinimized = false;
    _callType = type;
    _callUserId = userId;
    _callUserName = userName;
    notifyListeners();
  }

  void minimizeCall() {
    if (!_isCallActive) return;
    _isMinimized = true;
    notifyListeners();
  }

  void maximizeCall() {
    if (!_isCallActive) return;
    _isMinimized = false;
    notifyListeners();
  }

  void endCall() {
    _isCallActive = false;
    _isMinimized = false;
    notifyListeners();
  }

  // ── Incoming call helpers (unchanged) ──────────────────────────────────────
  Map<String, dynamic>? _currentCallData;
  Timer? _callTimeoutTimer;

  void triggerIncomingCall(Map<String, dynamic> data) {
    _currentCallData = data;
    _incomingCallController.add(data);

    _callTimeoutTimer = Timer(const Duration(seconds: 60), () {
      _currentCallData = null;
    });
  }

  void triggerCallResponse(Map<String, dynamic> data) {
    _callResponseController.add(data);
    if (data['type'] == 'call_response' && data['accepted'] == 'false') {
      _currentCallData = null;
    }
  }

  Map<String, dynamic>? get currentCallData => _currentCallData;

  void clearCallData() {
    _currentCallData = null;
    _callTimeoutTimer?.cancel();
    _callTimeoutTimer = null;
  }

  bool hasActiveIncomingCall() => _currentCallData != null;

  @override
  void dispose() {
    _incomingCallController.close();
    _callResponseController.close();
    _callTimeoutTimer?.cancel();
    super.dispose();
  }
}