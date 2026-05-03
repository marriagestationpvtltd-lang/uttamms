/// profile_field_options_service.dart
///
/// Fetches dropdown options for dynamic master fields
/// (educationtype, degree, faculty, educationmedium,
///  occupationtype, workingwith, annualincome)
/// from the backend master API and caches them for the session.
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:ms2026/config/app_endpoints.dart';

class ProfileFieldOptionsService {
  // Session-level in-memory cache: fieldKey → list of option strings
  static final Map<String, List<String>> _cache = {};

  /// Returns cached options for [field].
  /// If not yet fetched, fetches ALL dynamic fields in one request and caches.
  static Future<List<String>> getOptions(String field) async {
    if (_cache.containsKey(field)) return _cache[field]!;
    await _fetchAll();
    return _cache[field] ?? [];
  }

  /// Returns the full cache map after ensuring it is populated.
  static Future<Map<String, List<String>>> getAllOptions() async {
    if (_cache.isNotEmpty) return _cache;
    await _fetchAll();
    return _cache;
  }

  /// Clears the in-memory cache (e.g. after admin updates master data).
  static void clearCache() => _cache.clear();

  static Future<void> _fetchAll() async {
    try {
      final response = await http
          .get(Uri.parse(kEndpointProfileFieldOptions))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return;

      final body = json.decode(response.body) as Map<String, dynamic>;
      // Expected shape: { "status": "success", "data": { "fieldKey": ["opt1", ...] } }
      final data = body['data'] as Map<String, dynamic>?;
      if (data == null) return;

      for (final entry in data.entries) {
        final raw = entry.value;
        List<String> opts = [];
        if (raw is List) {
          opts = raw
              .map((e) {
                if (e is Map)
                  return (e['label'] ?? e['value'] ?? '').toString();
                return e.toString();
              })
              .where((s) => s.isNotEmpty)
              .toList();
        }
        _cache[entry.key] = opts;
      }
    } catch (_) {
      // Silently ignore — callers will get empty list and can show fallback.
    }
  }
}
