/// Native stub for [WebRingtonePlayer].
///
/// On native platforms (Android / iOS / desktop) the `audioplayers` package
/// handles ringtone playback directly, so this class is a no-op.
library web_call_ringtone_player_stub;

class WebRingtonePlayer {
  WebRingtonePlayer._();
  static final WebRingtonePlayer instance = WebRingtonePlayer._();

  /// No-op on native platforms.
  Future<void> play(String assetPath) async {}

  /// No-op on native platforms.
  Future<void> stop() async {}

  /// Always false on native platforms (handled by audioplayers).
  bool get isPlaying => false;
}
