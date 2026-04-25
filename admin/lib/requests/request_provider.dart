import 'dart:async';
import 'package:adminmrz/auth/service.dart';
import 'package:adminmrz/adminchat/services/admin_socket_service.dart';
import 'package:adminmrz/dashboard/dashservice.dart' show UnauthorizedException;
import 'package:adminmrz/requests/request_model.dart';
import 'package:adminmrz/requests/request_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class RequestProvider with ChangeNotifier {
  final RequestService _service = RequestService();

  List<RequestItem> _requests = [];
  RequestStats? _stats;
  RequestPagination? _pagination;
  bool _isLoading = false;
  String _error = '';
  int _currentPage = 1;
  String _statusFilter = 'all';
  String _searchQuery = '';

  // Real-time socket subscription
  StreamSubscription<Map<String, dynamic>>? _socketSub;

  List<RequestItem> get requests => _requests;
  RequestStats? get stats => _stats;
  RequestPagination? get pagination => _pagination;
  bool get isLoading => _isLoading;
  String get error => _error;
  int get currentPage => _currentPage;
  String get statusFilter => _statusFilter;
  String get searchQuery => _searchQuery;

  /// Subscribe to the admin socket so that any request_sent, request_accepted
  /// or request_rejected event triggers an immediate list refresh without the
  /// user having to pull-to-refresh.
  void subscribeToSocketUpdates(AdminSocketService socketService) {
    _socketSub?.cancel();
    _socketSub = socketService.onRequestUpdate.listen((_) {
      fetchRequests(reset: true);
    });
  }

  /// Cancel the socket subscription (call from dispose()).
  void unsubscribeFromSocketUpdates() {
    _socketSub?.cancel();
    _socketSub = null;
  }

  @override
  void dispose() {
    _socketSub?.cancel();
    super.dispose();
  }

  Future<void> fetchRequests({bool reset = false}) async {
    if (reset) {
      _currentPage = 1;
      _requests = [];
    }

    _isLoading = true;
    _error = '';
    notifyListeners();

    try {
      final response = await _service.getRequests(
        page: _currentPage,
        status: _statusFilter,
        search: _searchQuery,
      );
      if (reset || _currentPage == 1) {
        _requests = response.data;
      } else {
        _requests = [..._requests, ...response.data];
      }
      _stats = response.stats;
      _pagination = response.pagination;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadMore() async {
    if (_pagination == null || !_pagination!.hasMore || _isLoading) return;
    _currentPage++;
    await fetchRequests();
  }

  Future<void> setFilter(String status) async {
    if (_statusFilter == status) return;
    _statusFilter = status;
    await fetchRequests(reset: true);
  }

  Future<void> setSearch(String query) async {
    if (_searchQuery == query) return;
    _searchQuery = query;
    await fetchRequests(reset: true);
  }

  Future<void> forceUpdateStatus(
      int requestId, String action, BuildContext context) async {
    // The API expects 'accept'/'reject'; the resulting status is 'accepted'/'rejected'
    final apiAction = action == 'accepted' ? 'accept' : 'reject';
    try {
      final success = await _service.updateRequestStatus(
        requestId: requestId,
        action: apiAction,
      );
      if (success) {
        // Refresh to get updated stats and list from server
        await fetchRequests(reset: true);
      }
    } on UnauthorizedException {
      if (context.mounted) {
        context.read<AuthProvider>().logout();
      }
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }
}
