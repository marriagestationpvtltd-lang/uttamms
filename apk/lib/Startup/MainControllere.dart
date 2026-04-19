// screens/main_controller_screen.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../ReUsable/Navbar.dart'; // AppNavbar with onItemSelected callback
import '../Home/Screen/HomeScreenPage.dart';
import '../liked/liked.dart';
import '../Chat/ChatlistScreen.dart';
import '../profile/myprofile.dart';
import '../service/socket_service.dart';
import '../utils/responsive_layout.dart';

class MainControllerScreen extends StatefulWidget {
  final int initialIndex;
  const MainControllerScreen({Key? key, this.initialIndex = 0})
      : super(key: key);

  @override
  State<MainControllerScreen> createState() => _MainControllerScreenState();
}

class _MainControllerScreenState extends State<MainControllerScreen> {
  static const int _chatTabIndex = 2;

  late int _selectedIndex;
  String? _senderId;
  String? _senderName;
  String? _currentUserImage;
  int _chatUnreadCount = 0;
  final Set<String> _unreadChatRoomIds = {};
  StreamSubscription<List<dynamic>>? _unreadSubscription;
  StreamSubscription<Map<String, dynamic>>? _newMsgSubscription;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
    _loadUserFromPrefs();
  }

  @override
  void dispose() {
    _unreadSubscription?.cancel();
    _newMsgSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadUserFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final s = prefs.getString('user_data');
      if (s != null && s.isNotEmpty) {
        final data = jsonDecode(s);
        setState(() {
          _senderId = data['id']?.toString();
          _senderName = data['firstName']?.toString() ?? 'User';
          _currentUserImage = data['profile_picture']?.toString();
        });
        if (_senderId != null) {
          _listenUnreadCounts(_senderId!);
        }
      }
    } catch (e) {
      debugPrint('MainControllerScreen: loadUser error: $e');
    }
  }

  void _listenUnreadCounts(String userId) {
    _unreadSubscription?.cancel();
    _newMsgSubscription?.cancel();

    // Listen to chat_rooms_update from Socket.IO to count rooms with unread messages
    _unreadSubscription = SocketService().onChatRoomsUpdate.listen((rooms) {
      int unread = 0;
      for (final room in rooms) {
        if (room is Map) {
          final unreadCount = room['unreadCount'];
          if (unreadCount is int && unreadCount > 0)
            unread++;
          else if (unreadCount is num && unreadCount.toInt() > 0) unread++;
        }
      }
      if (_chatUnreadCount != unread && mounted) {
        setState(() => _chatUnreadCount = unread);
      }
    });

    // Also track unread rooms from new messages when user is not on Chat tab
    _newMsgSubscription = SocketService().onNewMessage.listen((msg) {
      final senderId = msg['senderId']?.toString() ?? '';
      final chatRoomId = msg['chatRoomId']?.toString() ?? '';
      if (senderId != userId &&
          chatRoomId.isNotEmpty &&
          _selectedIndex != _chatTabIndex &&
          mounted) {
        if (_unreadChatRoomIds.add(chatRoomId)) {
          setState(() => _chatUnreadCount = _unreadChatRoomIds.length);
        }
      }
    });
  }

  // Build the pages. Index 0=Home, 1=Liked, 2=Chat, 3=Account
  List<Widget> _buildScreens() {
    return [
      MatrimonyHomeScreen(), // index 0
      FavoritePeoplePage(), // index 1
      _senderId != null
          ? const ChatListScreen()
          : const Center(child: Text('Loading chat...')), // index 2
      MatrimonyProfilePage(), // index 3
    ];
  }

  @override
  Widget build(BuildContext context) {
    final screens = _buildScreens();
    final isWide = ResponsiveLayout.isWideLayout(context);

    if (isWide && kIsWeb) {
      // ── Web: side-navigation rail + content ──────────────────────────────
      return PopScope(
        canPop: false,
        child: Scaffold(
          body: Row(
            children: [
              _WebSideNav(
                selectedIndex: _selectedIndex,
                chatUnreadCount: _chatUnreadCount,
                currentUserImage: _currentUserImage,
                onItemSelected: (index) {
                  setState(() {
                    _selectedIndex = index;
                    if (index == _chatTabIndex) {
                      _chatUnreadCount = 0;
                      _unreadChatRoomIds.clear();
                    }
                  });
                },
              ),
              const VerticalDivider(width: 1, thickness: 1),
              Expanded(
                child: IndexedStack(
                  index: _selectedIndex,
                  children: screens,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // ── Mobile: bottom navigation ─────────────────────────────────────────
    return PopScope(
      canPop: _selectedIndex == 0,
      onPopInvoked: (bool didPop) {
        if (!didPop && _selectedIndex != 0) {
          setState(() {
            _selectedIndex = 0;
          });
        }
      },
      child: Scaffold(
        body: IndexedStack(
          index: _selectedIndex,
          children: screens,
        ),
        bottomNavigationBar: AppNavbar(
          selectedIndex: _selectedIndex,
          currentUserImage: _currentUserImage,
          chatUnreadCount: _chatUnreadCount,
          onItemSelected: (index) {
            setState(() {
              _selectedIndex = index;
              // Clear chat unread badge when user switches to Chat tab
              if (index == _chatTabIndex) {
                _chatUnreadCount = 0;
                _unreadChatRoomIds.clear();
              }
            });
          },
        ),
      ),
    );
  }
}

/// A side navigation rail shown on web/wide-screen layouts.
class _WebSideNav extends StatelessWidget {
  const _WebSideNav({
    required this.selectedIndex,
    required this.chatUnreadCount,
    required this.currentUserImage,
    required this.onItemSelected,
  });

  final int selectedIndex;
  final int chatUnreadCount;
  final String? currentUserImage;
  final ValueChanged<int> onItemSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.primary;

    final destinations = [
      const NavigationRailDestination(
        icon: Icon(Icons.home_outlined),
        selectedIcon: Icon(Icons.home),
        label: Text('Home'),
      ),
      const NavigationRailDestination(
        icon: Icon(Icons.favorite_border),
        selectedIcon: Icon(Icons.favorite),
        label: Text('Liked'),
      ),
      NavigationRailDestination(
        icon: Badge(
          isLabelVisible: chatUnreadCount > 0,
          label: Text(chatUnreadCount > 9 ? '9+' : '$chatUnreadCount'),
          child: const Icon(Icons.chat_bubble_outline),
        ),
        selectedIcon: const Icon(Icons.chat_bubble),
        label: const Text('Chat'),
      ),
      NavigationRailDestination(
        icon: currentUserImage != null
            ? CircleAvatar(
                radius: 13,
                backgroundImage: NetworkImage(currentUserImage!),
              )
            : const Icon(Icons.person_outline),
        selectedIcon: const Icon(Icons.person),
        label: const Text('Profile'),
      ),
    ];

    return NavigationRail(
      selectedIndex: selectedIndex,
      onDestinationSelected: onItemSelected,
      extended: true,
      minExtendedWidth: 200,
      leading: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          'Marriage\nStation',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      destinations: destinations,
    );
  }
}
