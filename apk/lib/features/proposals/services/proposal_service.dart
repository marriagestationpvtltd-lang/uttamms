import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../../config/app_endpoints.dart';
import '../../../core/api/api_response.dart';
import '../../../utils/access_control.dart';
import '../models/proposal_model.dart';

/// Service layer for the Proposals feature.
///
/// All methods call the `backend/Api2/` PHP endpoints and parse responses
/// into typed [ProposalModel] objects using [ApiResponse] for consistent
/// error handling across the app.
///
/// IMPORTANT: [sendRequest] enforces gated interaction rules - user must be
/// verified AND have active membership before sending any request.
class ProposalService {
  static const String _baseUrl = '$kApi2BaseUrl/proposals_api.php';

  // ---------------------------------------------------------------------------
  // Fetch proposals
  // ---------------------------------------------------------------------------

  /// Fetch proposals for [userId].
  ///
  /// [type] must be one of: `"received"`, `"sent"`, `"history"`.
  /// - `"received"` — pending requests sent to this user
  /// - `"sent"`     — pending requests sent by this user
  /// - `"history"`  — all accepted and rejected requests involving this user
  Future<ApiResponse<List<ProposalModel>>> fetchProposals({
    required String userId,
    required String type,
  }) async {
    try {
      final url = Uri.parse(_baseUrl)
          .replace(queryParameters: {'user_id': userId, 'type': type});
      final response = await http.get(url).timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        return ApiResponse.error(
          'Server returned status ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }

      final json = jsonDecode(response.body);
      if (json['status'] != 'success') {
        return ApiResponse.error(json['message'] ?? 'Unknown error');
      }

      final proposals = (json['data'] as List)
          .map((e) => ProposalModel.fromJson(e as Map<String, dynamic>))
          .toList();

      return ApiResponse.success(proposals);
    } catch (e) {
      return ApiResponse.error('Failed to fetch proposals: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Send request
  // ---------------------------------------------------------------------------

  /// Send a new connection request from [senderId] to [receiverId].
  ///
  /// [requestType] must be one of: `"Photo"`, `"Profile"`, `"Chat"`.
  /// Returns the `proposal_id` of the created (or updated) proposal.
  ///
  /// GATED INTERACTION: This method enforces that the user must be verified
  /// AND have active membership before sending any request. If requirements
  /// are not met, shows appropriate dialogs and returns an error.
  ///
  /// [context] is required for checking access control and showing dialogs.
  Future<ApiResponse<String>> sendRequest({
    required BuildContext context,
    required String senderId,
    required String receiverId,
    required String requestType,
  }) async {
    // Enforce gated interaction rules
    final canSend = await AccessControl.canSendRequest(context);
    if (!canSend) {
      return ApiResponse.error(
        'You must be verified and have an active membership to send requests',
      );
    }

    try {
      final url = Uri.parse('$kApi2BaseUrl/send_request.php');
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json; charset=UTF-8'},
            body: jsonEncode({
              'sender_id':    senderId,
              'receiver_id':  receiverId,
              'request_type': requestType,
            }),
          )
          .timeout(const Duration(seconds: 30));

      final json = jsonDecode(response.body);
      if (json['success'] == true) {
        return ApiResponse.success(json['proposal_id']?.toString() ?? '');
      }
      return ApiResponse.error(json['message'] ?? 'Failed to send request');
    } catch (e) {
      return ApiResponse.error('Failed to send request: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Accept proposal
  // ---------------------------------------------------------------------------

  /// Accept a pending proposal. Only the receiver may accept.
  Future<ApiResponse<bool>> acceptProposal({
    required String proposalId,
    required String userId,
  }) async {
    try {
      final url = Uri.parse('$kApi2BaseUrl/accept_proposal.php');
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json; charset=UTF-8'},
            body: jsonEncode({'proposal_id': proposalId, 'user_id': userId}),
          )
          .timeout(const Duration(seconds: 30));

      final json = jsonDecode(response.body);
      if (json['success'] == true) return ApiResponse.success(true);
      return ApiResponse.error(json['message'] ?? 'Failed to accept proposal');
    } catch (e) {
      return ApiResponse.error('Failed to accept proposal: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Reject proposal
  // ---------------------------------------------------------------------------

  /// Reject a pending proposal. Both the sender and receiver may reject.
  Future<ApiResponse<bool>> rejectProposal({
    required String proposalId,
    required String userId,
  }) async {
    try {
      final url = Uri.parse('$kApi2BaseUrl/reject_proposal.php');
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json; charset=UTF-8'},
            body: jsonEncode({'proposal_id': proposalId, 'user_id': userId}),
          )
          .timeout(const Duration(seconds: 30));

      final json = jsonDecode(response.body);
      if (json['success'] == true) return ApiResponse.success(true);
      return ApiResponse.error(json['message'] ?? 'Failed to reject proposal');
    } catch (e) {
      return ApiResponse.error('Failed to reject proposal: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Delete proposal
  // ---------------------------------------------------------------------------

  /// Delete a pending or rejected proposal.
  /// Only the sender or receiver of the proposal may delete it.
  Future<ApiResponse<bool>> deleteProposal({
    required String proposalId,
    required String userId,
  }) async {
    try {
      final url = Uri.parse('$kApi2BaseUrl/delete_proposal.php');
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json; charset=UTF-8'},
            body: jsonEncode({'proposal_id': proposalId, 'user_id': userId}),
          )
          .timeout(const Duration(seconds: 30));

      final json = jsonDecode(response.body);
      if (json['success'] == true) return ApiResponse.success(true);
      return ApiResponse.error(json['message'] ?? 'Failed to delete proposal');
    } catch (e) {
      return ApiResponse.error('Failed to delete proposal: $e');
    }
  }
}
