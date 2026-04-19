// lib/models/signup_model.dart
import 'dart:convert';
import 'dart:io' show File;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ms2026/config/app_endpoints.dart';

class SignupModel extends ChangeNotifier {
  // Fields matching your payload keys
  String email = '';
  String password = '';
  String contactNo = '';
  String firstName = '';
  String lastName = '';
  String languages = '';      // note: API payload uses "Languages" in your JSON example
  String nationality = '';
  String gender = '';
  String dateofbirth = '';    // API expects 'dateofbirth' (yyyy-mm-dd)
  int profileforId = 1;

  // Local-only UI items
  File? profilePictureFile;
  /// Used on web where [File] from dart:io is unavailable.
  XFile? profilePictureXFile;

  // State
  bool isSubmitting = false;
  String? error;
  Map<String, dynamic>? lastResponseData;
  String? bearerToken;

  // Setters (call from your UI onChanged / pick)
  void setEmail(String v) { email = v; notifyListeners(); }
  void setPassword(String v) { password = v; notifyListeners(); }
  void setContactNo(String v) { contactNo = v; notifyListeners(); }
  void setFirstName(String v) { firstName = v; notifyListeners(); }
  void setLastName(String v) { lastName = v; notifyListeners(); }
  void setLanguages(String v) { languages = v; notifyListeners(); }
  void setNationality(String v) { nationality = v; notifyListeners(); }
  void setGender(String v) { gender = v; notifyListeners(); }
  void setDateOfBirth(String v) { dateofbirth = v; notifyListeners(); }
  void setProfileForId(int v) { profileforId = v; notifyListeners(); }
  void setProfilePicture(File? f) { profilePictureFile = f; notifyListeners(); }
  void setProfilePictureXFile(XFile? x) { profilePictureXFile = x; profilePictureFile = kIsWeb ? null : (x != null ? File(x.path) : null); notifyListeners(); }

  // Clear possible previous error
  void clearError() { error = null; notifyListeners(); }

  // Build extra fields map if needed
  Map<String, String> _textFieldsForApi() {
    return {
      'email': email,
      'password': password,
      'contactNo': contactNo,
      'firstName': firstName,
      'lastName': lastName,
      // API in your example used "Languages" capitalized
      'Languages': languages,
      'Nationality': nationality,
      'gender': gender,
      'dateofbirth': dateofbirth,
      'profileforId': profileforId.toString(),
    };
  }

  /// LOGOUT USER
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();

    // Clear SharedPreferences
    await prefs.remove('bearer_token');
    await prefs.remove('user_data');
    await prefs.remove('user_firstName');
    await prefs.remove('user_lastName');
    await prefs.remove('user_email');
    await prefs.remove('user_contactNo');

    // OPTIONAL: clear everything (use only if safe)
    // await prefs.clear();

    // Reset model fields
    email = '';
    password = '';
    contactNo = '';
    firstName = '';
    lastName = '';
    languages = '';
    nationality = '';
    gender = '';
    dateofbirth = '';
    profileforId = 1;

    profilePictureFile = null;

    bearerToken = null;
    lastResponseData = null;
    error = null;
    isSubmitting = false;

    notifyListeners();
  }


  /// Submit multipart/form-data to signup endpoint
  Future<bool> submitSignup({String url = '${kApiBaseUrl}/Api2/signup.php'}) async {
    isSubmitting = true;
    error = null;
    notifyListeners();

    try {
      final uri = Uri.parse(url);
      final req = http.MultipartRequest('POST', uri);

      // Add text fields
      req.fields.addAll(_textFieldsForApi());

      // Add profile picture if present (cross-platform bytes approach)
      if (kIsWeb && profilePictureXFile != null) {
        final bytes = await profilePictureXFile!.readAsBytes();
        final fileName = profilePictureXFile!.name;
        req.files.add(http.MultipartFile.fromBytes(
          'profile_picture',
          bytes,
          filename: fileName,
        ));
      } else if (!kIsWeb && profilePictureFile != null && await profilePictureFile!.exists()) {
        final stream = http.ByteStream(profilePictureFile!.openRead());
        final length = await profilePictureFile!.length();
        final fileName = profilePictureFile!.path.split('/').last;
        final multipartFile = http.MultipartFile('profile_picture', stream, length, filename: fileName);
        req.files.add(multipartFile);
      }

      final streamedResp = await req.send();
      final resp = await http.Response.fromStream(streamedResp);

      // parse response
      final body = resp.body;
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final parsed = _tryParseJson(body);
        lastResponseData = parsed;

        // if API returns bearer_token field, store it
        if (parsed != null && parsed['bearer_token'] != null) {
          bearerToken = parsed['bearer_token'].toString();

          // ALSO UPDATE MODEL FIELDS FROM RESPONSE DATA
          if (parsed['data'] != null) {
            await _updateModelFromResponse(parsed['data']);
          }

          // Save to SharedPreferences
          await _saveToPrefs(bearerToken!, parsed['data']);
        }

        isSubmitting = false;
        notifyListeners();
        return true;
      } else {
        // server returned error status
        error = 'Server error: ${resp.statusCode}';
        final parsed = _tryParseJson(body);
        if (parsed != null && parsed['message'] != null) {
          error = '${parsed['message']} (status ${resp.statusCode})';
        }
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

  // NEW METHOD: Update model fields from API response
  Future<void> _updateModelFromResponse(Map<String, dynamic> data) async {
    // Update all fields from the API response
    if (data['email'] != null) email = data['email'].toString();
    if (data['contactNo'] != null) contactNo = data['contactNo'].toString();
    if (data['firstName'] != null) firstName = data['firstName'].toString();
    if (data['lastName'] != null) lastName = data['lastName'].toString();
    if (data['Languages'] != null) languages = data['Languages'].toString();
    if (data['Nationality'] != null) nationality = data['Nationality'].toString();
    if (data['gender'] != null) gender = data['gender'].toString();
    if (data['dateofbirth'] != null) dateofbirth = data['dateofbirth'].toString();
    if (data['profileforId'] != null) profileforId = int.tryParse(data['profileforId'].toString()) ?? 1;

    // Note: Don't update password from response for security

    notifyListeners();
  }


  Map<String, dynamic>? _tryParseJson(String s) {
    try {
      final j = jsonDecode(s);
      if (j is Map<String, dynamic>) return j;
      return null;
    } catch (_) {
      return null;
    }
  }


  Future<void> _saveToPrefs(String token, dynamic data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('bearer_token', token);

    // store data as JSON string
    if (data != null) {
      try {
        await prefs.setString('user_data', jsonEncode(data));
      } catch (_) {
        // ignore
      }
    }
    // ALSO save individual fields for quick access
    await prefs.setString('user_firstName', firstName);
    await prefs.setString('user_lastName', lastName);
    await prefs.setString('user_email', email);
    await prefs.setString('user_contactNo', contactNo);

  }
  // ALSO save individual fields for quick access


  // Helper to load saved token/data on app start (optional)
  static Future<Map<String, dynamic>?> loadSavedUser() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('bearer_token');
    final dataS = prefs.getString('user_data');
    if (token == null || dataS == null) return null;
    try {
      final data = jsonDecode(dataS);
      return {'token': token, 'data': data};
    } catch (_) {
      return {'token': token};
    }
  }

  // Load saved user data into model
  Future<void> loadUserData() async {
    final savedData = await loadSavedUser();

    if (savedData != null && savedData['data'] != null) {
      final data = savedData['data'] as Map<String, dynamic>;
      await _updateModelFromResponse(data);

      // Also set bearer token
      bearerToken = savedData['token']?.toString();
    }

    notifyListeners();
  }
}
