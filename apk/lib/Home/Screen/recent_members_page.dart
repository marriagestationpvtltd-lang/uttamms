import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:ms2026/constant/app_colors.dart';
import 'package:ms2026/constant/app_dimensions.dart';
import 'package:ms2026/constant/app_text_styles.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../service/verification_service.dart';
import '../../main.dart';
import '../../ReUsable/privacy_aware_profile_card.dart';
import 'package:ms2026/config/app_endpoints.dart';

class RecentMembersPage extends StatefulWidget {
  final int userId;
  const RecentMembersPage({Key? key, required this.userId}) : super(key: key);

  @override
  State<RecentMembersPage> createState() => _RecentMembersPageState();
}

class _RecentMembersPageState extends State<RecentMembersPage> {
  List<Map<String, dynamic>> _members = [];
  bool _isLoading = true;
  bool _isRefreshing = false;
  String _errorMessage = '';
  bool _hasMore = true;
  int _currentPage = 1;
  final int _perPage = 20;
  final ScrollController _scrollController = ScrollController();
  String _userCreatedDate = '';

  @override
  void initState() {
    super.initState();
    _fetchMembers();
    _scrollController.addListener(_scrollListener);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollListener() {
    if (_scrollController.position.pixels ==
            _scrollController.position.maxScrollExtent &&
        !_isLoading &&
        _hasMore) {
      _fetchMembers(loadMore: true);
    }
  }

  Future<void> _fetchMembers({bool loadMore = false}) async {
    if (loadMore) {
      _currentPage++;
    } else {
      setState(() {
        _isLoading = true;
        _currentPage = 1;
        _members.clear();
      });
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataString = prefs.getString('user_data');
      if (userDataString == null) return;

      final userData = jsonDecode(userDataString);
      final userid = userData["id"];
      _userCreatedDate = userData["created_at"] ?? "";

      final url = Uri.parse(
          '${kApiBaseUrl}/Api2/search_opposite_gender.php?user_id=$userid&sort_by=recent&limit=${_perPage * _currentPage}');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);

        if (data['success'] == true && data['data'] != null) {
          final List members = data['data'];

          // Filter members registered after current user
          final membersList = members.where((member) {
            final memberCreatedDate = member['created_at'] ?? '';
            if (memberCreatedDate.isEmpty || _userCreatedDate.isEmpty) {
              return true;
            }

            try {
              final memberDate = DateTime.parse(memberCreatedDate);
              final userDate = DateTime.parse(_userCreatedDate);
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
              'photo_request':
                  member['photo_request']?.toString().toLowerCase() ?? '',
              'created_at': member['created_at'] ?? '',
            };
          }).toList();

          if (!mounted) return;
          setState(() {
            _members = membersList;
            _isLoading = false;
            _isRefreshing = false;
            _hasMore = membersList.length >= _perPage * _currentPage;
          });
        } else {
          if (!mounted) return;
          setState(() {
            _isLoading = false;
            _isRefreshing = false;
          });
        }
      } else {
        if (!mounted) return;
        setState(() {
          _errorMessage = 'Failed to load members';
          _isLoading = false;
          _isRefreshing = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Error: $e';
        _isLoading = false;
        _isRefreshing = false;
      });
      debugPrint('Exception fetching recent members: $e');
    }
  }

  Future<void> _refreshMembers() async {
    setState(() => _isRefreshing = true);
    await _fetchMembers();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Recently Registered',
          style: AppTextStyles.heading3,
        ),
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
          systemStatusBarContrastEnforced: false,
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _members.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (_errorMessage.isNotEmpty && _members.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: AppColors.textHint),
            const SizedBox(height: 16),
            Text(_errorMessage, style: AppTextStyles.bodyMedium),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _refreshMembers,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: AppDimensions.borderRadiusLG,
                ),
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_members.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_add_alt_1_rounded,
                size: 80, color: AppColors.border),
            const SizedBox(height: 16),
            Text(
              'No recent members found',
              style: AppTextStyles.bodyLarge
                  .copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            Text(
              'Check back later for new members',
              style:
                  AppTextStyles.bodyMedium.copyWith(color: AppColors.textHint),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final crossAxisCount = width >= 1024 ? 4 : width >= 600 ? 3 : 2;
        final childAspectRatio = width >= 1024 ? 0.82 : width >= 600 ? 0.80 : 0.75;

        return RefreshIndicator(
          onRefresh: _refreshMembers,
          color: AppColors.primary,
          child: GridView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(12),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              childAspectRatio: childAspectRatio,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: _members.length + (_hasMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == _members.length) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ),
                );
              }
              return _buildMemberCard(_members[index]);
            },
          ),
        );
      },
    );
  }

  Widget _buildMemberCard(Map<String, dynamic> profile) {
    final lastName = profile['lastName'] ?? '';
    final memberid = profile['memberid'] ?? 'MS';
    final userIdd = profile['userId'] ?? profile['id'];
    final age = profile['age']?.toString() ?? '';
    final city = profile['city'] ?? '';
    final country = profile['country'] ?? '';
    final heightName = profile['heightName'] ?? '';
    final designation = profile['designation'] ?? '';
    final imageUrl = profile['image'] ?? '';
    final isVerified = profile['isVerified']?.toString() == '1';
    final privacy = profile['privacy']?.toString().toLowerCase() ?? '';
    final photoRequest =
        profile['photo_request']?.toString().toLowerCase() ?? '';

    final displayName = memberid != 'N/A' && memberid.isNotEmpty
        ? '$memberid $lastName'
        : 'MS $userIdd $lastName';
    final location = [city, if (country.isNotEmpty) country].join(', ');
    final displayHeight = heightName.isNotEmpty
        ? heightName.replaceAll(RegExp(r'\s*cm.*'), ' cm')
        : null;

    return PrivacyAwareProfileCard(
      imageUrl: imageUrl,
      name: displayName,
      age: age.isNotEmpty ? '$age yrs' : null,
      location: location.isNotEmpty ? location : null,
      height: displayHeight,
      profession: designation.isNotEmpty ? designation : null,
      privacy: privacy,
      photoRequest: photoRequest,
      isVerified: isVerified,
      showNewBadge: true,
      layout: CardLayout.grid,
      onTap: () async {
        final prefs = await SharedPreferences.getInstance();
        final userDataString = prefs.getString('user_data');
        if (userDataString == null) return;
        final userData = jsonDecode(userDataString);
        final myUserId = int.tryParse(userData['id'].toString());
        if (!mounted) return;
        if (await VerificationService.requireVerification(context)) {
          if (!mounted) return;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ProfileLoader(
                userId: userIdd.toString(),
                myId: myUserId.toString(),
              ),
            ),
          );
        }
      },
    );
  }
}
