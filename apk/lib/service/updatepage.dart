import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:ms2026/config/app_endpoints.dart';

class UpdateService {
  static const String baseUrl = "${kApiBaseUrl}/Api2"; // change to your domain

  // Reusable function to update page number
  static Future<bool> updatePageNumber({
    required String userId,
    required int pageNo,
  }) async {
    try {
      final uri = Uri.parse("$baseUrl/update_pageno.php");

      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: jsonEncode({'user_id': userId, 'pageno': pageNo}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['status'] == 'success') {
          print("Page updated: ${data['pageno']}");
          return true;
        } else {
          print("Error: ${data['message']}");
          return false;
        }
      } else {
        print("Server Error: ${response.statusCode}");
        return false;
      }
    } catch (e) {
      print("Exception: $e");
      return false;
    }
  }
}
