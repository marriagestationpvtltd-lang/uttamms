import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:ms2026/config/app_endpoints.dart';

class LocationService {
  static const String baseUrl = "${kApiBaseUrl}/Api3";

  /// Generic GET request
  static Future<List<Map<String, dynamic>>> _getList(
      String endpoint,
      ) async {
    final response = await http.get(Uri.parse("$baseUrl/$endpoint"));

    if (response.statusCode == 200) {
      final body = json.decode(response.body);

      if (body["status"] == "success") {
        return List<Map<String, dynamic>>.from(body["data"]);
      } else {
        throw Exception(body["message"] ?? "API Error");
      }
    } else {
      throw Exception("Failed to load data");
    }
  }

  /// Countries
  static Future<List<Map<String, dynamic>>> fetchCountries() async {
    return await _getList("countries.php");
  }

  /// States by Country
  static Future<List<Map<String, dynamic>>> fetchStates(int countryId) async {
    return await _getList("states.php?country_id=$countryId");
  }

  /// Cities by State
  static Future<List<Map<String, dynamic>>> fetchCities(int stateId) async {
    return await _getList("cities.php?state_id=$stateId");
  }
}
