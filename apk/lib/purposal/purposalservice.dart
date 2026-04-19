import 'dart:convert';
import 'package:http/http.dart' as http;
import 'Purposalmodel.dart';
import 'package:ms2026/config/app_endpoints.dart';

class ProposalService {
  static const String baseUrl = "${kApiBaseUrl}/Api2/proposals_api.php";

  static Future<List<ProposalModel>> fetchProposals(
      String userId, String type) async {
    final url = Uri.parse("$baseUrl?user_id=$userId&type=$type");

    final response = await http.get(url);

    if (response.statusCode == 200) {
      final jsonData = json.decode(response.body);

      if (jsonData["status"] == "success") {
        return (jsonData["data"] as List)
            .map((e) => ProposalModel.fromJson(e))
            .toList();
      }
    }
    return [];
  }



  // Delete proposal
  static Future<bool> deleteProposal(String userId, String proposalId) async {
    final response = await http.post(
      Uri.parse("${kApiBaseUrl}/Api2/purposal_delete.php"),
      body: {
        "user_id": userId,
        "proposal_id": proposalId,
      },
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['status'] == "success";
    } else {
      return false;
    }
  }

  static Future<bool> acceptProposal(String proposalId, String userId) async {
    try {
      final response = await http.post(
        Uri.parse('${kApiBaseUrl}/Api2/acceptProposal.php'), // Update with your actual endpoint
        body: {
          'proposal_id': proposalId,
          'user_id': userId,
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('Accept response: $data');
        return data['success'] == true;
      }
      return false;
    } catch (e) {
      print("Error accepting proposal: $e");
      return false;
    }
  }

  /// REJECT A PROPOSAL
  static Future<bool> rejectProposal(String proposalId, String userId) async {
    try {
      final response = await http.post(
        Uri.parse('${kApiBaseUrl}/Api2/rejectProposal.php'), // Update with your actual endpoint
        body: {
          'proposal_id': proposalId,
          'user_id': userId,
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('Reject response: $data');
        return data['success'] == true;
      }
      return false;
    } catch (e) {
      print("Error rejecting proposal: $e");
      return false;
    }
  }

  /// DELETE/CANCEL A PROPOSAL (if you don't have it already)
}
