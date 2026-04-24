import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../service/verification_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../Models/masterdata.dart';
import '../../constant/app_colors.dart';
import '../../core/user_state.dart';
import '../../main.dart';
import '../../pushnotification/pushservice.dart';
import '../../utils/privacy_utils.dart';
import 'package:ms2026/config/app_endpoints.dart';

/// Gallery image model
class GalleryImagee {
  final int id;
  final String imageUrl;
  final String createdDate;
  final String updatedDate;

  GalleryImagee({
    required this.id,
    required this.imageUrl,
    required this.createdDate,
    required this.updatedDate,
  });

  factory GalleryImagee.fromJson(Map<String, dynamic> json) {
    return GalleryImagee(
      id: json['id'] ?? 0,
      imageUrl: json['imageUrl'] ?? '',
      createdDate: json['createdDate'] ?? '',
      updatedDate: json['updatedDate'] ?? '',
    );
  }
}

/// Model class for matched user
class MatchedUser {
  final int userId;
  final String memberid;
  final String firstName;
  final String lastName;
  final bool isVerified;
  final String profilePicture;
  final int age;
  final String heightName;
  final String country;
  final String city;
  final String designation;
  final int matchPercent;
  final List<GalleryImagee> gallery;
  final String privacy;
  final String photo_request;
  final bool canViewPhoto; // backend-computed: true if viewer can see the photo
  final bool isLiked; // NEW: Added liked status

  MatchedUser({
    required this.userId,
    required this.memberid,
    required this.firstName,
    required this.lastName,
    required this.isVerified,
    required this.profilePicture,
    required this.age,
    required this.heightName,
    required this.country,
    required this.city,
    required this.designation,
    required this.matchPercent,
    required this.gallery,
    required this.privacy,
    required this.photo_request,
    required this.canViewPhoto,
    required this.isLiked, // NEW: Added liked status
  });

  factory MatchedUser.fromJson(Map<String, dynamic> json) {
    final galleryJson = json['gallery'] as List<dynamic>? ?? [];
    final galleryImages = galleryJson
        .map((item) => GalleryImagee.fromJson(item))
        .toList();

    return MatchedUser(
      userId: json['userid'],
      memberid: json['memberid'] ?? 'N/A',
      firstName: json['firstName'] ?? '',
      lastName: json['lastName'] ?? '',
      isVerified: json['isVerified'] == 1,
      profilePicture: json['profile_picture'] ?? '',
      age: json['age'] ?? 0,
      heightName: json['height_name'] ?? '',
      country: json['country'] ?? '',
      city: json['city'] ?? '',
      designation: json['designation'] ?? '',
      matchPercent: json['matchPercent'] ?? 0,
      gallery: galleryImages,
      privacy: json['privacy']?.toString().toLowerCase() ?? '',
      photo_request: json['photo_request']?.toString().toLowerCase() ?? '',
      canViewPhoto: PrivacyUtils.canViewPhotoFromJson(json),
      isLiked: json['like'] == true, // NEW: Parse liked status from API
    );
  }

  // Copy with method to update liked status
  MatchedUser copyWith({
    int? userId,
    String? memberid,
    String? firstName,
    String? lastName,
    bool? isVerified,
    String? profilePicture,
    int? age,
    String? heightName,
    String? country,
    String? city,
    String? designation,
    int? matchPercent,
    List<GalleryImagee>? gallery,
    String? privacy,
    String? photo_request,
    bool? canViewPhoto,
    bool? isLiked,
  }) {
    return MatchedUser(
      userId: userId ?? this.userId,
      memberid: memberid ?? this.memberid,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      isVerified: isVerified ?? this.isVerified,
      profilePicture: profilePicture ?? this.profilePicture,
      age: age ?? this.age,
      heightName: heightName ?? this.heightName,
      country: country ?? this.country,
      city: city ?? this.city,
      designation: designation ?? this.designation,
      matchPercent: matchPercent ?? this.matchPercent,
      gallery: gallery ?? this.gallery,
      privacy: privacy ?? this.privacy,
      photo_request: photo_request ?? this.photo_request,
      canViewPhoto: canViewPhoto ?? this.canViewPhoto,
      isLiked: isLiked ?? this.isLiked,
    );
  }

  // Getter to check if we should show clear image (uses backend-authoritative canViewPhoto)
  bool get shouldShowClearImage {
    return canViewPhoto;
  }

  // Getter to check if photo request has been sent
  bool get hasPhotoRequest {
    return photo_request.isNotEmpty &&
        photo_request != 'null' &&
        photo_request != 'free' &&
        photo_request != 'accepted';
  }

  // Getter for photo request status
  String get photoRequestStatus {
    if (photo_request.isEmpty || photo_request == 'null') return 'not_sent';
    return photo_request;
  }

  String get displayName {
    if (memberid != 'N/A' && memberid.isNotEmpty) {
      return '$memberid $lastName'.trim();
    }
    return 'MS: $userId $lastName'.trim();
  }

  String get location => '$city, $country';

  String get heightDisplay {
    final matches = RegExp(r'(\d+)\s*cm').firstMatch(heightName);
    if (matches != null) {
      return '${matches.group(1)} cm';
    }
    return heightName;
  }

  List<String> get allPhotos {
    final photos = <String>[];

    if (profilePicture.isNotEmpty) {
      photos.add(profilePicture);
    }

    for (final galleryItem in gallery) {
      if (galleryItem.imageUrl.isNotEmpty) {
        photos.add(galleryItem.imageUrl);
      }
    }

    if (photos.isEmpty) {
      photos.addAll([
        'https://images.unsplash.com/photo-1494790108755-2616b612b786?w=400',
        'https://images.unsplash.com/photo-1438761681033-6461ffad8d80?w=400',
        'https://images.unsplash.com/photo-1544005313-94ddf0286df2?w=400',
      ]);
    }

    return photos;
  }
}

/// Service class for sending requests
class RequestService {
  final String sendRequestUrl;

  RequestService({required this.sendRequestUrl});

  Future<Map<String, dynamic>> sendRequest({
    required int senderId,
    required int receiverId,
    required String requestType,
  }) async {
    try {
      final response = await http.post(
        Uri.parse(sendRequestUrl),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'sender_id': senderId,
          'receiver_id': receiverId,
          'request_type': requestType,
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        return {
          'success': false,
          'message': 'HTTP Error: ${response.statusCode}',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Error: $e',
      };
    }
  }
}

/// Service class for like actions
class LikeService {
  final String likeApiUrl;

  LikeService({required this.likeApiUrl});

  Future<Map<String, dynamic>> likeAction({
    required int senderId,
    required int receiverId,
    required String action, // 'add' or 'delete'
  }) async {
    try {
      final response = await http.post(
        Uri.parse(likeApiUrl),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'sender_id': senderId.toString(),
          'receiver_id': receiverId.toString(),
          'action': action,
        },
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        return {
          'success': false,
          'message': 'HTTP Error: ${response.statusCode}',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Error: $e',
      };
    }
  }
}

/// Service class to fetch matched users
class MatchService {
  final String apiUrl;
  final String baseUrl;

  MatchService({required this.apiUrl, this.baseUrl = ''});

  Future<List<MatchedUser>> fetchMatchedUsers(int userId) async {
    try {
      final uri = Uri.parse('$apiUrl?userid=$userId');
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success'] == true) {
          final List<dynamic> usersJson = data['matched_users'] ?? [];

          return usersJson.map((json) {
            return MatchedUser.fromJson(json);
          }).toList();
        } else {
          print('API Error: ${data['message']}');
          return [];
        }
      } else {
        print('HTTP Error: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      print('Error fetching matched users: $e');
      return [];
    }
  }

  String getFullImageUrl(String path) {
    if (path.startsWith('http')) return path;
    if (path.startsWith('/')) path = path.substring(1);
    return '$baseUrl/$path';
  }
}

class ProfileSwipeUI extends StatefulWidget {
  final int userId;
  final String matchApiUrl;
  final String sendRequestApiUrl;
  final String baseUrl;
  final bool isBlur;
  final String likeApiUrl; // NEW: Added like API URL

  const ProfileSwipeUI({
    super.key,
    required this.userId,
    required this.matchApiUrl,
    required this.sendRequestApiUrl,
    this.baseUrl = '',
    this.isBlur = true,
    required this.likeApiUrl, // NEW: Added like API URL
  });

  @override
  State<ProfileSwipeUI> createState() => _ProfileSwipeUIState();
}

class _ProfileSwipeUIState extends State<ProfileSwipeUI> {
  final PageController _pageController = PageController();
  late MatchService matchService;
  late RequestService requestService;
  late LikeService likeService;
  List<MatchedUser> profiles = [];
  bool isLoading = true;
  String errorMessage = '';
  int currentIndex = 0;
  String selectedRequestType = '';
  String userimage = '';
  var pageno;
  bool _showPopup = false;
  String _popupMessage = '';
  bool _isProcessingLike = false;

  @override
  void initState() {
    super.initState();
    matchService = MatchService(
        apiUrl: widget.matchApiUrl, baseUrl: widget.baseUrl);
    requestService = RequestService(sendRequestUrl: widget.sendRequestApiUrl);
    likeService = LikeService(likeApiUrl: widget.likeApiUrl);
    _loadProfiles();
    _loadMasterDataForImage();
  }

  @override
  void didUpdateWidget(ProfileSwipeUI oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId && widget.userId != 0) {
      _loadProfiles();
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
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

  Future<void> _loadProfiles() async {
    setState(() {
      isLoading = true;
      errorMessage = '';
    });

    try {
      final users = await matchService.fetchMatchedUsers(widget.userId);

      setState(() {
        profiles = users;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        errorMessage = 'Failed to load profiles: $e';
        isLoading = false;
      });
    }
  }

  bool _isCheckingStatus = false;
  bool _isLoading = true;

  /// Loads the current user's profile image and pageno from masterdata.
  /// Document status and usertype are read from the global [UserState] provider.
  Future<void> _loadMasterDataForImage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataString = prefs.getString('user_data');
      if (userDataString == null) return;
      final userData = jsonDecode(userDataString);
      final userId = int.tryParse(userData["id"].toString());
      if (userId == null) return;
      final UserMasterData user = await fetchUserMasterData(userId.toString());
      if (mounted) {
        setState(() {
          userimage = user.profilePicture;
          pageno = user.pageno;
          _isLoading = false;
          _isCheckingStatus = false;
        });
        // Keep UserState in sync with the data already fetched above –
        // avoids a separate masterdata.php call just for verification/usertype.
        context.read<UserState>().updateFromMasterData(user.docStatus, user.isVerified, user.usertype);
      }
    } catch (e) {
      debugPrint('Error loading master data for image: $e');
      if (mounted) setState(() => _isLoading = false);
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

  // NEW: Handle like action
  Future<void> _handleLikeAction(int index, MatchedUser user) async {
    if (_isProcessingLike) return; // Prevent multiple clicks

    setState(() {
      _isProcessingLike = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataString = prefs.getString('user_data');
      final userData = jsonDecode(userDataString!);
      final senderId = int.tryParse(userData["id"].toString());

      if (senderId == null) {
        _showRequestSentPopup('User not authenticated');
        return;
      }

      final receiverId = user.userId;
      final action = user.isLiked ? 'delete' : 'add';

      final result = await likeService.likeAction(
        senderId: senderId,
        receiverId: receiverId,
        action: action,
      );

      if (result['success'] == true) {
        // Update the profile in the list
        final updatedUser = user.copyWith(isLiked: !user.isLiked);

        setState(() {
          profiles[index] = updatedUser;
        });

        final message = user.isLiked
            ? 'Like removed successfully'
            : 'Liked successfully';
        _showRequestSentPopup(message);
      } else {
        _showRequestSentPopup('Failed: ${result['message']}');
      }
    } catch (e) {
      _showRequestSentPopup('Error: $e');
    } finally {
      setState(() {
        _isProcessingLike = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        _buildMainContent(),
        if (_showPopup)
          Positioned(
            top: 20,
            left: 20,
            right: 20,
            child: _buildPopupMessage(),
          ),
      ],
    );
  }

  Widget _buildMainContent() {
    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
        ),
      );
    }

    if (errorMessage.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: AppColors.primary, size: 48),
            const SizedBox(height: 12),
            Text(
              errorMessage,
              style: const TextStyle(color: AppColors.primary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadProfiles,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (profiles.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'No profiles found',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Check back later for new matches',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade400),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Navigation header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              // Prev arrow
              _NavArrowButton(
                icon: Icons.chevron_left,
                enabled: currentIndex > 0,
                onTap: () {
                  if (currentIndex > 0) {
                    _pageController.previousPage(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    );
                  }
                },
              ),
              const Spacer(),
              // Counter + label
              Column(
                children: [
                  Text(
                    '${currentIndex + 1} of ${profiles.length}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const Text(
                    'Suggested Profiles',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              // Next arrow
              _NavArrowButton(
                icon: Icons.chevron_right,
                enabled: currentIndex < profiles.length - 1,
                onTap: () {
                  if (currentIndex < profiles.length - 1) {
                    _pageController.nextPage(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    );
                  }
                },
              ),
            ],
          ),
        ),
        // Profile cards
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            itemCount: profiles.length,
            onPageChanged: (index) {
              setState(() {
                currentIndex = index;
              });
            },
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: _buildProfileCard(profiles[index], index),
              );
            },
          ),
        ),
        // Page dots
        if (profiles.length > 1)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                profiles.length > 7 ? 7 : profiles.length,
                (i) {
                  final dotIndex = _slidingWindowDotIndex(i);
                  final isActive = dotIndex == currentIndex;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: isActive ? 18 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: isActive
                          ? AppColors.primary
                          : Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }

  /// Maps a dot position [i] (0–6) to the actual profile index using a
  /// sliding window when there are more than 7 profiles.
  int _slidingWindowDotIndex(int i) {
    if (profiles.length <= 7) return i;
    if (currentIndex <= 3) return i;
    if (currentIndex >= profiles.length - 4) return profiles.length - 7 + i;
    return currentIndex - 3 + i;
  }

  Widget _buildPopupMessage() {
    return AnimatedOpacity(
      opacity: _showPopup ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 300),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.green,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _popupMessage,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 20),
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

  Widget _buildProfileCard(MatchedUser user, int index) {
    final photos = user.allPhotos.map((url) => matchService.getFullImageUrl(url)).toList();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.10),
            blurRadius: 18,
            spreadRadius: -2,
            offset: const Offset(0, 6),
          )
        ],
      ),
      child: Column(
        children: [
          // ── Photo section (top ~55%) ──────────────────────────────
          Expanded(
            flex: 55,
            child: ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
              child: Stack(
                children: [
                  _ImageSliderWithDots(
                    user: user,
                    photos: photos,
                    matchService: matchService,
                    onPhotoRequestTap: () async {
                      final prefs = await SharedPreferences.getInstance();
                      final userDataString = prefs.getString('user_data');
                      if (userDataString == null) return;
                      final userData = jsonDecode(userDataString);
                      final senderId = int.tryParse(userData["id"].toString());
                      if (!mounted) return;
                      if (await VerificationService.requireVerification(context)) {
                        if (!mounted) return;
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ProfileLoader(
                              userId: user.userId.toString(),
                              myId: senderId.toString(),
                            ),
                          ),
                        );
                      }
                    },
                  ),
                  // Match % badge – top right
                  Positioned(
                    top: 12,
                    right: 12,
                    child: _MatchBadge(percent: user.matchPercent),
                  ),
                  // Verified badge – top left
                  if (user.isVerified)
                    Positioned(
                      top: 12,
                      left: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1976D2),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 6,
                            )
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.verified,
                                color: Colors.white, size: 14),
                            SizedBox(width: 4),
                            Text(
                              'Verified',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  // Gallery count badge
                  if (user.gallery.isNotEmpty)
                    Positioned(
                      bottom: 10,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.55),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.photo_library_outlined,
                                size: 13, color: Colors.white),
                            const SizedBox(width: 4),
                            Text(
                              '${user.gallery.length + 1} photos',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
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

          // ── Info section (bottom ~45%) ────────────────────────────
          Expanded(
            flex: 45,
            child: Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius:
                    BorderRadius.vertical(bottom: Radius.circular(20)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  // Name row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          user.displayName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),

                  // Age & Height
                  _InfoRow(
                    icon: Icons.cake_outlined,
                    text: '${user.age} yrs  •  ${user.heightDisplay}',
                  ),
                  const SizedBox(height: 3),

                  // Location
                  _InfoRow(
                    icon: Icons.location_on_outlined,
                    text: user.location,
                  ),

                  // Designation
                  if (user.designation.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    _InfoRow(
                      icon: Icons.work_outline,
                      text: user.designation,
                    ),
                  ],

                  // Compatibility bar
                  const SizedBox(height: 6),
                  _CompatibilityBar(percent: user.matchPercent),
                    ],
                  ),

                  // Action buttons
                  Row(
                    children: [
                      // Like button
                      Expanded(
                        child: _ActionButton(
                          label: user.isLiked
                              ? 'Interested'
                              : 'Like',
                          icon: user.isLiked
                              ? Icons.favorite
                              : Icons.favorite_border,
                          isPrimary: false,
                          isActive: user.isLiked,
                          isLoading: _isProcessingLike,
                          onTap: () => _handleLikeAction(index, user),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // View Profile button
                      Expanded(
                        child: _ActionButton(
                          label: 'View Profile',
                          icon: Icons.person_outline,
                          isPrimary: true,
                          onTap: () async {
                            final prefs =
                                await SharedPreferences.getInstance();
                            final userDataString =
                                prefs.getString('user_data');
                            final userData = jsonDecode(userDataString!);
                            final senderId = int.tryParse(
                                userData["id"].toString());
                            if (!mounted) return;
                            if (await VerificationService.requireVerification(context)) {
                              if (!mounted) return;
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ProfileLoader(
                                    userId: user.userId.toString(),
                                    myId: senderId.toString(),
                                  ),
                                ),
                              );
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getMatchColor(int percent) {
    if (percent >= 80) return Colors.green;
    if (percent >= 50) return Colors.orange;
    return AppColors.primary;
  }
}

// ─── Helper widgets ───────────────────────────────────────────────────────────

class _NavArrowButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _NavArrowButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: enabled
              ? AppColors.primary.withOpacity(0.08)
              : Colors.grey.shade100,
          shape: BoxShape.circle,
          border: Border.all(
            color: enabled
                ? AppColors.primary.withOpacity(0.3)
                : Colors.grey.shade300,
          ),
        ),
        child: Icon(
          icon,
          color: enabled ? AppColors.primary : Colors.grey.shade400,
          size: 22,
        ),
      ),
    );
  }
}

class _MatchBadge extends StatelessWidget {
  final int percent;
  const _MatchBadge({required this.percent});

  Color get _color {
    if (percent >= 80) return const Color(0xFF388E3C);
    if (percent >= 50) return const Color(0xFFF57C00);
    return AppColors.primary;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _color,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _color.withOpacity(0.35),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Text(
        '$percent% Match',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: AppColors.textSecondary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _CompatibilityBar extends StatelessWidget {
  final int percent;
  const _CompatibilityBar({required this.percent});

  Color get _color {
    if (percent >= 80) return const Color(0xFF388E3C);
    if (percent >= 50) return const Color(0xFFF57C00);
    return AppColors.primary;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Compatibility',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            Text(
              '$percent%',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: percent / 100,
            minHeight: 5,
            backgroundColor: Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation<Color>(_color),
          ),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isPrimary;
  final bool isActive;
  final bool isLoading;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.isPrimary,
    required this.onTap,
    this.isActive = false,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final primaryColor = AppColors.primary;

    if (isPrimary) {
      return ElevatedButton.icon(
        onPressed: isLoading ? null : onTap,
        icon: isLoading
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Icon(icon, size: 16),
        label: Text(label, style: const TextStyle(fontSize: 13)),
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          elevation: 0,
        ),
      );
    }

    // Outlined style for Express Interest
    return OutlinedButton.icon(
      onPressed: isLoading ? null : onTap,
      icon: isLoading
          ? SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
              ),
            )
          : Icon(icon, size: 16, color: isActive ? primaryColor : AppColors.textSecondary),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          color: isActive ? primaryColor : AppColors.textSecondary,
        ),
      ),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        side: BorderSide(
          color: isActive ? primaryColor : Colors.grey.shade300,
        ),
      ),
    );
  }
}


class _ImageSliderWithDots extends StatefulWidget {
  final MatchedUser user;
  final List<String> photos;
  final MatchService matchService;
  final VoidCallback? onPhotoRequestTap;

  const _ImageSliderWithDots({
    required this.user,
    required this.photos,
    required this.matchService,
    this.onPhotoRequestTap,
  });

  @override
  State<_ImageSliderWithDots> createState() => _ImageSliderWithDotsState();
}

class _ImageSliderWithDotsState extends State<_ImageSliderWithDots> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController.addListener(() {
      setState(() {
        _currentPage = _pageController.page?.round() ?? 0;
      });
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Image slider
        PageView.builder(
          controller: _pageController,
          scrollDirection: Axis.horizontal,
          itemCount: widget.photos.length,
          itemBuilder: (context, index) {
            return _buildImageWidget(index);
          },
        ),

        // Subtle gradient at bottom (for visual continuity)
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            height: 60,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Colors.black.withOpacity(0.3),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),

        // Page indicators (top-center thin line dots)
        if (widget.photos.length > 1)
          Positioned(
            top: 10,
            left: 40,
            right: 40,
            child: Row(
              children: List.generate(
                widget.photos.length,
(index) {
                  final isActive = _currentPage == index;
                  return Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      height: 3,
                      decoration: BoxDecoration(
                        color: isActive
                            ? Colors.white
                            : Colors.white.withOpacity(0.45),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

        // Photo protected overlay for blurred images
        if (!widget.user.shouldShowClearImage)
          Positioned.fill(
            child: GestureDetector(
              onTap: widget.onPhotoRequestTap,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.15),
                      Colors.black.withOpacity(0.55),
                    ],
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.15),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.5),
                          width: 1.5,
                        ),
                      ),
                      child: const Icon(
                        Icons.lock_outline_rounded,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Photo Protected',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'View profile to see photos',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: widget.onPhotoRequestTap,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 22, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(30),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 12,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.person_outline_rounded,
                                color: AppColors.primary, size: 16),
                            const SizedBox(width: 7),
                            Text(
                              'View Profile',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
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
          ),
      ],
    );
  }

  Widget _buildImageWidget(int index) {
    // Apply blur if privacy is not free AND photo_request is not accepted
    final shouldShowClearImage = widget.user.shouldShowClearImage;

    if (shouldShowClearImage) {
      // Show clear image
      return Image.network(
        widget.photos[index],
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Container(
            color: Colors.grey[200],
            child: Center(
              child: CircularProgressIndicator(
                value: loadingProgress.expectedTotalBytes != null
                    ? loadingProgress.cumulativeBytesLoaded /
                    loadingProgress.expectedTotalBytes!
                    : null,
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.red),
              ),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) => Container(
          color: Colors.grey[200],
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.person,
                  size: 60,
                  color: Colors.grey,
                ),
                const SizedBox(height: 8),
                Text(
                  'Photo ${index + 1}',
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      // Show blurred image
      return Stack(
        children: [
          ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Image.network(
              widget.photos[index],
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return Container(
                  color: Colors.grey[200],
                  child: Center(
                    child: CircularProgressIndicator(
                      value: loadingProgress.expectedTotalBytes != null
                          ? loadingProgress.cumulativeBytesLoaded /
                          loadingProgress.expectedTotalBytes!
                          : null,
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.red),
                    ),
                  ),
                );
              },
              errorBuilder: (context, error, stackTrace) => Container(
                color: Colors.grey[200],
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.person,
                        size: 60,
                        color: Colors.grey,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Photo ${index + 1}',
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Transparent overlay for click
          Container(
            color: Colors.transparent,
          ),
        ],
      );
    }
  }

}
