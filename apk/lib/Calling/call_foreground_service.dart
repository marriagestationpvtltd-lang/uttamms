import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/services.dart';

/// Service to interact with Android foreground service for calls.
/// All methods are no-ops on web (Flutter Web does not support foreground
/// services — call state is managed entirely by the browser tab).
class CallForegroundServiceManager {
  static const MethodChannel _channel =
      MethodChannel('com.marriage.station/call_service');

  /// Start foreground service for a call
  static Future<bool> startCallService({
    required String callType,
    required String callerName,
    required String callId,
    required bool isIncoming,
  }) async {
    if (kIsWeb) return false;
    try {
      final result = await _channel.invokeMethod('startCallService', {
        'callType': callType,
        'callerName': callerName,
        'callId': callId,
        'isIncoming': isIncoming,
      });
      debugPrint('[CallForegroundService] Started: $result');
      return result == true;
    } on PlatformException catch (e) {
      debugPrint(
          '[CallForegroundService] Error starting service: ${e.message}');
      return false;
    }
  }

  /// Stop foreground service
  static Future<bool> stopCallService() async {
    if (kIsWeb) return false;
    try {
      final result = await _channel.invokeMethod('stopCallService');
      debugPrint('[CallForegroundService] Stopped: $result');
      return result == true;
    } on PlatformException catch (e) {
      debugPrint(
          '[CallForegroundService] Error stopping service: ${e.message}');
      return false;
    }
  }

  /// Update call notification (for when call connects)
  static Future<bool> updateCallNotification({
    required String callType,
    required String callerName,
    required bool isOngoing,
  }) async {
    if (kIsWeb) return false;
    try {
      final result = await _channel.invokeMethod('updateCallNotification', {
        'callType': callType,
        'callerName': callerName,
        'isOngoing': isOngoing,
      });
      debugPrint('[CallForegroundService] Updated notification: $result');
      return result == true;
    } on PlatformException catch (e) {
      debugPrint(
          '[CallForegroundService] Error updating notification: ${e.message}');
      return false;
    }
  }

  /// Check if service is running
  static Future<bool> isServiceRunning() async {
    if (kIsWeb) return false;
    try {
      final result = await _channel.invokeMethod('isServiceRunning');
      return result == true;
    } on PlatformException catch (e) {
      debugPrint(
          '[CallForegroundService] Error checking service: ${e.message}');
      return false;
    }
  }

  static Future<void> startOngoingCall({
    required String callType,
    required String otherUserName,
    required String callId,
  }) async {
    if (kIsWeb) return;
    await startCallService(
      callType: callType,
      callerName: otherUserName,
      callId: callId,
      isIncoming: false,
    );
    await updateCallNotification(
      callType: callType,
      callerName: otherUserName,
      isOngoing: true,
    );
  }

  /// Request audio focus for the active call.
  /// Must be called once the call is actually connected (remote peer joined) so
  /// that the outgoing ringtone is not interrupted while the call is still ringing.
  static Future<void> enableAudioFocus() async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod('enableAudioFocus');
    } on PlatformException catch (e) {
      debugPrint(
          '[CallForegroundService] Error enabling audio focus: ${e.message}');
    }
  }

  /// Switch the foreground call notification to a "connected" notification that
  /// shows a running chronometer starting from [connectedAt] (defaults to now).
  /// Call this the moment the in-app call duration timer starts ticking so that
  /// the system notification mirrors the in-call timer for the user.
  static Future<void> markCallConnected({
    required String callType,
    required String otherUserName,
    DateTime? connectedAt,
  }) async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod('markCallConnected', {
        'callType': callType,
        'callerName': otherUserName,
        'connectedAtMillis':
            (connectedAt ?? DateTime.now()).millisecondsSinceEpoch,
      });
    } on PlatformException catch (e) {
      debugPrint(
          '[CallForegroundService] Error marking call connected: ${e.message}');
    }
  }

  /// Cancel any active notification whose tag matches [tag]. When [prefix]
  /// is true, cancels notifications whose tag starts with [tag]. Used to
  /// remove the FCM-delivered OS banner for an incoming call once the
  /// full-screen in-app UI takes over (the FCM SDK uses an opaque internal
  /// id, so cancelling by id is not possible from Dart).
  static Future<int> cancelNotificationsByTag(String tag,
      {bool prefix = false}) async {
    if (kIsWeb || tag.isEmpty) return 0;
    try {
      final res = await _channel.invokeMethod<int>(
        'cancelNotificationsByTag',
        {'tag': tag, 'prefix': prefix},
      );
      return res ?? 0;
    } on PlatformException catch (e) {
      debugPrint(
          '[CallForegroundService] cancelNotificationsByTag error: ${e.message}');
      return 0;
    }
  }

  /// Cancel every active notification posted on any of the call channels
  /// (channel id starts with `calls_channel`). Safe blanket cleanup used
  /// when the user accepts/declines/ends a call so neither the OS-side
  /// FCM banner nor the in-app heads-up notification lingers.
  static Future<int> cancelAllCallBanners() async {
    if (kIsWeb) return 0;
    try {
      final res = await _channel.invokeMethod<int>('cancelAllCallBanners');
      return res ?? 0;
    } on PlatformException catch (e) {
      debugPrint(
          '[CallForegroundService] cancelAllCallBanners error: ${e.message}');
      return 0;
    }
  }
}
