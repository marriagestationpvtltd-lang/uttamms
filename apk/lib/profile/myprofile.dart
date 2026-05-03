import 'dart:io' if (dart.library.html) 'package:ms2026/utils/web_io_stub.dart';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../Auth/Screen/signupscreen2.dart';
import '../Auth/Screen/signupscreen3.dart';
import '../Auth/Screen/signupscreen5.dart';
import '../Auth/Screen/signupscreen6.dart';
import '../Auth/Screen/signupscreen8.dart';
import '../Auth/Screen/signupscreen9.dart';
import '../Auth/Screen/signupscreen10.dart';
import '../Auth/SuignupModel/signup_model.dart';
import '../DeleteAccount/deleteAccointScreen.dart';
import '../Package/PackageScreen.dart';
import '../Startup/onboarding.dart';
import '../constant/app_colors.dart';
import '../core/user_state.dart';
import '../service/connectivity_service.dart';
import '../otherenew/blocked_users_screen.dart';
import '../settings/settings_screen.dart';
import '../utils/image_utils.dart';
import 'package:ms2026/config/app_endpoints.dart';
import 'package:ms2026/config/profile_constants.dart';
import 'package:ms2026/features/shorts/services/shorts_service.dart';
import 'package:ms2026/features/shorts/story_viewer_screen.dart';

class MatrimonyProfilePage extends StatefulWidget {
  @override
  _MatrimonyProfilePageState createState() => _MatrimonyProfilePageState();
}

class _MatrimonyProfilePageState extends State<MatrimonyProfilePage> {
  static const SystemUiOverlayStyle _statusBarStyle = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemStatusBarContrastEnforced: false,
  );

  static const SystemUiOverlayStyle _loadingStatusBarStyle =
      SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemStatusBarContrastEnforced: false,
  );

  Map<String, dynamic>? profileData;
  bool isLoading = true;
  bool isProfileVerified = false;
  bool isShortlisted = false;
  String memberType = 'Free'; // Can be 'Free', 'Premium', 'Gold', 'Platinum'
  int _profilePictureTimestamp = DateTime.now().millisecondsSinceEpoch;
  String _profilePhotoStatus =
      'approved'; // 'pending' | 'approved' | 'rejected'
  String? _activePackageName;
  String? _activePackageExpiry;
  String _docStatus = 'not_uploaded';
  bool _isUploadingGallery = false;
  final Set<int> _galleryActionInProgress = <int>{};
  bool _isCheckingConnectivity = false;
  bool? _lastConnectivityState;
  ConnectivityService? _connectivityService;

  // User contact information
  String? _userEmail;
  String? _userPhone;
  String? _userId;

  @override
  void initState() {
    super.initState();
    fetchProfileData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final connectivityService = context.read<ConnectivityService>();
    if (_connectivityService == connectivityService) {
      return;
    }

    _connectivityService?.removeListener(_handleConnectivityChange);
    _connectivityService = connectivityService;
    _connectivityService?.addListener(_handleConnectivityChange);
    _handleConnectivityChange();
  }

  @override
  void dispose() {
    _connectivityService?.removeListener(_handleConnectivityChange);
    super.dispose();
  }

  Future<void> fetchProfileData() async {
    setState(() {
      isLoading = true;
    });

    final prefs = await SharedPreferences.getInstance();
    final userDataString = prefs.getString('user_data');
    final userData = jsonDecode(userDataString!);
    final userId = int.tryParse(userData["id"].toString());

    // Store user contact information from SharedPreferences
    setState(() {
      _userId = userData["id"]?.toString();
      _userEmail = userData["email"]?.toString();
      _userPhone = userData["contactNo"]?.toString();
    });

    try {
      final response = await http.get(
        Uri.parse('${kApiBaseUrl}/Api2/myprofile.php?userid=${userId}'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success') {
          final Map<String, dynamic> fullProfileData = {
            ..._asMap(data['data']),
            'gallery': (data['gallery'] as List?) ?? const [],
          };
          final userState = context.read<UserState>();
          if (userId != null) {
            await userState.refresh(userId);
          }
          setState(() {
            profileData = fullProfileData;
            isProfileVerified = userState.isVerified;
            memberType = _getMemberType(
                profileData?['personalDetail']?['usertype'] ?? 'free');
            _profilePhotoStatus = profileData?['personalDetail']
                        ?['profilePhotoStatus']
                    ?.toString() ??
                'approved';
            isLoading = false;
          });
          _fetchActivePackage(userId.toString());
          _syncDocStatusFromUserState();

          // Sync fresh name and profile picture back to SharedPreferences so
          // other screens (e.g. Settings, Home) always show up-to-date info.
          final personalDetail = data['data']?['personalDetail'];
          if (personalDetail != null) {
            Map<String, dynamic> currentUserData;
            try {
              currentUserData = jsonDecode(prefs.getString('user_data') ?? '{}')
                  as Map<String, dynamic>;
            } catch (_) {
              currentUserData = {};
            }
            bool updated = false;
            final String? firstName = personalDetail['firstName']?.toString();
            final String? lastName = personalDetail['lastName']?.toString();
            final String? profilePic =
                personalDetail['profile_picture']?.toString();
            if (firstName != null) {
              currentUserData['firstName'] = firstName;
              await prefs.setString('user_firstName', firstName);
              updated = true;
            }
            if (lastName != null) {
              currentUserData['lastName'] = lastName;
              await prefs.setString('user_lastName', lastName);
              updated = true;
            }
            if (profilePic != null) {
              currentUserData['profile_picture'] = profilePic;
              updated = true;
            }
            if (updated) {
              await prefs.setString('user_data', jsonEncode(currentUserData));
            }
          }
        } else {
          setState(() {
            isLoading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to load profile data'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } else {
        setState(() {
          isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Network error: ${response.statusCode}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      setState(() {
        isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Syncs `_docStatus` and `isProfileVerified` from the global [UserState]
  /// provider instead of making an extra API call to `check_document_status.php`.
  ///
  /// `isProfileVerified` is set from [UserState.isVerified] — the single
  /// flag that combines both identity and marital document approval.
  void _syncDocStatusFromUserState() {
    if (!mounted) return;
    try {
      final userState = context.read<UserState>();
      setState(() {
        _docStatus = userState.identityStatus;
        isProfileVerified = userState.isVerified;
      });
    } catch (e) {
      debugPrint('_syncDocStatusFromUserState error: $e');
    }
  }

  Future<void> _fetchActivePackage(String userId) async {
    try {
      final response = await http.get(
        Uri.parse('${kApiBaseUrl}/Api2/user_package.php?userid=$userId'),
      );

      if (response.statusCode != 200) {
        return;
      }

      final data = json.decode(response.body);
      if (data['success'] == true &&
          data['data'] != null &&
          (data['data'] as List).isNotEmpty) {
        final latest = (data['data'] as List).first;
        if (!mounted) return;
        setState(() {
          _activePackageName = latest['package_name']?.toString();
          final expiry = latest['expiredate']?.toString() ?? '';
          _activePackageExpiry =
              expiry.length >= 10 ? expiry.substring(0, 10) : expiry;
        });
      } else if (mounted) {
        setState(() {
          _activePackageName = null;
          _activePackageExpiry = null;
        });
      }
    } catch (e) {
      debugPrint('Active package fetch failed: $e');
    }
  }

  Future<void> _openMyStories(Map<String, dynamic> personalDetail) async {
    final viewerId = int.tryParse(_userId ?? '') ?? 0;
    if (viewerId <= 0) return;

    try {
      final stories = await ShortsService.fetchUserStories(
        userId: viewerId,
        targetUserId: viewerId,
      );

      if (!mounted) return;
      if (stories.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No active story found.')),
        );
        return;
      }

      final userName = _joinNonEmpty([
        personalDetail['firstName']?.toString() ?? '',
        personalDetail['lastName']?.toString() ?? '',
      ]);

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => StoryViewerScreen(
            userName: userName.isEmpty ? 'My Story' : userName,
            profilePicture: _getFullImageUrl(personalDetail['profile_picture']),
            stories: stories,
            currentUserId: viewerId,
            onEditPrivacy: (storyId, privacy) async {
              try {
                await ShortsService.updateStoryPrivacy(
                  userId: viewerId,
                  storyId: storyId,
                  privacy: privacy,
                );
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Story privacy updated')),
                  );
                }
                return true;
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(e.toString())),
                  );
                }
                return false;
              }
            },
            onDeleteStory: (storyId) async {
              try {
                await ShortsService.deleteStory(
                    userId: viewerId, storyId: storyId);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Story deleted')),
                  );
                }
                return true;
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(e.toString())),
                  );
                }
                return false;
              }
            },
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load story: $e')),
      );
    }
  }

  String _getMemberType(String userType) {
    switch (userType.toLowerCase()) {
      case 'premium':
        return 'Premium';
      case 'gold':
        return 'Gold';
      case 'platinum':
        return 'Platinum';
      default:
        return 'Free';
    }
  }

  String _getFullImageUrl(String? imagePath) {
    if (imagePath == null || imagePath.isEmpty) {
      return 'https://via.placeholder.com/150?text=No+Image';
    }

    String baseUrl;
    if (imagePath.startsWith('http')) {
      baseUrl = imagePath;
    } else {
      baseUrl = '${kApiBaseUrl}/Api2/$imagePath';
    }

    // Add timestamp to prevent caching
    return '$baseUrl?t=$_profilePictureTimestamp';
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  String _stringValue(dynamic value) {
    if (value == null) return '';
    return value.toString().trim();
  }

  bool _isMissing(dynamic value) {
    final normalized = _stringValue(value).toLowerCase();
    return normalized.isEmpty ||
        normalized == 'null' ||
        normalized == 'n/a' ||
        normalized == 'not specified' ||
        normalized == 'not provided' ||
        normalized == '0';
  }

  String _displayValue(dynamic value, {String fallback = 'Not provided'}) {
    return _isMissing(value) ? fallback : _stringValue(value);
  }

  String _firstFilled(List<dynamic> values, {String fallback = ''}) {
    for (final value in values) {
      if (!_isMissing(value)) {
        return _stringValue(value);
      }
    }
    return fallback;
  }

  int _countFilledFields(List<dynamic> values) {
    return values.where((value) => !_isMissing(value)).length;
  }

  String _joinNonEmpty(List<String> values, {String separator = ', '}) {
    return values.where((value) => value.trim().isNotEmpty).join(separator);
  }

  bool _isApprovedLikeStatus(dynamic value) {
    final normalized = _stringValue(value).toLowerCase();
    return normalized == 'approved' || normalized == 'verified';
  }

  Future<void> _openEditPage(Widget page,
      {Future<void> Function()? onReturn}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => page),
    );
    if (!mounted) return;
    final callback = onReturn ?? fetchProfileData;
    await callback();
  }

  /// Returns the current user's ID string from SharedPreferences, or an empty
  /// string when no session is found or when the stored data is malformed.
  Future<String> _getUserId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userData = jsonDecode(prefs.getString('user_data') ?? '{}');
      return userData['id']?.toString() ?? '';
    } catch (e) {
      debugPrint('_getUserId error: $e');
      return '';
    }
  }

  /// Joins a list to a comma-separated string. When [v] is already a string it
  /// is returned as-is, and [null] becomes an empty string.
  String _joinList(dynamic v) =>
      v is List ? v.join(',') : (v?.toString() ?? '');

  /// Refreshes only the personal-detail fields from the dedicated section API.
  /// Merges the fresh data into [profileData]['personalDetail'] in place so the
  /// rest of the profile (family, lifestyle, partner) is not disturbed.
  Future<void> _refreshPersonalSection() async {
    final userId = await _getUserId();
    if (userId.isEmpty) return;
    try {
      final res = await http.get(
        Uri.parse('$kApiBaseUrl/Api2/get_personal_detail.php?user_id=$userId'),
      );
      if (res.statusCode != 200) return;
      final body = jsonDecode(res.body);
      if (body['status'] != 'success' || body['data'] == null) return;
      final d = Map<String, dynamic>.from(body['data'] as Map);
      if (!mounted) return;
      setState(() {
        final pd = _asMap(profileData?['personalDetail']);
        pd['height_name'] = d['height_name'] ?? pd['height_name'];
        pd['weight_name'] = d['weight_name'] ?? pd['weight_name'];
        pd['bloodGroup'] = d['bloodGroup'] ?? pd['bloodGroup'];
        pd['complexion'] = d['complexion'] ?? pd['complexion'];
        pd['bodyType'] = d['bodyType'] ?? pd['bodyType'];
        pd['aboutMe'] = d['aboutMe'] ?? pd['aboutMe'];
        pd['Disability'] = d['Disability'] ?? pd['Disability'];
        pd['maritalStatusName'] =
            d['marital_status_name'] ?? pd['maritalStatusName'];
        pd['maritalStatusId'] = d['maritalStatusId'] ?? pd['maritalStatusId'];
        pd['haveSpecs'] = d['haveSpecs'] ?? pd['haveSpecs'];
        pd['anyDisability'] = d['anyDisability'] ?? pd['anyDisability'];
        pd['childStatus'] = d['childStatus'] ?? pd['childStatus'];
        pd['childLiveWith'] = d['childLiveWith'] ?? pd['childLiveWith'];
        profileData!['personalDetail'] = pd;
      });
    } catch (e) {
      debugPrint('_refreshPersonalSection error: $e');
    }
  }

  /// Refreshes only the education/career fields from the dedicated section API.
  Future<void> _refreshProfessionalSection() async {
    final userId = await _getUserId();
    if (userId.isEmpty) return;
    try {
      final res = await http.get(
        Uri.parse('$kApiBaseUrl/Api2/get_educationcareer.php?userid=$userId'),
      );
      if (res.statusCode != 200) return;
      final body = jsonDecode(res.body);
      if (body['status'] != 'success' || body['data'] == null) return;
      final d = Map<String, dynamic>.from(body['data'] as Map);
      if (!mounted) return;
      setState(() {
        final pd = _asMap(profileData?['personalDetail']);
        pd['educationmedium'] = d['educationmedium'] ?? pd['educationmedium'];
        pd['educationtype'] = d['educationtype'] ?? pd['educationtype'];
        pd['faculty'] = d['faculty'] ?? pd['faculty'];
        pd['degree'] = d['degree'] ?? pd['degree'];
        pd['areyouworking'] = d['areyouworking'] ?? pd['areyouworking'];
        pd['occupationtype'] = d['occupationtype'] ?? pd['occupationtype'];
        pd['companyname'] = d['companyname'] ?? pd['companyname'];
        pd['designation'] = d['designation'] ?? pd['designation'];
        pd['workingwith'] = d['workingwith'] ?? pd['workingwith'];
        pd['annualincome'] = d['annualincome'] ?? pd['annualincome'];
        pd['businessname'] = d['businessname'] ?? pd['businessname'];
        profileData!['personalDetail'] = pd;
      });
    } catch (e) {
      debugPrint('_refreshProfessionalSection error: $e');
    }
  }

  /// Refreshes only the family-detail fields from the dedicated section API.
  Future<void> _refreshFamilySection() async {
    final userId = await _getUserId();
    if (userId.isEmpty) return;
    try {
      final res = await http.get(
        Uri.parse('$kApiBaseUrl/Api2/get_family_details.php?userid=$userId'),
      );
      if (res.statusCode != 200) return;
      final body = jsonDecode(res.body);
      if (body['status'] != 'success' || body['data']?['family'] == null)
        return;
      final family = Map<String, dynamic>.from(body['data']['family'] as Map);
      if (!mounted) return;
      setState(() {
        final existing = _asMap(profileData?['familyDetail']);
        existing['familytype'] = family['familytype'] ?? existing['familytype'];
        existing['familybackground'] =
            family['familybackground'] ?? existing['familybackground'];
        existing['fatherstatus'] =
            family['fatherstatus'] ?? existing['fatherstatus'];
        existing['fathername'] = family['fathername'] ?? existing['fathername'];
        existing['fathereducation'] =
            family['fathereducation'] ?? existing['fathereducation'];
        existing['fatheroccupation'] =
            family['fatheroccupation'] ?? existing['fatheroccupation'];
        existing['motherstatus'] =
            family['motherstatus'] ?? existing['motherstatus'];
        existing['mothercaste'] =
            family['mothercaste'] ?? existing['mothercaste'];
        existing['mothereducation'] =
            family['mothereducation'] ?? existing['mothereducation'];
        existing['motheroccupation'] =
            family['motheroccupation'] ?? existing['motheroccupation'];
        existing['familyorigin'] =
            family['familyorigin'] ?? existing['familyorigin'];
        profileData!['familyDetail'] = existing;
      });
    } catch (e) {
      debugPrint('_refreshFamilySection error: $e');
    }
  }

  /// Refreshes only the lifestyle fields from the dedicated section API.
  Future<void> _refreshLifestyleSection() async {
    final userId = await _getUserId();
    if (userId.isEmpty) return;
    try {
      final res = await http.get(
        Uri.parse('$kApiBaseUrl/Api2/get_lifestyle.php?userid=$userId'),
      );
      if (res.statusCode != 200) return;
      final body = jsonDecode(res.body);
      if (body['status'] != 'success' || body['data'] == null) return;
      final d = Map<String, dynamic>.from(body['data'] as Map);
      if (!mounted) return;
      setState(() {
        final existing = _asMap(profileData?['lifestyle']);
        existing['diet'] = d['diet'] ?? existing['diet'];
        existing['smoke'] = d['smoke'] ?? existing['smoke'];
        existing['drinks'] = d['drinks'] ?? existing['drinks'];
        existing['drinktype'] = d['drinktype'] ?? existing['drinktype'];
        existing['smoketype'] = d['smoketype'] ?? existing['smoketype'];
        profileData!['lifestyle'] = existing;
      });
    } catch (e) {
      debugPrint('_refreshLifestyleSection error: $e');
    }
  }

  /// Refreshes only the partner-preference fields from the dedicated section API.
  Future<void> _refreshPartnerSection() async {
    final userId = await _getUserId();
    if (userId.isEmpty) return;
    try {
      final res = await http.get(
        Uri.parse(
            '$kApiBaseUrl/Api2/get_partner_preferences.php?userid=$userId'),
      );
      if (res.statusCode != 200) return;
      final body = jsonDecode(res.body);
      if (body['status'] != 'success' || body['data'] == null) return;
      final d = Map<String, dynamic>.from(body['data'] as Map);
      if (!mounted) return;
      setState(() {
        final existing = _asMap(profileData?['partner']);
        existing['minage'] = d['minage'] ?? existing['minage'];
        existing['maxage'] = d['maxage'] ?? existing['maxage'];
        existing['maritalstatus'] = _joinList(d['maritalstatus']).isNotEmpty
            ? _joinList(d['maritalstatus'])
            : existing['maritalstatus'];
        existing['religion'] = _joinList(d['religion']).isNotEmpty
            ? _joinList(d['religion'])
            : existing['religion'];
        existing['caste'] = _joinList(d['caste']).isNotEmpty
            ? _joinList(d['caste'])
            : existing['caste'];
        existing['qualification'] = _joinList(d['qualification']).isNotEmpty
            ? _joinList(d['qualification'])
            : existing['qualification'];
        existing['proffession'] = _joinList(d['proffession']).isNotEmpty
            ? _joinList(d['proffession'])
            : existing['proffession'];
        existing['annualincome'] = _joinList(d['annualincome']).isNotEmpty
            ? _joinList(d['annualincome'])
            : existing['annualincome'];
        existing['diet'] = _joinList(d['diet']).isNotEmpty
            ? _joinList(d['diet'])
            : existing['diet'];
        existing['smokeaccept'] = d['smokeaccept'] ?? existing['smokeaccept'];
        existing['drinkaccept'] = d['drinkaccept'] ?? existing['drinkaccept'];
        existing['familytype'] = _joinList(d['familytype']).isNotEmpty
            ? _joinList(d['familytype'])
            : existing['familytype'];
        existing['country'] = _joinList(d['country']).isNotEmpty
            ? _joinList(d['country'])
            : existing['country'];
        existing['state'] = _joinList(d['state']).isNotEmpty
            ? _joinList(d['state'])
            : existing['state'];
        existing['city'] = _joinList(d['city']).isNotEmpty
            ? _joinList(d['city'])
            : existing['city'];
        existing['otherexpectation'] =
            d['otherexpectation'] ?? existing['otherexpectation'];
        profileData!['partner'] = existing;
      });
    } catch (e) {
      debugPrint('_refreshPartnerSection error: $e');
    }
  }

  void _showMoreOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25.0)),
      ),
      builder: (BuildContext context) {
        return Container(
          padding: EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. BLOCKED USERS (First option)
                ListTile(
                  leading: Icon(Icons.block, color: Colors.red),
                  title: Text(
                    'Blocked Users',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  trailing: Icon(Icons.chevron_right, color: Colors.grey),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => BlockedUsersScreen(),
                      ),
                    );
                  },
                ),
                Divider(),

                // 2. PRIVACY SETTINGS
                ListTile(
                  leading: Icon(Icons.settings, color: Color(0xFFD32F2F)),
                  title: Text(
                    'Privacy Settings',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  trailing: Icon(Icons.chevron_right, color: Colors.grey),
                  onTap: () {
                    Navigator.pop(context);
                    _showPrivacySettings(context);
                  },
                ),
                Divider(),

                // 3. DELETE ACCOUNT
                ListTile(
                  leading: Icon(Icons.delete_outline, color: Colors.red),
                  title: Text(
                    'Delete Account',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  trailing: Icon(Icons.chevron_right, color: Colors.grey),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => DeleteAccountPage(),
                      ),
                    );
                  },
                ),
                Divider(),

                // 4. LOGOUT
                ListTile(
                  leading: Icon(Icons.logout, color: Colors.orange),
                  title: Text(
                    'Logout',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  trailing: Icon(Icons.chevron_right, color: Colors.grey),
                  onTap: () {
                    Navigator.pop(context);
                    _showLogoutConfirmation(context);
                  },
                ),
                SizedBox(height: 20),

                // 5. CANCEL BUTTON
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'Cancel',
                      style: TextStyle(color: Colors.grey, fontSize: 16),
                    ),
                  ),
                ),
                SizedBox(height: 10),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showPrivacySettings(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final userDataString = prefs.getString('user_data');
    if (userDataString == null) return;

    final userData = jsonDecode(userDataString);
    final int userId = int.parse(userData['id'].toString());

    // Step 1: Fetch current privacy from API; options come from shared constants
    String currentPrivacy = 'private';
    // Privacy values are stable system-level options — use the centralized
    // constant from profile_constants.dart instead of fetching from the API.
    List<String> privacyValues = List<String>.from(kPrivacyOptions);

    String prettyPrivacy(String value) {
      switch (value.toLowerCase()) {
        case 'free':
          return 'All Users';
        case 'paid':
          return 'Premium Users Only';
        case 'verified':
          return 'Verified Users Only';
        case 'private':
          return 'Private';
        default:
          return value;
      }
    }

    try {
      final Uri getUrl =
          Uri.parse('${kApiBaseUrl}/Api3/get_privacy.php?userid=$userId');
      final response = await http.get(getUrl);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'success') {
          currentPrivacy =
              data['data']['privacy']?.toString().toLowerCase() ?? 'private';
        }
      }
    } catch (e) {
      print("Error fetching privacy: $e");
    }

    if (!privacyValues.contains(currentPrivacy)) {
      privacyValues.add(currentPrivacy);
    }

    // Step 2: Show dialog with dropdown
    String selectedPrivacy = currentPrivacy;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            title: Text(
              'Privacy Settings',
              style: TextStyle(color: Color(0xFFD32F2F)),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(height: 20),
                  Text(
                    'Profile Picture Visibility',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  ExcludeFocus(
                    excluding: true,
                    child: DropdownButtonFormField<String>(
                      value: selectedPrivacy,
                      items: privacyValues.map((String value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(prettyPrivacy(value)),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setStateDialog(() {
                          selectedPrivacy = value ?? 'private';
                        });
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Cancel', style: TextStyle(color: Colors.grey)),
              ),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFD32F2F), Color(0xFFEF5350)],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: TextButton(
                  onPressed: () async {
                    Navigator.pop(context);

                    // Step 3: Call update_privacy API using selected API value
                    try {
                      final Uri updateUrl = Uri.parse(
                          '${kApiBaseUrl}/Api3/privacy.php?userid=$userId&privacy=$selectedPrivacy');
                      final response = await http.get(updateUrl);

                      if (response.statusCode == 200) {
                        final data = jsonDecode(response.body);
                        if (data['status'] == 'success') {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                  'Privacy settings updated successfully!'),
                              backgroundColor: Color(0xFFD32F2F),
                            ),
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Failed: ${data['message']}'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    } catch (e) {
                      print("Error updating privacy: $e");
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Error updating privacy'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  },
                  child: Text('Save Changes',
                      style: TextStyle(color: Colors.white)),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showLogoutConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Logout',
          style: TextStyle(color: Color(0xFFD32F2F)),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.logout, color: Colors.orange, size: 60),
            SizedBox(height: 20),
            Text(
              'Are you sure you want to logout?',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await context.read<SignupModel>().logout();

              if (!mounted) return;

              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => OnboardingScreen()),
                (route) => false,
              );
            },
            child: Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFD32F2F), Color(0xFFEF5350)],
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await _logout();
              },
              child: Text('Logout', style: TextStyle(color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _logout() async {
    // Clear the global UserState before wiping SharedPreferences.
    if (mounted) {
      await context.read<UserState>().clear();
    }
    final prefs = await SharedPreferences.getInstance();

    // Clear all local data
    await prefs.clear();
    // Preserve fast-start flag so subsequent opens still use the short animation.
    await prefs.setBool('has_launched_before', true);

    // Navigate to login screen
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Logged out successfully'),
        backgroundColor: Color(0xFFD32F2F),
      ),
    );
  }

  void _handleConnectivityChange() {
    final isConnected = _connectivityService?.isConnected ?? false;
    if (_lastConnectivityState == isConnected) {
      return;
    }

    final previousState = _lastConnectivityState;
    _lastConnectivityState = isConnected;

    if (previousState == false && isConnected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          fetchProfileData();
        }
      });
    }
  }

  Future<void> _handleOfflineRetry(
      ConnectivityService connectivityService) async {
    if (_isCheckingConnectivity) {
      return;
    }

    setState(() {
      _isCheckingConnectivity = true;
    });

    final hasInternet = await connectivityService.checkConnectivity();
    if (!mounted) {
      return;
    }

    setState(() {
      _isCheckingConnectivity = false;
    });

    if (hasInternet) {
      await fetchProfileData();
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('No internet connection. Please try again.'),
        backgroundColor: Color(0xFFD32F2F),
      ),
    );
  }

  Widget _buildOnlineScaffold(
      {required Widget child, SystemUiOverlayStyle? overlayStyle}) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle ?? _statusBarStyle,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: true,
        body: Container(
          color: const Color(0xFFF7F8FC),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ConnectivityService>(
      builder: (context, connectivityService, _) {
        final isConnected = connectivityService.isConnected;

        if (!isConnected) {
          return KeyedSubtree(
            key: const ValueKey('my-profile-offline'),
            child: _ProfileOfflineView(
              connectivityService: connectivityService,
              isCheckingConnectivity: _isCheckingConnectivity,
              onRetry: () => _handleOfflineRetry(connectivityService),
            ),
          );
        }

        if (isLoading) {
          return KeyedSubtree(
            key: const ValueKey('my-profile-online-loading'),
            child: _buildOnlineScaffold(
              overlayStyle: _loadingStatusBarStyle,
              child: const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFD32F2F)),
                ),
              ),
            ),
          );
        }

        if (profileData == null) {
          return KeyedSubtree(
            key: const ValueKey('my-profile-online-empty'),
            child: _buildOnlineScaffold(
              overlayStyle: _loadingStatusBarStyle,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline,
                        color: Colors.red, size: 50),
                    const SizedBox(height: 20),
                    const Text('No profile data found'),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: fetchProfileData,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD32F2F),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      child: const Text(
                        'Retry',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final personalDetail = _asMap(profileData!['personalDetail']);
        final familyDetail = _asMap(profileData!['familyDetail']);
        final lifestyle = _asMap(profileData!['lifestyle']);
        final partner = _asMap(profileData!['partner']);

        return KeyedSubtree(
          key: const ValueKey('my-profile-online'),
          child: _buildOnlineScaffold(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _buildHeader(personalDetail, lifestyle, familyDetail),
                  _buildCompletionSection(
                    personalDetail: personalDetail,
                    familyDetail: familyDetail,
                    lifestyle: lifestyle,
                    partner: partner,
                  ),
                  _buildGallerySection(),
                  _buildAboutMe(personalDetail, lifestyle, familyDetail),
                  _buildPersonalDetails(personalDetail),
                  _buildProfessionalDetails(personalDetail),
                  _buildCommunityDetails(personalDetail),
                  _buildLifestyle(lifestyle),
                  _buildFamilyDetails(familyDetail),
                  _buildPartnerPreferences(partner),
                  _buildMembershipAndPackageSection(),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(
    Map<String, dynamic> personalDetail,
    Map<String, dynamic> lifestyle,
    Map<String, dynamic> familyDetail,
  ) {
    final model = context.read<SignupModel>();
    final completion = _buildCompletionAudit(
      personalDetail: personalDetail,
      familyDetail: familyDetail,
      lifestyle: lifestyle,
      partner: _asMap(profileData?['partner']),
    ).completion;
    final primaryLocation = _joinNonEmpty([
      _firstFilled([personalDetail['city']]),
      _firstFilled([personalDetail['country']]),
    ]);
    final profileSubtitle = _joinNonEmpty([
      _displayValue(
        _firstFilled([personalDetail['designation'], personalDetail['degree']]),
        fallback: '',
      ),
      primaryLocation,
    ], separator: ' • ');

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFD32F2F), Color(0xFFEF5350)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(30),
          bottomRight: Radius.circular(30),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (Navigator.canPop(context))
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    )
                  else
                    const SizedBox(width: 48),
                  const Text(
                    'My Profile',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.settings, color: Colors.white),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              child: Column(
                children: [
                  Stack(
                    children: [
                      GestureDetector(
                        onTap: () => _openMyStories(personalDetail),
                        child: Container(
                          width: 92,
                          height: 92,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2.5),
                            image: DecorationImage(
                              image: NetworkImage(
                                _getFullImageUrl(
                                    personalDetail['profile_picture']),
                              ),
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),
                      // Photo approval status badge
                      if (_profilePhotoStatus == 'pending')
                        Positioned(
                          top: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF59E0B),
                              shape: BoxShape.circle,
                              border:
                                  Border.all(color: Colors.white, width: 1.5),
                            ),
                            child: const Icon(Icons.hourglass_top_rounded,
                                color: Colors.white, size: 12),
                          ),
                        )
                      else if (_profilePhotoStatus == 'rejected')
                        Positioned(
                          top: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444),
                              shape: BoxShape.circle,
                              border:
                                  Border.all(color: Colors.white, width: 1.5),
                            ),
                            child: const Icon(Icons.close_rounded,
                                color: Colors.white, size: 12),
                          ),
                        ),
                      if (isProfileVerified)
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Color(0xFFD32F2F),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.verified,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      Positioned(
                        bottom: 0,
                        left: 0,
                        child: InkWell(
                          onTap: () => _editProfilePicture(context),
                          child: Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: const Color(0xFFD32F2F),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: const Icon(
                              Icons.camera_alt,
                              color: Colors.white,
                              size: 14,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  // Photo status message below avatar
                  if (_profilePhotoStatus == 'pending')
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'Photo pending approval',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    )
                  else if (_profilePhotoStatus == 'rejected')
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'Photo rejected — please re-upload',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          '${_displayValue(personalDetail['firstName'], fallback: '')} ${_displayValue(personalDetail['lastName'], fallback: '')}, ${_calculateAge(personalDetail['birthDate'])}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (isProfileVerified)
                        const Icon(Icons.verified,
                            color: Colors.white, size: 20),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (profileSubtitle.isNotEmpty)
                    Text(
                      profileSubtitle,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 12.5,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 8),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (!_isMissing(personalDetail['degree']))
                        _buildInfoBadge(
                          _stringValue(personalDetail['degree']),
                          Icons.school,
                        ),
                      if (!_isMissing(model.gender))
                        _buildInfoBadge(_stringValue(model.gender), Icons.wc),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white.withOpacity(0.18)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildHeaderMetric(
                            'Profile Complete',
                            '$completion%',
                            Icons.auto_graph_rounded,
                          ),
                        ),
                        Container(width: 1, height: 32, color: Colors.white24),
                        Expanded(
                          child: _buildHeaderMetric(
                            'Verification',
                            isProfileVerified ? 'Verified' : 'Pending',
                            isProfileVerified
                                ? Icons.verified_rounded
                                : Icons.pending_actions_rounded,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  int _calculateAge(String? birthDate) {
    if (birthDate == null) return 0;
    try {
      DateTime birth = DateTime.parse(birthDate);
      DateTime now = DateTime.now();
      int age = now.year - birth.year;
      if (now.month < birth.month ||
          (now.month == birth.month && now.day < birth.day)) {
        age--;
      }
      return age;
    } catch (e) {
      return 0;
    }
  }

  Widget _buildMembershipAndPackageSection() {
    final hasPackage = !_isMissing(_activePackageName);

    final Color memberColor;
    final IconData memberIcon;
    final List<Color> gradientColors;

    switch (memberType) {
      case 'Premium':
        memberColor = const Color(0xFFFF8F00);
        memberIcon = Icons.workspace_premium_rounded;
        gradientColors = [const Color(0xFFFF6F00), const Color(0xFFFFA000)];
        break;
      case 'Gold':
        memberColor = const Color(0xFFF9A825);
        memberIcon = Icons.star_rounded;
        gradientColors = [const Color(0xFFF57F17), const Color(0xFFF9A825)];
        break;
      case 'Platinum':
        memberColor = const Color(0xFF546E7A);
        memberIcon = Icons.diamond_rounded;
        gradientColors = [const Color(0xFF37474F), const Color(0xFF607D8B)];
        break;
      default:
        memberColor = const Color(0xFF757575);
        memberIcon = Icons.person_rounded;
        gradientColors = [const Color(0xFF616161), const Color(0xFF9E9E9E)];
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.07),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Gradient header ──────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: gradientColors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.16),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Icon(memberIcon, color: Colors.white, size: 27),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$memberType Member',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _getMemberBenefits(memberType),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withOpacity(0.88),
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 11, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(20),
                        border:
                            Border.all(color: Colors.white.withOpacity(0.25)),
                      ),
                      child: Text(
                        memberType,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: _getMemberBenefitList(memberType)
                      .map((benefit) => Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.14),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: Colors.white.withOpacity(0.2)),
                            ),
                            child: Text(
                              benefit,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ))
                      .toList(),
                ),
              ],
            ),
          ),

          // ── Package status body ──────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(16),
            child: hasPackage
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F5E9),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: const Color(0xFF2E7D32).withOpacity(0.22),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.check_circle_rounded,
                                    color: Color(0xFF2E7D32), size: 19),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Active package: $_activePackageName',
                                    style: const TextStyle(
                                      color: Color(0xFF2E7D32),
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (!_isMissing(_activePackageExpiry)) ...[
                              const SizedBox(height: 6),
                              Padding(
                                padding: const EdgeInsets.only(left: 29),
                                child: Row(
                                  children: [
                                    Icon(Icons.event_available_rounded,
                                        size: 14, color: Colors.grey[600]),
                                    const SizedBox(width: 5),
                                    Text(
                                      'Valid until $_activePackageExpiry',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const SubscriptionPage(),
                            ),
                          ),
                          icon: const Icon(Icons.upgrade_rounded,
                              size: 18, color: Colors.white),
                          label: const Text(
                            'Update Package',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2E7D32),
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline_rounded,
                                color: Colors.grey[500], size: 18),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'You are on the $memberType plan. Upgrade to unlock premium features.',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 12.5,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const SubscriptionPage()),
                          ),
                          icon: Icon(
                            memberType == 'Free'
                                ? Icons.rocket_launch_rounded
                                : Icons.swap_horiz_rounded,
                            size: 18,
                            color: Colors.white,
                          ),
                          label: Text(
                            memberType == 'Free'
                                ? 'Upgrade Now'
                                : 'Change Plan',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: memberColor,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemberTypeSection() {
    Color memberColor;
    IconData memberIcon;

    switch (memberType) {
      case 'Premium':
        memberColor = Colors.amber[700]!;
        memberIcon = Icons.workspace_premium_rounded;
        break;
      case 'Gold':
        memberColor = Colors.amber;
        memberIcon = Icons.star_rounded;
        break;
      case 'Platinum':
        memberColor = Colors.blueGrey;
        memberIcon = Icons.diamond_rounded;
        break;
      default:
        memberColor = Colors.grey;
        memberIcon = Icons.person_rounded;
    }

    return Container(
      margin: EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            memberColor.withOpacity(0.95),
            Color.lerp(memberColor, Colors.black, 0.2)!,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: memberColor.withOpacity(0.25),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  memberIcon,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$memberType Member',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      _getMemberBenefits(memberType),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _getMemberBenefitList(memberType)
                .map(
                  (benefit) => Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      benefit,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  _activePackageName == null
                      ? 'You are currently on the $memberType membership.'
                      : 'Current package: $_activePackageName',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 12,
                  ),
                ),
              ),
              SizedBox(width: 12),
              ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => SubscriptionPage()),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: memberColor,
                  elevation: 0,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                child: Text(
                  memberType == 'Free' ? 'Upgrade' : 'Change Plan',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _getMemberBenefits(String type) {
    return _getMemberBenefitList(type).join(', ');
  }

  List<String> _getMemberBenefitList(String type) {
    switch (type) {
      case 'Premium':
        return ['Unlimited Chats', 'Profile Boost', 'Verified Badge'];
      case 'Gold':
        return ['Priority Listing', 'Advanced Search', 'Better Visibility'];
      case 'Platinum':
        return ['All Features', 'Personal Matchmaking', 'Priority Support'];
      default:
        return ['Basic Features', 'Standard Visibility'];
    }
  }

  Widget _buildInfoBadge(String text, IconData icon) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 14),
          SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderMetric(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Column(
        children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withOpacity(0.75),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  _CompletionAudit _buildCompletionAudit({
    required Map<String, dynamic> personalDetail,
    required Map<String, dynamic> familyDetail,
    required Map<String, dynamic> lifestyle,
    required Map<String, dynamic> partner,
  }) {
    final gallery = _galleryItems();
    final galleryApprovedCount = gallery
        .where((g) => _stringValue(g['status']).toLowerCase() == 'approved')
        .length;
    final profilePhotoUploaded = !_isMissing(personalDetail['profile_picture']);
    final profilePhotoApproved =
        _isApprovedLikeStatus(personalDetail['profilePhotoStatus']);
    final documentUploaded =
        _stringValue(_docStatus).toLowerCase() != UserState.statusNotUploaded;
    final documentVerified = isProfileVerified;

    final sectionProgress = <_CompletionSectionProgress>[
      _CompletionSectionProgress(
        title: 'Basic details',
        helperText: 'Complete your core personal information.',
        icon: Icons.person_outline_rounded,
        onTap: _editBasicInfo,
        completedCount: _countFilledFields([
          personalDetail['firstName'],
          personalDetail['lastName'],
          personalDetail['birthDate'],
          personalDetail['height_name'],
          personalDetail['maritalStatusName'],
          personalDetail['motherTongue'],
          personalDetail['city'],
          personalDetail['country'],
        ]),
        totalCount: 8,
      ),
      _CompletionSectionProgress(
        title: 'Photos',
        helperText:
            'Track profile photo upload/approval and gallery upload/approval.',
        icon: Icons.photo_library_outlined,
        onTap: () => _pickAndUploadGalleryPhotos(),
        completedCount: [
          profilePhotoUploaded,
          profilePhotoApproved,
          gallery.length >= 1,
          gallery.length >= 2,
          galleryApprovedCount > 0,
        ].where((filled) => filled).length,
        totalCount: 5,
      ),
      _CompletionSectionProgress(
        title: 'Document verification',
        helperText: 'Upload required documents and wait for admin approval.',
        icon: Icons.verified_user_outlined,
        onTap: () => _openEditPage(const IDVerificationScreen()),
        completedCount: [
          documentUploaded,
          documentVerified,
        ].where((filled) => filled).length,
        totalCount: 2,
      ),
      _CompletionSectionProgress(
        title: 'About you',
        helperText: 'A short introduction makes your profile stronger.',
        icon: Icons.auto_awesome_rounded,
        onTap: () => _editAboutMe(
          context,
          _firstFilled([
            personalDetail['aboutMe'],
            _generateAboutMe(personalDetail, lifestyle, familyDetail),
          ]),
        ),
        completedCount: _countFilledFields([personalDetail['aboutMe']]),
        totalCount: 1,
      ),
      _CompletionSectionProgress(
        title: 'Professional details',
        helperText: 'Education and work details improve profile trust.',
        icon: Icons.work_outline_rounded,
        onTap: _editProfessionalDetails,
        completedCount: _countFilledFields([
          personalDetail['degree'],
          personalDetail['faculty'],
          personalDetail['designation'],
          personalDetail['companyname'],
          personalDetail['annualincome'],
        ]),
        totalCount: 5,
      ),
      _CompletionSectionProgress(
        title: 'Community details',
        helperText: 'Religion and community details help matching accuracy.',
        icon: Icons.account_balance_outlined,
        onTap: _editCommunityDetails,
        completedCount: _countFilledFields([
          personalDetail['religionName'],
          personalDetail['communityName'],
          personalDetail['motherTongue'],
        ]),
        totalCount: 3,
      ),
      _CompletionSectionProgress(
        title: 'Lifestyle',
        helperText: 'Lifestyle answers help others understand you faster.',
        icon: Icons.spa_outlined,
        onTap: _editLifestyle,
        completedCount: _countFilledFields([
          lifestyle['diet'],
          lifestyle['smoke'],
          lifestyle['drinks'],
        ]),
        totalCount: 3,
      ),
      _CompletionSectionProgress(
        title: 'Family details',
        helperText: 'Family information is still incomplete.',
        icon: Icons.family_restroom_rounded,
        onTap: _editFamilyDetails,
        completedCount: _countFilledFields([
          familyDetail['familytype'],
          familyDetail['familybackground'],
          familyDetail['familyorigin'],
          familyDetail['fatheroccupation'],
          familyDetail['motheroccupation'],
        ]),
        totalCount: 5,
      ),
      _CompletionSectionProgress(
        title: 'Partner preference',
        helperText: 'Set your expected match preferences.',
        icon: Icons.favorite_border_rounded,
        onTap: _editPartnerPreferences,
        completedCount: _countFilledFields([
          partner['minage'],
          partner['maxage'],
          partner['maritalstatus'],
          partner['religion'],
          partner['qualification'],
          partner['proffession'],
        ]),
        totalCount: 6,
      ),
    ];

    final totalCount = sectionProgress.fold<int>(
      0,
      (sum, section) => sum + section.totalCount,
    );
    final completedCount = sectionProgress.fold<int>(
      0,
      (sum, section) => sum + section.completedCount,
    );
    final completionValue =
        totalCount == 0 ? 0 : ((completedCount / totalCount) * 100).round();
    final completion = completionValue < 0
        ? 0
        : (completionValue > 100 ? 100 : completionValue);
    final reminders = sectionProgress
        .where((section) => !section.isComplete)
        .map(
          (section) => _ProfileReminder(
            title: section.title,
            subtitle:
                '${section.remainingCount} of ${section.totalCount} checkpoints pending. ${section.helperText}',
            icon: section.icon,
            onTap: section.onTap,
            completedCount: section.completedCount,
            totalCount: section.totalCount,
          ),
        )
        .toList();

    return _CompletionAudit(
      completion: completion,
      completedCount: completedCount,
      totalCount: totalCount,
      reminders: reminders,
    );
  }

  // API responses currently use a mix of placeholder values for unset marital
  // status, so keep them grouped here and avoid showing a false document prompt.
  static const Set<String> _maritalStatusesWithoutRequiredDocument = {
    '',
    'married',
    'still unmarried',
    'unmarried',
    'not specified',
    'not available',
    'n/a',
    'na',
  };

  String _normalizeMaritalStatusValue(dynamic maritalStatus) {
    return maritalStatus?.toString().trim().toLowerCase() ?? '';
  }

  bool _requiresMaritalStatusDocument(dynamic maritalStatus) {
    final normalizedStatus = _normalizeMaritalStatusValue(maritalStatus);
    if (normalizedStatus.isEmpty) {
      return false;
    }
    return !_maritalStatusesWithoutRequiredDocument.contains(normalizedStatus);
  }

  Widget _buildCompletionSection({
    required Map<String, dynamic> personalDetail,
    required Map<String, dynamic> familyDetail,
    required Map<String, dynamic> lifestyle,
    required Map<String, dynamic> partner,
  }) {
    final audit = _buildCompletionAudit(
      personalDetail: personalDetail,
      familyDetail: familyDetail,
      lifestyle: lifestyle,
      partner: partner,
    );
    if (audit.completion >= 100) {
      return const SizedBox.shrink();
    }
    final nextStep = audit.reminders.isNotEmpty ? audit.reminders.first : null;
    final extraReminders = audit.reminders.length > 1
        ? audit.reminders.skip(1).take(2).toList()
        : const <_ProfileReminder>[];
    final hiddenReminderCount =
        audit.reminders.length > 3 ? audit.reminders.length - 3 : 0;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF90E18).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.task_alt_rounded,
                  color: Color(0xFFF90E18),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Profile completion',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${audit.reminders.length} section${audit.reminders.length > 1 ? 's are' : ' is'} still incomplete.',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${audit.completion}%',
                style: const TextStyle(
                  color: Color(0xFFF90E18),
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          if (nextStep != null) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF4F4),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                    color: const Color(0xFFF90E18).withOpacity(0.12)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(nextStep.icon,
                        color: const Color(0xFFF90E18), size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Next best step',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFF90E18),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          nextStep.title,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1A1A2E),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          nextStep.subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.35,
                            color: Colors.grey[700],
                          ),
                        ),
                        const SizedBox(height: 8),
                        _buildCompletionProgressBadge(nextStep),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  InkWell(
                    onTap: nextStep.onTap,
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF90E18),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'Continue',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              minHeight: 10,
              value: audit.completion / 100,
              backgroundColor: const Color(0xFFF5D8DA),
              valueColor: const AlwaysStoppedAnimation(Color(0xFFF90E18)),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _buildCompletionStatTile(
                  label: 'Done',
                  value: '${audit.completedCount}',
                  icon: Icons.check_circle_outline_rounded,
                  tint: const Color(0xFFE8F5E9),
                  iconColor: const Color(0xFF2E7D32),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildCompletionStatTile(
                  label: 'Remaining',
                  value: '${audit.totalCount - audit.completedCount}',
                  icon: Icons.pending_actions_rounded,
                  tint: const Color(0xFFFFF3E0),
                  iconColor: const Color(0xFFE65100),
                ),
              ),
            ],
          ),
          if (extraReminders.isNotEmpty) ...[
            const SizedBox(height: 16),
            ...extraReminders.map(
              (reminder) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F9FD),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFFF90E18).withOpacity(0.1),
                    child: Icon(reminder.icon, color: const Color(0xFFF90E18)),
                  ),
                  title: Text(
                    reminder.title,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 3),
                      _buildCompletionProgressBadge(reminder),
                      const SizedBox(height: 6),
                      Text(
                        reminder.subtitle,
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios_rounded,
                      size: 16, color: Color(0xFFF90E18)),
                  onTap: reminder.onTap,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                ),
              ),
            ),
          ],
          if (hiddenReminderCount > 0) ...[
            const SizedBox(height: 2),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F9FD),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                '$hiddenReminderCount more section${hiddenReminderCount > 1 ? 's need' : ' needs'} attention as you continue updating your profile.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[700],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCompletionStatTile({
    required String label,
    required String value,
    required IconData icon,
    required Color tint,
    required Color iconColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: iconColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Colors.grey[700],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompletionProgressBadge(_ProfileReminder reminder) {
    final remaining = reminder.totalCount - reminder.completedCount;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '${reminder.completedCount}/${reminder.totalCount} completed · $remaining left',
        style: const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: Color(0xFFF90E18),
        ),
      ),
    );
  }

  Widget _buildSectionAction({required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.primary, AppColors.primaryDark],
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.edit_outlined, color: Colors.white, size: 13),
            SizedBox(width: 4),
            Text(
              'Edit',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionValueCard({
    required String label,
    required String value,
    required IconData icon,
  }) {
    // Kept for backward compatibility; prefer _buildInfoRow for new rows.
    return _buildInfoRow(label, value);
  }

  Widget _buildInfoRow(String label, String value) {
    final missing = _isMissing(value);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 6,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: missing ? Colors.grey[400] : const Color(0xFF1A1A2E),
                fontSize: 13,
                fontWeight: missing ? FontWeight.normal : FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStat(String label, String value) {
    final missing = _isMissing(value);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color:
            missing ? Colors.grey.shade50 : AppColors.primary.withOpacity(0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: missing
              ? Colors.grey.shade200
              : AppColors.primary.withOpacity(0.12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.grey[500],
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: missing ? Colors.grey[400] : const Color(0xFF1A1A2E),
              fontSize: 13,
              fontWeight: missing ? FontWeight.normal : FontWeight.w700,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _galleryItems() {
    final raw = profileData?['gallery'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Color _galleryStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return const Color(0xFF2E7D32);
      case 'rejected':
        return const Color(0xFFC62828);
      default:
        return const Color(0xFFF57F17);
    }
  }

  IconData _galleryStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return Icons.verified_rounded;
      case 'rejected':
        return Icons.cancel_rounded;
      default:
        return Icons.pending_outlined;
    }
  }

  Future<void> _pickAndUploadGalleryPhotos() async {
    if (_isUploadingGallery) return;

    final prefs = await SharedPreferences.getInstance();
    final userDataString = prefs.getString('user_data');
    if (userDataString == null) return;

    final userData = jsonDecode(userDataString);
    final userId = int.tryParse(userData['id'].toString());
    if (userId == null || userId <= 0) return;

    final picker = ImagePicker();
    final images = await picker.pickMultiImage(imageQuality: 88);
    if (images.isEmpty) return;

    await _uploadGalleryPhotos(images, userId);
  }

  Future<void> _uploadGalleryPhotos(List<XFile> images, int userId) async {
    setState(() => _isUploadingGallery = true);

    try {
      final uri = Uri.parse('${kApiBaseUrl}/Api2/upload_gallery_photo.php');
      final request = http.MultipartRequest('POST', uri)
        ..fields['userid'] = userId.toString();

      for (final image in images) {
        final bytes = await image.readAsBytes();
        if (bytes.length > (8 * 1024 * 1024)) {
          continue;
        }
        request.files.add(
          http.MultipartFile.fromBytes(
            'gallery_photos[]',
            bytes,
            filename: image.name,
          ),
        );
      }

      if (request.files.isEmpty) {
        throw 'No valid images selected. Max size is 8MB per photo.';
      }

      final response = await request.send();
      final body = await response.stream.bytesToString();
      Map<String, dynamic> jsonBody;
      try {
        final parsed = jsonDecode(body);
        if (parsed is! Map<String, dynamic>) {
          throw const FormatException('Unexpected response shape');
        }
        jsonBody = parsed;
      } catch (_) {
        final statusText = response.statusCode > 0
            ? 'HTTP ${response.statusCode}'
            : 'Unknown server response';
        throw '$statusText: Server returned invalid response format.';
      }

      if (response.statusCode != 200 || jsonBody['status'] != 'success') {
        throw jsonBody['message']?.toString() ?? 'Upload failed';
      }

      await fetchProfileData();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Gallery uploaded. Waiting for admin approval.'),
          backgroundColor: const Color(0xFFD32F2F),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gallery upload failed: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isUploadingGallery = false);
      }
    }
  }

  Future<void> _replaceGalleryPhoto(int galleryId) async {
    if (_galleryActionInProgress.contains(galleryId)) return;

    final prefs = await SharedPreferences.getInstance();
    final userDataString = prefs.getString('user_data');
    if (userDataString == null) return;
    final userData = jsonDecode(userDataString);
    final userId = int.tryParse(userData['id'].toString());
    if (userId == null || userId <= 0) return;

    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 88,
    );
    if (image == null) return;

    setState(() => _galleryActionInProgress.add(galleryId));
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${kApiBaseUrl}/Api2/replace_gallery_photo.php'),
      )
        ..fields['userid'] = userId.toString()
        ..fields['gallery_id'] = galleryId.toString();

      final bytes = await image.readAsBytes();
      if (bytes.length > (8 * 1024 * 1024)) {
        throw 'Image too large. Max size is 8MB.';
      }

      request.files.add(
        http.MultipartFile.fromBytes(
          'gallery_photo',
          bytes,
          filename: image.name,
        ),
      );

      final response = await request.send();
      final body = await response.stream.bytesToString();
      final decoded = jsonDecode(body);
      if (response.statusCode != 200 || decoded['status'] != 'success') {
        throw decoded['message']?.toString() ?? 'Failed to replace photo';
      }

      await fetchProfileData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Photo replaced. Waiting for admin approval.'),
          backgroundColor: Color(0xFFD32F2F),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Replace failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _galleryActionInProgress.remove(galleryId));
      }
    }
  }

  Future<void> _deleteGalleryPhoto(int galleryId) async {
    if (_galleryActionInProgress.contains(galleryId)) return;

    final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete Photo'),
            content: const Text('Do you want to delete this gallery photo?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirm) return;

    final prefs = await SharedPreferences.getInstance();
    final userDataString = prefs.getString('user_data');
    if (userDataString == null) return;
    final userData = jsonDecode(userDataString);
    final userId = int.tryParse(userData['id'].toString());
    if (userId == null || userId <= 0) return;

    setState(() => _galleryActionInProgress.add(galleryId));
    try {
      final response = await http.post(
        Uri.parse('${kApiBaseUrl}/Api2/delete_gallery_photo.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userid': userId,
          'gallery_id': galleryId,
        }),
      );

      final decoded = jsonDecode(response.body);
      if (response.statusCode != 200 || decoded['status'] != 'success') {
        throw decoded['message']?.toString() ?? 'Failed to delete photo';
      }

      await fetchProfileData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Gallery photo deleted successfully.'),
          backgroundColor: Color(0xFFD32F2F),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Delete failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _galleryActionInProgress.remove(galleryId));
      }
    }
  }

  Widget _buildGallerySection() {
    final gallery = _galleryItems();
    final pendingCount = gallery
        .where(
            (g) => (g['status']?.toString().toLowerCase() ?? '') == 'pending')
        .length;
    final approvedCount = gallery
        .where(
            (g) => (g['status']?.toString().toLowerCase() ?? '') == 'approved')
        .length;
    final rejectedCount = gallery
        .where(
            (g) => (g['status']?.toString().toLowerCase() ?? '') == 'rejected')
        .length;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            decoration: BoxDecoration(
              color: const Color(0xFFD32F2F).withOpacity(0.04),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
              border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFD32F2F), Color(0xFFEF5350)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.photo_library_rounded,
                      color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'My Gallery',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A1A2E),
                        ),
                      ),
                      Text(
                        gallery.isEmpty
                            ? 'No photos added yet'
                            : '${gallery.length} photo${gallery.length > 1 ? 's' : ''}'
                                '  ·  $approvedCount ✓'
                                '${pendingCount > 0 ? '  ·  $pendingCount ⏳' : ''}'
                                '${rejectedCount > 0 ? '  ·  $rejectedCount ✗' : ''}',
                        style: TextStyle(color: Colors.grey[500], fontSize: 11),
                      ),
                      if (gallery.length > 1)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            'Swipe sideways to view and manage all photos',
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 10.5,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                // Upload button
                GestureDetector(
                  onTap:
                      _isUploadingGallery ? null : _pickAndUploadGalleryPhotos,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      gradient: _isUploadingGallery
                          ? null
                          : const LinearGradient(
                              colors: [Color(0xFFD32F2F), Color(0xFFEF5350)],
                            ),
                      color: _isUploadingGallery ? Colors.grey.shade300 : null,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_isUploadingGallery)
                          const SizedBox(
                            width: 13,
                            height: 13,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        else
                          const Icon(Icons.add_photo_alternate_rounded,
                              color: Colors.white, size: 15),
                        const SizedBox(width: 5),
                        Text(
                          _isUploadingGallery ? 'Uploading…' : 'Add Photos',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Pending warning ──────────────────────────────────────────
          if (pendingCount > 0)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: const Color(0xFFFFA000).withOpacity(0.35)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.schedule_rounded,
                      color: Color(0xFFE65100), size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$pendingCount photo${pendingCount > 1 ? 's are' : ' is'} awaiting admin approval and won\'t appear publicly until approved.',
                      style: const TextStyle(
                        color: Color(0xFFE65100),
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // ── Compact horizontal gallery / empty state ─────────────────
          Padding(
            padding: const EdgeInsets.all(16),
            child: gallery.isEmpty
                ? GestureDetector(
                    onTap: _isUploadingGallery
                        ? null
                        : _pickAndUploadGalleryPhotos,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 36),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFAFAFC),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFFD32F2F).withOpacity(0.22),
                        ),
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              color: const Color(0xFFD32F2F).withOpacity(0.07),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.add_photo_alternate_rounded,
                              color: Color(0xFFD32F2F),
                              size: 28,
                            ),
                          ),
                          const SizedBox(height: 14),
                          const Text(
                            'Tap to add your first photo',
                            style: TextStyle(
                              color: Color(0xFF1A1A2E),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            'Photos become visible after admin approval',
                            style: TextStyle(
                                color: Colors.grey[500], fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  )
                : SizedBox(
                    height: 208,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      itemCount: gallery.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemBuilder: (_, i) {
                        final item = gallery[i];
                        final galleryId =
                            int.tryParse(item['id']?.toString() ?? '0') ?? 0;
                        final status = item['status']?.toString() ?? 'pending';
                        final imageUrl = item['imageurl']?.toString() ?? '';
                        final rejectReason =
                            item['reject_reason']?.toString() ?? '';
                        final isBusy =
                            _galleryActionInProgress.contains(galleryId);

                        final Color statusColor;
                        final Color statusBg;
                        final IconData statusIcon;
                        switch (status.toLowerCase()) {
                          case 'approved':
                            statusColor = const Color(0xFF2E7D32);
                            statusBg = const Color(0xFFE8F5E9);
                            statusIcon = Icons.check_circle_rounded;
                            break;
                          case 'rejected':
                            statusColor = const Color(0xFFC62828);
                            statusBg = const Color(0xFFFFEBEE);
                            statusIcon = Icons.cancel_rounded;
                            break;
                          default:
                            statusColor = const Color(0xFFE65100);
                            statusBg = const Color(0xFFFFF3E0);
                            statusIcon = Icons.schedule_rounded;
                        }

                        final cardWidth = gallery.length == 1
                            ? MediaQuery.of(context).size.width - 64
                            : 164.0;

                        return SizedBox(
                          width: cardWidth,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                imageUrl.isEmpty
                                    ? Container(
                                        color: Colors.grey.shade200,
                                        child: const Icon(
                                          Icons.image_not_supported_outlined,
                                          color: Colors.grey,
                                        ),
                                      )
                                    : Image.network(
                                        imageUrl,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Container(
                                          color: Colors.grey.shade200,
                                          child: const Icon(
                                            Icons.broken_image_outlined,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ),
                                Positioned(
                                  top: 8,
                                  left: 8,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 7,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.58),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      '${i + 1}/${gallery.length}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  bottom: 0,
                                  left: 0,
                                  right: 0,
                                  child: Container(
                                    height: 74,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.bottomCenter,
                                        end: Alignment.topCenter,
                                        colors: [
                                          Colors.black.withOpacity(0.76),
                                          Colors.transparent,
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: 8,
                                  right: 8,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: statusBg.withOpacity(0.93),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(statusIcon,
                                            color: statusColor, size: 11),
                                        const SizedBox(width: 3),
                                        Text(
                                          status.toUpperCase(),
                                          style: TextStyle(
                                            color: statusColor,
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                if (status.toLowerCase() == 'rejected' &&
                                    rejectReason.isNotEmpty)
                                  Positioned(
                                    top: 8,
                                    left: 8,
                                    right: 70,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withOpacity(0.72),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        rejectReason,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 9.5,
                                        ),
                                      ),
                                    ),
                                  ),
                                Positioned(
                                  bottom: 8,
                                  left: 8,
                                  right: 8,
                                  child: isBusy
                                      ? const Center(
                                          child: SizedBox(
                                            width: 22,
                                            height: 22,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          ),
                                        )
                                      : Row(
                                          children: [
                                            Expanded(
                                              child: GestureDetector(
                                                onTap: galleryId > 0
                                                    ? () =>
                                                        _replaceGalleryPhoto(
                                                          galleryId,
                                                        )
                                                    : null,
                                                child: Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                    vertical: 7,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.white
                                                        .withOpacity(0.92),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            9),
                                                  ),
                                                  child: const Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .center,
                                                    children: [
                                                      Icon(
                                                        Icons.edit_rounded,
                                                        size: 13,
                                                        color:
                                                            Color(0xFF1A1A2E),
                                                      ),
                                                      SizedBox(width: 3),
                                                      Text(
                                                        'Change',
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color:
                                                              Color(0xFF1A1A2E),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            GestureDetector(
                                              onTap: galleryId > 0
                                                  ? () => _deleteGalleryPhoto(
                                                        galleryId,
                                                      )
                                                  : null,
                                              child: Container(
                                                width: 34,
                                                height: 34,
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFD32F2F)
                                                      .withOpacity(0.9),
                                                  borderRadius:
                                                      BorderRadius.circular(9),
                                                ),
                                                child: const Icon(
                                                  Icons.delete_outline_rounded,
                                                  size: 16,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
          if (gallery.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F9FD),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Icon(Icons.swipe_rounded,
                        size: 15, color: Colors.grey.shade600),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Swipe left or right to quickly review all gallery photos.',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.grey[700],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAboutMe(
    Map<String, dynamic> personalDetail,
    Map<String, dynamic> lifestyle,
    Map<String, dynamic> familyDetail,
  ) {
    final savedAbout = _stringValue(personalDetail['aboutMe']);
    final generatedAbout =
        _generateAboutMe(personalDetail, lifestyle, familyDetail);
    final showGenerated = savedAbout.isEmpty && generatedAbout.isNotEmpty;

    return _buildSection(
      title: 'About Me',
      icon: Icons.auto_awesome_rounded,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            showGenerated
                ? generatedAbout
                : _displayValue(savedAbout,
                    fallback: 'No information provided'),
            style: TextStyle(
              color: Colors.grey[700],
              fontSize: 14,
              height: 1.5,
            ),
          ),
          if (showGenerated) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF90E18).withOpacity(0.06),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Auto-generated from your filled profile data',
                    style: TextStyle(
                      color: Color(0xFFF90E18),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'You can use this text now and edit it later anytime.',
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: generatedAbout.isEmpty
                        ? null
                        : () => _saveAboutMe(generatedAbout),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF90E18),
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Use auto-generated About'),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
      onEdit: () => _editAboutMe(
        context,
        savedAbout.isEmpty ? generatedAbout : savedAbout,
      ),
    );
  }

  String _generateAboutMe(
    Map<String, dynamic> personalDetail,
    Map<String, dynamic> lifestyle,
    Map<String, dynamic> familyDetail,
  ) {
    final name = _joinNonEmpty([
      _firstFilled([personalDetail['firstName']]),
      _firstFilled([personalDetail['lastName']]),
    ], separator: ' ');
    final age = _calculateAge(personalDetail['birthDate']);
    final location = _joinNonEmpty([
      _firstFilled([personalDetail['city']]),
      _firstFilled([personalDetail['country']]),
    ]);
    final profession = _firstFilled([personalDetail['designation']]);
    final company = _firstFilled([personalDetail['companyname']]);
    final education = _firstFilled([personalDetail['degree']]);
    final religion = _firstFilled([personalDetail['religionName']]);
    final community = _firstFilled([personalDetail['communityName']]);
    final diet = _firstFilled([lifestyle['diet']]);
    final familyOrigin = _firstFilled([familyDetail['familyorigin']]);
    final familyBackground = _firstFilled([familyDetail['familybackground']]);

    final sentences = <String>[];

    final introBits = <String>[];
    if (name.isNotEmpty) {
      introBits.add(name);
    }
    if (age > 0) {
      introBits.add('$age years old');
    }
    if (location.isNotEmpty) {
      introBits.add('based in $location');
    }
    if (introBits.isNotEmpty) {
      sentences.add('I am ${introBits.join(', ')}.');
    }

    final workBits = <String>[];
    if (profession.isNotEmpty) {
      workBits.add('working as $profession');
    }
    if (company.isNotEmpty) {
      workBits.add('at $company');
    }
    if (education.isNotEmpty) {
      workBits.add('with $education');
    }
    if (workBits.isNotEmpty) {
      sentences.add('Professionally, I am ${workBits.join(' ')}.');
    }

    final personalBits = <String>[];
    if (religion.isNotEmpty) {
      personalBits.add(religion);
    }
    if (community.isNotEmpty) {
      personalBits.add(community);
    }
    if (diet.isNotEmpty) {
      personalBits.add('$diet lifestyle');
    }
    if (personalBits.isNotEmpty) {
      sentences.add('My background reflects ${personalBits.join(', ')}.');
    }

    final familyBits = <String>[];
    if (familyBackground.isNotEmpty) {
      familyBits.add(familyBackground);
    }
    if (familyOrigin.isNotEmpty) {
      familyBits.add('roots in $familyOrigin');
    }
    if (familyBits.isNotEmpty) {
      sentences.add(
          'Family is important to me and I value ${familyBits.join(' with ')}.');
    }

    return sentences.join(' ').trim();
  }

  Widget _buildLockedDetailRow(String label, String value) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 4,
                child: Text(
                  label,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 6,
                child: Row(
                  children: [
                    const Icon(
                      Icons.lock,
                      size: 14,
                      color: Color(0xFF2E7D32),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        value,
                        style: const TextStyle(
                          color: Color(0xFF1A1A2E),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, thickness: 0.5, color: Colors.grey.shade100),
      ],
    );
  }

  Widget _buildPersonalDetails(
    Map<String, dynamic> personalDetail,
  ) {
    final model = context.read<SignupModel>();
    final isVerified = context.read<UserState>().isVerified;

    return _buildSection(
      title: 'Personal Details',
      icon: Icons.person_outline,
      content: Column(
        children: [
          // Basic Personal Information
          if (isVerified) ...[
            _buildLockedDetailRow(
              'Full Name',
              '${_displayValue(personalDetail['firstName'], fallback: '')} ${_displayValue(personalDetail['lastName'], fallback: '')}'
                  .trim(),
            ),
            _buildLockedDetailRow(
                'Date of Birth', _formatDate(personalDetail['birthDate'])),
            _buildLockedDetailRow(
                'Age', '${_calculateAge(personalDetail['birthDate'])} Years'),
            _buildLockedDetailRow(
              'Email',
              _displayValue(model.email,
                  fallback: personalDetail['email']?.toString() ??
                      _userEmail ??
                      'N/A'),
            ),
            _buildLockedDetailRow(
              'Phone Number',
              _displayValue(model.contactNo,
                  fallback: personalDetail['contactNo']?.toString() ??
                      _userPhone ??
                      'N/A'),
            ),
            _buildLockedDetailRow('Marital Status',
                _displayValue(personalDetail['maritalStatusName'])),
          ] else ...[
            _buildDetailRow('Full Name',
                '${_displayValue(personalDetail['firstName'], fallback: '')} ${_displayValue(personalDetail['lastName'], fallback: '')}'),
            _buildDetailRow(
                'Date of Birth', _formatDate(personalDetail['birthDate'])),
            _buildDetailRow(
                'Age', '${_calculateAge(personalDetail['birthDate'])} Years'),
            _buildDetailRow(
                'Gender',
                _displayValue(
                    _firstFilled([personalDetail['gender'], model.gender]))),
            _buildDetailRow('Marital Status',
                _displayValue(personalDetail['maritalStatusName'])),
          ],

          // Physical Attributes
          _buildDetailRow(
              'Height', _displayValue(personalDetail['height_name'])),
          if (!_isMissing(personalDetail['weight_name']))
            _buildDetailRow(
                'Weight', _displayValue(personalDetail['weight_name'])),
          _buildDetailRow(
              'Blood Group', _displayValue(personalDetail['bloodGroup'])),
          if (!_isMissing(personalDetail['complexion']))
            _buildDetailRow(
                'Complexion', _displayValue(personalDetail['complexion'])),
          if (!_isMissing(personalDetail['bodyType']))
            _buildDetailRow(
                'Body Type', _displayValue(personalDetail['bodyType'])),

          // Health Information
          _buildDetailRow(
            'Disability',
            _displayValue(
              _firstFilled(
                  [personalDetail['disability'], personalDetail['Disability']]),
              fallback: 'None',
            ),
          ),
          if (!_isMissing(personalDetail['specs']))
            _buildDetailRow(
                'Specs/Lenses', _displayValue(personalDetail['specs'])),

          // Birth Details
          _buildDetailRow(
              'Birth Time', _displayValue(personalDetail['birthtime'])),
          _buildDetailRow(
              'Birth Place', _displayValue(personalDetail['birthcity'])),
        ],
      ),
      onEdit: () => _editPersonalDetails(),
      isLocked: _docStatus == 'approved',
    );
  }

  Widget _buildCommunityDetails(Map<String, dynamic> personalDetail) {
    return _buildSection(
      title: 'Religion & Community',
      icon: Icons.temple_hindu_outlined,
      content: Column(
        children: [
          _buildDetailRow(
              'Religion', _displayValue(personalDetail['religionName'])),
          _buildDetailRow(
              'Caste', _displayValue(personalDetail['communityName'])),
          _buildDetailRow(
              'Sub Caste', _displayValue(personalDetail['subCommunityName'])),
          _buildDetailRow(
              'Mother Tongue', _displayValue(personalDetail['motherTongue'])),
          _buildDetailRow('Manglik', _displayValue(personalDetail['manglik'])),
        ],
      ),
      onEdit: () => _editCommunityDetails(),
    );
  }

  String _formatDate(String? dateString) {
    if (dateString == null) return 'N/A';
    try {
      DateTime date = DateTime.parse(dateString);
      return '${date.day} ${_getMonthName(date.month)} ${date.year}';
    } catch (e) {
      return dateString;
    }
  }

  String _getMonthName(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return months[month - 1];
  }

  Widget _buildProfessionalDetails(Map<String, dynamic> personalDetail) {
    return _buildSection(
      title: 'Professional Details',
      icon: Icons.work_outline,
      content: Column(
        children: [
          // Education Information
          _buildDetailRow('Education', _displayValue(personalDetail['degree'])),
          _buildDetailRow('Faculty', _displayValue(personalDetail['faculty'])),
          _buildDetailRow(
              'Education Type', _displayValue(personalDetail['educationtype'])),
          if (!_isMissing(personalDetail['educationmedium']))
            _buildDetailRow('Education Medium',
                _displayValue(personalDetail['educationmedium'])),

          // Career Information
          _buildDetailRow(
              'Occupation', _displayValue(personalDetail['designation'])),
          _buildDetailRow(
              'Employer', _displayValue(personalDetail['companyname'])),
          _buildDetailRow(
              'Working With', _displayValue(personalDetail['workingwith'])),
          _buildDetailRow(
              'Annual Income', _displayValue(personalDetail['annualincome'])),
          _buildDetailRow(
              'Work Location', _displayValue(personalDetail['city'])),
        ],
      ),
      onEdit: () => _editProfessionalDetails(),
    );
  }

  Widget _buildFamilyDetails(Map<String, dynamic> familyDetail) {
    return _buildSection(
      title: 'Family Details',
      icon: Icons.family_restroom,
      content: Column(
        children: [
          // Family Type & Background
          _buildDetailRow(
              'Family Type', _displayValue(familyDetail['familytype'])),
          _buildDetailRow(
              'Family Status', _displayValue(familyDetail['familybackground'])),
          _buildDetailRow(
              'Family Origin', _displayValue(familyDetail['familyorigin'])),

          // Father Information
          _buildDetailRow(
              'Father Name', _displayValue(familyDetail['fathername'])),
          _buildDetailRow('Father Education',
              _displayValue(familyDetail['fathereducation'])),
          _buildDetailRow('Father\'s Occupation',
              _displayValue(familyDetail['fatheroccupation'])),

          // Mother Information
          if (!_isMissing(familyDetail['mothercaste']))
            _buildDetailRow(
                'Mother Caste', _displayValue(familyDetail['mothercaste'])),
          _buildDetailRow('Mother Education',
              _displayValue(familyDetail['mothereducation'])),
          _buildDetailRow('Mother\'s Occupation',
              _displayValue(familyDetail['motheroccupation'])),
        ],
      ),
      onEdit: () => _editFamilyDetails(),
    );
  }

  void _editProfilePicture(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final userDataString = prefs.getString('user_data');
    if (userDataString == null) return;

    final userData = jsonDecode(userDataString);
    final userId = int.parse(userData['id'].toString());

    final ImagePicker picker = ImagePicker();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'Edit Profile Picture',
          style: TextStyle(color: Color(0xFFD32F2F)),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Upload a new profile picture'),
            const SizedBox(height: 20),

            /// Gallery
            ElevatedButton(
              onPressed: () async {
                final XFile? image =
                    await picker.pickImage(source: ImageSource.gallery);
                if (image != null) {
                  Navigator.pop(context);
                  await _uploadProfilePictureBackground(
                    context,
                    image,
                    userId,
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xFFD32F2F),
              ),
              child: const Text('Choose from Gallery',
                  style: TextStyle(color: Colors.white)),
            ),

            const SizedBox(height: 10),

            /// Camera
            ElevatedButton(
              onPressed: () async {
                final XFile? image =
                    await picker.pickImage(source: ImageSource.camera);
                if (image != null) {
                  Navigator.pop(context);
                  await _uploadProfilePictureBackground(
                    context,
                    image,
                    userId,
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xFFD32F2F),
              ),
              child: const Text('Take a Photo',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  Future<void> _uploadProfilePictureBackground(
      BuildContext context, XFile imageFile, int userId) async {
    try {
      // Show loading
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(width: 10),
              Text('Uploading image...'),
            ],
          ),
          backgroundColor: Color(0xFFD32F2F),
          duration: Duration(seconds: 5),
        ),
      );

      // Validate file size (max 10MB)
      final bytes = await imageFile.readAsBytes();
      final fileSizeInMB = bytes.length / (1024 * 1024);
      if (fileSizeInMB > 10) {
        throw 'File size too large. Maximum allowed size is 10MB.';
      }

      // Validate file format
      final fileName = imageFile.name.toLowerCase();
      if (!fileName.endsWith('.jpg') &&
          !fileName.endsWith('.jpeg') &&
          !fileName.endsWith('.png')) {
        throw 'Invalid file format. Only JPG, JPEG, and PNG are allowed.';
      }

      final uri = Uri.parse('${kApiBaseUrl}/Api2/profile_picture.php');
      print('Uploading to: $uri');
      print('User ID: $userId');
      print('File name: ${imageFile.name}');
      print('File size: ${fileSizeInMB.toStringAsFixed(2)} MB');

      final request = http.MultipartRequest('POST', uri)
        ..fields['userid'] = userId.toString();

      // Use bytes-based upload for both web and native for consistency
      request.files.add(http.MultipartFile.fromBytes(
        'profile_picture',
        bytes,
        filename: imageFile.name,
      ));

      print('Sending request...');
      final response = await request.send();
      final responseBody = await response.stream.bytesToString();

      print('Response status code: ${response.statusCode}');
      print('Response body: $responseBody');

      if (response.statusCode == 200) {
        // Parse response to check for success status
        try {
          final responseData = jsonDecode(responseBody);
          if (responseData['status'] == 'success') {
            // Save the exact server-generated path so all screens use the
            // same fresh image URL and don't fall back to stale hardcoded names.
            final String serverPath =
                (responseData['path']?.toString() ?? '').trim();
            if (serverPath.isNotEmpty) {
              final prefs = await SharedPreferences.getInstance();
              final rawUserData = prefs.getString('user_data');
              if (rawUserData != null && rawUserData.isNotEmpty) {
                final userData = jsonDecode(rawUserData);
                userData['profile_picture'] = serverPath;
                userData['profilePicture'] = serverPath;
                // Keep compatibility with places still reading `image`.
                userData['image'] = resolveApiImageUrl(serverPath);
                await prefs.setString('user_data', jsonEncode(userData));
              }
              // Invalidate the chat-rooms cache so the chat list re-fetches
              // fresh participantImages (including the current user's updated
              // photo) instead of serving the stale cached room data.
              final uid = _userId ?? '';
              if (uid.isNotEmpty) {
                await prefs.remove('chat_rooms_cache_$uid');
              }
            }

            // Update timestamp to refresh image and mark as pending approval
            setState(() {
              _profilePictureTimestamp = DateTime.now().millisecondsSinceEpoch;
              _profilePhotoStatus = 'pending';
            });

            // Refresh profile data
            await fetchProfileData();

            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Profile picture updated successfully'),
                backgroundColor: Color(0xFFD32F2F),
              ),
            );
          } else {
            // Server returned error in response
            final errorMsg =
                responseData['message'] ?? 'Unknown error occurred';
            throw 'Server error: $errorMsg';
          }
        } catch (jsonError) {
          print('Error parsing response: $jsonError');
          throw 'Invalid server response: $responseBody';
        }
      } else {
        // Non-200 status code
        throw 'Server returned error ${response.statusCode}: $responseBody';
      }
    } catch (e) {
      print('Upload error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Upload failed: $e'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 5),
        ),
      );
    }
  }

  void _editBasicInfo() {
    _openEditPage(
      PersonalDetailsPage(
        isEditMode: true,
        initialData: _asMap(profileData?['personalDetail']),
      ),
      onReturn: _refreshPersonalSection,
    );
  }

  Future<bool> _saveAboutMe(String aboutMe) async {
    final prefs = await SharedPreferences.getInstance();
    final userDataString = prefs.getString('user_data');
    final userData = jsonDecode(userDataString!);
    final userId = int.tryParse(userData["id"].toString());

    try {
      final response = await http.post(
        Uri.parse("${kApiBaseUrl}/Api2/aboutme.php"),
        body: {
          "userid": userId.toString(),
          "aboutMe": aboutMe.trim(),
        },
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to update About Me');
      }

      setState(() {
        if (profileData != null && profileData!['personalDetail'] != null) {
          profileData!['personalDetail']['aboutMe'] = aboutMe.trim();
        }
      });

      await fetchProfileData();

      if (!mounted) return true;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('About Me updated successfully!'),
          backgroundColor: Color(0xFFD32F2F),
        ),
      );
      return true;
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    }
  }

  Future<void> _editAboutMe(BuildContext context, String currentAboutMe) async {
    final TextEditingController _controller =
        TextEditingController(text: currentAboutMe);
    bool isSaving = false;

    try {
      await showDialog(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: Text(
                "Edit About Me",
                style: TextStyle(color: Color(0xFFD32F2F)),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text("Update your about me information"),
                    SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: Icon(Icons.auto_awesome,
                            color: Color(0xFFD32F2F), size: 18),
                        label: Text(
                          'Auto Generate Your About Me',
                          style:
                              TextStyle(color: Color(0xFFD32F2F), fontSize: 13),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: Color(0xFFD32F2F)),
                          padding: EdgeInsets.symmetric(
                              vertical: 10, horizontal: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: () {
                          final pd = _asMap(profileData?['personalDetail']);
                          final lf = _asMap(profileData?['lifestyle']);
                          final fd = _asMap(profileData?['familyDetail']);
                          final generated = _generateAboutMe(pd, lf, fd);
                          if (generated.isNotEmpty) {
                            setStateDialog(() {
                              _controller.text = generated;
                            });
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Please fill in more profile details to auto-generate.',
                                ),
                                backgroundColor: Colors.orange,
                              ),
                            );
                          }
                        },
                      ),
                    ),
                    SizedBox(height: 12),
                    TextFormField(
                      controller: _controller,
                      decoration: InputDecoration(
                        labelText: "About Me",
                        border: OutlineInputBorder(),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFFD32F2F)),
                        ),
                      ),
                      maxLines: 5,
                      maxLength: 500,
                    ),
                    if (isSaving)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child:
                            CircularProgressIndicator(color: Color(0xFFD32F2F)),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.pop(context),
                  child: Text('Cancel', style: TextStyle(color: Colors.grey)),
                ),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFFD32F2F), Color(0xFFEF5350)],
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: TextButton(
                    onPressed: isSaving
                        ? null
                        : () async {
                            if (_controller.text.trim().isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Please enter some text'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                              return;
                            }

                            setStateDialog(() {
                              isSaving = true;
                            });

                            final saved =
                                await _saveAboutMe(_controller.text.trim());
                            if (!mounted) return;
                            if (saved) {
                              Navigator.pop(context);
                            } else {
                              setStateDialog(() {
                                isSaving = false;
                              });
                            }
                          },
                    child: Text('Save', style: TextStyle(color: Colors.white)),
                  ),
                ),
              ],
            );
          },
        ),
      );
    } finally {
      _controller.dispose();
    }
  }

  void _editPersonalDetails() {
    // Pass verification status directly to edit screen - no confirmation dialog
    // The edit screen will handle locking verified fields with visual indicators
    _openEditPage(
      PersonalDetailsPage(
        isEditMode: true,
        initialData: _asMap(profileData?['personalDetail']),
        isVerified: context.read<UserState>().isVerified,
      ),
      onReturn: _refreshPersonalSection,
    );
  }

  void _editCommunityDetails() {
    _openEditPage(
      CommunityDetailsPage(
        isEditMode: true,
        initialData: _asMap(profileData?['personalDetail']),
      ),
      onReturn: fetchProfileData,
    );
  }

  void _editProfessionalDetails() {
    _openEditPage(
      EducationCareerPage(
        isEditMode: true,
        initialData: _asMap(profileData?['personalDetail']),
      ),
      onReturn: _refreshProfessionalSection,
    );
  }

  void _editFamilyDetails() {
    _openEditPage(
      FamilyDetailsPage(
        isEditMode: true,
        initialData: _asMap(profileData?['familyDetail']),
      ),
      onReturn: _refreshFamilySection,
    );
  }

  void _editLifestyle() {
    _openEditPage(
      LifestylePage(
        isEditMode: true,
        initialData: _asMap(profileData?['lifestyle']),
      ),
      onReturn: _refreshLifestyleSection,
    );
  }

  void _editPartnerPreferences() {
    _openEditPage(
      const PartnerPreferencesPage(isEditMode: true),
      onReturn: _refreshPartnerSection,
    );
  }

  void _upgradeMembership() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Upgrade Membership',
          style: TextStyle(color: Color(0xFFD32F2F)),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildMembershipOption(
                  'Free', '👤', 'Basic Features', 'Rs0/month', false),
              SizedBox(height: 10),
              _buildMembershipOption('Premium', '👑',
                  'Unlimited Chats + Profile Boost', 'Rs999/month', true),
              SizedBox(height: 10),
              _buildMembershipOption('Gold', '⭐',
                  'Priority Listing + Advanced Search', 'Rs1,999/month', false),
              SizedBox(height: 10),
              _buildMembershipOption(
                  'Platinum',
                  '💎',
                  'All Features + Personal Matchmaking',
                  'rs2,999/month',
                  false),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  Widget _buildMembershipOption(
      String name, String icon, String features, String price, bool isPopular) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(
          color: isPopular ? Color(0xFFD32F2F) : Colors.grey[300]!,
          width: isPopular ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(icon, style: TextStyle(fontSize: 24)),
                  SizedBox(width: 10),
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              if (isPopular)
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Color(0xFFD32F2F),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'POPULAR',
                    style: TextStyle(color: Colors.white, fontSize: 10),
                  ),
                ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            features,
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
          SizedBox(height: 8),
          Text(
            price,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFFD32F2F),
            ),
          ),
          SizedBox(height: 8),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: isPopular
                  ? LinearGradient(
                      colors: [Color(0xFFD32F2F), Color(0xFFEF5350)],
                    )
                  : null,
              color: isPopular ? null : Colors.grey[100],
              borderRadius: BorderRadius.circular(20),
            ),
            child: TextButton(
              onPressed: () {
                setState(() {
                  memberType = name;
                });
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Upgraded to $name Membership!'),
                    backgroundColor: Color(0xFFD32F2F),
                  ),
                );
              },
              child: Text(
                memberType == name ? 'CURRENT PLAN' : 'UPGRADE',
                style: TextStyle(
                  color: isPopular ? Colors.white : Colors.grey[700],
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Column(
      children: [
        _buildInfoRow(label, value),
        Divider(height: 1, thickness: 0.5, color: Colors.grey.shade100),
      ],
    );
  }

  Widget _buildChip(String text, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 15),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: color.withOpacity(0.9),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(String title, String description) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          title,
          style: TextStyle(color: Color(0xFFD32F2F)),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(description),
            SizedBox(height: 20),
            TextFormField(
              decoration: InputDecoration(
                labelText: title ?? "Enter Your details",
                border: OutlineInputBorder(),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFFD32F2F)),
                ),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFD32F2F), Color(0xFFEF5350)],
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: TextButton(
              onPressed: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('$title updated successfully!'),
                    backgroundColor: Color(0xFFD32F2F),
                  ),
                );
              },
              child: Text('Save', style: TextStyle(color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLifestyle(Map<String, dynamic> lifestyle) {
    final List<Widget> habitChips = [];

    if (lifestyle['smoke'] == 'Yes') {
      habitChips.add(_buildChip(
        'Smoker${_isMissing(lifestyle['smoketype']) ? '' : ' (${lifestyle['smoketype']})'}',
        Icons.smoking_rooms,
        Colors.orange,
      ));
    } else if (!_isMissing(lifestyle['smoke'])) {
      habitChips.add(_buildChip('Non-Smoker', Icons.smoke_free, Colors.green));
    }

    if (lifestyle['drinks'] == 'Yes') {
      habitChips.add(_buildChip(
        'Drinker${_isMissing(lifestyle['drinktype']) ? '' : ' (${lifestyle['drinktype']})'}',
        Icons.local_bar,
        Colors.deepOrange,
      ));
    } else if (!_isMissing(lifestyle['drinks'])) {
      habitChips.add(_buildChip('Non-Drinker', Icons.no_drinks, Colors.teal));
    }

    if (!_isMissing(lifestyle['diet'])) {
      final normalizedDiet = _stringValue(lifestyle['diet']).toLowerCase();
      final isVegetarian =
          normalizedDiet.contains('veg') && !normalizedDiet.contains('non');
      habitChips.add(_buildChip(
        _stringValue(lifestyle['diet']),
        isVegetarian ? Icons.eco : Icons.restaurant,
        isVegetarian ? Colors.green : Colors.deepOrange,
      ));
    }

    return _buildSection(
      title: 'Lifestyle',
      icon: Icons.self_improvement,
      content: habitChips.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No lifestyle information added yet.',
                style: TextStyle(color: Colors.grey[500], fontSize: 13),
              ),
            )
          : Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: habitChips,
              ),
            ),
      onEdit: () => _editLifestyle(),
    );
  }

  Widget _buildPartnerPreferences(Map<String, dynamic> partner) {
    final ageText =
        !_isMissing(partner['minage']) && !_isMissing(partner['maxage'])
            ? '${partner['minage']}-${partner['maxage']} Years'
            : 'Not provided';
    return _buildSection(
      title: 'Partner Preferences',
      icon: Icons.search,
      content: Column(
        children: [
          _buildPreferenceRow('Age', ageText),
          if (!_isMissing(partner['minheight']) &&
              !_isMissing(partner['maxheight']))
            _buildPreferenceRow(
                'Height', '${partner['minheight']}-${partner['maxheight']}'),
          _buildPreferenceRow(
              'Marital Status', _displayValue(partner['maritalstatus'])),
          _buildPreferenceRow('Religion', _displayValue(partner['religion'])),
          _buildPreferenceRow('Caste', _displayValue(partner['caste'])),
          if (!_isMissing(partner['community']))
            _buildPreferenceRow(
                'Community', _displayValue(partner['community'])),
          if (!_isMissing(partner['mothertongue'])) // Corrected field name
            _buildPreferenceRow(
                'Mother Tongue', _displayValue(partner['mothertongue'])),
          _buildPreferenceRow(
              'Education', _displayValue(partner['qualification'])),
          _buildPreferenceRow('Occupation',
              _displayValue(partner['profession'])), // Corrected field name
          _buildPreferenceRow('Income', _displayValue(partner['annualincome'])),
          if (!_isMissing(partner['country']))
            _buildPreferenceRow('Country', _displayValue(partner['country'])),
          if (!_isMissing(partner['state']))
            _buildPreferenceRow('State', _displayValue(partner['state'])),
          if (!_isMissing(partner['district']))
            _buildPreferenceRow('District', _displayValue(partner['district'])),
          if (!_isMissing(partner['city']))
            _buildPreferenceRow('City', _displayValue(partner['city'])),
          _buildPreferenceRow('Diet', _displayValue(partner['diet'])),
          _buildPreferenceRow(
              'Family Values', _displayValue(partner['familytype'])),
          _buildPreferenceRow(
              'Other Expectations', _displayValue(partner['otherexpectation'])),
        ],
      ),
      onEdit: () => _editPartnerPreferences(),
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required Widget content,
    required VoidCallback onEdit,
    bool isLocked = false,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.04),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
              border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: AppColors.primary, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                ),
                isLocked
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2E7D32).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: const Color(0xFF2E7D32).withOpacity(0.3),
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.lock,
                                color: Color(0xFF2E7D32), size: 13),
                            SizedBox(width: 4),
                            Text(
                              'Locked',
                              style: TextStyle(
                                color: Color(0xFF2E7D32),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      )
                    : _buildSectionAction(onTap: onEdit),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: content,
          ),
        ],
      ),
    );
  }

  Widget _buildPreferenceRow(String label, String value) {
    return Column(
      children: [
        _buildInfoRow(label, value),
        Divider(height: 1, thickness: 0.5, color: Colors.grey.shade100),
      ],
    );
  }
}

class _ProfileOfflineView extends StatelessWidget {
  const _ProfileOfflineView({
    required this.connectivityService,
    required this.isCheckingConnectivity,
    required this.onRetry,
  });

  final ConnectivityService connectivityService;
  final bool isCheckingConnectivity;
  final Future<void> Function() onRetry;

  String _message() {
    if (connectivityService.isWifiConnected) {
      return 'Wi-Fi is connected, but internet access is unavailable.';
    }

    if (connectivityService.isMobileConnected) {
      return 'Mobile data is connected, but internet access is unavailable.';
    }

    return 'Please reconnect to continue viewing your profile.';
  }

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
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: true,
        body: Container(
          width: double.infinity,
          color: const Color(0xFFD32F2F),
          child: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.wifi_off_rounded,
                      color: Colors.white,
                      size: 72,
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'No Internet',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _message(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: isCheckingConnectivity ? null : onRetry,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFFD32F2F),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 28,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                      child: isCheckingConnectivity
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Color(0xFFD32F2F),
                                ),
                              ),
                            )
                          : const Text(
                              'Retry',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileReminder {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final int completedCount;
  final int totalCount;

  _ProfileReminder({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    required this.completedCount,
    required this.totalCount,
  });
}

class _CompletionAudit {
  final int completion;
  final int completedCount;
  final int totalCount;
  final List<_ProfileReminder> reminders;

  const _CompletionAudit({
    required this.completion,
    required this.completedCount,
    required this.totalCount,
    required this.reminders,
  });
}

class _CompletionSectionProgress {
  final String title;
  final String helperText;
  final IconData icon;
  final VoidCallback onTap;
  final int completedCount;
  final int totalCount;

  const _CompletionSectionProgress({
    required this.title,
    required this.helperText,
    required this.icon,
    required this.onTap,
    required this.completedCount,
    required this.totalCount,
  });

  bool get isComplete => completedCount >= totalCount;
  int get remainingCount => totalCount - completedCount;
}
