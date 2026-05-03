import 'package:adminmrz/deleteRequests/delete_request_model.dart';
import 'package:adminmrz/deleteRequests/delete_request_service.dart';
import 'package:flutter/material.dart';

class DeleteRequestProvider with ChangeNotifier {
  final DeleteRequestService _service = DeleteRequestService();

  List<DeleteRequestItem> _items = [];
  DeleteRequestStats? _stats;
  bool _isLoading = false;
  bool _isActing = false;
  String _error = '';
  int _currentPage = 1;
  int _totalPages = 1;
  String _statusFilter = 'all';
  String _searchQuery = '';

  List<DeleteRequestItem> get items => _items;
  DeleteRequestStats? get stats => _stats;
  bool get isLoading => _isLoading;
  bool get isActing => _isActing;
  String get error => _error;
  int get currentPage => _currentPage;
  int get totalPages => _totalPages;
  bool get hasMore => _currentPage < _totalPages;
  String get statusFilter => _statusFilter;
  String get searchQuery => _searchQuery;

  void setFilter(String status) {
    if (_statusFilter == status) return;
    _statusFilter = status;
    fetchRequests(reset: true);
  }

  void setSearch(String query) {
    if (_searchQuery == query) return;
    _searchQuery = query;
    fetchRequests(reset: true);
  }

  Future<void> fetchRequests({bool reset = false}) async {
    if (reset) {
      _currentPage = 1;
      _items = [];
    }

    _isLoading = true;
    _error = '';
    notifyListeners();

    try {
      final result = await _service.getRequests(
        page: _currentPage,
        status: _statusFilter,
        search: _searchQuery,
      );

      if (reset || _currentPage == 1) {
        _items = result.items;
      } else {
        _items = [..._items, ...result.items];
      }

      _stats = result.stats;
      _totalPages = result.totalPages;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadMore() async {
    if (_isLoading || !hasMore) return;
    _currentPage++;
    await fetchRequests();
  }

  /// [action] = "approve" | "reject"
  Future<bool> resolveRequest({
    required int requestId,
    required String action,
    String adminNote = '',
  }) async {
    _isActing = true;
    notifyListeners();

    try {
      await _service.resolveRequest(
        requestId: requestId,
        action: action,
        adminNote: adminNote,
      );
      // Refresh the list
      await fetchRequests(reset: true);
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    } finally {
      _isActing = false;
      notifyListeners();
    }
  }
}
