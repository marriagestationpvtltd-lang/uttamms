import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:ui' as ui;

import 'package:ms2026/Auth/Screen/signupscreen10.dart';
import 'package:ms2026/Notification/notification_inbox_service.dart';
import 'package:ms2026/constant/app_colors.dart';
import 'package:ms2026/constant/app_dimensions.dart';
import 'package:ms2026/constant/app_text_styles.dart';
import 'package:ms2026/ReUsable/loading_widgets.dart';
import 'package:ms2026/core/user_state.dart';
import 'package:ms2026/utils/image_utils.dart';
import '../main.dart';
import '../pushnotification/pushservice.dart';
import 'package:ms2026/config/app_endpoints.dart';
import 'package:ms2026/features/activity/services/activity_service.dart';
import 'package:ms2026/service/verification_service.dart';

class FavoritePeoplePage extends StatefulWidget {
  const FavoritePeoplePage({super.key});

  @override
  State<FavoritePeoplePage> createState() => _FavoritePeoplePageState();
}

class _FavoritePeoplePageState extends State<FavoritePeoplePage> {
  static const String _defaultLocationLabel = 'Location not available';
  static const String _defaultProfessionLabel = 'Profession not available';
  static const String _defaultProfileImage =
      'https://images.unsplash.com/photo-1529626455594-4ff0802cfb7e';
  static const double _badgeLabelMaxWidth = 150;
  static const double _favoriteCardRadius = 30;

  List<dynamic> favoritePeople = [];
  bool isLoading = true;
  bool _isRefreshing = false;
  String errorMessage = '';
  String? token;
  int? userId;
  String? userName;
  String? userLastName;
  bool _showPopup = false;
  String _popupMessage = '';
  String _selectedRequestType = 'Profile';

  @override
  void initState() {
    super.initState();
    _initializeUserData();
  }

  Future<void> _initializeUserData() async {
    final prefs = await SharedPreferences.getInstance();
    token = prefs.getString('bearer_token');
    final userDataString = prefs.getString('user_data');

    if (userDataString != null) {
      final userData = jsonDecode(userDataString);
      userId = int.tryParse(userData["id"].toString());
      userName = userData['firstName']?.toString();
      userLastName = userData['lastName']?.toString();
      if (userId != null) {
        _fetchFavoritePeople();
      }
    } else {
      setState(() {
        isLoading = false;
        errorMessage = 'User data not found. Please login again.';
      });
    }
  }

  Future<void> _fetchFavoritePeople({bool isRefresh = false}) async {
    if (userId == null) {
      setState(() {
        isLoading = false;
        errorMessage = 'User ID not found';
      });
      return;
    }

    if (!isRefresh) {
      setState(() {
        isLoading = true;
        errorMessage = '';
      });
    } else {
      setState(() => errorMessage = '');
    }

    try {
      final url = Uri.parse(
          '${kApiBaseUrl}/Api2/likelist.php?user_id=$userId');

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['status'] == 'success') {
          setState(() {
            favoritePeople = data['data'];
            isLoading = false;
          });
        } else {
          setState(() {
            errorMessage = data['message'] ?? 'Failed to fetch data';
            isLoading = false;
          });
        }
      } else {
        setState(() {
          errorMessage = 'Failed to load data. Status code: ${response.statusCode}';
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = 'Error: $e';
        isLoading = false;
      });
    }
  }

  Future<void> _removeFavorite(dynamic receiverId) async {
    if (userId == null) {
     // _showPopupMessage('User ID not found', isError: true);
      return;
    }

    try {
      final url = Uri.parse(
          '${kApiBaseUrl}/Api2/likelist.php?user_id=$userId&action=delete&receiver_id=$receiverId');

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['status'] == 'success') {
          // FIXED: Use 'userid' instead of 'id'
          setState(() {
            favoritePeople.removeWhere((person) => person['userid'] == receiverId);
          });
          // Log unlike activity (fire-and-forget)
          ActivityService.instance.log(
            userId: userId.toString(),
            activityType: ActivityType.likeRemoved,
            targetUserId: receiverId.toString(),
          );
       //   _showPopupMessage('Removed from favorites');
        } else {
       //   _showPopupMessage(data['message'] ?? 'Failed to remove', isError: true);
        }
      } else {
      //  _showPopupMessage('Failed to remove. Please try again.', isError: true);
      }
    } catch (e) {
     // _showPopupMessage('Error: $e', isError: true);
    }
  }
  // EXACT SAME METHOD AS MatchedProfilesPagee
  Future<void> _sendRequest(int receiverId, String receiverName, String requestType) async {
    try {
      // Ensure requestType has proper capitalization
      String formattedRequestType = requestType;
      if (requestType.toLowerCase() == 'profile') formattedRequestType = 'Profile';
      if (requestType.toLowerCase() == 'photo') formattedRequestType = 'Photo';
      if (requestType.toLowerCase() == 'chat') formattedRequestType = 'Chat';

      print('Sending request: sender_id=$userId, receiver_id=$receiverId, request_type=$formattedRequestType');

      // Try with JSON encoding
      final Map<String, dynamic> requestData = {
        'sender_id': userId,
        'receiver_id': receiverId,
        'request_type': formattedRequestType,
      };

      print('Request data (JSON): $requestData');

      final response = await http.post(
        Uri.parse('${kApiBaseUrl}/Api2/send_request.php'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode(requestData),
      );

      print('Response status: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          // Log request_sent activity (fire-and-forget)
          ActivityService.instance.log(
            userId: userId.toString(),
            activityType: ActivityType.requestSent,
            targetUserId: receiverId.toString(),
            description: '$formattedRequestType request sent to $receiverName',
          );
          // Send notification
          final success = await NotificationService.sendRequestNotification(
            recipientUserId: receiverId.toString(),
            senderName: "MS:$userId ${userLastName ?? ''}",
            senderId: userId.toString(),
            requestType: formattedRequestType,
          );

          if (success) {
            print("Request notification sent!");
          } else {
            print("Failed to send notification.");
          }

          await NotificationInboxService.recordOutgoingRequest(
            recipientUserId: receiverId.toString(),
            requestType: formattedRequestType,
            recipientName: receiverName,
          );

          _showRequestSentPopup('$formattedRequestType request sent to $receiverName');
        } else {
          _showRequestSentPopup('Failed: ${data['message']}');
        }
      } else {
        _showRequestSentPopup('HTTP Error: ${response.statusCode}');
      }
    } catch (e) {
      _showRequestSentPopup('Error: $e');
    }
  }  void _showRequestSentPopup(String message) {
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

  void _handleSendRequest(BuildContext context, int receiverId, String receiverName) {
    if (VerificationService.requireVerification(context)) {
      _showSendRequestDialog(context, receiverId, receiverName);
    }
  }

  void _handleViewProfile(BuildContext context, int receiverId) {
    if (VerificationService.requireVerification(context)) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ProfileLoader(userId: receiverId.toString(), myId: userId.toString(),),
        ),
      );
    }
  }

  // EXACT SAME DIALOG AS MatchedProfilesPagee
  void _showSendRequestDialog(
      BuildContext context,
      int receiverId,
      String receiverName,
      {String defaultRequestType = 'Profile'}) {

    String dialogSelectedRequestType = defaultRequestType;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text(
                'Send Request',
                style: TextStyle(
                  color: Color(0xFFEA4935),
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'To: $receiverName',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Select Request Type:',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildRequestTypeOption(
                    context,
                    setState,
                    dialogSelectedRequestType,
                    'Profile',
                    Icons.person_outline,
                    'View',
                        (newValue) {
                      setState(() {
                        dialogSelectedRequestType = newValue;
                      });
                    },
                  ),
                  _buildRequestTypeOption(
                    context,
                    setState,
                    dialogSelectedRequestType,
                    'Photo',
                    Icons.photo_library_outlined,
                    'Request More Photos',
                        (newValue) {
                      setState(() {
                        dialogSelectedRequestType = newValue;
                      });
                    },
                  ),
                  _buildRequestTypeOption(
                    context,
                    setState,
                    dialogSelectedRequestType,
                    'Chat',
                    Icons.chat_outlined,
                    'Start a Conversation',
                        (newValue) {
                      setState(() {
                        dialogSelectedRequestType = newValue;
                      });
                    },
                  ),
                  const SizedBox(height: 20),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    await _sendRequest(receiverId, receiverName, dialogSelectedRequestType);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xFFEA4935),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Send Request'),
                ),
              ],
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            );
          },
        );
      },
    );
  }

  // EXACT SAME WIDGET AS MatchedProfilesPagee
  Widget _buildRequestTypeOption(
      BuildContext context,
      StateSetter setState,
      String currentSelection,
      String value,
      IconData icon,
      String description,
      Function(String) onSelected,
      ) {
    final isSelected = currentSelection == value;

    return GestureDetector(
      onTap: () {
        onSelected(value);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? Color(0xFFEA4935).withOpacity(0.1) : Colors.grey.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Color(0xFFEA4935) : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isSelected ? Color(0xFFEA4935) : Colors.grey[300],
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: isSelected ? Colors.white : Colors.grey[700],
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: isSelected ? Color(0xFFEA4935) : Colors.black,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(
                Icons.check_circle,
                color: Color(0xFFEA4935),
                size: 20,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPopupMessage() {
    return AnimatedOpacity(
      opacity: _showPopup ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 300),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _popupMessage.contains('Failed') || _popupMessage.contains('Error')
              ? Colors.red
              : Colors.green,
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
            Icon(
              _popupMessage.contains('Failed') || _popupMessage.contains('Error')
                  ? Icons.error_outline
                  : Icons.check_circle,
              color: Colors.white,
              size: 24,
            ),
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

  // Check if image should be clear or blurred
  bool _shouldShowClearImage(Map<String, dynamic> person) {
    // Prefer backend-computed result when available
    if (person.containsKey('can_view_photo')) {
      return person['can_view_photo'] == true;
    }
    // Only accept when photo request is accepted - ignore privacy
    final photoRequest = person['photo_request']?.toString().toLowerCase() ?? '';
    return photoRequest == 'accepted';
  }

  String _getPhotoRequestStatus(Map<String, dynamic> person) {
    final photoRequest = person['photo_request']?.toString().toLowerCase() ?? '';
    if (photoRequest.isEmpty || photoRequest == 'null') return 'not_sent';
    return photoRequest;
  }

  int _verifiedFavoritesCount() {
    return favoritePeople.where((person) {
      final candidate = person as Map<String, dynamic>;
      return candidate['isVerified'] == 1 || candidate['isVerified'] == '1';
    }).length;
  }

  String _getDisplayNameWithFallback(String fullName, String age) {
    final trimmedName = fullName.trim();
    if (trimmedName.isEmpty && age.isEmpty) return 'Unknown User';
    if (trimmedName.isEmpty) return 'Unknown User, $age';
    if (age.isEmpty) return trimmedName;
    return '$trimmedName, $age';
  }

  String _photoRequestHighlightLabel(String photoRequestStatus) {
    switch (photoRequestStatus) {
      case 'accepted':
        return 'Photo request accepted';
      case 'pending':
        return 'Photo request pending';
      default:
        return 'Ready to connect';
    }
  }

  TextStyle _badgeTextStyle(bool darkText) {
    final baseStyle = darkText ? AppTextStyles.bodySmall : AppTextStyles.whiteBody;
    return baseStyle.copyWith(
      color: darkText ? AppColors.textPrimary : Colors.white,
      fontWeight: FontWeight.w600,
    );
  }

  ({String label, Color color, IconData icon}) _documentStatusStyle() {
    switch (context.read<UserState>().identityStatus.toLowerCase()) {
      case 'approved':
        return (
          label: 'ID Approved',
          color: AppColors.success,
          icon: Icons.verified_user_rounded,
        );
      case 'pending':
        return (
          label: 'ID Pending',
          color: AppColors.warning,
          icon: Icons.hourglass_top_rounded,
        );
      case 'rejected':
        return (
          label: 'ID Rejected',
          color: AppColors.error,
          icon: Icons.gpp_bad_rounded,
        );
      default:
        return (
          label: 'ID Required',
          color: AppColors.textHint,
          icon: Icons.shield_outlined,
        );
    }
  }

  Widget _buildHeaderSection() {
    final documentStatus = _documentStatusStyle();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          colors: [Color(0xFFF8576B), Color(0xFFFF8A5B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.22),
            blurRadius: 30,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your favorite people',
                      style: AppTextStyles.whiteHeading.copyWith(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Profiles you loved most — redesigned to feel premium, polished and easy to explore.',
                      style: AppTextStyles.whiteBody.copyWith(
                        color: Colors.white.withOpacity(0.88),
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.favorite_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _buildHeaderMetric(
                  value: favoritePeople.length.toString(),
                  label: 'Saved',
                  icon: Icons.bookmark_rounded,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildHeaderMetric(
                  value: _verifiedFavoritesCount().toString(),
                  label: 'Verified',
                  icon: Icons.verified_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.14),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withOpacity(0.18)),
            ),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: documentStatus.color.withOpacity(0.22),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(documentStatus.icon, color: Colors.white, size: 16),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    documentStatus.label,
                    style: AppTextStyles.whiteBody.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  context.read<UserState>().isVerified
                      ? 'Unlocked'
                      : 'Restricted',
                  style: AppTextStyles.whiteBody.copyWith(
                    color: Colors.white.withOpacity(0.78),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderMetric({
    required String value,
    required String label,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.18)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.18),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: AppTextStyles.whiteHeading.copyWith(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  label,
                  style: AppTextStyles.whiteBody.copyWith(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFDF6F7),
      appBar: AppBar(
        elevation: 0,
        centerTitle: false,
        backgroundColor: const Color(0xFFFDF6F7),
        titleSpacing: 16,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Favorite People',
              style: AppTextStyles.heading3.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              'A premium look for your saved matches',
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: IconButton(
                icon: const Icon(Icons.refresh_rounded, color: AppColors.primary),
                onPressed: _fetchFavoritePeople,
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned(
            top: -80,
            right: -50,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withOpacity(0.08),
              ),
            ),
          ),
          Positioned(
            top: 110,
            left: -70,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFFFC7D1).withOpacity(0.38),
              ),
            ),
          ),
          RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () async {
              setState(() => _isRefreshing = true);
              await _fetchFavoritePeople(isRefresh: true);
              if (mounted) setState(() => _isRefreshing = false);
            },
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              slivers: [
                SliverToBoxAdapter(child: _buildHeaderSection()),
                if (isLoading)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: LoadingWidget(message: 'Loading your favorite people...'),
                  )
                else if (errorMessage.isNotEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: ErrorStateWidget(
                      title: 'Unable to load favorites',
                      subtitle: 'Pull down to refresh or try again.',
                      errorMessage: errorMessage,
                      onRetry: _fetchFavoritePeople,
                    ),
                  )
                else if (favoritePeople.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyStateWidget(
                      icon: Icons.favorite_border_rounded,
                      title: 'No favorite people yet',
                      subtitle: 'The profiles you like most will show up here in a much better style.',
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => _favoriteCard(
                          context,
                          favoritePeople[index] as Map<String, dynamic>,
                          index,
                        ),
                        childCount: favoritePeople.length,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (_showPopup)
            Positioned(
              top: 20,
              left: 20,
              right: 20,
              child: _buildPopupMessage(),
            ),
        ],
      ),
    );
  }

  Widget _favoriteCard(BuildContext context, Map<String, dynamic> person, int index) {
    final firstName = person['firstName']?.toString() ?? '';
    final lastName = person['lastName']?.toString() ?? '';
    final fullName = '$firstName $lastName';
    final isVerified = person['isVerified'] == 1 || person['isVerified'] == '1';
    final city = person['city']?.toString() ?? _defaultLocationLabel;
    final designation =
        person['designation']?.toString() ?? _defaultProfessionLabel;
    final rawProfileImage = person['profile_picture']?.toString() ?? '';
    final resolvedProfileImage = resolveApiImageUrl(rawProfileImage);
    final profileImage = resolvedProfileImage.isNotEmpty
        ? resolvedProfileImage
        : _defaultProfileImage;
    final age = person['age']?.toString() ?? '';
    final photoRequestStatus = _getPhotoRequestStatus(person);
    final displayName = _getDisplayNameWithFallback(fullName, age);

    // FIXED: Use 'userid' instead of 'id'
    final receiverIdStr = person['userid']?.toString() ?? '0';
    final receiverId = int.tryParse(receiverIdStr) ?? 0;

    // Determine if image should be blurred
    final shouldShowClearImage = _shouldShowClearImage(person);

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_favoriteCardRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(_favoriteCardRadius),
                ),
                child: SizedBox(
                  height: 250,
                  width: double.infinity,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CachedNetworkImage(
                        imageUrl: profileImage,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          color: const Color(0xFFF7E9EB),
                          alignment: Alignment.center,
                          child: const CircularProgressIndicator(
                            color: AppColors.primary,
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: const Color(0xFFF7E9EB),
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.person_rounded,
                            size: 72,
                            color: AppColors.textHint,
                          ),
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withOpacity(0.08),
                              Colors.black.withOpacity(0.68),
                            ],
                          ),
                        ),
                      ),
                      if (!shouldShowClearImage)
                        Positioned.fill(
                          child: GestureDetector(
                            onTap: () {
                              _showPhotoRequestOverlay(context, person, fullName);
                            },
                            child: BackdropFilter(
                              filter: ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                              child: Container(
                                color: Colors.black.withOpacity(0.20),
                                alignment: Alignment.center,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 16,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.18),
                                    borderRadius: BorderRadius.circular(22),
                                    border: Border.all(
                                      color: Colors.white.withOpacity(0.24),
                                    ),
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.lock_rounded,
                                        color: Colors.red.shade100,
                                        size: 26,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Photo Protected',
                                        style: AppTextStyles.whiteLabel.copyWith(
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Tap to request access',
                                        style: AppTextStyles.whiteBody.copyWith(
                                          color: Colors.white.withOpacity(0.84),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      Positioned(
                        top: 16,
                        left: 16,
                        child: _buildImageBadge(
                          icon: isVerified
                              ? Icons.verified_rounded
                              : Icons.favorite_rounded,
                          label: isVerified ? 'Verified' : 'Saved Match',
                          badgeColor:
                              isVerified ? AppColors.verified : AppColors.primary,
                        ),
                      ),
                      Positioned(
                        top: 16,
                        right: 16,
                        child: GestureDetector(
                          onTap: () {
                            _showDeleteConfirmationDialog(receiverId, fullName);
                          },
                          child: Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.92),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.12),
                                  blurRadius: 14,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.favorite_rounded,
                              color: AppColors.primary,
                              size: 22,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 18,
                        right: 18,
                        bottom: 18,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    displayName,
                                    style: AppTextStyles.whiteHeading.copyWith(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (isVerified) ...[
                                  const SizedBox(width: 8),
                                  const Icon(
                                    Icons.verified_rounded,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                if (designation != _defaultProfessionLabel)
                                  _buildImageBadge(
                                    icon: Icons.work_outline_rounded,
                                    label: designation,
                                    badgeColor: Colors.white,
                                    darkText: true,
                                  ),
                                if (city != _defaultLocationLabel)
                                  _buildImageBadge(
                                    icon: Icons.location_on_outlined,
                                    label: city,
                                    badgeColor: Colors.white,
                                    darkText: true,
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Quick highlights',
                  style: AppTextStyles.labelLarge.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _buildInfoChip(
                      icon: Icons.favorite_rounded,
                      label: 'Favorite #${index + 1}',
                      color: const Color(0xFFFFF1F3),
                      textColor: AppColors.primary,
                    ),
                    _buildInfoChip(
                      icon: shouldShowClearImage
                          ? Icons.photo_camera_front_rounded
                          : Icons.lock_outline_rounded,
                      label: shouldShowClearImage
                          ? 'Photo visible'
                          : 'Photo protected',
                      color: shouldShowClearImage
                          ? const Color(0xFFEFF8F0)
                          : const Color(0xFFFFF5E8),
                      textColor: shouldShowClearImage
                          ? AppColors.success
                          : AppColors.warning,
                    ),
                    _buildInfoChip(
                      icon: Icons.send_rounded,
                      label: _photoRequestHighlightLabel(photoRequestStatus),
                      color: const Color(0xFFF4F2FF),
                      textColor: const Color(0xFF6C4CF1),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    _actionButton(
                      text: 'Send Request',
                      icon: Icons.send_rounded,
                      gradient: const LinearGradient(
                        colors: [Color(0xffFF3D57), Color(0xffFF7A45)],
                      ),
                      onPressed: () {
                        _handleSendRequest(context, receiverId, fullName);
                      },
                    ),
                    const SizedBox(width: 12),
                    _actionButton(
                      text: 'View Profile',
                      icon: Icons.visibility_rounded,
                      foregroundColor: AppColors.primary,
                      borderColor: const Color(0xFFFFCCD2),
                      backgroundColor: const Color(0xFFFFF7F8),
                      onPressed: () {
                        _handleViewProfile(context, receiverId);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageBadge({
    required IconData icon,
    required String label,
    required Color badgeColor,
    bool darkText = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: darkText ? badgeColor.withOpacity(0.92) : badgeColor.withOpacity(0.20),
        borderRadius: BorderRadius.circular(AppDimensions.radiusRound),
        border: Border.all(
          color: darkText
              ? Colors.white.withOpacity(0.32)
              : Colors.white.withOpacity(0.22),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 15,
            color: darkText ? AppColors.textPrimary : Colors.white,
          ),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _badgeLabelMaxWidth),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _badgeTextStyle(darkText),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip({
    required IconData icon,
    required String label,
    required Color color,
    required Color textColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: textColor),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              style: AppTextStyles.labelMedium.copyWith(
                color: textColor,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  void _showPhotoRequestOverlay(BuildContext context, Map<String, dynamic> person, String receiverName) {
    final photoRequestStatus = _getPhotoRequestStatus(person);
    final receiverId = int.tryParse(person['userid']?.toString() ?? '0') ?? 0;

    if (!VerificationService.requireVerification(context)) {
      return;
    }

    if (photoRequestStatus == 'not_sent') {
      _showSendRequestDialog(context, receiverId, receiverName, defaultRequestType: 'Photo');
    } else if (photoRequestStatus == 'pending') {
      // _showPopupMessage('Your photo request is pending approval');
    } else if (photoRequestStatus == 'rejected') {
     //  _showPopupMessage('Your photo request was rejected');
    }
  }

  void _showDeleteConfirmationDialog(dynamic receiverId, String receiverName) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Remove from Favorites'),
          content: Text('Are you sure you want to remove $receiverName from your favorites?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _removeFavorite(receiverId);
              },
              child: const Text(
                'Remove',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _actionButton({
    required String text,
    required IconData icon,
    Gradient? gradient,
    Color? backgroundColor,
    Color? foregroundColor,
    Color? borderColor,
    required VoidCallback onPressed,
  }) {
    return Expanded(
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          gradient: gradient,
          color: gradient == null ? backgroundColor ?? Colors.white : null,
          borderRadius: BorderRadius.circular(18),
          border: borderColor == null
              ? null
              : Border.all(
                  color: borderColor,
                ),
          boxShadow: gradient == null
              ? null
              : [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.22),
                    blurRadius: 14,
                    offset: const Offset(0, 10),
                  ),
                ],
        ),
        child: TextButton.icon(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            foregroundColor: foregroundColor ?? Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
          icon: Icon(icon, size: 18, color: foregroundColor ?? Colors.white),
          label: Text(
            text,
            style: AppTextStyles.labelMedium.copyWith(
              color: foregroundColor ?? Colors.white,
              fontSize: 13,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}
