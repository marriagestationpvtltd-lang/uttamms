import 'package:flutter/material.dart';

class ScreenStateManager {
  static final ScreenStateManager _instance = ScreenStateManager._internal();
  factory ScreenStateManager() => _instance;
  ScreenStateManager._internal();

  // Track currently active chat screen
  String? _activeChatRoomId;
  String? _currentUserId;
  // Track who the current user is chatting with (the other party)
  String? _partnerUserId;

  // Track app lifecycle state
  AppLifecycleState _appLifecycleState = AppLifecycleState.resumed;

  // Track if chat screen is active
  bool get isChatScreenActive => _activeChatRoomId != null;

  // Check if app is in foreground
  bool get isAppInForeground => _appLifecycleState == AppLifecycleState.resumed;

  // Check if specific chat is active
  bool isChatActive(String chatRoomId, String userId) {
    return _activeChatRoomId == chatRoomId && _currentUserId == userId;
  }

  // Check if currently chatting with a specific user
  bool isChattingWith(String userId) {
    return _partnerUserId != null && _partnerUserId == userId && isAppInForeground;
  }

  // Set chat as active
  void setChatActive(String chatRoomId, String userId, {String? partnerUserId}) {
    _activeChatRoomId = chatRoomId;
    _currentUserId = userId;
    _partnerUserId = partnerUserId;
  }

  // Clear chat active state
  void clearChatActive() {
    _activeChatRoomId = null;
    _currentUserId = null;
    _partnerUserId = null;
  }

  // Track screen lifecycle
  void onChatScreenOpened(String chatRoomId, String userId, {String? partnerUserId}) {
    setChatActive(chatRoomId, userId, partnerUserId: partnerUserId);
  }

  void onChatScreenClosed() {
    clearChatActive();
  }

  // Update app lifecycle state
  void updateAppLifecycleState(AppLifecycleState state) {
    _appLifecycleState = state;
  }
}

// Helper method to check if notification should be shown
bool shouldShowChatNotification(Map<String, dynamic> data) {
  final manager = ScreenStateManager();
  final type = data['type']?.toString();

  // Suppress chat notifications when the user is actively viewing that chat
  // AND the app is in the foreground
  if (type == 'chat' || type == 'chat_message') {
    final senderId = data['senderId']?.toString() ?? '';
    if (senderId.isNotEmpty && manager.isChattingWith(senderId)) {
      return false;
    }
  }

  return true;
}