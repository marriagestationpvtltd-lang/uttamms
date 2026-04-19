// call_manager.dart
import 'dart:async';
import 'package:flutter/material.dart';

class CallManager {
  static final CallManager _instance = CallManager._internal();
  factory CallManager() => _instance;
  CallManager._internal();

  // Stream for incoming calls
  final StreamController<Map<String, dynamic>> _incomingCallController = StreamController.broadcast();
  Stream<Map<String, dynamic>> get incomingCalls => _incomingCallController.stream;

  // Stream for call responses
  final StreamController<Map<String, dynamic>> _callResponseController = StreamController.broadcast();
  Stream<Map<String, dynamic>> get callResponses => _callResponseController.stream;

  // Current active call data
  Map<String, dynamic>? _currentCallData;
  Timer? _callTimeoutTimer;

  // Track the last channel name to deduplicate simultaneous Socket.IO + FCM triggers
  String? _lastIncomingChannelName;

  // Trigger incoming call
  void triggerIncomingCall(Map<String, dynamic> data) {
    final channelName = data['channelName']?.toString() ?? '';

    // Deduplicate: when a caller sends both a Socket.IO invite and an FCM push
    // (which is the normal fallback strategy), both paths call triggerIncomingCall
    // for the same call. Without deduplication this pushes TWO IncomingCallScreens;
    // the buried screen's 60-second ring-timer then pops the active call screen.
    if (channelName.isNotEmpty && channelName == _lastIncomingChannelName) {
      print('📱 CallManager: Duplicate incoming call ignored (channel: $channelName)');
      return;
    }
    _lastIncomingChannelName = channelName;

    print('📱 CallManager: Incoming call triggered: $data');
    _currentCallData = data;
    _incomingCallController.add(data);

    // Cancel any previous auto-reject timer before arming a new one
    _callTimeoutTimer?.cancel();
    // Auto-reject after 60 seconds if not answered
    _callTimeoutTimer = Timer(const Duration(seconds: 60), () {
      if (_currentCallData != null) {
        print('⏰ CallManager: Call timeout');
        _currentCallData = null;
        _lastIncomingChannelName = null;
      }
    });
  }

  // Trigger call response
  void triggerCallResponse(Map<String, dynamic> data) {
    print('📱 CallManager: Call response triggered: $data');
    _callResponseController.add(data);

    final type = data['type']?.toString();
    final isRejected = (type == 'call_response' || type == 'video_call_response') &&
        data['accepted'] == 'false';
    final isEnded = type == 'call_ended' ||
        type == 'video_call_ended' ||
        type == 'missed_call' ||
        type == 'missed_video_call';

    if (isRejected || isEnded) {
      _currentCallData = null;
    }
  }

  // Get current call data
  Map<String, dynamic>? get currentCallData => _currentCallData;

  // Clear call data
  void clearCallData() {
    _currentCallData = null;
    _lastIncomingChannelName = null; // allow the next distinct call to be processed
    _callTimeoutTimer?.cancel();
    _callTimeoutTimer = null;
    _callScreenShowing = false;
  }

  // Check if there's an active incoming call
  bool hasActiveIncomingCall() => _currentCallData != null;

  // Track whether the call screen is already being shown to prevent duplicate pushes
  bool _callScreenShowing = false;
  bool get isCallScreenShowing => _callScreenShowing;
  set isCallScreenShowing(bool value) => _callScreenShowing = value;

  void dispose() {
    _incomingCallController.close();
    _callResponseController.close();
    _callTimeoutTimer?.cancel();
  }
}
