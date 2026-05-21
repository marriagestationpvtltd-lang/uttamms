// ignore_for_file: use_string_in_part_of_directives, invalid_use_of_protected_member
part of 'call_overlay_manager.dart';

extension _IncomingCallRingtoneHandlers on IncomingCallOverlayManager {
  /// Play call ringtone using the unified AudioManager.
  /// AudioManager handles all sound policies, vibration, and cleanup automatically.
  Future<void> _playRingtone() async {
    try {
      await _stopRingtone();
      // AudioManager centralizes all ringtone logic and respects device policies
      await AudioManager.instance.playCallRingtone();
    } catch (e) {
      debugPrint('IncomingCallOverlayManager: ringtone error: $e');
    }
  }

  /// Stop call ringtone using the unified AudioManager.
  Future<void> _stopRingtone() async {
    try {
      await AudioManager.instance.stopCallRingtone();
    } catch (_) {}
  }
}
