import 'dart:convert';
import 'package:adminmrz/payment/paymentmodel.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:adminmrz/config/app_endpoints.dart';

class PaymentService {
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

  // Get payment history
  Future<PaymentHistoryResponse> getPaymentHistory() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/get_payments.php'),
        headers: await _authHeaders(),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return PaymentHistoryResponse.fromJson(data);
      } else {
        throw Exception('Failed to load payment history: ${response.statusCode}');
      }
    } catch (e) {
      rethrow;
    }
  }

  // Get payment history with filters (date range)
  Future<PaymentHistoryResponse> getFilteredPayments({
    DateTime? startDate,
    DateTime? endDate,
    String? paymentMethod,
    String? status,
  }) async {
    try {
      final Map<String, String> params = {};

      if (startDate != null) {
        params['start_date'] = startDate.toIso8601String().split('T')[0];
      }
      if (endDate != null) {
        params['end_date'] = endDate.toIso8601String().split('T')[0];
      }
      if (paymentMethod != null && paymentMethod.isNotEmpty) {
        params['payment_method'] = paymentMethod;
      }
      if (status != null && status.isNotEmpty) {
        params['status'] = status;
      }

      final uri = Uri.parse('$_baseUrl/get_payments.php').replace(
        queryParameters: params.isNotEmpty ? params : null,
      );

      final response = await http.get(
        uri,
        headers: await _authHeaders(),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return PaymentHistoryResponse.fromJson(data);
      } else {
        throw Exception('Failed to load filtered payments: ${response.statusCode}');
      }
    } catch (e) {
      rethrow;
    }
  }
}