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

      if (response.statusCode != 200) {
        debugPrint('[fetchPartnerPreference] HTTP ${response.statusCode}: ${response.body.substring(0, response.body.length.clamp(0, 200))}');
        return null;
      }

      final rawBody = response.body.trim();
      if (rawBody.isEmpty) {
        debugPrint('[fetchPartnerPreference] Empty body (HTTP ${response.statusCode}).');
        return null;
      }

      // Extract JSON even if PHP warning/notice text is prepended.
      final jsonStart = rawBody.indexOf('{');
      final jsonEnd = rawBody.lastIndexOf('}');
      final jsonCandidate = (jsonStart != -1 && jsonEnd != -1 && jsonEnd > jsonStart)
          ? rawBody.substring(jsonStart, jsonEnd + 1)
          : rawBody;

      if (jsonCandidate != rawBody) {
        debugPrint('[fetchPartnerPreference] Non-JSON prefix detected. Extracted candidate: $jsonCandidate');
      }

      try {
        final data = json.decode(jsonCandidate);
        if (data is Map<String, dynamic>) {
          return data;
        }
      } on FormatException catch (e) {
        debugPrint('[fetchPartnerPreference] FormatException: $e\nCandidate: $jsonCandidate');
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

      if (response.statusCode == 200) {
        final rawBody = response.body.trim();
        debugPrint('[savePartnerPreference] HTTP 200. Raw body: $rawBody');

        if (rawBody.isEmpty) {
          debugPrint('[savePartnerPreference] Empty body received.');
          return {
            'status': 'error',
            'message': 'Server returned an empty response. Please try again.',
          };
        }

        // Attempt to extract a JSON object even if PHP warning/notice text is
        // prepended to the response (happens when display_errors is enabled on
        // the server and an undefined array key triggers a notice/warning).
        final jsonStart = rawBody.indexOf('{');
        final jsonEnd = rawBody.lastIndexOf('}');
        final jsonCandidate = (jsonStart != -1 && jsonEnd != -1 && jsonEnd > jsonStart)
            ? rawBody.substring(jsonStart, jsonEnd + 1)
            : rawBody;

        if (jsonCandidate != rawBody) {
          debugPrint('[savePartnerPreference] Non-JSON prefix detected. Extracted candidate: $jsonCandidate');
        }

        try {
          final data = json.decode(jsonCandidate);
          if (data is Map<String, dynamic>) {
            return data;
          }
          debugPrint('[savePartnerPreference] Unexpected decoded type: ${data.runtimeType}. Value: $data');
          return {'status': 'error', 'message': 'Unexpected response format.'};
        } on FormatException catch (e) {
          debugPrint('[savePartnerPreference] FormatException: $e\nCandidate: $jsonCandidate');
          return {
            'status': 'error',
            'message': 'Server returned an unexpected response. Please try again.',
          };
        }
      } else {
        debugPrint('[savePartnerPreference] HTTP ${response.statusCode}. Body: ${response.body}');
        return {
          'status': 'error',
          'message': 'Server returned status code ${response.statusCode}'
        };
      }
    } catch (e) {
      debugPrint('[savePartnerPreference] Unexpected error: $e');
      return {'status': 'error', 'message': 'An unexpected error occurred. Please try again.'};
    }
  }
}
