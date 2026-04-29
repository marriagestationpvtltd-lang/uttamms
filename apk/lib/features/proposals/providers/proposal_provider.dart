import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/proposal_model.dart';
import '../services/proposal_service.dart';

/// State management for the Proposals feature.
///
/// Holds three separate lists:
/// - [received]  — pending proposals sent TO the current user
/// - [sent]      — pending proposals sent BY the current user
/// - [history]   — accepted and rejected proposals for the current user
///
/// All network calls go through [ProposalService] which returns
/// [ApiResponse] objects, keeping error handling consistent.
class ProposalProvider extends ChangeNotifier {
  final ProposalService _service;

  ProposalProvider({ProposalService? service})
      : _service = service ?? ProposalService();

  // -------------------------------------------------------------------------
  // State
  // -------------------------------------------------------------------------

  bool _isLoading = false;
  String? _error;

  List<ProposalModel> _received = [];
  List<ProposalModel> _sent     = [];
  List<ProposalModel> _history  = [];

  // -------------------------------------------------------------------------
  // Getters
  // -------------------------------------------------------------------------

  bool get isLoading => _isLoading;
  String? get error  => _error;

  List<ProposalModel> get received => List.unmodifiable(_received);
  List<ProposalModel> get sent     => List.unmodifiable(_sent);

  /// Accepted and rejected proposals (request history).
  List<ProposalModel> get history  => List.unmodifiable(_history);

  // -------------------------------------------------------------------------
  // Load all lists
  // -------------------------------------------------------------------------

  Future<void> loadAll(String userId) async {
    _isLoading = true;
    _error = null;
    notifyListeners(); // Immediately show loading spinner in the UI

    await Future.wait([
      _loadList(userId, 'received'),
      _loadList(userId, 'sent'),
      _loadList(userId, 'history'),
    ]);

    _isLoading = false;
    notifyListeners();
  }

  Future<void> _loadList(String userId, String type) async {
    final response = await _service.fetchProposals(userId: userId, type: type);

    if (response.isSuccess && response.data != null) {
      switch (type) {
        case 'received':
          _received = response.data!;
          break;
        case 'sent':
          _sent = response.data!;
          break;
        case 'history':
          _history = response.data!;
          break;
      }
    } else {
      _error = response.error ?? 'Failed to load $type proposals';
    }
    // notifyListeners() is called once in loadAll() after all lists have loaded
  }

  // -------------------------------------------------------------------------
  // Actions
  // -------------------------------------------------------------------------

  Future<bool> sendRequest({
    required BuildContext context,
    required String senderId,
    required String receiverId,
    required String requestType,
  }) async {
    final response = await _service.sendRequest(
      context:     context,
      senderId:    senderId,
      receiverId:  receiverId,
      requestType: requestType,
    );

    if (!response.isSuccess) {
      _error = response.error ?? 'Failed to send request';
      notifyListeners();
    }
    return response.isSuccess;
  }

  Future<bool> acceptProposal({
    required String proposalId,
    required String userId,
  }) async {
    final response = await _service.acceptProposal(
      proposalId: proposalId,
      userId:     userId,
    );

    if (response.isSuccess) {
      _received.removeWhere((p) => p.proposalId == proposalId);
    } else {
      _error = response.error ?? 'Failed to accept proposal';
    }
    notifyListeners();
    return response.isSuccess;
  }

  Future<bool> rejectProposal({
    required String proposalId,
    required String userId,
  }) async {
    final response = await _service.rejectProposal(
      proposalId: proposalId,
      userId:     userId,
    );

    if (response.isSuccess) {
      _received.removeWhere((p) => p.proposalId == proposalId);
    } else {
      _error = response.error ?? 'Failed to reject proposal';
    }
    notifyListeners();
    return response.isSuccess;
  }

  Future<bool> deleteProposal({
    required String proposalId,
    required String userId,
  }) async {
    final response = await _service.deleteProposal(
      proposalId: proposalId,
      userId:     userId,
    );

    if (response.isSuccess) {
      _sent.removeWhere((p) => p.proposalId == proposalId);
    } else {
      _error = response.error ?? 'Failed to delete proposal';
    }
    notifyListeners();
    return response.isSuccess;
  }

  // -------------------------------------------------------------------------
  // Error management
  // -------------------------------------------------------------------------

  /// Clear the current error and notify listeners so the UI can update.
  void clearError() {
    _error = null;
    notifyListeners();
  }
}

