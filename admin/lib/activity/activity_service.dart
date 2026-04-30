import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'activity_model.dart';
import 'package:adminmrz/config/app_endpoints.dart';
import 'package:adminmrz/dashboard/dashservice.dart' show UnauthorizedException;

class ActivityService {
  static const String _baseUrl = kAdminApi9BaseUrl;

  Future<Map<String, String>> _authHeaders() async {
    if (kIsWeb) {
      // Keep web GET requests simple to avoid CORS preflight failures.
      return {'Accept': 'application/json'};
    }
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    return {
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<ActivityFeedResponse> getActivities({
    int page = 1,
    int limit = 50,
    int? userId,
    String? activityType,
    String? dateFrom,
    String? dateTo,
    String? search,
  }) async {
    final queryParams = <String, String>{
      'page': page.toString(),
      'limit': limit.toString(),
    };
    if (userId != null) queryParams['user_id'] = userId.toString();
    if (activityType != null) queryParams['activity_type'] = activityType;
    if (dateFrom != null) queryParams['date_from'] = dateFrom;
    if (dateTo != null) queryParams['date_to'] = dateTo;
    if (search != null && search.isNotEmpty) queryParams['search'] = search;

    final uri = Uri.parse(
      '$_baseUrl/get_user_activities.php',
    ).replace(queryParameters: queryParams);

    final response = await http.get(uri, headers: await _authHeaders());

    developer.log(
      'getActivities [${response.statusCode}]: ${response.body}',
      name: 'ActivityService',
    );

    if (response.statusCode == 401) throw const UnauthorizedException();

    if (response.statusCode == 200) {
      final decoded = json.decode(response.body) as Map<String, dynamic>;
      // Determine success from the outer envelope before unwrapping.
      final outerSuccess =
          decoded['success'] == true || decoded['status'] == 'success';
      // Support both res.data and res.data.data wrapping
      final innerData = decoded['data'] is Map<String, dynamic>
          ? decoded['data'] as Map<String, dynamic>
          : decoded;
      // Merge the outer success flag into the payload so fromJson reads it correctly.
      final payload = <String, dynamic>{...innerData, 'success': outerSuccess};
      return ActivityFeedResponse.fromJson(payload);
    }
    throw Exception('Failed to load activities: ${response.statusCode}');
  }
}
