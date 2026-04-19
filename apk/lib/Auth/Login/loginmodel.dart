import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ms2026/config/app_endpoints.dart';

class LoginModel extends ChangeNotifier {
  // Login fields
  String email = '';
  String password = '';

  // State
  bool isSubmitting = false;
  String? error;
  String? bearerToken;
  Map<String, dynamic>? userData;

  // Setters
  void setEmail(String v) { email = v; notifyListeners(); }
  void setPassword(String v) { password = v; notifyListeners(); }
  void clearError() { error = null; notifyListeners(); }

  // Login method
  Future<bool> login({String url = '${kApiBaseUrl}/Api2/signin.php'}) async {
    isSubmitting = true;
    error = null;
    notifyListeners();

    try {
      final uri = Uri.parse(url);
      final headers = {'Content-Type': 'application/json'};
      final body = jsonEncode({
        'email': email,
        'password': password,
      });

      final response = await http.post(
        uri,
        headers: headers,
        body: body,
      );

      final parsed = jsonDecode(response.body);

      if (response.statusCode == 200 && parsed['success'] == true) {
        bearerToken = parsed['bearer_token'];
        userData = parsed['data'];

        // Save to SharedPreferences
        await _saveToPrefs();

        isSubmitting = false;
        notifyListeners();
        return true;
      } else {
        error = parsed['message'] ?? 'Login failed (status ${response.statusCode})';
        isSubmitting = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      error = e.toString();
      isSubmitting = false;
      notifyListeners();
      return false;
    }
  }

  // Save user data to SharedPreferences
  Future<void> _saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();

    // Save token
    if (bearerToken != null) {
      await prefs.setString('bearer_token', bearerToken!);
    }

    // Save user data as JSON
    if (userData != null) {
      await prefs.setString('user_data', jsonEncode(userData));

      // Also save individual fields for quick access
      final data = userData!;
      await prefs.setInt('user_id', data['id'] ?? 0);
      await prefs.setString('user_email', data['email']?.toString() ?? '');
      await prefs.setString('user_firstName', data['firstName']?.toString() ?? '');
      await prefs.setString('user_lastName', data['lastName']?.toString() ?? '');
      await prefs.setString('user_contactNo', data['contactNo']?.toString() ?? '');
      await prefs.setString('user_profile_picture', data['profile_picture']?.toString() ?? '');

      // Set login status
      await prefs.setBool('is_logged_in', true);
      await prefs.setString('login_time', DateTime.now().toIso8601String());
    }
  }

  // Check if user is logged in
  static Future<bool> isUserLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('is_logged_in') == true &&
        prefs.getString('bearer_token') != null;
  }

  // Get saved user data
  static Future<Map<String, dynamic>?> getSavedUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final userDataJson = prefs.getString('user_data');

    if (userDataJson != null) {
      try {
        return jsonDecode(userDataJson);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  // Get bearer token
  static Future<String?> getBearerToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('bearer_token');
  }

  // Logout
  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('bearer_token');
    await prefs.remove('user_data');
    await prefs.remove('is_logged_in');
    await prefs.remove('user_id');
    await prefs.remove('user_email');
    await prefs.remove('user_firstName');
    await prefs.remove('user_lastName');
    await prefs.remove('user_contactNo');
    await prefs.remove('user_profile_picture');
    await prefs.remove('login_time');
  }

  // Load saved data into model
  Future<void> loadSavedData() async {
    final prefs = await SharedPreferences.getInstance();

    // Load email if available
    final savedEmail = prefs.getString('user_email');
    if (savedEmail != null) {
      email = savedEmail;
    }

    // Load token
    bearerToken = prefs.getString('bearer_token');

    // Load user data
    final userDataJson = prefs.getString('user_data');
    if (userDataJson != null) {
      try {
        userData = jsonDecode(userDataJson);
      } catch (_) {
        userData = null;
      }
    }

    notifyListeners();
  }
}