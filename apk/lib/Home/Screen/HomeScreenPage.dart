import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:ms2026/Home/Screen/premiummember.dart';
import 'package:ms2026/Home/Screen/profilecard.dart';
import 'package:ms2026/Home/Screen/recent_members_page.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../Auth/Screen/signupscreen10.dart';
import '../../Auth/SuignupModel/signup_model.dart';
import '../../Chat/ChatdetailsScreen.dart';
import '../../Chat/ChatlistScreen.dart';
import '../../liked/liked.dart';
import '../../Models/masterdata.dart';
import 'package:http/http.dart' as http;
import 'package:ms2026/constant/app_colors.dart';
import 'package:ms2026/constant/app_dimensions.dart';
import 'package:ms2026/constant/app_text_styles.dart';
import 'package:ms2026/constant/status_bar_utils.dart';

import '../../Notification/notificationscreen.dart';
import '../../Notification/notification_inbox_service.dart';
import '../../Package/PackageScreen.dart';
import '../../Search/SearchPage.dart';
import '../../main.dart';
import '../../online/onlineservice.dart';
import '../../profile/myprofile.dart';
import '../../purposal/Purposalmodel.dart';
import '../../purposal/purposalScreen.dart';
import '../../purposal/purposalservice.dart';
import '../../purposal/requestcard.dart' show showUpgradeDialog;
import '../../service/Service_chat.dart';
import '../../service/verification_service.dart';
import '../../ReUsable/loading_widgets.dart';
import '../../utils/privacy_utils.dart';
import 'machprofilescreen.dart';
import 'package:ms2026/config/app_endpoints.dart';

// Cache data structure for better performance
class CachedData {
  final dynamic data;
  final DateTime timestamp;

  CachedData(this.data, this.timestamp);

  bool isExpired(Duration maxAge) {
    return DateTime.now().difference(timestamp) > maxAge;
  }
}

// Persistent cache keys for instant startup
const String _kMatchedProfilesCacheKey = 'home_matched_profiles_cache';
const String _kShortlistedCacheKey = 'home_shortlisted_cache';
const String _kCountsCacheKey = 'home_counts_cache';
const String _kRecentMembersCacheKey = 'home_recent_members_cache';

class MatrimonyHomeScreen extends StatefulWidget {
  const MatrimonyHomeScreen({super.key});

  @override
  State<MatrimonyHomeScreen> createState() => _MatrimonyHomeScreenState();
}

class _MatrimonyHomeScreenState extends State<MatrimonyHomeScreen> {
  static const String _apiBaseUrl = '${kApiBaseUrl}/Api2';
  static const String _placeholderProfileImage =
      'https://via.placeholder.com/150';
  static const Color _brandRed = AppColors.primary;

  List<dynamic> _matchedProfilesApi = [];
  bool _isLoading = true;
  String _errorMessage = '';
  List<Map<String, dynamic>> _premiumMembers = [];
  List<Map<String, dynamic>> _otherServices = [];
  List<MatchedUser> _photoRequestProfiles = [];
  List<ProposalModel> _chatRequestProfiles = [];
  bool _loading = true;
  bool _photoRequestsLoading = true;
  bool _chatRequestsLoading = true;
  int _proposalRequestCount = 0;
  int _favoriteRequestCount = 0;
  int _messageRequestCount = 0;

  List<dynamic> _shortlistedProfiles = [];
  bool _isLoadingShortlist = false;

  // Recent members state
  List<Map<String, dynamic>> _recentMembers = [];
  bool _recentMembersLoaded = false;
  bool _isLoadingRecentMembers = false;

  int userid = 0;
  String _userId = '';

  // Cache management
  Map<String, CachedData> _cache = {};

  // Lazy loading flags
  bool _premiumMembersLoaded = false;
  bool _otherServicesLoaded = false;

  // Notification count
  int _unreadNotificationCount = 0;

  // Pull-to-refresh shimmer flag
  bool _isRefreshing = false;

  // Silent background refresh flag (shown as thin progress bar at top)
  bool _isSilentRefreshing = false;

  Future<void> _refreshVerificationStatus() async {
    if (userid == 0) return;
    await VerificationService.instance.refresh(userid);
    if (mounted) setState(() {}); // rebuild so gated UI reflects new status
  }

  Future<void> _loadUnreadNotificationCount() async {
    try {
      final notifications = await NotificationInboxService.loadNotifications();
      final count = notifications.where((n) {
        final isRead = n['is_read'];
        return isRead == null || isRead == 0 || isRead == false;
      }).length;
      if (mounted) {
        setState(() => _unreadNotificationCount = count);
      }
    } catch (e) {
      debugPrint('Failed to load notification count: $e');
    }
  }

  Future<void> _refreshData() async {
    setState(() => _isRefreshing = true);
    // Clear cache so fresh data is fetched
    _cache.clear();
    try {
      await Future.wait([
        fetchMatchedProfiles(),
        _fetchQuickActionCounts(forceRefresh: true),
        _refreshVerificationStatus(),
        _fetchPremiumMembers(),
        _fetchOtherServices(),
        _fetchShortlistedProfiles(),
        _fetchRecentMembers(),
        _loadUnreadNotificationCount(),
      ]);
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  Future<void> fetchMatchedProfiles() async {
    // Check cache first
    final cacheKey = 'matched_profiles';
    if (_cache.containsKey(cacheKey) &&
        !_cache[cacheKey]!.isExpired(const Duration(minutes: 2))) {
      final cachedData = _cache[cacheKey]!.data as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _matchedProfilesApi = cachedData['raw'] as List<dynamic>;
        _photoRequestProfiles = cachedData['photo'] as List<MatchedUser>;
        _isLoading = false;
        _photoRequestsLoading = false;
      });
      return;
    }

    try {
      setState(() {
        if (_matchedProfilesApi.isEmpty) _isLoading = true;
        _photoRequestsLoading = true;
        _errorMessage = '';
      });

      // Get user ID from shared preferences
      final prefs = await SharedPreferences.getInstance();
      final userDataString = prefs.getString('user_data');
      if (userDataString == null) {
        throw Exception('User data not found');
      }

      final userData = jsonDecode(userDataString);
      final userId = userData["id"].toString();
      userid = int.tryParse(userData['id']?.toString() ?? '') ?? 0;


      // Make API call
      final url = Uri.parse('${kApiBaseUrl}/Api2/match.php?userid=$userId');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);

        if (result['success'] == true) {
          final rawProfiles = List<dynamic>.from(result['matched_users'] ?? []);
          final photoProfiles = rawProfiles
              .map((item) => MatchedUser.fromJson(Map<String, dynamic>.from(item)))
              .where((profile) {
            final status = profile.photoRequestStatus.toLowerCase();
            return status == 'accepted' || status == 'pending';
          }).toList()
            ..sort((a, b) => _requestStatusPriority(a.photoRequestStatus)
                .compareTo(_requestStatusPriority(b.photoRequestStatus)));

          // Cache the data
          _cache[cacheKey] = CachedData({
            'raw': rawProfiles,
            'photo': photoProfiles,
          }, DateTime.now());

          // Save to persistent cache for instant display on next launch
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(_kMatchedProfilesCacheKey,
                jsonEncode({'raw': rawProfiles}));
          } catch (e) {
            debugPrint('Error saving matched profiles to persistent cache: $e');
          }

          if (!mounted) return;
          setState(() {
            _matchedProfilesApi = rawProfiles;
            _photoRequestProfiles = photoProfiles;
            _isLoading = false;
            _photoRequestsLoading = false;
          });
        } else {
          throw Exception(result['message'] ?? 'Failed to load matched profiles');
        }
      } else {
        throw Exception('Failed to load data: ${response.statusCode}');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
        _photoRequestProfiles = [];
        _photoRequestsLoading = false;
      });
      debugPrint('Error fetching matched profiles: $e');
    }
  }

  Future<void> _fetchShortlistedProfiles() async {
    // Check cache first
    final cacheKey = 'shortlisted_profiles';
    if (_cache.containsKey(cacheKey) &&
        !_cache[cacheKey]!.isExpired(const Duration(minutes: 2))) {
      if (!mounted) return;
      setState(() {
        _shortlistedProfiles = _cache[cacheKey]!.data as List<dynamic>;
        _favoriteRequestCount = _shortlistedProfiles.length;
        _isLoadingShortlist = false;
      });
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataString = prefs.getString('user_data');
      if (userDataString == null) return;
      final userData = jsonDecode(userDataString);
      final userId = userData['id']?.toString() ?? '';
      if (userId.isEmpty) return;

      setState(() {
        if (_shortlistedProfiles.isEmpty) _isLoadingShortlist = true;
      });

      final url = Uri.https('digitallami.com', '/Api2/likelist.php', {'user_id': userId});
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'success') {
          final profiles = data['data'] ?? [];

          // Cache the data
          _cache[cacheKey] = CachedData(profiles, DateTime.now());

          // Save to persistent cache for instant display on next launch
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(
                _kShortlistedCacheKey, jsonEncode(profiles));
          } catch (e) {
            debugPrint('Error saving shortlisted profiles to persistent cache: $e');
          }

          if (!mounted) return;
          setState(() {
            _shortlistedProfiles = profiles;
            _favoriteRequestCount = profiles.length;
            _isLoadingShortlist = false;
          });
        } else {
          if (!mounted) return;
          setState(() => _isLoadingShortlist = false);
        }
      } else {
        if (!mounted) return;
        setState(() => _isLoadingShortlist = false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingShortlist = false);
      debugPrint('Error fetching shortlisted profiles: $e');
    }
  }

  Future<void> _fetchQuickActionCounts({bool forceRefresh = false}) async {
    const cacheKey = 'quick_action_counts';

    if (!forceRefresh &&
        _cache.containsKey(cacheKey) &&
        !_cache[cacheKey]!.isExpired(const Duration(minutes: 2))) {
      final cachedData = _cache[cacheKey]!.data as Map<String, int>;
      if (!mounted) return;
      setState(() {
        _proposalRequestCount = cachedData['proposal'] ?? 0;
        _messageRequestCount = cachedData['message'] ?? 0;
      });
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataString = prefs.getString('user_data');
      if (userDataString == null) return;

      final userData = jsonDecode(userDataString);
      final currentUserId = userData['id']?.toString() ?? '';
      if (currentUserId.isEmpty) return;

      final receivedRequests =
          await ProposalService.fetchProposals(currentUserId, 'received');
      final proposalRequestCount = receivedRequests
          .where((proposal) =>
              proposal.requestType?.toLowerCase() != 'chat' &&
              proposal.status?.toLowerCase() == 'pending')
          .length;
      final messageRequestCount = receivedRequests
          .where((proposal) =>
              proposal.requestType?.toLowerCase() == 'chat' &&
              proposal.status?.toLowerCase() == 'pending')
          .length;

      final counts = {
        'proposal': proposalRequestCount,
        'message': messageRequestCount,
      };

      _cache[cacheKey] = CachedData(counts, DateTime.now());

      // Save to persistent cache for instant display on next launch
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_kCountsCacheKey, jsonEncode(counts));
      } catch (e) {
        debugPrint('Error saving counts to persistent cache: $e');
      }

      if (!mounted) return;
      setState(() {
        _proposalRequestCount = counts['proposal'] ?? 0;
        _messageRequestCount = counts['message'] ?? 0;
      });
    } catch (e) {
      debugPrint('Error fetching quick action counts: $e');
    }
  }

  Future<void> _fetchPremiumMembers() async {
    // Check cache first
    final cacheKey = 'premium_members';
    if (_cache.containsKey(cacheKey) &&
        !_cache[cacheKey]!.isExpired(const Duration(minutes: 2))) {
      if (!mounted) return;
      setState(() {
        _premiumMembers = _cache[cacheKey]!.data as List<Map<String, dynamic>>;
        _isLoading = false;
        _premiumMembersLoaded = true;
      });
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final userDataString = prefs.getString('user_data');
    if (userDataString == null) return;
    final userData = jsonDecode(userDataString);
    final userid = userData["id"];

    try {
      final url = Uri.parse('${kApiBaseUrl}/Api2/premiuimmember.php?user_id=${userid}');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);

        if (data['success'] == true && data['data'] != null) {
          final List members = data['data'];

          final membersList = members.map<Map<String, dynamic>>((member) {
            // Construct full profile picture URL
            final rawImage = member['profile_picture'] ?? '';
            final imageUrl = rawImage.startsWith('http')
                ? rawImage
                : '${kApiBaseUrl}/Api2/$rawImage';

            return {
              'firstName': member['firstName'] ?? '',
              'lastName': member['lastName'] ?? '',
              'age': member['age'] ?? '',
              'city': member['city'] ?? '',
              'image': imageUrl,
              'isVerified': member['isVerified'] ?? '0',
              'id': member['id'],
              'privacy': member['privacy']?.toString().toLowerCase() ?? '',
              'photo_request': member['photo_request']?.toString().toLowerCase() ?? '',
              'can_view_photo': PrivacyUtils.canViewPhotoFromJson(member),
            };
            _isLoading = false;
            _premiumMembersLoaded = true;
          });
        } else {
          if (!mounted) return;
          setState(() {
            _isLoading = false;
            _premiumMembersLoaded = true;
          });
        }
      } else {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _premiumMembersLoaded = true;
        });
        debugPrint('Error fetching premium members: ${response.statusCode}');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _premiumMembersLoaded = true;
      });
      debugPrint('Exception: $e');
    }
  }


  Future<void> _fetchRecentMembers() async {
    // Check cache first
    final cacheKey = 'recent_members';
    if (_cache.containsKey(cacheKey) &&
        !_cache[cacheKey]!.isExpired(const Duration(minutes: 2))) {
      if (!mounted) return;
      setState(() {
        _recentMembers = _cache[cacheKey]!.data as List<Map<String, dynamic>>;
        _isLoadingRecentMembers = false;
        _recentMembersLoaded = true;
      });
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final userDataString = prefs.getString('user_data');
    if (userDataString == null) return;
    final userData = jsonDecode(userDataString);
    final userid = userData["id"];
    final userCreatedDate = userData["created_at"] ?? "";

    try {
      // Use search_opposite_gender API with sort by recent registration
      final url = Uri.parse('${kApiBaseUrl}/Api2/search_opposite_gender.php?user_id=$userid&sort_by=recent&limit=10');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);

        if (data['success'] == true && data['data'] != null) {
          final List members = data['data'];

          // Filter members registered after current user
          final membersList = members.where((member) {
            final memberCreatedDate = member['created_at'] ?? '';
            if (memberCreatedDate.isEmpty || userCreatedDate.isEmpty) return true;

            try {
              final memberDate = DateTime.parse(memberCreatedDate);
              final userDate = DateTime.parse(userCreatedDate);
              return memberDate.isAfter(userDate);
            } catch (e) {
              return true; // Include if date parsing fails
            }
          }).map<Map<String, dynamic>>((member) {
            // Construct full profile picture URL
            final rawImage = member['profile_picture'] ?? '';
            final imageUrl = rawImage.startsWith('http')
                ? rawImage
                : '${kApiBaseUrl}/Api2/$rawImage';

            return {
              'userId': member['userid'] ?? member['id'],
              'memberid': member['memberid'] ?? 'N/A',
              'firstName': member['firstName'] ?? '',
              'lastName': member['lastName'] ?? '',
              'age': member['age'] ?? '',
              'city': member['city'] ?? '',
              'country': member['country'] ?? '',
              'heightName': member['height_name'] ?? '',
              'designation': member['designation'] ?? '',
              'image': imageUrl,
              'isVerified': member['isVerified'] ?? '0',
              'id': member['id'],
              'privacy': member['privacy']?.toString().toLowerCase() ?? '',
              'photo_request': member['photo_request']?.toString().toLowerCase() ?? '',
              'can_view_photo': PrivacyUtils.canViewPhotoFromJson(member),
              'created_at': member['created_at'] ?? '',
            };
          }).toList();

          // Cache the data
          _cache[cacheKey] = CachedData(membersList, DateTime.now());

          // Save to persistent cache for instant display on next launch
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(_kRecentMembersCacheKey, jsonEncode(membersList));
          } catch (e) {
            debugPrint('Error saving recent members to persistent cache ($_kRecentMembersCacheKey): $e');
          }

          if (!mounted) return;
          setState(() {
            _recentMembers = membersList;
            _isLoadingRecentMembers = false;
            _recentMembersLoaded = true;
          });
        } else {
          if (!mounted) return;
          setState(() {
            _isLoadingRecentMembers = false;
            _recentMembersLoaded = true;
          });
        }
      } else {
        if (!mounted) return;
        setState(() {
          _isLoadingRecentMembers = false;
          _recentMembersLoaded = true;
        });
        debugPrint('Error fetching recent members: ${response.statusCode}');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingRecentMembers = false;
        _recentMembersLoaded = true;
      });
      debugPrint('Exception fetching recent members: $e');
    }
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
  Future<void> _fetchOtherServices() async {
    // Check cache first
    final cacheKey = 'other_services';
    if (_cache.containsKey(cacheKey) &&
        !_cache[cacheKey]!.isExpired(const Duration(minutes: 2))) {
      if (!mounted) return;
      setState(() {
        _otherServices = _cache[cacheKey]!.data as List<Map<String, dynamic>>;
        _loading = false;
        _otherServicesLoaded = true;
      });
      return;
    }

    try {
      final url = Uri.parse('${kApiBaseUrl}/Api2/services_api.php');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);

        if (data['success'] == true && data['data'] != null) {
          final List services = data['data'];

          final servicesList = services.map<Map<String, dynamic>>((service) {
            // Build full image URL
            final rawImage = service['profile_picture'] ?? '';
            final imageUrl = rawImage.startsWith('http')
                ? rawImage
                : '${kApiBaseUrl}/$rawImage';

            return {
              'category': service['servicetype'] ?? '',
              'name': '${service['firstname'] ?? ''} ${service['lastname'] ?? ''}',
              'age': service['age']?.toString() ?? '',
              'location': service['city'] ?? '',
              'experience': service['experience'] ?? '',
              'image': imageUrl,
              'id': service['id'],
            };
          }).toList();

          // Cache the data
          _cache[cacheKey] = CachedData(servicesList, DateTime.now());

          if (!mounted) return;
          setState(() {
            _otherServices = servicesList;
            _loading = false;
            _otherServicesLoaded = true;
          });
        } else {
          if (!mounted) return;
          setState(() {
            _loading = false;
            _otherServicesLoaded = true;
          });
        }
      } else {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _otherServicesLoaded = true;
        });
        debugPrint('Error fetching services: ${response.statusCode}');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _otherServicesLoaded = true;
      });
      debugPrint('Exception: $e');
    }
  }

  Future<void> _fetchChatRequestProfiles() async {
    try {
      setState(() {
        _chatRequestsLoading = true;
      });

      final prefs = await SharedPreferences.getInstance();
      final userDataString = prefs.getString('user_data');
      if (userDataString == null) {
        if (!mounted) return;
        setState(() {
          _chatRequestProfiles = [];
          _chatRequestsLoading = false;
        });
        return;
      }

      final userData = jsonDecode(userDataString);
      final currentUserId = userData['id'].toString();

      final results = await Future.wait([
        ProposalService.fetchProposals(currentUserId, 'sent'),
        ProposalService.fetchProposals(currentUserId, 'accepted'),
      ]);

      if (!mounted) return;
      setState(() {
        _chatRequestProfiles = _mergeChatRequests(
          currentUserId: currentUserId,
          sentRequests: results[0],
          acceptedRequests: results[1],
        );
        _chatRequestsLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching chat request profiles: $e');
      if (!mounted) return;
      setState(() {
        _chatRequestProfiles = [];
        _chatRequestsLoading = false;
      });
    }
  }






String usertye = '';
  String userimage = '';
  var  pageno;
  String name = '';

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  void loadMasterData() async {
    final prefs = await SharedPreferences.getInstance();
    final userDataString = prefs.getString('user_data');
    if (userDataString == null) return;
    final userData = jsonDecode(userDataString);
    final userId = int.tryParse(userData["id"].toString());

    // Pre-populate AppBar immediately from cached user_data so the UI renders
    // instantly without waiting for the masterdata API response.
    if (mounted) {
      setState(() {
        name = '${userData['firstName'] ?? ''} ${userData['lastName'] ?? ''}'.trim();
        userimage = userData['profile_picture'] ?? userData['profilePicture'] ?? '';
        usertye = userData['usertype'] ?? '';
        _userId = userId?.toString() ?? '';
        userid = userId ?? 0;
      });
    }

    // Load cached verification status immediately, then refresh from network.
    if (userId != null) {
      await VerificationService.instance.loadFromCache();
      VerificationService.instance.refresh(userId);
    }

    try {
      UserMasterData user = await fetchUserMasterData(userId.toString());

      debugPrint("Name: ${user.firstName} ${user.lastName}");
      debugPrint("Usertype: ${user.usertype}");
      debugPrint("Page No: ${user.pageno}");
      debugPrint("Profile: ${user.profilePicture}");
      if (!mounted) return;
      setState(() {
        usertye = user.usertype;
        userimage = user.profilePicture;
        pageno = user.pageno;
        name = "${user.firstName} ${user.lastName}";
        _userId = userId?.toString() ?? '';
        userid = userId ?? 0;
      });
    } catch (e) {
      debugPrint("Error: $e");
    }
  }

  @override
  void initState() {
    super.initState();
    _loadPersistentCacheThenRefresh();
    loadMasterData();
    _loadUnreadNotificationCount();
    OnlineStatusService().start();
  }

  /// Loads cached data from SharedPreferences for instant display, then
  /// silently refreshes from the network in the background.
  Future<void> _loadPersistentCacheThenRefresh() async {
    await _loadPersistentCache();
    if (!mounted) return;
    setState(() => _isSilentRefreshing = true);
    try {
      // Use eagerError: false so one failing call doesn't block the others
      await Future.wait([
        fetchMatchedProfiles(),
        _fetchQuickActionCounts(),
        _fetchShortlistedProfiles(),
        _fetchPremiumMembers(),
        _fetchRecentMembers(),
        _fetchOtherServices(),
      ], eagerError: false);
    } catch (e) {
      debugPrint('Error during silent background refresh: $e');
    } finally {
      if (mounted) setState(() => _isSilentRefreshing = false);
    }
  }

  /// Reads matched profiles, shortlisted profiles, and counts from
  /// SharedPreferences and updates state immediately (no network call).
  Future<void> _loadPersistentCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Load matched profiles
      final matchedJson = prefs.getString(_kMatchedProfilesCacheKey);
      if (matchedJson != null) {
        try {
          final decoded = jsonDecode(matchedJson);
          if (decoded is Map<String, dynamic>) {
            final rawList = decoded['raw'];
            final rawProfiles = rawList is List ? List<dynamic>.from(rawList) : <dynamic>[];
            final photoProfiles = rawProfiles
                .whereType<Map>()
                .map((item) {
                  try {
                    return MatchedUser.fromJson(Map<String, dynamic>.from(item));
                  } catch (_) {
                    return null;
                  }
                })
                .whereType<MatchedUser>()
                .where((profile) {
                  final status = profile.photoRequestStatus.toLowerCase();
                  return status == 'accepted' || status == 'pending';
                })
                .toList()
              ..sort((a, b) => _requestStatusPriority(a.photoRequestStatus)
                  .compareTo(_requestStatusPriority(b.photoRequestStatus)));
            if (mounted) {
              setState(() {
                _matchedProfilesApi = rawProfiles;
                _photoRequestProfiles = photoProfiles;
                _isLoading = false;
                _photoRequestsLoading = false;
              });
            }
          }
        } catch (e) {
          debugPrint('Error parsing matched profiles cache: $e');
        }
      }

      // Load shortlisted profiles
      final shortlistedJson = prefs.getString(_kShortlistedCacheKey);
      if (shortlistedJson != null) {
        try {
          final decoded = jsonDecode(shortlistedJson);
          if (decoded is List) {
            final profiles = List<dynamic>.from(decoded);
            if (mounted) {
              setState(() {
                _shortlistedProfiles = profiles;
                _favoriteRequestCount = profiles.length;
                _isLoadingShortlist = false;
              });
            }
          }
        } catch (e) {
          debugPrint('Error parsing shortlisted profiles cache: $e');
        }
      }

      // Load counts
      final countsJson = prefs.getString(_kCountsCacheKey);
      if (countsJson != null) {
        try {
          final decoded = jsonDecode(countsJson);
          if (decoded is Map<String, dynamic>) {
            if (mounted) {
              setState(() {
                _proposalRequestCount = (decoded['proposal'] as num?)?.toInt() ?? 0;
                _messageRequestCount = (decoded['message'] as num?)?.toInt() ?? 0;
              });
            }
          }
        } catch (e) {
          debugPrint('Error parsing counts cache: $e');
        }
      }

      // Load recent members
      final recentJson = prefs.getString(_kRecentMembersCacheKey);
      if (recentJson != null) {
        try {
          final decoded = jsonDecode(recentJson);
          if (decoded is List) {
            final members = List<Map<String, dynamic>>.from(
                decoded.whereType<Map<dynamic, dynamic>>().map((e) => Map<String, dynamic>.from(e)));
            if (mounted && members.isNotEmpty) {
              setState(() {
                _recentMembers = members;
                _recentMembersLoaded = true;
                _isLoadingRecentMembers = false;
              });
            }
          }
        } catch (e) {
          debugPrint('Error parsing recent members cache: $e');
        }
      }
    } catch (e) {
      debugPrint('Error loading persistent cache: $e');
    }
  }

  @override
  void dispose() {
    // Clean up resources
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    return Consumer<SignupModel>(
      builder: (context, model, child) {
        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: _buildAppBar(),
          body: Stack(
            children: [
              RefreshIndicator(
            color: AppColors.primary,
            onRefresh: _refreshData,
            child: ShimmerLoading(
              isLoading: _isRefreshing,
              child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppSpacing.verticalSM,
                  if (pageno != 10)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _buildProfileCompletenessCard(),
                    ),
                  AppSpacing.verticalMD,
                  // Recent Members Section
                  VisibilityDetector(
                    key: const Key('recent-members-section'),
                    onVisibilityChanged: (info) {
                      // Load data when section becomes visible (>10% visible)
                      if (info.visibleFraction > 0.1 && !_recentMembersLoaded) {
                        _fetchRecentMembers();
                      }
                    },
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: GestureDetector(
                            onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) =>
                                        RecentMembersPage(userId: userid))),
                            child: _buildSectionHeader('Recently Registered',
                                showSeeAll: true),
                          ),
                        ),
                        AppSpacing.verticalSM,
                        _buildRecentMembers(),
                      ],
                    ),
                  ),
                  AppSpacing.verticalMD,
                  _buildStatsBanner(),
                  AppSpacing.verticalMD,
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _buildSectionHeader('Quick Actions', showSeeAll: false),
                  ),
                  AppSpacing.verticalSM,
                  _buildQuickActions(),
                  AppSpacing.verticalLG,
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _buildSectionHeader('Suggested Profiles', showSeeAll: false),
                  ),
                  AppSpacing.verticalSM,
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      height: MediaQuery.of(context).size.height * 0.63,
                      decoration: BoxDecoration(
                        borderRadius: AppDimensions.borderRadiusXL,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.black.withOpacity(0.06),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: AppDimensions.borderRadiusXL,
                        child: ProfileSwipeUI(
                          userId: userid,
                          matchApiUrl: '${kApiBaseUrl}/Api2/match.php',
                          baseUrl: '${kApiBaseUrl}/Api2',
                          sendRequestApiUrl: '${kApiBaseUrl}/Api2/send_request.php',
                          likeApiUrl: '${kApiBaseUrl}/Api2/like_action.php',
                        ),
                      ),
                    ),
                  ),
                  AppSpacing.verticalLG,
                  VisibilityDetector(
                    key: const Key('premium-members-section'),
                    onVisibilityChanged: (info) {
                      // Load data when section becomes visible (>10% visible)
                      if (info.visibleFraction > 0.1 && !_premiumMembersLoaded) {
                        _fetchPremiumMembers();
                      }
                    },
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: GestureDetector(
                            onTap: () => Navigator.push(context,
                                MaterialPageRoute(builder: (_) => PaidUsersListPage(userId: userid))),
                            child: _buildSectionHeader('Premium Members', showSeeAll: true),
                          ),
                        ),
                        AppSpacing.verticalSM,
                        _buildPremiumMembers(),
                      ],
                    ),
                  ),
                  AppSpacing.verticalLG,
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: GestureDetector(
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => MatchedProfilesPagee(
                            currentUserId: userid, docstatus: VerificationService.instance.identityStatus))),
                      child: _buildSectionHeader('Matched Profiles', showSeeAll: true),
                    ),
                  ),
                  AppSpacing.verticalSM,
                  _buildMatchedProfilesFromApi(),
                  AppSpacing.verticalLG,
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: GestureDetector(
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => FavoritePeoplePage())),
                      child: _buildSectionHeader('Shortlisted Profiles', showSeeAll: true),
                    ),
                  ),
                  AppSpacing.verticalSM,
                  _buildShortlistedProfiles(),
                  AppSpacing.verticalLG,
                  VisibilityDetector(
                    key: const Key('other-services-section'),
                    onVisibilityChanged: (info) {
                      // Load data when section becomes visible (>10% visible)
                      if (info.visibleFraction > 0.1 && !_otherServicesLoaded) {
                        _fetchOtherServices();
                      }
                    },
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: _buildSectionHeader('Other Services', showSeeAll: false),
                        ),
                        AppSpacing.verticalSM,
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: _buildOtherServices(),
                        ),
                      ],
                    ),
                  ),
                  AppSpacing.verticalXL,
                ],
              ),
            ),
          ),
          ),
              // Thin progress indicator at top during silent background refresh
              if (_isSilentRefreshing)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: LinearProgressIndicator(
                    color: AppColors.primary,
                    backgroundColor: AppColors.primary.withOpacity(0.12),
                    minHeight: 2,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      automaticallyImplyLeading: false,
      backgroundColor: AppColors.white,
      surfaceTintColor: AppColors.white,
      elevation: 0,
      shadowColor: Colors.transparent,
      scrolledUnderElevation: 0,
      titleSpacing: 16,
      systemOverlayStyle: setStatusBar(Colors.transparent, Brightness.dark),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(
          height: 1,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.primary, Color(0xFFFF6B6B), Color(0xFFFFE0E0)],
              stops: [0.0, 0.4, 1.0],
            ),
          ),
        ),
      ),
      title: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => MatrimonyProfilePage()),
        ),
        behavior: HitTestBehavior.opaque,
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: (usertye.isNotEmpty && usertye != 'free')
                      ? const [Color(0xFFFFD700), Color(0xFFFF8C00)]
                      : [AppColors.primary, AppColors.primaryDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: ((usertye.isNotEmpty && usertye != 'free')
                            ? const Color(0xFFFFD700)
                            : AppColors.primary)
                        .withOpacity(0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: CircleAvatar(
                radius: 22,
                backgroundColor: AppColors.white,
                child: CircleAvatar(
                  radius: 20,
                  backgroundImage: userimage.isNotEmpty
                      ? NetworkImage('${kApiBaseUrl}/Api2/$userimage')
                      : null,
                  onBackgroundImageError:
                      userimage.isNotEmpty ? (_, __) {} : null,
                  child: userimage.isEmpty
                      ? const Icon(Icons.person_rounded,
                          color: AppColors.textHint, size: 22)
                      : null,
                ),
              ),
            ),
            AppSpacing.horizontalSM,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_getGreeting()}! 👋',
                    style: AppTextStyles.captionSmall.copyWith(
                      fontSize: 11,
                      color: AppColors.textHint,
                    ),
                  ),
                  Text(
                    name.isNotEmpty ? name : 'Welcome',
                    style: AppTextStyles.labelLarge.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Row(
                    children: [
                      if (_userId.isNotEmpty) ...[
                        Text(
                          'MS: $_userId',
                          style: AppTextStyles.primaryLabel.copyWith(fontSize: 11),
                        ),
                        AppSpacing.horizontalXS,
                      ],
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: AppColors.success,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (usertye == 'free')
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 6),
              child: GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => SubscriptionPage()),
                ).then((_) { if (mounted) loadMasterData(); }),
                child: Container(
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 11),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF8C00), Color(0xFFFFB800)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(17),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFF8C00).withOpacity(0.35),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.star_rounded, color: Colors.white, size: 14),
                      SizedBox(width: 4),
                      Text(
                        'Upgrade',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                          height: 1.0,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          )
        else if (usertye.isNotEmpty && usertye != 'free')
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Container(
                height: 30,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFD700), Color(0xFFFF8C00)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFFD700).withOpacity(0.35),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 14),
                    SizedBox(width: 4),
                    Text(
                      'Premium',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                        height: 1.0,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        _buildAppBarIcon(
          icon: Icons.search_rounded,
          onPressed: () {
            if (VerificationService.instance.isVerified) {
              Navigator.push(context, MaterialPageRoute(builder: (_) => SearchPage()));
            } else {
              VerificationService.requireVerification(context);
            }
          },
        ),
        AppSpacing.horizontalXS,
        _buildNotificationBell(),
        AppSpacing.horizontalMD,
      ],
    );
  }

  Widget _buildAppBarIcon({required IconData icon, required VoidCallback onPressed}) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.08),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        padding: EdgeInsets.zero,
        icon: Icon(icon, color: AppColors.primary, size: 20),
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildNotificationBell() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        _buildAppBarIcon(
          icon: Icons.notifications_rounded,
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MatrimonyNotificationPage()),
          ).then((_) => _loadUnreadNotificationCount()),
        ),
        if (_unreadNotificationCount > 0)
          Positioned(
            right: 0,
            top: 0,
            child: Container(
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: Text(
                _unreadNotificationCount > 99
                    ? '99+'
                    : '$_unreadNotificationCount',
                style: AppTextStyles.captionSmall.copyWith(
                  color: AppColors.white,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildProfileCompletenessCard() {
    final double progress = (pageno != null ? (pageno * 10) / 100.0 : 0.0).clamp(0.0, 1.0);
    final int percent = (progress * 100).round();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, Color(0xFFD81B60)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: AppDimensions.borderRadiusXL,
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.35),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Complete Your Profile',
                  style: AppTextStyles.heading4.copyWith(
                    color: AppColors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                    letterSpacing: -0.3,
                  ),
                ),
                AppSpacing.verticalXS,
                Text(
                  'More complete = better matches',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.white.withOpacity(0.7),
                  ),
                ),
                AppSpacing.verticalSM,
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: AppDimensions.borderRadiusMD,
                        child: LinearProgressIndicator(
                          value: progress,
                          backgroundColor: AppColors.white.withOpacity(0.25),
                          valueColor: const AlwaysStoppedAnimation<Color>(AppColors.white),
                          minHeight: 8,
                        ),
                      ),
                    ),
                    AppSpacing.horizontalSM,
                    Text(
                      '$percent%',
                      style: AppTextStyles.labelLarge.copyWith(
                        color: AppColors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
                AppSpacing.verticalSM,
                GestureDetector(
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => IDVerificationScreen())),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: AppDimensions.borderRadiusRound,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Continue',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        AppSpacing.horizontalXS,
                        const Icon(Icons.arrow_forward_rounded,
                            color: AppColors.primary, size: 14),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          AppSpacing.horizontalMD,
          Column(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Icon(
                    Icons.favorite_rounded,
                    color: AppColors.white,
                    size: 34,
                  ),
                ),
              ),
              AppSpacing.verticalSM,
              Icon(
                Icons.diamond_outlined,
                color: AppColors.white.withOpacity(0.7),
                size: 28,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatsBanner() {
    final int matchCount = _matchedProfilesApi.length;
    final int premiumCount = _premiumMembers.length;
    final int profilePercent = ((pageno ?? 0) * 10).clamp(0, 100);
    final int servicesCount = _otherServices.length;

    final stats = [
      {'icon': Icons.favorite_rounded, 'value': '$matchCount', 'label': 'Matches', 'color': AppColors.primary},
      {'icon': Icons.star_rounded, 'value': '$premiumCount', 'label': 'Premium', 'color': const Color(0xFFFFA000)},
      {'icon': Icons.person_rounded, 'value': '$profilePercent%', 'label': 'Profile', 'color': const Color(0xFF2196F3)},
      {'icon': Icons.handshake_rounded, 'value': '$servicesCount', 'label': 'Services', 'color': const Color(0xFF00897B)},
    ];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: AppDimensions.borderRadiusXL,
        boxShadow: [
          BoxShadow(
            color: AppColors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: stats.map((stat) {
          final color = stat['color'] as Color;
          return Column(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(stat['icon'] as IconData, color: color, size: 22),
              ),
              AppSpacing.verticalSM,
              Text(
                stat['value'] as String,
                style: AppTextStyles.labelLarge.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: color,
                  letterSpacing: -0.3,
                ),
              ),
              AppSpacing.verticalXS,
              Text(
                stat['label'] as String,
                style: AppTextStyles.labelSmall.copyWith(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildQuickActions() {
    final actions = [
      {
        'icon': Icons.search_rounded,
        'label': 'Search',
        'gradient': [const Color(0xFF6C63FF), const Color(0xFF4834D4)],
        'onTap': () {
          if (VerificationService.instance.isVerified) {
            Navigator.push(context, MaterialPageRoute(builder: (_) => SearchPage()));
          } else {
            VerificationService.requireVerification(context);
          }
        },
      },
      {
        'icon': Icons.send_rounded,
        'label': 'Proposals',
        'count': _proposalRequestCount,
        'gradient': [AppColors.primary, AppColors.primaryDark],
        'onTap': () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => ProposalsPage())),
      },
      {
        'icon': Icons.favorite_rounded,
        'label': 'Favorites',
        'count': _favoriteRequestCount,
        'gradient': [const Color(0xFFE91E63), const Color(0xFFC2185B)],
        'onTap': () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => FavoritePeoplePage())),
      },
      {
        'icon': Icons.chat_bubble_rounded,
        'label': 'Messages',
        'count': _messageRequestCount,
        'gradient': [const Color(0xFF2196F3), const Color(0xFF1565C0)],
        'onTap': () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => ChatListScreen())),
      },
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: actions.map((action) {
          final gradient = action['gradient'] as List<Color>;
          final onTap = action['onTap'] as VoidCallback;

          return Expanded(
            child: GestureDetector(
              onTap: onTap,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: gradient,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: AppDimensions.borderRadiusLG,
                  boxShadow: [
                    BoxShadow(
                      color: gradient[0].withOpacity(0.38),
                      blurRadius: 18,
                      spreadRadius: 0,
                      offset: const Offset(0, 6),
                    ),
                    BoxShadow(
                      color: gradient.last.withOpacity(0.18),
                      blurRadius: 8,
                      spreadRadius: -2,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: AppColors.white.withOpacity(0.22),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.white.withOpacity(0.35),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.black.withOpacity(0.12),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Icon(
                            action['icon'] as IconData,
                            color: AppColors.white,
                            size: 28,
                          ),
                        ),
                        if ((action['count'] as int? ?? 0) > 0)
                          Positioned(
                            top: -5,
                            right: -5,
                            child: Container(
                              constraints: const BoxConstraints(
                                  minWidth: 18, minHeight: 18),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 1),
                              decoration: const BoxDecoration(
                                color: AppColors.white,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                (action['count'] as int) > 99
                                    ? '99+'
                                    : '${action['count']}',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: gradient[0],
                                  height: 1.0,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      action['label'] as String,
                      style: AppTextStyles.captionSmall.copyWith(
                        color: AppColors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildMatchedProfilesFromApi() {
    if (_isLoading && _matchedProfilesApi.isEmpty) {
      return const ProfileCardListSkeleton(count: 3, height: 270);
    }

    if (_errorMessage.isNotEmpty) {
      return SizedBox(
        height: 260,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded,
                  color: Colors.red.shade300, size: 40),
              AppSpacing.verticalSM,
              Text('Failed to load profiles',
                  style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
              AppSpacing.verticalSM,
              TextButton(
                onPressed: fetchMatchedProfiles,
                child: Text('Retry', style: AppTextStyles.primaryLabel),
              ),
            ],
          ),
        ),
      );
    }

    if (_matchedProfilesApi.isEmpty) {
      return SizedBox(
        height: 260,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.favorite_border_rounded,
                  size: 48, color: AppColors.border),
              AppSpacing.verticalSM,
              Text('No matched profiles found',
                  style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textHint)),
            ],
          ),
        ),
      );
    }

    return SizedBox(
      height: 270,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _matchedProfilesApi.length,
        padding: const EdgeInsets.only(left: 16, right: 8),
        itemBuilder: (context, index) {
          final profile = _matchedProfilesApi[index];
          final userId = profile['userid']?.toString() ?? '';
          final lastName = profile['lastName'] ?? '';
          final displayName = userId.isNotEmpty
              ? '$userId $lastName'.trim()
              : lastName.isNotEmpty ? lastName : 'User';
          final age = profile['age']?.toString() ?? '';
          final height = profile['height_name'] ?? '';
          final profession = profile['designation'] ?? '';
          final city = profile['city'] ?? '';
          final country = profile['country'] ?? '';
          final location =
              '$city${city.isNotEmpty && country.isNotEmpty ? ', ' : ''}$country';
          final profilePicture = profile['profile_picture'] ?? '';
          final imageUrl = profilePicture.isNotEmpty
              ? '${kApiBaseUrl}/Api2/$profilePicture'
              : '';
          final matchPercent = profile['matchPercent'];
          final isVerified = profile['isVerified'] == 1;
          final matchedPrivacy = profile['privacy']?.toString().toLowerCase() ?? '';
          final matchedPhotoRequest = profile['photo_request']?.toString().toLowerCase() ?? '';
          final matchedShowClear = profile['can_view_photo'] == true;

          Color matchColor = AppColors.success;
          if (matchPercent != null) {
            matchColor = matchPercent >= 80
                ? AppColors.success
                : matchPercent >= 50
                    ? AppColors.warning
                    : AppColors.primary;
          }

          Widget matchedProfileImg = imageUrl.isNotEmpty
              ? Image.network(
                  imageUrl,
                  width: double.infinity,
                  height: 155,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    height: 155,
                    color: AppColors.background,
                    child: const Center(
                      child: Icon(Icons.person_rounded,
                          size: 60, color: AppColors.textHint),
                    ),
                  ),
                )
              : Container(
                  height: 155,
                  color: AppColors.background,
                  child: const Center(
                    child: Icon(Icons.person_rounded,
                        size: 60, color: AppColors.textHint),
                  ),
                );
          if (imageUrl.isNotEmpty && !matchedShowClear) {
            matchedProfileImg = ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: matchedProfileImg,
            );
          }

          return GestureDetector(
            onTap: () {
              final profileUserId = profile['userid'];
              if (profileUserId != null) {
                if (VerificationService.requireVerification(context)) {
                  Navigator.push(context, MaterialPageRoute(
                      builder: (_) => ProfileLoader(
                          userId: profileUserId.toString(),
                          myId: userid.toString())));
                }
              }
            },
            child: Container(
              width: 190,
              margin: const EdgeInsets.only(right: 14),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: AppDimensions.borderRadiusXL,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.black.withOpacity(0.07),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(20)),
                        child: Stack(
                          children: [
                            matchedProfileImg,
                            Positioned(
                              bottom: 0,
                              left: 0,
                              right: 0,
                              child: Container(
                                height: 50,
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.transparent,
                                      Colors.black54
                                    ],
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              bottom: 6,
                              left: 10,
                              right: 10,
                              child: Text(
                                'MS $displayName',
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: AppColors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  shadows: [
                                    Shadow(
                                        color: Colors.black45,
                                        blurRadius: 4)
                                  ],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isVerified)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            width: 26,
                            height: 26,
                            decoration: const BoxDecoration(
                              color: AppColors.white,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.verified_rounded,
                                color: Color(0xFF2196F3), size: 16),
                          ),
                        ),
                      if (matchPercent != null)
                        Positioned(
                          top: 8,
                          left: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: matchColor,
                              borderRadius: AppDimensions.borderRadiusMD,
                            ),
                            child: Text(
                              '$matchPercent%',
                              style: AppTextStyles.captionSmall.copyWith(
                                color: AppColors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (age.isNotEmpty || height.isNotEmpty)
                                Text(
                                  '${age.isNotEmpty ? '$age yrs' : ''}${age.isNotEmpty && height.isNotEmpty ? ', ' : ''}$height',
                                  style: AppTextStyles.captionSmall.copyWith(
                                    fontSize: 11,
                                    color: AppColors.textSecondary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              if (profession.isNotEmpty) ...[
                                AppSpacing.verticalXS,
                                Row(
                                  children: [
                                    Icon(Icons.work_outline_rounded,
                                        size: 11,
                                        color: AppColors.textHint),
                                    AppSpacing.horizontalXS,
                                    Expanded(
                                      child: Text(
                                        profession,
                                        style: AppTextStyles.captionSmall.copyWith(
                                          fontSize: 11,
                                          color: AppColors.textSecondary,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              if (location.isNotEmpty) ...[
                                AppSpacing.verticalXS,
                                Row(
                                  children: [
                                    Icon(Icons.location_on_outlined,
                                        size: 11,
                                        color: AppColors.textHint),
                                    AppSpacing.horizontalXS,
                                    Expanded(
                                      child: Text(
                                        location,
                                        style: AppTextStyles.captionSmall.copyWith(
                                          fontSize: 11,
                                          color: AppColors.textSecondary,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                          SizedBox(
                            width: double.infinity,
                            height: 30,
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                padding: EdgeInsets.zero,
                                side: const BorderSide(
                                    color: AppColors.primary, width: 1.5),
                                shape: RoundedRectangleBorder(
                                    borderRadius: AppDimensions.borderRadiusMD),
                              ),
                              onPressed: () {
                                final profileUserId = profile['userid'];
                                if (profileUserId != null) {
                                  if (VerificationService.requireVerification(context)) {
                                    Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (_) => ProfileLoader(
                                                userId: profileUserId
                                                    .toString(),
                                                myId: userid.toString())));
                                  }
                                }
                              },
                              child: Text(
                                'Connect',
                                style: AppTextStyles.primaryLabel,
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
          );
        },
      ),
    );
  }

  Widget _buildShortlistedProfiles() {
    if (_isLoadingShortlist && _shortlistedProfiles.isEmpty) {
      return const ShortlistCardListSkeleton(count: 3);
    }

    if (_shortlistedProfiles.isEmpty) {
      return SizedBox(
        height: 180,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.bookmark_border_rounded,
                  size: 48, color: AppColors.border),
              AppSpacing.verticalSM,
              Text('No shortlisted profiles yet',
                  style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textHint)),
            ],
          ),
        ),
      );
    }

    return SizedBox(
      height: 180,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _shortlistedProfiles.length,
        padding: const EdgeInsets.only(left: 16, right: 8),
        itemBuilder: (context, index) {
          final person = _shortlistedProfiles[index];
          final firstName = person['firstName']?.toString() ?? '';
          final lastName = person['lastName']?.toString() ?? '';
          final fullName = '$firstName $lastName'.trim();
          final displayName = fullName.isNotEmpty ? fullName : 'User';
          final city = person['city']?.toString() ?? '';
          final profilePicture = person['profile_picture']?.toString() ?? '';
          final imageUrl = profilePicture.isNotEmpty
              ? (profilePicture.startsWith('http')
                  ? profilePicture
                  : '${kApiBaseUrl}/Api2/$profilePicture')
              : '';
          final isVerified =
              person['isVerified'] == 1 || person['isVerified'] == '1';
          final receiverId = person['userid'];
          final shortlistPrivacy = person['privacy']?.toString().toLowerCase() ?? '';
          final shortlistPhotoRequest = person['photo_request']?.toString().toLowerCase() ?? '';
          final shortlistShowClear = person['can_view_photo'] == true;

          Widget shortlistProfileImg = imageUrl.isNotEmpty
              ? Image.network(
                  imageUrl,
                  width: double.infinity,
                  height: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: AppColors.background,
                    child: const Center(
                        child: Icon(Icons.person_rounded,
                            size: 50, color: AppColors.textHint)),
                  ),
                )
              : Container(
                  color: AppColors.background,
                  child: const Center(
                      child: Icon(Icons.person_rounded,
                          size: 50, color: AppColors.textHint)),
                );
          if (imageUrl.isNotEmpty && !shortlistShowClear) {
            shortlistProfileImg = ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: shortlistProfileImg,
            );
          }

          return GestureDetector(
            onTap: () {
              if (receiverId != null) {
                if (VerificationService.requireVerification(context)) {
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => ProfileLoader(
                              userId: receiverId.toString(),
                              myId: userid.toString())));
                }
              }
            },
            child: Container(
              width: 150,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: AppDimensions.borderRadiusLG,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.black.withOpacity(0.07),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: AppDimensions.borderRadiusLG,
                child: Stack(
                  children: [
                    // Full-height image
                    shortlistProfileImg,
                    // Bottom gradient overlay
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: 90,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.transparent, AppColors.black],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ),
                    ),
                    // Name & city text at bottom
                    Positioned(
                      bottom: 8,
                      left: 10,
                      right: 10,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            displayName,
                            style: AppTextStyles.caption.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.white,
                              shadows: const [
                                Shadow(
                                    color: Colors.black87,
                                    blurRadius: 6,
                                    offset: Offset(0, 1))
                              ],
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (city.isNotEmpty)
                            Row(
                              children: [
                                Icon(Icons.location_on,
                                    size: 12, color: AppColors.white.withOpacity(0.7)),
                                AppSpacing.horizontalXS,
                                Expanded(
                                  child: Text(
                                    city,
                                    style: AppTextStyles.captionSmall.copyWith(
                                        fontSize: 11, color: AppColors.white.withOpacity(0.7)),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                    // Verified badge
                    if (isVerified)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: const BoxDecoration(
                            color: AppColors.white,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.verified_rounded,
                              color: Color(0xFF2196F3), size: 14),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPremiumMembers() {
    if (_premiumMembers.isEmpty && !_premiumMembersLoaded) {
      return const ProfileCardListSkeleton(count: 3, height: 260);
    }

    if (_premiumMembers.isEmpty) {
      return SizedBox(
        height: 240,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.star_outline_rounded,
                  size: 48, color: AppColors.border),
              AppSpacing.verticalSM,
              Text('No premium members yet',
                  style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textHint)),
            ],
          ),
        ),
      );
    }

    return SizedBox(
      height: 260,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _premiumMembers.length,
        padding: const EdgeInsets.only(left: 16, right: 8),
        itemBuilder: (context, index) {
          final profile = _premiumMembers[index];
          final lastName = profile['lastName'] ?? '';
          final userIdd = profile['id'];
          final age = profile['age'] ?? '';
          final location = profile['city'] ?? '';
          final imageUrl = profile['image'] ?? '';
          final isVerified = profile['isVerified']?.toString() == '1';
          final ageStr = age.toString();
          final detailLine = [
            if (ageStr.isNotEmpty && ageStr != '0') '$ageStr yrs',
            if (location.isNotEmpty) location,
          ].join(' · ');
          final premiumPrivacy = profile['privacy']?.toString().toLowerCase() ?? '';
          final premiumPhotoRequest = profile['photo_request']?.toString().toLowerCase() ?? '';
          final premiumShowClear = profile['can_view_photo'] == true;

          Widget premiumProfileImg = Image.network(
            imageUrl,
            width: double.infinity,
            height: 160,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              height: 160,
              color: AppColors.background,
              child: const Center(
                child: Icon(Icons.person_rounded,
                    size: 60, color: AppColors.textHint),
              ),
            ),
          );
          if (!premiumShowClear) {
            premiumProfileImg = ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: premiumProfileImg,
            );
          }

          return GestureDetector(
            onTap: () {
              if (VerificationService.requireVerification(context)) {
                Navigator.push(context, MaterialPageRoute(
                    builder: (_) => ProfileLoader(
                        userId: userIdd.toString(), myId: userid.toString())));
              }
            },
            child: Container(
              width: 180,
              margin: const EdgeInsets.only(right: 14),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: AppDimensions.borderRadiusXL,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.black.withOpacity(0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(20)),
                        child: Stack(
                          children: [
                            premiumProfileImg,
                            Positioned(
                              bottom: 0,
                              left: 0,
                              right: 0,
                              child: Container(
                                height: 60,
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.transparent,
                                      Colors.black54
                                    ],
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        top: 10,
                        left: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [AppColors.premium, Color(0xFFFFA000)],
                            ),
                            borderRadius: AppDimensions.borderRadiusMD,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.star_rounded,
                                  color: AppColors.white, size: 10),
                              AppSpacing.horizontalXS,
                              Text(
                                'Premium',
                                style: AppTextStyles.captionSmall.copyWith(
                                  color: AppColors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (isVerified)
                        Positioned(
                          top: 10,
                          right: 10,
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: const BoxDecoration(
                              color: AppColors.white,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.verified_rounded,
                                color: Color(0xFF2196F3), size: 18),
                          ),
                        ),
                    ],
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'MS $userIdd $lastName',
                                style: AppTextStyles.labelMedium,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              AppSpacing.verticalXS,
                              Row(
                                children: [
                                  Icon(Icons.location_on_rounded,
                                      size: 12, color: AppColors.textHint),
                                  AppSpacing.horizontalXS,
                                  Expanded(
                                    child: Text(
                                      detailLine,
                                      style: AppTextStyles.captionSmall.copyWith(
                                        fontSize: 11,
                                        color: AppColors.textSecondary,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          SizedBox(
                            width: double.infinity,
                            height: 32,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                elevation: 0,
                                padding: EdgeInsets.zero,
                                shape: RoundedRectangleBorder(
                                  borderRadius: AppDimensions.borderRadiusLG,
                                ),
                              ),
                              onPressed: () {
                                if (VerificationService.requireVerification(context)) {
                                  Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                          builder: (_) => ProfileLoader(
                                              userId: userIdd.toString(),
                                              myId: userid.toString())));
                                }
                              },
                              child: Text(
                                'View Profile',
                                style: AppTextStyles.whiteLabel,
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
          );
        },
      ),
    );
  }

  Widget _buildRecentMembers() {
    if (_recentMembers.isEmpty && _isLoadingRecentMembers) {
      return const ProfileCardListSkeleton(count: 3, height: 270);
    }

    if (_recentMembers.isEmpty) {
      return SizedBox(
        height: 240,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.person_add_alt_1_rounded,
                  size: 48, color: AppColors.border),
              AppSpacing.verticalSM,
              Text('No recent members yet',
                  style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textHint)),
            ],
          ),
        ),
      );
    }

    return SizedBox(
      height: 270,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _recentMembers.length,
        padding: const EdgeInsets.only(left: 16, right: 8),
        itemBuilder: (context, index) {
          final profile = _recentMembers[index];
          final lastName = profile['lastName'] ?? '';
          final firstName = profile['firstName'] ?? '';
          final memberid = profile['memberid'] ?? 'MS';
          final userIdd = profile['userId'] ?? profile['id'];
          final age = profile['age'] ?? '';
          final location = profile['city'] ?? '';
          final country = profile['country'] ?? '';
          final heightName = profile['heightName'] ?? '';
          final designation = profile['designation'] ?? '';
          final imageUrl = profile['image'] ?? '';
          final isVerified = profile['isVerified']?.toString() == '1';
          final privacy = profile['privacy']?.toString().toLowerCase() ?? '';
          final photoRequest = profile['photo_request']?.toString().toLowerCase() ?? '';

          // Determine if we should show clear image (use backend-computed can_view_photo)
          final shouldShowClearImage = profile['can_view_photo'] == true;

          return GestureDetector(
            onTap: () {
              if (VerificationService.requireVerification(context)) {
                Navigator.push(context, MaterialPageRoute(
                    builder: (_) => ProfileLoader(
                        userId: userIdd.toString(), myId: userid.toString())));
              }
            },
            child: Container(
              width: 190,
              margin: const EdgeInsets.only(right: 14),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: AppDimensions.borderRadiusXL,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.black.withOpacity(0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(20)),
                        child: shouldShowClearImage
                            ? Image.network(
                                imageUrl,
                                width: double.infinity,
                                height: 180,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  height: 180,
                                  color: AppColors.background,
                                  child: const Center(
                                    child: Icon(Icons.person_rounded,
                                        size: 60, color: AppColors.textHint),
                                  ),
                                ),
                              )
                            : Stack(
                                children: [
                                  Image.network(
                                    imageUrl,
                                    width: double.infinity,
                                    height: 180,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                      height: 180,
                                      color: AppColors.background,
                                      child: const Center(
                                        child: Icon(Icons.person_rounded,
                                            size: 60, color: AppColors.textHint),
                                      ),
                                    ),
                                  ),
                                  Container(
                                    width: double.infinity,
                                    height: 180,
                                    decoration: BoxDecoration(
                                      color: AppColors.black.withOpacity(0.25),
                                    ),
                                    child: BackdropFilter(
                                      filter: ui.ImageFilter.blur(
                                          sigmaX: 14, sigmaY: 14),
                                      child: Container(
                                        color: AppColors.black.withOpacity(0.05),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                      ),
                      // New member badge
                      Positioned(
                        top: 10,
                        left: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF4CAF50), Color(0xFF2E7D32)],
                            ),
                            borderRadius: AppDimensions.borderRadiusMD,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.fiber_new_rounded,
                                  color: AppColors.white, size: 10),
                              AppSpacing.horizontalXS,
                              Text(
                                'New',
                                style: AppTextStyles.captionSmall.copyWith(
                                  color: AppColors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (isVerified)
                        Positioned(
                          top: 10,
                          right: 10,
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: const BoxDecoration(
                              color: AppColors.white,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.verified_rounded,
                                color: Color(0xFF2196F3), size: 18),
                          ),
                        ),
                    ],
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            memberid != 'N/A' && memberid.isNotEmpty
                                ? '$memberid $lastName'
                                : 'MS $userIdd $lastName',
                            style: AppTextStyles.labelMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          AppSpacing.verticalXS,
                          Text(
                            [
                              if (age.toString().isNotEmpty && age.toString() != '0') '$age yrs',
                              if (heightName.isNotEmpty)
                                heightName.replaceAll(RegExp(r'\s*cm.*'), ' cm'),
                            ].join(' · '),
                            style: AppTextStyles.captionSmall.copyWith(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (designation.isNotEmpty) ...[
                            AppSpacing.verticalXS,
                            Text(
                              designation,
                              style: AppTextStyles.captionSmall.copyWith(
                                fontSize: 10,
                                color: AppColors.textHint,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          AppSpacing.verticalXS,
                          Row(
                            children: [
                              Icon(Icons.location_on_rounded,
                                  size: 11, color: AppColors.textHint),
                              AppSpacing.horizontalXS,
                              Expanded(
                                child: Text(
                                  '$location${country.isNotEmpty ? ', $country' : ''}',
                                  style: AppTextStyles.captionSmall.copyWith(
                                    fontSize: 10,
                                    color: AppColors.textSecondary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
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
            ),
          );
        },
      ),
    );
  }

  Widget _buildOtherServices() {
    if (_loading && _otherServices.isEmpty) {
      return const SizedBox(
        height: 200,
        child: ServiceListSkeleton(count: 3),
      );
    }

    if (_otherServices.isEmpty) {
      return SizedBox(
        height: 120,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.handshake_outlined,
                  size: 40, color: AppColors.border),
              AppSpacing.verticalSM,
              Text('No services available',
                  style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textHint)),
            ],
          ),
        ),
      );
    }

    return Column(
      children: _otherServices.map((service) {
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: AppDimensions.borderRadiusXL,
            boxShadow: [
              BoxShadow(
                color: AppColors.black.withOpacity(0.07),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  bottomLeft: Radius.circular(20),
                ),
                child: Stack(
                  children: [
                    Image.network(
                      service['image'],
                      width: 120,
                      height: 175,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 120,
                        height: 175,
                        color: AppColors.background,
                        child: const Center(
                          child: Icon(Icons.person_rounded,
                              size: 50, color: AppColors.textHint),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 10,
                      left: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AppColors.primary, Color(0xFFD81B60)],
                          ),
                          borderRadius: AppDimensions.borderRadiusMD,
                        ),
                        child: Text(
                          service['category'],
                          textAlign: TextAlign.center,
                          style: AppTextStyles.captionSmall.copyWith(
                            color: AppColors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 14, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              service['name'],
                              style: AppTextStyles.heading4.copyWith(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          AppSpacing.horizontalSM,
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.08),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.favorite_border_rounded,
                                color: AppColors.primary, size: 16),
                          ),
                        ],
                      ),
                      AppSpacing.verticalSM,
                      Row(
                        children: [
                          Icon(Icons.cake_outlined,
                              size: 13, color: AppColors.textHint),
                          AppSpacing.horizontalXS,
                          Text(
                            'Age ${service['age']}',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                          AppSpacing.horizontalSM,
                          Icon(Icons.location_on_outlined,
                              size: 13, color: AppColors.textHint),
                          AppSpacing.horizontalXS,
                          Expanded(
                            child: Text(
                              service['location'],
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.textSecondary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      AppSpacing.verticalXS,
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.06),
                          borderRadius: AppDimensions.borderRadiusMD,
                        ),
                        child: Text(
                          'Exp: ${service['experience']}',
                          style: AppTextStyles.labelSmall.copyWith(color: AppColors.primary),
                        ),
                      ),
                      AppSpacing.verticalSM,
                      SizedBox(
                        width: double.infinity,
                        height: 40,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: AppDimensions.borderRadiusXL,
                            ),
                          ),
                          icon: const Icon(Icons.chat_bubble_outline_rounded,
                              color: AppColors.white, size: 16),
                          label: Text(
                            'Start Conversation',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => ServiceChatPage(
                                      senderId: userid.toString(),
                                      receiverId: service['id'].toString(),
                                      name: service['name'],
                                      exp: service['experience'],
                                      cat: service['category']))),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  List<ProposalModel> _mergeChatRequests({
    required String currentUserId,
    required List<ProposalModel> sentRequests,
    required List<ProposalModel> acceptedRequests,
  }) {
    final Map<String, ProposalModel> mergedRequests = {};

    void addRequests(List<ProposalModel> requests) {
      for (final request in requests) {
        final requestType = (request.requestType ?? '').toLowerCase();
        final status = (request.status ?? '').toLowerCase();
        final isSentByCurrentUser = request.senderId?.toString() == currentUserId;

        if (requestType != 'chat' || !isSentByCurrentUser) {
          continue;
        }

        if (status != 'accepted' && status != 'pending') {
          continue;
        }

        final key = request.proposalId ??
            '${request.senderId}_${request.receiverId}_${request.requestType}';
        final existing = mergedRequests[key];

        if (existing == null ||
            _requestStatusPriority(status) <
                _requestStatusPriority(existing.status)) {
          mergedRequests[key] = request;
        }
      }
    }

    addRequests(sentRequests);
    addRequests(acceptedRequests);

    final requests = mergedRequests.values.toList()
      ..sort((a, b) {
        final statusCompare = _requestStatusPriority(a.status)
            .compareTo(_requestStatusPriority(b.status));
        if (statusCompare != 0) {
          return statusCompare;
        }

        final aName = '${a.firstName ?? ''} ${a.lastName ?? ''}'.trim();
        final bName = '${b.firstName ?? ''} ${b.lastName ?? ''}'.trim();
        return aName.compareTo(bName);
      });

    return requests;
  }

  int _requestStatusPriority(String? status) {
    switch ((status ?? '').toLowerCase()) {
      case 'accepted':
        return 0;
      case 'pending':
        return 1;
      default:
        return 2;
    }
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'accepted':
        return AppColors.success;
      case 'pending':
        return const Color(0xFFF9A825);
      default:
        return _brandRed;
    }
  }

  String _resolveApiImageUrl(String rawImage) {
    if (rawImage.isEmpty) {
      return '';
    }

    if (rawImage.startsWith('http')) {
      return rawImage;
    }

    final normalizedPath = rawImage.startsWith('/')
        ? rawImage.substring(1)
        : rawImage;
    return '$_apiBaseUrl/$normalizedPath';
  }

  Widget _buildRequestLoadingState() {
    return const SizedBox(
      height: 250,
      child: ProfileCardListSkeleton(count: 2, height: 250),
    );
  }

  Widget _buildRequestEmptyState({
    required IconData icon,
    required String message,
  }) {
    return SizedBox(
      height: 250,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: AppColors.border),
            AppSpacing.verticalSM,
            Text(
              message,
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textHint),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRequestFallbackImage() {
    return Container(
      width: double.infinity,
      height: 160,
      color: AppColors.background,
      child: const Center(
        child: Icon(Icons.person_rounded, size: 60, color: AppColors.textHint),
      ),
    );
  }

  Widget _buildRequestStatusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: AppDimensions.borderRadiusMD,
      ),
      child: Text(
        label,
        style: AppTextStyles.captionSmall.copyWith(
          color: AppColors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  void _openProfile(String profileUserId) {
    if (!VerificationService.requireVerification(context)) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProfileLoader(
          userId: profileUserId,
          myId: userid.toString(),
        ),
      ),
    );
  }

  void _openPhotoRequestProfile(String profileUserId) {
    if (!VerificationService.requireVerification(context)) return;

    if (usertye == 'free') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => SubscriptionPage()),
      );
      return;
    }

    _openProfile(profileUserId);
  }

  Future<void> _openChatRequest(ProposalModel request) async {
    try {
      if (!VerificationService.requireVerification(context)) return;

      if (usertye == "free") {
        showUpgradeDialog(context);
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final userDataString = prefs.getString('user_data');
      if (userDataString == null) {
        return;
      }

      final userData = jsonDecode(userDataString);
      final currentUserIdStr = userData['id'].toString();
      final currentUserName =
          '${userData['firstName'] ?? ''} ${userData['lastName'] ?? ''}'.trim();
      final currentUserImage =
          _resolveApiImageUrl(userData['profilePicture']?.toString() ?? '');

      final isCurrentUserSender = currentUserIdStr == request.senderId;
      final otherUserId = isCurrentUserSender
          ? (request.receiverId ?? '')
          : (request.senderId ?? '');

      if (otherUserId.isEmpty) {
        return;
      }

      final otherUserName =
          'MS ${request.memberid ?? ''} ${request.firstName ?? ''} ${request.lastName ?? ''}'
              .trim();
      final otherUserImage = _resolveApiImageUrl(request.profilePicture ?? '');

      final userIds = [currentUserIdStr, otherUserId]..sort();
      final chatRoomId = userIds.join('_');

      // Chat room is auto-created by the Socket.IO server on first message send.
      // No need to pre-create it in Firestore.

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatDetailScreen(
            chatRoomId: chatRoomId,
            receiverId: otherUserId,
            receiverName:
                otherUserName.isNotEmpty ? otherUserName : 'User $otherUserId',
            receiverImage: otherUserImage.isNotEmpty
                ? otherUserImage
                : _placeholderProfileImage,
            currentUserId: currentUserIdStr,
            currentUserName: currentUserName.isNotEmpty
                ? currentUserName
                : 'User $currentUserIdStr',
            currentUserImage: currentUserImage.isNotEmpty
                ? currentUserImage
                : _placeholderProfileImage,
          ),
        ),
      );
    } catch (e) {
      debugPrint('Error opening chat request: $e');
    }
  }



  Widget _buildSectionHeader(String title, {bool showSeeAll = true}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          children: [
            Container(
              width: 3,
              height: 20,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primary, Color(0xFFD81B60)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: AppDimensions.borderRadiusXS,
              ),
            ),
            AppSpacing.horizontalSM,
            Text(
              title,
              style: AppTextStyles.labelLarge.copyWith(letterSpacing: -0.2),
            ),
          ],
        ),
        if (showSeeAll)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'See All',
                style: AppTextStyles.labelSmall.copyWith(color: AppColors.primary.withOpacity(0.85)),
              ),
              AppSpacing.horizontalXS,
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.primary, size: 16),
            ],
          ),
      ],
    );
  }
}
