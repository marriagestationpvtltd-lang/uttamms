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

      final body = response.body.trim();
      if (body.isEmpty || body.startsWith('<')) {
        debugPrint('[fetchPartnerPreference] Non-JSON body (${response.statusCode}): ${body.substring(0, body.length.clamp(0, 500))}');
        return null;
      }
      try {
        final data = json.decode(body);
        if (data is Map<String, dynamic>) {
          return data;
        }
      } on FormatException catch (e) {
        debugPrint('[fetchPartnerPreference] FormatException: $e\nBody: ${body.substring(0, body.length.clamp(0, 500))}');
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
        'mothertongue': motherTongue ?? '',
        'horoscopebelief': '',
        'manglik': '',
        'country': countryIds.join(','),
        'state': stateIds.join(','),
        'city': cityIds.join(','),
        'qualification': education ?? '',
        'educationmedium': '',
        'profession': occupation ?? '',
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
        final body = response.body.trim();
        if (body.isEmpty || body.startsWith('<')) {
          print('[savePartnerPreference] Non-JSON body (HTTP 200). Body preview: ${body.substring(0, body.length.clamp(0, 500))}');
          return {
            'status': 'error',
            'message': 'Server returned an unexpected response. Please try again.',
          };
        }
        try {
          final data = json.decode(body);
          if (data is Map<String, dynamic>) {
            return data;
          }
          print('[savePartnerPreference] Unexpected body type: $data');
          return {'status': 'error', 'message': 'Unexpected response format.'};
        } on FormatException catch (e) {
          print('[savePartnerPreference] FormatException: $e\nBody preview: ${body.substring(0, body.length.clamp(0, 500))}');
          return {
            'status': 'error',
            'message': 'Server returned an unexpected response. Please try again.',
          };
        }
      } else {
        print('[savePartnerPreference] HTTP ${response.statusCode}. Body: ${response.body.substring(0, response.body.length.clamp(0, 500))}');
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
