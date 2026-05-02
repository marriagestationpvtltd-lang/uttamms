import 'dart:async';
import 'dart:convert';
import 'package:adminmrz/adminchat/services/admin_socket_service.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../model/MatchedProfile.dart';
import 'package:adminmrz/config/app_endpoints.dart';

class MatchedProfileProvider with ChangeNotifier {
  String _name = '';
  bool _isloading = false;
  bool _isLoadingMore = false;
  bool _hasMore = false;
  int _currentPage = 1;
  int _totalCount = 0;
  static const int _perPage = 20;
  int? _currentUserId;
  String _memberid = '';

  // Search & filter state
  String _searchQuery = '';
  String _filterType = 'matched'; // 'matched' | 'all'

  final AdminSocketService _socketService = AdminSocketService();
  StreamSubscription<Map<String, dynamic>>? _presenceSub;

  String get memberid => _memberid;
  String get name => _name;
  bool get isloading => _isloading;
  bool get isLoadingMore => _isLoadingMore;
  bool get hasMore => _hasMore;
  int get totalCount => _totalCount;
  int get currentPage => _currentPage;
  String get searchQuery => _searchQuery;
  String get filterType => _filterType;

  List<MatchedProfile> _matchedProfiles = [];

  List<MatchedProfile> get profiles => List.unmodifiable(_matchedProfiles);

  // Getters for the specific fields you want to access
  List<String> get memberiddd =>
      _matchedProfiles.map((profile) => profile.memberid).toList();
  List<int> get ids => _matchedProfiles.map((profile) => profile.id).toList();
  List<String> get firstNames =>
      _matchedProfiles.map((profile) => profile.firstName).toList();
  List<String> get lastNames =>
      _matchedProfiles.map((profile) => profile.lastName).toList();
  List<double> get matchingPercentages =>
      _matchedProfiles.map((profile) => profile.matchingPercentage).toList();
  List<bool> get isPaidList =>
      _matchedProfiles.map((profile) => profile.isPaid).toList();
  List<bool> get isOnlineList =>
      _matchedProfiles.map((profile) => profile.isOnline).toList();
  List<String> get occupation =>
      _matchedProfiles.map((profile) => profile.occupation).toList();
  List<String> get education =>
      _matchedProfiles.map((profile) => profile.education).toList();
  List<String> get country =>
      _matchedProfiles.map((profile) => profile.country).toList();
  List<String> get marit =>
      _matchedProfiles.map((profile) => profile.marit).toList();
  List<String> get gender =>
      _matchedProfiles.map((profile) => profile.gender).toList();
  List<int> get age => _matchedProfiles.map((profile) => profile.age).toList();

  List<String> get profilePictures =>
      _matchedProfiles.map((profile) => profile.profilePicture).toList();

  bool _asBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final normalized = value?.toString().trim().toLowerCase() ?? '';
    return normalized == '1' || normalized == 'true' || normalized == 'yes';
  }

  List<MatchedProfile> _parseProfileList(dynamic rawList) {
    final list = rawList as List? ?? [];
    final out = <MatchedProfile>[];
    for (final item in list) {
      if (item is Map) {
        try {
          out.add(MatchedProfile.fromJson(Map<String, dynamic>.from(item)));
        } catch (e) {
          debugPrint('Skipping malformed matched profile item: $e');
        }
      }
    }
    return out;
  }

  List<MatchedProfile> _applyLocalSearchFilter(
    List<MatchedProfile> profiles,
    String query,
  ) {
    final trimmed = query.trim().toLowerCase();
    if (trimmed.isEmpty) return profiles;
    return profiles.where((p) {
      final fullName = ('${p.firstName} ${p.lastName}').toLowerCase();
      return fullName.contains(trimmed) ||
          p.memberid.toLowerCase().contains(trimmed);
    }).toList();
  }

  Future<(List<MatchedProfile>, int)> _fetchFromMatchAdmin(
    int userId, {
    int page = 1,
    String? filterTypeOverride,
  }) async {
    final response = await http.post(
      Uri.parse('${kAdminApiBaseUrl}/match_admin.php'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'user_id': userId,
        'page': page,
        'per_page': _perPage,
        if (_searchQuery.isNotEmpty) 'search': _searchQuery,
        'filter_type': filterTypeOverride ?? _filterType,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to load matched profiles: ${response.statusCode}',
      );
    }

    final data = json.decode(response.body);
    final pageProfiles = _parseProfileList(data['data']);
    final totalCount = data['total'] is int
        ? data['total'] as int
        : int.tryParse(data['total']?.toString() ?? '') ?? pageProfiles.length;

    return (pageProfiles, totalCount);
  }

  Future<List<MatchedProfile>> _fetchFromLegacyMatched(int userId) async {
    final response = await http.post(
      Uri.parse('${kAdminApiBaseUrl}/matched.php'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'user_id': userId}),
    );

    if (response.statusCode != 200) return const <MatchedProfile>[];

    final data = json.decode(response.body);
    if (data is! Map || data['status'] != 'success') {
      return const <MatchedProfile>[];
    }

    final parsed = _parseProfileList(data['data']);
    return _applyLocalSearchFilter(parsed, _searchQuery);
  }

  // Fetch only page 1 – subsequent pages are loaded lazily via fetchMoreProfiles().
  Future<void> fetchMatchedProfiles(
    int userId, {
    String? filterType,
    String? searchQuery,
  }) async {
    _currentUserId = userId;
    if (filterType != null) _filterType = filterType;
    if (searchQuery != null) _searchQuery = searchQuery;
    _currentPage = 1;
    _hasMore = false;
    _isloading = true;
    _matchedProfiles = [];
    notifyListeners();

    try {
      List<MatchedProfile> pageProfiles = const <MatchedProfile>[];
      int resolvedTotalCount = 0;

      try {
        final (profiles, total) = await _fetchFromMatchAdmin(userId, page: 1);
        pageProfiles = profiles;
        resolvedTotalCount = total;
      } catch (e) {
        debugPrint('match_admin.php request failed: $e');
      }

      // Local fallback path:
      // 1) old matched.php endpoint (historically used in this project)
      // 2) relaxed filter_type=all if strict matched returns empty
      if (pageProfiles.isEmpty) {
        final legacyProfiles = await _fetchFromLegacyMatched(userId);
        if (legacyProfiles.isNotEmpty) {
          pageProfiles = legacyProfiles;
          resolvedTotalCount = legacyProfiles.length;
        }
      }

      if (pageProfiles.isEmpty && _filterType == 'matched') {
        try {
          final (profiles, total) = await _fetchFromMatchAdmin(
            userId,
            page: 1,
            filterTypeOverride: 'all',
          );
          pageProfiles = profiles;
          resolvedTotalCount = total;
        } catch (e) {
          debugPrint('Relaxed all-filter fallback failed: $e');
        }
      }

      _matchedProfiles = pageProfiles;

      _totalCount = resolvedTotalCount > 0
          ? resolvedTotalCount
          : pageProfiles.length;

      _hasMore =
          pageProfiles.length >= _perPage &&
          _matchedProfiles.length < _totalCount;
      _currentPage = 2;

      if (_matchedProfiles.isNotEmpty) {
        _name = _matchedProfiles.first.firstName;
        _memberid = _matchedProfiles.first.memberid;
      } else {
        _name = '';
        _memberid = '';
      }
    } catch (e) {
      debugPrint('Error fetching matched profiles: $e');
    } finally {
      _isloading = false;
      notifyListeners();
    }
  }

  // Lazy-load the next page and append results.
  Future<void> fetchMoreProfiles() async {
    if (_isLoadingMore || !_hasMore || _currentUserId == null) return;
    _isLoadingMore = true;
    notifyListeners();

    try {
      final (pageProfiles, total) = await _fetchFromMatchAdmin(
        _currentUserId!,
        page: _currentPage,
      );

      // Deduplicate by id before appending
      final existingIds = _matchedProfiles.map((p) => p.id).toSet();
      final newProfiles = pageProfiles
          .where((p) => !existingIds.contains(p.id))
          .toList();

      _matchedProfiles.addAll(newProfiles);
      _currentPage++;

      _totalCount = total > 0 ? total : _matchedProfiles.length;

      _hasMore =
          pageProfiles.length >= _perPage &&
          _matchedProfiles.length < _totalCount;
    } catch (e) {
      debugPrint('Error fetching more profiles: $e');
    } finally {
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  // Update search query and reset pagination (server-side search).
  Future<void> updateSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed == _searchQuery) return;
    _searchQuery = trimmed;
    if (_currentUserId != null) {
      await fetchMatchedProfiles(_currentUserId!);
    }
  }

  // Change filter type ('matched' | 'all') and reset pagination.
  Future<void> updateFilterType(String type) async {
    if (type == _filterType) return;
    _filterType = type;
    if (_currentUserId != null) {
      await fetchMatchedProfiles(_currentUserId!);
    }
  }

  // Helper methods
  String getProfilePicture(int index) {
    if (index < 0 || index >= _matchedProfiles.length) return '';
    return _matchedProfiles[index].profilePicture;
  }

  bool isPaid(int index) {
    if (index < 0 || index >= _matchedProfiles.length) return false;
    return _matchedProfiles[index].isPaid;
  }

  bool isOnline(int index) {
    if (index < 0 || index >= _matchedProfiles.length) return false;
    return _matchedProfiles[index].isOnline;
  }

  String getFullName(int index) {
    if (index < 0 || index >= _matchedProfiles.length) return '';
    return '${_matchedProfiles[index].firstName} ${_matchedProfiles[index].lastName}';
  }

  // Lightweight refresh: re-fetch current profiles and update only isOnline field
  Future<void> refreshOnlineStatuses() async {
    if (_currentUserId == null || _matchedProfiles.isEmpty) return;

    try {
      final response = await http.post(
        Uri.parse('${kAdminApiBaseUrl}/match_admin.php'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'user_id': _currentUserId,
          'page': 1,
          'per_page': _matchedProfiles.length.clamp(_perPage, 100),
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final list = data['data'] as List? ?? [];

        // Build a lookup map: id -> isOnline
        final Map<int, bool> onlineMap = {
          for (var item in list)
            int.tryParse(item['id']?.toString() ?? '') ?? 0: _asBool(
              item['is_online'],
            ),
        };

        // Update only isOnline without disturbing order or other fields
        bool changed = false;
        final updated = _matchedProfiles.map((profile) {
          final newStatus = onlineMap[profile.id];
          if (newStatus != null && newStatus != profile.isOnline) {
            changed = true;
            return profile.copyWith(isOnline: newStatus);
          }
          return profile;
        }).toList();

        if (changed) {
          _matchedProfiles = updated;
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('Error refreshing online statuses: $e');
    }
  }

  void clearData() {
    _matchedProfiles.clear();
    _name = '';
    _memberid = '';
    _hasMore = false;
    _currentPage = 1;
    _totalCount = 0;
    _currentUserId = null;
    _isloading = false;
    _isLoadingMore = false;
    _searchQuery = '';
    _filterType = 'matched';
    stopPresenceListener();
    notifyListeners();
  }

  // Start a socket-based presence listener that immediately reflects
  // online/offline changes for the currently loaded matched profiles.
  void startPresenceListener() {
    _presenceSub?.cancel();
    _socketService.connect();
    _presenceSub = _socketService.onUserStatusChange.listen(
      (data) {
        bool changed = false;
        final int userId = int.tryParse(data['userId']?.toString() ?? '') ?? -1;
        if (userId == -1) return;
        final bool isOnline = data['isOnline'] == true;

        final idx = _matchedProfiles.indexWhere((p) => p.id == userId);
        if (idx != -1 && _matchedProfiles[idx].isOnline != isOnline) {
          _matchedProfiles[idx] = _matchedProfiles[idx].copyWith(
            isOnline: isOnline,
          );
          changed = true;
        }
        if (changed) notifyListeners();
      },
      onError: (e) {
        debugPrint('MatchedProfile presence listener error: $e');
      },
    );
  }

  void stopPresenceListener() {
    _presenceSub?.cancel();
    _presenceSub = null;
  }
}
