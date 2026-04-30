import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../model/usermodel.dart';
import 'package:adminmrz/config/app_endpoints.dart';
import 'package:adminmrz/dashboard/dashservice.dart' show UnauthorizedException;

class UserService {
  static const String baseUrl = kAdminApi9BaseUrl;

  Future<Map<String, String>> _authHeaders() async {
    if (kIsWeb) {
      // Keep web GET requests simple to avoid CORS preflight failures.
      return {'Accept': 'application/json'};
    }
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<UserListResponse> getUsers() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/get_users.php'),
        headers: await _authHeaders(),
      );

      if (response.statusCode == 401) {
        throw const UnauthorizedException();
      }

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return UserListResponse.fromJson(data);
      } else {
        throw Exception('Failed to load users: ${response.statusCode}');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Suspend or unsuspend one or more users.
  /// [action] must be `'suspend'` or `'unsuspend'`.
  /// Returns a map with `'success'` (bool) and `'message'` (String).
  Future<Map<String, dynamic>> suspendUsers({
    required List<int> userIds,
    required String action,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/suspend_user.php'),
        headers: await _authHeaders(),
        body: json.encode({'user_ids': userIds, 'action': action}),
      );
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
      return {'success': false, 'message': 'HTTP ${response.statusCode}'};
    } catch (e) {
      debugPrint('UserService.suspendUsers error: $e');
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Soft-delete one or more users.
  /// Returns a map with `'success'` (bool) and `'message'` (String).
  Future<Map<String, dynamic>> deleteUsers({required List<int> userIds}) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/delete_user.php'),
        headers: await _authHeaders(),
        body: json.encode({'user_ids': userIds}),
      );
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
      return {'success': false, 'message': 'HTTP ${response.statusCode}'};
    } catch (e) {
      debugPrint('UserService.deleteUsers error: $e');
      return {'success': false, 'message': e.toString()};
    }
  }
}
