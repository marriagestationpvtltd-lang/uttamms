import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_endpoints.dart';

enum AppSoundToneType {
  incomingCall,
  message,
  typing,
}

class AppSoundToneService {
  AppSoundToneService._();

  static final AppSoundToneService instance = AppSoundToneService._();

  static const _settingsUrl = '$kApiBaseUrl/Api2/app_settings.php';
  static const Duration cacheTtl = Duration(minutes: 5);

  final Map<AppSoundToneType, String> _customUrls = {
    AppSoundToneType.incomingCall: '',
    AppSoundToneType.message: '',
    AppSoundToneType.typing: '',
  };

  DateTime? _cachedAt;
  bool _refreshing = false;

  static const Map<AppSoundToneType, String> _defaultAssets = {
    AppSoundToneType.incomingCall: 'audio/ring_classic.wav',
    AppSoundToneType.message: 'audio/message_received.wav',
    AppSoundToneType.typing: 'audio/typing_tick.wav',
  };

  static const Map<AppSoundToneType, String> _remoteKeys = {
    AppSoundToneType.incomingCall: 'custom_incoming_tone_url',
    AppSoundToneType.message: 'custom_message_tone_url',
    AppSoundToneType.typing: 'custom_typing_tone_url',
  };

  static const Map<AppSoundToneType, String> _cacheKeys = {
    AppSoundToneType.incomingCall: 'cached_custom_incoming_tone_url',
    AppSoundToneType.message: 'cached_custom_message_tone_url',
    AppSoundToneType.typing: 'cached_custom_typing_tone_url',
  };

  Future<void> preload() async {
    await load();
  }

  Future<void> load() async {
    final now = DateTime.now();
    if (_cachedAt != null && now.difference(_cachedAt!) < cacheTtl) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    for (final entry in _cacheKeys.entries) {
      _customUrls[entry.key] = _normalizeCustomToneUrl(
        prefs.getString(entry.value),
      );
    }

    _cachedAt = now;
    _backgroundRefresh();
  }

  String defaultAsset(AppSoundToneType type) => _defaultAssets[type]!;

  Future<String> customUrl(AppSoundToneType type) async {
    await load();
    return _customUrls[type] ?? '';
  }

  Future<List<AppSoundPlaybackSource>> playbackSources(
      AppSoundToneType type) async {
    await load();
    final sources = <AppSoundPlaybackSource>[];
    final custom = (_customUrls[type] ?? '').trim();
    if (custom.isNotEmpty) {
      sources.add(AppSoundPlaybackSource.remote(custom));
    }
    // Always include bundled default asset as final fallback so tone plays
    // even when no custom URL is configured on the server.
    final defaultPath = _defaultAssets[type];
    if (defaultPath != null && defaultPath.isNotEmpty) {
      sources.add(AppSoundPlaybackSource.asset(defaultPath));
    }
    return sources;
  }

  void _backgroundRefresh() {
    if (_refreshing) return;
    _refreshing = true;

    () async {
      try {
        final response = await http
            .get(Uri.parse(_settingsUrl))
            .timeout(const Duration(seconds: 5));

        if (response.statusCode != 200) return;
        final decoded = jsonDecode(response.body);
        if (decoded is! Map<String, dynamic>) return;
        final data = decoded['data'];
        if (data is! Map<String, dynamic>) return;

        final prefs = await SharedPreferences.getInstance();
        for (final entry in _remoteKeys.entries) {
          final raw = data[entry.value]?.toString();
          final normalized = _normalizeCustomToneUrl(raw);
          _customUrls[entry.key] = normalized;
          await prefs.setString(_cacheKeys[entry.key]!, normalized);
        }

        _cachedAt = DateTime.now();
      } catch (e) {
        debugPrint('AppSoundToneService refresh error: $e');
      } finally {
        _refreshing = false;
      }
    }();
  }

  String _normalizeCustomToneUrl(String? toneUrl) {
    final raw = toneUrl?.trim() ?? '';
    if (raw.isEmpty) return '';

    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return raw;
    }

    final apiUri = Uri.parse(kApiBaseUrl);
    final origin = '${apiUri.scheme}://${apiUri.authority}';

    if (raw.startsWith('//')) {
      return '${apiUri.scheme}:$raw';
    }

    if (raw.startsWith('/uploads/')) {
      final appRoot = apiUri.path.replaceFirst(RegExp(r'/Backend/?$'), '');
      return '$origin$appRoot$raw';
    }

    if (raw.startsWith('/')) {
      return '$origin$raw';
    }

    final basePath =
        apiUri.path.endsWith('/') ? apiUri.path : '${apiUri.path}/';
    return '$origin$basePath$raw';
  }
}

class AppSoundPlaybackSource {
  final String value;
  final bool isRemote;

  const AppSoundPlaybackSource.asset(this.value) : isRemote = false;
  const AppSoundPlaybackSource.remote(this.value) : isRemote = true;
}
