import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../config/app_endpoints.dart';

/// Thin fire-and-forget service for logging user activity.
///
/// Callers should NOT await responses from these methods unless they
/// specifically need confirmation – activity logging must never block the UI.
///
/// Usage:
///   ActivityService.instance.log(
///     userId:       currentUserId,
///     activityType: ActivityType.profileView,
///     targetUserId: viewedUserId,
///   );
class ActivityService {
  ActivityService._();
  static final ActivityService instance = ActivityService._();

  // ---------------------------------------------------------------------------
  // Log
  // ---------------------------------------------------------------------------

  /// Send an activity log entry to the server.
  ///
  /// Returns `true` on success, `false` on any failure.
  /// Errors are swallowed so that a logging failure never crashes the app.
  Future<bool> log({
    required String userId,
    required String activityType,
    String? description,
    String? targetUserId,
    String? deviceInfo,
  }) async {
    try {
      final body = <String, dynamic>{
        'user_id':       userId,
        'activity_type': activityType,
      };
      if (description  != null) body['description']    = description;
      if (targetUserId != null) body['target_user_id'] = targetUserId;
      if (deviceInfo   != null) body['device_info']    = deviceInfo;

      final response = await http
          .post(
            Uri.parse(kEndpointLogActivity),
            headers: {'Content-Type': 'application/json; charset=UTF-8'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 10));

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return json['success'] == true;
    } catch (_) {
      // Logging failures must never surface to the user
      return false;
    }
  }
}

// =============================================================================
// Activity type constants  (mirror the ENUM in the DB)
// =============================================================================

abstract class ActivityType {
  static const String login               = 'login';
  static const String logout              = 'logout';
  static const String profileView         = 'profile_view';
  static const String search              = 'search';
  static const String proposalSent        = 'proposal_sent';
  static const String proposalAccepted    = 'proposal_accepted';
  static const String proposalRejected    = 'proposal_rejected';
  static const String callInitiated       = 'call_initiated';
  static const String callReceived        = 'call_received';
  static const String callEnded           = 'call_ended';
  static const String customToneSet       = 'custom_tone_set';
  static const String customToneRemoved   = 'custom_tone_removed';
  static const String settingsChanged     = 'settings_changed';
  static const String other               = 'other';
}
