/// Web implementation of a simple ringtone player.
///
/// Browsers enforce autoplay restrictions on the Web Audio API (AudioContext),
/// which means `audioplayers` can fail silently when the sound is triggered
/// by a WebSocket event rather than a direct user gesture.
/// `<audio>` elements (HTMLAudioElement) have a more relaxed policy — browsers
/// allow them to play when the page has already received a prior user gesture —
/// and are therefore more reliable for incoming-call ringtones on the web.
///
/// This file is imported only on web via a conditional import:
///   `import '…/web_call_ringtone_player_stub.dart'
///       if (dart.library.html) '…/web_ringtone_player.dart';`
library web_ringtone_player;

// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

class WebRingtonePlayer {
  WebRingtonePlayer._();
  static final WebRingtonePlayer instance = WebRingtonePlayer._();

  html.AudioElement? _el;
  bool _playing = false;

  /// Start looping the given asset path (relative to Flutter's `/assets/`
  /// directory, e.g. `'audio/ring_classic.wav'`).
  Future<void> play(String assetPath) async {
    if (_playing) return;
    try {
      await stop(); // dispose any previous element
      final el = html.AudioElement('/assets/$assetPath')
        ..loop = true
        ..volume = 0.9;
      _el = el;
      await el.play();
      _playing = true;
    } catch (e) {
      // Browsers may still block audio in rare cases; fail silently.
      html.window.console.warn('WebRingtonePlayer: could not play $assetPath – $e');
    }
  }

  /// Stop and dispose the current audio element.
  Future<void> stop() async {
    _playing = false;
    final el = _el;
    _el = null;
    if (el != null) {
      try {
        el.pause();
        el.src = '';
      } catch (_) {}
    }
  }

  /// Whether the player is currently playing.
  bool get isPlaying => _playing;
}
