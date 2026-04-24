import 'package:adminmrz/auth/service.dart';
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

  List<RequestItem> get requests => _requests;
  RequestStats? get stats => _stats;
  RequestPagination? get pagination => _pagination;
  bool get isLoading => _isLoading;
  String get error => _error;
  int get currentPage => _currentPage;
  String get statusFilter => _statusFilter;
  String get searchQuery => _searchQuery;

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
    try {
      final success = await _service.updateRequestStatus(
        requestId: requestId,
        action: action,
      );
      if (success) {
        final idx = _requests.indexWhere((r) => r.id == requestId);
        if (idx != -1) {
          _requests = List<RequestItem>.from(_requests)
            ..[idx] = _requests[idx].copyWith(status: action);
          // Refresh stats after status change
          if (_stats != null) {
            await fetchRequests(reset: true);
          }
        }
        notifyListeners();
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
