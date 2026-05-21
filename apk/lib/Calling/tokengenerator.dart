// tokengenerator.dart
import 'dart:convert';
import 'dart:async';
import 'package:ms2026/service/auth_http_client.dart' as http;
import 'package:ms2026/config/app_endpoints.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

class AgoraTokenService {
  static const String tokenUrl = '$kApiBaseUrl/Api2/test_token.php';
  static const String appId =
      '7750d283e6794eebba06e7d021e8a01c'; // Your Agora App ID
  static const int _kMaxTokenAttempts = 3;
  static const Duration _kTokenTimeout = Duration(seconds: 20);

  /// Fetches an Agora token from your PHP server.
  /// [channelName] - name of the Agora channel
  /// [uid] - integer user ID
  /// [expireTime] - token expiry in seconds
  /// [isStringUid] - true if you want server to generate string UID token
  static Future<String> getToken({
    required String channelName,
    required int uid,
    required String userId,
    String callType = 'audio',
    int expireTime = 3600,
    bool isStringUid = false,
  }) async {
    try {
      String effectiveUserId = userId.trim();
      if (effectiveUserId.isEmpty) {
        final prefs = await SharedPreferences.getInstance();
        final userDataString = prefs.getString('user_data');
        if (userDataString != null && userDataString.isNotEmpty) {
          final userData = json.decode(userDataString);
          if (userData is Map<String, dynamic>) {
            effectiveUserId = userData['id']?.toString() ??
                userData['userid']?.toString() ??
                userData['userId']?.toString() ??
                '';
          }
        }
      }

      if (effectiveUserId.isEmpty) {
        throw Exception('userId is empty for token request');
      }

      final uri = Uri.parse(tokenUrl).replace(queryParameters: {
        'channelName': channelName,
        'uid': uid.toString(),
        'userId': effectiveUserId,
        'userid': effectiveUserId,
        'userld': effectiveUserId,
        'callType': callType,
        'expireTime': expireTime.toString(),
        'isStringUid': isStringUid ? '1' : '0',
      });

      debugPrint('🌐 Fetching token: $uri');

      Object? lastError;
      for (var attempt = 1; attempt <= _kMaxTokenAttempts; attempt++) {
        try {
          final response = await http.get(
            uri,
            headers: {'Content-Type': 'application/json'},
          ).timeout(_kTokenTimeout);

          debugPrint(
              '📡 Token response status (attempt $attempt): ${response.statusCode}');

          if (response.statusCode != 200) {
            // Retry for transient server-side conditions.
            if (attempt < _kMaxTokenAttempts && response.statusCode >= 500) {
              await Future.delayed(Duration(milliseconds: 700 * attempt));
              continue;
            }
            throw Exception('HTTP ${response.statusCode}: ${response.body}');
          }

          final result = json.decode(response.body);

          if (result is! Map<String, dynamic>) {
            throw Exception('Invalid response format');
          }

          if (result['success'] != true) {
            throw Exception(
                'Token failed: ${result['error'] ?? 'Unknown error'}');
          }

          final token = result['data'];
          if (token == null || token is! String) {
            throw Exception('Token is missing or invalid in API response');
          }

          debugPrint(
              '✅ Token received: ${token.length} chars (attempt $attempt)');
          return token;
        } catch (e) {
          lastError = e;
          final isRetriable = e is TimeoutException ||
              e.toString().toLowerCase().contains('socket') ||
              e.toString().toLowerCase().contains('connection');
          if (!isRetriable || attempt == _kMaxTokenAttempts) {
            rethrow;
          }
          await Future.delayed(Duration(milliseconds: 700 * attempt));
        }
      }

      throw Exception('Token request failed: $lastError');
    } catch (e) {
      debugPrint('❌ Token error: $e');
      rethrow;
    }
  }

  /// Test function to verify token generation
  static Future<void> testTokenGeneration() async {
    try {
      const testChannel = 'test_call_123';
      const testUid = 12345;

      final token = await getToken(
        channelName: testChannel,
        uid: testUid,
        userId: testUid.toString(),
      );
      debugPrint('✅ Token test successful: ${token.substring(0, 30)}...');
    } catch (e) {
      debugPrint('❌ Token test failed: $e');
    }
  }
}
