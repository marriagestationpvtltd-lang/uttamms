import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Singleton that provides **synchronous** access to the most-recently-seen
/// chat messages for any room.
///
/// The cache is backed by [SharedPreferences].  Because
/// [SharedPreferences.getInstance] must be awaited once, call [init] from
/// `main()` before [runApp].  After that single async initialisation every
/// subsequent read ([getMessages]) is **synchronous** — no await, no
/// microtask — so callers can populate their state in [State.initState]
/// before the first frame is painted, eliminating the white-screen / skeleton
/// flash.
///
/// Usage:
/// ```dart
/// // main.dart
/// await ChatMessageCache.instance.init();
/// runApp(…);
///
/// // ChatDetailScreen – initState
/// final cached = ChatMessageCache.instance.getMessages(roomId);
/// if (cached.isNotEmpty) {
///   _cachedMessages = cached;
///   _isFirstLoad = false;
/// }
/// ```
class ChatMessageCache {
  ChatMessageCache._();

  static final ChatMessageCache instance = ChatMessageCache._();

  SharedPreferences? _prefs;

  /// Maximum number of messages stored per room.
  static const int maxCachedMessages = 30;

  static const String _keyPrefix = 'chat_msgs_';

  /// Must be called (and awaited) **once** before [runApp].
  /// Safe to call multiple times — subsequent calls are no-ops.
  Future<void> init() async {
    if (_prefs != null) return;
    _prefs = await SharedPreferences.getInstance();
  }

  // ── Serialisation helpers ─────────────────────────────────────────────────

  static Map<String, dynamic> _serialize(Map<String, dynamic> msg) {
    final m = Map<String, dynamic>.from(msg);
    if (m['timestamp'] is DateTime) {
      m['timestamp'] = (m['timestamp'] as DateTime).toIso8601String();
    }
    return m;
  }

  static Map<String, dynamic> _deserialize(Map<String, dynamic> raw) {
    final m = Map<String, dynamic>.from(raw);
    if (m['timestamp'] is String) {
      final dt = DateTime.tryParse(m['timestamp'] as String);
      if (dt != null) m['timestamp'] = dt.toLocal();
    }
    return m;
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// Returns the cached messages for [roomId] **synchronously**.
  ///
  /// Returns an empty list when [init] has not been called yet, when no
  /// messages have ever been saved for this room, or on any parse error.
  List<Map<String, dynamic>> getMessages(String roomId) {
    if (_prefs == null) return [];
    try {
      final raw = _prefs!.getString('$_keyPrefix$roomId');
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => _deserialize(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      debugPrint('ChatMessageCache.getMessages error: $e');
      return [];
    }
  }

  /// Saves the most-recent [maxCachedMessages] from [messages] for [roomId].
  ///
  /// The write is fire-and-forget; errors are logged but not thrown.
  void saveMessages(String roomId, List<Map<String, dynamic>> messages) {
    if (_prefs == null) return;
    try {
      final toSave = messages.length >= maxCachedMessages
          ? messages.sublist(messages.length - maxCachedMessages)
          : messages;
      final encoded = jsonEncode(toSave.map(_serialize).toList());
      _prefs!.setString('$_keyPrefix$roomId', encoded);
    } catch (e) {
      debugPrint('ChatMessageCache.saveMessages error: $e');
    }
  }

  /// Removes the cached messages for [roomId] (e.g. on logout).
  void clearRoom(String roomId) {
    _prefs?.remove('$_keyPrefix$roomId');
  }
}
