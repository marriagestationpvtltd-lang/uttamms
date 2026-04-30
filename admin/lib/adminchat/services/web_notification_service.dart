import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:js_util' as js_util;
import 'package:flutter/foundation.dart';

/// Service for browser notifications and message sounds on the web platform.
///
/// - Background messages  → browser notification + sound
/// - Foreground messages  → sound only (no notification popup)
class WebNotificationService {
  WebNotificationService._();

  /// Tracks in-flight permission requests to avoid duplicate prompts.
  /// Cleared once the request finishes (success, denial, or error).
  static Future<void>? _permissionRequestFuture;

  /// Temporary gesture listeners used to trigger the permission prompt.
  /// These are removed once the first gesture is detected.
  static StreamSubscription<html.Event>? _permissionClickSubscription;
  static StreamSubscription<html.KeyboardEvent>? _permissionKeySubscription;
  static StreamSubscription<html.Event>? _permissionTouchSubscription;

  // ------------------------------------------------------------------
  // Permission
  // ------------------------------------------------------------------

  /// Requests the browser notification permission.
  /// Should be called once after the user first interacts with the app.
  static Future<void> requestPermission() async {
    if (!html.Notification.supported) return;
    if (html.Notification.permission == 'granted') return;
    final result = await html.Notification.requestPermission();
    if (result == 'denied') {
      debugPrint('Notification permission denied by the user.');
    }
    if (result != 'default') {
      _disposePermissionListeners();
    }
  }

  /// Ensures we request permission on the next user gesture (click/tap/key).
  /// This attaches temporary listeners and is safe to call multiple times.
  /// Required because some browsers block permission prompts without a gesture.
  static void ensurePermissionOnUserGesture() {
    if (!html.Notification.supported) return;
    if (html.Notification.permission != 'default') return;
    if (_permissionRequestFuture != null) return;

    _disposePermissionListeners();

    final permissionGestureCompleter = Completer<void>();

    void handleGesture([dynamic _]) {
      if (permissionGestureCompleter.isCompleted) return;
      permissionGestureCompleter.complete();
      _disposePermissionListeners();
    }

    _permissionClickSubscription =
        html.document.onClick.listen(handleGesture);
    _permissionKeySubscription =
        html.document.onKeyDown.listen(handleGesture);
    _permissionTouchSubscription =
        html.document.onTouchStart.listen(handleGesture);

    _permissionRequestFuture = permissionGestureCompleter.future
        .then((_) => requestPermission())
        .catchError((error, stackTrace) {
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stackTrace,
              library: 'WebNotificationService',
              context: ErrorDescription(
                'requesting browser notification permission',
              ),
            ),
          );
          debugPrint(
            'Notification permission request failed: $error '
            '(state: ${html.Notification.permission})\n$stackTrace',
          );
        })
        .whenComplete(() {
          _permissionRequestFuture = null;
          _disposePermissionListeners();
        });
  }

  static void _disposePermissionListeners() {
    _permissionClickSubscription?.cancel();
    _permissionKeySubscription?.cancel();
    _permissionTouchSubscription?.cancel();
    _permissionClickSubscription = null;
    _permissionKeySubscription = null;
    _permissionTouchSubscription = null;
  }

  // ------------------------------------------------------------------
  // Background detection
  // ------------------------------------------------------------------

  /// Returns `true` when the browser tab / window is not visible
  /// (i.e. the app is in the background).
  static bool isAppInBackground() {
    return html.document.hidden ?? false;
  }

  // ------------------------------------------------------------------
  // Browser notification
  // ------------------------------------------------------------------

  /// Shows a native browser notification with [senderName] as the title
  /// and [message] as the body.
  ///
  /// By default the notification is only shown when the browser tab is hidden
  /// (app in the background).  Pass [showInForeground] = true to also show
  /// the popup when the tab is visible (e.g. from a global listener while the
  /// admin is on a different page inside the same tab).
  ///
  /// [userId] is forwarded to the Flutter app via a custom browser event when
  /// the admin clicks the notification, so the app can navigate directly to
  /// that user's conversation.
  static void showMessageNotification({
    required String senderName,
    required String message,
    String userId = '',
    bool showInForeground = false,
  }) {
    if (!html.Notification.supported) return;
    if (html.Notification.permission == 'default') {
      // Ensure we prompt for permission on the next user gesture.
      ensurePermissionOnUserGesture();
      return;
    }
    if (html.Notification.permission != 'granted') return;
    if (!showInForeground && !isAppInBackground()) return;

    final notification = html.Notification(
      senderName,
      body: message,
      icon: '/adminp/icons/Icon-192.png',
    );

    // Auto-close after 6 seconds.
    Future.delayed(const Duration(seconds: 6), notification.close);

    // Clicking the notification focuses the tab and opens the conversation.
    notification.onClick.listen((_) {
      js_util.callMethod(js_util.globalThis, 'eval', ['window.focus()']);
      if (userId.isNotEmpty) {
        // Dispatch a custom event so the Flutter app can navigate to the user.
        js_util.callMethod(js_util.globalThis, 'eval', [
          'window.dispatchEvent(new CustomEvent("chatNotification", {detail: {userId: ${json.encode(userId)}}}))'
        ]);
      }
      notification.close();
    });
  }

  // ------------------------------------------------------------------
  // Notification sound  (WhatsApp-like double-tone via Web Audio API)
  // ------------------------------------------------------------------

  /// Plays a short WhatsApp-style notification sound using the Web Audio API.
  /// Works regardless of foreground/background state.
  static void playMessageSound() {
    try {
      js_util.callMethod(js_util.globalThis, 'eval', [
        '''
        (function() {
          try {
            var AudioCtx = window.AudioContext || window.webkitAudioContext;
            if (!AudioCtx) return;
            var ctx = new AudioCtx();

            // Two quick descending tones, identical to WhatsApp's ping.
            var tones = [
              { start: 0.00, freq: 880, end: 660 },
              { start: 0.12, freq: 880, end: 660 }
            ];

            tones.forEach(function(t) {
              var osc  = ctx.createOscillator();
              var gain = ctx.createGain();
              osc.connect(gain);
              gain.connect(ctx.destination);

              osc.type = 'sine';
              osc.frequency.setValueAtTime(t.freq, ctx.currentTime + t.start);
              osc.frequency.exponentialRampToValueAtTime(
                t.end, ctx.currentTime + t.start + 0.10);

              gain.gain.setValueAtTime(0.45, ctx.currentTime + t.start);
              gain.gain.exponentialRampToValueAtTime(
                0.001, ctx.currentTime + t.start + 0.18);

              osc.start(ctx.currentTime + t.start);
              osc.stop(ctx.currentTime  + t.start + 0.18);
            });
          } catch(e) { /* silently ignore – e.g. user hasn't interacted yet */ }
        })();
        '''
      ]);
    } catch (_) {}
  }

  // ------------------------------------------------------------------
  // Call ringtone  (looping HTML5 Audio during incoming call)
  // ------------------------------------------------------------------

  static const String _kCallRingtoneUrl = '/assets/audio/ring_classic.wav';
  static html.AudioElement? _callRingtoneEl;

  /// Starts looping the incoming call ringtone.
  /// Uses `assets/audio/ring_classic.wav` bundled with the admin app.
  /// Safe to call multiple times — a running ringtone is stopped first.
  static void playCallRingtone() {
    stopCallRingtone();
    try {
      final el = html.AudioElement(_kCallRingtoneUrl)
        ..loop = true
        ..volume = 0.85;
      _callRingtoneEl = el;
      el.play().catchError((_) {});
    } catch (_) {}
  }

  /// Stops the looping call ringtone started by [playCallRingtone].
  static void stopCallRingtone() {
    try {
      final el = _callRingtoneEl;
      _callRingtoneEl = null;
      if (el != null) {
        el.pause();
        el.src = '';
      }
    } catch (_) {}
  }
}
