import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:ms2026/config/app_endpoints.dart';

class UserPartnerPreferenceService {
  final String saveUrl;
  final String fetchUrl;

  UserPartnerPreferenceService({
    this.saveUrl = '${kApiBaseUrl}/Api2/user_partner.php',
    this.fetchUrl = '${kApiBaseUrl}/Api2/get_partner_preferences.php',
  });

  Future<Map<String, dynamic>?> fetchPartnerPreference({
    required int userId,
  }) async {
    try {
      final response = await http
          .get(Uri.parse('$fetchUrl?userid=$userId'))
          .timeout(const Duration(seconds: 30));

      // Log full response details
      debugPrint('[fetchPartnerPreference] HTTP ${response.statusCode}');
      final rawBody = response.body.trim();
      debugPrint('[fetchPartnerPreference] Raw body (first 500 chars): ${rawBody.substring(0, rawBody.length.clamp(0, 500))}');

      if (response.statusCode != 200) {
        debugPrint('[fetchPartnerPreference] Non-200 status code');
        return null;
      }

      if (rawBody.isEmpty) {
        debugPrint('[fetchPartnerPreference] Empty body received.');
        return null;
      }

      // Check if response looks like HTML
      if (rawBody.startsWith('<') || rawBody.toLowerCase().contains('<!doctype') || rawBody.toLowerCase().contains('<html')) {
        debugPrint('[fetchPartnerPreference] HTML response detected instead of JSON');
        return null;
      }

      // Extract JSON even if PHP warning/notice text is prepended.
      final jsonStart = rawBody.indexOf('{');
      final jsonEnd = rawBody.lastIndexOf('}');

      if (jsonStart == -1 || jsonEnd == -1 || jsonEnd <= jsonStart) {
        debugPrint('[fetchPartnerPreference] No valid JSON object found in response');
        return null;
      }

      final jsonCandidate = rawBody.substring(jsonStart, jsonEnd + 1);

      if (jsonCandidate != rawBody) {
        debugPrint('[fetchPartnerPreference] Non-JSON prefix detected. Extracted candidate: $jsonCandidate');
      }

      try {
        final data = json.decode(jsonCandidate);
        if (data is Map<String, dynamic>) {
          debugPrint('[fetchPartnerPreference] Successfully parsed JSON response');
          return data;
        }
        debugPrint('[fetchPartnerPreference] Unexpected decoded type: ${data.runtimeType}');
        return null;
      } on FormatException catch (e) {
        debugPrint('[fetchPartnerPreference] FormatException: $e');
        debugPrint('[fetchPartnerPreference] JSON candidate that failed: $jsonCandidate');
        return null;
      }
    } catch (e) {
      debugPrint('[fetchPartnerPreference] Unexpected error: $e');
    }

    return null;
  }

  Future<Map<String, dynamic>> savePartnerPreference({
    required int userId,
    required String ageFrom,
    required String ageTo,
    required String heightFrom,
    required String heightTo,
    required String maritalStatus,
    required String religion,
    List<String> countryIds = const [],
    List<String> stateIds = const [],
    List<String> cityIds = const [],
    String? community,
    String? motherTongue,
    String? country,
    String? state,
    String? district,
    String? education,
    String? occupation,
    String? diet,
    String? smokeAccept,
    String? drinkAccept,
    String? otherExpectation,
  }) async {
    final url = Uri.parse(saveUrl);

    try {
      final body = <String, dynamic>{
        'userid': userId.toString(),
        'minage': ageFrom,
        'maxage': ageTo,
        'minheight': heightFrom,
        'maxheight': heightTo,
        'maritalstatus': maritalStatus,
        'profilewithchild': '',
        'familytype': '',
        'religion': religion,
        'caste': community ?? '',
        'subcaste': '',
        // PHP field name is "mothertoungue" (typo in backend — must match exactly)
        'mothertoungue': motherTongue ?? '',
        // PHP field name is "herscopeblief" (typo in backend — must match exactly)
        'herscopeblief': '',
        'manglik': '',
        'country': countryIds.join(','),
        'state': stateIds.join(','),
        'city': cityIds.join(','),
        'qualification': education ?? '',
        'educationmedium': '',
        // PHP field name is "proffession" (typo in backend — must match exactly)
        'proffession': occupation ?? '',
        'workingwith': '',
        'annualincome': '',
        'diet': diet ?? '',
        'smokeaccept': smokeAccept ?? '',
        'drinkaccept': drinkAccept ?? '',
        'disabilityaccept': '',
        'complexion': '',
        'bodytype': '',
        'otherexpectation': otherExpectation ?? '',
        'country_names': country ?? '',
        'state_names': state ?? '',
        'district_names': district ?? '',
      };

      final response = await http
          .post(
            url,
            headers: {
              'Content-Type': 'application/json; charset=UTF-8',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));

      // Log full response details
      debugPrint('[savePartnerPreference] HTTP ${response.statusCode}');
      debugPrint('[savePartnerPreference] Response headers: ${response.headers}');
      final rawBody = response.body.trim();
      debugPrint('[savePartnerPreference] Raw body (first 500 chars): ${rawBody.substring(0, rawBody.length.clamp(0, 500))}');

      if (response.statusCode == 200) {
        if (rawBody.isEmpty) {
          debugPrint('[savePartnerPreference] Empty body received.');
          return {
            'status': 'error',
            'message': 'Server returned an empty response. Please try again.',
          };
        }

        // Check if response looks like HTML (common error response format)
        if (rawBody.startsWith('<') || rawBody.toLowerCase().contains('<!doctype') || rawBody.toLowerCase().contains('<html')) {
          debugPrint('[savePartnerPreference] HTML response detected instead of JSON');
          return {
            'status': 'error',
            'message': 'Server returned an HTML page. Please contact support.',
          };
        }

        // Attempt to extract a JSON object even if PHP warning/notice text is
        // prepended to the response (happens when display_errors is enabled on
        // the server and an undefined array key triggers a notice/warning).
        final jsonStart = rawBody.indexOf('{');
        final jsonEnd = rawBody.lastIndexOf('}');

        if (jsonStart == -1 || jsonEnd == -1 || jsonEnd <= jsonStart) {
          debugPrint('[savePartnerPreference] No valid JSON object found in response');
          return {
            'status': 'error',
            'message': 'Invalid server response format. Please try again.',
          };
        }

        final jsonCandidate = rawBody.substring(jsonStart, jsonEnd + 1);

        if (jsonCandidate != rawBody) {
          debugPrint('[savePartnerPreference] Non-JSON prefix detected. Extracted candidate: $jsonCandidate');
        }

        try {
          final data = json.decode(jsonCandidate);
          if (data is Map<String, dynamic>) {
            debugPrint('[savePartnerPreference] Successfully parsed JSON response');
            return data;
          }
          debugPrint('[savePartnerPreference] Unexpected decoded type: ${data.runtimeType}. Value: $data');
          return {'status': 'error', 'message': 'Unexpected response format.'};
        } on FormatException catch (e) {
          debugPrint('[savePartnerPreference] FormatException: $e');
          debugPrint('[savePartnerPreference] JSON candidate that failed: $jsonCandidate');
          return {
            'status': 'error',
            'message': 'Server returned invalid JSON. Please try again or contact support.',
          };
        }
      } else {
        debugPrint('[savePartnerPreference] Non-200 status code: ${response.statusCode}');
        debugPrint('[savePartnerPreference] Response body: ${rawBody.substring(0, rawBody.length.clamp(0, 500))}');
        return {
          'status': 'error',
          'message': 'Server error (${response.statusCode}). Please try again.',
        };
      }
    } catch (e) {
      debugPrint('[savePartnerPreference] Unexpected error: $e');
      return {'status': 'error', 'message': 'An unexpected error occurred. Please try again.'};
    }
  }
}
