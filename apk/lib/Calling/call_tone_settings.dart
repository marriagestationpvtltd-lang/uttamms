import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ms2026/config/app_endpoints.dart';

class CallTonePlaybackSource {
  final String value;
  final bool isRemote;

  const CallTonePlaybackSource.asset(this.value) : isRemote = false;

  const CallTonePlaybackSource.remote(this.value) : isRemote = true;
}

class CallToneSettings {
  static const defaultToneId = 'default';
  static const defaultAssetPath = 'audio/outcall.mp3';
  static const legacyDefaultAssetPath = 'images/outcall.mp3';
  static const _toneAssets = <String, String>{
    'classic': 'audio/ring_classic.wav',
    'soft': 'audio/ring_soft.wav',
    'modern': 'audio/ring_modern.wav',
    defaultToneId: defaultAssetPath,
  };

  final String toneId;
  final String customToneUrl;

  const CallToneSettings({
    this.toneId = defaultToneId,
    this.customToneUrl = '',
  });

  String get assetPath => _toneAssets[toneId] ?? defaultAssetPath;

  List<CallTonePlaybackSource> get playbackSources {
    final sources = <CallTonePlaybackSource>[];
    if (customToneUrl.isNotEmpty) {
      sources.add(CallTonePlaybackSource.remote(customToneUrl));
    }

    final primaryAsset = assetPath;
    sources.add(CallTonePlaybackSource.asset(primaryAsset));
    if (toneId == defaultToneId && primaryAsset != legacyDefaultAssetPath) {
      sources.add(const CallTonePlaybackSource.asset(legacyDefaultAssetPath));
    }

    return sources;
  }

  static String normalizeToneId(String? toneId) {
    return toneId != null && _toneAssets.containsKey(toneId)
        ? toneId
        : defaultToneId;
  }

  static String normalizeCustomToneUrl(String? customToneUrl) {
    return customToneUrl?.trim() ?? '';
  }
}

class CallToneSettingsService {
  CallToneSettingsService._();

  static final CallToneSettingsService instance = CallToneSettingsService._();

  static const _settingsUrl = '${kApiBaseUrl}/Api2/app_settings.php';
  static const _cachedToneIdKey = 'cached_call_tone_id';
  static const _cachedCustomToneUrlKey = 'cached_custom_call_tone_url';

  /// How long the in-memory cache is considered fresh. Within this window,
  /// [load] returns instantly without any server call.
  static const Duration cacheTtl = Duration(minutes: 5);

  /// In-memory cached settings – survives across call screens because the
  /// service is a singleton.
  CallToneSettings? _cached;
  DateTime? _cachedAt;

  /// Whether a background refresh is already in flight so we don't fire
  /// multiple concurrent HTTP requests.
  bool _refreshing = false;

  /// Pre-warm the cache (e.g. at app startup). Safe to call multiple times.
  Future<void> preload() async => load();

  /// Returns the admin-configured tone settings.
  ///
  /// **Fast path** – if the in-memory cache is still fresh (< [cacheTtl]),
  /// the result is returned synchronously with zero network I/O.
  ///
  /// **Warm path** – if the cache exists but is stale, the stale value is
  /// returned immediately and a background refresh is kicked off.
  ///
  /// **Cold path** – on the very first call (no in-memory cache), settings
  /// are read from SharedPreferences (instant) and then a blocking server
  /// fetch is attempted once.  The result is cached for subsequent calls.
  Future<CallToneSettings> load() async {
    // ── Fast path: in-memory cache is fresh ──
    if (_cached != null && _cachedAt != null) {
      final age = DateTime.now().difference(_cachedAt!);
      if (age < cacheTtl) {
        return _cached!;
      }
      // Cache exists but is stale – return it immediately and refresh in the
      // background so the next call gets an up-to-date value.
      _backgroundRefresh();
      return _cached!;
    }

    // ── Cold path: first load ever in this process ──
    final prefs = await SharedPreferences.getInstance();
    final cachedToneId = CallToneSettings.normalizeToneId(
      prefs.getString(_cachedToneIdKey),
    );
    final cachedCustomToneUrl = CallToneSettings.normalizeCustomToneUrl(
      prefs.getString(_cachedCustomToneUrlKey),
    );

    // Try fetching from the server once to prime the cache.
    final remote = await _fetchFromServer(prefs);
    if (remote != null) {
      _cached = remote;
      _cachedAt = DateTime.now();
      return remote;
    }

    // Server unreachable – use the SharedPreferences fallback.
    final fallback = CallToneSettings(
      toneId: cachedToneId,
      customToneUrl: cachedCustomToneUrl,
    );
    _cached = fallback;
    _cachedAt = DateTime.now();
    return fallback;
  }

  // ── Internal helpers ──────────────────────────────────────────────────

  /// Performs the HTTP fetch and, on success, persists to SharedPreferences.
  /// Returns `null` when the server is unreachable or the response is
  /// malformed.
  Future<CallToneSettings?> _fetchFromServer(SharedPreferences prefs) async {
    try {
      final response = await http
          .get(Uri.parse(_settingsUrl))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body is Map<String, dynamic>) {
          final data = body['data'];
          if (data is Map<String, dynamic>) {
            final remoteToneId = CallToneSettings.normalizeToneId(
              data['call_tone_id']?.toString(),
            );
            final remoteCustomToneUrl =
                CallToneSettings.normalizeCustomToneUrl(
              data['custom_call_tone_url']?.toString(),
            );
            await prefs.setString(_cachedToneIdKey, remoteToneId);
            await prefs.setString(
                _cachedCustomToneUrlKey, remoteCustomToneUrl);
            return CallToneSettings(
              toneId: remoteToneId,
              customToneUrl: remoteCustomToneUrl,
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading caller tone settings: $e');
    }
    return null;
  }

  /// Kicks off a non-blocking server refresh.  At most one refresh runs at
  /// a time; subsequent calls while one is in-flight are silently ignored.
  void _backgroundRefresh() {
    if (_refreshing) return;
    _refreshing = true;
    () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final remote = await _fetchFromServer(prefs);
        if (remote != null) {
          _cached = remote;
          _cachedAt = DateTime.now();
        }
      } finally {
        _refreshing = false;
      }
    }();
  }
}
