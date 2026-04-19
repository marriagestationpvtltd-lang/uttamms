import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:ui' as ui;
import '../main.dart';
import '../pushnotification/pushservice.dart';
import '../utils/privacy_utils.dart'; // Add privacy utils import
import 'filterPage.dart';
import 'package:ms2026/config/app_endpoints.dart';

class SearchResultPage extends StatefulWidget {
  final Map<String, dynamic>? filterParams;
  final String? quickSearchType;
  final String? quickSearchValue;

  const SearchResultPage({
    super.key,
    this.filterParams,
    this.quickSearchType,
    this.quickSearchValue,
  });

  @override
  State<SearchResultPage> createState() => _SearchResultPageState();
}

class _SearchResultPageState extends State<SearchResultPage> {
  List<dynamic> profiles = [];
  bool _isLoading = true;
  String _errorMessage = '';
  int _totalCount = 0;
  int _currentUserId = 0;
  String docstatus = 'not_uploaded'; // Add document status
  Set<int> _blockedUserIds = {};

  // Track sent requests
  Map<int, String> _sentRequests = {};

  @override
  void initState() {
    super.initState();
    _loadUserDataAndFetchProfiles();
  }

  Future<void> _loadUserDataAndFetchProfiles() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataString = prefs.getString('user_data');

      if (userDataString == null) {
        setState(() {
          _errorMessage = 'User data not found';
          _isLoading = false;
        });
        return;
      }

      final userData = jsonDecode(userDataString);
      final userId = int.tryParse(userData["id"].toString()) ?? 0;

      setState(() {
        _currentUserId = userId;
      });

      if (userId > 0) {
        await _checkDocumentStatus(userId); // Check document status
        await _fetchBlockedUsers();
        await _fetchProfiles(userId);
      } else {
        setState(() {
          _errorMessage = 'Invalid user ID';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load user data: $e';
        _isLoading = false;
      });
    }
  }

  // Check document status
  Future<void> _checkDocumentStatus(int userId) async {
    try {
      final response = await http.post(
        Uri.parse("${kApiBaseUrl}/Api2/check_document_status.php"),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_id': userId}),
      );

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          setState(() {
            docstatus = result['status'] ?? 'not_uploaded';
          });
        }
      }
    } catch (e) {
      print("Error checking document status: $e");
    }
  }

  // Fetch blocked users
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
      print("Error fetching blocked users: $e");
    }
  }

  Future<void> _fetchProfiles(int userId) async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = '';
      });

      String baseUrl =
          '${kApiBaseUrl}/Api2/search_opposite_gender.php?user_id=$userId';

      // Quick search by phone / id / email / name
      if (widget.quickSearchType != null &&
          widget.quickSearchValue != null &&
          widget.quickSearchValue!.isNotEmpty) {
        baseUrl =
            '$baseUrl&search_type=${Uri.encodeComponent(widget.quickSearchType!)}'
            '&search_value=${Uri.encodeComponent(widget.quickSearchValue!)}';
      } else if (widget.filterParams != null &&
          widget.filterParams!.isNotEmpty) {
        // Advanced search with filters
        Map<String, String> queryParams = {};
        widget.filterParams!.forEach((key, value) {
          if (value != null) {
            queryParams[key] = value.toString();
          }
        });
        queryParams.removeWhere((key, value) => value.isEmpty);
        if (queryParams.isNotEmpty) {
          String queryString = Uri(queryParameters: queryParams).query;
          baseUrl = '$baseUrl&$queryString';
        }
      }

      final url = Uri.parse(baseUrl);
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);

        if (result['success'] == true) {
          final allProfiles = result['data'] ?? [];
          // Filter out blocked users
          final filteredProfiles = allProfiles.where((profile) {
            final profileId = int.tryParse(profile['id']?.toString() ?? '0') ?? 0;
            return !_blockedUserIds.contains(profileId);
          }).toList();

          setState(() {
            profiles = filteredProfiles;
            _totalCount = filteredProfiles.length;
            _isLoading = false;
          });
        } else {
          throw Exception(result['message'] ?? 'Failed to load profiles');
        }
      } else {
        throw Exception('Failed to load data: ${response.statusCode}');
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
      print('Error fetching profiles: $e');
    }
  }

  // Helper function to check if photo should be blurred
  bool _shouldShowClearImage(Map<String, dynamic> profile) {
    // Use PrivacyUtils for consistent privacy enforcement
    final privacy = profile['privacy']?.toString();
    final photoRequest = profile['photo_request']?.toString();
    final canViewPhoto = profile['can_view_photo'] as bool?;

    return PrivacyUtils.shouldShowClearImage(
      privacy: privacy,
      photoRequest: photoRequest,
      canViewPhoto: canViewPhoto,
    );
  }

  // Helper function to get photo request status
  String _getPhotoRequestStatus(Map<String, dynamic> profile) {
    final photoRequest = profile['photo_request']?.toString().toLowerCase() ?? '';
    if (photoRequest.isEmpty || photoRequest == 'null') return 'not_sent';
    return photoRequest;
  }

  // Handle document not approved status
  void _handleDocumentNotApproved() {
    if (docstatus == 'not_uploaded') {
      // Navigate to ID verification screen
      // Navigator.push(context, MaterialPageRoute(builder: (context) => IDVerificationScreen()));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please upload your documents first'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
    } else if (docstatus == 'pending') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Your documents are pending approval'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 3),
        ),
      );
    } else if (docstatus == 'rejected') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Your documents were rejected. Please re-upload'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }


  bool _isRequestSent(int userId) {
    return _sentRequests.containsKey(userId);
  }



  void _showRequestTypeDialog(int receiverId, String receiverName, Map<String, dynamic> profile) {
    // Check if we need to handle photo request specifically
    final shouldShowClearImage = _shouldShowClearImage(profile);
    final photoRequestStatus = _getPhotoRequestStatus(profile);

    String selectedRequestType = 'Profile';

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(
                'Send Request to $receiverName',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Select Request Type:',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  SizedBox(height: 20),

                  _buildRequestTypeOption(
                    'Profile',
                    'View Full Profile Details',
                    Icons.person_outline,
                    selectedRequestType == 'Profile',
                        () => setState(() => selectedRequestType = 'Profile'),
                  ),
                  SizedBox(height: 12),

                  _buildRequestTypeOption(
                    'Photo',
                    shouldShowClearImage ? 'View Gallery Photos' : 'Request Photo Access',
                    Icons.photo_library_outlined,
                    selectedRequestType == 'Photo',
                        () => setState(() => selectedRequestType = 'Photo'),
                  ),
                  SizedBox(height: 12),

                  _buildRequestTypeOption(
                    'Chat',
                    'Start a Conversation',
                    Icons.chat_bubble_outline,
                    selectedRequestType == 'Chat',
                        () => setState(() => selectedRequestType = 'Chat'),
                  ),

                  // Show photo request status if applicable
                  if (!shouldShowClearImage)
                    Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text(
                        _getPhotoRequestStatusText(photoRequestStatus),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange,
                          fontStyle: FontStyle.italic,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Cancel',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ),

              ],
            );
          },
        );
      },
    );
  }

  String _getPhotoRequestStatusText(String status) {
    switch (status) {
      case 'pending':
        return 'Photo request already sent and pending approval';
      case 'rejected':
        return 'Previous photo request was rejected';
      case 'accepted':
        return 'Photo access already granted';
      default:
        return 'Photo access requires permission';
    }
  }

  Widget _buildRequestTypeOption(String title,
      String subtitle,
      IconData icon,
      bool isSelected,
      VoidCallback onTap,) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? Color(0xffFF0066).withOpacity(0.1) : Colors.grey
              .shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Color(0xffFF0066) : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isSelected ? Color(0xffFF0066) : Colors.grey.shade300,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 20,
                color: isSelected ? Colors.white : Colors.grey.shade700,
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Color(0xffFF0066) : Colors.black87,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check_circle,
                color: Color(0xffFF0066),
                size: 24,
              ),
          ],
        ),
      ),
    );
  }

  String _buildResultTitle() {
    if (widget.quickSearchType != null && widget.quickSearchValue != null) {
      final typeLabel = {
        'phone': 'Phone',
        'id': 'Profile ID',
        'email': 'Email',
        'name': 'Name',
      }[widget.quickSearchType] ??
          widget.quickSearchType!;
      return 'Results for "$typeLabel: ${widget.quickSearchValue}"';
    }
    if (widget.filterParams != null && widget.filterParams!.isNotEmpty) {
      return 'Match Based On Your Filter';
    }
    return 'All Matches';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),

            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      _buildResultTitle(),
                      style: TextStyle(
                        color: Color(0xfffb5f6a),
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_totalCount > 0)
                    Text(
                      "$_totalCount Matches",
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                ],
              ),
            ),

            Expanded(
              child: _buildProfileGrid(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileGrid() {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(color: Color(0xffFF0066)),
      );
    }

    if (_errorMessage.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 60, color: Colors.red),
            SizedBox(height: 16),
            Text(
              'Error Loading Profiles',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.red,
              ),
            ),
            SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _errorMessage,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadUserDataAndFetchProfiles,
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xffFF0066),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text('Retry', style: TextStyle(color: Colors.white)),
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
            Icon(Icons.search_off, size: 60, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              widget.quickSearchType != null
                  ? 'No Results Found'
                  : widget.filterParams != null &&
                          widget.filterParams!.isNotEmpty
                      ? 'No Profiles Match Your Filters'
                      : 'No Profiles Found',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            SizedBox(height: 8),
            Text(
              widget.quickSearchType != null
                  ? 'Try a different search term'
                  : widget.filterParams != null &&
                          widget.filterParams!.isNotEmpty
                      ? 'Try adjusting your search filters'
                      : 'Check back later for new profiles',
              style: TextStyle(color: Colors.grey),
            ),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xffFF0066),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                'Go Back',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: profiles.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.75, // Adjusted for better fit
      ),
      itemBuilder: (_, index) => _buildProfileCard(profiles[index]),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(1, 70, 0, 0),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xffFF0066), Color(0xffFF1500)],
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              height: 55,
              alignment: Alignment.center,
              padding: const EdgeInsets.only(right: 8),
              child: const Icon(Icons.arrow_back, color: Colors.white, size: 26),
            ),
          ),
          Expanded(
            child: Container(
              height: 55,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(40),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: "Search by profile id",
                        hintStyle: TextStyle(color: Colors.grey),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  Icon(Icons.search, color: Color(0xfffb5f6a)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),

          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const FilterPage()),
              );
            },
            child: Container(
              height: 55,
              width: 55,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
              ),
              child: const Icon(Icons.tune, color: Colors.black),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileCard(Map<String, dynamic> profile) {
    final firstName = "MS:${profile['id'] ?? ''}";
    final lastName = profile['lastName'] ?? '';
    final name = '$firstName $lastName'.trim();
    final age = profile['age']?.toString() ?? 'N/A';
    final height = profile['height_name']?.toString() ?? 'N/A';
    final education = profile['education']?.toString() ?? 'Not specified';
    final city = profile['city']?.toString() ?? 'Not specified';
    final profilePicture = profile['profile_picture']?.toString() ?? '';
    final userId = profile['id'] ?? 0;
    final isVerified = profile['isVerified'] == 1;
    final usertype = profile['usertype']?.toString() ?? '';

    final profession = profile['designation']?.toString() ?? education;

    final imageUrl = profilePicture.isNotEmpty
        ? profilePicture
        : 'https://images.pexels.com/photos/415829/pexels-photo-415829.jpeg';

    final isRequestSent = _isRequestSent(userId);

    // Check if photo should be blurred
    final shouldShowClearImage = _shouldShowClearImage(profile);
    final photoRequestStatus = _getPhotoRequestStatus(profile);

    return GestureDetector(
      onTap: () {
        // Check document status before navigation
        if (docstatus == 'approved') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ProfileLoader(userId: userId.toString(), myId: _currentUserId.toString(),),
            ),
          );
        } else {
          _handleDocumentNotApproved();
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 8,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // IMAGE SECTION with conditional blur
            Container(
              height: 130, // Reduced height
              width: double.infinity,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(18),
                ),
                child: _buildProfileImage(
                  imageUrl: imageUrl,
                  shouldShowClearImage: shouldShowClearImage,
                  photoRequestStatus: photoRequestStatus,
                  profile: profile,
                  isRequestSent: isRequestSent,
                  isVerified: isVerified,
                  usertype: usertype,
                  name: name,
                ),
              ),
            ),

            // CONTENT SECTION - Use Flexible instead of Expanded
            Flexible(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          height: 16,
                          child: _buildInfoRow(
                            icon: Icons.person_outline,
                            text: "Age $age yrs, $height",
                          ),
                        ),
                        const SizedBox(height: 4),

                        SizedBox(
                          height: 16,
                          child: _buildInfoRow(
                            icon: Icons.work_outline,
                            text: profession,
                          ),
                        ),
                        const SizedBox(height: 4),

                        SizedBox(
                          height: 16,
                          child: _buildInfoRow(
                            icon: Icons.location_on_outlined,
                            text: city,
                            iconColor: const Color(0xfffb5f6a),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),

                    // Button with GestureDetector to prevent bubbling

                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileImage({
    required String imageUrl,
    required bool shouldShowClearImage,
    required String photoRequestStatus,
    required Map<String, dynamic> profile,
    required bool isRequestSent,
    required bool isVerified,
    required String usertype,
    required String name,
  }) {
    if (shouldShowClearImage) {
      // Show clear image
      return Stack(
        fit: StackFit.expand,
        children: [
          // Clear Image
          Image.network(
            imageUrl,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Center(
                child: CircularProgressIndicator(
                  value: loadingProgress.expectedTotalBytes != null
                      ? loadingProgress.cumulativeBytesLoaded /
                      loadingProgress.expectedTotalBytes!
                      : null,
                  color: const Color(0xfffb5f6a),
                ),
              );
            },
            errorBuilder: (context, error, stackTrace) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.person,
                      size: 40,
                      color: Colors.grey,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      name.split(' ').first,
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),

          // Name overlay
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.8),
                  ],
                ),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(18),
                  bottomRight: Radius.circular(18),
                ),
              ),
              child: Text(
                name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),

          // Request sent indicator
          if (isRequestSent)
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 4,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check,
                      size: 12,
                      color: Colors.white,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'Sent',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Verification badge
          if (isVerified)
            Positioned(
              top: 8,
              right: isRequestSent ? 50 : 8,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.verified,
                  size: 14,
                  color: Colors.white,
                ),
              ),
            ),

          // Premium badge
          if (usertype == 'paid')
            Positioned(
              top: isRequestSent ? 35 : 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.amber[700],
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'PREMIUM',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
        ],
      );
    } else {
      // Show blurred image
      return Stack(
        fit: StackFit.expand,
        children: [
          // Blurred Image
          Stack(
            children: [
              // Original Image
              Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.person,
                          size: 40,
                          color: Colors.grey,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          name.split(' ').first,
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),

              // Blur Overlay
              Positioned.fill(
                child: Container(
                  color: Colors.black.withOpacity(0.3),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(
                      sigmaX: PrivacyUtils.kStandardBlurSigmaX,
                      sigmaY: PrivacyUtils.kStandardBlurSigmaY,
                    ),
                    child: Container(
                      color: Colors.black.withOpacity(0.1),
                    ),
                  ),
                ),
              ),

              // Lock icon overlay
              Positioned.fill(
                child: Center(
                  child: Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.red.withOpacity(0.8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 8,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.lock,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
              ),
            ],
          ),

          // Name overlay
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.8),
                  ],
                ),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(18),
                  bottomRight: Radius.circular(18),
                ),
              ),
              child: Text(
                name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),

          // Photo request status indicator
          Positioned(
            top: 8,
            left: 8,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.lock,
                    size: 12,
                    color: Colors.white,
                  ),
                  SizedBox(width: 4),
                  Text(
                    _getBlurIndicatorText(photoRequestStatus),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Verification badge
          if (isVerified)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.verified,
                  size: 14,
                  color: Colors.white,
                ),
              ),
            ),

          // Premium badge
          if (usertype == 'paid')
            Positioned(
              top: 35,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.amber[700],
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'PREMIUM',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
        ],
      );
    }
  }

  String _getBlurIndicatorText(String status) {
    switch (status) {
      case 'pending':
        return 'Pending';
      case 'rejected':
        return 'Rejected';
      case 'accepted':
        return 'Access';
      default:
        return 'Private';
    }
  }



  Widget _buildInfoRow({
    required IconData icon,
    required String text,
    Color iconColor = Colors.grey,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(
          icon,
          size: 12,
          color: iconColor,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 11,
              color: Colors.grey,
              height: 1.2,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}