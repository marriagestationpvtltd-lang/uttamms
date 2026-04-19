import 'package:shared_preferences/shared_preferences.dart';

/// Singleton that persists user sound & vibration preferences locally.
///
/// All keys are stored in SharedPreferences so they survive app restarts
/// without requiring a server round-trip.
///
/// Usage:
///   // Read (sync after first load)
///   SoundSettingsService.instance.messageSoundEnabled
///
///   // Save
///   await SoundSettingsService.instance.setMessageSoundEnabled(false);
class SoundSettingsService {
  SoundSettingsService._();
  static final SoundSettingsService instance = SoundSettingsService._();

  // ── SharedPreferences keys ────────────────────────────────────────────────
  static const _kSoundEnabled    = 'sound_enabled';
  static const _kCallSound       = 'sound_call_enabled';
  static const _kMessageSound    = 'sound_message_enabled';
  static const _kTypingSound     = 'sound_typing_enabled';
  static const _kVibration       = 'vibration_enabled';

  // ── In-memory cache (populated by load()) ────────────────────────────────
  bool _soundEnabled    = true;
  bool _callSound       = true;
  bool _messageSound    = true;
  bool _typingSound     = true;
  bool _vibration       = true;

  bool _loaded = false;

  // ── Getters ───────────────────────────────────────────────────────────────

  /// Master sound switch. When false, all other sound settings are ignored.
  bool get soundEnabled => _soundEnabled;

  /// Whether the admin-configured ringtone plays for calls.
  bool get callSoundEnabled => _soundEnabled && _callSound;

  /// Whether a ding plays when a chat message is received.
  bool get messageSoundEnabled => _soundEnabled && _messageSound;

  /// Whether a short tick plays when the other party starts typing.
  bool get typingSoundEnabled => _soundEnabled && _typingSound;

  /// Whether the device vibrates on message receive / incoming call.
  bool get vibrationEnabled => _vibration;

  // Raw sub-flags (used by the Settings UI to show the stored value
  // regardless of the master switch state).
  bool get callSoundRaw     => _callSound;
  bool get messageSoundRaw  => _messageSound;
  bool get typingSoundRaw   => _typingSound;

  // ── Loaders ───────────────────────────────────────────────────────────────

  /// Load settings from SharedPreferences. Must be called once (e.g. at app
  /// start or before the first chat screen opens). Safe to call multiple times.
  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _soundEnabled  = prefs.getBool(_kSoundEnabled)  ?? true;
    _callSound     = prefs.getBool(_kCallSound)     ?? true;
    _messageSound  = prefs.getBool(_kMessageSound)  ?? true;
    _typingSound   = prefs.getBool(_kTypingSound)   ?? true;
    _vibration     = prefs.getBool(_kVibration)     ?? true;
    _loaded = true;
  }

  // ── Setters ───────────────────────────────────────────────────────────────

  Future<void> setSoundEnabled(bool v) async {
    _soundEnabled = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSoundEnabled, v);
  }

  Future<void> setCallSoundEnabled(bool v) async {
    _callSound = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kCallSound, v);
  }

  Future<void> setMessageSoundEnabled(bool v) async {
    _messageSound = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kMessageSound, v);
  }

  Future<void> setTypingSoundEnabled(bool v) async {
    _typingSound = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kTypingSound, v);
  }

  Future<void> setVibrationEnabled(bool v) async {
    _vibration = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kVibration, v);
  }
}
