import 'dart:io' if (dart.library.html) 'package:ms2026/utils/web_io_stub.dart';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../Auth/Screen/Edit/3edit.dart';
import '../Auth/Screen/Edit/Community.dart';
import '../Auth/Screen/Edit/edit5.dart';
import '../Auth/Screen/Edit/edit6.dart';
import '../Auth/Screen/Edit/edit7.dart';
import '../Auth/Screen/Edit/edit8.dart';
import '../Auth/Screen/marital_document_screen.dart';
import '../Auth/SuignupModel/signup_model.dart';
import '../DeleteAccount/deleteAccointScreen.dart';
import '../Package/PackageScreen.dart';
import '../Startup/onboarding.dart';
import '../constant/app_colors.dart';
import '../core/user_state.dart';
import '../service/connectivity_service.dart';
import '../otherenew/blocked_users_screen.dart';
import '../settings/settings_screen.dart';
import 'package:ms2026/config/app_endpoints.dart';

class MatrimonyProfilePage extends StatefulWidget {
  @override
  _MatrimonyProfilePageState createState() => _MatrimonyProfilePageState();
}

class _MatrimonyProfilePageState extends State<MatrimonyProfilePage> {
  static const SystemUiOverlayStyle _statusBarStyle =
      SystemUiOverlayStyle(
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
  String? _activePackageName;
  String? _activePackageExpiry;
  String _docStatus = 'not_uploaded';
  bool _docUploadSkipped = false;
  bool _isCheckingConnectivity = false;
  bool? _lastConnectivityState;
  ConnectivityService? _connectivityService;
  int? _backendProfileCompletion; // Backend-calculated completion percentage

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
          setState(() {
            profileData = data['data'];
            isProfileVerified = profileData?['personalDetail']?['isVerified'] == 1;
            memberType = _getMemberType(profileData?['personalDetail']?['usertype'] ?? 'free');
            // Store backend-calculated completion percentage
            _backendProfileCompletion = data['profileCompletion'];
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
              currentUserData =
                  jsonDecode(prefs.getString('user_data') ?? '{}') as Map<String, dynamic>;
            } catch (_) {
              currentUserData = {};
            }
            bool updated = false;
            final String? firstName = personalDetail['firstName']?.toString();
            final String? lastName = personalDetail['lastName']?.toString();
            final String? profilePic = personalDetail['profile_picture']?.toString();
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
  void _syncDocStatusFromUserState() {
    if (!mounted) return;
    try {
      final status = context.read<UserState>().identityStatus;
      final maritalStatusName =
          profileData?['personalDetail']?['maritalStatusName']?.toString() ?? '';
      final requiresDoc = _requiresMaritalStatusDocument(maritalStatusName);
      setState(() {
        _docStatus = status;
        if (requiresDoc) {
          isProfileVerified = status == 'approved';
        }
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
          _activePackageExpiry = expiry.length >= 10 ? expiry.substring(0, 10) : expiry;
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

  Future<void> _openEditPage(Widget page) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => page),
    );
    if (!mounted) return;
    await fetchProfileData();
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

    // Step 1: Fetch current privacy from API
    String currentPrivacy = 'Private';
    try {
      final Uri getUrl = Uri.parse(
          '${kApiBaseUrl}/Api3/get_privacy.php?userid=$userId');
      final response = await http.get(getUrl);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'success') {
          final privacy = data['data']['privacy']?.toString().toLowerCase();
          // Map API value to dropdown label
          switch (privacy) {
            case 'free':
              currentPrivacy = 'All Users';
              break;
            case 'paid':
              currentPrivacy = 'Premium Users Only';
              break;
            case 'verified':
              currentPrivacy = 'Verified Users Only';
              break;
            case 'private':
            default:
              currentPrivacy = 'private';
          }
        }
      }
    } catch (e) {
      print("Error fetching privacy: $e");
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
                      items: [
                        'All Users',
                        'Premium Users Only',
                        'Verified Users Only',
                        'Private'
                      ].map((String value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(value),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setStateDialog(() {
                          selectedPrivacy = value ?? 'Private';
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

                    // Step 3: Map dropdown value back to API value
                    String privacyValue = 'private';
                    switch (selectedPrivacy) {
                      case 'All Users':
                        privacyValue = 'free';
                        break;
                      case 'Premium Users Only':
                        privacyValue = 'paid';
                        break;
                      case 'Verified Users Only':
                        privacyValue = 'verified';
                        break;
                      case 'Private':
                      default:
                        privacyValue = 'private';
                    }

                    // Step 4: Call update_privacy API
                    try {
                      final Uri updateUrl = Uri.parse(
                          '${kApiBaseUrl}/Api3/privacy.php?userid=$userId&privacy=$privacyValue');
                      final response = await http.get(updateUrl);

                      if (response.statusCode == 200) {
                        final data = jsonDecode(response.body);
                        if (data['status'] == 'success') {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Privacy settings updated successfully!'),
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
                  child: Text('Save Changes', style: TextStyle(color: Colors.white)),
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

  Future<void> _handleOfflineRetry(ConnectivityService connectivityService) async {
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

  Widget _buildOnlineScaffold({required Widget child, SystemUiOverlayStyle? overlayStyle}) {
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
                    const Icon(Icons.error_outline, color: Colors.red, size: 50),
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
        final model = context.read<SignupModel>();

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
                  _buildDocumentStatusSection(personalDetail),
                  if (_docStatus == 'approved')
                    _buildVerifiedInformationSection(personalDetail, model),
                  _buildMembershipAndPackageSection(),
                  _buildProfileInfo(personalDetail),
                  _buildAboutMe(personalDetail, lifestyle, familyDetail),
                  _buildPersonalDetails(personalDetail),
                  _buildCommunityDetails(personalDetail),
                  _buildProfessionalDetails(personalDetail),
                  _buildFamilyDetails(familyDetail),
                  _buildLifestyle(lifestyle),
                  _buildPartnerPreferences(partner),
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
    // Use backend completion if available, otherwise calculate locally
    final completion = _backendProfileCompletion ?? _calculateProfileCompletion(
      personalDetail: personalDetail,
      familyDetail: familyDetail,
      lifestyle: lifestyle,
      partner: _asMap(profileData?['partner']),
    );
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
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFFD32F2F), // Dark Red
            Color(0xFFEF5350), // Light Red
          ],
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
                      onPressed: () {
                        Navigator.pop(context);
                      },
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
                      MaterialPageRoute(
                          builder: (_) => const SettingsScreen()),
                    ),
                  ),
                ],
              ),
            ),

            // Profile Image and Basic Info
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Stack(
                    children: [
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          image: DecorationImage(
                            image: NetworkImage(
                              _getFullImageUrl(personalDetail['profile_picture']),
                            ),
                            fit: BoxFit.cover,
                          ),
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
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFD32F2F),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: const Icon(
                              Icons.camera_alt,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          '${_displayValue(personalDetail['firstName'], fallback: '')} ${_displayValue(personalDetail['lastName'], fallback: '')}, ${_calculateAge(personalDetail['birthDate'])}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (isProfileVerified)
                        const Icon(Icons.verified, color: Colors.white, size: 20),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // User ID Display
                  if (_userId != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withOpacity(0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.perm_identity, color: Colors.white, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            'ID: ${_userId}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 6),
                  if (profileSubtitle.isNotEmpty)
                    Text(
                      profileSubtitle,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 10),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      if (!_isMissing(personalDetail['religionName']))
                        _buildInfoBadge(
                          _stringValue(personalDetail['religionName']),
                          Icons.person,
                        ),
                      if (!_isMissing(personalDetail['communityName']))
                        _buildInfoBadge(
                          _stringValue(personalDetail['communityName']),
                          Icons.castle,
                        ),
                      if (!_isMissing(personalDetail['degree']))
                        _buildInfoBadge(
                          _stringValue(personalDetail['degree']),
                          Icons.school,
                        ),
                      if (!_isMissing(model.gender))
                        _buildInfoBadge(_stringValue(model.gender), Icons.wc),
                      if (!_isMissing(_userId))
                        _buildInfoBadge('ID: $_userId', Icons.badge_outlined),
                    ],
                 ),
                  const SizedBox(height: 16),
                 Container(
                   width: double.infinity,
                   padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                   decoration: BoxDecoration(
                     color: Colors.white.withOpacity(0.14),
                     borderRadius: BorderRadius.circular(18),
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
                       Container(width: 1, height: 42, color: Colors.white24),
                       Expanded(
                         child: _buildHeaderMetric(
                           'Member Type',
                           memberType,
                           Icons.workspace_premium_rounded,
                         ),
                       ),
                       Container(width: 1, height: 42, color: Colors.white24),
                       Expanded(
                         child: _buildHeaderMetric(
                           'Plan',
                           _activePackageName ?? 'Free',
                           Icons.receipt_long_rounded,
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
      if (now.month < birth.month || (now.month == birth.month && now.day < birth.day)) {
        age--;
      }
      return age;
    } catch (e) {
      return 0;
    }
  }

  Widget _buildMembershipAndPackageSection() {
    final hasPackage = !_isMissing(_activePackageName);

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
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.07),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Gradient header with member type
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  memberColor.withOpacity(0.95),
                  Color.lerp(memberColor, Colors.black, 0.2)!,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
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
                      child: Icon(memberIcon, color: Colors.white, size: 28),
                    ),
                    const SizedBox(width: 15),
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
                          const SizedBox(height: 4),
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
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _getMemberBenefitList(memberType)
                      .map(
                        (benefit) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
              ],
            ),
          ),

          // Active package banner
          Padding(
            padding: const EdgeInsets.all(14),
            child: hasPackage
                ? Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2E7D32).withOpacity(0.06),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFF2E7D32).withOpacity(0.25),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.check_circle_rounded,
                              color: Color(0xFF2E7D32),
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'You are currently active on $_activePackageName package.',
                                style: const TextStyle(
                                  color: Color(0xFF2E7D32),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (!_isMissing(_activePackageExpiry)) ...[
                          const SizedBox(height: 6),
                          Padding(
                            padding: const EdgeInsets.only(left: 30),
                            child: Text(
                              'Valid until: $_activePackageExpiry',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ),
                        ],
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
                            icon: const Icon(Icons.upgrade_rounded, size: 18),
                            label: const Text(
                              'Update Package',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2E7D32),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'You are currently on the $memberType membership.',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 13,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const SubscriptionPage()),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: memberColor,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 18, vertical: 12),
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
          ),
        ],
      ),
    );
  }

  Widget _buildMemberTypeSection() {
    Color memberColor;
    IconData memberIcon;

    switch(memberType) {
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
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
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
    switch(type) {
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

  int _calculateProfileCompletion({
    required Map<String, dynamic> personalDetail,
    required Map<String, dynamic> familyDetail,
    required Map<String, dynamic> lifestyle,
    required Map<String, dynamic> partner,
  }) {
    final fields = [
      personalDetail['firstName'],
      personalDetail['lastName'],
      personalDetail['birthDate'],
      personalDetail['height_name'],
      personalDetail['maritalStatusName'],
      personalDetail['motherTongue'],
      personalDetail['city'],
      personalDetail['country'],
      personalDetail['religionName'],
      personalDetail['communityName'],
      personalDetail['degree'],
      personalDetail['designation'],
      personalDetail['annualincome'],
      personalDetail['aboutMe'],
      familyDetail['familytype'],
      familyDetail['familybackground'],
      familyDetail['fatheroccupation'],
      familyDetail['motheroccupation'],
      familyDetail['familyorigin'],
      lifestyle['diet'],
      lifestyle['smoke'],
      lifestyle['drinks'],
      partner['minage'],
      partner['maxage'],
      partner['maritalstatus'],
      partner['religion'],
      partner['qualification'],
      partner['proffession'],
    ];

    final completed = _countFilledFields(fields);
    return ((completed / fields.length) * 100).round();
  }

  List<_ProfileReminder> _buildMissingSections({
    required Map<String, dynamic> personalDetail,
    required Map<String, dynamic> familyDetail,
    required Map<String, dynamic> lifestyle,
    required Map<String, dynamic> partner,
  }) {
    final reminders = <_ProfileReminder>[];

    final basicMissing = _countMissing([
      personalDetail['birthDate'],
      personalDetail['height_name'],
      personalDetail['maritalStatusName'],
      personalDetail['motherTongue'],
      personalDetail['city'],
      personalDetail['country'],
    ]);
    if (basicMissing > 0) {
      reminders.add(
        _ProfileReminder(
          title: 'Complete your basic profile',
          subtitle: '$basicMissing important detail${basicMissing > 1 ? 's are' : ' is'} still missing.',
          icon: Icons.person_outline_rounded,
          onTap: _editBasicInfo,
        ),
      );
    }

    if (_isMissing(personalDetail['aboutMe'])) {
      reminders.add(
        _ProfileReminder(
          title: 'Add your profile introduction',
          subtitle: 'Use the auto-generated About section and update it anytime.',
          icon: Icons.auto_awesome_rounded,
          onTap: () => _editAboutMe(context, _generateAboutMe(personalDetail, lifestyle, familyDetail)),
        ),
      );
    }

    final professionalMissing = _countMissing([
      personalDetail['degree'],
      personalDetail['designation'],
      personalDetail['annualincome'],
    ]);
    if (professionalMissing > 0) {
      reminders.add(
        _ProfileReminder(
          title: 'Update professional details',
          subtitle: '$professionalMissing professional field${professionalMissing > 1 ? 's are' : ' is'} pending.',
          icon: Icons.work_outline_rounded,
          onTap: _editProfessionalDetails,
        ),
      );
    }

    final familyMissing = _countMissing([
      familyDetail['familytype'],
      familyDetail['familybackground'],
      familyDetail['fatheroccupation'],
      familyDetail['motheroccupation'],
      familyDetail['familyorigin'],
    ]);
    if (familyMissing > 0) {
      reminders.add(
        _ProfileReminder(
          title: 'Finish family details',
          subtitle: '$familyMissing family detail${familyMissing > 1 ? 's are' : ' is'} incomplete.',
          icon: Icons.family_restroom_rounded,
          onTap: _editFamilyDetails,
        ),
      );
    }

    final lifestyleMissing = _countMissing([
      lifestyle['diet'],
      lifestyle['smoke'],
      lifestyle['drinks'],
    ]);
    if (lifestyleMissing > 0) {
      reminders.add(
        _ProfileReminder(
          title: 'Fill lifestyle preferences',
          subtitle: 'This helps show accurate profile and match preferences.',
          icon: Icons.spa_outlined,
          onTap: _editLifestyle,
        ),
      );
    }

    final partnerMissing = _countMissing([
      partner['minage'],
      partner['maxage'],
      partner['maritalstatus'],
      partner['religion'],
      partner['qualification'],
      partner['proffession'],
    ]);
    if (partnerMissing > 0) {
      reminders.add(
        _ProfileReminder(
          title: 'Complete partner preference',
          subtitle: '$partnerMissing preference field${partnerMissing > 1 ? 's are' : ' is'} missing.',
          icon: Icons.favorite_border_rounded,
          onTap: _editPartnerPreferences,
        ),
      );
    }

    return reminders;
  }

  int _countMissing(List<dynamic> values) {
    return values.where(_isMissing).length;
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

  Widget _buildDocumentStatusSection(Map<String, dynamic> personalDetail) {
    final maritalStatus = personalDetail['maritalStatusName']?.toString() ?? '';
    if (!_requiresMaritalStatusDocument(maritalStatus) ||
        (_docUploadSkipped && _docStatus == 'not_uploaded')) {
      return const SizedBox.shrink();
    }

    Color bgColor;
    Color iconColor;
    IconData icon;
    String title;
    String subtitle;
    Widget? action;

    switch (_docStatus) {
      case 'approved':
        bgColor = const Color(0xFFE8F5E9);
        iconColor = const Color(0xFF2E7D32);
        icon = Icons.verified_rounded;
        title = 'Document Verified';
        subtitle = 'Your marital status document has been approved. Your profile is verified.';
        action = null;
        break;
      case 'pending':
        bgColor = const Color(0xFFFFFDE7);
        iconColor = const Color(0xFFF57F17);
        icon = Icons.hourglass_top_rounded;
        title = 'Document Under Review';
        subtitle = 'Your document has been submitted and is awaiting admin approval.';
        action = null;
        break;
      case 'rejected':
        bgColor = const Color(0xFFFFEBEE);
        iconColor = const Color(0xFFD32F2F);
        icon = Icons.cancel_rounded;
        title = 'Document Rejected';
        subtitle = 'Your document was rejected. Please upload a valid document to get verified.';
        action = TextButton.icon(
          onPressed: () => _openEditPage(const MaritalDocumentUploadScreen()),
          icon: const Icon(Icons.upload_file_rounded, size: 18),
          label: const Text('Re-upload Document'),
          style: TextButton.styleFrom(foregroundColor: const Color(0xFFD32F2F)),
        );
        break;
      default: // not_uploaded
        bgColor = const Color(0xFFFCE4EC);
        iconColor = const Color(0xFFD32F2F);
        icon = Icons.upload_file_rounded;
        title = 'Document Required';
        subtitle = 'Since your marital status is "$maritalStatus", you must upload a supporting document (e.g. death certificate / divorce decree / court order) to get your profile verified.';
        action = Row(
          children: [
            ElevatedButton.icon(
              onPressed: () => _openEditPage(const MaritalDocumentUploadScreen()),
              icon: const Icon(Icons.upload_rounded, size: 18, color: Colors.white),
              label: const Text('Upload Document', style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD32F2F),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
            ),
            const SizedBox(width: 8),
            Semantics(
              label: 'Skip document upload for this session',
              child: TextButton(
                onPressed: () => setState(() => _docUploadSkipped = true),
                child: Text('Skip', style: TextStyle(color: Colors.grey[600])),
              ),
            ),
          ],
        );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: iconColor.withOpacity(0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: iconColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[700],
                    height: 1.4,
                  ),
                ),
                if (action != null) ...[
                  const SizedBox(height: 10),
                  action,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompletionSection({
    required Map<String, dynamic> personalDetail,
    required Map<String, dynamic> familyDetail,
    required Map<String, dynamic> lifestyle,
    required Map<String, dynamic> partner,
  }) {
    // Use backend completion if available, otherwise calculate locally
    final completion = _backendProfileCompletion ?? _calculateProfileCompletion(
      personalDetail: personalDetail,
      familyDetail: familyDetail,
      lifestyle: lifestyle,
      partner: partner,
    );
    final reminders = _buildMissingSections(
      personalDetail: personalDetail,
      familyDetail: familyDetail,
      lifestyle: lifestyle,
      partner: partner,
    );

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
                      reminders.isEmpty
                          ? 'Your profile looks complete.'
                          : 'We found ${reminders.length} section${reminders.length > 1 ? 's' : ''} that still need attention.',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '$completion%',
                style: const TextStyle(
                  color: Color(0xFFF90E18),
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              minHeight: 10,
              value: completion / 100,
              backgroundColor: const Color(0xFFF5D8DA),
              valueColor: const AlwaysStoppedAnimation(Color(0xFFF90E18)),
            ),
          ),
          if (reminders.isNotEmpty) ...[
            const SizedBox(height: 16),
            ...reminders.map(
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
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(reminder.subtitle),
                  trailing: TextButton(
                    onPressed: reminder.onTap,
                    child: const Text('Fill now'),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPackageDetailsSection() {
    final hasPackage = !_isMissing(_activePackageName);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
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
                child: const Icon(Icons.receipt_long_rounded, color: Color(0xFFF90E18)),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Package Information',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _buildSummaryTile(
                  'Membership',
                  '$memberType Member',
                  Icons.workspace_premium_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildSummaryTile(
                  'Current Package',
                  hasPackage ? _stringValue(_activePackageName) : 'Free Plan',
                  Icons.sell_rounded,
                ),
              ),
            ],
          ),
          if (hasPackage || !_isMissing(_activePackageExpiry)) ...[
            const SizedBox(height: 10),
            _buildSummaryTile(
              'Validity',
              _displayValue(_activePackageExpiry, fallback: 'No expiry available'),
              Icons.event_available_rounded,
            ),
          ],
          const SizedBox(height: 14),
          // Active package status and update button
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFFF90E18).withOpacity(0.08),
                  const Color(0xFFF90E18).withOpacity(0.04),
                ],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFF90E18).withOpacity(0.2)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: hasPackage ? const Color(0xFF4CAF50) : Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    hasPackage ? Icons.check_circle : Icons.info,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasPackage
                          ? 'You are currently active on this package'
                          : 'You are on a free plan',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1A1A2E),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        hasPackage
                          ? 'Click the button to update or change your package'
                          : 'Upgrade to unlock premium features',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const SubscriptionPage()),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF90E18),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    hasPackage ? 'Update' : 'Upgrade',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
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

  Widget _buildSummaryTile(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FD),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF90E18).withOpacity(0.08),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: const Color(0xFFF90E18), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileInfo(Map<String, dynamic> personalDetail) {
    final location = _displayValue(
      _joinNonEmpty([
        _firstFilled([personalDetail['city']]),
        _firstFilled([personalDetail['country']]),
      ]),
    );
    final isVerified = _docStatus == 'approved';

    Widget statRow(String l1, dynamic v1, String l2, dynamic v2) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            Expanded(child: _buildMiniStat(l1, _displayValue(v1))),
            const SizedBox(width: 10),
            Expanded(child: _buildMiniStat(l2, _displayValue(v2))),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
        border: Border.all(color: AppColors.primary.withOpacity(0.06)),
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
                  child: const Icon(Icons.account_circle_outlined, color: AppColors.primary, size: 18),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Account Information',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A1A2E),
                        ),
                      ),
                      Text(
                        'Your account details',
                        style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                statRow('User ID', _userId, 'Profile ID', personalDetail['memberid']),
                statRow('Privacy', personalDetail['privacy'], 'Location', location),
              ],
            ),
          ),
        ],
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
        color: missing ? Colors.grey.shade50 : AppColors.primary.withOpacity(0.03),
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

  Widget _buildAboutMe(
    Map<String, dynamic> personalDetail,
    Map<String, dynamic> lifestyle,
    Map<String, dynamic> familyDetail,
  ) {
    final savedAbout = _stringValue(personalDetail['aboutMe']);
    final generatedAbout = _generateAboutMe(personalDetail, lifestyle, familyDetail);
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
                : _displayValue(savedAbout, fallback: 'No information provided'),
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
      sentences.add('Family is important to me and I value ${familyBits.join(' with ')}.');
    }

    return sentences.join(' ').trim();
  }

  Widget _buildVerifiedInformationSection(
    Map<String, dynamic> personalDetail,
    SignupModel model,
  ) {
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
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF2E7D32).withOpacity(0.08),
                  const Color(0xFF43A047).withOpacity(0.05),
                ],
              ),
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
                    color: const Color(0xFF2E7D32).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.verified_user, color: Color(0xFF2E7D32), size: 18),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Verified Information',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A1A2E),
                        ),
                      ),
                      Text(
                        'Cannot be changed after verification',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF9E9E9E),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2E7D32).withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.lock,
                    color: Color(0xFF2E7D32),
                    size: 16,
                  ),
                ),
              ],
            ),
          ),

          // Info Banner
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF2E7D32).withOpacity(0.2)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline,
                  color: Color(0xFF2E7D32),
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Your document has been verified',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF2E7D32),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'These fields cannot be changed. If you need to change any information, please contact support.',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[700],
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Locked Fields
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Column(
              children: [
                _buildLockedDetailRow('Full Name', '${_displayValue(personalDetail['firstName'], fallback: '')} ${_displayValue(personalDetail['lastName'], fallback: '')}'),
                _buildLockedDetailRow('Date of Birth', _formatDate(personalDetail['birthDate'])),
                _buildLockedDetailRow('Age', '${_calculateAge(personalDetail['birthDate'])} Years'),
                _buildLockedDetailRow('Email', _displayValue(model.email, fallback: personalDetail['email']?.toString() ?? 'N/A')),
                _buildLockedDetailRow('Phone Number', _displayValue(model.contactNo, fallback: personalDetail['contactNo']?.toString() ?? 'N/A')),
                _buildLockedDetailRow('Marital Status', _displayValue(personalDetail['maritalStatusName'])),
              ],
            ),
          ),
        ],
      ),
    );
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
    final isVerified = _docStatus == 'approved';

    return _buildSection(
      title: 'Personal Details',
      icon: Icons.person_outline,
      content: Column(
        children: [
          // Basic Personal Information
          if (!isVerified) ...[
            _buildDetailRow('Full Name', '${_displayValue(personalDetail['firstName'], fallback: '')} ${_displayValue(personalDetail['lastName'], fallback: '')}'),
            _buildDetailRow('Date of Birth', _formatDate(personalDetail['birthDate'])),
            _buildDetailRow('Age', '${_calculateAge(personalDetail['birthDate'])} Years'),
            _buildDetailRow('Gender', _displayValue(_firstFilled([personalDetail['gender'], model.gender]))),
            _buildDetailRow('Marital Status', _displayValue(personalDetail['maritalStatusName'])),
          ],

          // Physical Attributes
          _buildDetailRow('Height', _displayValue(personalDetail['height_name'])),
          if (!_isMissing(personalDetail['weight_name']))
            _buildDetailRow('Weight', _displayValue(personalDetail['weight_name'])),
          _buildDetailRow('Blood Group', _displayValue(personalDetail['bloodGroup'])),
          if (!_isMissing(personalDetail['complexion']))
            _buildDetailRow('Complexion', _displayValue(personalDetail['complexion'])),
          if (!_isMissing(personalDetail['bodyType']))
            _buildDetailRow('Body Type', _displayValue(personalDetail['bodyType'])),

          // Health Information
          _buildDetailRow(
            'Disability',
            _displayValue(
              _firstFilled([personalDetail['disability'], personalDetail['Disability']]),
              fallback: 'None',
            ),
          ),
          if (!_isMissing(personalDetail['specs']))
            _buildDetailRow('Specs/Lenses', _displayValue(personalDetail['specs'])),

          // Birth Details
          _buildDetailRow('Birth Time', _displayValue(personalDetail['birthtime'])),
          _buildDetailRow('Birth Place', _displayValue(personalDetail['birthcity'])),
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
          _buildDetailRow('Religion', _displayValue(personalDetail['religionName'])),
          _buildDetailRow('Caste', _displayValue(personalDetail['communityName'])),
          _buildDetailRow('Sub Caste', _displayValue(personalDetail['subCommunityName'])),
          _buildDetailRow('Mother Tongue', _displayValue(personalDetail['motherTongue'])),
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
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
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
          _buildDetailRow('Education Type', _displayValue(personalDetail['educationtype'])),
          if (!_isMissing(personalDetail['educationmedium']))
            _buildDetailRow('Education Medium', _displayValue(personalDetail['educationmedium'])),

          // Career Information
          _buildDetailRow('Occupation', _displayValue(personalDetail['designation'])),
          _buildDetailRow('Employer', _displayValue(personalDetail['companyname'])),
          _buildDetailRow('Working With', _displayValue(personalDetail['workingwith'])),
          _buildDetailRow('Annual Income', _displayValue(personalDetail['annualincome'])),
          _buildDetailRow('Work Location', _displayValue(personalDetail['city'])),
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
          _buildDetailRow('Family Type', _displayValue(familyDetail['familytype'])),
          _buildDetailRow('Family Status', _displayValue(familyDetail['familybackground'])),
          _buildDetailRow('Family Origin', _displayValue(familyDetail['familyorigin'])),

          // Father Information
          _buildDetailRow('Father Name', _displayValue(familyDetail['fathername'])),
          _buildDetailRow('Father Education', _displayValue(familyDetail['fathereducation'])),
          _buildDetailRow('Father\'s Occupation', _displayValue(familyDetail['fatheroccupation'])),

          // Mother Information
          if (!_isMissing(familyDetail['mothercaste']))
            _buildDetailRow('Mother Caste', _displayValue(familyDetail['mothercaste'])),
          _buildDetailRow('Mother Education', _displayValue(familyDetail['mothereducation'])),
          _buildDetailRow('Mother\'s Occupation', _displayValue(familyDetail['motheroccupation'])),
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
                final XFile? image = await picker.pickImage(source: ImageSource.gallery);
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
              child: const Text('Choose from Gallery', style: TextStyle(color: Colors.white)),
            ),

            const SizedBox(height: 10),

            /// Camera
            ElevatedButton(
              onPressed: () async {
                final XFile? image = await picker.pickImage(source: ImageSource.camera);
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
              child: const Text('Take a Photo', style: TextStyle(color: Colors.white)),
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
            // Save new image path locally
            final prefs = await SharedPreferences.getInstance();
            final userData = jsonDecode(prefs.getString('user_data')!);
            userData['profile_picture'] = 'uploads/profile_pictures/profilepicture_$userId.jpg';
            prefs.setString('user_data', jsonEncode(userData));

            // Update timestamp to refresh image
            setState(() {
              _profilePictureTimestamp = DateTime.now().millisecondsSinceEpoch;
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
            final errorMsg = responseData['message'] ?? 'Unknown error occurred';
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
      PersonalDetailsPagee(
        initialData: _asMap(profileData?['personalDetail']),
      ),
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
    final TextEditingController _controller = TextEditingController(text: currentAboutMe);
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
                        icon: Icon(Icons.auto_awesome, color: Color(0xFFD32F2F), size: 18),
                        label: Text(
                          'Auto Generate Your About Me',
                          style: TextStyle(color: Color(0xFFD32F2F), fontSize: 13),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: Color(0xFFD32F2F)),
                          padding: EdgeInsets.symmetric(vertical: 10, horizontal: 12),
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
                        child: CircularProgressIndicator(color: Color(0xFFD32F2F)),
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
                    onPressed: isSaving ? null : () async {
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

                      final saved = await _saveAboutMe(_controller.text.trim());
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
      PersonalDetailsPagee(
        initialData: _asMap(profileData?['personalDetail']),
        isVerified: _docStatus == 'approved', // Pass verification status to edit screen
      ),
    );
  }

  void _editCommunityDetails() {
    _openEditPage(
      CommunityDetailsPageEdit(
        initialData: _asMap(profileData?['personalDetail']),
      ),
    );
  }

  void _editProfessionalDetails() {
    _openEditPage(
      EducationCareerPagee(
        initialData: _asMap(profileData?['personalDetail']),
      ),
    );
  }

  void _editFamilyDetails() {
    _openEditPage(
      FamilyDetailsPagee(
        initialFamilyData: _asMap(profileData?['familyDetail']),
      ),
    );
  }

  void _editLifestyle() {
    _openEditPage(
      LifestylePagee(
        initialData: _asMap(profileData?['lifestyle']),
      ),
    );
  }

  void _editPartnerPreferences() {
    _openEditPage(
      PartnerPreferencesPagee(
        initialData: _asMap(profileData?['partner']),
      ),
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
              _buildMembershipOption('Free', '👤', 'Basic Features', 'Rs0/month', false),
              SizedBox(height: 10),
              _buildMembershipOption('Premium', '👑', 'Unlimited Chats + Profile Boost', 'Rs999/month', true),
              SizedBox(height: 10),
              _buildMembershipOption('Gold', '⭐', 'Priority Listing + Advanced Search', 'Rs1,999/month', false),
              SizedBox(height: 10),
              _buildMembershipOption('Platinum', '💎', 'All Features + Personal Matchmaking', 'rs2,999/month', false),
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

  Widget _buildMembershipOption(String name, String icon, String features, String price, bool isPopular) {
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
              gradient: isPopular ? LinearGradient(
                colors: [Color(0xFFD32F2F), Color(0xFFEF5350)],
              ) : null,
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
      final isVegetarian = normalizedDiet.contains('veg') && !normalizedDiet.contains('non');
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
    final ageText = !_isMissing(partner['minage']) && !_isMissing(partner['maxage'])
        ? '${partner['minage']}-${partner['maxage']} Years'
        : 'Not provided';
    return _buildSection(
      title: 'Partner Preferences',
      icon: Icons.search,
      content: Column(
        children: [
          _buildPreferenceRow('Age', ageText),
          if (!_isMissing(partner['minheight']) && !_isMissing(partner['maxheight']))
            _buildPreferenceRow('Height', '${partner['minheight']}-${partner['maxheight']}'),
          _buildPreferenceRow('Marital Status', _displayValue(partner['maritalstatus'])),
          _buildPreferenceRow('Religion', _displayValue(partner['religion'])),
          _buildPreferenceRow('Caste', _displayValue(partner['caste'])),
          if (!_isMissing(partner['community']))
            _buildPreferenceRow('Community', _displayValue(partner['community'])),
          if (!_isMissing(partner['mothertongue'])) // Corrected field name
            _buildPreferenceRow('Mother Tongue', _displayValue(partner['mothertongue'])),
          _buildPreferenceRow('Education', _displayValue(partner['qualification'])),
          _buildPreferenceRow('Occupation', _displayValue(partner['profession'])), // Corrected field name
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
          _buildPreferenceRow('Family Values', _displayValue(partner['familytype'])),
          _buildPreferenceRow('Other Expectations', _displayValue(partner['otherexpectation'])),
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
                    ? GestureDetector(
                        onTap: onEdit,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                              Icon(Icons.lock, color: Color(0xFF2E7D32), size: 13),
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

  _ProfileReminder({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });
}
