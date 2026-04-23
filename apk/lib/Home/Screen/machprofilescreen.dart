import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../Auth/Screen/signupscreen10.dart';
import '../../service/verification_service.dart';
import '../../core/user_state.dart';
import '../../main.dart';
import '../../pushnotification/pushservice.dart';
import '../../ReUsable/loading_widgets.dart';
import '../../utils/privacy_utils.dart';
import 'package:ms2026/config/app_endpoints.dart';
import 'package:ms2026/features/activity/services/activity_service.dart';

class MatchedProfilesPagee extends StatefulWidget {
  final int currentUserId;

  const MatchedProfilesPagee({
    Key? key,
    required this.currentUserId,
  }) : super(key: key);

  @override
  State<MatchedProfilesPagee> createState() => _MatchedProfilesPageeState();
}

class _MatchedProfilesPageeState extends State<MatchedProfilesPagee> {
  List<dynamic> _matchedProfiles = [];
  bool _isLoading = false;
  bool _isRefreshing = false;
  String _errorMessage = '';
  bool _isBlurred = true;
  final String _apiUrl = '${kApiBaseUrl}/Api2/match.php';
  String _userName = '';
  String _userLastName = '';
  int _userId = 0;
  bool _showPopup = false;
  String _popupMessage = '';

  @override
  void initState() {
    super.initState();
    _fetchMatchedProfiles();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataString = prefs.getString('user_data');
      if (userDataString != null) {
        final userData = jsonDecode(userDataString);
        setState(() {
          _userId = int.tryParse(userData["id"].toString()) ?? 0;
          _userName = userData["firstName"] ?? '';
          _userLastName = userData["lastName"] ?? '';
        });
      }
    } catch (e) {
      print('Error loading user data: $e');
    }
  }

  Future<void> _fetchMatchedProfiles({bool isRefresh = false}) async {
    if (!isRefresh) {
      setState(() {
        _isLoading = true;
        _errorMessage = '';
      });
    } else {
      setState(() => _errorMessage = '');
    }

    try {
      final response = await http.post(
        Uri.parse(_apiUrl),
        body: {'userid': widget.currentUserId.toString()},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          setState(() {
            _matchedProfiles = data['matched_users'] ?? [];
          });
        } else {
          setState(() {
            _errorMessage = data['message'] ?? 'Failed to fetch profiles';
          });
        }
      } else {
        setState(() {
          _errorMessage = 'HTTP Error: ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error: ${e.toString()}';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }



  void _showRequestSentPopup(String message) {
    setState(() {
      _popupMessage = message;
      _showPopup = true;
    });

    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _showPopup = false;
        });
      }
    });
  }


  Future<void> _handleLikeProfile(int profileId, bool isCurrentlyLiked) async {
    try {
      final response = await http.post(
        Uri.parse('${kApiBaseUrl}/Api2/like_profile.php'),
        body: {
          'sender_id': widget.currentUserId.toString(),
          'receiver_id': profileId.toString(),
          'action': isCurrentlyLiked ? 'delete' : 'add',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          setState(() {
            final index = _matchedProfiles.indexWhere((p) => p['userid'] == profileId);
            if (index != -1) {
              _matchedProfiles[index]['like'] = !isCurrentlyLiked;
            }
          });
          // Log like/unlike activity (fire-and-forget)
          ActivityService.instance.log(
            userId: widget.currentUserId.toString(),
            activityType: isCurrentlyLiked ? ActivityType.likeRemoved : ActivityType.likeSent,
            targetUserId: profileId.toString(),
          );
          _showRequestSentPopup(isCurrentlyLiked ? 'Removed from likes' : 'Added to likes');
        } else {
          _showRequestSentPopup('Failed: ${data['message']}');
        }
      }
    } catch (e) {
      _showRequestSentPopup('Error: $e');
    }
  }




  Widget _buildProfileCard(int index) {
    final profile = _matchedProfiles[index];

    final userId = profile['userid']?.toString() ?? 'null';
    final lastName = profile['lastName'] ?? '';
    final name = userId != 'null'
        ? 'MS:$userId $lastName'.trim()
        : lastName.isNotEmpty
            ? lastName
            : 'User';

    final age = profile['age']?.toString() ?? '';
    final height = profile['height_name'] ?? '';
    final profession = profile['designation'] ?? '';
    final city = profile['city'] ?? '';
    final country = profile['country'] ?? '';
    final location =
        '$city${city.isNotEmpty && country.isNotEmpty ? ', ' : ''}$country';
    final matchPercent = profile['matchPercent'] ?? 0;
    final isVerified = profile['isVerified'] == 1;
    final isLiked = profile['like'] == true;
    final privacy =
        profile['privacy']?.toString().toLowerCase() ?? 'free';
    final photoRequestStatus =
        profile['photo_request']?.toString().toLowerCase() ?? 'not_sent';

    final baseImageUrl = '${kApiBaseUrl}/Api2/';
    final profilePicture = profile['profile_picture'] ?? '';
    final imageUrl = profilePicture.isNotEmpty ? baseImageUrl + profilePicture : '';

    final shouldShowClearImage = PrivacyUtils.shouldShowClearImage(
      privacy: privacy,
      photoRequest: photoRequestStatus,
      canViewPhoto: profile['can_view_photo'] as bool?,
    );
    final isActuallyBlurred = _isBlurred && !shouldShowClearImage;

    return GestureDetector(
      onTap: () => _navigateToProfile(profile['userid']),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // ── Profile image ────────────────────────────────────────
              _buildCardImage(imageUrl, isActuallyBlurred),

              // ── Gradient scrim ───────────────────────────────────────
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0.35, 0.62, 1.0],
                      colors: [
                        Colors.transparent,
                        Colors.black.withOpacity(0.38),
                        Colors.black.withOpacity(0.84),
                      ],
                    ),
                  ),
                ),
              ),

              // ── Lock overlay ─────────────────────────────────────────
              if (isActuallyBlurred)
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withOpacity(0.46),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.14),
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: Colors.white.withOpacity(0.35)),
                          ),
                          child: const Icon(Icons.lock_outline_rounded,
                              size: 22, color: Colors.white),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          photoRequestStatus == 'pending'
                              ? 'Request Pending'
                              : photoRequestStatus == 'rejected'
                                  ? 'Request Rejected'
                                  : 'Photo Private',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.2,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),

              // ── Match % badge (top-right) ────────────────────────────
              if (matchPercent > 0)
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: _getMatchColor(matchPercent),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.25),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                    child: Text(
                      '$matchPercent%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),

              // ── Like button (top-left) ───────────────────────────────
              Positioned(
                top: 10,
                left: 10,
                child: GestureDetector(
                  onTap: () =>
                      _handleLikeProfile(profile['userid'], isLiked),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.90),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.18),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(
                      isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      size: 18,
                      color: isLiked ? const Color(0xFFEA4935) : Colors.grey[600],
                    ),
                  ),
                ),
              ),

              // ── Bottom info ──────────────────────────────────────────
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(11, 0, 11, 11),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Name + verified icon
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.1,
                                shadows: [
                                  Shadow(
                                      color: Colors.black54,
                                      blurRadius: 4),
                                ],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isVerified)
                            const Padding(
                              padding: EdgeInsets.only(left: 4),
                              child: Icon(Icons.verified_rounded,
                                  size: 14, color: Color(0xFF4FC3F7)),
                            ),
                        ],
                      ),

                      const SizedBox(height: 2),

                      // Age / Height
                      if (age.isNotEmpty || height.isNotEmpty)
                        Text(
                          [
                            if (age.isNotEmpty) '$age yrs',
                            if (height.isNotEmpty) height,
                          ].join(' · '),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),

                      // Location
                      if (location.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(Icons.location_on_outlined,
                                size: 10, color: Colors.white54),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                location,
                                style: const TextStyle(
                                    color: Colors.white54, fontSize: 10),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],

                      const SizedBox(height: 8),

                      // View Profile CTA
                      Container(
                        height: 33,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [
                              Color(0xFFFF6B35),
                              Color(0xFFEA1935)
                            ],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFEA4935)
                                  .withOpacity(0.45),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () =>
                                _navigateToProfile(profile['userid']),
                            child: const Center(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.visibility_outlined,
                                      size: 13, color: Colors.white),
                                  SizedBox(width: 5),
                                  Text(
                                    'View Profile',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                      letterSpacing: 0.2,
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

  Widget _buildCardImage(String imageUrl, bool isBlurred) {
    Widget img;
    if (imageUrl.isNotEmpty) {
      final net = Image.network(
        imageUrl,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFFFE5E5), Color(0xFFFFCDD2)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
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
      img = isBlurred
          ? ImageFiltered(
              imageFilter: ui.ImageFilter.blur(
                sigmaX: PrivacyUtils.kStandardBlurSigmaX,
                sigmaY: PrivacyUtils.kStandardBlurSigmaY,
              ),
              child: net,
            )
          : net;
    } else {
      img = _cardPlaceholder();
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
        child: Icon(Icons.person_outline_rounded,
            size: 64, color: Color(0xFFEA4935)),
      ),
    );
  }

  Color _getMatchColor(int percent) {
    if (percent >= 80) return Colors.green;
    if (percent >= 60) return Colors.blue;
    if (percent >= 40) return Colors.orange;
    return Colors.red;
  }






  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFEA4935)),
            strokeWidth: 3,
          ),
          SizedBox(height: 20),
          Text(
            'Finding your perfect matches...',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, color: Colors.red, size: 60),
            SizedBox(height: 20),
            Text(
              'Unable to load matches',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
            ),
            SizedBox(height: 10),
            Text(
              _errorMessage,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
              ),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: _fetchMatchedProfiles,
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xFFEA4935),
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: 30, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.group, color: Colors.grey[400], size: 80),
            SizedBox(height: 20),
            Text(
              'No matches yet',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
            ),
            SizedBox(height: 10),
            Text(
              'Adjust your preferences to find more matches',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 16,
              ),
            ),
            SizedBox(height: 30),
            ElevatedButton(
              onPressed: () {},
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xFFEA4935),
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: 30, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text('Edit Preferences'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPopupMessage() {
    return AnimatedOpacity(
      opacity: _showPopup ? 1.0 : 0.0,
      duration: Duration(milliseconds: 300),
      child: Container(
        margin: EdgeInsets.all(20),
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.green,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 20,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white, size: 24),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                _popupMessage,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            IconButton(
              icon: Icon(Icons.close, color: Colors.white, size: 18),
              onPressed: () {
                setState(() {
                  _showPopup = false;
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToProfile(int userId) {
    if (!VerificationService.requireVerification(context)) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProfileLoader(userId: userId.toString(), myId: userId.toString(),),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final int crossAxisCount = screenWidth >= 600 ? 3 : 2;
    // Card aspect ratio: portrait photo card ~0.62 works well with full-bleed
    const double childAspectRatio = 0.62;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F8),
      appBar: AppBar(
        title: const Text(
          'Matched Profiles',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: Colors.white,
            letterSpacing: 0.2,
          ),
        ),
        backgroundColor: const Color(0xFFEA4935),
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            tooltip: 'Refresh',
            onPressed: () async {
              setState(() => _isRefreshing = true);
              await _fetchMatchedProfiles(isRefresh: true);
              if (mounted) setState(() => _isRefreshing = false);
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          _isLoading
              ? _buildLoadingState()
              : _errorMessage.isNotEmpty
                  ? _buildErrorState()
                  : _matchedProfiles.isEmpty
                      ? _buildEmptyState()
                      : RefreshIndicator(
                          onRefresh: () async {
                            setState(() => _isRefreshing = true);
                            await _fetchMatchedProfiles(isRefresh: true);
                            if (mounted)
                              setState(() => _isRefreshing = false);
                          },
                          color: const Color(0xFFEA4935),
                          child: ShimmerLoading(
                            isLoading: _isRefreshing,
                            child: CustomScrollView(
                              slivers: [
                                // ── Header strip ─────────────────────────
                                SliverToBoxAdapter(
                                  child: Container(
                                    padding: const EdgeInsets.fromLTRB(
                                        16, 14, 16, 14),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      boxShadow: [
                                        BoxShadow(
                                          color:
                                              Colors.black.withOpacity(0.05),
                                          blurRadius: 6,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFEA4935)
                                                .withOpacity(0.08),
                                            borderRadius:
                                                BorderRadius.circular(20),
                                          ),
                                          child: Text(
                                            '${_matchedProfiles.length} matches found',
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFFEA4935),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                                // ── Profile grid ─────────────────────────
                                SliverPadding(
                                  padding: const EdgeInsets.fromLTRB(
                                      12, 14, 12, 16),
                                  sliver: SliverGrid(
                                    gridDelegate:
                                        SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: crossAxisCount,
                                      crossAxisSpacing: 12,
                                      mainAxisSpacing: 12,
                                      childAspectRatio: childAspectRatio,
                                    ),
                                    delegate: SliverChildBuilderDelegate(
                                      (context, index) =>
                                          _buildProfileCard(index),
                                      childCount: _matchedProfiles.length,
                                    ),
                                  ),
                                ),

                                // ── Verify identity banner ────────────────
                                if (!context.read<UserState>().isVerified)
                                  SliverToBoxAdapter(
                                    child: Container(
                                      margin: const EdgeInsets.fromLTRB(
                                          12, 0, 12, 16),
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius:
                                            BorderRadius.circular(14),
                                        border: Border.all(
                                            color: Colors.orange
                                                .withOpacity(0.4)),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black
                                                .withOpacity(0.05),
                                            blurRadius: 10,
                                          ),
                                        ],
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                              color: Colors.orange
                                                  .withOpacity(0.1),
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(
                                                Icons.verified_user_rounded,
                                                color: Colors.orange,
                                                size: 22),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                const Text(
                                                  'Verify Your Identity',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: 14,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  'Complete verification to access all features',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.grey[600],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(
                                                Icons.arrow_forward_rounded,
                                                color: Color(0xFFEA4935),
                                                size: 20),
                                            onPressed: () {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                    builder: (context) =>
                                                        IDVerificationScreen()),
                                              );
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),

                                const SliverToBoxAdapter(
                                    child: SizedBox(height: 30)),
                              ],
                            ),
                          ),
                        ),

          // ── Notification popup ───────────────────────────────
          if (_showPopup)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _buildPopupMessage(),
            ),
        ],
      ),
    );
  }}
