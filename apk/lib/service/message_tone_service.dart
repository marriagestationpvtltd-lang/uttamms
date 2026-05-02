import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/services.dart';
import 'socket_service.dart';
import 'sound_settings_service.dart';
import 'app_sound_tone_service.dart';
import 'device_sound_policy_service.dart';
import '../Chat/screen_state_manager.dart';

/// Global singleton that listens to the Socket.IO [onNewMessage] stream and
/// plays the admin-configured (or default) message receive tone whenever a
/// message arrives while the user is NOT actively viewing that chat and the
/// app is in the foreground.
///
/// Call [MessageToneService.instance.init(currentUserId)] once after login
/// (e.g. from [MainControllerScreen._listenUnreadCounts]) to start listening.
/// Call [dispose()] on logout.
class MessageToneService {
  MessageToneService._();
  static final MessageToneService instance = MessageToneService._();

  StreamSubscription<Map<String, dynamic>>? _subscription;
  AudioPlayer? _player;
  String? _currentUserId;

  // Debounce: don't play the tone more than once per 800 ms
  DateTime? _lastPlayed;
  static const _debounce = Duration(milliseconds: 800);

  /// Start listening for incoming messages.
  /// Safe to call multiple times — re-subscribes on each call.
  void init(String currentUserId) {
    _currentUserId = currentUserId;
    _subscription?.cancel();
    _subscription = SocketService().onNewMessage.listen(_onNewMessage);
  }

  /// Stop listening and release audio resources.
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _player?.dispose();
    _player = null;
    _currentUserId = null;
  }

  void _onNewMessage(Map<String, dynamic> msg) {
    final senderId = _extractSenderId(msg);

    // If sender is missing in payload, still play tone for non-chat context.
    if (senderId.isEmpty) {
      final now = DateTime.now();
      if (_lastPlayed != null && now.difference(_lastPlayed!) < _debounce) return;
      _lastPlayed = now;
      _playTone();
      return;
    }

    // Ignore messages sent by the current user.
    if (senderId == _currentUserId) return;

    // Suppress when the user is actively viewing this chat.
    if (ScreenStateManager().isChattingWith(senderId)) return;

    // Debounce: rapid-fire messages should only trigger one tone.
    final now = DateTime.now();
    if (_lastPlayed != null && now.difference(_lastPlayed!) < _debounce) return;
    _lastPlayed = now;

    _playTone();
  }

  /// Called from the FCM foreground handler as a fallback so tone plays even
  /// if the socket didn't deliver the message (e.g. brief disconnect).
  /// Shares the same debounce window so there's no double-play when both fire.
  void playToneForIncomingFcm(String senderId) {
    if (senderId == _currentUserId) return;
    if (ScreenStateManager().isChattingWith(senderId)) return;

    final now = DateTime.now();
    if (_lastPlayed != null && now.difference(_lastPlayed!) < _debounce) return;
    _lastPlayed = now;

    _playTone();
  }

  /// FCM payload variant that can resolve sender from multiple key formats.
  void playToneForIncomingFcmData(Map<String, dynamic> data) {
    final senderId = _extractSenderId(data);
    if (senderId.isNotEmpty) {
      playToneForIncomingFcm(senderId);
      return;
    }

    // Sender is unknown: still play tone for incoming chat notification.
    final now = DateTime.now();
    if (_lastPlayed != null && now.difference(_lastPlayed!) < _debounce) return;
    _lastPlayed = now;
    _playTone();
  }

  String _extractSenderId(Map<String, dynamic> data) {
    return data['senderId']?.toString() ??
        data['sender_id']?.toString() ??
        data['fromId']?.toString() ??
        data['from_id']?.toString() ??
        '';
  }

  Future<void> _playTone() async {
    try {
      if (!SoundSettingsService.instance.messageSoundEnabled) return;

      final canPlay = await DeviceSoundPolicyService.canPlayInAppSound();
      if (!canPlay) {
        debugPrint('MessageToneService: phone is silent/vibrate/DND, skipping tone');
        return;
      }

      if (SoundSettingsService.instance.vibrationEnabled && !kIsWeb) {
        HapticFeedback.mediumImpact();
      }

      _player ??= AudioPlayer();

      final sources = await AppSoundToneService.instance
          .playbackSources(AppSoundToneType.message);

      await _player!.stop();

      if (sources.isEmpty) {
        // No custom/default source configured — fall back to system alert.
        if (!kIsWeb) await SystemSound.play(SystemSoundType.alert);
        return;
      }

      for (final source in sources) {
        try {
          if (source.isRemote) {
            await _player!.play(UrlSource(source.value));
          } else {
            await _player!.play(AssetSource(source.value));
          }
          return;
        } catch (_) {
          continue;
        }
      }

      // All sources failed — fall back to system alert.
      if (!kIsWeb) await SystemSound.play(SystemSoundType.alert);
    } catch (e) {
      debugPrint('MessageToneService: playTone error: $e');
    }
  }
}
