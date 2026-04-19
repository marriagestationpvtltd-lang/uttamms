import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:ms2026/constant/app_colors.dart';
import 'package:ms2026/constant/status_bar_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../Models/masterdata.dart';
import '../../main.dart';
import '../../ReUsable/loading_widgets.dart';
import '../../utils/privacy_utils.dart';
import 'package:ms2026/config/app_endpoints.dart';

class PaidUsersListPage extends StatefulWidget {
  final int userId;
  const PaidUsersListPage({Key? key, required this.userId}) : super(key: key);

  @override
  State<PaidUsersListPage> createState() => _PaidUsersListPageState();
}

class _PaidUsersListPageState extends State<PaidUsersListPage> {
  List<dynamic> _users = [];
  bool _isLoading = true;
  bool _isRefreshing = false;
  String _errorMessage = '';
  bool _hasMore = true;
  int _currentPage = 1;
  final int _perPage = 20;
  final ScrollController _scrollController = ScrollController();
  String _searchQuery = '';
  String _selectedCity = '';
  List<String> _availableCities = [];
  String usertye = '';

  // Filter variables
  String _selectedGender = '';
  String _selectedAgeRange = '';
  List<String> _selectedInterests = [];
  List<String> _availableInterests = [];

  // Layout variables
  late double _screenWidth;
  bool get _isMobile => _screenWidth < 768;
  bool get _isTablet => _screenWidth >= 768 && _screenWidth < 1024;
  bool get _isDesktop => _screenWidth >= 1024;

  // Responsive grid configuration
  int get _gridCrossAxisCount {
    if (_isMobile) return 2;
    if (_isTablet) return 3;
    return 4;
  }

  double get _cardAspectRatio {
    if (_isMobile) return 0.62;
    if (_isTablet) return 0.68;
    return 0.72;
  }

  // Animation controllers
  late AnimationController _filterAnimationController;
  late Animation<double> _filterAnimation;
  bool _showFilters = false;

  @override
  void initState() {
    super.initState();
    _fetchUsers();
    _scrollController.addListener(_scrollListener);
    loadMasterData();
    _initializeAnimations();
  }

  void _initializeAnimations() {
    // Will be initialized in build context
  }

  Future<UserMasterData> fetchUserMasterData(String userId) async {
    final url = Uri.parse(
      "${kApiBaseUrl}/Api2/masterdata.php?userid=$userId",
    );
    final response = await http.get(url);
    if (response.statusCode != 200) {
      throw Exception("Failed: ${response.statusCode}");
    }
    final res = json.decode(response.body);
    if (res['success'] != true) {
      throw Exception(res['message'] ?? "API error");
    }
    return UserMasterData.fromJson(res['data']);
  }

  void loadMasterData() async {
    final prefs = await SharedPreferences.getInstance();
    final userDataString = prefs.getString('user_data');
    final userData = jsonDecode(userDataString!);
    final userId = int.tryParse(userData["id"].toString());
    try {
      UserMasterData user = await fetchUserMasterData(userId.toString());
      setState(() {
        usertye = user.usertype;
      });
    } catch (e) {
      print("Error: $e");
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchUsers({bool reset = false}) async {
    if (reset) {
      setState(() {
        _currentPage = 1;
        _users = [];
        _hasMore = true;
      });
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final response = await http.get(
        Uri.parse('${kApiBaseUrl}/Api2/premiuimmember.php?user_id=${widget.userId}&page=$_currentPage'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final newUsers = data['data'] ?? [];

          // Extract cities and interests from new users
          final cities = <String>{};
          final interests = <String>{};

          for (var user in newUsers) {
            if (user['city'] != null && user['city'].toString().isNotEmpty) {
              cities.add(user['city'].toString());
            }
            if (user['interests'] != null && user['interests'].toString().isNotEmpty) {
              final userInterests = user['interests'].toString().split(',');
              interests.addAll(userInterests);
            }
          }

          setState(() {
            if (reset) {
              _users = newUsers;
            } else {
              _users.addAll(newUsers);
            }
            _hasMore = newUsers.length == _perPage;
            _isLoading = false;
            _availableCities = cities.toList()..sort();
            _availableInterests = interests.toList()..sort();
          });
        } else {
          setState(() {
            _errorMessage = data['message'] ?? 'Failed to fetch users';
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _errorMessage = 'HTTP Error: ${response.statusCode}';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  void _scrollListener() {
    if (_scrollController.position.pixels == _scrollController.position.maxScrollExtent) {
      if (_hasMore && !_isLoading) {
        setState(() {
          _currentPage++;
        });
        _fetchUsers();
      }
    }
  }

  List<dynamic> _getFilteredUsers() {
    List<dynamic> filtered = _users;

    // Search filter
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((user) {
        final name = 'MS:${user['id']} ${user['lastName']}'.toLowerCase();
        final city = (user['city'] ?? '').toLowerCase();
        final email = (user['email'] ?? '').toLowerCase();
        return name.contains(_searchQuery.toLowerCase()) ||
            city.contains(_searchQuery.toLowerCase()) ||
            email.contains(_searchQuery.toLowerCase());
      }).toList();
    }

    // City filter
    if (_selectedCity.isNotEmpty) {
      filtered = filtered.where((user) {
        return (user['city'] ?? '').toString() == _selectedCity;
      }).toList();
    }

    // Gender filter
    if (_selectedGender.isNotEmpty) {
      filtered = filtered.where((user) {
        return (user['gender'] ?? '').toString().toLowerCase() == _selectedGender.toLowerCase();
      }).toList();
    }

    // Interests filter
    if (_selectedInterests.isNotEmpty) {
      filtered = filtered.where((user) {
        final userInterests = (user['interests'] ?? '').toString().split(',');
        return _selectedInterests.any((interest) => userInterests.contains(interest));
      }).toList();
    }

    // Age range filter
    if (_selectedAgeRange.isNotEmpty) {
      filtered = filtered.where((user) {
        final age = int.tryParse(user['age']?.toString() ?? '0') ?? 0;
        switch (_selectedAgeRange) {
          case '18-25':
            return age >= 18 && age <= 25;
          case '26-35':
            return age >= 26 && age <= 35;
          case '36-45':
            return age >= 36 && age <= 45;
          case '46+':
            return age >= 46;
          default:
            return true;
        }
      }).toList();
    }

    return filtered;
  }

  Widget _buildUserCard(Map<String, dynamic> user) {
    final name = 'MS:${user['id'] ?? ''} ${user['lastName'] ?? ''}'.trim();
    final age = user['age']?.toString() ?? '';
    final city = user['city'] ?? '';
    final isVerified = user['isVerified'] == 1;
    final profilePic = user['profile_picture'];
    final imageUrl = profilePic != null && profilePic.toString().isNotEmpty
        ? '${kApiBaseUrl}/Api2/$profilePic'
        : '';

    // Use profile owner's privacy setting, not viewer's subscription
    final privacy = user['privacy']?.toString().toLowerCase() ?? '';
    final photoRequest = user['photo_request']?.toString().toLowerCase() ?? '';
    final canViewPhoto = user['can_view_photo'] as bool?;
    final shouldBlurPhoto = !PrivacyUtils.shouldShowClearImage(
      privacy: privacy,
      photoRequest: photoRequest,
      canViewPhoto: canViewPhoto,
    );
    final interests = (user['interests']?.toString() ?? '')
        .split(',')
        .where((s) => s.trim().isNotEmpty)
        .take(2)
        .toList();

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ProfileLoader(
              userId: user['id'].toString(),
              myId: widget.userId.toString(),
            ),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.13),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // ── Full-bleed background image ──────────────────────────
              _buildCardImage(imageUrl, shouldBlurPhoto),

              // ── Deep gradient scrim at bottom for readability ────────
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0.42, 0.72, 1.0],
                      colors: [
                        Colors.transparent,
                        Colors.black.withOpacity(0.45),
                        Colors.black.withOpacity(0.88),
                      ],
                    ),
                  ),
                ),
              ),

              // ── Top badges row ───────────────────────────────────────
              Positioned(
                top: 10,
                left: 10,
                right: 10,
                child: Row(
                  children: [
                    // Premium badge – gold gradient pill
                    _PremiumBadge(),
                    const Spacer(),
                    if (isVerified && !shouldBlurPhoto)
                      _VerifiedBadge(),
                  ],
                ),
              ),

              // ── Lock overlay when photo is private ───────────────────
              if (shouldBlurPhoto)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.48),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.15),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withOpacity(0.4),
                              width: 1.5,
                            ),
                          ),
                          child: const Icon(
                            Icons.lock_outline_rounded,
                            color: Colors.white,
                            size: 26,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Photo Private',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.85),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // ── Bottom info + CTA ────────────────────────────────────
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(13, 0, 13, 13),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Name
                      Text(
                        name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                          shadows: [
                            Shadow(
                              color: Colors.black54,
                              blurRadius: 6,
                            ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),

                      const SizedBox(height: 4),

                      // Age + City row
                      Row(
                        children: [
                          if (age.isNotEmpty) ...[
                            const Icon(
                              Icons.cake_outlined,
                              size: 12,
                              color: Colors.white70,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              '$age yrs',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.white70,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                          if (age.isNotEmpty && city.isNotEmpty)
                            Container(
                              margin: const EdgeInsets.symmetric(horizontal: 6),
                              width: 3,
                              height: 3,
                              decoration: const BoxDecoration(
                                color: Colors.white54,
                                shape: BoxShape.circle,
                              ),
                            ),
                          if (city.isNotEmpty)
                            Expanded(
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.location_on_outlined,
                                    size: 12,
                                    color: Colors.white70,
                                  ),
                                  const SizedBox(width: 3),
                                  Expanded(
                                    child: Text(
                                      city,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.white70,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),

                      // Interests chips
                      if (interests.isNotEmpty && !shouldBlurPhoto) ...[
                        const SizedBox(height: 7),
                        Wrap(
                          spacing: 5,
                          runSpacing: 4,
                          children: interests.map((interest) {
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.18),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: Colors.white.withOpacity(0.3)),
                              ),
                              child: Text(
                                interest.trim(),
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],

                      const SizedBox(height: 10),

                      // View Profile CTA
                      Container(
                        height: 38,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFF6B35), Color(0xFFEA1935)],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFEA4935).withOpacity(0.45),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ProfileLoader(
                                    userId: user['id'].toString(),
                                    myId: widget.userId.toString(),
                                  ),
                                ),
                              );
                            },
                            child: const Center(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.visibility_outlined,
                                      size: 15, color: Colors.white),
                                  SizedBox(width: 6),
                                  Text(
                                    'View Profile',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCardImage(String imageUrl, bool shouldBlur) {
    Widget img;
    if (imageUrl.isNotEmpty) {
      img = Image.network(
        imageUrl,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Container(
            color: const Color(0xFFF0E8E8),
            child: const Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor:
                    AlwaysStoppedAnimation<Color>(Color(0xFFEA4935)),
              ),
            ),
          );
        },
        errorBuilder: (_, __, ___) => _cardPlaceholder(),
      );
    } else {
      img = _cardPlaceholder();
    }

    if (shouldBlur) {
      return ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: img,
      );
    }
    return img;
  }

  Widget _cardPlaceholder() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFE5E5), Color(0xFFFFCDD2)],
        ),
      ),
      child: const Center(
        child: Icon(Icons.person_outline_rounded, size: 64, color: Color(0xFFEA4935)),
      ),
    );
  }

  Widget _buildFilterChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        // Gender Filter


        // Age Range Filter
        ExcludeFocus(
          excluding: true,
          child: DropdownButtonHideUnderline(
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: _selectedAgeRange.isEmpty ? Colors.grey[100] : Color(0xFFEA4935).withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _selectedAgeRange.isEmpty ? Colors.grey[300]! : Color(0xFFEA4935),
                ),
              ),
              child: DropdownButton<String>(
                value: _selectedAgeRange.isEmpty ? null : _selectedAgeRange,
                hint: Row(
                  children: [
                    Icon(Icons.timeline, size: 16, color: Colors.grey[600]),
                    SizedBox(width: 6),
                    Text('Age Range', style: TextStyle(color: Colors.grey[600])),
                  ],
                ),
                items: [
                  DropdownMenuItem(value: '', child: Text('All Ages')),
                  DropdownMenuItem(value: '18-25', child: Text('18-25')),
                  DropdownMenuItem(value: '26-35', child: Text('26-35')),
                  DropdownMenuItem(value: '36-45', child: Text('36-45')),
                  DropdownMenuItem(value: '46+', child: Text('46+')),
                ],
                onChanged: (value) {
                  setState(() {
                    _selectedAgeRange = value ?? '';
                  });
                },
                icon: Icon(Icons.arrow_drop_down, color: Colors.grey[600]),
                isDense: true,
              ),
            ),
          ),
        ),

        // City Filter
        if (_availableCities.isNotEmpty)
          ExcludeFocus(
            excluding: true,
            child: DropdownButtonHideUnderline(
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: _selectedCity.isEmpty ? Colors.grey[100] : Color(0xFFEA4935).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _selectedCity.isEmpty ? Colors.grey[300]! : Color(0xFFEA4935),
                  ),
                ),
                child: DropdownButton<String>(
                  value: _selectedCity.isEmpty ? null : _selectedCity,
                  hint: Row(
                    children: [
                      Icon(Icons.location_city, size: 16, color: Colors.grey[600]),
                      SizedBox(width: 6),
                      Text('City', style: TextStyle(color: Colors.grey[600])),
                    ],
                  ),
                  items: [
                    DropdownMenuItem(value: '', child: Text('All Cities')),
                    ..._availableCities.map((city) {
                      return DropdownMenuItem(value: city, child: Text(city));
                    }).toList(),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedCity = value ?? '';
                    });
                  },
                  icon: Icon(Icons.arrow_drop_down, color: Colors.grey[600]),
                  isDense: true,
                ),
              ),
            ),
          ),

        // Clear Filters Button
        if (_selectedGender.isNotEmpty || _selectedAgeRange.isNotEmpty || _selectedCity.isNotEmpty || _selectedInterests.isNotEmpty)
          GestureDetector(
            onTap: () {
              setState(() {
                _selectedGender = '';
                _selectedAgeRange = '';
                _selectedCity = '';
                _selectedInterests = [];
              });
            },
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.clear_all, size: 16, color: Colors.grey[700]),
                  SizedBox(width: 6),
                  Text('Clear All', style: TextStyle(color: Colors.grey[700])),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMobileLayout(List<dynamic> filteredUsers, bool hasUsers) {
    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        // ── Premium Header ───────────────────────────────────────────
        SliverAppBar(
          floating: true,
          pinned: true,
          snap: true,
          expandedHeight: 160,
          systemOverlayStyle: setStatusBar(Colors.transparent, Brightness.light),
          flexibleSpace: FlexibleSpaceBar(
            collapseMode: CollapseMode.parallax,
            background: Stack(
              fit: StackFit.expand,
              children: [
                // Background gradient
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF1A0A0A), Color(0xFF7B1010), Color(0xFFEA4935)],
                      stops: [0.0, 0.45, 1.0],
                    ),
                  ),
                ),
                // Subtle diamond pattern overlay (drawn locally)
                Opacity(
                  opacity: 0.05,
                  child: CustomPaint(
                    painter: _DiamondPatternPainter(),
                    child: const SizedBox.expand(),
                  ),
                ),
                // Content
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 20,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: Colors.white.withOpacity(0.3)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.workspace_premium,
                                    size: 13, color: Color(0xFFFFD700)),
                                SizedBox(width: 5),
                                Text(
                                  'PREMIUM',
                                  style: TextStyle(
                                    color: Color(0xFFFFD700),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Premium Members',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Connect with verified elite profiles',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.75),
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── Search Bar ───────────────────────────────────────────────
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          sliver: SliverToBoxAdapter(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.07),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search by name, city…',
                  hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
                  prefixIcon:
                      const Icon(Icons.search_rounded, color: Color(0xFFEA4935)),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.close_rounded,
                              color: Colors.grey[400], size: 18),
                          onPressed: () => setState(() => _searchQuery = ''),
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 14),
                ),
                onChanged: (value) => setState(() => _searchQuery = value),
              ),
            ),
          ),
        ),

        // ── Filter Chips ─────────────────────────────────────────────
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          sliver: SliverToBoxAdapter(child: _buildFilterChips()),
        ),

        // ── Results Count ────────────────────────────────────────────
        if (hasUsers)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEA4935).withOpacity(0.08),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${filteredUsers.length} members',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFEA4935),
                      ),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.tune_rounded,
                        color: Color(0xFFEA4935), size: 20),
                    onPressed: _showFilterBottomSheet,
                  ),
                ],
              ),
            ),
          ),

        // Loading State
        if (_isLoading && _users.isEmpty)
          SliverFillRemaining(
            child: Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFEA4935)),
              ),
            ),
          ),

        // Error State
        if (_errorMessage.isNotEmpty && _users.isEmpty)
          SliverFillRemaining(
            child: _buildErrorState(),
          ),

        // Empty State
        if (!hasUsers && !_isLoading && _errorMessage.isEmpty)
          SliverFillRemaining(
            child: _buildEmptyState(),
          ),

        // Users Grid
        if (hasUsers)
          SliverPadding(
            padding: EdgeInsets.all(16),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: _gridCrossAxisCount,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: _cardAspectRatio,
              ),
              delegate: SliverChildBuilderDelegate(
                    (context, index) {
                  if (index >= filteredUsers.length) {
                    return _hasMore
                        ? Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFEA4935)),
                      ),
                    )
                        : SizedBox.shrink();
                  }
                  return _buildUserCard(filteredUsers[index]);
                },
                childCount: filteredUsers.length + (_hasMore ? 1 : 0),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildDesktopLayout(List<dynamic> filteredUsers, bool hasUsers) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Sidebar Filters
        Container(
          width: 300,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(
              right: BorderSide(color: Colors.grey[200]!),
            ),
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Search
                Text(
                  'Search',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[900],
                  ),
                ),
                SizedBox(height: 12),
                TextField(
                  decoration: InputDecoration(
                    hintText: 'Search premium users...',
                    prefixIcon: Icon(Icons.search, color: Color(0xFFEA4935)),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Color(0xFFEA4935)),
                    ),
                  ),
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                    });
                  },
                ),

                SizedBox(height: 24),

                // Filters Title
                Text(
                  'Filters',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[900],
                  ),
                ),
                SizedBox(height: 16),

                // Gender Filter


                SizedBox(height: 24),

                // Age Range
                Text(
                  'Age Range',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700],
                  ),
                ),
                SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    ...['18-25', '26-35', '36-45', '46+'].map((range) {
                      return FilterChip(
                        label: Text(range),
                        selected: _selectedAgeRange == range,
                        onSelected: (selected) {
                          setState(() {
                            _selectedAgeRange = selected ? range : '';
                          });
                        },
                        selectedColor: Color(0xFFEA4935),
                        checkmarkColor: Colors.white,
                      );
                    }).toList(),
                  ],
                ),

                SizedBox(height: 24),

                // City Filter
                if (_availableCities.isNotEmpty) ...[
                  Text(
                    'City',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[700],
                    ),
                  ),
                  SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      FilterChip(
                        label: Text('All Cities'),
                        selected: _selectedCity.isEmpty,
                        onSelected: (selected) {
                          setState(() {
                            _selectedCity = '';
                          });
                        },
                        selectedColor: Color(0xFFEA4935),
                        checkmarkColor: Colors.white,
                      ),
                      ..._availableCities.take(10).map((city) {
                        return FilterChip(
                          label: Text(city),
                          selected: _selectedCity == city,
                          onSelected: (selected) {
                            setState(() {
                              _selectedCity = selected ? city : '';
                            });
                          },
                          selectedColor: Color(0xFFEA4935),
                          checkmarkColor: Colors.white,
                        );
                      }).toList(),
                    ],
                  ),
                ],

                Spacer(),

                // Stats Card
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Statistics',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[700],
                        ),
                      ),
                      SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              children: [
                                Text(
                                  '${filteredUsers.length}',
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFFEA4935),
                                  ),
                                ),
                                Text(
                                  'Filtered',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            width: 1,
                            height: 40,
                            color: Colors.grey[300],
                          ),
                          Expanded(
                            child: Column(
                              children: [
                                Text(
                                  '${_users.length}',
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey[800],
                                  ),
                                ),
                                Text(
                                  'Total',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      if (_selectedGender.isNotEmpty || _selectedAgeRange.isNotEmpty || _selectedCity.isNotEmpty)
                        ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _selectedGender = '';
                              _selectedAgeRange = '';
                              _selectedCity = '';
                              _selectedInterests = [];
                            });
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            foregroundColor: Color(0xFFEA4935),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(color: Color(0xFFEA4935)),
                            ),
                            minimumSize: Size(double.infinity, 40),
                          ),
                          child: Text('Clear All Filters'),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // Main Content
        Expanded(
          child: Column(
            children: [
              // Header with Actions
              Container(
                padding: EdgeInsets.symmetric(horizontal: 32, vertical: 20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    bottom: BorderSide(color: Colors.grey[200]!),
                  ),
                ),
                child: Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Premium Members',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[900],
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Discover and connect with verified premium users',
                          style: TextStyle(
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                    Spacer(),
                    ElevatedButton.icon(
                      onPressed: () => _fetchUsers(reset: true),
                      icon: Icon(Icons.refresh, size: 18),
                      label: Text('Refresh'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color(0xFFEA4935),
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Grid Content
              Expanded(
                child: _isLoading && _users.isEmpty
                    ? Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFEA4935)),
                  ),
                )
                    : _errorMessage.isNotEmpty
                    ? _buildErrorState()
                    : !hasUsers
                    ? _buildEmptyState()
                    : Padding(
                  padding: EdgeInsets.all(24),
                  child: GridView.builder(
                    controller: _scrollController,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: _gridCrossAxisCount,
                      crossAxisSpacing: 24,
                      mainAxisSpacing: 24,
                      childAspectRatio: _cardAspectRatio,
                    ),
                    itemCount: filteredUsers.length + (_hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index >= filteredUsers.length) {
                        return _hasMore
                            ? Center(
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFEA4935)),
                          ),
                        )
                            : SizedBox.shrink();
                      }
                      return _buildUserCard(filteredUsers[index]);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showFilterBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.8,
          padding: EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Filters',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[900],
                    ),
                  ),
                  Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close),
                  ),
                ],
              ),
              SizedBox(height: 24),

              // Gender Filter


              SizedBox(height: 24),

              // Age Range
              Text(
                'Age Range',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700],
                ),
              ),
              SizedBox(height: 12),
              Wrap(
                spacing: 12,
                children: [
                  ...['18-25', '26-35', '36-45', '46+'].map((range) {
                    return ChoiceChip(
                      label: Text(range),
                      selected: _selectedAgeRange == range,
                      onSelected: (selected) {
                        setState(() {
                          _selectedAgeRange = selected ? range : '';
                        });
                      },
                      selectedColor: Color(0xFFEA4935),
                      labelStyle: TextStyle(
                        color: _selectedAgeRange == range ? Colors.white : Colors.grey[700],
                      ),
                    );
                  }).toList(),
                ],
              ),

              SizedBox(height: 24),

              // City Filter
              if (_availableCities.isNotEmpty) ...[
                Text(
                  'City',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700],
                  ),
                ),
                SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  children: [
                    ChoiceChip(
                      label: Text('All Cities'),
                      selected: _selectedCity.isEmpty,
                      onSelected: (selected) {
                        setState(() {
                          _selectedCity = '';
                        });
                      },
                      selectedColor: Color(0xFFEA4935),
                      labelStyle: TextStyle(
                        color: _selectedCity.isEmpty ? Colors.white : Colors.grey[700],
                      ),
                    ),
                    ..._availableCities.take(8).map((city) {
                      return ChoiceChip(
                        label: Text(city),
                        selected: _selectedCity == city,
                        onSelected: (selected) {
                          setState(() {
                            _selectedCity = selected ? city : '';
                          });
                        },
                        selectedColor: Color(0xFFEA4935),
                        labelStyle: TextStyle(
                          color: _selectedCity == city ? Colors.white : Colors.grey[700],
                        ),
                      );
                    }).toList(),
                  ],
                ),
              ],

              Spacer(),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        setState(() {
                          _selectedGender = '';
                          _selectedAgeRange = '';
                          _selectedCity = '';
                          _selectedInterests = [];
                        });
                        Navigator.pop(context);
                      },
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        side: BorderSide(color: Colors.grey[300]!),
                      ),
                      child: Text(
                        'Clear All',
                        style: TextStyle(
                          color: Colors.grey[700],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color(0xFFEA4935),
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Apply Filters',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Container(
        constraints: BoxConstraints(maxWidth: 400),
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.error_outline, color: Colors.red, size: 48),
            ),
            SizedBox(height: 24),
            Text(
              'Oops! Something went wrong',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.grey[900],
              ),
            ),
            SizedBox(height: 12),
            Text(
              _errorMessage,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
            SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () => _fetchUsers(reset: true),
              icon: Icon(Icons.refresh),
              label: Text('Try Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xFFEA4935),
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Container(
        constraints: BoxConstraints(maxWidth: 400),
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.group_off, color: Colors.grey[400], size: 48),
            ),
            SizedBox(height: 24),
            Text(
              'No Users Found',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.grey[900],
              ),
            ),
            SizedBox(height: 12),
            Text(
              _searchQuery.isNotEmpty || _selectedCity.isNotEmpty || _selectedGender.isNotEmpty
                  ? 'Try adjusting your search criteria'
                  : 'No premium users available at the moment',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
            SizedBox(height: 32),
            if (_searchQuery.isNotEmpty || _selectedCity.isNotEmpty || _selectedGender.isNotEmpty)
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _searchQuery = '';
                    _selectedCity = '';
                    _selectedGender = '';
                    _selectedAgeRange = '';
                    _selectedInterests = [];
                  });
                },
                icon: Icon(Icons.clear_all),
                label: Text('Clear All Filters'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey[200],
                  foregroundColor: Colors.grey[800],
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _screenWidth = MediaQuery.of(context).size.width;
    final filteredUsers = _getFilteredUsers();
    final hasUsers = filteredUsers.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F8),
      body: RefreshIndicator(
        color: const Color(0xFFEA4935),
        onRefresh: () async {
          setState(() => _isRefreshing = true);
          await _fetchUsers(reset: true);
          if (mounted) setState(() => _isRefreshing = false);
        },
        child: ShimmerLoading(
          isLoading: _isRefreshing,
          child: _isDesktop
              ? _buildDesktopLayout(filteredUsers, hasUsers)
              : _buildMobileLayout(filteredUsers, hasUsers),
        ),
      ),
      floatingActionButton: _isDesktop
          ? null
          : FloatingActionButton.extended(
              onPressed: _showFilterBottomSheet,
              icon: const Icon(Icons.tune_rounded),
              label: const Text('Filters'),
              backgroundColor: const Color(0xFFEA4935),
              foregroundColor: Colors.white,
              elevation: 4,
            ),
    );
  }
}

// ─────────────────────────────────────────────
// Standalone badge widgets
// ─────────────────────────────────────────────

class _PremiumBadge extends StatelessWidget {
  const _PremiumBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFD700), Color(0xFFFF8C00)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.amber.withOpacity(0.5),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.workspace_premium, size: 12, color: Colors.white),
          SizedBox(width: 4),
          Text(
            'PREMIUM',
            style: TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _VerifiedBadge extends StatelessWidget {
  const _VerifiedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF10B981),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.green.withOpacity(0.4),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified_rounded, size: 12, color: Colors.white),
          SizedBox(width: 4),
          Text(
            'Verified',
            style: TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Diamond grid pattern (local, no network dependency)
// ─────────────────────────────────────────────

class _DiamondPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    const double step = 18;
    for (double x = 0; x < size.width + step; x += step) {
      for (double y = 0; y < size.height + step; y += step) {
        final path = Path()
          ..moveTo(x, y - step / 2)
          ..lineTo(x + step / 2, y)
          ..lineTo(x, y + step / 2)
          ..lineTo(x - step / 2, y)
          ..close();
        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DiamondPatternPainter oldDelegate) => false;
}