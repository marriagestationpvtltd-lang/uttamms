import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'detailmodel.dart';
import 'package:adminmrz/config/app_endpoints.dart';

class UserDetailsService {
  static const String _baseUrl = '${kAdminApiBaseUrl}/Api2';
  static const String _adminBaseUrl = kAdminApi9BaseUrl;

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  Future<UserDetailsResponse> getUserDetails(int userId, int myId) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/other_profile.php?userid=$userId&myid=$myId'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return UserDetailsResponse.fromJson(data);
      } else {
        throw Exception('Failed to load user details: ${response.statusCode}');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Update a single field for a user profile from the admin panel.
  /// [userId] – target user's ID
  /// [section] – one of: 'personal', 'family', 'lifestyle', 'partner'
  /// [field]   – API field key (snake_case, matches backend column)
  /// [value]   – new value as string
  Future<bool> updateUserDetail({
    required int userId,
    required String section,
    required String field,
    required String value,
  }) async {
    try {
      final token = await _getToken();
      final response = await http.post(
        Uri.parse('$_adminBaseUrl/update_user_profile.php'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'userid': userId,
          'section': section,
          'field': field,
          'value': value,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['success'] == true || data['status'] == 'success';
      }
      return false;
    } catch (e) {
      debugPrint('updateUserDetail error: $e');
      return false;
    }
  }

  /// Fetch user activity stats (requests sent/received, chat requests, etc.)
  Future<ActivityStats> getUserActivity(int userId) async {
    try {
      final token = await _getToken();
      final response = await http.get(
        Uri.parse('$_adminBaseUrl/get_user_activity.php?userid=$userId'),
        headers: {
          'Accept': 'application/json',
          if (!kIsWeb && token != null) 'Authorization': 'Bearer $token',
        },
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final payload = data['data'] ?? data;
        return ActivityStats.fromJson(
          payload is Map<String, dynamic> ? payload : {},
        );
      }
      return ActivityStats.empty();
    } catch (e) {
      debugPrint('getUserActivity error: $e');
      return ActivityStats.empty();
    }
  }

  /// Approve or reject a user's pending profile photo.
  /// [action] – 'approve' or 'reject'
  /// [reason] – optional rejection reason
  Future<bool> handleProfilePhotoRequest({
    required int userId,
    required String action,
    String? reason,
  }) async {
    try {
      final token = await _getToken();
      final response = await http.post(
        Uri.parse('$_adminBaseUrl/approve_profile_photo.php'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'userid': userId,
          'action': action,
          if (reason != null && reason.isNotEmpty) 'reason': reason,
        }),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['success'] == true || data['status'] == 'success';
      }
      return false;
    } catch (e) {
      debugPrint('handleProfilePhotoRequest error: $e');
      return false;
    }
  }

  /// Send an admin notification directly to a user.
  Future<bool> sendAdminNotification({
    required int userId,
    required String title,
    required String message,
  }) async {
    try {
      final token = await _getToken();
      final response = await http.post(
        Uri.parse('$_adminBaseUrl/send_admin_notification.php'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'userid': userId,
          'title': title,
          'message': message,
        }),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['success'] == true || data['status'] == 'success';
      }
      return false;
    } catch (e) {
      debugPrint('sendAdminNotification error: $e');
      return false;
    }
  }
}
