import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '_http_upload_stub.dart' if (dart.library.io) '_http_upload_io.dart';
import 'package:adminmrz/config/app_endpoints.dart';

class RingtoneTone {
  final String id;
  final String label;
  final String asset;

  const RingtoneTone({
    required this.id,
    required this.label,
    required this.asset,
  });
}

enum AppSoundToneType { outgoingCall, incomingCall, message, typing }

class AppSoundToneState {
  final String toneId;
  final String customUrl;
  final String customName;

  const AppSoundToneState({
    this.toneId = 'default',
    this.customUrl = '',
    this.customName = '',
  });

  bool get hasCustom => customUrl.isNotEmpty;

  AppSoundToneState copyWith({
    String? toneId,
    String? customUrl,
    String? customName,
  }) {
    return AppSoundToneState(
      toneId: toneId ?? this.toneId,
      customUrl: customUrl ?? this.customUrl,
      customName: customName ?? this.customName,
    );
  }
}

class _ToneSettingKeys {
  final String toneIdKey;
  final String customUrlKey;
  final String customNameKey;
  final String clearPayloadKey;
  final String uploadType;

  const _ToneSettingKeys({
    required this.toneIdKey,
    required this.customUrlKey,
    required this.customNameKey,
    required this.clearPayloadKey,
    required this.uploadType,
  });
}

class CallSettingsProvider extends ChangeNotifier {
  static const _keyRepeatInterval = 'call_repeat_interval';
  static final _settingsUrl = '$kAdminApiBaseUrl/Api2/app_settings.php';
  static final _updateSettingsUrl =
      '$kAdminApi9BaseUrl/update_app_settings.php';
  static final _uploadOutgoingUrl = '$kAdminApi9BaseUrl/upload_call_tone.php';
  static final _uploadMultiSoundUrl =
      '$kAdminApi9BaseUrl/upload_sound_tone.php';

  static const List<RingtoneTone> availableTones = [
    RingtoneTone(
      id: 'classic',
      label: 'Classic Ring (440 + 480 Hz)',
      asset: 'audio/ring_classic.wav',
    ),
    RingtoneTone(
      id: 'soft',
      label: 'Soft Professional (800 + 1000 Hz)',
      asset: 'audio/ring_soft.wav',
    ),
    RingtoneTone(
      id: 'modern',
      label: 'Modern Double-Beep',
      asset: 'audio/ring_modern.wav',
    ),
    RingtoneTone(
      id: 'default',
      label: 'Original Tone',
      asset: 'audio/outcall.mp3',
    ),
  ];

  static const Map<AppSoundToneType, _ToneSettingKeys> _toneKeys = {
    AppSoundToneType.outgoingCall: _ToneSettingKeys(
      toneIdKey: 'call_tone_id',
      customUrlKey: 'custom_call_tone_url',
      customNameKey: 'custom_call_tone_name',
      clearPayloadKey: 'clear_custom_call_tone',
      uploadType: 'outgoing_call',
    ),
    AppSoundToneType.incomingCall: _ToneSettingKeys(
      toneIdKey: 'incoming_tone_id',
      customUrlKey: 'custom_incoming_tone_url',
      customNameKey: 'custom_incoming_tone_name',
      clearPayloadKey: 'clear_custom_incoming_tone',
      uploadType: 'incoming_call',
    ),
    AppSoundToneType.message: _ToneSettingKeys(
      toneIdKey: 'message_tone_id',
      customUrlKey: 'custom_message_tone_url',
      customNameKey: 'custom_message_tone_name',
      clearPayloadKey: 'clear_custom_message_tone',
      uploadType: 'message',
    ),
    AppSoundToneType.typing: _ToneSettingKeys(
      toneIdKey: 'typing_tone_id',
      customUrlKey: 'custom_typing_tone_url',
      customNameKey: 'custom_typing_tone_name',
      clearPayloadKey: 'clear_custom_typing_tone',
      uploadType: 'typing',
    ),
  };

  final Map<AppSoundToneType, AppSoundToneState> _tones = {
    AppSoundToneType.outgoingCall: const AppSoundToneState(),
    AppSoundToneType.incomingCall: const AppSoundToneState(),
    AppSoundToneType.message: const AppSoundToneState(),
    AppSoundToneType.typing: const AppSoundToneState(),
  };

  int _repeatIntervalSeconds = 3;
  bool _isUploadingCustomTone = false;

  String get selectedToneId => _tones[AppSoundToneType.outgoingCall]!.toneId;
  int get repeatIntervalSeconds => _repeatIntervalSeconds;
  String get customToneUrl => _tones[AppSoundToneType.outgoingCall]!.customUrl;
  String get customToneName =>
      _tones[AppSoundToneType.outgoingCall]!.customName;
  bool get hasCustomTone => _tones[AppSoundToneType.outgoingCall]!.hasCustom;
  bool get isUploadingCustomTone => _isUploadingCustomTone;

  AppSoundToneState toneState(AppSoundToneType type) => _tones[type]!;

  RingtoneTone get selectedTone => availableTones.firstWhere(
    (tone) => tone.id == selectedToneId,
    orElse: () => availableTones.first,
  );

  CallSettingsProvider() {
    _load();
  }

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _repeatIntervalSeconds = prefs.getInt(_keyRepeatInterval) ?? 3;

    for (final entry in _toneKeys.entries) {
      final keys = entry.value;
      _tones[entry.key] = AppSoundToneState(
        toneId: _normalizeToneId(prefs.getString(keys.toneIdKey)),
        customUrl: _normalizeCustomToneUrl(prefs.getString(keys.customUrlKey)),
        customName: _normalizeCustomToneName(
          prefs.getString(keys.customNameKey),
        ),
      );
    }

    notifyListeners();
    await _syncToneFromServer();
  }

  Future<void> setTone(String toneId) async {
    await setToneFor(AppSoundToneType.outgoingCall, toneId);
  }

  Future<void> setToneFor(AppSoundToneType type, String toneId) async {
    final keys = _toneKeys[type]!;
    _tones[type] = _tones[type]!.copyWith(toneId: _normalizeToneId(toneId));
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keys.toneIdKey, _tones[type]!.toneId);
    await _saveToneToServer(type);
  }

  Future<void> setRepeatInterval(int seconds) async {
    _repeatIntervalSeconds = seconds.clamp(1, 30);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyRepeatInterval, _repeatIntervalSeconds);
  }

  Future<void> uploadCustomTone({
    required String fileName,
    Uint8List? bytes,
    String? path,
  }) async {
    await uploadCustomToneFor(
      type: AppSoundToneType.outgoingCall,
      fileName: fileName,
      bytes: bytes,
      path: path,
    );
  }

  Future<void> uploadCustomToneFor({
    required AppSoundToneType type,
    required String fileName,
    Uint8List? bytes,
    String? path,
  }) async {
    if ((bytes == null || bytes.isEmpty) && (path == null || path.isEmpty)) {
      throw Exception('No ringtone file selected.');
    }

    _isUploadingCustomTone = true;
    notifyListeners();

    try {
      final token = await _getToken();
      final authHeader = (!kIsWeb && token != null)
          ? <String, String>{'Authorization': 'Bearer $token'}
          : null;

      final fileBytes = bytes;
      if (fileBytes == null || fileBytes.isEmpty) {
        throw Exception(
          'Selected file bytes are empty. Please pick the file again.',
        );
      }

      final uploadUrl = type == AppSoundToneType.outgoingCall
          ? _uploadOutgoingUrl
          : _uploadMultiSoundUrl;

      final payloadFields = <String, String>{};
      if (type != AppSoundToneType.outgoingCall) {
        payloadFields['tone_type'] = _toneKeys[type]!.uploadType;
      }

      final response = await uploadMultipartPost(
        url: uploadUrl,
        fieldName: 'tone',
        bytes: fileBytes,
        filename: fileName,
        contentType: _audioMediaType(fileName),
        extraHeaders: authHeader,
        fields: payloadFields,
      ).timeout(const Duration(seconds: 30));

      final body = await response.stream.bytesToString();
      if (response.statusCode != 200) {
        String? message;
        try {
          final decoded = jsonDecode(body);
          if (decoded is Map<String, dynamic>) {
            message = decoded['message']?.toString();
          }
        } catch (_) {}
        throw Exception(
          message ?? 'Upload failed (HTTP ${response.statusCode}).',
        );
      }

      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw Exception('Unexpected upload response.');
      }

      await _syncToneFromServer();
    } finally {
      _isUploadingCustomTone = false;
      notifyListeners();
    }
  }

  static MediaType? _audioMediaType(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    const map = <String, String>{
      'mp3': 'audio/mpeg',
      'mp4': 'audio/mp4',
      'ogg': 'audio/ogg',
      'webm': 'audio/webm',
      'aac': 'audio/aac',
      'wav': 'audio/wav',
      'm4a': 'audio/x-m4a',
    };
    final mimeStr = map[ext];
    if (mimeStr == null) return null;
    return MediaType.parse(mimeStr);
  }

  Future<void> clearCustomTone() async {
    await clearCustomToneFor(AppSoundToneType.outgoingCall);
  }

  Future<void> clearCustomToneFor(AppSoundToneType type) async {
    final token = await _getToken();
    final payloadKey = _toneKeys[type]!.clearPayloadKey;
    final response = await sendJsonPost(
      _updateSettingsUrl,
      {payloadKey: true},
      extraHeaders: token != null ? {'Authorization': 'Bearer $token'} : null,
    ).timeout(const Duration(seconds: 5));

    if (response.statusCode != 200) {
      throw Exception('Failed to remove custom ringtone.');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Unexpected remove response.');
    }

    final settings = decoded['data'];
    if (settings is! Map<String, dynamic>) {
      throw Exception('Remove did not return settings.');
    }

    await _applyRemoteSettings(settings);
  }

  String _normalizeToneId(String? toneId) {
    final normalizedToneId = toneId ?? 'default';
    return availableTones.any((tone) => tone.id == normalizedToneId)
        ? normalizedToneId
        : 'default';
  }

  String _normalizeCustomToneUrl(String? toneUrl) {
    final raw = toneUrl?.trim() ?? '';
    if (raw.isEmpty) return '';

    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return raw;
    }

    final apiUri = Uri.parse(kAdminApiBaseUrl);
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

    final basePath = apiUri.path.endsWith('/')
        ? apiUri.path
        : '${apiUri.path}/';
    return '$origin$basePath$raw';
  }

  String _normalizeCustomToneName(String? toneName) => toneName?.trim() ?? '';

  Future<void> _persistRemoteSettings() async {
    final prefs = await SharedPreferences.getInstance();
    for (final entry in _toneKeys.entries) {
      final state = _tones[entry.key]!;
      final keys = entry.value;
      await prefs.setString(keys.toneIdKey, state.toneId);
      await prefs.setString(keys.customUrlKey, state.customUrl);
      await prefs.setString(keys.customNameKey, state.customName);
    }
  }

  Future<void> _applyRemoteSettings(Map<String, dynamic> settings) async {
    bool hasChanged = false;

    for (final entry in _toneKeys.entries) {
      final type = entry.key;
      final keys = entry.value;
      final current = _tones[type]!;

      final remote = AppSoundToneState(
        toneId: _normalizeToneId(settings[keys.toneIdKey]?.toString()),
        customUrl: _normalizeCustomToneUrl(
          settings[keys.customUrlKey]?.toString(),
        ),
        customName: _normalizeCustomToneName(
          settings[keys.customNameKey]?.toString(),
        ),
      );

      if (remote.toneId != current.toneId ||
          remote.customUrl != current.customUrl ||
          remote.customName != current.customName) {
        hasChanged = true;
      }

      _tones[type] = remote;
    }

    await _persistRemoteSettings();

    if (hasChanged) {
      notifyListeners();
    }
  }

  Future<void> _syncToneFromServer() async {
    try {
      final response = await http
          .get(Uri.parse(_settingsUrl))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return;

      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic>) return;

      final settings = data['data'];
      if (settings is! Map<String, dynamic>) return;

      await _applyRemoteSettings(settings);
    } catch (e) {
      debugPrint('Error loading remote tone settings: ${e.runtimeType} - $e');
    }
  }

  Future<void> _saveToneToServer(AppSoundToneType type) async {
    try {
      final token = await _getToken();
      final toneKey = _toneKeys[type]!.toneIdKey;
      final response = await sendJsonPost(
        _updateSettingsUrl,
        {toneKey: _tones[type]!.toneId},
        extraHeaders: token != null ? {'Authorization': 'Bearer $token'} : null,
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) return;

      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic>) return;

      final settings = data['data'];
      if (settings is! Map<String, dynamic>) return;

      await _applyRemoteSettings(settings);
    } catch (e) {
      debugPrint('Error saving remote tone settings: ${e.runtimeType} - $e');
    }
  }
}
