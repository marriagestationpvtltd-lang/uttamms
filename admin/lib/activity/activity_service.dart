import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'activity_model.dart';
import 'package:adminmrz/config/app_endpoints.dart';

class ActivityService {
  static const String _baseUrl = kAdminApi9BaseUrl;

  Future<Map<String, String>> _authHeaders() async {
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
      'page':  page.toString(),
      'limit': limit.toString(),
    };
    if (userId != null)       queryParams['user_id']       = userId.toString();
    if (activityType != null) queryParams['activity_type'] = activityType;
    if (dateFrom != null)     queryParams['date_from']     = dateFrom;
    if (dateTo != null)       queryParams['date_to']       = dateTo;
    if (search != null && search.isNotEmpty) queryParams['search'] = search;

    final uri = Uri.parse('$_baseUrl/get_user_activities.php')
        .replace(queryParameters: queryParams);

    final response = await http.get(uri, headers: await _authHeaders());

    if (response.statusCode == 200) {
      final data = json.decode(response.body) as Map<String, dynamic>;
      return ActivityFeedResponse.fromJson(data);
    }
    throw Exception('Failed to load activities: ${response.statusCode}');
  }
}
