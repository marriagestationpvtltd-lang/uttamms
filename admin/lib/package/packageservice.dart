import 'dart:convert';
import 'package:adminmrz/package/packagemodel.dart';
import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:adminmrz/config/app_endpoints.dart';


class PackageService {
  static const String _baseUrl = kAdminApi9BaseUrl;

  Future<Map<String, String>> _authHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // Get all packages
  Future<PackageListResponse> getPackages() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/get_packages.php'),
        headers: await _authHeaders(),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return PackageListResponse.fromJson(data);
      } else {
        throw Exception('Failed to load packages: ${response.statusCode}');
      }
    } catch (e) {
      rethrow;
    }
  }

  // Create new package
  Future<CreatePackageResponse> createPackage(Package package) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/create_package.php'),
        headers: await _authHeaders(),
        body: json.encode(package.toCreateJson()),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return CreatePackageResponse.fromJson(data);
      } else {
        throw Exception('Failed to create package: ${response.statusCode}');
      }
    } catch (e) {
      rethrow;
    }
  }

  // Update package
  Future<bool> updatePackage(Package package) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/update_package.php'),
        headers: await _authHeaders(),
        body: jsonEncode(package.toUpdateJson()),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      } else {
        throw Exception(
          'Failed to update package: ${response.statusCode}',
        );
      }
    } catch (e) {
      rethrow;
    }
  }


  // Delete package
  Future<bool> deletePackage(int packageId) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/delete_package.php'),
        headers: await _authHeaders(),
        body: jsonEncode({
          'id': packageId,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      } else {
        throw Exception(
          'Failed to delete package: ${response.statusCode}',
        );
      }
    } catch (e) {
      rethrow;
    }
  }

}