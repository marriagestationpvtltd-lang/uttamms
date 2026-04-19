/// Web stub for flutter_ringtone_player.
///
/// flutter_ringtone_player relies on native audio system sounds which are not
/// available in the browser.  On web, incoming call audio is handled by the
/// audioplayers package (which supports web) playing an asset tone instead.
/// This stub provides no-op implementations so the code compiles on web.
library web_ringtone_player_stub;

// ── Enums ─────────────────────────────────────────────────────────────────────

class AndroidSounds {
  const AndroidSounds._();
  static const AndroidSounds ringtone = AndroidSounds._();
  static const AndroidSounds notification = AndroidSounds._();
  static const AndroidSounds alarm = AndroidSounds._();
}

class IosSounds {
  const IosSounds._();
  static const IosSounds electronic = IosSounds._();
  static const IosSounds bell = IosSounds._();
  static const IosSounds glass = IosSounds._();
}

// ── Plugin stub ───────────────────────────────────────────────────────────────

class FlutterRingtonePlayer {
  /// No-op on web.
  Future<void> play({
    AndroidSounds? android,
    IosSounds? ios,
    bool looping = false,
    bool asAlarm = false,
    double? volume,
  }) async {}

  /// No-op on web.
  Future<void> stop() async {}

  /// No-op on web.
  Future<void> playNotification() async {}

  /// No-op on web.
  Future<void> playRingtone() async {}

  /// No-op on web.
  Future<void> playAlarm() async {}
}
