import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

import 'docmodel.dart';
import 'package:adminmrz/config/app_endpoints.dart';


class DocumentsProvider with ChangeNotifier {
  List<Document> _documents = [];
  bool _isLoading = false;
  String? _error;
  bool _isActionLoading = false;
  bool _isInitialized = false;

  List<Document> get documents => _documents;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isActionLoading => _isActionLoading;
  bool get isInitialized => _isInitialized;

  void clearError() {
    _error = null;
    notifyListeners();
  }

  // Filter getters
  List<Document> get pendingDocuments =>
      _documents.where((doc) => doc.isPending).toList();

  List<Document> get approvedDocuments =>
      _documents.where((doc) => doc.isApproved).toList();

  List<Document> get rejectedDocuments =>
      _documents.where((doc) => doc.isRejected).toList();

  List<Document> documentsForUser(int userId) =>
      _documents.where((doc) => doc.userId == userId).toList();

  Future<bool> fetchDocuments() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');

      if (token == null) {
        _error = 'Not authenticated';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      final url = Uri.parse('$kAdminApi9BaseUrl/get_documents.php');

      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );


      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);

        if (responseData['success'] == true) {
          final List<dynamic> data = responseData['data'] ?? [];
          _documents = data.map((doc) => Document.fromJson(doc)).toList();
          _isLoading = false;
          _isInitialized = true;
          notifyListeners();
          return true;
        } else {
          _error = responseData['message'] ?? 'Failed to load documents';
          _isLoading = false;
          notifyListeners();
          return false;
        }
      } else {
        _error = 'Server error: ${response.statusCode}';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = 'Network error: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateDocumentStatus({
    required int documentId,
    required String action,
    String? rejectReason,
  }) async {
    _isActionLoading = true;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');

      if (token == null) {
        _error = 'Not authenticated';
        _isActionLoading = false;
        notifyListeners();
        return false;
      }

      final url = Uri.parse('$kAdminApi9BaseUrl/update_document_status.php');

      final Map<String, dynamic> body = {
        'document_id': documentId,
        'action': action,
      };

      if (action == 'reject' && rejectReason != null) {
        body['reject_reason'] = rejectReason;
      }

      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: json.encode(body),
      );


      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);

        if (responseData['success'] == true) {
          // Update local document status
          final index = _documents.indexWhere((doc) => doc.documentId == documentId);
          if (index != -1) {
            final updatedDoc = Document(
              userId: _documents[index].userId,
              email: _documents[index].email,
              firstName: _documents[index].firstName,
              lastName: _documents[index].lastName,
              gender: _documents[index].gender,
              status: action == 'approve' ? 'approved' : 'rejected',
              rejectReason: action == 'reject' ? (rejectReason ?? '') : '',
              isVerified: action == 'approve' ? 1 : 0,
              documentId: _documents[index].documentId,
              documentType: _documents[index].documentType,
              documentIdNumber: _documents[index].documentIdNumber,
              photo: _documents[index].photo,
            );
            _documents[index] = updatedDoc;
          }

          _isActionLoading = false;
          notifyListeners();
          return true;
        } else {
          _error = responseData['message'] ?? 'Failed to update status';
          _isActionLoading = false;
          notifyListeners();
          return false;
        }
      } else {
        _error = 'Server error: ${response.statusCode}';
        _isActionLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = 'Network error: $e';
      _isActionLoading = false;
      notifyListeners();
      return false;
    }
  }
}