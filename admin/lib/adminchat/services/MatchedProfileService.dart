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
  List<MatchedProfile> _allMatchedProfiles = [];

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

  String _normalizeProfilePicture(String rawPath) {
    final trimmed = rawPath.trim();
    if (trimmed.isEmpty || trimmed.startsWith('http')) return trimmed;
    final root = kAdminApiBaseUrl.endsWith('/Backend')
        ? kAdminApiBaseUrl.substring(
            0,
            kAdminApiBaseUrl.length - '/Backend'.length,
          )
        : kAdminApiBaseUrl;
    return '$root/${trimmed.startsWith('/') ? trimmed.substring(1) : trimmed}';
  }

  List<MatchedProfile> _normalizeProfiles(List<MatchedProfile> profiles) {
    return profiles
        .map(
          (profile) => MatchedProfile(
            id: profile.id,
            firstName: profile.firstName,
            lastName: profile.lastName,
            memberid: profile.memberid,
            matchingPercentage: profile.matchingPercentage,
            isPaid: profile.isPaid,
            isOnline: profile.isOnline,
            occupation: profile.occupation,
            education: profile.education,
            country: profile.country,
            marit: profile.marit,
            gender: profile.gender,
            age: profile.age,
            profilePicture: _normalizeProfilePicture(profile.profilePicture),
          ),
        )
        .toList();
  }

  void _syncVisibleProfiles({bool resetPage = true}) {
    final filtered = _applyLocalSearchFilter(_allMatchedProfiles, _searchQuery);
    _totalCount = filtered.length;

    if (resetPage) {
      _currentPage = 1;
      _matchedProfiles = filtered.take(_perPage).toList();
    }

    _hasMore = _matchedProfiles.length < filtered.length;
    if (_hasMore && _currentPage < 2) {
      _currentPage = 2;
    }

    if (_matchedProfiles.isNotEmpty) {
      _name = _matchedProfiles.first.firstName;
      _memberid = _matchedProfiles.first.memberid;
    } else {
      _name = '';
      _memberid = '';
    }
  }

  Future<List<MatchedProfile>> _fetchFromUnifiedMatch(int userId) async {
    final url = '$kAdminApi2BaseUrl/match.php?userid=$userId';
    debugPrint('[MatchedProfile] Fetching: $url');
    final response = await http.get(Uri.parse(url));

    debugPrint('[MatchedProfile] Response status: ${response.statusCode}');
    if (response.statusCode != 200) {
      throw Exception('Failed to load unified matches: ${response.statusCode}');
    }

    final data = json.decode(response.body);
    debugPrint(
      '[MatchedProfile] success=${data['success']} type=${data['success'].runtimeType}',
    );
    if (data is! Map || data['success'] != true) {
      throw Exception(
        data is Map
            ? (data['message'] ?? 'Unified match request failed')
            : 'Unified match request failed',
      );
    }

    final rawList = data['matched_users'];
    debugPrint('[MatchedProfile] matched_users count=${rawList?.length ?? 0}');
    final parsed = _normalizeProfiles(_parseProfileList(rawList));
    debugPrint('[MatchedProfile] parsed profiles: ${parsed.length}');
    final dedupedById = <int, MatchedProfile>{
      for (final profile in parsed) profile.id: profile,
    };
    final list = dedupedById.values.toList()
      ..sort((a, b) => b.matchingPercentage.compareTo(a.matchingPercentage));
    debugPrint('[MatchedProfile] deduped+sorted: ${list.length}');
    return list;
  }

  Future<(List<MatchedProfile>, int)> _fetchFromMatchAdmin(
    int userId, {
    int page = 1,
    String? filterTypeOverride,
  }) async {
    final response = await http.post(
      Uri.parse('$kAdminApiBaseUrl/match_admin.php'),
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
      Uri.parse('$kAdminApiBaseUrl/matched.php'),
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
    _allMatchedProfiles = [];
    _matchedProfiles = [];
    notifyListeners();

    debugPrint('[MatchedProfile] fetchMatchedProfiles start userId=$userId');
    try {
      try {
        _allMatchedProfiles = await _fetchFromUnifiedMatch(userId);
        debugPrint(
          '[MatchedProfile] _allMatchedProfiles.length=${_allMatchedProfiles.length}',
        );
        _syncVisibleProfiles(resetPage: true);
        debugPrint(
          '[MatchedProfile] _matchedProfiles.length=${_matchedProfiles.length} _totalCount=$_totalCount',
        );
        return;
      } catch (e) {
        debugPrint(
          '[MatchedProfile] Unified Api2/match.php request failed: $e',
        );
      }

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

      _allMatchedProfiles = _normalizeProfiles(pageProfiles);
      _matchedProfiles = List<MatchedProfile>.from(_allMatchedProfiles);
      _totalCount = resolvedTotalCount > 0
          ? resolvedTotalCount
          : _matchedProfiles.length;
      _hasMore = false;
      _currentPage = 1;

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
      final filtered = _applyLocalSearchFilter(
        _allMatchedProfiles,
        _searchQuery,
      );
      final nextPage = filtered
          .skip(_matchedProfiles.length)
          .take(_perPage)
          .toList();
      if (nextPage.isNotEmpty) {
        _matchedProfiles.addAll(nextPage);
        _currentPage++;
      }
      _totalCount = filtered.length;
      _hasMore = _matchedProfiles.length < filtered.length;
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
    _syncVisibleProfiles(resetPage: true);
    notifyListeners();
  }

  // Change filter type ('matched' | 'all') and reset pagination.
  Future<void> updateFilterType(String type) async {
    if (type == _filterType) return;
    _filterType = type;
    _syncVisibleProfiles(resetPage: true);
    notifyListeners();
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
    if (_currentUserId == null || _allMatchedProfiles.isEmpty) return;

    try {
      final response = await http.get(
        Uri.parse('$kAdminApi2BaseUrl/match.php?userid=${_currentUserId!}'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final list = data['matched_users'] as List? ?? [];

        // Build a lookup map: id -> isOnline
        final Map<int, bool> onlineMap = {
          for (var item in list)
            int.tryParse((item['userid'] ?? item['id'])?.toString() ?? '') ?? 0:
                _asBool(item['is_online']),
        };

        // Update only isOnline without disturbing order or other fields
        bool changed = false;
        final updatedAll = _allMatchedProfiles.map((profile) {
          final newStatus = onlineMap[profile.id];
          if (newStatus != null && newStatus != profile.isOnline) {
            changed = true;
            return profile.copyWith(isOnline: newStatus);
          }
          return profile;
        }).toList();

        if (changed) {
          _allMatchedProfiles = updatedAll;
          _syncVisibleProfiles(resetPage: true);
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('Error refreshing online statuses: $e');
    }
  }

  void clearData() {
    _allMatchedProfiles.clear();
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
