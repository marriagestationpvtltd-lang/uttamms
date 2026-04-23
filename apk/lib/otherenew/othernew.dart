import 'dart:async';
import 'dart:convert';
import 'dart:ui'; // Required for ImageFilter
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:ms2026/Chat/ChatdetailsScreen.dart';
import 'package:ms2026/Notification/notification_inbox_service.dart';
import 'package:ms2026/pushnotification/pushservice.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../Auth/Screen/signupscreen10.dart';
import '../Chat/adminchat.dart';
import '../Models/masterdata.dart';
import '../Package/PackageScreen.dart';
import '../constant/constant.dart';
import '../core/user_state.dart';
import '../main.dart';
import '../otherenew/service.dart';
import '../service/socket_service.dart';
import '../utils/image_utils.dart';
import '../utils/time_utils.dart';
import 'modelfile.dart';
import 'package:ms2026/config/app_endpoints.dart';
import 'package:ms2026/features/activity/services/activity_service.dart';

class ProfileScreen extends StatefulWidget {
  final String userId;


ProfileScreen({super.key, required this.userId,});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const String _requestBaseUrl = '${kApiBaseUrl}/request';

  bool _isBlocked = false;
  bool _isLoadingBlock = false;
  Future<void> _checkBlockStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final userDataString = prefs.getString('user_data');
    if (userDataString == null) return;

    final userData = jsonDecode(userDataString);
    final myId = userData["id"].toString();

    final service = ProfileService();
    final isBlocked = await service.isUserBlocked(
      myId: myId,
      userId: widget.userId,
    );

    if (mounted) {
      setState(() {
        _isBlocked = isBlocked;
      });
    }
  }

  void _showBlockProfileDialog(BuildContext context) async {
    if (_isBlocked) {
      // Show unblock confirmation
      showDialog<void>(
        context: context,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            title: const Text('Unblock Profile'),
            content: const Text('Are you sure you want to unblock this profile? They will be able to contact you again.'),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('CANCEL'),
              ),
              TextButton(
                onPressed: () => _unblockUser(dialogContext),
                child: Text(
                  'UNBLOCK',
                  style: TextStyle(color: Theme.of(context).primaryColor),
                ),
              ),
            ],
          );
        },
      );
    } else {
      // Show block confirmation
      showDialog<void>(
        context: context,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            title: const Text('Block Profile'),
            content: const Text('Are you sure you want to block this profile? They will not be able to contact you or see your profile.'),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('CANCEL'),
              ),
              TextButton(
                onPressed: () => _blockUser(dialogContext),
                child: Text(
                  'BLOCK',
                  style: TextStyle(color: Theme.of(context).primaryColor),
                ),
              ),
            ],
          );
        },
      );
    }
  }


  Future<void> _blockUser(BuildContext dialogContext) async {
    setState(() {
      _isLoadingBlock = true;
    });

    Navigator.of(dialogContext).pop(); // Close dialog

    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataString = prefs.getString('user_data');
      final userData = jsonDecode(userDataString!);
      final myId = userData["id"].toString();

      final service = ProfileService();
      final result = await service.blockUser(
        myId: myId,
        userId: widget.userId,
      );

      if (mounted) {
        if (result['status'] == 'success') {
          setState(() {
            _isBlocked = true;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Profile blocked successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message'] ?? 'Failed to block user'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingBlock = false;
        });
      }
    }
  }

  Future<void> _unblockUser(BuildContext dialogContext) async {
    setState(() {
      _isLoadingBlock = true;
    });

    Navigator.of(dialogContext).pop(); // Close dialog

    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataString = prefs.getString('user_data');
      final userData = jsonDecode(userDataString!);
      final myId = userData["id"].toString();

      final service = ProfileService();
      final result = await service.unblockUser(
        myId: myId,
        userId: widget.userId,
      );

      if (mounted) {
        if (result['status'] == 'success') {
          setState(() {
            _isBlocked = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Profile unblocked successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message'] ?? 'Failed to unblock user'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingBlock = false;
        });
      }
    }
  }




  void _showReportDialog(BuildContext context) {
    String? selectedReason;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext sheetContext) {
        return StatefulBuilder(
          builder: (_, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Icon(Icons.flag, color: Colors.orange, size: 24),
                        SizedBox(width: 8),
                        Text(
                          'Report Profile',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      'Select reason for report:',
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...AppConstants.reportReasons.map((reason) => RadioListTile<String>(
                        value: reason,
                        groupValue: selectedReason,
                        onChanged: (value) =>
                            setSheetState(() => selectedReason = value),
                        title: Text(reason,
                            style: const TextStyle(fontSize: 14)),
                        activeColor: Colors.red,
                        dense: true,
                      )),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () =>
                                Navigator.of(sheetContext).pop(),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: selectedReason == null
                                ? null
                                : () async {
                                    Navigator.of(sheetContext).pop();
                                    await _submitReport(
                                        context, selectedReason!);
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                            ),
                            child: const Text(
                              'Report',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _submitReport(BuildContext context, String reason) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataString = prefs.getString('user_data');
      if (userDataString == null) return;
      final userData = jsonDecode(userDataString);
      final currentUserId = userData['id'].toString();
      final adminUserId = AppConstants.adminUserId;

      final userProfile =
          Provider.of<UserProfile>(context, listen: false);
      final reportedUserName =
          userProfile.name.isNotEmpty ? userProfile.name : 'Unknown';

      final reporterName = '${userData['firstName'] ?? ''} ${userData['lastName'] ?? ''}'.trim();
      final reportPayload = jsonEncode({
        'reportedUserId': widget.userId,
        'reportedUserName': reportedUserName,
        'reporterName': reporterName.isNotEmpty ? reporterName : (userData['firstName']?.toString() ?? 'Unknown'),
        'reporterId': currentUserId,
        'reporterImage': userData['image']?.toString() ?? '',
        'reportReason': reason,
      });

      final List<String> ids = [currentUserId, adminUserId]..sort();
      final adminChatRoomId = ids.join('_');
      SocketService().sendMessage(
        chatRoomId: adminChatRoomId,
        senderId: currentUserId,
        receiverId: adminUserId,
        message: reportPayload,
        messageType: 'report',
        messageId: const Uuid().v4(),
        user1Name: userData['firstName']?.toString() ?? '',
        user2Name: 'Admin',
        user1Image: userData['image']?.toString() ?? '',
        user2Image: '',
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile reported successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to report: $e')),
        );
      }
    }
  }
  @override
  void initState() {
    super.initState();
    _loadProfileData();
    _loadUserData();
    addProfileView(widget.userId);
    _checkBlockStatus();
    _startOnlineStatusListener();
  }

  @override
  void dispose() {
    _onlineStatusSub?.cancel();
    super.dispose();
  }


  Future<void> addProfileView(String viewedUserId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataString = prefs.getString('user_data');

      if (userDataString == null) return;

      final userData = jsonDecode(userDataString);
      final myId = userData["id"].toString();

      final response = await http.post(
        Uri.parse("$_requestBaseUrl/add_profile_view.php"),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          "userid": myId,           // viewer
          "viewuserid": viewedUserId // profile owner
        }),
      );

      final result = jsonDecode(response.body);
      debugPrint("Profile view response: $result");

      if (response.statusCode == 200 &&
          result['status']?.toString().toLowerCase() == 'success') {
        final viewerName = await NotificationInboxService.getCurrentUserDisplayName();
        await NotificationService.sendProfileViewNotification(
          recipientUserId: viewedUserId,
          viewerName: viewerName,
          viewerId: myId,
        );
        // Log profile_view activity (fire-and-forget)
        ActivityService.instance.log(
          userId: myId,
          activityType: ActivityType.profileView,
          targetUserId: viewedUserId,
        );
      }

    } catch (e) {
      debugPrint("Error adding profile view: $e");
    }
  }

  Future<UserMasterData> fetchUserMasterData(String userId) async {
    final url = Uri.parse(
      "${ProfileService.baseUrl}/masterdata.php?userid=$userId",
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


  Future<void> _loadUserData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataString = prefs.getString('user_data');

      if (userDataString == null) {
        setState(() => isLoading = false);
        return;
      }

      final userData = jsonDecode(userDataString);
      final rawId = userData["id"];
      final userIdString = rawId.toString().trim();

      UserMasterData user = await fetchUserMasterData(userIdString);

      if (mounted) {
        setState(() {
          userimage = user.profilePicture;
          pageno = user.pageno;
          userId = user.id?.toString() ?? userIdString;
          name = user.firstName;
          isLoading = false;
        });
      }

    } catch (e) {
      debugPrint('Error loading user data: $e');
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  String myidd = '';
  String userimage = '';
  var pageno;
  String userId = '';
  String name = '';
  bool isLoading = true;

  bool _isOtherUserOnline = false;
  DateTime? _otherUserLastSeen;
  StreamSubscription? _onlineStatusSub;

  void _startOnlineStatusListener() {
    final targetId = widget.userId;

    // Fetch initial status from server
    SocketService().getUserStatus(targetId).then((data) {
      if (!mounted) return;
      final bool isOnline = data['isOnline'] == true;
      final DateTime? lastSeen = SocketService.parseTimestamp(data['lastSeen']);
      final bool recentlySeen = lastSeen != null &&
          DateTime.now().difference(lastSeen).inMinutes < 5;
      setState(() {
        _isOtherUserOnline = isOnline || recentlySeen;
        _otherUserLastSeen = lastSeen;
      });
    });

    // Subscribe to real-time status changes via Socket.IO
    _onlineStatusSub?.cancel();
    _onlineStatusSub = SocketService().onUserStatusChange.listen((data) {
      if (!mounted) return;
      final uid = data['userId']?.toString() ?? '';
      if (uid != targetId) return;
      final bool isOnline = data['isOnline'] == true;
      final DateTime? lastSeen = SocketService.parseTimestamp(data['lastSeen']);
      final bool recentlySeen = lastSeen != null &&
          DateTime.now().difference(lastSeen).inMinutes < 5;
      if (_isOtherUserOnline != (isOnline || recentlySeen) ||
          _otherUserLastSeen != lastSeen) {
        setState(() {
          _isOtherUserOnline = isOnline || recentlySeen;
          _otherUserLastSeen = lastSeen;
        });
      }
    });
  }

  Future<void> _loadProfileData() async {
    final prefs = await SharedPreferences.getInstance();
    final userDataString = prefs.getString('user_data');
    final userData = jsonDecode(userDataString!);
    final myid = int.tryParse(userData["id"].toString());
    try {
      setState(() {
        myidd = myid.toString();
      });
      final service = ProfileService();

      // Load both profile and matched profiles in parallel
      final results = await Future.wait([
        service.fetchProfile(myId: myid.toString(), userId: widget.userId.toString()),
        service.fetchMatchedProfiles(userId: myid.toString()),
      ]);

      final profileResponse = results[0] as ProfileResponse;
      final matchedProfiles = results[1] as List<MatchedProfile>;
      // Sort: new members (higher userId) first
      matchedProfiles.sort((a, b) => b.userid.compareTo(a.userid));

      if (mounted) {
        final userProfile = Provider.of<UserProfile>(context, listen: false);
        userProfile.updateProfileData(profileResponse, matchedProfiles);
      }
    } catch (e) {
      debugPrint('Error loading profile data: $e');
    }
  }


  @override
  Widget build(BuildContext context) {
    final Color red = Colors.red.shade700;
    final Color pinkGradientEnd = const Color(0xFFEA4E7A);
    final LinearGradient buttonGradient = LinearGradient(
      colors: <Color>[red, pinkGradientEnd],
    );

    final Color dimmedRedStart = Colors.red.shade200;
    final Color dimmedPinkEndLight = const Color(0xFFF7D1DB);
    final LinearGradient dimmedButtonGradient = LinearGradient(
      colors: <Color>[dimmedRedStart, dimmedPinkEndLight],
    );
    final Color dimmedButtonTextColor = Colors.grey.shade700;

    final UserProfile userProfile = context.watch<UserProfile>();


    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        leading: const BackButton(color: Colors.black87),
        title: const Text(
          "Profile",
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child:
            PopupMenuButton<String>(
              onSelected: (String result) {
                if (result == 'block') {
                  _showBlockProfileDialog(context);
                } else if (result == 'report') {
                  _showReportDialog(context);
                }
              },
              itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                PopupMenuItem<String>(
                  value: 'block',
                  child: Row(
                    children: [
                      Icon(
                        _isBlocked ? Icons.check_circle : Icons.block,
                        color: _isBlocked ? Colors.green : Colors.red,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(_isBlocked ? 'Unblock Profile' : 'Block Profile'),
                    ],
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'report',
                  child: Row(
                    children: [
                      Icon(Icons.flag, color: Colors.orange, size: 20),
                      SizedBox(width: 8),
                      Text('Report'),
                    ],
                  ),
                ),
              ],
              icon: const Icon(Icons.more_vert, color: Colors.black87),
            ),
          ),
        ],
      ),
      body: userProfile.profileResponse == null
          ? const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading profile...'),
          ],
        ),
      )
          : SingleChildScrollView(
        child: Column(
          children: <Widget>[
            _ProfileHeaderSection(
              userProfile: userProfile,
              red: red,
              buttonGradient: buttonGradient,
              onPhotoRequestPressed: () => _handlePhotoRequest(context),
              onUpgradePressed: () => _showUpgradeDialog(context),
              userid: widget.userId,
              isOnline: _isOtherUserOnline,
              lastSeen: _otherUserLastSeen,
            ),
            const SizedBox(height: 16),
            _ContactInfoSection(
              contactInfo: userProfile.contactInfo,
              red: red,
              buttonGradient: buttonGradient,
              dimmedButtonGradient: dimmedButtonGradient,
              dimmedButtonTextColor: dimmedButtonTextColor,
              userProfile: userProfile,
              onChatRequestPressed: () => _handleChatRequest(context),
              onUpgradePressed: () => _showUpgradeDialog(context),
              userId: widget.userId, // Pass the user ID from ProfileScreen
              userName: userProfile.name, currentUserId: myidd, currentUserName: name, currentUserImage: userimage, docStatus: context.read<UserState>().identityStatus, userType: context.read<UserState>().usertype, // Pass the user name
            ),
            const SizedBox(height: 16),
            _PhotosAlbumSection(
              photoAlbumUrls: userProfile.photoAlbumUrls,
              red: red,
              buttonGradient: buttonGradient,
              userProfile: userProfile,
              onUpgradePressed: () => _showUpgradeDialog(context),
              onPhotoRequestPressed: () => _handlePhotoRequest(context),
            ),
            const SizedBox(height: 16),
            if (userProfile.personalDetails.isNotEmpty)
              _DetailsGridSection<PersonalDetailItem>(
                title: "Personal Details",
                red: red,
                items: userProfile.personalDetails,
                itemBuilder: (PersonalDetailItem item, Color sectionRed) =>
                    _DetailGridItem(
                      icon: item.icon,
                      title: item.title,
                      value: item.value,
                      red: sectionRed,
                    ),
              ),
            const SizedBox(height: 16),

            // Community Details Section
            if (userProfile.communityDetails.isNotEmpty)
              _DetailsGridSection<CommunityDetailItem>(
                title: "Community Details",
                red: red,
                items: userProfile.communityDetails,
                itemBuilder: (CommunityDetailItem item, Color sectionRed) =>
                    _DetailGridItem(
                      icon: item.icon,
                      title: item.title,
                      value: item.value,
                      red: sectionRed,
                    ),
              ),
            const SizedBox(height: 16),

            // Education & Career Details Section
            if (userProfile.educationCareerDetails.isNotEmpty)
              _DetailsGridSection<EducationCareerDetailItem>(
                title: "Education & Career Details",
                red: red,
                items: userProfile.educationCareerDetails,
                itemBuilder: (EducationCareerDetailItem item, Color sectionRed) =>
                    _DetailGridItem(
                      icon: item.icon,
                      title: item.title,
                      value: item.value,
                      red: sectionRed,
                    ),
              ),
            const SizedBox(height: 16),

            // Life Style Details Section
            if (userProfile.lifeStyleDetails.isNotEmpty)
              _DetailsGridSection<LifeStyleDetailItem>(
                title: "Life Style Details",
                red: red,
                items: userProfile.lifeStyleDetails,
                itemBuilder: (LifeStyleDetailItem item, Color sectionRed) =>
                    _DetailGridItem(
                      icon: item.icon,
                      title: item.title,
                      value: item.value,
                      red: sectionRed,
                    ),
              ),
            const SizedBox(height: 16),

            // Match Overview Section
            if (userProfile.matchedPreferencesCount > 0)
              _MatchOverviewSection(
                matchedPreferencesCount: userProfile.matchedPreferencesCount,
                totalPreferencesCount: userProfile.totalPreferencesCount,
                red: red,
                imageUrl: userProfile.avatarUrl,
              ),
            const SizedBox(height: 16),

            // Partner Preference Section
            if (userProfile.partnerPreferences.isNotEmpty)
              _PartnerPreferenceSection(
                partnerPreferences: userProfile.partnerPreferences,
                red: red,
              ),
            const SizedBox(height: 16),

            // Other Matched Profiles Section
            if (userProfile.otherMatchedProfiles.isNotEmpty)
              _OtherMatchedProfilesSection(
                otherMatchedProfiles: userProfile.otherMatchedProfiles,
                red: red,
                gradient: buttonGradient,
              ),
            const SizedBox(height: 20),// ... rest of your sections
          ],
        ),
      ),
    );
  }

  void _showUpgradeDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Upgrade Account'),
          content: const Text(
            'This feature is available for paid members. '
                'Upgrade your account to access photos and chat.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('LATER'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SubscriptionPage(),
                  ),
                );
              },
              child: const Text('UPGRADE NOW'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _handlePhotoRequest(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Send Photo Request'),
          content: const Text(
              'Do you want to request photo access from this user?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCEL'),
            ),
            TextButton(
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                final userDataString = prefs.getString('user_data');
                final userData = jsonDecode(userDataString!);
                final myid = int.tryParse(userData["id"].toString());
                Navigator.pop(context);

                // Optimistically update UI immediately
                final userProfile = Provider.of<UserProfile>(context, listen: false);
                final currentResponse = userProfile.profileResponse;
                if (currentResponse != null) {
                  // Create updated response with pending status
                  final updatedPersonalDetail = PersonalDetail(
                    photoRequest: 'pending',
                    chatRequest: currentResponse.data.personalDetail.chatRequest,
                    firstName: currentResponse.data.personalDetail.firstName,
                    lastName: currentResponse.data.personalDetail.lastName,
                    profilePicture: currentResponse.data.personalDetail.profilePicture,
                    usertype: currentResponse.data.personalDetail.usertype,
                    isVerified: currentResponse.data.personalDetail.isVerified,
                    privacy: currentResponse.data.personalDetail.privacy,
                    city: currentResponse.data.personalDetail.city,
                    country: currentResponse.data.personalDetail.country,
                    educationmedium: currentResponse.data.personalDetail.educationmedium,
                    educationtype: currentResponse.data.personalDetail.educationtype,
                    faculty: currentResponse.data.personalDetail.faculty,
                    degree: currentResponse.data.personalDetail.degree,
                    areyouworking: currentResponse.data.personalDetail.areyouworking,
                    occupationtype: currentResponse.data.personalDetail.occupationtype,
                    companyname: currentResponse.data.personalDetail.companyname,
                    designation: currentResponse.data.personalDetail.designation,
                    workingwith: currentResponse.data.personalDetail.workingwith,
                    annualincome: currentResponse.data.personalDetail.annualincome,
                    businessname: currentResponse.data.personalDetail.businessname,
                    memberid: currentResponse.data.personalDetail.memberid,
                    heightName: currentResponse.data.personalDetail.heightName,
                    maritalStatusId: currentResponse.data.personalDetail.maritalStatusId,
                    maritalStatusName: currentResponse.data.personalDetail.maritalStatusName,
                    motherTongue: currentResponse.data.personalDetail.motherTongue,
                    aboutMe: currentResponse.data.personalDetail.aboutMe,
                    birthDate: currentResponse.data.personalDetail.birthDate,
                    disability: currentResponse.data.personalDetail.disability,
                    bloodGroup: currentResponse.data.personalDetail.bloodGroup,
                    religionName: currentResponse.data.personalDetail.religionName,
                    communityName: currentResponse.data.personalDetail.communityName,
                    subCommunityName: currentResponse.data.personalDetail.subCommunityName,
                    manglik: currentResponse.data.personalDetail.manglik,
                    birthtime: currentResponse.data.personalDetail.birthtime,
                    birthcity: currentResponse.data.personalDetail.birthcity,
                    photoRequestType: 'sent',
                    chatRequestType: currentResponse.data.personalDetail.chatRequestType,
                  );

                  final updatedData = ProfileData(
                    personalDetail: updatedPersonalDetail,
                    familyDetail: currentResponse.data.familyDetail,
                    lifestyle: currentResponse.data.lifestyle,
                    partner: currentResponse.data.partner,
                  );

                  final optimisticResponse = ProfileResponse(
                    status: currentResponse.status,
                    data: updatedData,
                    partnerMatch: currentResponse.partnerMatch,
                    gallery: currentResponse.gallery,
                    accessControl: currentResponse.accessControl,
                  );

                  userProfile.updateFromResponse(optimisticResponse);
                }

                // Show success message immediately
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Photo request sent successfully!'),
                    backgroundColor: Colors.green,
                    duration: Duration(seconds: 2),
                  ),
                );

                // Send request in background without blocking UI
                try {
                  final service = ProfileService();
                  final result = await service.sendPhotoRequest(
                    myId: myid.toString(),
                    userId: widget.userId,
                  );

                  // If request failed, revert the optimistic update
                  if (result['status'] != 'success') {
                    await _refreshProfile(context);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            result['message']?.toString().isNotEmpty == true
                                ? result['message'].toString()
                                : 'Unable to send photo request right now.',
                          ),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                } catch (e) {
                  // Revert on error
                  await _refreshProfile(context);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Failed to send photo request: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              child: Text(
                'SEND',
                style: TextStyle(color: Theme.of(context).primaryColor),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _handleChatRequest(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Send Chat Request'),
          content: const Text(
              'Do you want to request chat access from this user?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCEL'),
            ),
            TextButton(
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                final userDataString = prefs.getString('user_data');
                final userData = jsonDecode(userDataString!);
                final myid = int.tryParse(userData["id"].toString());
                Navigator.pop(context);

                // Optimistically update UI immediately
                final userProfile = Provider.of<UserProfile>(context, listen: false);
                final currentResponse = userProfile.profileResponse;
                if (currentResponse != null) {
                  // Create updated response with pending status
                  final updatedPersonalDetail = PersonalDetail(
                    photoRequest: currentResponse.data.personalDetail.photoRequest,
                    chatRequest: 'pending',
                    firstName: currentResponse.data.personalDetail.firstName,
                    lastName: currentResponse.data.personalDetail.lastName,
                    profilePicture: currentResponse.data.personalDetail.profilePicture,
                    usertype: currentResponse.data.personalDetail.usertype,
                    isVerified: currentResponse.data.personalDetail.isVerified,
                    privacy: currentResponse.data.personalDetail.privacy,
                    city: currentResponse.data.personalDetail.city,
                    country: currentResponse.data.personalDetail.country,
                    educationmedium: currentResponse.data.personalDetail.educationmedium,
                    educationtype: currentResponse.data.personalDetail.educationtype,
                    faculty: currentResponse.data.personalDetail.faculty,
                    degree: currentResponse.data.personalDetail.degree,
                    areyouworking: currentResponse.data.personalDetail.areyouworking,
                    occupationtype: currentResponse.data.personalDetail.occupationtype,
                    companyname: currentResponse.data.personalDetail.companyname,
                    designation: currentResponse.data.personalDetail.designation,
                    workingwith: currentResponse.data.personalDetail.workingwith,
                    annualincome: currentResponse.data.personalDetail.annualincome,
                    businessname: currentResponse.data.personalDetail.businessname,
                    memberid: currentResponse.data.personalDetail.memberid,
                    heightName: currentResponse.data.personalDetail.heightName,
                    maritalStatusId: currentResponse.data.personalDetail.maritalStatusId,
                    maritalStatusName: currentResponse.data.personalDetail.maritalStatusName,
                    motherTongue: currentResponse.data.personalDetail.motherTongue,
                    aboutMe: currentResponse.data.personalDetail.aboutMe,
                    birthDate: currentResponse.data.personalDetail.birthDate,
                    disability: currentResponse.data.personalDetail.disability,
                    bloodGroup: currentResponse.data.personalDetail.bloodGroup,
                    religionName: currentResponse.data.personalDetail.religionName,
                    communityName: currentResponse.data.personalDetail.communityName,
                    subCommunityName: currentResponse.data.personalDetail.subCommunityName,
                    manglik: currentResponse.data.personalDetail.manglik,
                    birthtime: currentResponse.data.personalDetail.birthtime,
                    birthcity: currentResponse.data.personalDetail.birthcity,
                    photoRequestType: currentResponse.data.personalDetail.photoRequestType,
                    chatRequestType: 'sent',
                  );

                  final updatedData = ProfileData(
                    personalDetail: updatedPersonalDetail,
                    familyDetail: currentResponse.data.familyDetail,
                    lifestyle: currentResponse.data.lifestyle,
                    partner: currentResponse.data.partner,
                  );

                  final optimisticResponse = ProfileResponse(
                    status: currentResponse.status,
                    data: updatedData,
                    partnerMatch: currentResponse.partnerMatch,
                    gallery: currentResponse.gallery,
                    accessControl: currentResponse.accessControl,
                  );

                  userProfile.updateFromResponse(optimisticResponse);
                }

                // Show success message immediately
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Chat request sent successfully!'),
                    backgroundColor: Colors.green,
                    duration: Duration(seconds: 2),
                  ),
                );

                // Send request in background without blocking UI
                try {
                  final service = ProfileService();
                  final result = await service.sendChatRequest(
                    myId: myid.toString(),
                    userId: widget.userId,
                  );

                  // If request failed, revert the optimistic update
                  if (result['status'] != 'success') {
                    await _refreshProfile(context);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            result['message']?.toString().isNotEmpty == true
                                ? result['message'].toString()
                                : 'Unable to send chat request right now.',
                          ),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                } catch (e) {
                  // Revert on error
                  await _refreshProfile(context);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Failed to send chat request: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              child: Text(
                'SEND',
                style: TextStyle(color: Theme.of(context).primaryColor),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _refreshProfile(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final userDataString = prefs.getString('user_data');
    final userData = jsonDecode(userDataString!);
    final myid = int.tryParse(userData["id"].toString());
    try {
      final service = ProfileService();
      final results = await Future.wait([
        service.fetchProfile(
          myId: myid,
          userId: widget.userId,
        ),
        service.fetchMatchedProfiles(
          userId: myid.toString(),
        ),
      ]);
      final response = results[0] as ProfileResponse;
      final matchedProfiles = results[1] as List<MatchedProfile>;

      // Update the profile with both sets of data
      final userProfile = Provider.of<UserProfile>(context, listen: false);
      userProfile.updateProfileData(response, matchedProfiles);

      debugPrint('✅ Loaded ${matchedProfiles.length} matched profiles');

    } catch (e) {
      debugPrint('❌ Error refreshing profile: $e');
    }
  }
}

// ─── Refactored Sections ─────────────────────────────────────────

class _ProfileHeaderSection extends StatelessWidget {
  String userid;
  final UserProfile userProfile;
  final Color red;
  final LinearGradient buttonGradient;
  final VoidCallback onPhotoRequestPressed;
  final VoidCallback onUpgradePressed;
  final bool isOnline;
  final DateTime? lastSeen;

   _ProfileHeaderSection({
    required this.userProfile,
    required this.red,
    required this.buttonGradient,
    required this.onPhotoRequestPressed,
    required this.onUpgradePressed,
    required this.userid,
    this.isOnline = false,
    this.lastSeen,
  });

  @override
  Widget build(BuildContext context) {
    // Blur profile photo if shouldBlurPhotos is true
    final bool shouldBlurPhoto = userProfile.shouldBlurPhotos;

    return Container(
      //color: Colors.white,
     // padding: const EdgeInsets.all(1),
      child: Column(
        children: <Widget>[
          Stack(
            alignment: Alignment.bottomRight,
            children: <Widget>[
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: red, width: 4),
                ),
                child: CircleAvatar(
                  radius: 45,
                  backgroundImage: shouldBlurPhoto
                      ? null
                      : NetworkImage(userProfile.avatarUrl),
                  backgroundColor: Colors.grey.shade200,
                  child: shouldBlurPhoto
                      ? ClipOval(
                    child: ImageFiltered(
                      imageFilter: ImageFilter.blur(
                        sigmaX: 5.0,
                        sigmaY: 5.0,
                      ),
                      child: Image.network(
                        userProfile.avatarUrl,
                        width: 110,
                        height: 110,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                        const Icon(Icons.person, size: 55),
                      ),
                    ),
                  )
                      : (userProfile.avatarUrl.isEmpty
                      ? const Icon(Icons.person, size: 55)
                      : null),
                ),
              ),
              if (userProfile.isVerified)
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: red, width: 2.5),
                  ),
                  child: Icon(Icons.verified, color: red, size: 15),
                ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            "MS:${userid} ${userProfile.name}",
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          if (isOnline)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: const BoxDecoration(
                    color: Color(0xFF22C55E),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                const Text(
                  'Online',
                  style: TextStyle(
                    color: Color(0xFF22C55E),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            )
          else if (lastSeen != null)
            Text(
              formatLastSeen(lastSeen!),
              style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
            ),
          const SizedBox(height: 3),
          if (userProfile.studentStatus.isNotEmpty)
            Text(
              userProfile.studentStatus,
              style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          const SizedBox(height: 3),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.location_on, color: red, size: 15),
              const SizedBox(width: 3),
              if (userProfile.location.isNotEmpty)
                Flexible(
                  child: Text(
                    userProfile.location,
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
          if (userProfile.bio.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              userProfile.bio,
              textAlign: TextAlign.center,
              style: const TextStyle(height: 1.4, fontSize: 13),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 10),

          // Photo Request Button - Show if photos are blurred
          if (userProfile.shouldBlurPhotos)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildPhotoRequestButton(context),
            ),

          // Shortlist Button
          _GradientButton(
            text: "Shortlist this Profile",
            icon: Icons.favorite_border,
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Profile shortlisted!')),
              );
            },
            gradient: buttonGradient,
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoRequestButton(BuildContext context) {
    // ❌ NOT PAID
    if (!userProfile.isCurrentUserPaid) {
      return Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.blue.shade400, Colors.blue.shade600],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.blue.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onUpgradePressed,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.star, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'Premium Feature',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          'Upgrade to View Photos',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 16),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // 🔥 RECEIVED REQUEST → Accept/Reject with beautiful design
    if (userProfile.isPhotoRequestReceived) {
      return Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.purple.shade50, Colors.pink.shade50],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.purple.shade200.withOpacity(0.5)),
          boxShadow: [
            BoxShadow(
              color: Colors.purple.withOpacity(0.1),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              // Avatar + Name Row
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [red, Colors.pink.shade400],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: CircleAvatar(
                      radius: 24,
                      backgroundColor: Colors.white,
                      backgroundImage: userProfile.avatarUrl.isNotEmpty
                          ? NetworkImage(userProfile.avatarUrl)
                          : null,
                      child: userProfile.avatarUrl.isEmpty
                          ? const Icon(Icons.person, color: Colors.grey)
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          userProfile.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.purple.shade100,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.photo_camera,
                                size: 14,
                                color: Colors.purple.shade700,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Wants to see your photos',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.purple.shade700,
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

              const SizedBox(height: 20),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: _buildActionButton(
                      context: context,
                      text: "Accept",
                      icon: Icons.check_circle,
                      color: Colors.green,
                      onPressed: () async {
                        final prefs = await SharedPreferences.getInstance();
                        final userData = jsonDecode(prefs.getString('user_data')!);
                        final myId = userData["id"].toString();

                        final service = ProfileService();
                        final result = await service.acceptRequest(
                          myId: myId,
                          senderId: userid,
                          type: "Photo",
                        );

                        if (result['status'] == 'success') {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Row(
                                children: const [
                                  Icon(Icons.check_circle, color: Colors.white),
                                  SizedBox(width: 8),
                                  Text("Photo request accepted"),
                                ],
                              ),
                              backgroundColor: Colors.green,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          );

                          final parentState =
                          context.findAncestorStateOfType<_ProfileScreenState>();
                          parentState?._refreshProfile(context);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildActionButton(
                      context: context,
                      text: "Decline",
                      icon: Icons.cancel,
                      color: Colors.red,
                      onPressed: () async {
                        final prefs = await SharedPreferences.getInstance();
                        final userData = jsonDecode(prefs.getString('user_data')!);
                        final myId = userData["id"].toString();

                        final service = ProfileService();
                        final result = await service.rejectRequest(
                          myId: myId,
                          senderId: userid,
                          type: "Photo",
                        );

                        if (result['status'] == 'success') {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Row(
                                children: const [
                                  Icon(Icons.info, color: Colors.white),
                                  SizedBox(width: 8),
                                  Text("Photo request rejected"),
                                ],
                              ),
                              backgroundColor: Colors.orange,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          );

                          final parentState =
                          context.findAncestorStateOfType<_ProfileScreenState>();
                          parentState?._refreshProfile(context);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    // ⏳ SENT REQUEST
    if (userProfile.isPhotoRequestSent) {
      return Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.orange.shade200),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.hourglass_bottom, color: Colors.orange.shade700, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Request Pending',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.orange,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Waiting for ${userProfile.name.split(' ').first} to respond',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 13,
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

    // ❌ REJECTED
    if (userProfile.isPhotoRequestRejected) {
      return Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.block, color: Colors.grey.shade600, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Request Declined',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Your photo request was not accepted',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 13,
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

    // 🔥 BOTH SIDE NOT SENT → SHOW REQUEST BUTTON
    if (userProfile.isPhotoRequestNone) {
      return Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [red, Colors.pink.shade400],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: red.withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPhotoRequestPressed,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.photo_camera, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Private Photos',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          'Request Photo Access',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.arrow_forward,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

// Helper method for action buttons
  Widget _buildActionButton({
    required BuildContext context,
    required String text,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withOpacity(0.8), color],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.3),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white, size: 18),
                const SizedBox(width: 6),
                Text(
                  text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }}

class _ContactInfoSection extends StatelessWidget {
  final List<ContactInfoItem> contactInfo;
  final Color red;
  final LinearGradient buttonGradient;
  final LinearGradient dimmedButtonGradient;
  final Color dimmedButtonTextColor;
  final UserProfile userProfile;
  final VoidCallback onChatRequestPressed;
  final VoidCallback onUpgradePressed;
  final String userId;
  final String userName;

  // Add these state variables that you'll need to pass from parent
  final String currentUserId;
  final String currentUserName;
  final String currentUserImage;
  final String docStatus;
  final String userType;

  const _ContactInfoSection({
    required this.contactInfo,
    required this.red,
    required this.buttonGradient,
    required this.dimmedButtonGradient,
    required this.dimmedButtonTextColor,
    required this.userProfile,
    required this.onChatRequestPressed,
    required this.onUpgradePressed,
    required this.userId,
    required this.userName,
    required this.currentUserId,
    required this.currentUserName,
    required this.currentUserImage,
    required this.docStatus,
    required this.userType,
  });

  @override
  Widget build(BuildContext context) {
    return _CardSection(
      title: "Contact Info",
      red: red,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Free Inquiry Button - Now navigates to Admin Chat
          Padding(
            padding: const EdgeInsets.only(bottom: 16.0),
            child: _GradientButton(
              text: "Free inquiry from admin",
              icon: Icons.support_agent,
              onPressed: () {
                _navigateToAdminChat(context);
              },
              gradient: buttonGradient,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            ),
          ),

          // Chat/Request Button
          Padding(
            padding: const EdgeInsets.only(bottom: 16.0),
            child: _buildChatButton(context),
          ),
        ],
      ),
    );
  }

  String _calculateAgeFromBirthDate(String birthDate) {
    if (birthDate.isEmpty || birthDate == 'Not specified' || birthDate == 'Not available') {
      return 'N/A';
    }
    try {
      DateTime? dob = DateTime.tryParse(birthDate);
      if (dob == null) {
        final match = RegExp(r'^(\d{2})-(\d{2})-(\d{4})$').firstMatch(birthDate);
        if (match != null) {
          dob = DateTime.tryParse(
            '${match.group(3)}-${match.group(2)}-${match.group(1)}',
          );
        }
      }
      if (dob == null) return 'N/A';
      final now = DateTime.now();
      int age = now.year - dob.year;
      if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) {
        age--;
      }
      return age.toString();
    } catch (_) {
      return 'N/A';
    }
  }

  Future<void> _navigateToAdminChat(BuildContext context) async {
    final Map<String, dynamic> profileData = {
      'userId': userId,
      'name': userProfile.name,
      'lastName': userProfile.profileResponse?.data.personalDetail.lastName ?? '',
      'firstName': userProfile.profileResponse?.data.personalDetail.firstName ?? '',
      'profileImage': userProfile.avatarUrl,
      'bio': userProfile.bio,
      'location': userProfile.location,
      'age': _calculateAgeFromBirthDate(userProfile.birthDate),
      'height': userProfile.height,
      'religion': userProfile.religion,
      'community': userProfile.community,
      'occupation': userProfile.occupation,
      'education': userProfile.degree,
      'shouldBlurPhoto': userProfile.shouldBlurPhotos,
    };

    final prefs = await SharedPreferences.getInstance();
    final userDataString = prefs.getString('user_data');
    final userData = jsonDecode(userDataString!);
    final senderId = userData["id"].toString();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AdminChatScreen(
          senderID: senderId,
          userName: "Admin",
          isAdmin: false,
          initialProfileData: profileData,
        ),
      ),
    );
  }

  void _showDocumentVerificationDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: const LinearGradient(
                colors: [
                  Color(0xFFFF6B6B),
                  Color(0xFF4ECDC4),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.verified_user_rounded,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  "Verify Your Identity",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  "You're a paid member! Please verify your documents to start chatting with other members.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 28),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.pop(context);
                        },
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.white),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text(
                          "Later",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) => IDVerificationScreen()
                              )
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text(
                          "Verify Now",
                          style: TextStyle(
                            color: Color(0xFFFF6B6B),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showDocumentPendingDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              color: Colors.white,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.hourglass_empty,
                    color: Colors.orange,
                    size: 36,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  "Verification Pending",
                  style: TextStyle(
                    color: Colors.orange,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  "Your document verification is in progress. You'll be able to chat once it's approved.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 28),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
                  ),
                  child: const Text(
                    "Got it",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showDocumentRejectedDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              color: Colors.white,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.error_outline,
                    color: Colors.red,
                    size: 36,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  "Document Rejected",
                  style: TextStyle(
                    color: Colors.red,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  "Your document was rejected. Please upload a valid document to continue.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 28),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.pop(context);
                        },
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.grey),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text(
                          "Cancel",
                          style: TextStyle(
                            color: Colors.grey,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) => IDVerificationScreen()
                              )
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text(
                          "Re-upload",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showUpgradeChatDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: const LinearGradient(
                colors: [
                  Color(0xFFff0000),
                  Color(0xFF2575FC),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.chat_bubble_rounded,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  "Upgrade to Chat",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  "Unlock unlimited messaging and premium chat features by upgrading your plan.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 28),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.pop(context);
                        },
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.white),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text(
                          "Skip",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const SubscriptionPage(),
                              )
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text(
                          "Upgrade",
                          style: TextStyle(
                            color: Color(0xFFff0000),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }


  Widget _buildChatButton(BuildContext context) {
    // ❌ NOT PAID - Premium Upgrade Card
    if (!userProfile.isCurrentUserPaid) {
      return Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.blue.shade400, Colors.blue.shade600],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.blue.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onUpgradePressed,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.chat, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'Premium Feature',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          'Upgrade to Start Chat',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 16),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // 🔥 RECEIVED REQUEST → Accept/Reject with beautiful design
    if (userProfile.isChatRequestReceived) {
      return Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.blue.shade50, Colors.indigo.shade50],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.blue.shade200.withOpacity(0.5)),
          boxShadow: [
            BoxShadow(
              color: Colors.blue.withOpacity(0.1),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              // Avatar + Name Row
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.blue, Colors.indigo.shade400],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: CircleAvatar(
                      radius: 24,
                      backgroundColor: Colors.white,
                      backgroundImage: userProfile.avatarUrl.isNotEmpty
                          ? NetworkImage(userProfile.avatarUrl)
                          : null,
                      child: userProfile.avatarUrl.isEmpty
                          ? const Icon(Icons.person, color: Colors.grey)
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          userProfile.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade100,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.chat_bubble,
                                size: 14,
                                color: Colors.blue.shade700,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Wants to chat with you',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.blue.shade700,
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

              const SizedBox(height: 20),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: _buildActionButton(
                      context: context,
                      text: "Accept",
                      icon: Icons.check_circle,
                      color: Colors.green,
                      onPressed: () async {
                        final prefs = await SharedPreferences.getInstance();
                        final userData = jsonDecode(prefs.getString('user_data')!);
                        final myId = userData["id"].toString();

                        final service = ProfileService();
                        final result = await service.acceptRequest(
                          myId: myId,
                          senderId: userId,
                          type: "Chat",
                        );

                        if (result['status'] == 'success') {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Row(
                                children: const [
                                  Icon(Icons.check_circle, color: Colors.white),
                                  SizedBox(width: 8),
                                  Text("Chat request accepted • Start chatting now"),
                                ],
                              ),
                              backgroundColor: Colors.green,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              duration: const Duration(seconds: 3),
                            ),
                          );

                          final parentState =
                          context.findAncestorStateOfType<_ProfileScreenState>();
                          parentState?._refreshProfile(context);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildActionButton(
                      context: context,
                      text: "Decline",
                      icon: Icons.cancel,
                      color: Colors.red,
                      onPressed: () async {
                        final prefs = await SharedPreferences.getInstance();
                        final userData = jsonDecode(prefs.getString('user_data')!);
                        final myId = userData["id"].toString();

                        final service = ProfileService();
                        final result = await service.rejectRequest(
                          myId: myId,
                          senderId: userId,
                          type: "Chat",
                        );

                        if (result['status'] == 'success') {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Row(
                                children: const [
                                  Icon(Icons.info, color: Colors.white),
                                  SizedBox(width: 8),
                                  Text("Chat request declined"),
                                ],
                              ),
                              backgroundColor: Colors.orange,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          );

                          final parentState =
                          context.findAncestorStateOfType<_ProfileScreenState>();
                          parentState?._refreshProfile(context);
                        }
                      },
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.access_time, size: 16, color: Colors.grey.shade600),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Respond within 24 hours to keep the conversation active',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
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
    }

    // ⏳ SENT REQUEST
    if (userProfile.isChatRequestSent) {
      return Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.orange.shade200),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.hourglass_bottom, color: Colors.orange.shade700, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Request Pending',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.orange,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Waiting for ${userProfile.name.split(' ').first} to accept',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'You\'ll be notified when they respond',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 11,
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

    // ✅ ACCEPTED REQUEST - Start Chat Button with Access Control
    if (userProfile.isChatRequestAccepted) {
      return Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.green.shade400, Colors.green.shade600],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.green.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () async {
              // ✅ VERIFIED DOCUMENT AND PAID MEMBER → Can chat
              if (docStatus == "approved" && userType == "paid") {
                try {
                  // Generate chatRoomId (sorted)
                  List<String> ids = [currentUserId, userId];
                  ids.sort();
                  String chatRoomId = ids.join('_');

                  // Chat room is auto-created by the Socket.IO server on first message send.
                  // No need to pre-create it in Firestore.

                  // Navigate
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ChatDetailScreen(
                        chatRoomId: chatRoomId,
                        receiverId: userId,
                        receiverName: userName.isNotEmpty
                            ? userName
                            : "User $userId",
                        receiverImage: resolveApiImageUrl(userProfile.avatarUrl),
                        currentUserId: currentUserId,
                        currentUserName: currentUserName.isNotEmpty
                            ? currentUserName
                            : "User $currentUserId",
                        currentUserImage: resolveApiImageUrl(currentUserImage),
                      ),
                    ),
                  );
                } catch (e) {
                  debugPrint("Error navigating to chat: $e");
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text("Failed to open chat"),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }

              // ❌ DOCUMENT NOT UPLOADED AND FREE MEMBER → Show ID Verification
              else if (docStatus == "not_uploaded" && userType == 'free') {
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => IDVerificationScreen()
                    )
                );
              }

              // ❌ FREE MEMBER BUT DOCUMENT APPROVED → Show Upgrade Dialog
              else if (userType == "free" && docStatus == 'approved') {
                _showUpgradeChatDialog(context);
              }

              // ❌ PAID MEMBER BUT DOCUMENT NOT APPROVED → Show Document Verification
              else if (userType == "paid" && docStatus != 'approved') {
                _showDocumentVerificationDialog(context);
              }

              // ❌ DOCUMENT PENDING → Show Pending Status
              else if (docStatus == "pending") {
                _showDocumentPendingDialog(context);
              }

              // ❌ DOCUMENT REJECTED → Show Re-upload Option
              else if (docStatus == "rejected") {
                _showDocumentRejectedDialog(context);
              }

              // ❌ ANY OTHER CASE → Default to Upgrade
              else {
                _showUpgradeChatDialog(context);
              }
            },
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.chat, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Chat Now',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          'Start Conversation',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.arrow_forward,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // ❌ REJECTED
    if (userProfile.isChatRequestRejected) {
      return Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.chat_bubble_outline, color: Colors.grey.shade600, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Request Declined',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Your chat request was not accepted',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'You can try again after 12 hours',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
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

    // 🔥 BOTH SIDE NOT SENT → SEND REQUEST BUTTON
    if (userProfile.isChatRequestNone) {
      return Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.purple.shade400, Colors.deepPurple.shade600],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.purple.withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onChatRequestPressed,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.chat_bubble_outline, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Start Conversation',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          'Send Chat Request',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.send,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  String _generateChatRoomId(String uid1, String uid2) {
    List<String> ids = [uid1, uid2];
    ids.sort();
    return "${ids[0]}_${ids[1]}";
  }

  Widget _buildActionButton({
    required BuildContext context,
    required String text,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withOpacity(0.8), color],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.3),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white, size: 18),
                const SizedBox(width: 6),
                Text(
                  text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PhotosAlbumSection extends StatelessWidget {
  final List<String> photoAlbumUrls;
  final Color red;
  final LinearGradient buttonGradient;
  final UserProfile userProfile;
  final VoidCallback onUpgradePressed;
  final VoidCallback onPhotoRequestPressed;

  const _PhotosAlbumSection({
    required this.photoAlbumUrls,
    required this.red,
    required this.buttonGradient,
    required this.userProfile,
    required this.onUpgradePressed,
    required this.onPhotoRequestPressed,
  });

  @override
  Widget build(BuildContext context) {
    if (photoAlbumUrls.isEmpty) {
      return const SizedBox.shrink();
    }

    // Blur gallery if shouldBlurPhotos is true
    final bool shouldBlur = userProfile.shouldBlurPhotos;

    return _CardSection(
      title: "Photos Album",
      red: red,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          SizedBox(
            height: 140,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: photoAlbumUrls.length,
              itemBuilder: (BuildContext context, int i) => Padding(
                padding: const EdgeInsets.only(right: 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: !shouldBlur
                      ? Image.network(
                    photoAlbumUrls[i],
                    width: 110,
                    height: 140,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        width: 110,
                        height: 140,
                        color: Colors.grey.shade300,
                        child: const Icon(Icons.broken_image,
                            color: Colors.grey),
                      );
                    },
                  )
                      : ImageFiltered(
                    imageFilter: ImageFilter.blur(
                      sigmaX: 5.0,
                      sigmaY: 5.0,
                    ),
                    child: Container(
                      width: 110,
                      height: 140,
                      color: Colors.grey.shade300,
                      child: Image.network(
                        photoAlbumUrls[i],
                        fit: BoxFit.cover,
                        color: Colors.black.withAlpha(
                          (255 * 0.4).round(),
                        ),
                        colorBlendMode: BlendMode.darken,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: Colors.grey.shade300,
                            child: const Icon(Icons.broken_image,
                                color: Colors.grey),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (shouldBlur)
            Positioned.fill(
              child: Center(
                child: _buildOverlay(context),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOverlay(BuildContext context) {
    // Case 1: User is not paid
    if (!userProfile.isCurrentUserPaid) {
      return _RequestButton(
        text: "Upgrade to View Photos",
        icon: Icons.upgrade,
        onPressed: onUpgradePressed,
        color: Colors.blue,
        isPending: false,
        isRejected: false,
        isAccepted: false,
        isUpgrade: true,
      );
    }

    // Case 2: Request is pending
    if (userProfile.isPhotoRequestPending) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(0.9),
          borderRadius: BorderRadius.circular(30),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            SizedBox(width: 8),
            Text(
              'Photo Request Pending',
              style: TextStyle(color: Colors.white, fontSize: 14),
            ),
          ],
        ),
      );
    }

    // Case 3: Request is rejected
    if (userProfile.isPhotoRequestRejected) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.grey.withOpacity(0.9),
          borderRadius: BorderRadius.circular(30),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.block, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Text(
              'Photo Request Rejected',
              style: TextStyle(color: Colors.white, fontSize: 14),
            ),
          ],
        ),
      );
    }

    // Case 4: Request not sent yet (paid user)
    if (userProfile.isPhotoRequestNotSent) {
      return _RequestButton(
        text: "Send Photo Request",
        icon: Icons.photo_camera,
        onPressed: onPhotoRequestPressed,
        color: red,
        isPending: false,
        isRejected: false,
        isAccepted: false,
        isUpgrade: false,
      );
    }

    // Fallback
    return const SizedBox.shrink();
  }
}

class _DetailsGridSection<T> extends StatelessWidget {
  final String title;
  final List<T> items;
  final Color red;
  final Widget Function(T item, Color red) itemBuilder;

  const _DetailsGridSection({
    required this.title,
    required this.items,
    required this.red,
    required this.itemBuilder,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    return _CardSection(
      title: title,
      red: red,
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 2.3,
          crossAxisSpacing: 8,
          mainAxisSpacing: 4,
        ),
        itemCount: items.length,
        itemBuilder: (BuildContext context, int index) {
          return itemBuilder(items[index], red);
        },
      ),
    );
  }
}

class _MatchOverviewSection extends StatelessWidget {
  final int matchedPreferencesCount;
  final int totalPreferencesCount;
  final Color red;
  final String imageUrl;

  const _MatchOverviewSection({
    required this.matchedPreferencesCount,
    required this.totalPreferencesCount,
    required this.red,
    this.imageUrl = '',
  });

  Color _matchColor(double ratio) {
    if (ratio >= 0.75) return Colors.green;
    if (ratio >= 0.5) return Colors.orange;
    return Colors.red;
  }

  String _matchLabel(double ratio) {
    if (ratio >= 0.75) return 'Great Match';
    if (ratio >= 0.5) return 'Good Match';
    return 'Low Match';
  }

  int get matchPercentage => totalPreferencesCount > 0
      ? ((matchedPreferencesCount / totalPreferencesCount) * 100).round()
      : 0;

  @override
  Widget build(BuildContext context) {
    final total = totalPreferencesCount > 0 ? totalPreferencesCount : 1;
    final double ratio = matchedPreferencesCount / total;
    final int percent = (ratio * 100).round();
    final Color color = _matchColor(ratio);
    final String label = _matchLabel(ratio);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withAlpha((255 * 0.08).round()),
            blurRadius: 10,
          ),
        ],
        border: Border.all(color: color.withOpacity(0.3), width: 1.5),
      ),
      child: Column(
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              CircleAvatar(
                radius: 28,
                backgroundImage: NetworkImage(imageUrl),
                onBackgroundImageError: (_, __) {},
                child: imageUrl.isEmpty
                    ? const Icon(Icons.person, size: 28)
                    : null,
              ),
              const SizedBox(width: 16),
              Flexible(
                child: Text(
                  "$matchPercentage% Match - $matchedPreferencesCount of $totalPreferencesCount preferences",
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Partner Performance',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: Colors.grey.shade800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$matchedPreferencesCount out of $totalPreferencesCount preferences match',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 8,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }
}

class _PartnerPreferenceSection extends StatelessWidget {
  final List<PartnerPreferenceItem> partnerPreferences;
  final Color red;

  const _PartnerPreferenceSection({
    required this.partnerPreferences,
    required this.red,
  });

  @override
  Widget build(BuildContext context) {
    if (partnerPreferences.isEmpty) return const SizedBox.shrink();

    return _CardSection(
      title: "Partner Preference",
      red: red,
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 2.3,
          crossAxisSpacing: 8,
          mainAxisSpacing: 4,
        ),
        itemCount: partnerPreferences.length,
        itemBuilder: (BuildContext context, int index) {
          final PartnerPreferenceItem item = partnerPreferences[index];
          return _PartnerPreferenceGridItem(
            icon: item.icon,
            title: item.title,
            value: item.value,
            matched: item.matched,
            red: red,
          );
        },
      ),
    );
  }
}

class _OtherMatchedProfilesSection extends StatelessWidget {
  static const int _newMemberBadgeCount = 3;
  final List<MatchedProfile> otherMatchedProfiles;
  final Color red;
  final LinearGradient gradient;

  const _OtherMatchedProfilesSection({
    required this.otherMatchedProfiles,
    required this.red,
    required this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    if (otherMatchedProfiles.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                "OTHER MATCHED PROFILE",
                style: TextStyle(
                  color: red,
                  fontWeight: FontWeight.w600,
                  fontSize: 14.5,
                  letterSpacing: 0.4,
                ),
              ),
              Container(
                height: 2,
                width: 40,
                color: red,
                margin: const EdgeInsets.only(top: 4),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 280,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: otherMatchedProfiles.length,
              itemBuilder: (BuildContext context, int index) {
                final MatchedProfile profile = otherMatchedProfiles[index];
                return _MatchedProfileCard(
                  profile: profile,
                  red: red,
                  gradient: gradient,
                  isNewMember: index < _newMemberBadgeCount,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Helper Widgets ──────────────────────────────────────────────

/// A reusable card section with a title and child content.
class _CardSection extends StatelessWidget {
  final String title;
  final Widget child;
  final Color red;

  const _CardSection({
    required this.title,
    required this.child,
    required this.red,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withAlpha((255 * 0.06).round()),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title.toUpperCase(),
                  style: TextStyle(
                    color: red,
                    fontWeight: FontWeight.w600,
                    fontSize: 14.5,
                    letterSpacing: 0.4,
                  ),
                ),
                Container(
                  height: 2,
                  width: 40,
                  color: red,
                  margin: const EdgeInsets.only(top: 4),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(padding: const EdgeInsets.all(16), child: child),
        ],
      ),
    );
  }
}

/// A button with a gradient background.
class _GradientButton extends StatelessWidget {
  final String text;
  final IconData? icon;
  final VoidCallback onPressed;
  final LinearGradient gradient;
  final EdgeInsetsGeometry padding;
  final Color textColor;

  const _GradientButton({
    required this.text,
    this.icon,
    required this.onPressed,
    required this.gradient,
    this.padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
    this.textColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(30),
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          foregroundColor: textColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
          padding: padding,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (icon != null) Icon(icon, size: 20),
            if (icon != null) const SizedBox(width: 8),
            Flexible(
              child: Text(
                text,
                style: const TextStyle(fontSize: 16),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A gradient button specifically for direct chat functionality, handling its own dialog.

/// Widget for displaying a single detail item in a grid (Personal, Community, Education, Life Style).
class _DetailGridItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final Color red;

  const _DetailGridItem({
    required this.icon,
    required this.title,
    required this.value,
    required this.red,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, color: red, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.black87,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Widget for displaying a single partner preference item in a grid.
class _PartnerPreferenceGridItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final bool matched;
  final Color red;

  const _PartnerPreferenceGridItem({
    required this.icon,
    required this.title,
    required this.value,
    required this.matched,
    required this.red,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, color: red, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                title,
                style: const TextStyle(fontSize: 13, color: Colors.black87),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Icon(
          matched ? Icons.check_circle_rounded : Icons.cancel_rounded,
          color: matched ? Colors.green.shade600 : Colors.red.shade600,
          size: 20,
        ),
      ],
    );
  }
}

/// Widget for displaying a single matched profile card.
/// Widget for displaying a single matched profile card.
/// Widget for displaying a single matched profile card.
class _MatchedProfileCard extends StatelessWidget {
  final MatchedProfile profile;
  final Color red;
  final LinearGradient gradient;
  final bool isNewMember;

  const _MatchedProfileCard({
    required this.profile,
    required this.red,
    required this.gradient,
    this.isNewMember = false,
  });

  @override
  Widget build(BuildContext context) {
    // Use backend-computed canViewPhoto (respects target's privacy + viewer's plan/verification)
    final bool canViewPhoto = profile.canViewPhoto;

    return Container(
      width: 180,
      margin: const EdgeInsets.only(right: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withAlpha((255 * 0.08).round()),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Profile Image with Match Percent Badge and Photo Request Status
          Stack(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                child: canViewPhoto
                    ? Image.network(
                  profile.imageUrl,
                  height: 120,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      height: 120,
                      width: double.infinity,
                      color: Colors.grey.shade300,
                      child: const Icon(Icons.person, size: 50, color: Colors.grey),
                    );
                  },
                )
                    : ImageFiltered(
                  imageFilter: ImageFilter.blur(
                    sigmaX: 5.0,
                    sigmaY: 5.0,
                  ),
                  child: Container(
                    height: 120,
                    width: double.infinity,
                    color: Colors.grey.shade300,
                    child: profile.imageUrl.isNotEmpty
                        ? Image.network(
                      profile.imageUrl,
                      fit: BoxFit.cover,
                      color: Colors.black.withAlpha(
                        (255 * 0.4).round(),
                      ),
                      colorBlendMode: BlendMode.darken,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          color: Colors.grey.shade300,
                          child: const Icon(Icons.person, size: 50, color: Colors.grey),
                        );
                      },
                    )
                        : const Icon(Icons.person, size: 50, color: Colors.grey),
                  ),
                ),
              ),

              // Match Percent Badge
              if (profile.matchPercent > 0)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _getMatchColor(profile.matchPercent),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      "${profile.matchPercent}%",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

              if (isNewMember)
                Positioned(
                  top: 38,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: red,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'New',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),

              // Verified Badge
              if (profile.isVerifiedBool)
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.verified, color: Colors.blue, size: 16),
                  ),
                ),

              // Photo Request Status Badge (if not accepted)
              if (!canViewPhoto)
                Positioned(
                  bottom: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _getPhotoRequestColor(profile.photoRequest),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _getPhotoRequestIcon(profile.photoRequest),
                          color: Colors.white,
                          size: 10,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          _getPhotoRequestText(profile.photoRequest),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    "MS: ${profile.memberid?.isNotEmpty == true ? profile.memberid : profile.userid} ${profile.name}",
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    profile.ageAndHeight,
                    style: const TextStyle(color: Colors.grey, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  const SizedBox(height: 8),
                  _buildInfoRow("Location:", "${profile.city}, ${profile.country}"),
                  _buildInfoRow("Profession:", profile.profession),

                  // Photo Request Status (if not accepted)
                  if (!canViewPhoto)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _getPhotoRequestColor(profile.photoRequest).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _getPhotoRequestIcon(profile.photoRequest),
                              color: _getPhotoRequestColor(profile.photoRequest),
                              size: 12,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _getPhotoRequestText(profile.photoRequest),
                              style: TextStyle(
                                color: _getPhotoRequestColor(profile.photoRequest),
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),

          // Action Buttons
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Like Button
                Expanded(
                  child: _SmallIconButton(
                    icon: profile.like ? Icons.favorite : Icons.favorite_border,
                    color: profile.like ? Colors.red : Colors.grey,
                    onPressed: () {
                      // Handle like/unlike
                      // You'll need to implement setState or state management
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(profile.like ? 'Removed like' : 'Liked ${profile.firstName}'),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                // View Profile Button
                Expanded(
                  flex: 2,
                  child: _GradientButton(
                    text: "View",
                    onPressed: () async {
                      final prefs = await SharedPreferences.getInstance();
                      final userDataString = prefs.getString('user_data');
                      final userData = jsonDecode(userDataString!);
                      final myid = int.tryParse(userData["id"].toString());
                      // Navigate to profile view
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ProfileLoader(
                            myId:myid.toString(),
                            userId: profile.userid.toString(),
                          ),
                        ),
                      );
                    },
                    gradient: gradient,
                    icon: Icons.person_outline,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
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

  Color _getMatchColor(int percent) {
    if (percent >= 80) return const Color(0xFF2E7D32);
    if (percent >= 60) return const Color(0xFF1565C0);
    if (percent >= 40) return const Color(0xFFE65100);
    return const Color(0xFFC62828);
  }

  // Helper methods for photo request status
  Color _getPhotoRequestColor(String status) {
    switch (status.toLowerCase()) {
      case 'accepted':
        return Colors.green;
      case 'pending':
        return Colors.orange;
      case 'rejected':
        return Colors.red;
      case 'not sent':
      default:
        return Colors.grey;
    }
  }

  IconData _getPhotoRequestIcon(String status) {
    switch (status.toLowerCase()) {
      case 'accepted':
        return Icons.check_circle;
      case 'pending':
        return Icons.hourglass_empty;
      case 'rejected':
        return Icons.block;
      case 'not sent':
      default:
        return Icons.lock;
    }
  }

  String _getPhotoRequestText(String status) {
    switch (status.toLowerCase()) {
      case 'accepted':
        return 'Photo Unlocked';
      case 'pending':
        return 'Request Pending';
      case 'rejected':
        return 'Request Rejected';
      case 'not sent':
        return 'Photo Locked';
      default:
        return status;
    }
  }

  // Helper widget to build consistent info rows
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 11,
              color: Colors.black87,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
}

// Small icon button helper
class _SmallIconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  const _SmallIconButton({
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(20),
      ),
      child: IconButton(
        icon: Icon(icon, size: 18),
        color: color,
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(
          minWidth: 32,
          minHeight: 32,
        ),
      ),
    );
  }
}


// Small icon button helper

// Request Button Widget
class _RequestButton extends StatelessWidget {
  final String text;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color color;
  final bool isPending;
  final bool isRejected;
  final bool isAccepted;
  final bool isUpgrade;

  const _RequestButton({
    required this.text,
    required this.icon,
    this.onPressed,
    required this.color,
    required this.isPending,
    required this.isRejected,
    required this.isAccepted,
    required this.isUpgrade,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: (!isPending && !isRejected && !isAccepted && !isUpgrade && onPressed != null)
            ? LinearGradient(
          colors: [color, color.withOpacity(0.8)],
        )
            : null,
        color: (isPending || isRejected || isAccepted || isUpgrade || onPressed == null)
            ? color
            : null,
        borderRadius: BorderRadius.circular(30),
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (isPending)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            else
              Icon(icon, size: 20),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                text,
                style: const TextStyle(fontSize: 14, color: Colors.white),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
