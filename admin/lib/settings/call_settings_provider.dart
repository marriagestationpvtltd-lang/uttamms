import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Platform-conditional multipart upload helper.
// On native (dart:io) it manually follows redirects to preserve POST.
// On web the browser's XHR layer is used unchanged.
import '_http_upload_stub.dart' if (dart.library.io) '_http_upload_io.dart';
import 'package:adminmrz/config/app_endpoints.dart';

/// Available ringtone options bundled with the app.
class RingtoneTone {
  final String id;
  final String label;
  final String asset; // relative to assets/

  const RingtoneTone({
    required this.id,
    required this.label,
    required this.asset,
  });
}

class CallSettingsProvider extends ChangeNotifier {
  static const _keyToneId = 'call_tone_id';
  static const _keyCustomToneUrl = 'custom_call_tone_url';
  static const _keyCustomToneName = 'custom_call_tone_name';
  static const _keyRepeatInterval = 'call_repeat_interval';
  static const _settingsUrl = '${kAdminApiBaseUrl}/Api2/app_settings.php';
  static const _updateSettingsUrl =
      '$kAdminApi9BaseUrl/update_app_settings.php';
  static const _uploadToneUrl = '$kAdminApi9BaseUrl/upload_call_tone.php';
  static const _uploadToneAltUrl =
      '${kAdminApiBaseUrl}/Api9/upload_call_tone.php';

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

  String _selectedToneId = 'default';
  int _repeatIntervalSeconds = 3;
  String _customToneUrl = '';
  String _customToneName = '';
  bool _isUploadingCustomTone = false;

  String get selectedToneId => _selectedToneId;
  int get repeatIntervalSeconds => _repeatIntervalSeconds;
  String get customToneUrl => _customToneUrl;
  String get customToneName => _customToneName;
  bool get hasCustomTone => _customToneUrl.isNotEmpty;
  bool get isUploadingCustomTone => _isUploadingCustomTone;

  RingtoneTone get selectedTone => availableTones.firstWhere(
    (tone) => tone.id == _selectedToneId,
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
    _selectedToneId = _normalizeToneId(prefs.getString(_keyToneId));
    _customToneUrl = _normalizeCustomToneUrl(
      prefs.getString(_keyCustomToneUrl),
    );
    _customToneName = _normalizeCustomToneName(
      prefs.getString(_keyCustomToneName),
    );
    _repeatIntervalSeconds = prefs.getInt(_keyRepeatInterval) ?? 3;
    notifyListeners();
    await _syncToneFromServer();
  }

  Future<void> setTone(String toneId) async {
    _selectedToneId = _normalizeToneId(toneId);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyToneId, _selectedToneId);
    await _saveToneToServer();
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
    if ((bytes == null || bytes.isEmpty) && (path == null || path.isEmpty)) {
      throw Exception('No ringtone file selected.');
    }

    _isUploadingCustomTone = true;
    notifyListeners();

    try {
      // Prefer in-memory bytes (always available with FilePicker withData:true).
      // Path-based uploads are kept as a fallback for native platforms only.
      Uint8List? fileBytes = (bytes != null && bytes.isNotEmpty) ? bytes : null;

      final token = await _getToken();
      final authHeader = token != null
          ? <String, String>{'Authorization': 'Bearer $token'}
          : null;

      // Some deployments expose /Api9 (capital A) instead of /api9.
      // Try Api9 first to avoid a noisy initial 500 on case-sensitive hosts.
      final uploadUrls = <String>{_uploadToneAltUrl, _uploadToneUrl}.toList();
      Map<String, dynamic>? decoded;
      int? lastStatusCode;
      String? lastMessage;

      for (final uploadUrl in uploadUrls) {
        late http.StreamedResponse response;

        if (fileBytes != null) {
          // Use the redirect-aware helper so that a server-side 301/302 redirect
          // does NOT silently convert POST → GET (which would cause the PHP
          // endpoint to return "Invalid request method.").
          response = await uploadMultipartPost(
            url: uploadUrl,
            fieldName: 'tone',
            bytes: fileBytes,
            filename: fileName,
            contentType: _audioMediaType(fileName),
            extraHeaders: authHeader,
          ).timeout(const Duration(seconds: 30));
        } else {
          // Fallback: path available but bytes were not pre-read (native only).
          final request = http.MultipartRequest('POST', Uri.parse(uploadUrl));
          if (authHeader != null) request.headers.addAll(authHeader);
          request.files.add(
            await http.MultipartFile.fromPath(
              'tone',
              path!,
              filename: fileName,
            ),
          );
          response = await request.send().timeout(const Duration(seconds: 30));
        }

        final body = await response.stream.bytesToString();
        lastStatusCode = response.statusCode;
        decoded = null;
        try {
          final raw = jsonDecode(body);
          if (raw is Map<String, dynamic>) decoded = raw;
        } catch (_) {
          decoded = null;
        }

        if (response.statusCode == 200 && decoded != null) {
          break;
        }

        lastMessage = decoded?['message']?.toString();
        debugPrint(
          'uploadCustomTone failed at $uploadUrl: '
          'status=${response.statusCode}, body=$body',
        );
      }

      if (decoded == null || lastStatusCode != 200) {
        if (lastStatusCode != null) {
          throw Exception(
            lastMessage ?? 'Upload failed (HTTP $lastStatusCode).',
          );
        }
        throw Exception(
          'Upload failed: server returned an unexpected response. '
          'Please try again or contact support.',
        );
      }

      final settings = decoded['data'];
      if (settings is! Map<String, dynamic>) {
        throw Exception('Upload did not return settings.');
      }

      await _applyRemoteSettings(settings);
    } finally {
      _isUploadingCustomTone = false;
      notifyListeners();
    }
  }

  /// Returns a [MediaType] for common audio extensions so the server can
  /// identify the content without relying solely on the file name.
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
    final token = await _getToken();
    final response = await sendJsonPost(
      _updateSettingsUrl,
      {'clear_custom_call_tone': true},
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

  String _normalizeCustomToneUrl(String? toneUrl) => toneUrl?.trim() ?? '';

  String _normalizeCustomToneName(String? toneName) => toneName?.trim() ?? '';

  Future<void> _persistRemoteSettings({
    required String toneId,
    required String customToneUrl,
    required String customToneName,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyToneId, toneId);
    await prefs.setString(_keyCustomToneUrl, customToneUrl);
    await prefs.setString(_keyCustomToneName, customToneName);
  }

  Future<void> _applyRemoteSettings(Map<String, dynamic> settings) async {
    final remoteToneId = _normalizeToneId(settings['call_tone_id']?.toString());
    final remoteCustomToneUrl = _normalizeCustomToneUrl(
      settings['custom_call_tone_url']?.toString(),
    );
    final remoteCustomToneName = _normalizeCustomToneName(
      settings['custom_call_tone_name']?.toString(),
    );

    final hasChanged =
        remoteToneId != _selectedToneId ||
        remoteCustomToneUrl != _customToneUrl ||
        remoteCustomToneName != _customToneName;

    _selectedToneId = remoteToneId;
    _customToneUrl = remoteCustomToneUrl;
    _customToneName = remoteCustomToneName;

    await _persistRemoteSettings(
      toneId: _selectedToneId,
      customToneUrl: _customToneUrl,
      customToneName: _customToneName,
    );

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
      debugPrint(
        'Error loading remote call tone settings: ${e.runtimeType} - $e',
      );
    }
  }

  Future<void> _saveToneToServer() async {
    try {
      final token = await _getToken();
      final response = await sendJsonPost(
        _updateSettingsUrl,
        {'call_tone_id': _selectedToneId},
        extraHeaders: token != null ? {'Authorization': 'Bearer $token'} : null,
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) return;

      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic>) return;

      final settings = data['data'];
      if (settings is! Map<String, dynamic>) return;

      await _applyRemoteSettings(settings);
    } catch (e) {
      debugPrint(
        'Error saving remote call tone settings: ${e.runtimeType} - $e',
      );
    }
  }
}
