import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../Models/masterdata.dart';
import '../service/verification_service.dart';
import '../Package/PackageScreen.dart';
import '../core/user_state.dart';
import '../online/onlineservice.dart';
import '../utils/time_utils.dart';
import '../utils/image_utils.dart';
import '../utils/privacy_utils.dart';
import '../utils/responsive_layout.dart';
import '../purposal/Purposalmodel.dart';
import '../purposal/purposalservice.dart';
import '../purposal/purposalScreen.dart';
import '../pushnotification/pushservice.dart';
import '../Notification/notificationscreen.dart';
import '../Notification/notification_inbox_service.dart';
import '../Calling/call_history_screen.dart';
import 'ChatdetailsScreen.dart';
import 'adminchat.dart';
import '../service/socket_service.dart';
import 'package:ms2026/config/app_endpoints.dart';
import '../otherenew/othernew.dart';
import '../ReUsable/loading_widgets.dart';
import '../settings/sound_vibration_settings_screen.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  // Static broadcast stream used to trigger a refresh from outside the widget
  // (e.g. when the chat tab is re-activated via IndexedStack).
  static final StreamController<void> _tabActivated =
      StreamController<void>.broadcast();

  /// Call this whenever the chat tab becomes visible so the list re-fetches
  /// fresh participant images from the socket server.
  static void requestRefresh() => _tabActivated.add(null);

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

/// Distinguishes between the two message-display contexts so that masking
/// rules can be applied correctly:
///   [listPreview] – conversation list thumbnail; non-premium users see first 4 words.
///   [chat]        – full chat screen; messages are ALWAYS shown unmasked.
enum _MessageViewContext { listPreview, chat }

class _ChatListScreenState extends State<ChatListScreen>
    with WidgetsBindingObserver {
  String userimage = '';
  int _selfImageVersion = DateTime.now().millisecondsSinceEpoch;
  var pageno;
  String userId = '';
  String name = '';
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool isLoading = true;

  List<ProposalModel> _pendingChatRequests = [];
  List<ProposalModel> _sentChatRequests = [];
  bool _requestsLoading = true;
  bool _sentRequestsLoading = true;
  final PageController _receivedReqPageCtrl = PageController();
  final PageController _sentReqPageCtrl = PageController();
  int _receivedReqPage = 0;
  int _sentReqPage = 0;
  int _receivedProposalCount = 0;
  int _unreadNotificationCount = 0;
  int _totalUnreadCount = 0;
  int _totalUnreadConversations = 0;

  int _displayCount = 10;
  bool _isLoadingMore = false;
  int _cachedTotalRooms = 0;
  final ScrollController _scrollController = ScrollController();

  // Track if user is actively scrolling to debounce message updates
  bool _isUserScrolling = false;
  Timer? _scrollIdleTimer;

  // Buffer for pending room updates during scroll
  List<Map<String, dynamic>>? _pendingRoomUpdate;

  StreamSubscription? _adminChatSubscription;
  String _adminLastMessage = '';
  DateTime? _adminLastMessageTime;
  int _adminUnreadCount = 0;
  bool _adminLoading = true;
  static const String _adminUserId = '1';
  static const String _adminDisplayName = 'Admin Support';

  // Local cache keys (user-specific suffix appended at runtime)
  static const String _chatRoomsCacheKey = 'chat_rooms_cache';
  static const String _chatRoomsCacheTsKey = 'chat_rooms_cache_ts';
  static const String _pendingRequestsCacheKey = 'pending_chat_requests_cache';
  static const String _sentRequestsCacheKey = 'sent_chat_requests_cache';

  // Chat rooms list driven by Socket.IO
  List<Map<String, dynamic>> _socketChatRooms = [];
  bool _chatRoomsInitialized = false;
  StreamSubscription? _chatRoomsUpdateSubscription;
  StreamSubscription? _newMessageSubscription;
  StreamSubscription? _userBlockedSubscription;

  // Tracks when the chat rooms were last fetched to avoid redundant refreshes.
  DateTime? _lastChatRoomsFetch;
  DateTime? _lastSuccessfulChatRoomsFetch;
  bool _chatRoomsRefreshInFlight = false;
  bool _chatRoomsRefreshQueued = false;
  static const Duration _minRefreshGap = Duration(milliseconds: 900);
  static const Duration _cacheFreshWindow = Duration(seconds: 20);

  // Subscription for tab-activation refresh requests
  StreamSubscription? _tabActivatedSub;

  // Subscription for proposal accepted events (e.g. photo request accepted)
  // so the chat list updates participant photo visibility immediately.
  StreamSubscription? _proposalAcceptedSub;

  // Online status for chat participants
  final Map<String, bool> _onlineStatuses = {};
  final Map<String, DateTime?> _lastSeenTimes = {};
  StreamSubscription? _onlineStatusSubscription;

  // Admin online status
  bool _adminOnline = false;
  StreamSubscription? _adminStatusSubscription;

  // Web two-panel: tracks the currently selected chat room on wide screens
  Map<String, dynamic>? _webSelectedChatData;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadUserData();
    OnlineStatusService().start();
    _scrollController.addListener(_onScroll);
    _searchController.addListener(_onSearchChanged);
    // Refresh chat rooms when the chat tab is re-activated (IndexedStack does
    // not call initState on tab switch, so we use a static broadcast stream).
    _tabActivatedSub = ChatListScreen._tabActivated.stream.listen((_) {
      if (!mounted || userId.isEmpty) return;
      final last = _lastChatRoomsFetch;
      // Throttle to at most once every 5 seconds to avoid rapid re-fetches
      // when the user quickly switches tabs back and forth.
      if (last == null ||
          DateTime.now().difference(last) >= const Duration(seconds: 5)) {
        _refreshChatRooms();
      }
    });
    // When any proposal is accepted (photo request, chat request), refresh
    // the chat list immediately so the updated photo-request status is shown.
    _proposalAcceptedSub = SocketService().onProposalAccepted.listen((_) {
      if (!mounted || userId.isEmpty) return;
      _refreshChatRooms();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabActivatedSub?.cancel();
    _proposalAcceptedSub?.cancel();
    _adminChatSubscription?.cancel();
    _onlineStatusSubscription?.cancel();
    _chatRoomsUpdateSubscription?.cancel();
    _newMessageSubscription?.cancel();
    _userBlockedSubscription?.cancel();
    _adminStatusSubscription?.cancel();
    _scrollIdleTimer?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    _receivedReqPageCtrl.dispose();
    _sentReqPageCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      OnlineStatusService().setOffline();
    } else if (state == AppLifecycleState.resumed) {
      _syncCurrentUserImageFromLocalCache();
      OnlineStatusService().start();
      _startAdminStatusListener();
      _startOnlineStatusListeners();
      // Re-fetch chat rooms on every resume so that profile-photo changes made
      // by any participant are reflected immediately without requiring a full
      // app restart or waiting for the throttle window to expire.
      if (userId.isNotEmpty) {
        _refreshChatRooms();
      }
    }
  }

  String _resolvedCurrentUserImage() {
    final base = resolveApiImageUrl(userimage).trim();
    if (base.isEmpty) return base;
    final sep = base.contains('?') ? '&' : '?';
    return '$base${sep}v=$_selfImageVersion';
  }

  Future<void> _syncCurrentUserImageFromLocalCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataString = prefs.getString('user_data');
      if (userDataString == null || userDataString.isEmpty) return;

      final userData = jsonDecode(userDataString);
      final latest = (userData['profile_picture'] ??
              userData['profilePicture'] ??
              userData['image'] ??
              '')
          .toString()
          .trim();

      if (latest.isEmpty) return;

      final normalizedLatest = resolveApiImageUrl(latest);
      final normalizedCurrent = resolveApiImageUrl(userimage);
      if (normalizedLatest == normalizedCurrent) return;

      if (!mounted) return;
      setState(() {
        userimage = latest;
        _selfImageVersion = DateTime.now().millisecondsSinceEpoch;
      });
    } catch (_) {}
  }

  void _onScroll() {
    // Mark that user is actively scrolling
    if (!_isUserScrolling) {
      _isUserScrolling = true;
    }

    // Reset idle timer to detect when scrolling stops
    _scrollIdleTimer?.cancel();
    _scrollIdleTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        _isUserScrolling = false;
        // Apply any pending room updates after scroll completes
        if (_pendingRoomUpdate != null) {
          _applyRoomUpdate(_pendingRoomUpdate!);
          _pendingRoomUpdate = null;
        }
      }
    });

    if (_searchQuery.isNotEmpty) return;
    if (_scrollController.hasClients &&
        _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoadingMore &&
        _displayCount < _cachedTotalRooms) {
      setState(() {
        _isLoadingMore = true;
        _displayCount += 10;
        _isLoadingMore = false;
      });
    }
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim().toLowerCase();
    if (query == _searchQuery) return;
    setState(() => _searchQuery = query);
  }

  // ── Local cache helpers ──────────────────────────────────────────────────

  /// Loads chat rooms from SharedPreferences cache and updates state.
  /// Returns true if cached data was found and applied.
  Future<bool> _loadChatRoomsFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('${_chatRoomsCacheKey}_$userId');
      if (cached == null || !mounted) return false;
      final List<dynamic> decoded = jsonDecode(cached);
      final parsedRooms = _safeRoomList(decoded);
      int totalUnread = 0;
      int unreadConvs = 0;
      for (final room in parsedRooms) {
        final int unread = _safeUnreadCount(room['unreadCount']);
        totalUnread += unread;
        if (unread > 0) unreadConvs++;
      }
      final nonAdminRooms = parsedRooms.where((r) => !_isAdminRoom(r)).toList();
      setState(() {
        _socketChatRooms = parsedRooms;
        _cachedTotalRooms = nonAdminRooms.length;
        _chatRoomsInitialized = true;
        _totalUnreadCount = totalUnread;
        _totalUnreadConversations = unreadConvs;
      });

      final cacheTs = prefs.getInt('${_chatRoomsCacheTsKey}_$userId');
      if (cacheTs != null && cacheTs > 0) {
        _lastSuccessfulChatRoomsFetch =
            DateTime.fromMillisecondsSinceEpoch(cacheTs);
      }
      return true;
    } catch (e) {
      print('Error loading chat rooms cache for user $userId: $e');
      return false;
    }
  }

  /// Persists the current chat room list to SharedPreferences.
  Future<void> _saveChatRoomsToCache(List<Map<String, dynamic>> rooms) async {
    if (userId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('${_chatRoomsCacheKey}_$userId', jsonEncode(rooms));
      await prefs.setInt('${_chatRoomsCacheTsKey}_$userId',
          DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      print('Error saving chat rooms cache for user $userId: $e');
    }
  }

  bool _isChatRoomsCacheFresh() {
    final last = _lastSuccessfulChatRoomsFetch;
    if (last == null) return false;
    return DateTime.now().difference(last) <= _cacheFreshWindow;
  }

  /// Loads pending/sent chat requests from SharedPreferences cache.
  /// Returns true if cached data was found and applied.
  Future<bool> _loadRequestsFromCache(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingCached = prefs.getString('${_pendingRequestsCacheKey}_$uid');
      final sentCached = prefs.getString('${_sentRequestsCacheKey}_$uid');
      if ((pendingCached == null && sentCached == null) || !mounted) {
        return false;
      }
      final List<ProposalModel> pending = pendingCached != null
          ? (jsonDecode(pendingCached) as List)
              .map((e) => ProposalModel.fromJson(e as Map<String, dynamic>))
              .toList()
          : [];
      final List<ProposalModel> sent = sentCached != null
          ? (jsonDecode(sentCached) as List)
              .map((e) => ProposalModel.fromJson(e as Map<String, dynamic>))
              .toList()
          : [];
      setState(() {
        _pendingChatRequests = pending;
        _sentChatRequests = sent;
        _requestsLoading = false;
        _sentRequestsLoading = false;
      });
      return true;
    } catch (e) {
      print('Error loading requests cache for user $uid: $e');
      return false;
    }
  }

  /// Persists pending/sent chat requests to SharedPreferences.
  Future<void> _saveRequestsToCache(
      String uid, List<ProposalModel> pending, List<ProposalModel> sent) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('${_pendingRequestsCacheKey}_$uid',
          jsonEncode(pending.map((p) => p.toJson()).toList()));
      await prefs.setString('${_sentRequestsCacheKey}_$uid',
          jsonEncode(sent.map((p) => p.toJson()).toList()));
    } catch (e) {
      print('Error saving requests cache for user $uid: $e');
    }
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
      pageno = user.pageno;

      final localProfileImage =
          (userData["profile_picture"] ?? userData["profilePicture"] ?? '')
              .toString()
              .trim();

      _initializeChatBootstrap(
        resolvedUserId: user.id?.toString() ?? userIdString,
        resolvedName: '${user.firstName} ${user.lastName}'.trim(),
        resolvedImage: localProfileImage.isNotEmpty
            ? localProfileImage
            : user.profilePicture,
      );

      // Keep UserState in sync with the data already fetched above –
      // avoids a separate masterdata.php call just for verification/usertype.
      if (mounted) {
        context.read<UserState>().updateFromMasterData(
            user.docStatus, user.isVerified, user.usertype);
      }

      print('=== USER DATA LOADED ===');
      print('userId: $userId');
      print('name: $name');
    } catch (e) {
      print('Error loading user data: $e');

      try {
        final prefs = await SharedPreferences.getInstance();
        final userDataString = prefs.getString('user_data');
        if (userDataString != null) {
          final userData = jsonDecode(userDataString);
          final fallbackUserId = (userData['id'] ?? '').toString().trim();
          final fallbackName =
              '${userData["firstName"] ?? userData["first_name"] ?? ''} ${userData["lastName"] ?? userData["last_name"] ?? ''}'
                  .trim();
          final fallbackImage =
              (userData["profilePicture"] ?? userData["profile_picture"] ?? '')
                  .toString();

          if (fallbackUserId.isNotEmpty) {
            _initializeChatBootstrap(
              resolvedUserId: fallbackUserId,
              resolvedName: fallbackName,
              resolvedImage: fallbackImage,
            );
            return;
          }
        }
      } catch (_) {}

      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  void _initializeChatBootstrap({
    required String resolvedUserId,
    required String resolvedName,
    required String resolvedImage,
  }) {
    if (!mounted) return;
    setState(() {
      userimage = resolvedImage;
      _selfImageVersion = DateTime.now().millisecondsSinceEpoch;
      userId = resolvedUserId;
      name = resolvedName;
      isLoading = false;
    });

    _loadPendingChatRequests(resolvedUserId);
    _loadUnreadNotificationCount();
    _startAdminChatListener(resolvedUserId);
    _initChatRoomsStream();
    _startAdminStatusListener();
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

  Future<void> _loadPendingChatRequests(String uid) async {
    try {
      // Load from cache first so the list appears instantly
      final cacheLoaded = await _loadRequestsFromCache(uid);
      // Only show loading spinner if no cached data is available
      if (!cacheLoaded && mounted) {
        setState(() {
          _requestsLoading = true;
          _sentRequestsLoading = true;
        });
      }
      final results = await Future.wait([
        ProposalService.fetchProposals(uid, 'received'),
        ProposalService.fetchProposals(uid, 'sent'),
      ]);
      final allReceived = results[0];
      final pending = allReceived
          .where((p) =>
              p.requestType?.toLowerCase() == 'chat' &&
              p.status?.toLowerCase() == 'pending')
          .toList();
      final receivedPendingCount =
          allReceived.where((p) => p.status?.toLowerCase() == 'pending').length;
      final sent = results[1]
          .where((p) =>
              p.requestType?.toLowerCase() == 'chat' &&
              p.status?.toLowerCase() == 'pending')
          .toList();
      if (mounted) {
        setState(() {
          _pendingChatRequests = pending;
          _sentChatRequests = sent;
          _receivedProposalCount = receivedPendingCount;
          _requestsLoading = false;
          _sentRequestsLoading = false;
        });
      }
      // Persist fresh data so the next launch shows it instantly
      await _saveRequestsToCache(uid, pending, sent);
    } catch (e) {
      print('Error loading chat requests: $e');
      if (mounted)
        setState(() {
          _requestsLoading = false;
          _sentRequestsLoading = false;
        });
    }
  }

  /// Start admin chat summary listener via Socket.IO chat_rooms_update.
  /// The admin chat room appears in the user's room list since both users
  /// are participants in the same chat_rooms MySQL table entry.
  void _startAdminChatListener(String uid) {
    _adminChatSubscription?.cancel();
    if (mounted) setState(() => _adminLoading = true);

    // Fetch once to show initial state
    _fetchChatRoomsWithRetry(uid).then((rooms) {
      if (!mounted) return;
      _updateAdminRoomInfo(uid, rooms);
    }).catchError((_) {
      if (mounted) setState(() => _adminLoading = false);
    });

    // Subscribe to real-time updates — already done via _startChatRoomsUpdateListener()
    // Re-use the same stream: filter for admin room in onChatRoomsUpdate.
    _adminChatSubscription = SocketService().onChatRoomsUpdate.listen((rooms) {
      if (!mounted) return;
      _updateAdminRoomInfo(uid, rooms);
    });
  }

  Future<List<Map<String, dynamic>>> _fetchChatRoomsWithRetry(
    String uid, {
    int attempts = 3,
  }) async {
    final socketService = SocketService();
    List<Map<String, dynamic>> parsedRooms = [];

    for (int i = 0; i < attempts; i++) {
      final rooms = await socketService.getChatRooms(uid);
      parsedRooms = _safeRoomList(rooms);
      if (parsedRooms.isNotEmpty) return parsedRooms;

      if (!socketService.isConnected) {
        await Future.delayed(const Duration(milliseconds: 800));
      } else {
        await Future.delayed(const Duration(milliseconds: 450));
      }
    }

    return parsedRooms;
  }

  void _updateAdminRoomInfo(String uid, List<dynamic> rooms) {
    // Admin chat room id = sorted join of uid and _adminUserId
    final ids = [uid, _adminUserId]..sort();
    final adminRoomId = ids.join('_');

    final adminRoomList = _safeRoomList(rooms)
        .where((r) => r['chatRoomId'] == adminRoomId)
        .toList();

    if (adminRoomList.isEmpty) {
      if (mounted)
        setState(() {
          _adminLoading = false;
        });
      return;
    }
    final adminRoom = adminRoomList.first;

    final String msgType = adminRoom['lastMessageType']?.toString() ?? 'text';
    final String preview = _formatConversationPreview(
      rawMessage: adminRoom['lastMessage']?.toString() ?? '',
      messageType: msgType,
      compactMediaLabels: true,
    );

    final dynamic lastMsgTime = adminRoom['lastMessageTime'];
    DateTime? latestTime;
    if (lastMsgTime is String) latestTime = DateTime.tryParse(lastMsgTime);

    final int unread = _safeUnreadCount(adminRoom['unreadCount']);

    if (mounted) {
      setState(() {
        _adminLastMessage = preview;
        _adminLastMessageTime = latestTime;
        _adminUnreadCount = unread;
        _adminLoading = false;
      });
    }
  }

  Future<void> _markAdminChatSeen() async {
    if (userId.isEmpty) return;
    // Mark via Socket.IO
    final ids = [userId, _adminUserId]..sort();
    final adminRoomId = ids.join('_');
    SocketService().markRead(adminRoomId, userId);
    if (mounted) {
      setState(() {
        _adminUnreadCount = 0;
      });
    }
  }

  /// Initialise chat rooms via Socket.IO and subscribe to real-time updates.
  void _initChatRoomsStream() {
    if (userId.isEmpty) return;
    final socketService = SocketService();
    if (!socketService.isConnected) {
      SharedPreferences.getInstance().then((prefs) {
        final token = prefs.getString('bearer_token');
        socketService.connect(userId, token: token);
      });
    }

    // Set up real-time listeners BEFORE the initial fetch so that any
    // chat_rooms_update / new_message events emitted by the server while
    // getChatRooms is in-flight are not silently dropped by the broadcast stream.
    _startChatRoomsUpdateListener();
    _startNewMessageListener();
    _startUserBlockedListener();
    _startOnlineStatusListeners();

    // Load from cache first so the list appears instantly without a spinner
    _loadChatRoomsFromCache().then((_) {
      if (_isChatRoomsCacheFresh()) {
        return;
      }

      _fetchChatRoomsWithRetry(userId).then((parsedRooms) {
        if (!mounted) return;

        // Guard: if the ack returned empty (either a genuine timeout/no-op
        // because _socket was null, or a server-side error) but
        // _startChatRoomsUpdateListener has already populated real data via a
        // chat_rooms_update push, do not overwrite that data and do not
        // persist an empty list to the cache.
        if (parsedRooms.isEmpty && _socketChatRooms.isNotEmpty) {
          if (!_chatRoomsInitialized) {
            setState(() => _chatRoomsInitialized = true);
          }
          return;
        }

        int totalUnread = 0;
        int unreadConvs = 0;
        for (final room in parsedRooms) {
          final int unread = _safeUnreadCount(room['unreadCount']);
          totalUnread += unread;
          if (unread > 0) unreadConvs++;
        }
        final nonAdminRooms =
            parsedRooms.where((r) => !_isAdminRoom(r)).toList();
        setState(() {
          _socketChatRooms = parsedRooms;
          _cachedTotalRooms = nonAdminRooms.length;
          _chatRoomsInitialized = true;
          _totalUnreadCount = totalUnread;
          _totalUnreadConversations = unreadConvs;
        });
        _lastSuccessfulChatRoomsFetch = DateTime.now();
        // Persist fresh data for next launch
        _saveChatRoomsToCache(parsedRooms);
        // Seed initial online status from room data before real-time events arrive
        _updateOnlineStatusesFromRooms(parsedRooms);
      });
    });
  }

  /// Listen for local user_blocked notifications so the conversation is
  /// removed from the list immediately after a successful block action,
  /// without waiting for the next chat_rooms_update push.
  void _startUserBlockedListener() {
    _userBlockedSubscription?.cancel();
    _userBlockedSubscription =
        SocketService().onUserBlocked.listen((blockedUserId) {
      if (!mounted) return;
      setState(() {
        _socketChatRooms.removeWhere((room) {
          final p1 = room['user1Id']?.toString() ?? '';
          final p2 = room['user2Id']?.toString() ?? '';
          return p1 == blockedUserId || p2 == blockedUserId;
        });
        final nonAdminRooms =
            _socketChatRooms.where((r) => !_isAdminRoom(r)).toList();
        _cachedTotalRooms = nonAdminRooms.length;
      });
      _saveChatRoomsToCache(_socketChatRooms);
      // Full refresh so server-side hidden state is respected
      _refreshChatRooms();
    });
  }

  /// Subscribe to real-time chat room list updates from Socket.IO.
  void _startChatRoomsUpdateListener() {
    _chatRoomsUpdateSubscription?.cancel();
    _chatRoomsUpdateSubscription =
        SocketService().onChatRoomsUpdate.listen((rooms) {
      if (!mounted) return;
      final parsedRooms = _safeRoomList(rooms);
      int totalUnread = 0;
      int unreadConvs = 0;
      for (final room in parsedRooms) {
        final int unread = _safeUnreadCount(room['unreadCount']);
        totalUnread += unread;
        if (unread > 0) unreadConvs++;
      }
      final nonAdminRooms = parsedRooms.where((r) => !_isAdminRoom(r)).toList();
      setState(() {
        _socketChatRooms = parsedRooms;
        _cachedTotalRooms = nonAdminRooms.length;
        // Mark initialised so the skeleton loader is removed as soon as the
        // server pushes real data via this event — even before getChatRooms ack.
        _chatRoomsInitialized = true;
        _totalUnreadCount = totalUnread;
        _totalUnreadConversations = unreadConvs;
      });
      // Keep cache up-to-date with real-time changes
      _saveChatRoomsToCache(parsedRooms);
      // Update online status from refreshed room data
      _updateOnlineStatusesFromRooms(parsedRooms);
    });
  }

  /// Subscribe to new_message events so the chat list moves the relevant
  /// conversation to the top instantly without waiting for chat_rooms_update.
  void _startNewMessageListener() {
    _newMessageSubscription?.cancel();
    _newMessageSubscription = SocketService().onNewMessage.listen((data) {
      if (!mounted) return;
      final chatRoomId = data['chatRoomId']?.toString() ?? '';
      if (chatRoomId.isEmpty) return;

      final String message = data['message']?.toString() ?? '';
      final String messageType = data['messageType']?.toString() ?? 'text';
      final String senderId = data['senderId']?.toString() ?? '';
      final dynamic timestamp = data['timestamp'];

      final idx = _socketChatRooms
          .indexWhere((r) => r['chatRoomId']?.toString() == chatRoomId);
      if (idx == -1) {
        // This is a new conversation not yet in the local list.
        // Re-fetch the full room list so the new chat appears immediately.
        _refreshChatRooms();
        return;
      }

      final room = Map<String, dynamic>.from(_socketChatRooms[idx]);
      room['lastMessage'] = message;
      room['lastMessageType'] = messageType;
      room['lastMessageTime'] = timestamp;
      room['lastMessageSenderId'] = senderId;

      // Increment unread count for messages received from the other participant.
      if (senderId != userId) {
        final int prevUnread = _safeUnreadCount(room['unreadCount']);
        room['unreadCount'] = prevUnread + 1;
      }

      // If user is actively scrolling, defer the update to prevent scroll jank
      if (_isUserScrolling) {
        _pendingRoomUpdate = [room];
        return;
      }

      _applyRoomUpdate([room]);
    });
  }

  /// Applies room updates and recomputes totals (avoiding duplicate logic)
  void _applyRoomUpdate(List<Map<String, dynamic>> updatedRooms) {
    if (updatedRooms.isEmpty) return;

    final room = updatedRooms[0];
    final idx = _socketChatRooms.indexWhere(
        (r) => r['chatRoomId']?.toString() == room['chatRoomId']?.toString());

    if (idx >= 0) {
      setState(() {
        _socketChatRooms.removeAt(idx);
        _socketChatRooms.insert(0, room);
        // Recompute totals so the header badge stays accurate.
        int totalUnread = 0;
        int unreadConvs = 0;
        for (final r in _socketChatRooms) {
          final int u = _safeUnreadCount(r['unreadCount']);
          totalUnread += u;
          if (u > 0) unreadConvs++;
        }
        _totalUnreadCount = totalUnread;
        _totalUnreadConversations = unreadConvs;
      });

      // Keep the pinned admin card in sync when the admin room receives a message.
      if (_isAdminRoom(room)) {
        final String preview = _formatConversationPreview(
          rawMessage: room['lastMessage']?.toString() ?? '',
          messageType: room['lastMessageType']?.toString() ?? 'text',
          compactMediaLabels: true,
        );
        DateTime? latestTime;
        final timestamp = room['lastMessageTime'];
        if (timestamp is String) latestTime = DateTime.tryParse(timestamp);
        setState(() {
          _adminLastMessage = preview;
          _adminLastMessageTime = latestTime;
          final senderId = room['lastMessageSenderId']?.toString() ?? '';
          if (senderId != userId && senderId.isNotEmpty) _adminUnreadCount += 1;
        });
      }
    }
  }

  /// Listen to Socket.IO user_status_change for admin's online status.
  void _startAdminStatusListener() {
    _adminStatusSubscription?.cancel();

    // Fetch initial admin status
    SocketService().getUserStatus(_adminUserId).then((statusData) {
      if (!mounted) return;
      final bool online = statusData['isOnline'] == true;
      setState(() {
        _adminOnline = online;
      });
    }).catchError((e) {
      print('Error fetching admin status: $e');
    });

    // Listen for status changes
    _adminStatusSubscription =
        SocketService().onUserStatusChange.listen((data) {
      if (!mounted) return;
      final uid = data['userId']?.toString() ?? '';
      if (uid != _adminUserId) return;
      final bool online = data['isOnline'] == true;
      setState(() {
        _adminOnline = online;
      });
    });
  }

  /// Seed [_onlineStatuses] and [_lastSeenTimes] from the `participantOnlineStatus`
  /// and `participantLastSeen` maps that the server now embeds in each room.
  /// This gives accurate initial indicators before any real-time events arrive.
  void _updateOnlineStatusesFromRooms(List<Map<String, dynamic>> rooms) {
    final Map<String, bool> updates = {};
    final Map<String, DateTime?> lastSeenUpdates = {};
    for (final room in rooms) {
      final onlineMap = room['participantOnlineStatus'];
      final lastSeenMap = room['participantLastSeen'];
      if (onlineMap is Map) {
        onlineMap.forEach((k, v) {
          updates[k.toString()] = v == true;
        });
      }
      if (lastSeenMap is Map) {
        lastSeenMap.forEach((k, v) {
          lastSeenUpdates[k.toString()] = SocketService.parseTimestamp(v);
        });
      }
    }
    if (updates.isNotEmpty || lastSeenUpdates.isNotEmpty) {
      setState(() {
        _onlineStatuses.addAll(updates);
        _lastSeenTimes.addAll(lastSeenUpdates);
      });
    }
  }

  /// Listen to Socket.IO user-status events and update per-participant maps.
  void _startOnlineStatusListeners() {
    _onlineStatusSubscription?.cancel();
    _onlineStatusSubscription =
        SocketService().onUserStatusChange.listen((data) {
      if (!mounted) return;
      final uid = data['userId']?.toString() ?? '';
      if (uid.isEmpty) return;
      final bool online = data['isOnline'] == true;
      final DateTime? lastSeen = SocketService.parseTimestamp(data['lastSeen']);
      setState(() {
        _onlineStatuses[uid] = online;
        _lastSeenTimes[uid] = lastSeen;
      });
    });
  }

  String _formatTime(DateTime? time) {
    if (time == null) return '';
    return DateFormat('hh:mm a').format(time.toLocal());
  }

  /// Safely converts a dynamic map (typically from a socket event payload) to
  /// Map<String, String>, tolerating null values and non-string entries.
  /// This avoids [TypeError] exceptions that occur when [Map.from()] is called
  /// on a map whose values are not already of type String.
  Map<String, String> _safeStringMap(dynamic raw) {
    if (raw is! Map) return {};
    return Map<String, String>.fromEntries(
      raw.entries
          .map((e) => MapEntry(e.key.toString(), e.value?.toString() ?? '')),
    );
  }

  /// Safely normalizes a dynamic map payload to Map<String, dynamic>.
  Map<String, dynamic>? _safeDynamicMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return null;
  }

  /// Converts a dynamic list payload to a list of map payloads, skipping
  /// malformed entries instead of throwing cast errors.
  List<Map<String, dynamic>> _safeRoomList(dynamic rawRooms) {
    if (rawRooms is! List) return const [];
    final out = <Map<String, dynamic>>[];
    for (final item in rawRooms) {
      final map = _safeDynamicMap(item);
      if (map != null) out.add(map);
    }
    return out;
  }

  // User-side public label: MS user ID + last name (first name hidden).
  String _publicIdentityFromIds({String? userId, String? lastName}) {
    final String u = (userId ?? '').trim();
    final String idPart = u.isEmpty ? 'MS ID' : 'MS$u';
    final String ln = (lastName ?? '').trim();
    if (ln.isEmpty) return idPart;
    return '$idPart $ln';
  }

  String _extractLastName(String rawName) {
    final parts = rawName
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '';
    return parts.last;
  }

  String _publicNameForProposal(ProposalModel req) {
    return _publicIdentityFromIds(
      userId: (req.senderId ?? req.receiverId),
      lastName: req.lastName,
    );
  }

  /// Safely converts a dynamic list (typically from a socket event payload) to
  /// List<String>, converting each element via [toString()] to avoid
  /// [TypeError] exceptions when integer participant IDs are present.
  List<String> _safeStringList(dynamic raw) {
    if (raw is! List) return [];
    return raw.map((e) => e?.toString() ?? '').toList();
  }

  /// Reads unread count from number/string/map payloads safely.
  int _safeUnreadCount(dynamic raw) {
    if (raw == null) return 0;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw) ?? 0;
    if (raw is Map) {
      final myId = userId.trim();
      final dynamic mine =
          raw[myId] ?? raw[int.tryParse(myId)] ?? raw[myId.toString()];
      if (mine is num) return mine.toInt();
      if (mine is String) return int.tryParse(mine) ?? 0;
      for (final value in raw.values) {
        if (value is num) return value.toInt();
        if (value is String) {
          final parsed = int.tryParse(value);
          if (parsed != null) return parsed;
        }
      }
    }
    return 0;
  }

  /// Falls back to room-id parsing if participants are missing in payload.
  List<String> _participantsFromRoom(Map<String, dynamic> room) {
    final fromPayload = _safeStringList(room['participants'])
        .where((e) => e.trim().isNotEmpty)
        .toList();
    if (fromPayload.isNotEmpty) return fromPayload;

    final fromNameKeys = _safeStringMap(room['participantNames'])
        .keys
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (fromNameKeys.isNotEmpty) return fromNameKeys;

    final chatRoomId = room['chatRoomId']?.toString() ?? '';
    if (chatRoomId.isEmpty) return const [];

    var parts =
        chatRoomId.split('_').where((e) => e.trim().isNotEmpty).toList();
    if (parts.length == 3 && parts.first.toLowerCase() == 'chat') {
      parts = parts.sublist(1);
    }
    return parts;
  }

  /// Fetch fresh chat rooms from the server and update state.
  /// Called on demand (e.g. after returning from ChatDetailScreen).
  Future<void> _refreshChatRooms({bool force = false}) async {
    if (userId.isEmpty || !mounted) return;

    final now = DateTime.now();
    if (!force &&
        _lastSuccessfulChatRoomsFetch != null &&
        now.difference(_lastSuccessfulChatRoomsFetch!) < _minRefreshGap) {
      return;
    }

    if (_chatRoomsRefreshInFlight) {
      _chatRoomsRefreshQueued = true;
      return;
    }

    _chatRoomsRefreshInFlight = true;
    _lastChatRoomsFetch = DateTime.now();
    try {
      final parsedRooms = await _fetchChatRoomsWithRetry(userId);
      if (!mounted) return;

      // Guard: don't overwrite real data with an empty timeout response.
      if (parsedRooms.isEmpty && _socketChatRooms.isNotEmpty) {
        if (!_chatRoomsInitialized) {
          setState(() => _chatRoomsInitialized = true);
        }
        return;
      }

      int totalUnread = 0;
      int unreadConvs = 0;
      for (final room in parsedRooms) {
        final int unread = _safeUnreadCount(room['unreadCount']);
        totalUnread += unread;
        if (unread > 0) unreadConvs++;
      }
      final nonAdminRooms = parsedRooms.where((r) => !_isAdminRoom(r)).toList();
      setState(() {
        _socketChatRooms = parsedRooms;
        _cachedTotalRooms = nonAdminRooms.length;
        _chatRoomsInitialized = true;
        _totalUnreadCount = totalUnread;
        _totalUnreadConversations = unreadConvs;
      });
      _lastSuccessfulChatRoomsFetch = DateTime.now();
      _saveChatRoomsToCache(parsedRooms);
      _updateOnlineStatusesFromRooms(parsedRooms);
    } catch (e) {
      debugPrint('_refreshChatRooms error: $e');
    } finally {
      _chatRoomsRefreshInFlight = false;
      if (_chatRoomsRefreshQueued && mounted) {
        _chatRoomsRefreshQueued = false;
        Future.microtask(() => _refreshChatRooms(force: true));
      }
    }
  }

  /// Placeholder used to mask the tail of a message preview for non-premium users.
  static const String _previewMask = '****';

  /// Masks all words after the first one with [_previewMask].
  ///
  /// Applied in the [_MessageViewContext.listPreview] context for non-premium
  /// users so they see only the first word and a single placeholder for the
  /// rest.  Returns the original message unchanged when it is a single word.
  ///
  /// Example: "Hello world how are you" → "Hello ****"
  String _maskMessagePreview(String message) {
    if (message.isEmpty) return message;
    final words =
        message.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.length <= 1) return message;
    return '${words.first} $_previewMask';
  }

  String _formatConversationPreview({
    required String rawMessage,
    String? messageType,
    bool compactMediaLabels = false,
  }) {
    final type = messageType?.trim().toLowerCase();
    switch (type) {
      case 'image':
        return compactMediaLabels ? '📷 Image' : '📷 Photo';
      case 'image_gallery':
        return compactMediaLabels ? '🖼️ Gallery' : '🖼️ Photos';
      case 'voice':
        return compactMediaLabels ? '🎤 Voice note' : '🎤 Voice message';
      case 'doc':
        return '📄 Document';
      case 'profile_card':
        return '👤 Profile Card';
      case 'report':
        return '🚩 Profile Report';
      case 'call':
        return _formatCallPreview(rawMessage);
      case 'text':
      case null:
        break;
      default:
        return rawMessage;
    }

    final decoded = _tryParseJsonMap(rawMessage);
    if (decoded != null &&
        (decoded.containsKey('callType') ||
            decoded.containsKey('callStatus') ||
            decoded.containsKey('callDuration') ||
            decoded.containsKey('duration') ||
            decoded.containsKey('label'))) {
      return _formatCallPreview(rawMessage, decoded: decoded);
    }

    return rawMessage;
  }

  String _formatCallPreview(
    String rawMessage, {
    Map<String, dynamic>? decoded,
  }) {
    final payload = decoded ?? _tryParseJsonMap(rawMessage);
    if (payload == null) {
      return rawMessage.isEmpty ? 'Call' : rawMessage;
    }

    final String callType = payload['callType']?.toString() ?? '';
    final String status = payload['callStatus']?.toString() ?? '';
    final String label = (payload['label']?.toString() ?? '').trim();
    final int durationSeconds = (payload['duration'] as num?)?.toInt() ??
        (payload['callDuration'] as num?)?.toInt() ??
        0;
    final bool isVideo = callType == 'video';

    if (label.isNotEmpty) {
      return label;
    }

    if (status == 'missed') {
      return isVideo ? 'Missed Video Call' : 'Missed Call';
    }
    if (status == 'declined') {
      return isVideo ? 'Video Call Declined' : 'Call Declined';
    }
    if (status == 'cancelled') {
      return isVideo ? 'Video Call Cancelled' : 'Call Cancelled';
    }
    if (status == 'busy') {
      return isVideo ? 'Video Call (Busy)' : 'Voice Call (Busy)';
    }

    final String baseLabel =
        isVideo ? 'Video Call' : (callType == 'audio' ? 'Audio Call' : 'Call');
    if (durationSeconds <= 0) return baseLabel;
    return '$baseLabel • ${_formatCallDuration(durationSeconds)}';
  }

  Map<String, dynamic>? _tryParseJsonMap(String rawMessage) {
    if (rawMessage.isEmpty) return null;
    try {
      final decoded = jsonDecode(rawMessage);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
    return null;
  }

  String _formatCallDuration(int seconds) {
    final duration = Duration(seconds: seconds);
    final hours = duration.inHours;
    if (hours > 0) {
      final remainingMinutes = duration.inMinutes.remainder(60);
      final secondsComponent = duration.inSeconds.remainder(60);
      return '$hours:${remainingMinutes.toString().padLeft(2, '0')}:${secondsComponent.toString().padLeft(2, '0')}';
    }
    final minutes = duration.inMinutes;
    final secondsComponent = duration.inSeconds.remainder(60);
    return '$minutes:${secondsComponent.toString().padLeft(2, '0')}';
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: TextField(
        controller: _searchController,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Search chats',
          prefixIcon: const Icon(Icons.search, color: Colors.black45),
          suffixIcon: _searchQuery.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, color: Colors.black45),
                  onPressed: () {
                    _searchController.clear();
                    FocusScope.of(context).unfocus();
                  },
                ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFF90E18), width: 1.4),
          ),
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _filterChatRooms(
      List<Map<String, dynamic>> rooms) {
    if (_searchQuery.isEmpty) return rooms;
    return rooms.where((room) {
      final participantNames = _safeStringMap(room['participantNames']);
      final names = participantNames.values.join(' ').toLowerCase();
      final String lastMessage = room['lastMessage']?.toString() ?? '';
      final String messageType = room['lastMessageType']?.toString() ?? 'text';
      final preview = _formatConversationPreview(
        rawMessage: lastMessage,
        messageType: messageType,
        compactMediaLabels: true,
      ).toLowerCase();
      return names.contains(_searchQuery) || preview.contains(_searchQuery);
    }).toList();
  }

  /// Format a lastSeen timestamp into a human-readable "last active" string.
  String _formatLastSeen(DateTime lastSeen) => formatLastSeen(lastSeen);

  bool _isAdminRoom(Map<String, dynamic> room) {
    if (userId.isEmpty) return false;

    final participants = _participantsFromRoom(room);
    if (participants.contains(_adminUserId) && participants.contains(userId)) {
      return true;
    }

    final chatRoomId = room['chatRoomId']?.toString() ?? '';
    if (chatRoomId.isEmpty) return false;
    final ids = [userId, _adminUserId]..sort();
    return chatRoomId == ids.join('_');
  }

  Widget _buildPinnedAdminCard() {
    final String subtitle = _adminLoading
        ? 'Loading...'
        : (_adminLastMessage.isNotEmpty
            ? _adminLastMessage
            : 'Message us anytime for help');
    final String timeLabel = _formatTime(_adminLastMessageTime);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          await _markAdminChatSeen();
          if (!mounted) return;
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AdminChatScreen(
                senderID: userId,
                userName: 'Admin',
                isAdmin: false,
              ),
            ),
          );
          await _markAdminChatSeen();
        },
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFF90E18), Color(0xFFD00D15)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFF90E18).withOpacity(0.25),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Stack(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: Colors.white.withOpacity(0.2),
                    child: const Icon(Icons.support_agent,
                        color: Colors.white, size: 24),
                  ),
                  Positioned(
                    bottom: 1,
                    right: 1,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: _adminOnline
                            ? const Color(0xFF22C55E)
                            : Colors.grey.shade400,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          _adminDisplayName,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (_adminUnreadCount > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '$_adminUnreadCount',
                              style: const TextStyle(
                                color: Color(0xFFF90E18),
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        const Spacer(),
                        if (timeLabel.isNotEmpty)
                          Text(
                            timeLabel,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.8),
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          margin: const EdgeInsets.only(right: 5),
                          decoration: BoxDecoration(
                            color: _adminOnline
                                ? const Color(0xFF22C55E)
                                : Colors.grey.shade400,
                            shape: BoxShape.circle,
                          ),
                        ),
                        Text(
                          _adminOnline ? 'Online' : 'Offline',
                          style: TextStyle(
                            color: _adminOnline
                                ? const Color(0xFF22C55E)
                                : Colors.white.withOpacity(0.9),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (!_adminLoading && subtitle.isNotEmpty) ...[
                          Text(
                            ' · ',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 12,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.9),
                                fontSize: 12,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleAcceptChatRequest(ProposalModel proposal) async {
    final userState = context.read<UserState>();
    // Step 1: Check document status
    if (!await VerificationService.requireVerification(context)) return;

    // Step 2: Confirm and accept
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Accept Chat Request"),
        content: Text(
          "${_publicNameForProposal(proposal)} wants to chat with you. Accept?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Accept"),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final success = await ProposalService.acceptProposal(
        proposal.proposalId.toString(),
        userId,
      );
      if (mounted) Navigator.pop(context);

      if (success) {
        // Create chat room via Socket.IO and send "Ok Let's Talk" message
        try {
          final senderId = proposal.senderId ?? '';
          final senderName = _publicNameForProposal(proposal);
          final senderImage = resolveApiImageUrl(proposal.profilePicture ?? '');

          if (senderId.isNotEmpty) {
            final List<String> ids = [userId, senderId]..sort();
            final chatRoomId = ids.join('_');

            SocketService().sendMessage(
              chatRoomId: chatRoomId,
              senderId: userId,
              receiverId: senderId,
              message: "Ok Let's Talk",
              messageType: 'text',
              messageId: const Uuid().v4(),
              user1Name: name,
              user2Name: senderName,
              user1Image: _resolvedCurrentUserImage(),
              user2Image: senderImage,
            );

            // Send notification to the request sender
            await NotificationService.sendChatNotification(
              recipientUserId: senderId,
              senderName: _publicIdentityFromIds(userId: userId),
              senderId: userId,
              message: "Ok Let's Talk",
            );
          }
        } catch (e) {
          print('Error creating chat room or sending initial message: $e');
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Chat request accepted"),
            backgroundColor: Colors.green,
          ),
        );
        await _loadPendingChatRequests(userId);
        // Refresh chat rooms so the newly created conversation appears in the
        // list immediately instead of waiting for the next socket event.
        _refreshChatRooms();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Failed to accept request"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _handleRejectChatRequest(ProposalModel proposal) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Reject Chat Request"),
        content: const Text("Are you sure you want to reject this request?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Reject"),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final success = await ProposalService.rejectProposal(
        proposal.proposalId.toString(),
        userId,
      );
      if (mounted) Navigator.pop(context);

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Chat request rejected"),
            backgroundColor: Colors.orange,
          ),
        );
        await _loadPendingChatRequests(userId);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Failed to reject request"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
      );
    }
  }

  void _showUpgradeDialog(BuildContext context) {
    showUpgradeDialog(context);
  }

  void _showChatRequestActionSheet(ProposalModel req) {
    final displayName = _publicNameForProposal(req);
    final imageUrl = req.profilePicture?.isNotEmpty == true
        ? req.profilePicture!
        : 'https://static.vecteezy.com/system/resources/previews/022/997/791/non_2x/contact-person-icon-transparent-blur-glass-effect-icon-free-vector.jpg';

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      backgroundColor: Colors.white,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 20),
            PrivacyUtils.buildPrivacyAwareAvatar(
              imageUrl: imageUrl,
              privacy: req.privacy,
              photoRequest: req.photoRequest,
              radius: 32,
            ),
            const SizedBox(height: 12),
            Text(
              displayName,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F172A),
              ),
            ),
            if ((req.city ?? '').isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                req.city!,
                style: const TextStyle(fontSize: 13, color: Colors.black54),
              ),
            ],
            const SizedBox(height: 8),
            const Text(
              'Wants to chat with you',
              style: TextStyle(fontSize: 14, color: Colors.black54),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  final profileId = req.senderId ?? '';
                  if (profileId.isNotEmpty) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ProfileScreen(userId: profileId),
                      ),
                    ).then((_) => _loadPendingChatRequests(userId));
                  }
                },
                icon: const Icon(Icons.person_outline),
                label: const Text(
                  'View Profile',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF90E18),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 0,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _handleRejectChatRequest(req);
                    },
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFE0E0E0)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text(
                      'Reject',
                      style: TextStyle(
                          color: Colors.black54,
                          fontSize: 15,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _handleAcceptChatRequest(req);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1565C0),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Accept',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatRequestCard(ProposalModel req) {
    final imageUrl = req.profilePicture?.isNotEmpty == true
        ? req.profilePicture!
        : 'https://static.vecteezy.com/system/resources/previews/022/997/791/non_2x/contact-person-icon-transparent-blur-glass-effect-icon-free-vector.jpg';
    final displayName = _publicNameForProposal(req);

    return InkWell(
      onTap: () {
        final senderId = req.senderId ?? '';
        if (senderId.isNotEmpty) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ProfileScreen(userId: senderId),
            ),
          ).then((_) async {
            if (mounted) {
              await _loadPendingChatRequests(userId);
              _refreshChatRooms();
            }
          });
        }
      },
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.white, Color(0xFFF8FAFC)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                PrivacyUtils.buildPrivacyAwareAvatar(
                  imageUrl: imageUrl,
                  privacy: req.privacy,
                  photoRequest: req.photoRequest,
                  radius: 28,
                  backgroundColor: Colors.grey[200],
                ),
                Positioned(
                  bottom: -4,
                  right: -4,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF90E18),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.chat_bubble,
                        size: 12, color: Colors.white),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF0F172A),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  if ((req.city ?? '').isNotEmpty)
                    Text(
                      req.city!,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 3),
                  const Text(
                    'Wants to chat with you',
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFFF90E18),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  label: 'Accept chat request from $displayName',
                  button: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _handleAcceptChatRequest(req),
                    child: ExcludeSemantics(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF90E18),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'Accept',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Semantics(
                  label: 'Reject chat request from $displayName',
                  button: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _handleRejectChatRequest(req),
                    child: ExcludeSemantics(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'Reject',
                          style: TextStyle(
                            color: Colors.black54,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
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
  }

  Widget _buildSentChatRequestCard(ProposalModel req) {
    final imageUrl = req.profilePicture?.isNotEmpty == true
        ? req.profilePicture!
        : 'https://static.vecteezy.com/system/resources/previews/022/997/791/non_2x/contact-person-icon-transparent-blur-glass-effect-icon-free-vector.jpg';
    final displayName = _publicNameForProposal(req);

    return InkWell(
      onTap: () => _showSentChatRequestSheet(req),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.white, Color(0xFFF8FAFC)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                PrivacyUtils.buildPrivacyAwareAvatar(
                  imageUrl: imageUrl,
                  privacy: req.privacy,
                  photoRequest: req.photoRequest,
                  radius: 28,
                  backgroundColor: Colors.grey[200],
                ),
                Positioned(
                  bottom: -4,
                  right: -4,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      color: Color(0xFF1565C0),
                      shape: BoxShape.circle,
                    ),
                    child:
                        const Icon(Icons.send, size: 12, color: Colors.white),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF0F172A),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  if ((req.city ?? '').isNotEmpty)
                    Text(
                      req.city!,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 3),
                  const Text(
                    'Chat request sent · Awaiting response',
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFF1565C0),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFF1565C0).withOpacity(0.10),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'Pending',
                style: TextStyle(
                  color: Color(0xFF1565C0),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSentChatRequestSheet(ProposalModel req) {
    final displayName = _publicNameForProposal(req);
    final imageUrl = req.profilePicture?.isNotEmpty == true
        ? req.profilePicture!
        : 'https://static.vecteezy.com/system/resources/previews/022/997/791/non_2x/contact-person-icon-transparent-blur-glass-effect-icon-free-vector.jpg';

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      backgroundColor: Colors.white,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 20),
            PrivacyUtils.buildPrivacyAwareAvatar(
              imageUrl: imageUrl,
              privacy: req.privacy,
              photoRequest: req.photoRequest,
              radius: 32,
            ),
            const SizedBox(height: 12),
            Text(
              displayName,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F172A),
              ),
            ),
            if ((req.city ?? '').isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                req.city!,
                style: const TextStyle(fontSize: 13, color: Colors.black54),
              ),
            ],
            const SizedBox(height: 8),
            const Text(
              'Chat request sent · Awaiting response',
              style: TextStyle(fontSize: 14, color: Color(0xFF1565C0)),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  final profileId = req.receiverId ?? '';
                  if (profileId.isNotEmpty) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ProfileScreen(userId: profileId),
                      ),
                    ).then((_) => _loadPendingChatRequests(userId));
                  }
                },
                icon: const Icon(Icons.person_outline),
                label: const Text(
                  'View Profile',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF90E18),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 0,
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _handleCancelChatRequest(req);
                },
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFE0E0E0)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text(
                  'Cancel Request',
                  style: TextStyle(
                      color: Colors.black54,
                      fontSize: 15,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleCancelChatRequest(ProposalModel proposal) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Cancel Chat Request"),
        content: const Text("Are you sure you want to cancel this request?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("No"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Yes, Cancel"),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final success = await ProposalService.deleteProposal(
        userId,
        proposal.proposalId.toString(),
      );
      if (mounted) Navigator.pop(context);

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Chat request cancelled"),
            backgroundColor: Colors.orange,
          ),
        );
        await _loadPendingChatRequests(userId);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Failed to cancel request"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
      );
    }
  }

  Widget build(BuildContext context) {
    if (isLoading) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          title: const Text('Chat', style: TextStyle(color: Colors.black87)),
        ),
        body: const SingleChildScrollView(
          physics: NeverScrollableScrollPhysics(),
          child: ChatListSkeleton(count: 8),
        ),
      );
    }

    if (userId.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          title: const Text('Chat', style: TextStyle(color: Colors.black87)),
        ),
        body: const Center(
          child: Text('Unable to load user data'),
        ),
      );
    }

    // Web wide-screen: two-panel layout (like WhatsApp Web)
    if (kIsWeb && ResponsiveLayout.isWideLayout(context)) {
      return Scaffold(
        body: Row(
          children: [
            SizedBox(
              width: 360,
              child: _buildChatListScaffold(),
            ),
            const VerticalDivider(width: 1, thickness: 1),
            Expanded(child: _buildWebDetailPanel()),
          ],
        ),
      );
    }

    // Mobile / narrow layout: original full-screen Scaffold
    return Scaffold(
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFF90E18), Color(0xFFD00D15)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.white,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
          systemStatusBarContrastEnforced: false,
        ),
        title: Row(
          children: [
            const Text('Chats',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600)),
            const SizedBox(width: 12),
            if (_totalUnreadConversations > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$_totalUnreadConversations',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                icon: const Icon(Icons.favorite_border),
                tooltip: 'Proposals',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ProposalsPage(),
                    ),
                  );
                },
              ),
              if (_receivedProposalCount > 0)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    constraints:
                        const BoxConstraints(minWidth: 18, minHeight: 18),
                    child: Text(
                      _receivedProposalCount > 99
                          ? '99+'
                          : '$_receivedProposalCount',
                      style: const TextStyle(
                        color: Color(0xFFF90E18),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_rounded),
                tooltip: 'Notifications',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const MatrimonyNotificationPage(),
                    ),
                  ).then((_) => _loadUnreadNotificationCount());
                },
              ),
              if (_unreadNotificationCount > 0)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    constraints:
                        const BoxConstraints(minWidth: 18, minHeight: 18),
                    child: Text(
                      _unreadNotificationCount > 99
                          ? '99+'
                          : '$_unreadNotificationCount',
                      style: const TextStyle(
                        color: Color(0xFFF90E18),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.call),
            tooltip: 'Call History',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const CallHistoryScreen(),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Sound & Vibration',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SoundVibrationSettingsScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: Container(
        color: const Color(0xFFFAF0F0),
        child: Column(
          children: [
            _buildSearchBar(),
            _buildPinnedAdminCard(),
            if (_totalUnreadCount > 0)
              Container(
                color: const Color(0xFFF90E18).withOpacity(0.08),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.message,
                        color: Color(0xFFF90E18), size: 18),
                    const SizedBox(width: 8),
                    Text(
                      '$_totalUnreadCount unread messages in $_totalUnreadConversations conversations',
                      style: const TextStyle(
                        color: Color(0xFFF90E18),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: _buildChatListWithDebug(),
            ),
          ],
        ),
      ),
      floatingActionButton: null,
    );
  }

  /// Builds the main chat list scaffold (used as the left panel on web).
  Widget _buildChatListScaffold() {
    return Scaffold(
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFF90E18), Color(0xFFD00D15)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            const Text('Chats',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600)),
            const SizedBox(width: 12),
            if (_totalUnreadConversations > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$_totalUnreadConversations',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
      body: Container(
        color: const Color(0xFFFAF0F0),
        child: Column(
          children: [
            _buildSearchBar(),
            _buildPinnedAdminCard(),
            if (_totalUnreadCount > 0)
              Container(
                color: const Color(0xFFF90E18).withOpacity(0.08),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.message,
                        color: Color(0xFFF90E18), size: 18),
                    const SizedBox(width: 8),
                    Text(
                      '$_totalUnreadCount unread messages in $_totalUnreadConversations conversations',
                      style: const TextStyle(
                        color: Color(0xFFF90E18),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: _buildChatListWithDebug(),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds the right detail panel for web two-panel layout.
  Widget _buildWebDetailPanel() {
    final sel = _webSelectedChatData;
    if (sel == null) {
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF8FAFF), Color(0xFFF3F6FC), Color(0xFFEFF2F8)],
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 32),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.88),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFE5EAF2)),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0F172A).withOpacity(0.08),
                    blurRadius: 28,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 84,
                    height: 84,
                    decoration: const BoxDecoration(
                      color: Color(0xFFEEF3FF),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.chat_bubble_outline_rounded,
                      size: 42,
                      color: Color(0xFF3056D3),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Your conversations live here',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Select any chat from the left panel to open messages, calls, and media in one place.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.45,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return ChatDetailScreen(
      key: ValueKey(sel['chatRoomId']),
      chatRoomId: sel['chatRoomId']!,
      receiverId: sel['receiverId']!,
      receiverName: sel['receiverName']!,
      receiverImage: sel['receiverImage']!,
      receiverPrivacy: sel['receiverPrivacy'],
      receiverPhotoRequest: sel['receiverPhotoRequest'],
      currentUserId: userId,
      currentUserName: name,
      currentUserImage: _resolvedCurrentUserImage(),
    );
  }

  Widget _buildChatListWithDebug() {
    if (!_chatRoomsInitialized) {
      return const SingleChildScrollView(
        physics: NeverScrollableScrollPhysics(),
        child: ChatListSkeleton(count: 7),
      );
    }

    // Sort client-side by lastMessageTime descending.
    final chatRooms = List<Map<String, dynamic>>.from(
      _socketChatRooms.where((room) => !_isAdminRoom(room)),
    )..sort((a, b) {
        final aTime = SocketService.parseTimestamp(a['lastMessageTime']);
        final bTime = SocketService.parseTimestamp(b['lastMessageTime']);
        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return bTime.compareTo(aTime);
      });

    final filteredRooms = _filterChatRooms(chatRooms);

    if (filteredRooms.isEmpty &&
        _pendingChatRequests.isEmpty &&
        _sentChatRequests.isEmpty &&
        !_requestsLoading &&
        !_sentRequestsLoading &&
        _searchQuery.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(Icons.chat_bubble_outline,
                  size: 44, color: Color(0xFFF90E18)),
            ),
            const SizedBox(height: 16),
            const Text(
              'No conversations yet',
              style: TextStyle(fontSize: 16, color: Colors.black87),
            ),
            const SizedBox(height: 6),
            Text(
              'Send a chat request to start talking',
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    if (filteredRooms.isEmpty && _searchQuery.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text(
              'No chats match your search',
              style: TextStyle(fontSize: 15, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return _buildRoomsList(filteredRooms);
  }

  Widget _buildRoomsList(List<Map<String, dynamic>> chatRooms) {
    final bool isSearching = _searchQuery.isNotEmpty;
    final displayedRooms = isSearching
        ? chatRooms
        : chatRooms.sublist(0, _displayCount.clamp(0, chatRooms.length));

    final int reqCount = _pendingChatRequests.length;
    final int sentCount = _sentChatRequests.length;

    // Section visibility flags
    final bool showRequestsHeader = _requestsLoading || reqCount > 0;
    final bool showSentHeader = _sentRequestsLoading || sentCount > 0;
    final bool showConversationsHeader =
        (showRequestsHeader || showSentHeader) && displayedRooms.isNotEmpty;

    // ── Section widgets: carousels for requests + conversations header ─────────
    final bool showLoadingMore = _isLoadingMore && !isSearching;
    final List<Widget> sectionItems = [];
    if (showRequestsHeader)
      sectionItems.add(_buildReceivedRequestsCarousel(reqCount));
    if (showSentHeader) sectionItems.add(_buildSentRequestsCarousel(sentCount));
    if (showConversationsHeader) {
      sectionItems.add(Semantics(
        header: true,
        label: 'Conversations section',
        child: Container(
          color: Colors.grey.shade50,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: const Text(
            'Conversations',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.black54,
            ),
          ),
        ),
      ));
    }
    final int sectionCount = sectionItems.length;
    final int totalItems =
        sectionCount + displayedRooms.length + (showLoadingMore ? 1 : 0);

    return Container(
      color: Colors.white,
      child: ListView.separated(
        controller: _scrollController,
        itemCount: totalItems,
        separatorBuilder: (_, index) {
          if (index < sectionCount) return const SizedBox.shrink();
          return const Divider(indent: 72, height: 1, color: Color(0xFFE0E0E0));
        },
        itemBuilder: (context, index) {
          // ── Section items (carousels, conversations header) ──
          if (index < sectionCount) return sectionItems[index];

          // ── Loading indicator at tail ──
          final int roomIndex = index - sectionCount;
          if (showLoadingMore && roomIndex == displayedRooms.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                  child: CircularProgressIndicator(color: Color(0xFFF90E18))),
            );
          }

          final data = displayedRooms[roomIndex];

          final participants = _participantsFromRoom(data);
          final participantNames = _safeStringMap(data['participantNames']);
          final participantImages = _safeStringMap(data['participantImages']);
          final participantPrivacy = _safeStringMap(data['participantPrivacy']);
          final participantPhotoRequests =
              _safeStringMap(data['participantPhotoRequests']);
          final int unreadForMe = _safeUnreadCount(data['unreadCount']);
          final String lastMessage = data['lastMessage']?.toString() ?? '';
          final DateTime? lastMessageTime =
              SocketService.parseTimestamp(data['lastMessageTime']);
          final String lastMessageType =
              data['lastMessageType']?.toString() ?? 'text';
          final lastMessageSenderId = data['lastMessageSenderId'] ?? '';

          // Find the OTHER participant (not me). Be defensive because payload
          // fields can occasionally be partial during reconnect windows.
          String otherParticipantId = '';
          String otherPersonName = '';

          for (var participantId in participants) {
            if (participantId.trim() != userId.trim()) {
              otherParticipantId = participantId;
              final rawName = participantNames[otherParticipantId] ?? '';
              otherPersonName = _publicIdentityFromIds(
                userId: otherParticipantId,
                lastName: _extractLastName(rawName),
              );
              break;
            }
          }

          if (otherParticipantId.isEmpty) {
            for (final entry in participantNames.entries) {
              if (entry.key.trim() != userId.trim()) {
                otherParticipantId = entry.key.trim();
                otherPersonName = _publicIdentityFromIds(
                  userId: otherParticipantId,
                  lastName: _extractLastName(entry.value),
                );
                break;
              }
            }
          }

          if (otherParticipantId.isEmpty) {
            for (final key in participantImages.keys) {
              if (key.trim() != userId.trim()) {
                otherParticipantId = key.trim();
                break;
              }
            }
          }

          if (otherParticipantId.isEmpty) {
            final chatRoomId = data['chatRoomId']?.toString() ?? '';
            if (chatRoomId.isNotEmpty) {
              final parts = chatRoomId
                  .split('_')
                  .where((e) => e.trim().isNotEmpty)
                  .toList();
              for (final p in parts) {
                if (p != 'chat' && p.trim() != userId.trim()) {
                  otherParticipantId = p.trim();
                  break;
                }
              }
            }
          }

          if (otherPersonName.isEmpty) {
            otherPersonName =
                _publicIdentityFromIds(userId: otherParticipantId);
          }

          // Determine if last message was sent by me
          final isLastMessageFromMe = lastMessageSenderId == userId;

          // Prepare message preview
          final String formattedPreview = _formatConversationPreview(
            rawMessage: lastMessage,
            messageType: lastMessageType,
          );

          // This block executes in the [_MessageViewContext.listPreview] context.
          // Non-premium users see only the first word of text messages received
          // from the other person; the rest is masked with "****".
          // Media/call labels are shown as-is since they convey no private text.
          //
          // NOTE: The [chat] context (ChatDetailScreen) NEVER applies masking –
          // full message text is always shown there regardless of premium status.
          final bool isCurrentUserPaid =
              context.read<UserState>().usertype == 'paid';
          final String normalizedMsgType = lastMessageType.trim().toLowerCase();
          final bool isTextType =
              normalizedMsgType == 'text' || normalizedMsgType.isEmpty;
          final bool shouldMaskPreview =
              !isLastMessageFromMe && !isCurrentUserPaid && isTextType;

          final String displayPreview = shouldMaskPreview
              ? _maskMessagePreview(formattedPreview)
              : formattedPreview;

          final String messagePreview =
              isLastMessageFromMe && displayPreview.isNotEmpty
                  ? 'You: $displayPreview'
                  : displayPreview;

          final String formattedTime = _formatTime(lastMessageTime);

          // Online status for this participant
          final bool isOnline = _onlineStatuses[otherParticipantId] ?? false;
          final DateTime? participantLastSeen =
              _lastSeenTimes[otherParticipantId];
          final String resolvedOtherImage =
              resolveApiImageUrl(participantImages[otherParticipantId] ?? '');

          // Extract privacy data for the other participant
          final String? otherParticipantPrivacy =
              participantPrivacy[otherParticipantId];
          final String? otherParticipantPhotoRequest =
              participantPhotoRequests[otherParticipantId];

          // Extract paid/verified status for the other participant
          final participantPaidStatus =
              _safeStringMap(data['participantPaidStatus']);
          final participantVerifiedStatus = Map<String, dynamic>.from(
              data['participantVerifiedStatus'] is Map
                  ? data['participantVerifiedStatus']
                  : <String, dynamic>{});
          final bool otherIsPaid =
              participantPaidStatus[otherParticipantId] == 'paid';
          final bool otherIsVerified =
              participantVerifiedStatus[otherParticipantId] == 1;

          return InkWell(
            onTap: () async {
              if (_isAdminRoom(data)) {
                _markAdminChatSeen();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AdminChatScreen(
                      senderID: userId,
                      userName: _adminDisplayName,
                      isAdmin: false,
                    ),
                  ),
                ).then((_) => _markAdminChatSeen());
                return;
              }
              final userState = context.read<UserState>();

              // Gate 1: user must be document-verified before entering any chat.
              if (!await VerificationService.requireVerification(context)) {
                return;
              }
              if (!context.mounted) return;

              // Gate 2: user must have an active package to open chat.
              // "Free users can ACCEPT requests but cannot OPEN chat without package."
              // Show upgrade dialog BEFORE navigation to prevent navigation loops.
              if (!userState.hasPackage) {
                _showUpgradeDialog(context);
                return;
              }
              final chatData = {
                'chatRoomId': data['chatRoomId']?.toString() ?? '',
                'receiverId': otherParticipantId,
                'receiverName': otherPersonName,
                'receiverImage': resolvedOtherImage,
                'receiverPrivacy': otherParticipantPrivacy,
                'receiverPhotoRequest': otherParticipantPhotoRequest,
              };
              if (kIsWeb && ResponsiveLayout.isWideLayout(context)) {
                // Web two-panel: update the right panel instead of navigating
                setState(() => _webSelectedChatData = chatData);
              } else {
                await _syncCurrentUserImageFromLocalCache();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ChatDetailScreen(
                      chatRoomId: chatData['chatRoomId']!,
                      receiverId: chatData['receiverId']!,
                      receiverName: chatData['receiverName']!,
                      receiverImage: chatData['receiverImage']!,
                      receiverPrivacy: chatData['receiverPrivacy'],
                      receiverPhotoRequest: chatData['receiverPhotoRequest'],
                      currentUserId: userId,
                      currentUserName: name,
                      currentUserImage: _resolvedCurrentUserImage(),
                    ),
                  ),
                ).then((_) => _refreshChatRooms());
              }
            },
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 6),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: unreadForMe > 0
                      ? const Color(0xFFFBCFE8)
                      : const Color(0xFFE5E7EB),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Profile Image with online status indicator
                  Stack(
                    children: [
                      PrivacyUtils.buildPrivacyAwareAvatar(
                        imageUrl: resolvedOtherImage,
                        privacy: otherParticipantPrivacy,
                        photoRequest: otherParticipantPhotoRequest,
                        radius: 28,
                        backgroundColor: Colors.grey[200],
                      ),
                      // Green online dot (top-right)
                      if (isOnline)
                        Positioned(
                          top: 0,
                          right: 0,
                          child: Container(
                            width: 13,
                            height: 13,
                            decoration: BoxDecoration(
                              color: const Color(0xFF22C55E),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                          ),
                        ),
                      // Unread count badge (bottom-right)
                      if (unreadForMe > 0)
                        Positioned(
                          bottom: -2,
                          right: -2,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(
                              color: Color(0xFFF90E18),
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '$unreadForMe',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),

                  const SizedBox(width: 12),

                  // Chat Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      otherPersonName,
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: unreadForMe > 0
                                            ? FontWeight.w700
                                            : FontWeight.w600,
                                        color: const Color(0xFF0F172A),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  // Verified badge
                                  if (otherIsVerified) ...[
                                    const SizedBox(width: 4),
                                    const Icon(Icons.verified,
                                        size: 14, color: Color(0xFF1DA1F2)),
                                  ],
                                  // Paid badge
                                  if (otherIsPaid) ...[
                                    const SizedBox(width: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 5, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFFD700)
                                            .withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                            color: const Color(0xFFB8860B),
                                            width: 0.5),
                                      ),
                                      child: const Text(
                                        'Paid',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Color(0xFFB8860B),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (formattedTime.isNotEmpty)
                              Text(
                                formattedTime,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: unreadForMe > 0
                                      ? const Color(0xFFF90E18)
                                      : Colors.grey[600],
                                  fontWeight: unreadForMe > 0
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        if (isOnline)
                          const Row(
                            children: [
                              Icon(Icons.circle,
                                  size: 8, color: Color(0xFF22C55E)),
                              SizedBox(width: 4),
                              Text(
                                'Online',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF22C55E),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          )
                        else if (participantLastSeen != null)
                          Row(
                            children: [
                              const Icon(Icons.access_time,
                                  size: 10, color: Colors.grey),
                              const SizedBox(width: 3),
                              Text(
                                _formatLastSeen(participantLastSeen),
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        const SizedBox(height: 3),
                        Text(
                          messagePreview,
                          style: TextStyle(
                            fontSize: 14,
                            color: unreadForMe > 0
                                ? const Color(0xFF0F172A)
                                : Colors.grey[700],
                            fontWeight: unreadForMe > 0
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                      ],
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

  // ── Received chat requests carousel ─────────────────────────────────────────
  Widget _buildReceivedRequestsCarousel(int reqCount) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          color: const Color(0xFFF90E18).withOpacity(0.06),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: _requestsLoading
              ? const LinearProgressIndicator()
              : Row(
                  children: [
                    const Icon(Icons.mark_chat_unread,
                        color: Color(0xFFF90E18), size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Chat Requests ($reqCount)',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFF90E18),
                      ),
                    ),
                    const Spacer(),
                    if (reqCount > 1)
                      Text(
                        '${_receivedReqPage + 1} / $reqCount',
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFFF90E18)),
                      ),
                  ],
                ),
        ),
        if (!_requestsLoading && reqCount > 0)
          SizedBox(
            height: 120,
            child: PageView.builder(
              controller: _receivedReqPageCtrl,
              itemCount: reqCount,
              onPageChanged: (p) => setState(() => _receivedReqPage = p),
              itemBuilder: (_, i) =>
                  _buildChatRequestCard(_pendingChatRequests[i]),
            ),
          ),
        if (!_requestsLoading && reqCount > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                reqCount,
                (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: i == _receivedReqPage ? 10 : 6,
                  height: 6,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    color: i == _receivedReqPage
                        ? const Color(0xFFF90E18)
                        : Colors.grey.shade300,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ── Sent chat requests carousel ───────────────────────────────────────────
  Widget _buildSentRequestsCarousel(int sentCount) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          color: const Color(0xFF1565C0).withOpacity(0.06),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: _sentRequestsLoading
              ? const LinearProgressIndicator()
              : Row(
                  children: [
                    const Icon(Icons.send, color: Color(0xFF1565C0), size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Sent Requests ($sentCount)',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1565C0),
                      ),
                    ),
                    const Spacer(),
                    if (sentCount > 1)
                      Text(
                        '${_sentReqPage + 1} / $sentCount',
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF1565C0)),
                      ),
                  ],
                ),
        ),
        if (!_sentRequestsLoading && sentCount > 0)
          SizedBox(
            height: 120,
            child: PageView.builder(
              controller: _sentReqPageCtrl,
              itemCount: sentCount,
              onPageChanged: (p) => setState(() => _sentReqPage = p),
              itemBuilder: (_, i) =>
                  _buildSentChatRequestCard(_sentChatRequests[i]),
            ),
          ),
        if (!_sentRequestsLoading && sentCount > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                sentCount,
                (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: i == _sentReqPage ? 10 : 6,
                  height: 6,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    color: i == _sentReqPage
                        ? const Color(0xFF1565C0)
                        : Colors.grey.shade300,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  void showUpgradeDialog(BuildContext context) {
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
                // Icon
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

                // Title
                const Text(
                  "Upgrade to Chat",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 12),

                // Description
                const Text(
                  "Unlock unlimited messaging and premium chat features by upgrading your plan.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),

                const SizedBox(height: 28),

                // Buttons
                Row(
                  children: [
                    // Skip Button
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

                    // Upgrade Button
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => SubscriptionPage(),
                              ));
                          // Navigate to upgrade screen
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
}
