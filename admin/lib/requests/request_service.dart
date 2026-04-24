import 'dart:convert';
import 'dart:developer' as developer;
import 'package:adminmrz/config/app_endpoints.dart';
import 'package:adminmrz/dashboard/dashservice.dart' show UnauthorizedException;
import 'package:adminmrz/requests/request_model.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class RequestService {
  static const String _baseUrl = kAdminApi9BaseUrl;

  Future<Map<String, String>> _authHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<RequestsResponse> getRequests({
    int page = 1,
    int perPage = 20,
    String status = 'all',
    String search = '',
  }) async {
    final params = <String, String>{
      'page': page.toString(),
      'per_page': perPage.toString(),
      if (status != 'all') 'status': status,
      if (search.isNotEmpty) 'search': search,
    };

    final uri = Uri.parse('$_baseUrl/get_requests.php')
        .replace(queryParameters: params);

    final response = await http.get(uri, headers: await _authHeaders());

    developer.log(
      'getRequests [${response.statusCode}]: ${response.body}',
      name: 'RequestService',
    );

    if (response.statusCode == 401) throw const UnauthorizedException();

    if (response.statusCode == 200) {
      final decoded = json.decode(response.body) as Map<String, dynamic>;
      // Support both res.data and res.data.data wrapping
      final payload = decoded['data'] is Map<String, dynamic>
          ? decoded['data'] as Map<String, dynamic>
          : decoded;
      return RequestsResponse.fromJson(payload);
    }

    throw Exception('Failed to load requests: ${response.statusCode}');
  }

  Future<bool> updateRequestStatus({
    required int requestId,
    required String action,
  }) async {
    final uri = Uri.parse('$_baseUrl/update_request_status.php');

    final response = await http.post(
      uri,
      headers: await _authHeaders(),
      body: json.encode({'request_id': requestId, 'action': action}),
    );

    if (response.statusCode == 401) throw const UnauthorizedException();

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data['success'] == true;
    }

    throw Exception(
        'Failed to update request status: ${response.statusCode}');
  }
}
