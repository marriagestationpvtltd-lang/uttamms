import 'dart:convert';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:adminmrz/config/app_endpoints.dart';
import 'package:adminmrz/dashboard/dashservice.dart' show UnauthorizedException;

// ─── Model ────────────────────────────────────────────────────────────────────

class AdminCallRecord {
  final String  callId;
  final String? roomId;
  final String  callerId;
  final String  callerName;
  final String  callerImage;
  final String  recipientId;
  final String  recipientName;
  final String  recipientImage;
  final String  callType;       // 'audio' | 'video' | 'group'
  final List<String> participants;
  final DateTime? startTime;
  final DateTime? endTime;
  final int     duration;       // seconds
  final String  status;         // 'completed'|'missed'|'declined'|'cancelled'|'ended'|'rejected'
  final String  initiatedBy;
  final String? endedBy;
  final String? recordingUrl;

  const AdminCallRecord({
    required this.callId,
    this.roomId,
    required this.callerId,
    required this.callerName,
    required this.callerImage,
    required this.recipientId,
    required this.recipientName,
    required this.recipientImage,
    required this.callType,
    List<String>? participants,
    this.startTime,
    this.endTime,
    required this.duration,
    required this.status,
    required this.initiatedBy,
    this.endedBy,
    this.recordingUrl,
  }) : participants = participants ?? const [];

  factory AdminCallRecord.fromJson(Map<String, dynamic> j) {
    List<String> _parseParticipants(dynamic v) {
      if (v == null) return [];
      if (v is List) return v.map((e) => e.toString()).toList();
      return [];
    }

    return AdminCallRecord(
      callId:         j['callId']?.toString()        ?? '',
      roomId:         j['roomId']?.toString(),
      callerId:       j['callerId']?.toString()       ?? '',
      callerName:     j['callerName']?.toString()     ?? '',
      callerImage:    j['callerImage']?.toString()    ?? '',
      recipientId:    j['recipientId']?.toString()    ?? '',
      recipientName:  j['recipientName']?.toString()  ?? '',
      recipientImage: j['recipientImage']?.toString() ?? '',
      callType:       j['callType']?.toString()       ?? 'audio',
      participants:   _parseParticipants(j['participants']),
      startTime:      j['startTime'] != null
          ? DateTime.tryParse(j['startTime'].toString())
          : null,
      endTime: j['endTime'] != null
          ? DateTime.tryParse(j['endTime'].toString())
          : null,
      duration:       j['duration'] is int
          ? j['duration'] as int
          : int.tryParse(j['duration']?.toString() ?? '0') ?? 0,
      status:       j['status']?.toString()      ?? 'missed',
      initiatedBy:  j['initiatedBy']?.toString() ?? '',
      endedBy:      j['endedBy']?.toString(),
      recordingUrl: j['recordingUrl']?.toString(),
    );
  }
}

class AdminCallHistoryResponse {
  final bool                  success;
  final List<AdminCallRecord> calls;
  final int                   total;
  final int                   page;
  final int                   limit;
  final int                   totalPages;

  const AdminCallHistoryResponse({
    required this.success,
    required this.calls,
    required this.total,
    required this.page,
    required this.limit,
    required this.totalPages,
  });

  factory AdminCallHistoryResponse.fromJson(Map<String, dynamic> j) {
    final list = (j['calls'] as List<dynamic>? ?? [])
        .map((e) => AdminCallRecord.fromJson(e as Map<String, dynamic>))
        .toList();
    return AdminCallHistoryResponse(
      success:    j['success'] == true,
      calls:      list,
      total:      j['total'] is int ? j['total'] as int : int.tryParse(j['total']?.toString() ?? '0') ?? 0,
      page:       j['page']  is int ? j['page']  as int : int.tryParse(j['page']?.toString()  ?? '1') ?? 1,
      limit:      j['limit'] is int ? j['limit'] as int : int.tryParse(j['limit']?.toString() ?? '50') ?? 50,
      totalPages: j['total_pages'] is int ? j['total_pages'] as int : int.tryParse(j['total_pages']?.toString() ?? '1') ?? 1,
    );
  }
}

// ─── Service ──────────────────────────────────────────────────────────────────

class AdminCallHistoryService {
  static const String _baseUrl = kAdminApi9BaseUrl;

  Future<Map<String, String>> _authHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    return {
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<AdminCallHistoryResponse> getCalls({
    int page = 1,
    int limit = 50,
    String? search,
    String? callType,
    String? status,
    String? dateFrom,
    String? dateTo,
  }) async {
    final q = <String, String>{
      'page':  page.toString(),
      'limit': limit.toString(),
    };
    if (search   != null && search.isNotEmpty)   q['search']    = search;
    if (callType != null && callType.isNotEmpty)  q['call_type'] = callType;
    if (status   != null && status.isNotEmpty)    q['status']    = status;
    if (dateFrom != null && dateFrom.isNotEmpty)  q['date_from'] = dateFrom;
    if (dateTo   != null && dateTo.isNotEmpty)    q['date_to']   = dateTo;

    final uri = Uri.parse('$_baseUrl/get_admin_call_history.php')
        .replace(queryParameters: q);
    final response = await http.get(uri, headers: await _authHeaders());

    developer.log(
      'getCalls [${response.statusCode}]: ${response.body.length} bytes',
      name: 'AdminCallHistoryService',
    );

    if (response.statusCode == 401) throw const UnauthorizedException();
    if (response.statusCode == 200) {
      final decoded = json.decode(response.body) as Map<String, dynamic>;
      return AdminCallHistoryResponse.fromJson(decoded);
    }
    throw Exception('Failed to load call history: ${response.statusCode}');
  }
}
