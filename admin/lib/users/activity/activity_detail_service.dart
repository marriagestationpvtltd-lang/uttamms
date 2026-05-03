import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:adminmrz/config/app_endpoints.dart';
import 'activity_detail_model.dart';

class ActivityDetailService {
  static final String _base = kAdminApi9BaseUrl;

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  Future<ActivityDetailPage> fetchSection({
    required int userId,
    required ActivitySection section,
    int page = 1,
    int limit = 30,
  }) async {
    try {
      final token = await _getToken();
      final uri = Uri.parse(
        '$_base/get_member_activity_detail.php'
        '?userid=$userId&section=${section.key}&page=$page&limit=$limit',
      );
      final response = await http
          .get(
            uri,
            headers: {
              'Accept': 'application/json',
              if (!kIsWeb && token != null) 'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          return ActivityDetailPage.fromJson(data);
        }
      }
      debugPrint('fetchSection error: HTTP ${response.statusCode}');
      return _emptyPage(section);
    } catch (e) {
      debugPrint('fetchSection exception: $e');
      return _emptyPage(section);
    }
  }

  ActivityDetailPage _emptyPage(ActivitySection section) => ActivityDetailPage(
    section: section.key,
    total: 0,
    page: 1,
    totalPages: 1,
    items: [],
  );
}
