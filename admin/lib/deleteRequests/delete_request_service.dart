import 'dart:convert';
import 'dart:developer' as developer;
import 'package:adminmrz/config/app_endpoints.dart';
import 'package:adminmrz/dashboard/dashservice.dart' show UnauthorizedException;
import 'package:adminmrz/deleteRequests/delete_request_model.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class DeleteRequestService {
  static final String _base = kAdminApi9BaseUrl;

  Future<Map<String, String>> _headers() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<
    ({
      List<DeleteRequestItem> items,
      DeleteRequestStats stats,
      int total,
      int totalPages,
    })
  >
  getRequests({
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

    final uri = Uri.parse(
      '$_base/get_delete_requests.php',
    ).replace(queryParameters: params);

    final response = await http.get(uri, headers: await _headers());

    developer.log(
      'getDeleteRequests [${response.statusCode}]: ${response.body}',
      name: 'DeleteRequestService',
    );

    if (response.statusCode == 401) throw const UnauthorizedException();
    if (response.statusCode != 200) {
      throw Exception('Failed to load delete requests: ${response.statusCode}');
    }

    final decoded = json.decode(response.body) as Map<String, dynamic>;
    final data = decoded['data'] as Map<String, dynamic>;

    final items = (data['requests'] as List)
        .map((e) => DeleteRequestItem.fromJson(e as Map<String, dynamic>))
        .toList();

    final stats = DeleteRequestStats.fromJson(
      data['stats'] as Map<String, dynamic>,
    );

    final pag = data['pagination'] as Map<String, dynamic>;
    final total = pag['total'] is int
        ? pag['total'] as int
        : int.tryParse(pag['total'].toString()) ?? 0;
    final totalPages = pag['total_pages'] is int
        ? pag['total_pages'] as int
        : int.tryParse(pag['total_pages'].toString()) ?? 1;

    return (items: items, stats: stats, total: total, totalPages: totalPages);
  }

  /// [action] is either "approve" or "reject".
  Future<void> resolveRequest({
    required int requestId,
    required String action,
    String adminNote = '',
  }) async {
    final response = await http.post(
      Uri.parse('$_base/resolve_delete_request.php'),
      headers: await _headers(),
      body: json.encode({
        'request_id': requestId,
        'action': action,
        if (adminNote.isNotEmpty) 'admin_note': adminNote,
      }),
    );

    developer.log(
      'resolveDeleteRequest [${response.statusCode}]: ${response.body}',
      name: 'DeleteRequestService',
    );

    if (response.statusCode == 401) throw const UnauthorizedException();

    final decoded = json.decode(response.body) as Map<String, dynamic>;
    if (decoded['success'] != true) {
      throw Exception(decoded['message'] ?? 'Failed to resolve request');
    }
  }
}
