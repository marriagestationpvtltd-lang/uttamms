import 'dart:async';
import 'dart:html' as html;
import 'package:adminmrz/auth/service.dart';
import 'package:adminmrz/adminchat/services/admin_socket_service.dart';
import 'package:adminmrz/core/permissions.dart';
import 'package:adminmrz/core/theme_provider.dart';
import 'package:adminmrz/notifications/notification_center.dart';
import 'package:adminmrz/users/userdetails/detailscreen.dart';
import 'package:adminmrz/users/userdetails/userdetailprovider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../adminchat/chatprovider.dart';
import '../adminchat/loading.dart';
import '../adminchat/services/web_notification_service.dart';
import '../activity/activity_feed_screen.dart';
import '../activity/message_monitor_screen.dart';
import '../dashboard/dashboardhome.dart';
import '../document/screens/docscreen.dart';
import '../package/packageScreen.dart';
import '../payment/paymentscreen.dart';
import '../requests/request_provider.dart';
import '../requests/request_screen.dart';
import '../settings/call_settings_screen.dart';
import '../users/userscreen.dart';

// ─── Breakpoints ─────────────────────────────────────────────────────────────
const _kMobileBreakpoint = 768.0;

// ─── Design tokens ────────────────────────────────────────────────────────────
const _kSidebarBg     = Color(0xFF0F172A);
const _kSidebarBorder = Color(0xFF1E293B);
const _kAccent        = Color(0xFF6366F1);
const _kAccentLight   = Color(0xFF818CF8);
const _kTextPrimary   = Color(0xFFE2E8F0);
const _kTextSecondary = Color(0xFF94A3B8);
const _kTextMuted     = Color(0xFF64748B);
const _kContentBg     = Color(0xFFF1F5F9);
const _kTopBarBg      = Colors.white;
const _kTopBarBorder  = Color(0xFFE2E8F0);

// ─── Nav item model ───────────────────────────────────────────────────────────
class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem({required this.icon, required this.label});
}

// ─── Page ────────────────────────────────────────────────────────────────────
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  int _selectedIndex = 0;
  bool _isSidebarExpanded = true;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  late final List<Widget> _pages;

  // ── Global chat notification listener ────────────────────────────────────
  static const int _adminSenderId = 1;
  final AdminSocketService _socketService = AdminSocketService();
  StreamSubscription<Map<String, dynamic>>? _globalMessageSub;
  // Tracks known user names fetched lazily for notification display.
  final Map<String, String> _globalUserNames = {};
  // JS event listener reference kept so we can remove it on dispose.
  late final void Function(html.Event) _onChatNotifEvent;

  @override
  void initState() {
    super.initState();
    _pages = [
      DashboardHome(onNavigate: _onItemTapped),
      UsersPage(onOpenChat: _openChatForUser),
      const DocumentsPage(),
      const PackagesPage(),
      const PaymentsPage(),
      Loading(),
      ChangeNotifierProvider(
        create: (_) => RequestProvider(),
        child: const RequestsPage(),
      ),
      const CallSettingsScreen(),
      const ActivityFeedScreen(),
      const MessageMonitorScreen(),
    ];
    _startGlobalConversationListener();
    _onChatNotifEvent = _handleChatNotifJsEvent;
    html.window.addEventListener('chatNotification', _onChatNotifEvent);

    // Check if there's a pending profile view from a new tab
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPendingProfileView();
    });
  }

  @override
  void dispose() {
    _globalMessageSub?.cancel();
    html.window.removeEventListener('chatNotification', _onChatNotifEvent);
    super.dispose();
  }

  /// Handles the custom browser event dispatched when the admin clicks a
  /// chat browser notification.  Navigates to the Chat tab and opens the
  /// conversation with the user.
  void _handleChatNotifJsEvent(html.Event event) {
    if (!mounted) return;
    final detail = (event as html.CustomEvent).detail;
    final userIdStr = detail != null ? detail['userId']?.toString() : null;
    if (userIdStr == null || userIdStr.isEmpty) return;
    final userId = int.tryParse(userIdStr);
    if (userId == null) return;
    _openChatForUser(userId);
  }

  void _startGlobalConversationListener() {
    _socketService.connect();
    _globalMessageSub?.cancel();
    _globalMessageSub = _socketService.onNewMessage.listen((data) {
      if (!mounted) return;
      final senderId = data['senderId']?.toString() ?? '';
      if (senderId.isEmpty || senderId == _adminSenderId.toString()) return;
      if (_selectedIndex == 5) return;
      _showGlobalNotification(
        userId: senderId,
        message: _messagePreviewFromSocket(data),
      );
    });
  }

  /// Shows a browser notification and, when the tab is in the background,
  /// also plays the notification sound.  Called by the global listener when
  /// the admin is on a page other than the Chat tab.
  Future<void> _showGlobalNotification({
    required String userId,
    required String message,
  }) async {
    // Resolve a display name; use the cache when available.
    String senderName = _globalUserNames[userId] ?? '';
    if (senderName.isEmpty) {
      final chatProvider = context.read<ChatProvider>();
      final user = chatProvider.getUserById(int.tryParse(userId) ?? -1);
      senderName = user?['namee']?.toString() ?? '';
      if (senderName.isEmpty && chatProvider.chatList.isEmpty) {
        await chatProvider.fetchChatList();
        senderName =
            chatProvider.getUserById(int.tryParse(userId) ?? -1)?['namee']
                ?.toString() ??
            '';
      }
      if (senderName.isEmpty) senderName = 'Someone';
      // Limit the cache size to avoid unbounded growth in long-running sessions.
      if (_globalUserNames.length >= 200) _globalUserNames.clear();
      _globalUserNames[userId] = senderName;
    }

    final String displayMessage = message.isEmpty ? '📷 Photo' : message;

    // Play sound only when the browser tab is in the background.
    if (WebNotificationService.isAppInBackground()) {
      WebNotificationService.playMessageSound();
    }

    // Only show the browser notification when the admin tab is backgrounded.
    WebNotificationService.showMessageNotification(
      senderName: senderName,
      message: displayMessage,
      userId: userId,
    );
  }

  String _messagePreviewFromSocket(Map<String, dynamic> data) {
    final type = data['messageType']?.toString() ?? 'text';
    switch (type) {
      case 'image':
        return '📷 Photo';
      case 'profile_card':
        return '👤 Match Profile';
      case 'call':
        return '📞 Call';
      default:
        final text = data['message']?.toString() ?? '';
        return text.isEmpty ? '📷 Photo' : text;
    }
  }

  /// Navigate to the Chat tab and pre-select [userId] so the conversation
  /// opens immediately — mirroring how the chat sidebar selects a user.
  void _openChatForUser(int userId) {
    // Update the ChatProvider to select this user (same as chat sidebar does)
    final chatProvider = context.read<ChatProvider>();
    chatProvider.updateidd(userId);
    // Switch to Chat tab (index 5)
    setState(() => _selectedIndex = 5);
  }

  void _checkPendingProfileView() {
    // Check if this tab was opened to view a specific user profile
    final pendingUserId = html.window.sessionStorage['pendingProfileView'];
    if (pendingUserId != null && pendingUserId.isNotEmpty) {
      html.window.sessionStorage.remove('pendingProfileView');
      final userId = int.tryParse(pendingUserId);
      if (userId != null && mounted) {
        // Navigate to the user profile
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ChangeNotifierProvider(
              create: (_) => UserDetailsProvider(),
              child: UserDetailsScreen(
                userId: userId,
                myId: 1,
              ),
            ),
          ),
        );
      }
    }
  }

  static const List<_NavItem> _navItems = [
    _NavItem(icon: Icons.grid_view_rounded,   label: 'Dashboard'),
    _NavItem(icon: Icons.people_alt_rounded,  label: 'Members'),
    _NavItem(icon: Icons.description_rounded, label: 'Documents'),
    _NavItem(icon: Icons.inventory_2_rounded, label: 'Packages'),
    _NavItem(icon: Icons.payments_rounded,    label: 'Payments'),
    _NavItem(icon: Icons.chat_bubble_rounded, label: 'Chat'),
    _NavItem(icon: Icons.handshake_rounded,   label: 'Requests'),
    _NavItem(icon: Icons.tune_rounded,        label: 'Call Settings'),
    _NavItem(icon: Icons.timeline_rounded,    label: 'Activities'),
    _NavItem(icon: Icons.monitor_heart_rounded, label: 'Messages'),
  ];

  void _onItemTapped(int index) => setState(() => _selectedIndex = index);
  void _toggleSidebar()        => setState(() => _isSidebarExpanded = !_isSidebarExpanded);

  // ─── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final adminData    = authProvider.adminData;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < _kMobileBreakpoint;
        if (isMobile) {
          return _buildMobileLayout(adminData, authProvider);
        }
        return Scaffold(
          body: Row(
            children: [
              _buildSidebar(adminData, authProvider),
              Expanded(child: _buildMainContent()),
            ],
          ),
        );
      },
    );
  }

  // ─── Mobile layout ──────────────────────────────────────────────────────────
  Widget _buildMobileLayout(
    Map<String, dynamic>? adminData,
    AuthProvider authProvider,
  ) {
    final isChatPage = _selectedIndex == 5;
    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildDrawer(adminData, authProvider),
      body: Column(
        children: [
          _buildMobileTopBar(),
          Expanded(
            child: isChatPage
                ? _pages[_selectedIndex]
                : Container(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    padding: const EdgeInsets.all(16),
                    child: _pages[_selectedIndex],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileTopBar() {
    final title    = _navItems[_selectedIndex].label;
    final cs       = Theme.of(context).colorScheme;
    final isDark   = Theme.of(context).brightness == Brightness.dark;
    final topBarBg = cs.surface;
    final topBarBorder = cs.outlineVariant;
    final iconBg   = isDark ? const Color(0xFF263248) : const Color(0xFFF8FAFC);
    final mutedColor = cs.onSurface.withOpacity(0.45);

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: topBarBg,
        border: Border(bottom: BorderSide(color: topBarBorder)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            height: 36,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _scaffoldKey.currentState?.openDrawer(),
                borderRadius: BorderRadius.circular(8),
                child: Icon(Icons.menu_rounded, size: 20, color: mutedColor),
              ),
            ),
          ),
          const SizedBox(width: 10),
          _logoMark(),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            width: 34,
            height: 34,
            margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: topBarBorder),
            ),
            child: IconButton(
              onPressed: () => context.read<ThemeProvider>().toggleTheme(),
              icon: Icon(
                isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                size: 16,
                color: mutedColor,
              ),
              padding: EdgeInsets.zero,
              tooltip: isDark ? 'Light Mode' : 'Dark Mode',
            ),
          ),
          NotificationCenter(
            onViewAll: () {
              _scaffoldKey.currentState?.closeDrawer();
              _onItemTapped(8);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDrawer(
    Map<String, dynamic>? adminData,
    AuthProvider authProvider,
  ) {
    final name     = adminData?['name']?.toString() ?? 'Admin';
    final role     = adminData?['role']?.toString() ?? 'admin';
    final initials = name.isNotEmpty ? name[0].toUpperCase() : 'A';

    return Drawer(
      width: 260,
      backgroundColor: _kSidebarBg,
      child: Column(
        children: [
          Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: _kSidebarBorder)),
            ),
            child: Row(
              children: [
                _logoMark(),
                const SizedBox(width: 10),
                Expanded(
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Marriage Station',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _kTextPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 1),
                      Text(
                        'Admin Panel',
                        style: TextStyle(fontSize: 10, color: _kTextMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Builder(
              builder: (context) {
                final permissions = context.read<AuthProvider>().permissions;
                final Map<int, bool> visible = {
                  0: true,
                  1: permissions.canManageUsers,
                  2: permissions.canVerifyDocuments,
                  3: permissions.canManagePackages,
                  4: permissions.canManagePayments,
                  5: permissions.canAccessChats,
                  6: permissions.canManageRequests,
                  7: permissions.canManageSettings,
                  8: permissions.canViewActivities,
                  9: permissions.canMonitorMessages,
                };
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _navItems.length,
                  itemBuilder: (_, i) =>
                      (visible[i] ?? true) ? _buildDrawerNavTile(i) : const SizedBox.shrink(),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: _kSidebarBorder)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: _kAccent.withOpacity(0.2),
                  child: Text(
                    initials,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _kAccentLight,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _kTextPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        role,
                        style: const TextStyle(fontSize: 10, color: _kTextMuted),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 28,
                  height: 28,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () async => await authProvider.logout(),
                      borderRadius: BorderRadius.circular(6),
                      child: const Icon(
                        Icons.logout_rounded,
                        size: 16,
                        color: _kTextMuted,
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

  Widget _buildDrawerNavTile(int index) {
    final isActive = _selectedIndex == index;
    final item     = _navItems[index];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            _onItemTapped(index);
            _scaffoldKey.currentState?.closeDrawer();
          },
          borderRadius: BorderRadius.circular(8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: isActive ? _kAccent.withOpacity(0.14) : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border(
                left: BorderSide(
                  color: isActive ? _kAccent : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
            child: Row(
              children: [
                const SizedBox(width: 2),
                Icon(
                  item.icon,
                  size: 18,
                  color: isActive ? _kAccentLight : _kTextSecondary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                      color: isActive ? _kTextPrimary : _kTextSecondary,
                    ),
                  ),
                ),
                if (isActive)
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: _kAccentLight,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Sidebar ────────────────────────────────────────────────────────────────
  Widget _buildSidebar(
    Map<String, dynamic>? adminData,
    AuthProvider authProvider,
  ) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      width: _isSidebarExpanded ? 240 : 68,
      decoration: const BoxDecoration(color: _kSidebarBg),
      child: Column(
        children: [
          _buildSidebarHeader(),
          Expanded(child: _buildNavList()),
          _buildSidebarFooter(adminData, authProvider),
        ],
      ),
    );
  }

  Widget _buildSidebarHeader() {
    return Container(
      height: 64,
      padding: EdgeInsets.symmetric(horizontal: _isSidebarExpanded ? 14 : 0),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _kSidebarBorder)),
      ),
      child: _isSidebarExpanded
          ? Row(
              children: [
                _logoMark(),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Marriage Station',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _kTextPrimary,
                          letterSpacing: -0.2,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 1),
                      Text(
                        'Admin Panel',
                        style: TextStyle(fontSize: 10, color: _kTextMuted),
                      ),
                    ],
                  ),
                ),
                _sidebarToggleButton(),
              ],
            )
          : Center(
              child: GestureDetector(
                onTap: _toggleSidebar,
                child: _logoMark(),
              ),
            ),
    );
  }

  Widget _logoMark() {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(9),
      ),
      child: const Icon(Icons.favorite_rounded, color: Colors.white, size: 18),
    );
  }

  Widget _sidebarToggleButton() {
    return SizedBox(
      width: 28,
      height: 28,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _toggleSidebar,
          borderRadius: BorderRadius.circular(6),
          child: const Icon(
            Icons.chevron_left_rounded,
            size: 18,
            color: _kTextMuted,
          ),
        ),
      ),
    );
  }

  Widget _buildNavList() {
    final permissions = context.read<AuthProvider>().permissions;
    // Map nav-item index → permission check (null means always visible).
    final Map<int, bool> visible = {
      0: true,                                  // Dashboard
      1: permissions.canManageUsers,            // Members
      2: permissions.canVerifyDocuments,        // Documents
      3: permissions.canManagePackages,         // Packages
      4: permissions.canManagePayments,         // Payments
      5: permissions.canAccessChats,            // Chat
      6: permissions.canManageRequests,         // Requests
      7: permissions.canManageSettings,         // Call Settings
      8: permissions.canViewActivities,         // Activities
      9: permissions.canMonitorMessages,        // Messages
    };
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _navItems.length,
      itemBuilder: (_, i) =>
          (visible[i] ?? true) ? _buildNavTile(i) : const SizedBox.shrink(),
    );
  }

  Widget _buildNavTile(int index) {
    final isActive = _selectedIndex == index;
    final item     = _navItems[index];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _onItemTapped(index),
          borderRadius: BorderRadius.circular(9),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: EdgeInsets.symmetric(
              horizontal: _isSidebarExpanded ? 10 : 0,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              gradient: isActive
                  ? LinearGradient(
                      colors: [_kAccent.withOpacity(0.22), Colors.transparent],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    )
                  : null,
              borderRadius: BorderRadius.circular(9),
              border: Border(
                left: BorderSide(
                  color: isActive ? _kAccent : Colors.transparent,
                  width: 4,
                ),
              ),
            ),
            child: _isSidebarExpanded
                ? Row(
                    children: [
                      const SizedBox(width: 2),
                      Icon(
                        item.icon,
                        size: 18,
                        color: isActive ? _kAccentLight : _kTextSecondary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          item.label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isActive
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: isActive ? _kTextPrimary : _kTextSecondary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isActive)
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: _kAccentLight,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  )
                : Center(
                    child: Tooltip(
                      message: item.label,
                      child: Icon(
                        item.icon,
                        size: 20,
                        color: isActive ? _kAccentLight : _kTextSecondary,
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildSidebarFooter(
    Map<String, dynamic>? adminData,
    AuthProvider authProvider,
  ) {
    final name   = adminData?['name']?.toString() ?? 'Admin';
    final role   = adminData?['role']?.toString() ?? 'admin';
    final initials = name.isNotEmpty ? name[0].toUpperCase() : 'A';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _kSidebarBorder)),
      ),
      child: _isSidebarExpanded
          ? Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: _kAccent.withOpacity(0.2),
                  child: Text(
                    initials,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _kAccentLight,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _kTextPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        role,
                        style: const TextStyle(
                          fontSize: 10,
                          color: _kTextMuted,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 28,
                  height: 28,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () async => await authProvider.logout(),
                      borderRadius: BorderRadius.circular(6),
                      child: const Icon(
                        Icons.logout_rounded,
                        size: 16,
                        color: _kTextMuted,
                      ),
                    ),
                  ),
                ),
              ],
            )
          : Center(
              child: Tooltip(
                message: 'Logout',
                child: GestureDetector(
                  onTap: () async => await authProvider.logout(),
                  child: const Icon(
                    Icons.logout_rounded,
                    size: 18,
                    color: _kTextMuted,
                  ),
                ),
              ),
            ),
    );
  }

  // ─── Main content area ──────────────────────────────────────────────────────
  Widget _buildMainContent() {
    final bool isChatPage = _selectedIndex == 5;
    // Members page (index 1) has its own "Member Directory" header, so the
    // top bar and outer padding are redundant and waste vertical space.
    final bool isMembersPage = _selectedIndex == 1;
    return Column(
      children: [
        if (!isChatPage && !isMembersPage) _buildTopBar(),
        Expanded(
          child: isChatPage
              ? _pages[_selectedIndex]
              : Container(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  padding: isMembersPage
                      ? EdgeInsets.zero
                      : const EdgeInsets.all(24),
                  child: _pages[_selectedIndex],
                ),
        ),
      ],
    );
  }

  Widget _buildTopBar() {
    final title = _navItems[_selectedIndex].label;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final topBarBg = cs.surface;
    final topBarBorder = cs.outlineVariant;
    final iconBg = isDark ? const Color(0xFF1E2D45) : const Color(0xFFF1F5F9);
    final mutedColor = cs.onSurface.withOpacity(0.40);

    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: topBarBg,
        border: Border(bottom: BorderSide(color: topBarBorder, width: 1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.20 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Breadcrumb
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: topBarBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.home_outlined, size: 13, color: mutedColor),
                const SizedBox(width: 5),
                Text('/', style: TextStyle(fontSize: 11, color: mutedColor)),
                const SizedBox(width: 5),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface.withOpacity(0.80),
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          // Notification bell
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: NotificationCenter(
              onViewAll: () => _onItemTapped(8),
            ),
          ),
          // Dark / Light mode toggle
          Container(
            width: 38,
            height: 38,
            margin: const EdgeInsets.only(right: 4),
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: topBarBorder),
            ),
            child: IconButton(
              onPressed: () => context.read<ThemeProvider>().toggleTheme(),
              icon: Icon(
                isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                size: 17,
                color: mutedColor,
              ),
              padding: EdgeInsets.zero,
              tooltip: isDark ? 'Switch to Light Mode' : 'Switch to Dark Mode',
            ),
          ),
        ],
      ),
    );
  }
}
