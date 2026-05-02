import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/services.dart';

/// Reads device sound policy (ringer + DND) from Android native code.
///
/// We use this to avoid playing custom in-app tones when the phone is in
/// silent/vibrate or Do Not Disturb mode.
class DeviceSoundPolicyService {
  DeviceSoundPolicyService._();

  static const MethodChannel _channel =
      MethodChannel('com.marriage.station/call_service');

  // ── Result cache ──────────────────────────────────────────────────────────
  // The device sound mode (silent / vibrate / normal) changes rarely and only
  // via a deliberate user action.  Caching the last result for a few seconds
  // avoids a platform-channel round-trip on every message receive event.
  static bool? _cachedResult;
  static DateTime? _cachedAt;
  static const _cacheDuration = Duration(seconds: 3);

  /// Returns `true` when custom in-app sounds are allowed.
  ///
  /// On non-Android platforms we keep previous behavior and return `true`.
  static Future<bool> canPlayInAppSound() async {
    if (kIsWeb) return true;

    // Return cached value if still fresh.
    final now = DateTime.now();
    if (_cachedResult != null &&
        _cachedAt != null &&
        now.difference(_cachedAt!) < _cacheDuration) {
      return _cachedResult!;
    }

    try {
      final result = await _channel
          .invokeMapMethod<String, dynamic>('getDeviceSoundPolicy');
      if (result == null) {
        _cachedResult = true;
        _cachedAt = now;
        return true;
      }

      final shouldPlay = result['shouldPlayInAppSound'];
      final value = shouldPlay is bool ? shouldPlay : true;
      _cachedResult = value;
      _cachedAt = now;
      return value;
    } catch (e) {
      // Fail open so audio behavior doesn't break if native bridge is unavailable.
      debugPrint('DeviceSoundPolicyService: fallback to allow sound ($e)');
      _cachedResult = true;
      _cachedAt = now;
      return true;
    }
  }

  /// Force-expire the cache immediately (e.g. after the user changes sound
  /// mode inside the app settings screen).
  static void invalidateCache() {
    _cachedResult = null;
    _cachedAt = null;
  }
}
