import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui' as ui;
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/user_state.dart';
import '../main.dart';
import 'SearchResult.dart';
import 'package:ms2026/config/app_endpoints.dart';
import '../ReUsable/loading_widgets.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage>
    with SingleTickerProviderStateMixin {
  // ── tabs ──
  late TabController _tabController;

  // ── Quick Search ──
  final TextEditingController _quickSearchController = TextEditingController();
  final FocusNode _quickSearchFocus = FocusNode();
  List<String> recentSearches = [];

  // ── Recommended profiles (Quick Search tab background) ──
  List<dynamic> _recommendedProfiles = [];
  bool _isLoading = true;
  String _errorMessage = '';
  int _currentUserId = 0;
  Set<int> _blockedUserIds = {};

  // ── Advanced Search (filter) state ──
  RangeValues _ageRange = const RangeValues(22, 60);
  RangeValues _heightRange = const RangeValues(121, 215);
  String _religion = "Any";
  String _maritalStatus = "Any";
  String _education = "Any";
  String _annualIncome = "Any";
  String _occupation = "Any";
  String _familyType = "Any";
  String _diet = "Any";
  String _smoking = "Any";
  String _drinking = "Any";
  String _cityFilter = "";
  final TextEditingController _cityController = TextEditingController();

  // Quick filter state
  bool _hasPhotoOnly = false;
  String _membershipType = "All";
  bool _verifiedOnly = false;
  String _newlyRegistered = "All";

  int _matchesCount = 0;
  int _initialTotalCount = 0;
  bool _isLoadingCount = true;
  bool _isInitialLoad = true;
  Map<String, dynamic> _filterParams = {};
  Timer? _debounceTimer;

  // Dropdown option lists
  static const List<String> _religionOptions = [
    "Any", "Hindu", "Buddhist", "Muslim", "Christian", "Sikh", "Jain", "Other"
  ];
  static const List<String> _maritalOptions = [
    "Any", "Never Married", "Divorced", "Widowed", "Awaiting Divorce"
  ];
  static const List<String> _educationOptions = [
    "Any", "High School", "Intermediate", "Bachelor", "Master", "PhD", "Diploma", "Other"
  ];
  static const List<String> _incomeOptions = [
    "Any", "Below 2 Lakh", "2 To 5 Lakh", "5 To 10 Lakh",
    "10 To 20 Lakh", "20 To 30 Lakh", "Above 30 Lakh"
  ];
  static const List<String> _occupationOptions = [
    "Any", "Government Job", "Private Job", "Self Employed / Business",
    "Doctor", "Engineer", "Teacher / Professor", "Lawyer", "Army / Police",
    "IT Professional", "Accountant", "Not Working", "Other"
  ];
  static const List<String> _familyTypeOptions = [
    "Any", "Nuclear", "Joint", "Extended"
  ];
  static const List<String> _dietOptions = [
    "Any", "Vegetarian", "Non-Vegetarian", "Vegan", "Eggetarian"
  ];
  static const List<String> _smokeOptions = [
    "Any", "No", "Yes", "Occasionally"
  ];
  static const List<String> _drinkOptions = [
    "Any", "No", "Yes", "Occasionally"
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _quickSearchFocus.addListener(() => setState(() {}));
    _loadUserDataAndFetchProfiles();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _quickSearchController.dispose();
    _quickSearchFocus.dispose();
    _cityController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  // Load user data and fetch recommended profiles
  Future<void> _loadUserDataAndFetchProfiles() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataString = prefs.getString('user_data');
      if (userDataString == null) {
        setState(() { _errorMessage = 'User data not found'; _isLoading = false; });
        return;
      }
      final userData = jsonDecode(userDataString);
      final userId = int.tryParse(userData["id"].toString()) ?? 0;
      setState(() { _currentUserId = userId; });

      if (userId > 0) {
        await _fetchBlockedUsers();
        await Future.wait([
          _fetchRecommendedProfiles(userId),
          _fetchInitialTotalCount(),
        ]);
      } else {
        setState(() { _errorMessage = 'Invalid user ID'; _isLoading = false; });
      }
    } catch (e) {
      setState(() { _errorMessage = 'Failed to load user data: $e'; _isLoading = false; });
    }
  }

  Future<void> _fetchBlockedUsers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataString = prefs.getString('user_data');
      if (userDataString == null) return;
      final userData = jsonDecode(userDataString);
      final myId = userData["id"].toString();
      final response = await http.post(
        Uri.parse('${kApiBaseUrl}/Api2/get_blocked_users.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'my_id': myId}),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'success') {
          final blockedUsers = List<Map<String, dynamic>>.from(data['users'] ?? []);
          setState(() {
            _blockedUserIds = blockedUsers
                .map((user) => int.tryParse(user['id'].toString()) ?? 0)
                .where((id) => id != 0)
                .toSet();
          });
        }
      }
    } catch (e) {
      debugPrint("Error fetching blocked users: $e");
    }
  }

  Future<void> _fetchRecommendedProfiles(int userId) async {
    try {
      setState(() { _isLoading = true; _errorMessage = ''; });
      final url = Uri.parse('${kApiBaseUrl}/Api2/match.php?userid=$userId');
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          final allProfiles = result['matched_users'] ?? [];
          final filteredProfiles = allProfiles.where((profile) {
            final profileId = int.tryParse(profile['userid']?.toString() ?? '0') ?? 0;
            return !_blockedUserIds.contains(profileId);
          }).toList();
          setState(() { _recommendedProfiles = filteredProfiles; _isLoading = false; });
        } else {
          throw Exception(result['message'] ?? 'Failed to load recommended profiles');
        }
      } else {
        throw Exception('Failed to load data: ${response.statusCode}');
      }
    } catch (e) {
      setState(() { _errorMessage = e.toString(); _isLoading = false; });
      debugPrint('Error fetching recommended profiles: $e');
    }
  }

  bool _shouldShowClearImage(Map<String, dynamic> profile) {
    // Prefer backend-computed result when available
    if (profile.containsKey('can_view_photo')) {
      return profile['can_view_photo'] == true;
    }
    // Only accept when photo request is accepted - ignore privacy
    final photoRequest = profile['photo_request']?.toString().toLowerCase() ?? '';
    return photoRequest == 'accepted';
  }

  String _getPhotoRequestStatus(Map<String, dynamic> profile) {
    final photoRequest = profile['photo_request']?.toString().toLowerCase() ?? '';
    if (photoRequest.isEmpty || photoRequest == 'null') return 'not_sent';
    return photoRequest;
  }

  void _handleDocumentNotApproved() {
    final status = context.read<UserState>().identityStatus;
    String msg = '';
    Color color = Colors.red;
    if (status == 'not_uploaded') {
      msg = 'Please upload your documents first';
    } else if (status == 'pending') {
      msg = 'Your documents are pending approval';
      color = Colors.orange;
    } else if (status == 'rejected') {
      msg = 'Your documents were rejected. Please re-upload';
    }
    if (msg.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: color, duration: const Duration(seconds: 3)),
      );
    }
  }

  // ── Advanced Search helpers ────────────────────────────────────────────────

  Future<void> _loadFilterCount() async {
    if (_currentUserId == 0) return;
    await _fetchInitialTotalCount();
  }

  Future<void> _fetchInitialTotalCount() async {
    if (_currentUserId == 0) {
      setState(() { _isLoadingCount = false; _matchesCount = 0; _initialTotalCount = 0; });
      return;
    }
    try {
      final url = Uri.parse(
          '${kApiBaseUrl}/Api2/search_opposite_gender.php?user_id=$_currentUserId');
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          setState(() {
            _initialTotalCount = result['total_count'] ?? 0;
            _matchesCount = _initialTotalCount;
            _isLoadingCount = false;
            _isInitialLoad = false;
          });
        } else {
          setState(() { _isLoadingCount = false; _isInitialLoad = false; });
        }
      } else {
        setState(() { _isLoadingCount = false; _isInitialLoad = false; });
      }
    } catch (e) {
      setState(() { _isLoadingCount = false; _isInitialLoad = false; });
    }
  }

  int? _getReligionId(String religion) {
    switch (religion) {
      case "Hindu":     return 1;
      case "Buddhist":  return 4;
      case "Muslim":    return 3;
      case "Christian": return 2;
      case "Sikh":      return 5;
      case "Jain":      return 6;
      default:          return null;
    }
  }

  bool _areFiltersApplied() {
    return _ageRange.start != 22 ||
        _ageRange.end != 60 ||
        _heightRange.start != 121 ||
        _heightRange.end != 215 ||
        _religion != "Any" ||
        _maritalStatus != "Any" ||
        _education != "Any" ||
        _annualIncome != "Any" ||
        _occupation != "Any" ||
        _familyType != "Any" ||
        _diet != "Any" ||
        _smoking != "Any" ||
        _drinking != "Any" ||
        _cityFilter.isNotEmpty ||
        _hasPhotoOnly ||
        _membershipType != "All" ||
        _verifiedOnly ||
        _newlyRegistered != "All";
  }

  Map<String, dynamic> _buildFilterParams() {
    final Map<String, dynamic> params = {};

    if (_ageRange.start != 22 || _ageRange.end != 60) {
      params['minage'] = _ageRange.start.round();
      params['maxage'] = _ageRange.end.round();
    }
    if (_heightRange.start != 121 || _heightRange.end != 215) {
      params['minheight'] = _heightRange.start.round();
      params['maxheight'] = _heightRange.end.round();
    }
    if (_religion != "Any") {
      final id = _getReligionId(_religion);
      if (id != null) params['religion'] = id;
    }
    if (_maritalStatus != "Any") params['marital_status'] = _maritalStatus;
    if (_education != "Any")     params['education']      = _education;
    if (_annualIncome != "Any")  params['annual_income']  = _annualIncome;
    if (_occupation != "Any")    params['occupation']     = _occupation;
    if (_familyType != "Any")    params['family_type']    = _familyType;
    if (_diet != "Any")          params['diet']           = _diet;
    if (_smoking != "Any")       params['smoking']        = _smoking;
    if (_drinking != "Any")      params['drinking']       = _drinking;
    if (_cityFilter.isNotEmpty)  params['city']           = _cityFilter;

    if (_hasPhotoOnly)           params['has_photo']      = '1';
    if (_membershipType != "All") params['usertype']      = _membershipType.toLowerCase();
    if (_verifiedOnly)           params['is_verified']    = '1';
    if (_newlyRegistered != "All") {
      if (_newlyRegistered.contains("7"))       params['days_since_registration'] = '7';
      else if (_newlyRegistered.contains("15")) params['days_since_registration'] = '15';
      else if (_newlyRegistered.contains("30")) params['days_since_registration'] = '30';
    }

    return params;
  }

  void _fetchMatchesCount() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () async {
      if (!mounted) return;
      setState(() => _isLoadingCount = true);
      try {
        _filterParams = _buildFilterParams();
        if (_filterParams.isEmpty) {
          setState(() { _matchesCount = _initialTotalCount; _isLoadingCount = false; });
          return;
        }
        final filteredParams = Map<String, dynamic>.from(_filterParams)
          ..removeWhere((key, value) => value == null);
        final queryParams = {
          'user_id': _currentUserId.toString(),
          ...filteredParams.map((key, value) => MapEntry(key, value.toString())),
        };
        final queryString = Uri(queryParameters: queryParams).query;
        final url = Uri.parse('${kApiBaseUrl}/Api2/search_opposite_gender.php?$queryString');
        final response = await http.get(url);
        if (response.statusCode == 200) {
          final result = jsonDecode(response.body);
          if (result['success'] == true) {
            if (mounted) {
              setState(() { _matchesCount = result['total_count'] ?? 0; _isLoadingCount = false; });
            }
          }
        } else {
          if (mounted) setState(() => _isLoadingCount = false);
        }
      } catch (e) {
        if (mounted) setState(() { _matchesCount = 0; _isLoadingCount = false; });
      }
    });
  }

  void _handleFilterChange() => _fetchMatchesCount();

  void _clearAllFilters() {
    _cityController.clear();
    setState(() {
      _ageRange = const RangeValues(22, 60);
      _heightRange = const RangeValues(121, 215);
      _religion = "Any";
      _maritalStatus = "Any";
      _education = "Any";
      _annualIncome = "Any";
      _occupation = "Any";
      _familyType = "Any";
      _diet = "Any";
      _smoking = "Any";
      _drinking = "Any";
      _cityFilter = "";
      _hasPhotoOnly = false;
      _membershipType = "All";
      _verifiedOnly = false;
      _newlyRegistered = "All";
      _matchesCount = _initialTotalCount;
      _filterParams = {};
    });
  }

  // ── Quick search ──────────────────────────────────────────────────────────

  void _performQuickSearch() {
    final query = _quickSearchController.text.trim();
    if (query.isEmpty) return;
    FocusScope.of(context).unfocus();
    if (!recentSearches.contains(query)) {
      setState(() {
        recentSearches.insert(0, query);
        if (recentSearches.length > 5) recentSearches.removeLast();
      });
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SearchResultPage(
          quickSearchType: 'name',
          quickSearchValue: query,
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemStatusBarContrastEnforced: false,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFFF7F7F7),
        body: Column(
          children: [
            _buildGradientHeader(),
            _buildTabBar(),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildQuickSearchTab(),
                  _buildAdvancedSearchTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Gradient header ───────────────────────────────────────────────────────

  Widget _buildGradientHeader() {
    return Container(
      padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: MediaQuery.of(context).padding.top + 8,
          bottom: 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xffFF1500), Color(0xffFF5A60)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: const Icon(Icons.arrow_back, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Find Your Match',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Search by name or use advanced filters',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.favorite, color: Colors.white, size: 22),
          ),
        ],
      ),
    );
  }

  // ── Tab bar ───────────────────────────────────────────────────────────────

  Widget _buildTabBar() {
    return Container(
      color: Colors.white,
      child: TabBar(
        controller: _tabController,
        onTap: (index) {
          if (index == 1 && _currentUserId > 0 && _isInitialLoad) {
            _loadFilterCount();
          }
        },
        labelColor: const Color(0xffFF1500),
        unselectedLabelColor: Colors.grey,
        indicatorColor: const Color(0xffFF1500),
        indicatorWeight: 3,
        labelStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        tabs: const [
          Tab(icon: Icon(Icons.search, size: 20), text: 'Quick Search'),
          Tab(icon: Icon(Icons.tune, size: 20), text: 'Advanced Search'),
        ],
      ),
    );
  }

  // ── QUICK SEARCH TAB ──────────────────────────────────────────────────────

  Widget _buildQuickSearchTab() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSearchInputCard(),
          if (recentSearches.isNotEmpty) _buildRecentSearches(),
          _buildRecommendedSection(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSearchInputCard() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                color: const Color(0xFFF7F7F7),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _quickSearchFocus.hasFocus
                      ? const Color(0xffFF1500)
                      : Colors.grey.shade300,
                ),
              ),
              child: TextField(
                controller: _quickSearchController,
                focusNode: _quickSearchFocus,
                keyboardType: TextInputType.name,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _performQuickSearch(),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Search by name…',
                  hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                  prefixIcon: Icon(Icons.search, color: Colors.grey.shade400, size: 22),
                  suffixIcon: _quickSearchController.text.isNotEmpty
                      ? GestureDetector(
                          onTap: () {
                            _quickSearchController.clear();
                            setState(() {});
                          },
                          child: Icon(Icons.clear, color: Colors.grey.shade400, size: 20),
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _quickSearchController.text.trim().isNotEmpty
                ? _performQuickSearch
                : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 52,
              width: 52,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: _quickSearchController.text.trim().isNotEmpty
                      ? [const Color(0xffFF1500), const Color(0xffFF5A60)]
                      : [Colors.grey.shade300, Colors.grey.shade300],
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.search, color: Colors.white, size: 24),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentSearches() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Recent Searches',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87)),
              GestureDetector(
                onTap: () => setState(() => recentSearches.clear()),
                child: const Text('Clear all',
                    style: TextStyle(fontSize: 13, color: Color(0xffFF1500), fontWeight: FontWeight.w500)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: recentSearches.map((term) => GestureDetector(
              onTap: () {
                _quickSearchController.text = term;
                _performQuickSearch();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F3F3),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.history, size: 14, color: Colors.grey),
                    const SizedBox(width: 6),
                    Text(term, style: const TextStyle(fontSize: 13, color: Colors.black87)),
                  ],
                ),
              ),
            )).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildRecommendedSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Recommended For You',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.black87)),
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SearchResultPage()),
                ),
                child: const Text('See all',
                    style: TextStyle(fontSize: 13, color: Color(0xffFF1500), fontWeight: FontWeight.w500)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildRecommendedGrid(),
        ],
      ),
    );
  }

  Widget _buildRecommendedGrid() {
    if (_isLoading) {
      return const SizedBox(height: 300, child: SearchProfileGridSkeleton(count: 4));
    }
    if (_errorMessage.isNotEmpty) {
      return SizedBox(
        height: 200,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 40),
              const SizedBox(height: 8),
              Text(_errorMessage, style: const TextStyle(color: Colors.grey), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: _loadUserDataAndFetchProfiles,
                icon: const Icon(Icons.refresh, color: Color(0xffFF1500)),
                label: const Text('Retry', style: TextStyle(color: Color(0xffFF1500))),
              ),
            ],
          ),
        ),
      );
    }
    if (_recommendedProfiles.isEmpty) {
      return const SizedBox(
        height: 200,
        child: Center(child: Text('No recommendations found', style: TextStyle(color: Colors.grey))),
      );
    }
    final count = _recommendedProfiles.length > 4 ? 4 : _recommendedProfiles.length;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: count,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.65,
      ),
      itemBuilder: (_, i) => _buildProfileCard(_recommendedProfiles[i]),
    );
  }

  // ── ADVANCED SEARCH TAB ───────────────────────────────────────────────────

  Widget _buildAdvancedSearchTab() {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 14),
                _buildAdvFilterHeader(),
                const SizedBox(height: 20),

                // ── Quick Filters ──
                _buildQuickFiltersSection(),
                const SizedBox(height: 24),

                // ── Age ──
                _buildFilterLabel('Age Range'),
                _buildRangeSlider(_ageRange, 18, 70, (v) {
                  setState(() => _ageRange = v);
                  _handleFilterChange();
                }),
                const SizedBox(height: 20),

                // ── Height ──
                _buildFilterLabel('Height Range (cm)'),
                _buildRangeSlider(_heightRange, 100, 250, (v) {
                  setState(() => _heightRange = v);
                  _handleFilterChange();
                }),
                const SizedBox(height: 20),

                // ── Marital Status ──
                _buildFilterLabel('Marital Status'),
                const SizedBox(height: 8),
                _buildDropdown(_maritalStatus, _maritalOptions, (v) {
                  setState(() => _maritalStatus = v!);
                  _handleFilterChange();
                }),
                const SizedBox(height: 20),

                // ── Religion ──
                _buildFilterLabel('Religion'),
                const SizedBox(height: 8),
                _buildDropdown(_religion, _religionOptions, (v) {
                  setState(() => _religion = v!);
                  _handleFilterChange();
                }),
                const SizedBox(height: 20),

                // ── Education ──
                _buildFilterLabel('Education'),
                const SizedBox(height: 8),
                _buildDropdown(_education, _educationOptions, (v) {
                  setState(() => _education = v!);
                  _handleFilterChange();
                }),
                const SizedBox(height: 20),

                // ── Annual Income ──
                _buildFilterLabel('Annual Income'),
                const SizedBox(height: 8),
                _buildDropdown(_annualIncome, _incomeOptions, (v) {
                  setState(() => _annualIncome = v!);
                  _handleFilterChange();
                }),
                const SizedBox(height: 20),

                // ── Occupation ──
                _buildFilterLabel('Occupation'),
                const SizedBox(height: 8),
                _buildDropdown(_occupation, _occupationOptions, (v) {
                  setState(() => _occupation = v!);
                  _handleFilterChange();
                }),
                const SizedBox(height: 20),

                // ── Family Type ──
                _buildFilterLabel('Family Type'),
                const SizedBox(height: 8),
                _buildDropdown(_familyType, _familyTypeOptions, (v) {
                  setState(() => _familyType = v!);
                  _handleFilterChange();
                }),
                const SizedBox(height: 20),

                // ── Diet ──
                _buildFilterLabel('Diet'),
                const SizedBox(height: 8),
                _buildDropdown(_diet, _dietOptions, (v) {
                  setState(() => _diet = v!);
                  _handleFilterChange();
                }),
                const SizedBox(height: 20),

                // ── Smoking & Drinking (side by side) ──
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildFilterLabel('Smoking'),
                          const SizedBox(height: 8),
                          _buildDropdown(_smoking, _smokeOptions, (v) {
                            setState(() => _smoking = v!);
                            _handleFilterChange();
                          }),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildFilterLabel('Drinking'),
                          const SizedBox(height: 8),
                          _buildDropdown(_drinking, _drinkOptions, (v) {
                            setState(() => _drinking = v!);
                            _handleFilterChange();
                          }),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // ── Location (City) ──
                _buildFilterLabel('City / Location'),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.shade100,
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: _cityController,
                    keyboardType: TextInputType.text,
                    decoration: InputDecoration(
                      hintText: 'Enter city or location…',
                      hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                      prefixIcon: Icon(Icons.location_on_outlined, color: Colors.grey.shade500, size: 20),
                      suffixIcon: _cityFilter.isNotEmpty
                          ? GestureDetector(
                              onTap: () {
                                _cityController.clear();
                                setState(() => _cityFilter = "");
                                _handleFilterChange();
                              },
                              child: Icon(Icons.clear, color: Colors.grey.shade400, size: 18),
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                    onChanged: (val) {
                      setState(() => _cityFilter = val.trim());
                      _handleFilterChange();
                    },
                  ),
                ),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
        _buildAdvancedSearchBottom(),
      ],
    );
  }

  Widget _buildAdvFilterHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text('Filter Options',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
        Row(
          children: [
            GestureDetector(
              onTap: _clearAllFilters,
              child: const Text('Clear all', style: TextStyle(fontSize: 14, color: Colors.grey)),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xffFF1500),
                borderRadius: BorderRadius.circular(20),
              ),
              child: _isLoadingCount
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                    )
                  : Text('$_matchesCount',
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAdvancedSearchBottom() {
    final filtersApplied = _areFiltersApplied();
    return Column(
      children: [
        Container(
          height: 44,
          color: const Color(0xFFF3F3F3),
          alignment: Alignment.center,
          child: _isLoadingCount
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    SizedBox(
                      width: 14, height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Color(0xffFF1500))),
                    ),
                    SizedBox(width: 8),
                    Text('Calculating matches…',
                        style: TextStyle(fontSize: 13, color: Colors.black54)),
                  ],
                )
              : Text(
                  _matchesCount == 1
                      ? '1 match${filtersApplied ? ' based on your filter' : ''}'
                      : '$_matchesCount matches${filtersApplied ? ' based on your filter' : ''}',
                  style: const TextStyle(fontSize: 13, color: Colors.black54),
                ),
        ),
        GestureDetector(
          onTap: _matchesCount > 0
              ? () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SearchResultPage(
                          filterParams: filtersApplied ? _buildFilterParams() : null),
                    ),
                  );
                }
              : null,
          child: Container(
            width: double.infinity,
            height: 54,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: _matchesCount > 0
                    ? [const Color(0xffFF1500), const Color(0xffFF5A60)]
                    : [Colors.grey.shade400, Colors.grey.shade400],
              ),
            ),
            child: const Center(
              child: Text('Search Matches',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
            ),
          ),
        ),
      ],
    );
  }

  // ── Filter sub-widgets ────────────────────────────────────────────────────

  Widget _buildFilterLabel(String title) {
    return Row(
      children: [
        Text(title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black87)),
        const SizedBox(width: 8),
        Container(height: 2, width: 30, color: const Color(0xffFF1500)),
      ],
    );
  }

  Widget _buildDropdown(String value, List<String> list, Function(String?) onChange) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [BoxShadow(color: Colors.grey.shade100, blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: ExcludeFocus(
        excluding: true,
        child: DropdownButton<String>(
          value: value,
          underline: const SizedBox(),
          isExpanded: true,
          items: list.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
          onChanged: onChange,
        ),
      ),
    );
  }

  Widget _buildRangeSlider(
      RangeValues range, double min, double max, Function(RangeValues) onChange) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _rangeBubble(range.start.round().toString()),
            _rangeBubble(range.end.round().toString()),
          ],
        ),
        RangeSlider(
          values: range,
          min: min,
          max: max,
          activeColor: const Color(0xffFF1500),
          inactiveColor: const Color(0xfffbc0c7),
          onChanged: onChange,
        ),
      ],
    );
  }

  Widget _rangeBubble(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      decoration: BoxDecoration(color: const Color(0xffFF1500), borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
    );
  }

  // ── Quick Filters Section ───────────────────────────────────────────────

  Widget _buildQuickFiltersSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xffFFF5F5), Color(0xffFFE8E8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xffFFD0D0), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.flash_on, color: Color(0xffFF1500), size: 20),
              ),
              const SizedBox(width: 10),
              const Text('Quick Filters',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xffFF1500))),
              const Spacer(),
              if (_hasPhotoOnly || _verifiedOnly || _membershipType != "All" || _newlyRegistered != "All")
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xffFF1500),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text('Active',
                      style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // Photo Filter
          _buildCheckboxFilter(
            icon: Icons.photo_camera,
            label: "With Photos Only",
            subtitle: "फोटो सहितका प्रोफाइल मात्र",
            value: _hasPhotoOnly,
            onChanged: (val) {
              setState(() => _hasPhotoOnly = val!);
              _handleFilterChange();
            },
          ),
          const SizedBox(height: 12),

          // Verified Filter
          _buildCheckboxFilter(
            icon: Icons.verified_user,
            label: "Verified Members",
            subtitle: "प्रमाणित सदस्यहरू मात्र",
            value: _verifiedOnly,
            onChanged: (val) {
              setState(() => _verifiedOnly = val!);
              _handleFilterChange();
            },
          ),
          const SizedBox(height: 12),

          // Membership Type
          const Text('Membership Type',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildChipFilter("All",  _membershipType == "All",  () { setState(() => _membershipType = "All");  _handleFilterChange(); }),
              const SizedBox(width: 8),
              _buildChipFilter("Paid", _membershipType == "Paid", () { setState(() => _membershipType = "Paid"); _handleFilterChange(); }),
              const SizedBox(width: 8),
              _buildChipFilter("Free", _membershipType == "Free", () { setState(() => _membershipType = "Free"); _handleFilterChange(); }),
            ],
          ),
          const SizedBox(height: 12),

          // Newly Registered
          const Text('Registration Date',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black12),
            ),
            child: DropdownButton<String>(
              value: _newlyRegistered,
              underline: const SizedBox(),
              isExpanded: true,
              icon: const Icon(Icons.arrow_drop_down, color: Color(0xffFF1500)),
              items: const [
                DropdownMenuItem(value: "All",         child: Text("All Members")),
                DropdownMenuItem(value: "Last 7 days", child: Text("Last 7 days")),
                DropdownMenuItem(value: "Last 15 days",child: Text("Last 15 days")),
                DropdownMenuItem(value: "Last 30 days",child: Text("Last 30 days")),
              ],
              onChanged: (val) {
                setState(() => _newlyRegistered = val!);
                _handleFilterChange();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckboxFilter({
    required IconData icon,
    required String label,
    required String subtitle,
    required bool value,
    required Function(bool?) onChanged,
  }) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: value ? const Color(0xffFF1500).withOpacity(0.05) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: value ? const Color(0xffFF1500) : Colors.black12,
            width: value ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: value ? const Color(0xffFF1500) : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon,
                  color: value ? Colors.white : Colors.grey.shade600, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: value ? FontWeight.w600 : FontWeight.w500,
                          color: value ? const Color(0xffFF1500) : Colors.black87)),
                  Text(subtitle,
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                ],
              ),
            ),
            Transform.scale(
              scale: 1.1,
              child: Checkbox(
                value: value,
                onChanged: onChanged,
                activeColor: const Color(0xffFF1500),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChipFilter(String label, bool isSelected, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xffFF1500) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? const Color(0xffFF1500) : Colors.black26,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Center(
            child: Text(label,
                style: TextStyle(
                    color: isSelected ? Colors.white : Colors.black87,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    fontSize: 13)),
          ),
        ),
      ),
    );
  }

  // ── Profile card (shared between tabs) ───────────────────────────────────

  Widget _buildProfileCard(Map<String, dynamic> profile) {
    final lastName  = profile['lastName'] ?? '';
    final userId    = profile['userid'] ?? 0;
    final name      = 'MS:$userId $lastName'.trim();
    final age       = profile['age']?.toString() ?? '–';
    final height    = profile['height_name']?.toString() ?? '–';
    final profession = profile['designation']?.toString() ?? '–';
    final city      = profile['city']?.toString() ?? '';
    final location  = city.isNotEmpty ? city : 'Nepal';
    final baseImageUrl    = '${kApiBaseUrl}/Api2/';
    final profilePicture  = profile['profile_picture']?.toString() ?? '';
    final imageUrl = profilePicture.isNotEmpty
        ? baseImageUrl + profilePicture
        : 'https://placehold.co/600x800/png';
    final matchPercent = profile['matchPercent'] ?? 0;
    Color matchColor = Colors.grey;
    if (matchPercent >= 80)      matchColor = Colors.green;
    else if (matchPercent >= 50) matchColor = Colors.orange;
    else if (matchPercent > 0)   matchColor = Colors.red;

    final shouldShowClearImage = _shouldShowClearImage(profile);
    final photoRequestStatus   = _getPhotoRequestStatus(profile);

    return GestureDetector(
      onTap: () {
        if (context.read<UserState>().isVerified) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ProfileLoader(
                  userId: userId.toString(), myId: _currentUserId.toString()),
            ),
          );
        } else {
          _handleDocumentNotApproved();
        }
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Colors.white,
          boxShadow: [
            BoxShadow(color: Colors.grey.shade200, blurRadius: 6, offset: const Offset(0, 3))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image
            Expanded(
              flex: 6,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _buildImageWithBlur(
                        imageUrl: imageUrl, shouldShowClearImage: shouldShowClearImage),
                    if (!shouldShowClearImage)
                      Positioned(
                        top: 6, left: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.65),
                              borderRadius: BorderRadius.circular(20)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.lock, size: 10, color: Colors.white),
                              const SizedBox(width: 3),
                              Text(_getBlurIndicatorText(photoRequestStatus),
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                    if (profile['isVerified'] == 1)
                      Positioned(
                        top: 6, right: 6,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle),
                          child: const Icon(Icons.verified, size: 12, color: Colors.white),
                        ),
                      ),
                    if (matchPercent > 0)
                      Positioned(
                        bottom: 6, right: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                              color: matchColor.withOpacity(0.9),
                              borderRadius: BorderRadius.circular(10)),
                          child: Text('$matchPercent%',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            // Info
            Expanded(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.all(9),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Text(name,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700, color: Colors.black87),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    _infoRow(Icons.person_outline, 'Age $age, $height'),
                    _infoRow(Icons.work_outline, profession),
                    _infoRow(Icons.location_on_outlined, location,
                        iconColor: const Color(0xfffb5f6a)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String text, {Color iconColor = Colors.grey}) {
    return Row(
      children: [
        Icon(icon, size: 11, color: iconColor),
        const SizedBox(width: 4),
        Expanded(
          child: Text(text,
              style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }

  Widget _buildImageWithBlur({required String imageUrl, required bool shouldShowClearImage}) {
    if (shouldShowClearImage) {
      return Image.network(
        imageUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            Container(color: Colors.grey[200],
                child: const Center(child: Icon(Icons.person, size: 40, color: Colors.grey))),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.network(
          imageUrl,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              Container(color: Colors.grey[200],
                  child: const Center(child: Icon(Icons.person, size: 40, color: Colors.grey))),
        ),
        BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(color: Colors.black.withOpacity(0.15)),
        ),
        Center(
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                shape: BoxShape.circle, color: Colors.red.withOpacity(0.8)),
            child: const Icon(Icons.lock, color: Colors.white, size: 20),
          ),
        ),
      ],
    );
  }

  String _getBlurIndicatorText(String status) {
    switch (status) {
      case 'pending':  return 'Pending';
      case 'rejected': return 'Rejected';
      case 'accepted': return 'Access';
      default:         return 'Private';
    }
  }
}
