// tokengenerator.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:ms2026/config/app_endpoints.dart';

class AgoraTokenService {
  static const String tokenUrl = '${kApiBaseUrl}/Api2/test_token.php';
  static const String appId = '7750d283e6794eebba06e7d021e8a01c'; // Your Agora App ID

  /// Fetches an Agora token from your PHP server.
  /// [channelName] - name of the Agora channel
  /// [uid] - integer user ID
  /// [expireTime] - token expiry in seconds
  /// [isStringUid] - true if you want server to generate string UID token
  static Future<String> getToken({
    required String channelName,
    required int uid,
    int expireTime = 3600,
    bool isStringUid = false,
  }) async {
    try {
      final uri = Uri.parse(tokenUrl).replace(queryParameters: {
        'channelName': channelName,
        'uid': uid.toString(),
        'expireTime': expireTime.toString(),
        'isStringUid': isStringUid ? '1' : '0',
      });

      print('🌐 Fetching token: $uri');

      final response = await http.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      print('📡 Response status: ${response.statusCode}');
      print('📡 Response body: ${response.body}');

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }

      final result = json.decode(response.body);

      if (result is! Map<String, dynamic>) {
        throw Exception('Invalid response format');
      }

      if (result['success'] != true) {
        throw Exception('Token failed: ${result['error'] ?? 'Unknown error'}');
      }

      final token = result['data'];
      if (token == null || token is! String) {
        throw Exception('Token is missing or invalid in API response');
      }

      print('✅ Token received: ${token.length} chars');
      return token;
    } catch (e) {
      print('❌ Token error: $e');
      rethrow;
    }
  }

  /// Test function to verify token generation
  static Future<void> testTokenGeneration() async {
    try {
      const testChannel = 'test_call_123';
      const testUid = 12345;

      final token = await getToken(channelName: testChannel, uid: testUid);
      print('✅ Token test successful: ${token.substring(0, 30)}...');
    } catch (e) {
      print('❌ Token test failed: $e');
    }
  }
}
