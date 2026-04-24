import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:adminmrz/config/app_endpoints.dart';

class AuthProvider with ChangeNotifier {
  String? _token;
  Map<String, dynamic>? _adminData;
  bool _isLoading = false;
  String? _error;

  String? get token => _token;
  Map<String, dynamic>? get adminData => _adminData;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAuthenticated => _token != null;

  AuthProvider() {
    _loadToken();
  }

  Future<void> _loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('token');
    final adminDataString = prefs.getString('adminData');
    if (adminDataString != null) {
      _adminData = json.decode(adminDataString);
    }
    notifyListeners();
  }

  // Method 1: Try with CORS mode first
  Future<bool> login(String email, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final url = Uri.parse('$kAdminApi9BaseUrl/login.php');
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: json.encode({
          'email': email,
          'password': password,
        }),
      );


      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);

        if (responseData['success'] == true) {
          _token = responseData['data']['token'];
          _adminData = responseData['data']['admin'];

          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('token', _token!);
          await prefs.setString('adminData', json.encode(_adminData));

          _isLoading = false;
          notifyListeners();
          return true;
        } else {
          _error = responseData['message'] ?? 'Login failed';
          _isLoading = false;
          notifyListeners();
          return false;
        }
      } else {
        _error = 'Server error: ${response.statusCode}\n${response.body}';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {

      // Try alternative method if first fails
      return await _loginWithAlternativeMethod(email, password);
    }
  }

  // Method 2: Alternative approach for CORS issues
  Future<bool> _loginWithAlternativeMethod(String email, String password) async {
    try {
      final url = Uri.parse('$kAdminApi9BaseUrl/login.php');

      // Create a more compatible request
      final request = http.Request('POST', url);
      request.headers['Content-Type'] = 'application/json';
      request.body = json.encode({
        'email': email,
        'password': password,
      });

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);

        if (responseData['success'] == true) {
          _token = responseData['data']['token'];
          _adminData = responseData['data']['admin'];

          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('token', _token!);
          await prefs.setString('adminData', json.encode(_adminData));

          _isLoading = false;
          notifyListeners();
          return true;
        }
      }

      _error = 'Failed to connect. Please check CORS settings.';
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _error = 'Network error: Please ensure CORS is enabled on the server.\nError: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // Method 3: Using a proxy (if you have one)
  Future<bool> _loginWithProxy(String email, String password) async {
    try {
      // If you have a proxy server, use it here
      final proxyUrl = Uri.parse('https://cors-anywhere.herokuapp.com/$kAdminApi9BaseUrl/login.php');

      final response = await http.post(
        proxyUrl,
        headers: {
          'Content-Type': 'application/json',
          'x-requested-with': 'XMLHttpRequest',
        },
        body: json.encode({
          'email': email,
          'password': password,
        }),
      );

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);

        if (responseData['success'] == true) {
          _token = responseData['data']['token'];
          _adminData = responseData['data']['admin'];

          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('token', _token!);
          await prefs.setString('adminData', json.encode(_adminData));

          _isLoading = false;
          notifyListeners();
          return true;
        }
      }

      return false;
    } catch (e) {
      return false;
    }
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('adminData');

    _token = null;
    _adminData = null;
    notifyListeners();
  }
}