import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../../../config/app_endpoints.dart';
import '../../../core/api/api_response.dart';
import '../models/call_settings_model.dart';

/// Service layer for the Call Settings feature.
///
/// Covers:
///   - Fetching the current user's settings + available ringtones in one call.
///   - Updating the chosen ringtone or toggling custom mode.
///   - Uploading a custom ringtone file.
///   - Resolving the correct ringtone for an incoming/outgoing call.
class CallSettingsService {
  // ---------------------------------------------------------------------------
  // Fetch settings + ringtone list
  // ---------------------------------------------------------------------------

  /// Fetch all call settings for [userId] together with the list of
  /// available system ringtones (one round-trip).
  Future<ApiResponse<CallSettingsModel>> fetchSettings(String userId) async {
    try {
      final url = Uri.parse(kEndpointCallSettings)
          .replace(queryParameters: {'user_id': userId});

      final response =
          await http.get(url).timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        return ApiResponse.error('Server returned ${response.statusCode}',
            statusCode: response.statusCode);
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      if (json['success'] != true) {
        return ApiResponse.error(json['message'] ?? 'Failed to fetch settings');
      }

      return ApiResponse.success(CallSettingsModel.fromJson(json));
    } catch (e) {
      return ApiResponse.error('Failed to fetch call settings: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Update settings
  // ---------------------------------------------------------------------------

  /// Update the user's call settings.
  ///
  /// Pass [ringtoneId] to select a system ringtone.
  /// Pass [isCustom] = true to activate the custom tone, false to deactivate.
  Future<ApiResponse<bool>> updateSettings({
    required String userId,
    String? ringtoneId,
    bool? isCustom,
  }) async {
    try {
      final body = <String, dynamic>{'user_id': userId};
      if (ringtoneId != null) body['ringtone_id'] = ringtoneId;
      if (isCustom != null)   body['is_custom']   = isCustom;

      final response = await http
          .post(
            Uri.parse(kEndpointCallSettings),
            headers: {'Content-Type': 'application/json; charset=UTF-8'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      if (json['success'] == true) return ApiResponse.success(true);
      return ApiResponse.error(json['message'] ?? 'Failed to update settings');
    } catch (e) {
      return ApiResponse.error('Failed to update call settings: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Upload custom tone
  // ---------------------------------------------------------------------------

  /// Upload [file] as the user's custom ringtone.
  ///
  /// Returns the [customToneUrl] stored on the server on success.
  Future<ApiResponse<String>> uploadCustomTone({
    required String userId,
    required File file,
  }) async {
    try {
      final uri = Uri.parse(kEndpointUploadCustomTone);
      final request = http.MultipartRequest('POST', uri)
        ..fields['user_id'] = userId
        ..files.add(await http.MultipartFile.fromPath('tone', file.path));

      final streamed  = await request.send().timeout(const Duration(seconds: 60));
      final response  = await http.Response.fromStream(streamed);
      final json      = jsonDecode(response.body) as Map<String, dynamic>;

      if (json['success'] == true) {
        return ApiResponse.success(json['custom_tone_url']?.toString() ?? '');
      }
      return ApiResponse.error(json['message'] ?? 'Failed to upload custom tone');
    } catch (e) {
      return ApiResponse.error('Failed to upload custom tone: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Resolve call ringtone
  // ---------------------------------------------------------------------------

  /// Resolve which ringtone should play when [callerId] calls [receiverId].
  Future<ApiResponse<CallRingtoneModel>> getCallRingtone({
    required String callerId,
    required String receiverId,
  }) async {
    try {
      final url = Uri.parse(kEndpointGetCallRingtone).replace(
          queryParameters: {'caller_id': callerId, 'receiver_id': receiverId});

      final response =
          await http.get(url).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        return ApiResponse.error('Server returned ${response.statusCode}',
            statusCode: response.statusCode);
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      if (json['success'] != true) {
        return ApiResponse.error(json['message'] ?? 'Failed to get ringtone');
      }

      return ApiResponse.success(CallRingtoneModel.fromJson(json));
    } catch (e) {
      return ApiResponse.error('Failed to get call ringtone: $e');
    }
  }
}
