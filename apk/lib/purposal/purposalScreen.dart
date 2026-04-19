import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:ms2026/Auth/Screen/signupscreen10.dart';
import 'package:ms2026/Chat/ChatlistScreen.dart';
import 'package:ms2026/Home/Screen/HomeScreenPage.dart';
import 'package:ms2026/Package/PackageScreen.dart';
import 'package:ms2026/ReUsable/loading_widgets.dart';
import 'package:ms2026/purposal/purposalservice.dart';
import 'package:ms2026/purposal/requestcard.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../Chat/ChatdetailsScreen.dart';
import '../Models/masterdata.dart';
import 'Purposalmodel.dart';
import 'package:ms2026/config/app_endpoints.dart';

class ProposalsPage extends StatefulWidget {
  const ProposalsPage({super.key});

  @override
  State<ProposalsPage> createState() => _ProposalsPageState();
}

class _ProposalsPageState extends State<ProposalsPage> {
  String userid = '';
  int selectedTab = 0;
  String usertye = '';
  String userimage = '';
  var pageno;

  // PageController for swiping between tabs
  late PageController _pageController;

  bool loading = true;
  List<ProposalModel> list = [];

  // Separate lists for each tab
  List<ProposalModel> receivedList = [];
  List<ProposalModel> sentList = [];
  List<ProposalModel> acceptedList = [];

  // Loading states for each tab
  bool loadingReceived = true;
  bool loadingSent = false;
  bool loadingAccepted = false;

  // Track which tabs have been loaded to avoid duplicate fetches
  final Set<int> _loadedTabs = {};

  // Refresh shimmer state for each tab
  bool _refreshingReceived = false;
  bool _refreshingSent = false;
  bool _refreshingAccepted = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: selectedTab);
    _loadInitialData();
    loadMasterData();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// LOAD INITIAL DATA - only loads the first (active) tab
  Future<void> _loadInitialData() async {
    await _loadDataForTab(0);
  }

  void loadMasterData() async {
    final prefs = await SharedPreferences.getInstance();
    final userDataString = prefs.getString('user_data');
    final userData = jsonDecode(userDataString!);
    final userId = int.tryParse(userData["id"].toString());
    try {
      UserMasterData user = await fetchUserMasterData(userId.toString());

      print("Name: ${user.firstName} ${user.lastName}");
      print("Usertype: ${user.usertype}");
      print("Page No: ${user.pageno}");
      print("Profile: ${user.profilePicture}");
      setState(() {
        usertye = user.usertype;
        userimage = user.profilePicture;
        pageno = user.pageno;
      });
    } catch (e) {
      print("Error: $e");
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

  /// LOAD DATA FOR SPECIFIC TAB
  Future<void> _loadDataForTab(int tabIndex) async {
    final prefs = await SharedPreferences.getInstance();
    final userDataString = prefs.getString('user_data');
    final userData = jsonDecode(userDataString!);
    final userId = int.tryParse(userData["id"].toString());

    if (mounted) {
      setState(() {
        userid = userId.toString();
        // Set loading state for specific tab
        switch (tabIndex) {
          case 0:
            loadingReceived = true;
            break;
          case 1:
            loadingSent = true;
            break;
          case 2:
            loadingAccepted = true;
            break;
        }
      });
    }

    try {
      String type = _getTypeFromTab(tabIndex);
      final result = await ProposalService.fetchProposals(userId.toString(), type);

      if (mounted) {
        setState(() {
          _loadedTabs.add(tabIndex);
          switch (tabIndex) {
            case 0:
              receivedList = result;
              loadingReceived = false;
              break;
            case 1:
              sentList = result;
              loadingSent = false;
              break;
            case 2:
              acceptedList = result;
              loadingAccepted = false;
              break;
          }
        });
      }
    } catch (e) {
      print("Error loading proposals: $e");
      if (mounted) {
        setState(() {
          _loadedTabs.add(tabIndex);
          switch (tabIndex) {
            case 0:
              receivedList = [];
              loadingReceived = false;
              break;
            case 1:
              sentList = [];
              loadingSent = false;
              break;
            case 2:
              acceptedList = [];
              loadingAccepted = false;
              break;
          }
        });
      }
    }
  }

  String _getTypeFromTab(int tabIndex) {
    switch (tabIndex) {
      case 0:
        return "received";
      case 1:
        return "sent";
      case 2:
        return "accepted";
      default:
        return "received";
    }
  }

  /// HANDLE TAB SELECTION
  void _onTabSelected(int index) {
    if (selectedTab != index) {
      setState(() => selectedTab = index);
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      // Lazily load the tab data only if it hasn't been loaded yet
      if (!_loadedTabs.contains(index)) {
        _loadDataForTab(index);
      }
    }
  }

  /// REFRESH DATA FOR A SPECIFIC TAB
  void _refreshTabData(int tabIndex) {
    _loadDataForTab(tabIndex);
  }

  /// REFRESH ALL TABS
  void _refreshAllTabs() {
    Future.wait([
      _loadDataForTab(0),
      _loadDataForTab(1),
      _loadDataForTab(2),
    ]);
  }

  /// HANDLE PAGE CHANGE (from swipe)
  void _onPageChanged(int index) {
    setState(() {
      selectedTab = index;
    });
    // Lazily load the tab data only if it hasn't been loaded yet
    if (!_loadedTabs.contains(index)) {
      _loadDataForTab(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 4),
            _buildTabBar(),
            const SizedBox(height: 8),

            // PAGE VIEW FOR SWIPEABLE CONTENT
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: _onPageChanged,
                children: [
                  _buildTabContent(
                    isLoading: loadingReceived,
                    isRefreshing: _refreshingReceived,
                    list: receivedList,
                    tabIndex: 0,
                  ),
                  _buildTabContent(
                    isLoading: loadingSent || !_loadedTabs.contains(1),
                    isRefreshing: _refreshingSent,
                    list: sentList,
                    tabIndex: 1,
                  ),
                  _buildTabContent(
                    isLoading: loadingAccepted || !_loadedTabs.contains(2),
                    isRefreshing: _refreshingAccepted,
                    list: acceptedList,
                    tabIndex: 2,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFD32F2F), Color(0xFFB71C1C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.arrow_back,
                color: Colors.white,
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Proposals',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 0.3,
                ),
              ),
              Text(
                'Manage your connection requests',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withOpacity(0.8),
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
          const Spacer(),
          GestureDetector(
            onTap: _refreshAllTabs,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.refresh_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            _buildTabItem('Received', 0,
                loadingReceived ? null : receivedList.length),
            _buildTabItem('Sent', 1,
                (loadingSent || !_loadedTabs.contains(1)) ? null : sentList.length),
            _buildTabItem('Accepted', 2,
                (loadingAccepted || !_loadedTabs.contains(2)) ? null : acceptedList.length),
          ],
        ),
      ),
    );
  }

  Widget _buildTabContent({
    required bool isLoading,
    required bool isRefreshing,
    required List<ProposalModel> list,
    required int tabIndex,
  }) {
    if (isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              valueColor:
                  const AlwaysStoppedAnimation<Color>(Color(0xFFD32F2F)),
              strokeWidth: 2.5,
            ),
            const SizedBox(height: 16),
            Text(
              'Loading...',
              style: TextStyle(
                color: Colors.grey.shade500,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    if (list.isEmpty) {
      return _buildEmptyState(tabIndex);
    }

    return RefreshIndicator(
      color: const Color(0xFFD32F2F),
      onRefresh: () async {
        setState(() {
          if (tabIndex == 0) _refreshingReceived = true;
          else if (tabIndex == 1) _refreshingSent = true;
          else _refreshingAccepted = true;
        });
        await _loadDataForTab(tabIndex);
        if (mounted) {
          setState(() {
            if (tabIndex == 0) _refreshingReceived = false;
            else if (tabIndex == 1) _refreshingSent = false;
            else _refreshingAccepted = false;
          });
        }
      },
      child: ShimmerLoading(
        isLoading: isRefreshing,
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          itemCount: list.length,
          itemBuilder: (context, index) {
            return RequestCardDynamic(
              data: list[index],
              tabIndex: tabIndex,
              userid: userid,
              onActionComplete: () {
                _loadDataForTab(tabIndex);
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildEmptyState(int tabIndex) {
    final configs = [
      _EmptyStateConfig(
        icon: Icons.move_to_inbox_rounded,
        title: 'No Received Requests',
        subtitle: 'When someone sends you a request,\nit will appear here.',
        color: const Color(0xFFD32F2F),
      ),
      _EmptyStateConfig(
        icon: Icons.send_rounded,
        title: 'No Sent Requests',
        subtitle: 'Requests you\'ve sent to others\nwill appear here.',
        color: const Color(0xFF1565C0),
      ),
      _EmptyStateConfig(
        icon: Icons.check_circle_outline_rounded,
        title: 'No Accepted Requests',
        subtitle: 'Your accepted connections\nwill appear here.',
        color: const Color(0xFF2E7D32),
      ),
    ];

    final config = configs[tabIndex];

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                color: config.color.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                config.icon,
                size: 44,
                color: config.color.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              config.title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              config.subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade500,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabItem(String title, int index, int? count) {
    final bool active = selectedTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => _onTabSelected(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: active ? const Color(0xFFD32F2F) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: active ? Colors.white : Colors.grey.shade600,
                  fontSize: 13,
                  fontWeight:
                      active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              if (count != null && count > 0) ...[
                const SizedBox(width: 5),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: active
                        ? Colors.white.withOpacity(0.25)
                        : const Color(0xFFD32F2F).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: active ? Colors.white : const Color(0xFFD32F2F),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyStateConfig {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;

  const _EmptyStateConfig({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
  });
}

