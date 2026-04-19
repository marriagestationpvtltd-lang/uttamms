/// Example Service - Template for API Integration
///
/// Shows proper error handling, timeout configuration,
/// and response parsing patterns.

import 'dart:async';
import 'dart:convert';
import 'dart:io' if (dart.library.html) 'package:ms2026/utils/web_io_stub.dart';
import 'package:http/http.dart' as http;
import '../../../core/api/api_response.dart';
import '../models/example_model.dart';

class ExampleService {
  final String baseUrl = 'YOUR_API_BASE_URL/api';
  final Duration timeout = const Duration(seconds: 30);

  /// Fetch list of items
  Future<ApiResponse<List<ExampleModel>>> fetchItems({
    required String userId,
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final url = Uri.parse('$baseUrl/items')
          .replace(queryParameters: {
        'user_id': userId,
        'page': page.toString(),
        'limit': limit.toString(),
      });

      final response = await http
          .get(
            url,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              // Add authentication headers if needed
              // 'Authorization': 'Bearer $token',
            },
          )
          .timeout(timeout);

      return _handleResponse<List<ExampleModel>>(
        response,
        (data) {
          if (data is List) {
            return data
                .map((item) => ExampleModel.fromJson(item))
                .toList();
          } else if (data is Map && data['items'] is List) {
            return (data['items'] as List)
                .map((item) => ExampleModel.fromJson(item))
                .toList();
          } else {
            throw FormatException('Unexpected data format');
          }
        },
      );
    } on TimeoutException {
      return ApiResponse.error(
        'Request timeout. Please check your connection.',
      );
    } on SocketException {
      return ApiResponse.error('No internet connection');
    } on FormatException catch (e) {
      return ApiResponse.error('Invalid response format: ${e.message}');
    } catch (e) {
      return ApiResponse.error('Unexpected error: ${e.toString()}');
    }
  }

  /// Fetch single item by ID
  Future<ApiResponse<ExampleModel>> fetchItem({
    required String itemId,
  }) async {
    try {
      final url = Uri.parse('$baseUrl/items/$itemId');

      final response = await http
          .get(
            url,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
          )
          .timeout(timeout);

      return _handleResponse<ExampleModel>(
        response,
        (data) => ExampleModel.fromJson(data),
      );
    } on TimeoutException {
      return ApiResponse.error('Request timeout. Check your connection.');
    } on SocketException {
      return ApiResponse.error('No internet connection');
    } catch (e) {
      return ApiResponse.error('Error: ${e.toString()}');
    }
  }

  /// Create new item
  Future<ApiResponse<ExampleModel>> createItem({
    required String userId,
    required String title,
    String? description,
  }) async {
    try {
      final url = Uri.parse('$baseUrl/items');

      final response = await http
          .post(
            url,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: json.encode({
              'user_id': userId,
              'title': title,
              if (description != null) 'description': description,
            }),
          )
          .timeout(timeout);

      return _handleResponse<ExampleModel>(
        response,
        (data) => ExampleModel.fromJson(data),
      );
    } catch (e) {
      return ApiResponse.error('Error creating item: ${e.toString()}');
    }
  }

  /// Update existing item
  Future<ApiResponse<ExampleModel>> updateItem({
    required String itemId,
    String? title,
    String? description,
    bool? isActive,
  }) async {
    try {
      final url = Uri.parse('$baseUrl/items/$itemId');

      final body = <String, dynamic>{};
      if (title != null) body['title'] = title;
      if (description != null) body['description'] = description;
      if (isActive != null) body['is_active'] = isActive;

      final response = await http
          .put(
            url,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: json.encode(body),
          )
          .timeout(timeout);

      return _handleResponse<ExampleModel>(
        response,
        (data) => ExampleModel.fromJson(data),
      );
    } catch (e) {
      return ApiResponse.error('Error updating item: ${e.toString()}');
    }
  }

  /// Delete item
  Future<ApiResponse<bool>> deleteItem({
    required String itemId,
  }) async {
    try {
      final url = Uri.parse('$baseUrl/items/$itemId');

      final response = await http
          .delete(
            url,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
          )
          .timeout(timeout);

      if (response.statusCode == 200 || response.statusCode == 204) {
        return ApiResponse.success(true);
      } else {
        return ApiResponse.error('Failed to delete item');
      }
    } catch (e) {
      return ApiResponse.error('Error deleting item: ${e.toString()}');
    }
  }

  /// Generic response handler
  ApiResponse<T> _handleResponse<T>(
    http.Response response,
    T Function(dynamic data) parser,
  ) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      try {
        final jsonData = json.decode(response.body);

        // Handle different response structures
        if (jsonData is Map) {
          if (jsonData['status'] == 'success' || jsonData['success'] == true) {
            final data = jsonData['data'] ?? jsonData;
            return ApiResponse.success(
              parser(data),
              statusCode: response.statusCode,
            );
          } else if (jsonData['status'] == 'error' ||
              jsonData['success'] == false) {
            return ApiResponse.error(
              jsonData['message'] ?? 'Request failed',
              statusCode: response.statusCode,
            );
          } else {
            // Assume the entire response is the data
            return ApiResponse.success(
              parser(jsonData),
              statusCode: response.statusCode,
            );
          }
        } else {
          // Response is a list or other type
          return ApiResponse.success(
            parser(jsonData),
            statusCode: response.statusCode,
          );
        }
      } catch (e) {
        return ApiResponse.error(
          'Failed to parse response: ${e.toString()}',
          statusCode: response.statusCode,
        );
      }
    } else if (response.statusCode == 404) {
      return ApiResponse.error(
        'Resource not found',
        statusCode: response.statusCode,
      );
    } else if (response.statusCode == 401) {
      return ApiResponse.error(
        'Unauthorized. Please login again.',
        statusCode: response.statusCode,
      );
    } else if (response.statusCode >= 500) {
      return ApiResponse.error(
        'Server error. Please try again later.',
        statusCode: response.statusCode,
      );
    } else {
      return ApiResponse.error(
        'Request failed with status ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }
  }
}
