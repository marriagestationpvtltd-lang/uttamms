import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/call_settings_model.dart';
import '../services/call_settings_service.dart';

/// State management for the Call Settings feature.
///
/// Responsibilities:
///   - Load the user's current settings and the available ringtone list.
///   - Update the chosen system ringtone.
///   - Toggle custom-tone mode on/off.
///   - Upload a new custom tone file.
///   - Resolve the ringtone for an outgoing/incoming call.
class CallSettingsProvider extends ChangeNotifier {
  final CallSettingsService _service;

  CallSettingsProvider({CallSettingsService? service})
      : _service = service ?? CallSettingsService();

  // -------------------------------------------------------------------------
  // State
  // -------------------------------------------------------------------------

  bool _isLoading = false;
  String? _error;
  CallSettingsModel? _settings;

  // -------------------------------------------------------------------------
  // Getters
  // -------------------------------------------------------------------------

  bool get isLoading           => _isLoading;
  String? get error            => _error;
  CallSettingsModel? get settings => _settings;

  /// Convenience: the ringtone list from settings (empty until loaded).
  List<RingtoneModel> get ringtones => _settings?.ringtones ?? [];

  // -------------------------------------------------------------------------
  // Load
  // -------------------------------------------------------------------------

  Future<void> loadSettings(String userId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    final response = await _service.fetchSettings(userId);

    _isLoading = false;
    if (response.isSuccess && response.data != null) {
      _settings = response.data;
    } else {
      _error = response.error ?? 'Failed to load call settings';
    }
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Select system ringtone
  // -------------------------------------------------------------------------

  Future<bool> selectRingtone({
    required String userId,
    required String ringtoneId,
  }) async {
    final response = await _service.updateSettings(
      userId:     userId,
      ringtoneId: ringtoneId,
      isCustom:   false,
    );

    if (response.isSuccess) {
      // Reload to get the updated URL / name from the server
      await loadSettings(userId);
      return true;
    }

    _error = response.error ?? 'Failed to select ringtone';
    notifyListeners();
    return false;
  }

  // -------------------------------------------------------------------------
  // Enable / disable custom tone
  // -------------------------------------------------------------------------

  Future<bool> setCustomMode({
    required String userId,
    required bool enabled,
  }) async {
    final response = await _service.updateSettings(
      userId:   userId,
      isCustom: enabled,
    );

    if (response.isSuccess) {
      await loadSettings(userId);
      return true;
    }

    _error = response.error ?? 'Failed to update custom mode';
    notifyListeners();
    return false;
  }

  // -------------------------------------------------------------------------
  // Upload custom tone
  // -------------------------------------------------------------------------

  Future<bool> uploadCustomTone({
    required String userId,
    required File file,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    final response = await _service.uploadCustomTone(
      userId: userId,
      file:   file,
    );

    _isLoading = false;
    if (response.isSuccess) {
      await loadSettings(userId);
      return true;
    }

    _error = response.error ?? 'Failed to upload custom tone';
    notifyListeners();
    return false;
  }

  // -------------------------------------------------------------------------
  // Resolve ringtone for a call (does not update state)
  // -------------------------------------------------------------------------

  Future<CallRingtoneModel?> resolveCallRingtone({
    required String callerId,
    required String receiverId,
  }) async {
    final response = await _service.getCallRingtone(
      callerId:   callerId,
      receiverId: receiverId,
    );
    if (response.isSuccess) return response.data;
    _error = response.error;
    notifyListeners();
    return null;
  }

  // -------------------------------------------------------------------------
  // Error management
  // -------------------------------------------------------------------------

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
