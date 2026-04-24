import 'dart:async';

import 'package:adminmrz/adminchat/services/admin_socket_service.dart';
import 'package:adminmrz/dashboard/dashservice.dart' show UnauthorizedException;
import 'package:adminmrz/users/service/userservice.dart';
import 'package:adminmrz/users/userdetails/detailmodel.dart';
import 'package:adminmrz/users/userdetails/userdetailservice.dart';
import 'package:flutter/material.dart';

import 'model/usermodel.dart';


class UserProvider with ChangeNotifier {
  final UserService _userService = UserService();
  final UserDetailsService _userDetailsService = UserDetailsService();

  List<User> _allUsers = [];
  List<User> _filteredUsers = [];
  Set<int> _selectedUserIds = {}; // Store selected user IDs
  bool _isLoading = false;
  String _error = '';
  String _searchQuery = '';
  String _statusFilter = 'all';
  String _userTypeFilter = 'all';
  bool _isSelectAll = false;
  bool _isSessionExpired = false;

  // Pagination state
  final int _pageSize = 50;
  int _displayPage = 1;

  final AdminSocketService _socketService = AdminSocketService();
  StreamSubscription<Map<String, dynamic>>? _presenceSub;
  final Map<int, ActivityStats> _activityByUser = {};
  final Set<int> _activityLoading = {};

  // Getters
  List<User> get filteredUsers => _filteredUsers;
  List<User> get allUsers => _allUsers;
  bool get isLoading => _isLoading;
  String get error => _error;
  int get totalCount => _allUsers.length;
  int get filteredCount => _filteredUsers.length;
  String get searchQuery => _searchQuery;
  String get statusFilter => _statusFilter;
  String get userTypeFilter => _userTypeFilter;
  Set<int> get selectedUserIds => _selectedUserIds;
  bool get isSelectAll => _isSelectAll;
  int get selectedCount => _selectedUserIds.length;
  bool get isSessionExpired => _isSessionExpired;
  ActivityStats? activityFor(int userId) => _activityByUser[userId];
  bool isActivityLoading(int userId) => _activityLoading.contains(userId);

  // Pagination getters
  int get _pageLimit => _displayPage * _pageSize;
  List<User> get pagedUsers => _filteredUsers.take(_pageLimit).toList();
  bool get hasMoreToShow => _filteredUsers.length > _pageLimit;

  final Set<int> _photoActioning = {};
  bool isPhotoActioning(int userId) => _photoActioning.contains(userId);

  /// Returns the [User] from the loaded list matching [userId], or null if not found.
  User? getUserById(int userId) {
    try {
      return _allUsers.firstWhere((u) => u.id == userId);
    } catch (_) {
      return null;
    }
  }

  // Check if all filtered users are selected
  bool get areAllFilteredSelected {
    if (_filteredUsers.isEmpty) return false;
    return _selectedUserIds.length == _filteredUsers.length &&
        _filteredUsers.every((user) => _selectedUserIds.contains(user.id));
  }

  Future<void> fetchUsers() async {
    _isLoading = true;
    _error = '';
    _isSessionExpired = false;
    notifyListeners();

    try {
      final response = await _userService.getUsers();
      _allUsers = response.data;
      _applyFilters();
      _socketService.connect();
      _startPresenceListener();
      _activityByUser.clear();
      _activityLoading.clear();
    } on UnauthorizedException {
      _isSessionExpired = true;
      _error = 'Session expired. Please log in again.';
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void _startPresenceListener() {
    _presenceSub?.cancel();
    _presenceSub = _socketService.onUserStatusChange.listen((data) {
      bool changed = false;
      final docId = data['userId']?.toString() ?? '';
      final isOnline = data['isOnline'] == true ? 1 : 0;
      if (docId.isEmpty) return;

      for (final user in _allUsers) {
        if (user.id.toString() == docId) {
          if (user.isOnline != isOnline) {
            user.isOnline = isOnline;
            changed = true;
          }
          break;
        }
      }
      if (changed) _applyFilters();
    }, onError: (e) {
      debugPrint('UserProvider presence error: $e');
    });
  }

  @override
  void dispose() {
    _presenceSub?.cancel();
    super.dispose();
  }

  // Selection methods
  void toggleUserSelection(int userId) {
    if (_selectedUserIds.contains(userId)) {
      _selectedUserIds.remove(userId);
    } else {
      _selectedUserIds.add(userId);
    }
    _updateSelectAllState();
    notifyListeners();
  }

  void selectAllUsers() {
    if (areAllFilteredSelected) {
      // Deselect all filtered users
      _selectedUserIds.removeAll(_filteredUsers.map((user) => user.id));
    } else {
      // Select all filtered users
      _selectedUserIds.addAll(_filteredUsers.map((user) => user.id));
    }
    _updateSelectAllState();
    notifyListeners();
  }

  void _updateSelectAllState() {
    _isSelectAll = areAllFilteredSelected;
  }

  void clearSelection() {
    _selectedUserIds.clear();
    _isSelectAll = false;
    notifyListeners();
  }

  Future<void> preloadActivity(int userId) async {
    if (_activityByUser.containsKey(userId) || _activityLoading.contains(userId)) {
      return;
    }
    _activityLoading.add(userId);
    // Schedule the loading-state notification for after the current build frame
    // so that notifyListeners() is never called synchronously during a build,
    // which can cause a "Cannot read properties of undefined" error in Flutter web.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_activityLoading.contains(userId)) notifyListeners();
    });
    try {
      final stats = await _userDetailsService.getUserActivity(userId);
      _activityByUser[userId] = stats;
    } catch (_) {
      // Ignore quietly; UI will show fallback values.
    } finally {
      _activityLoading.remove(userId);
      notifyListeners();
    }
  }

  bool isUserSelected(int userId) {
    return _selectedUserIds.contains(userId);
  }

  /// Approve or reject a user's profile photo from the member list card.
  Future<bool> approvePhoto(int userId, String action, {String? reason}) async {
    _photoActioning.add(userId);
    notifyListeners();
    try {
      final ok = await _userDetailsService.handleProfilePhotoRequest(
        userId: userId,
        action: action,
        reason: reason,
      );
      if (ok) {
        for (final u in _allUsers) {
          if (u.id == userId) {
            u.status = action == 'approve' ? 'approved' : 'rejected';
            break;
          }
        }
        _applyFilters();
      }
      return ok;
    } catch (_) {
      return false;
    } finally {
      _photoActioning.remove(userId);
      notifyListeners();
    }
  }

  // Action methods
  Future<void> suspendSelectedUsers(BuildContext context) async {
    if (_selectedUserIds.isEmpty) return;

    final ids = List<int>.from(_selectedUserIds);
    final confirmed = await _showConfirmationDialog(
        context,
        'Suspend Users',
        'Are you sure you want to suspend ${ids.length} user(s)?');

    if (!confirmed) return;

    _isLoading = true;
    notifyListeners();

    try {
      final result = await _userService.suspendUsers(
        userIds: ids,
        action: 'suspend',
      );

      if (result['success'] == true) {
        for (final user in _allUsers) {
          if (ids.contains(user.id)) {
            user.isActive = 0;
          }
        }
        _applyFilters();
        clearSelection();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message']?.toString() ??
                '${ids.length} user(s) suspended successfully'),
            backgroundColor: Colors.orange,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message']?.toString() ?? 'Failed to suspend users'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> deleteSelectedUsers(BuildContext context) async {
    if (_selectedUserIds.isEmpty) return;

    final ids = List<int>.from(_selectedUserIds);
    final confirmed = await _showConfirmationDialog(
        context,
        'Delete Users',
        'Are you sure you want to delete ${ids.length} user(s)? This action cannot be undone.');

    if (!confirmed) return;

    _isLoading = true;
    notifyListeners();

    try {
      final result = await _userService.deleteUsers(userIds: ids);

      if (result['success'] == true) {
        _allUsers.removeWhere((user) => ids.contains(user.id));
        _applyFilters();
        clearSelection();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message']?.toString() ??
                '${ids.length} user(s) deleted successfully'),
            backgroundColor: Colors.red,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message']?.toString() ?? 'Failed to delete users'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> _showConfirmationDialog(BuildContext context, String title, String message) async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: title.contains('Delete') ? Colors.red : Colors.orange,
            ),
            child: Text(title.contains('Delete') ? 'Delete' : 'Suspend'),
          ),
        ],
      ),
    ) ?? false;
  }

  void setSearchQuery(String query) {
    _searchQuery = query.toLowerCase();
    _applyFilters();
  }

  void setStatusFilter(String status) {
    _statusFilter = status;
    _applyFilters();
  }

  void setUserTypeFilter(String userType) {
    _userTypeFilter = userType;
    _applyFilters();
  }

  void _applyFilters() {
    List<User> filtered = List<User>.from(_allUsers);

    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((user) {
        final name = user.fullName.toLowerCase();
        final email = user.email.toLowerCase();
        final id = user.id.toString();
        final phone = (user.phone ?? '').toLowerCase();
        return name.contains(_searchQuery) ||
            email.contains(_searchQuery) ||
            id.contains(_searchQuery) ||
            phone.contains(_searchQuery);
      }).toList();
    }

    // Apply status filter
    if (_statusFilter != 'all') {
      filtered = filtered.where((user) => user.status == _statusFilter).toList();
    }

    // Apply user type filter
    if (_userTypeFilter != 'all') {
      filtered = filtered.where((user) => user.usertype == _userTypeFilter).toList();
    }

    resetPaging();
    _filteredUsers = filtered;
    notifyListeners();
  }

  void loadMoreUsers() {
    _displayPage++;
    notifyListeners();
  }

  /// Resets to page 1. Does NOT call [notifyListeners] — always called from
  /// [_applyFilters] which already triggers a notification.
  void resetPaging() {
    _displayPage = 1;
  }

  void clearFilters() {
    _searchQuery = '';
    _statusFilter = 'all';
    _userTypeFilter = 'all';
    _applyFilters();
  }

  Map<String, int> getStatusStats() {
    Map<String, int> stats = {
      'approved': 0,
      'pending': 0,
      'rejected': 0,
      'not_uploaded': 0,
    };

    for (var user in _allUsers) {
      if (stats.containsKey(user.status)) {
        stats[user.status] = stats[user.status]! + 1;
      }
    }

    return stats;
  }

  Map<String, int> getUserTypeStats() {
    Map<String, int> stats = {
      'paid': 0,
      'free': 0,
    };

    for (var user in _allUsers) {
      stats[user.usertype] = stats[user.usertype]! + 1;
    }

    return stats;
  }
}
