import 'dart:async';
import 'dart:convert';
import 'package:adminmrz/adminchat/model/MatchedProfile.dart';
import 'package:adminmrz/adminchat/services/admin_socket_service.dart';
import 'package:adminmrz/adminchat/services/MatchedProfileService.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'chat_theme.dart';
import 'chatprovider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:adminmrz/config/app_endpoints.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Static design tokens (same in both modes)
// ─────────────────────────────────────────────────────────────────────────────
const _kPrimary = Color(0xFF7B61FF);
const _kOnline = Color(0xFF22C55E);

const _kPaginationScrollThreshold = 200.0;
const _kShareHistoryPageSize = 100;
final DateTime _kEpochStart = DateTime(1970);

class ProfileSidebar extends StatefulWidget {
  final int selectedTab;
  final Function(int) onTabChange;

  const ProfileSidebar({
    Key? key,
    required this.selectedTab,
    required this.onTabChange,
  }) : super(key: key);

  @override
  _ProfileSidebarState createState() => _ProfileSidebarState();
}

class _ProfileSidebarState extends State<ProfileSidebar> {
  // ── filters & search ───────────────────────────────────────────────────────
  bool _showFilters = false;
  String _memberStatus = "All";
  String _onlineStatus = "All";
  String _sortBy = "Match %";
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";

  // ── profile view filter: 'all' | 'matched' | 'shared' ─────────────────────
  String _profileFilter = 'matched';

  // ── search debounce ───────────────────────────────────────────────────────
  Timer? _searchDebounce;

  // ── Socket-backed shared-profile tracking ─────────────────────────────────
  final AdminSocketService _socketService = AdminSocketService();
  Map<int, Map<String, dynamic>> _sharedProfilesData = {};
  Set<int> _sharedProfileIds = {};
  Map<int, DateTime> _lastShareTimestamp = {};
  int _totalShares = 0;
  int _shareHistoryRequestId = 0;
  String? _activeRoomId;
  StreamSubscription<Map<String, dynamic>>? _newMessageSub;
  StreamSubscription<Map<String, dynamic>>? _messageDeletedSub;
  StreamSubscription<Map<String, dynamic>>? _messageUnsentSub;

  // ── track which user's matches we've loaded ───────────────────────────────
  int? _lastFetchedUserId;
  int? _lastObservedChatUserId;
  DateTime? _lastFetchAttemptAt;
  static const Duration _kSameUserRetryThrottle = Duration(seconds: 3);
  bool _matchesLoaded = false;

  // ── scroll ────────────────────────────────────────────────────────────────
  final ScrollController _scrollController = ScrollController();

  // ── online status polling ─────────────────────────────────────────────────
  Timer? _onlineStatusTimer;

  // ─────────────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _scrollController.addListener(_onScroll);
    _socketService.connect();
    _newMessageSub = _socketService.onNewMessage.listen(
      _handleRealtimeShareEvent,
    );
    _messageDeletedSub = _socketService.onMessageDeleted.listen(
      _handleRealtimeShareEvent,
    );
    _messageUnsentSub = _socketService.onMessageUnsent.listen(
      _handleRealtimeShareEvent,
    );
    // Poll online status for matched profiles every 10 seconds
    _onlineStatusTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted || !_matchesLoaded) return;
      Provider.of<MatchedProfileProvider>(
        context,
        listen: false,
      ).refreshOnlineStatuses();
    });
  }

  void _onSearchChanged() {
    final query = _searchController.text;
    setState(() => _searchQuery = query);
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      Provider.of<MatchedProfileProvider>(
        context,
        listen: false,
      ).updateSearch(query);
    });
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent -
            _kPaginationScrollThreshold) {
      final provider = Provider.of<MatchedProfileProvider>(
        context,
        listen: false,
      );
      provider.fetchMoreProfiles();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    _ensureMatchesForSelectedUser(chatProvider.id);
  }

  void _ensureMatchesForSelectedUser(int? userId) {
    if (!mounted || userId == null) return;

    final matchProvider = Provider.of<MatchedProfileProvider>(
      context,
      listen: false,
    );

    final bool sameUser = userId == _lastFetchedUserId;
    if (sameUser) {
      final bool hasExistingData =
          matchProvider.ids.isNotEmpty || _sharedProfileIds.isNotEmpty;

      // If we already have data for the same user (or an in-flight fetch),
      // skip reloading. This preserves smooth scrolling and avoids duplicate
      // network requests while still allowing retry when the prior load failed.
      if (hasExistingData || matchProvider.isloading) return;

      final now = DateTime.now();
      if (_lastFetchAttemptAt != null &&
          now.difference(_lastFetchAttemptAt!) < _kSameUserRetryThrottle) {
        return;
      }
    }

    _lastFetchAttemptAt = DateTime.now();
    _lastFetchedUserId = userId;
    final roomId = AdminSocketService.chatRoomId(userId.toString());
    _activeRoomId = roomId;
    _socketService.ensureConnected().then((connected) {
      if (connected && _activeRoomId == roomId) {
        _socketService.joinRoom(roomId);
      }
    });

    setState(() {
      _matchesLoaded = true;
      _profileFilter = 'matched';
      _searchQuery = '';
      _searchController.clear();
      _sharedProfilesData = {};
      _sharedProfileIds = {};
      _lastShareTimestamp = {};
      _totalShares = 0;
    });

    matchProvider.clearData();
    _loadSharedProfilesForUser(userId.toString());
    matchProvider.fetchMatchedProfiles(userId);
    matchProvider.startPresenceListener();

    // Reset scroll position for new user's list
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    });
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchDebounce?.cancel();
    _onlineStatusTimer?.cancel();
    _newMessageSub?.cancel();
    _messageDeletedSub?.cancel();
    _messageUnsentSub?.cancel();
    Provider.of<MatchedProfileProvider>(
      context,
      listen: false,
    ).stopPresenceListener();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _loadMatches() {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    final userId = chatProvider.id;
    if (userId == null) return;
    setState(() => _matchesLoaded = true);
    Provider.of<MatchedProfileProvider>(
      context,
      listen: false,
    ).fetchMatchedProfiles(userId);
  }

  void _setProfileFilter(String filter) {
    if (filter == _profileFilter) return;
    setState(() => _profileFilter = filter);
    final provider = Provider.of<MatchedProfileProvider>(
      context,
      listen: false,
    );
    // 'shared' is client-side – no API change needed
    if (filter != 'shared') {
      provider.updateFilterType(filter);
    }
  }

  void _handleRealtimeShareEvent(Map<String, dynamic> data) {
    final roomId = data['chatRoomId']?.toString();
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    final receiverId = chatProvider.id?.toString();
    if (receiverId == null || receiverId.isEmpty) return;
    if (_activeRoomId == null || roomId != _activeRoomId) return;
    _loadSharedProfilesForUser(receiverId);
  }

  Map<String, dynamic>? _decodeProfileData(dynamic rawMessage) {
    if (rawMessage is Map<String, dynamic>) return rawMessage;
    if (rawMessage is Map) return Map<String, dynamic>.from(rawMessage);
    if (rawMessage is String && rawMessage.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawMessage);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return null;
  }

  int? _parseProfileId(Map<String, dynamic> profileData) {
    final rawId = profileData['id'];
    if (rawId is int) return rawId;
    if (rawId is num) return rawId.toInt();
    return int.tryParse(rawId?.toString() ?? '');
  }

  void _recordSharedProfile({
    required Map<int, Map<String, dynamic>> sharedData,
    required Set<int> sharedIds,
    required Map<int, DateTime> lastTs,
    required int profileId,
    required String profileName,
    required String memberId,
    required String receiverId,
    required DateTime timestamp,
  }) {
    if (!sharedData.containsKey(profileId)) {
      sharedData[profileId] = {
        'profile_name': profileName,
        'timestamp': timestamp,
        'shared_to': receiverId,
        'profile_member_id': memberId,
        'share_count': 1,
      };
      sharedIds.add(profileId);
      lastTs[profileId] = timestamp;
      return;
    }

    sharedData[profileId]!['share_count'] =
        (sharedData[profileId]!['share_count'] ?? 0) + 1;
    if (timestamp.isAfter(lastTs[profileId] ?? _kEpochStart)) {
      lastTs[profileId] = timestamp;
      sharedData[profileId]!['timestamp'] = timestamp;
    }
  }

  Future<void> _loadSharedProfilesForUser(String receiverId) async {
    if (receiverId.isEmpty) return;

    final requestId = ++_shareHistoryRequestId;
    final roomId = AdminSocketService.chatRoomId(receiverId);
    final sharedData = <int, Map<String, dynamic>>{};
    final sharedIds = <int>{};
    final lastTs = <int, DateTime>{};
    int totalShares = 0;
    int page = 1;
    bool hasMore = true;

    try {
      final connected = await _socketService.ensureConnected();
      if (!connected) throw Exception('Socket not connected');

      while (hasMore) {
        final result = await _socketService.getMessages(
          roomId,
          page: page,
          limit: _kShareHistoryPageSize,
        );
        final messages = (result['messages'] as List? ?? const []);

        for (final raw in messages) {
          if (raw is! Map) continue;
          final msg = Map<String, dynamic>.from(raw);
          if (msg['messageType']?.toString() != 'profile_card') continue;
          if (msg['senderId']?.toString() != kAdminUserId) continue;
          if (msg['receiverId']?.toString() != receiverId) continue;
          if (msg['isUnsent'] == true) continue;
          if (msg['isDeletedForSender'] == true ||
              msg['isDeletedForReceiver'] == true)
            continue;

          final profileData = _decodeProfileData(msg['message']);
          if (profileData == null) continue;
          final profileId = _parseProfileId(profileData);
          if (profileId == null) continue;

          totalShares++;
          _recordSharedProfile(
            sharedData: sharedData,
            sharedIds: sharedIds,
            lastTs: lastTs,
            profileId: profileId,
            profileName: profileData['name']?.toString() ?? '',
            memberId: profileData['Member ID']?.toString() ?? '',
            receiverId: receiverId,
            timestamp:
                AdminSocketService.parseTimestamp(msg['timestamp']) ??
                _kEpochStart,
          );
        }

        hasMore = result['hasMore'] == true;
        page++;
      }

      if (!mounted || requestId != _shareHistoryRequestId) return;
      setState(() {
        _sharedProfilesData = sharedData;
        _sharedProfileIds = sharedIds;
        _lastShareTimestamp = lastTs;
        _totalShares = totalShares;
      });
    } catch (e) {
      if (!mounted || requestId != _shareHistoryRequestId) return;
      debugPrint('Error loading shared profiles: $e');
      setState(() {
        _sharedProfilesData = {};
        _sharedProfileIds = {};
        _lastShareTimestamp = {};
        _totalShares = 0;
      });
    }
  }

  String _toggleFilter(String current, String target) =>
      current == target ? 'All' : target;

  List<MatchedProfile> _filterProfiles(MatchedProfileProvider p) {
    return _filterProfilesWith(
      p,
      memberStatus: _memberStatus,
      onlineStatus: _onlineStatus,
      profileFilter: _profileFilter,
    );
  }

  List<MatchedProfile> _filterProfilesWith(
    MatchedProfileProvider p, {
    required String memberStatus,
    required String onlineStatus,
    required String profileFilter,
  }) {
    final List<MatchedProfile> out = [];
    final profiles = p.profiles;
    if (profiles.isEmpty) return out;
    for (final profile in profiles) {
      // Member status filter (client-side – based on loaded data)
      if (memberStatus == "Paid" && !profile.isPaid) continue;
      if (memberStatus == "Free" && profile.isPaid) continue;
      if (onlineStatus == "Online" && !profile.isOnline) continue;
      if (onlineStatus == "Offline" && profile.isOnline) continue;
      // "Share Profile Count" view: only profiles that have been shared
      if (profileFilter == 'shared' && !_sharedProfileIds.contains(profile.id))
        continue;
      out.add(profile);
    }
    return out;
  }

  List<MatchedProfile> _sortProfiles(List<MatchedProfile> profiles) {
    if (profiles.isEmpty) return const [];
    final sorted = profiles.toList();
    switch (_sortBy) {
      case "Match %":
        sorted.sort(
          (a, b) => b.matchingPercentage.compareTo(a.matchingPercentage),
        );
        break;
      case "Name":
        sorted.sort(
          (a, b) => '${a.firstName} ${a.lastName}'.compareTo(
            '${b.firstName} ${b.lastName}',
          ),
        );
        break;
      case "Age":
        sorted.sort((a, b) => a.age.compareTo(b.age));
        break;
      case "Online First":
        sorted.sort((a, b) {
          if (a.isOnline && !b.isOnline) return -1;
          if (!a.isOnline && b.isOnline) return 1;
          return b.matchingPercentage.compareTo(a.matchingPercentage);
        });
        break;
      case "Recently Shared":
        sorted.sort((a, b) {
          final aShared = _sharedProfileIds.contains(a.id);
          final bShared = _sharedProfileIds.contains(b.id);
          if (aShared && !bShared) return -1;
          if (!aShared && bShared) return 1;
          if (aShared && bShared) {
            final aTs = _lastShareTimestamp[a.id] ?? _kEpochStart;
            final bTs = _lastShareTimestamp[b.id] ?? _kEpochStart;
            return bTs.compareTo(aTs);
          }
          return b.matchingPercentage.compareTo(a.matchingPercentage);
        });
        break;
    }
    return sorted;
  }

  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _sendMessage(
    String matched,
    String memberid,
    String gender,
    String occupation,
    String education,
    String marit,
    String age,
    int profileId,
    String firstName,
    String lastName,
    String? profilePicture,
    String country,
  ) async {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    try {
      final receiverId = chatProvider.id?.toString();
      if (receiverId == null || receiverId.isEmpty) {
        throw Exception('No receiver selected');
      }
      final connected = await _socketService.ensureConnected();
      if (!connected) throw Exception('Socket not connected');

      final profileData = {
        // Unified fields
        'userId': profileId.toString(),
        'memberId': memberid,
        'firstName': firstName,
        'lastName': lastName,
        'profileImage': profilePicture ?? '',
        'age': age,
        'gender': gender,
        'location': country,
        'occupation': occupation,
        'education': education,
        'maritalStatus': marit,
        'matchPercent': double.tryParse(matched)?.round() ?? 0,
        'isPremium': chatProvider.ispaid,
        'isProfileVerified': false,
        'canViewPhoto': true,
        'sharedBy': 'admin',
        // Backward-compat aliases
        'id': profileId,
        'name': lastName,
        'first': firstName,
        'last': lastName,
        'Member ID': memberid,
        'country': country,
        'marit': marit,
        'is_paid': chatProvider.ispaid,
        'shouldBlurPhoto': false,
      };

      _socketService.sendMessage(
        chatRoomId: AdminSocketService.chatRoomId(receiverId),
        receiverId: receiverId,
        message: jsonEncode(profileData),
        messageType: 'profile_card',
        messageId:
            'profile_${DateTime.now().millisecondsSinceEpoch}_$kAdminUserId',
        receiverName: chatProvider.namee,
        receiverImage: chatProvider.profilePicture,
      );

      _recordSharedProfile(
        sharedData: _sharedProfilesData,
        sharedIds: _sharedProfileIds,
        lastTs: _lastShareTimestamp,
        profileId: profileId,
        profileName: '$firstName $lastName',
        memberId: memberid,
        receiverId: receiverId,
        timestamp: DateTime.now(),
      );
      if (mounted) {
        setState(() {
          _totalShares += 1;
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile shared successfully'),
            duration: Duration(seconds: 2),
            backgroundColor: _kOnline,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to share profile: $e'),
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _timeAgo(DateTime ts) {
    final d = DateTime.now().difference(ts);
    if (d.inMinutes < 1) return 'now';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    if (d.inDays < 7) return '${d.inDays}d';
    return '${(d.inDays / 7).floor()}w';
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  BUILD
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final chatProvider = Provider.of<ChatProvider>(context);
    final c = ChatColors.of(context);

    if (chatProvider.id != _lastObservedChatUserId) {
      final pendingUserId = chatProvider.id;
      _lastObservedChatUserId = pendingUserId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _ensureMatchesForSelectedUser(pendingUserId);
      });
    }

    return Container(
      width: 300,
      color: c.cardBg,
      child: Column(
        children: [
          _buildHeader(chatProvider),
          _buildProfileFilterButtons(),
          _buildSearchBar(),
          _buildFilterRow(),
          if (_showFilters) _buildFilterPanel(),
          _buildStatsRow(),
          Divider(height: 1, color: c.border),
          Expanded(child: _buildProfileList()),
        ],
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────────────────
  Widget _buildHeader(ChatProvider chat) {
    final c = ChatColors.of(context);
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: c.cardBg,
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: c.primaryLight,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.favorite, color: _kPrimary, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Match Profiles',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: c.text,
                  ),
                ),
                if (chat.namee != null)
                  Text(
                    'for ${chat.namee}',
                    style: TextStyle(fontSize: 10, color: c.muted),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          Consumer<MatchedProfileProvider>(
            builder: (_, p, __) {
              if (_matchesLoaded && !p.isloading && chat.id != null) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: c.primaryLight,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${p.ids.length}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _kPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: _loadMatches,
                      child: Tooltip(
                        message: 'Refresh matches',
                        child: Icon(Icons.refresh, size: 16, color: c.muted),
                      ),
                    ),
                  ],
                );
              }
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: c.primaryLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${p.ids.length}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _kPrimary,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ── Profile view filter buttons: All / Match / Share Profile Count ─────────
  Widget _buildProfileFilterButtons() {
    final c = ChatColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: c.cardBg,
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Consumer<MatchedProfileProvider>(
        builder: (_, provider, __) {
          final sharedCount = _sharedProfileIds.length;
          return Row(
            children: [
              _profileFilterBtn(
                label: 'All',
                icon: Icons.grid_view_rounded,
                filter: 'all',
                badgeCount: null,
                c: c,
              ),
              const SizedBox(width: 5),
              _profileFilterBtn(
                label: 'Match',
                icon: Icons.favorite_rounded,
                filter: 'matched',
                badgeCount:
                    _profileFilter == 'matched' && provider.totalCount > 0
                    ? provider.totalCount
                    : null,
                c: c,
              ),
              const SizedBox(width: 5),
              _profileFilterBtn(
                label: 'Shared',
                icon: Icons.send_rounded,
                filter: 'shared',
                badgeCount: sharedCount > 0 ? sharedCount : null,
                c: c,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _profileFilterBtn({
    required String label,
    required IconData icon,
    required String filter,
    required int? badgeCount,
    required ChatColors c,
  }) {
    final active = _profileFilter == filter;
    return Expanded(
      child: GestureDetector(
        onTap: () => _setProfileFilter(filter),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? _kPrimary : c.searchFill,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active ? _kPrimary : c.border,
              width: active ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 11, color: active ? Colors.white : c.muted),
              const SizedBox(width: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: active ? Colors.white : c.muted,
                ),
              ),
              if (badgeCount != null) ...[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: active
                        ? Colors.white.withOpacity(0.25)
                        : c.primaryLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$badgeCount',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: active ? Colors.white : _kPrimary,
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

  // ── Search ──────────────────────────────────────────────────────────────
  Widget _buildSearchBar() {
    final c = ChatColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
      child: SizedBox(
        height: 36,
        child: TextField(
          controller: _searchController,
          style: TextStyle(fontSize: 12, color: c.text),
          cursorColor: _kPrimary,
          decoration: InputDecoration(
            hintText: 'Search name, ID, phone…',
            hintStyle: TextStyle(fontSize: 11, color: c.muted),
            prefixIcon: Icon(Icons.search, size: 16, color: c.muted),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: Icon(Icons.clear, size: 14, color: c.muted),
                    padding: EdgeInsets.zero,
                    onPressed: () {
                      _searchController.clear();
                      Provider.of<MatchedProfileProvider>(
                        context,
                        listen: false,
                      ).updateSearch('');
                    },
                  )
                : null,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide: BorderSide(color: c.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide: BorderSide(color: c.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide: const BorderSide(color: _kPrimary, width: 1.5),
            ),
            filled: true,
            fillColor: c.searchFill,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 0,
            ),
            isDense: true,
          ),
        ),
      ),
    );
  }

  // ── Filter row (chips) ───────────────────────────────────────────────────
  Widget _buildFilterRow() {
    final c = ChatColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 4),
      child: Row(
        children: [
          _filterChip(
            'Paid',
            _memberStatus == 'Paid',
            () => setState(
              () => _memberStatus = _toggleFilter(_memberStatus, 'Paid'),
            ),
          ),
          const SizedBox(width: 4),
          _filterChip(
            'Online',
            _onlineStatus == 'Online',
            () => setState(
              () => _onlineStatus = _toggleFilter(_onlineStatus, 'Online'),
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => setState(() => _showFilters = !_showFilters),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _showFilters ? c.primaryLight : c.searchFill,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _showFilters ? _kPrimary : c.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.tune,
                    size: 12,
                    color: _showFilters ? _kPrimary : c.muted,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    'Sort',
                    style: TextStyle(
                      fontSize: 10,
                      color: _showFilters ? _kPrimary : c.muted,
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

  Widget _filterChip(String label, bool active, VoidCallback onTap) {
    final c = ChatColors.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: active ? c.primaryLight : c.searchFill,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: active ? _kPrimary : c.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: active ? _kPrimary : c.muted,
          ),
        ),
      ),
    );
  }

  // ── Collapsible sort/filter panel ────────────────────────────────────────
  Widget _buildFilterPanel() {
    final c = ChatColors.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: c.searchFill,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sort By',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: c.muted,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children:
                ['Match %', 'Name', 'Age', 'Online First', 'Recently Shared']
                    .map(
                      (s) => GestureDetector(
                        onTap: () => setState(() => _sortBy = s),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _sortBy == s ? _kPrimary : c.cardBg,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _sortBy == s ? _kPrimary : c.border,
                            ),
                          ),
                          child: Text(
                            s,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: _sortBy == s ? Colors.white : c.muted,
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
          ),
        ],
      ),
    );
  }

  // ── Stats row ────────────────────────────────────────────────────────────
  Widget _buildStatsRow() {
    final c = ChatColors.of(context);
    final statsBg = c.isDark
        ? const Color(0xFF052E16)
        : const Color(0xFFF0FDF4);
    final statsBorder = c.isDark
        ? const Color(0xFF14532D)
        : const Color(0xFFBBF7D0);
    final unique = _sharedProfileIds.length;
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 4, 10, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: statsBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: statsBorder),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _statItem(
            Icons.share_outlined,
            '$_totalShares',
            'Total Shares',
            const Color(0xFF16A34A),
          ),
          Container(width: 1, height: 24, color: statsBorder),
          _statItem(
            Icons.people_outline,
            '$unique',
            'Unique Profiles',
            const Color(0xFF0284C7),
          ),
        ],
      ),
    );
  }

  Widget _statItem(IconData icon, String value, String label, Color color) {
    final c = ChatColors.of(context);
    return Column(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(height: 1),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        Text(label, style: TextStyle(fontSize: 8, color: c.muted)),
      ],
    );
  }

  // ── Profile list ─────────────────────────────────────────────────────────
  Widget _buildProfileList() {
    return Consumer<MatchedProfileProvider>(
      builder: (context, provider, _) {
        // ── No user selected ──────────────────────────────────────────
        final chatProvider = Provider.of<ChatProvider>(context, listen: false);
        if (chatProvider.id == null) {
          return _buildEmptyState(
            icon: Icons.chat_bubble_outline,
            title: 'Select a conversation',
            subtitle:
                'Choose a user from the left panel to view matching profiles',
          );
        }

        // ── If profiles are already available, show them immediately ────
        // (do NOT gate on _matchesLoaded – the flag may lag behind the data
        //  when the Consumer rebuilds before a setState propagates)
        final profiles = provider.profiles;
        if (profiles.isNotEmpty) {
          final visibleProfiles = _sortProfiles(_filterProfiles(provider));

          if (visibleProfiles.isEmpty) {
            final fallbackProfiles = _sortProfiles(
              _filterProfilesWith(
                provider,
                memberStatus: 'All',
                onlineStatus: 'All',
                profileFilter: 'matched',
              ),
            );

            final hadClientSideRestrictions =
                _memberStatus != 'All' ||
                _onlineStatus != 'All' ||
                _profileFilter == 'shared';

            // If local chip filters hide everything while API data is present,
            // recover automatically so the sidebar does not appear broken.
            if (hadClientSideRestrictions && fallbackProfiles.isNotEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                setState(() {
                  _memberStatus = 'All';
                  _onlineStatus = 'All';
                  _profileFilter = 'matched';
                });
              });
              return _buildProfilesListView(provider, fallbackProfiles);
            }

            return _buildEmptyState(
              icon: Icons.search_off,
              title: 'No results',
              subtitle: 'Try adjusting your search or filters',
              showClear: true,
            );
          }

          // ── Profile cards ──────────────────────────────────────────
          return _buildProfilesListView(provider, visibleProfiles);
        }

        // ── Loading skeleton (first load only, before data exists) ────
        if (provider.isloading) {
          return _buildSkeletonLoader();
        }

        // ── Show Match button (not yet triggered) ──────────────────────
        if (!_matchesLoaded) {
          return _buildShowMatchButton(chatProvider);
        }

        // ── No matches found for this user ────────────────────────────
        return _buildEmptyState(
          icon: Icons.favorite_border,
          title: 'No matches yet',
          subtitle: 'No matching profiles found for this user',
          showRefetch: true,
        );
      },
    );
  }

  Widget _buildProfilesListView(
    MatchedProfileProvider provider,
    List<MatchedProfile> profiles,
  ) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.only(top: 6, bottom: 16),
      itemCount:
          profiles.length +
          (provider.hasMore || provider.isLoadingMore ? 1 : 0),
      cacheExtent: 300,
      physics: const ClampingScrollPhysics(),
      itemBuilder: (context, i) {
        if (i == profiles.length) {
          return _buildPaginationFooter(provider);
        }
        final profile = profiles[i];
        final profileId = profile.id;
        final isPaid = profile.isPaid;
        final isOnline = profile.isOnline;
        final isShared = _sharedProfileIds.contains(profileId);
        final shareCount = _sharedProfilesData[profileId]?['share_count'] ?? 0;
        final lastShareTs = _lastShareTimestamp[profileId];
        final pic = profile.profilePicture.isNotEmpty
            ? profile.profilePicture
            : null;
        final matchPct = profile.matchingPercentage;
        final fullName = '${profile.firstName} ${profile.lastName}';

        return _ProfileCard(
          key: ValueKey(profileId),
          profileId: profileId,
          fullName: fullName,
          firstName: profile.firstName,
          lastName: profile.lastName,
          memberid: profile.memberid,
          occupation: profile.occupation,
          age: profile.age,
          gender: profile.gender,
          matchPct: matchPct,
          isPaid: isPaid,
          isOnline: isOnline,
          isShared: isShared,
          shareCount: shareCount,
          lastShareTs: lastShareTs,
          profilePicture: pic,
          onShare: () => _sendMessage(
            matchPct.toString(),
            profile.memberid,
            profile.gender,
            profile.occupation,
            profile.education,
            profile.marit,
            profile.age.toString(),
            profileId,
            profile.firstName,
            profile.lastName,
            pic,
            profile.country,
          ),
          timeAgo: _timeAgo,
        );
      },
    );
  }

  // ── Show Match button ────────────────────────────────────────────────────
  Widget _buildShowMatchButton(ChatProvider chat) {
    final c = ChatColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: c.primaryLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.manage_search_rounded,
                size: 30,
                color: _kPrimary,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              chat.namee != null
                  ? '${chat.namee} को म्याच हेर्नुहोस्'
                  : 'Match profiles',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: c.text,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'यस युजरसँग मिल्दो प्रोफाइलहरू लोड गर्न तलको बटन थिच्नुहोस्',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: c.muted, height: 1.5),
            ),
            const SizedBox(height: 18),
            GestureDetector(
              onTap: _loadMatches,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF7B61FF), Color(0xFF5B41CF)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: _kPrimary.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.favorite, size: 14, color: Colors.white),
                    SizedBox(width: 6),
                    Text(
                      'Show Match',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 0.3,
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
  }

  // ── Pagination footer ────────────────────────────────────────────────────
  Widget _buildPaginationFooter(MatchedProfileProvider provider) {
    final c = ChatColors.of(context);
    if (provider.isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(_kPrimary),
            ),
          ),
        ),
      );
    }
    if (provider.hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: TextButton.icon(
            onPressed: provider.fetchMoreProfiles,
            icon: const Icon(Icons.expand_more, size: 16, color: _kPrimary),
            label: const Text(
              'Load more',
              style: TextStyle(fontSize: 11, color: _kPrimary),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Text(
          provider.totalCount > 0
              ? 'Showing ${provider.ids.length} of ${provider.totalCount}'
              : provider.ids.isEmpty
              ? 'No profiles found'
              : 'All ${provider.ids.length} profiles shown',
          style: TextStyle(fontSize: 10, color: c.muted),
        ),
      ),
    );
  }

  // ── Skeleton loader ───────────────────────────────────────────────────────
  Widget _buildSkeletonLoader() {
    return ListView.builder(
      padding: const EdgeInsets.only(top: 6),
      itemCount: 6,
      physics: const NeverScrollableScrollPhysics(),
      itemBuilder: (_, __) => const _SkeletonCard(),
    );
  }

  // ── Empty state ───────────────────────────────────────────────────────────
  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
    bool showClear = false,
    bool showRefetch = false,
  }) {
    final c = ChatColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: c.primaryLight,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 30, color: _kPrimary),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: c.text,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: c.muted, height: 1.5),
            ),
            if (showClear) ...[
              const SizedBox(height: 12),
              TextButton(
                onPressed: () {
                  setState(() {
                    _memberStatus = 'All';
                    _onlineStatus = 'All';
                    _sortBy = 'Match %';
                    _profileFilter = 'matched';
                  });
                  _searchController.clear();
                  Provider.of<MatchedProfileProvider>(
                    context,
                    listen: false,
                  ).updateSearch('');
                },
                style: TextButton.styleFrom(foregroundColor: _kPrimary),
                child: const Text(
                  'Clear filters',
                  style: TextStyle(fontSize: 11),
                ),
              ),
            ],
            if (showRefetch) ...[
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: _loadMatches,
                icon: const Icon(Icons.refresh, size: 14),
                label: const Text('Retry', style: TextStyle(fontSize: 11)),
                style: TextButton.styleFrom(foregroundColor: _kPrimary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Profile Card widget (extracted for performance via const constructor)
// ─────────────────────────────────────────────────────────────────────────────
class _ProfileCard extends StatelessWidget {
  final int profileId;
  final String fullName;
  final String firstName;
  final String lastName;
  final String memberid;
  final String occupation;
  final int age;
  final String gender;
  final double matchPct;
  final bool isPaid;
  final bool isOnline;
  final bool isShared;
  final int shareCount;
  final DateTime? lastShareTs;
  final String? profilePicture;
  final VoidCallback onShare;
  final String Function(DateTime) timeAgo;

  const _ProfileCard({
    Key? key,
    required this.profileId,
    required this.fullName,
    required this.firstName,
    required this.lastName,
    required this.memberid,
    required this.occupation,
    required this.age,
    required this.gender,
    required this.matchPct,
    required this.isPaid,
    required this.isOnline,
    required this.isShared,
    required this.shareCount,
    required this.lastShareTs,
    required this.profilePicture,
    required this.onShare,
    required this.timeAgo,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final c = ChatColors.of(context);
    final hasPic = profilePicture != null && profilePicture!.isNotEmpty;
    final safeFullName = fullName.trim().isNotEmpty
        ? fullName.trim()
        : '${firstName.trim()} ${lastName.trim()}'.trim().isNotEmpty
        ? '${firstName.trim()} ${lastName.trim()}'.trim()
        : memberid.trim().isNotEmpty
        ? memberid.trim()
        : 'Profile #$profileId';
    final subtitleBits = <String>[
      if (memberid.trim().isNotEmpty) memberid.trim(),
      if (occupation.trim().isNotEmpty) occupation.trim(),
      if (age > 0) '${age}y',
      if (gender.trim().isNotEmpty) gender.trim(),
    ];
    final matchColor = matchPct >= 70
        ? const Color(0xFF16A34A)
        : matchPct >= 50
        ? _kPrimary
        : const Color(0xFF64748B);

    // Dark-mode aware contextual colors
    final sharedBadgeBg = c.isDark
        ? const Color(0xFF052E16)
        : const Color(0xFFF0FDF4);
    final sharedBadgeBorder = c.isDark
        ? const Color(0xFF14532D)
        : const Color(0xFFBBF7D0);
    final freeBadgeBg = c.isDark
        ? const Color(0xFF0C1A2E)
        : const Color(0xFFEFF6FF);
    final freeBadgeText = c.isDark
        ? const Color(0xFF93C5FD)
        : const Color(0xFF2563EB);
    final offlineDot = c.isDark
        ? const Color(0xFF4A5568)
        : const Color(0xFFCBD5E1);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border(
          left: BorderSide(
            color: isShared ? _kOnline : Colors.transparent,
            width: 3,
          ),
          right: BorderSide(color: c.border),
          top: BorderSide(color: c.border),
          bottom: BorderSide(color: c.border),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: c.searchFill,
                      backgroundImage: hasPic
                          ? NetworkImage(profilePicture!)
                          : null,
                      child: !hasPic
                          ? Text(
                              safeFullName.characters.first.toUpperCase(),
                              style: TextStyle(
                                color: c.text,
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            )
                          : null,
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: isOnline ? _kOnline : offlineDot,
                          shape: BoxShape.circle,
                          border: Border.all(color: c.cardBg, width: 1.5),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              safeFullName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: c.text,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: matchColor.withOpacity(0.14),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${matchPct.toStringAsFixed(0)}%',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: matchColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitleBits.isNotEmpty
                            ? subtitleBits.join(' • ')
                            : 'Matched profile available',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          height: 1.35,
                          color: c.muted,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: isPaid ? c.primaryLight : freeBadgeBg,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              isPaid ? 'Paid Member' : 'Free Member',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: isPaid ? _kPrimary : freeBadgeText,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: (isOnline ? _kOnline : offlineDot)
                                  .withOpacity(0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              isOnline ? 'Online' : 'Offline',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: isOnline ? _kOnline : c.muted,
                              ),
                            ),
                          ),
                          if (isShared)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: sharedBadgeBg,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: sharedBadgeBorder),
                              ),
                              child: Text(
                                lastShareTs != null
                                    ? 'Shared ×$shareCount • ${timeAgo(lastShareTs!)}'
                                    : 'Shared ×$shareCount',
                                style: const TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF16A34A),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => launchUrl(
                      Uri.parse('$kAdminApiBaseUrl/profile.php?id=$profileId'),
                      mode: LaunchMode.externalApplication,
                    ),
                    icon: const Icon(Icons.open_in_new_rounded, size: 14),
                    label: const Text(
                      'View Profile',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _kPrimary,
                      side: const BorderSide(color: _kPrimary),
                      padding: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 10,
                      ),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: isShared ? null : onShare,
                  icon: Icon(
                    isShared ? Icons.check : Icons.send_outlined,
                    size: 14,
                  ),
                  label: Text(
                    isShared ? 'Sent' : 'Share',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isShared ? sharedBadgeBg : _kPrimary,
                    foregroundColor: isShared ? _kOnline : Colors.white,
                    disabledBackgroundColor: sharedBadgeBg,
                    disabledForegroundColor: _kOnline,
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 12,
                    ),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
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
}

// ─────────────────────────────────────────────────────────────────────────────
//  Skeleton loader card
// ─────────────────────────────────────────────────────────────────────────────
class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final c = ChatColors.of(context);
    final shimmerColor = c.isDark
        ? const Color(0xFF2A3540)
        : const Color(0xFFEEF2F7);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          // Avatar skeleton
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: c.searchFill,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _shimmerBox(120, 10, shimmerColor),
                const SizedBox(height: 6),
                _shimmerBox(80, 8, shimmerColor),
                const SizedBox(height: 6),
                _shimmerBox(160, 8, shimmerColor),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _shimmerBox(double w, double h, Color color) => Container(
    width: w,
    height: h,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(4),
    ),
  );
}
