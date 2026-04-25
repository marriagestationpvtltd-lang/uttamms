import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'activity_model.dart';
import 'activity_service.dart';
import 'package:adminmrz/adminchat/services/admin_socket_service.dart';

// ─── Design tokens (shared with dashboard) ────────────────────────────────────
const _kPrimary   = Color(0xFF6366F1);
const _kEmerald   = Color(0xFF10B981);
const _kSky       = Color(0xFF0EA5E9);
const _kAmber     = Color(0xFFF59E0B);
const _kRose      = Color(0xFFEF4444);
const _kViolet    = Color(0xFF8B5CF6);
const _kPink      = Color(0xFFEC4899);
const _kSlate100  = Color(0xFFF1F5F9);
const _kSlate400  = Color(0xFF94A3B8);

class ActivityFeedScreen extends StatefulWidget {
  const ActivityFeedScreen({super.key});

  @override
  State<ActivityFeedScreen> createState() => _ActivityFeedScreenState();
}

class _ActivityFeedScreenState extends State<ActivityFeedScreen> {
  final ActivityService _service = ActivityService();
  final AdminSocketService _socketService = AdminSocketService();
  final ScrollController _scrollController = ScrollController();

  List<UserActivity> _activities = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  String _error = '';
  int _page = 1;
  int _totalPages = 1;
  Timer? _refreshTimer;
  Timer? _socketRefreshDebounce;
  StreamSubscription<Map<String, dynamic>>? _activitySub;
  StreamSubscription<Map<String, dynamic>>? _adminActivitySub;

  // Negative counter ensures real-time synthetic IDs never collide with DB IDs.
  static int _syntheticIdCounter = -1;

  // Filter state
  String? _selectedType;    // null = All
  String _searchText = '';
  final TextEditingController _searchCtrl = TextEditingController();

  static const int _pageSize = 50;

  static const List<_FilterChip> _filterChips = [
    _FilterChip(label: 'All',      type: null,                                color: _kPrimary),
    _FilterChip(label: 'Like',     type: 'like_sent',                         color: _kRose),
    _FilterChip(label: 'Message',  type: 'message_sent',                      color: _kSky),
    _FilterChip(label: 'Call',     type: 'call_made,call_received',            color: _kEmerald),
    _FilterChip(label: 'Request',  type: 'request_sent',                      color: _kAmber),
    _FilterChip(label: 'Login',    type: 'login',                             color: _kViolet),
    _FilterChip(label: 'Package',  type: 'package_bought',                    color: _kPink),
  ];

  @override
  void initState() {
    super.initState();
    _fetchActivities(reset: true);
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) { if (mounted) _fetchActivities(reset: true, silent: true); },
    );
    _scrollController.addListener(_onScroll);
    // Subscribe to real-time activity events from the socket server.
    // Debounce rapid bursts (e.g. call_made + call_received arriving within
    // milliseconds) into a single refresh, and give the 750 ms batch worker
    // enough time to persist any pending messages before we reset the list.
    _activitySub = _socketService.onUserActivity.listen((_) {
      if (!mounted) return;
      _socketRefreshDebounce?.cancel();
      _socketRefreshDebounce = Timer(
        const Duration(milliseconds: 1500),
        () { if (mounted) _fetchActivities(reset: true, silent: true); },
      );
    });
    // Subscribe to real-time admin_activity events (full message content or
    // general activity data forwarded by the new_activity socket handler)
    _adminActivitySub = _socketService.onAdminActivity.listen((data) {
      if (!mounted) return;

      final UserActivity activity;

      if (data.containsKey('activity_type')) {
        // General activity format emitted by the new_activity → admin_activity flow
        final userId     = data['user_id']?.toString() ?? '';
        final userName   = data['user_name']?.toString() ?? 'User $userId';
        final targetId   = data['target_id'];
        final targetName = data['target_name']?.toString();
        final timestamp  = data['created_at']?.toString();
        final createdAt  = timestamp != null
            ? DateTime.tryParse(timestamp) ?? DateTime.now()
            : DateTime.now();

        activity = UserActivity(
          id:           _syntheticIdCounter--,
          userId:       int.tryParse(userId) ?? 0,
          userName:     userName,
          targetId:     targetId != null ? int.tryParse(targetId.toString()) : null,
          targetName:   targetName,
          activityType: data['activity_type']?.toString() ?? 'other',
          description:  data['description']?.toString() ?? '',
          createdAt:    createdAt,
        );
      } else {
        // Legacy message-specific format from send_message handler
        final senderId     = data['sender_id']?.toString() ?? '';
        final receiverId   = data['receiver_id']?.toString() ?? '';
        final senderName   = data['sender_name']?.toString()   ?? 'User $senderId';
        final receiverName = data['receiver_name']?.toString() ?? 'User $receiverId';
        final message      = data['message']?.toString() ?? '';
        final timestamp    = data['timestamp']?.toString();
        final createdAt    = timestamp != null
            ? DateTime.tryParse(timestamp) ?? DateTime.now()
            : DateTime.now();

        activity = UserActivity(
          id:           _syntheticIdCounter--,
          userId:       int.tryParse(senderId) ?? 0,
          userName:     senderName,
          targetId:     int.tryParse(receiverId),
          targetName:   receiverName,
          activityType: 'message_sent',
          description:  '$senderName → $receiverName: $message',
          createdAt:    createdAt,
        );
      }

      // Prepend the real-time item. When user_activity fires ~750 ms later
      // and triggers a full reset fetch, the API response will replace these
      // synthetic entries with the persisted DB records (no permanent duplicates).
      setState(() => _activities.insert(0, activity));
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _socketRefreshDebounce?.cancel();
    _activitySub?.cancel();
    _adminActivitySub?.cancel();
    _scrollController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoadingMore && _page < _totalPages) {
        _fetchActivities(reset: false);
      }
    }
  }

  Future<void> _fetchActivities({bool reset = true, bool silent = false}) async {
    if (!mounted) return;
    if (reset) {
      if (!silent) setState(() { _isLoading = true; _error = ''; });
      _page = 1;
    } else {
      if (_isLoadingMore) return;
      setState(() => _isLoadingMore = true);
    }

    try {
      final resp = await _service.getActivities(
        page:         _page,
        limit:        _pageSize,
        activityType: _selectedType,
        search:       _searchText.isEmpty ? null : _searchText,
      );
      if (!mounted) return;
      setState(() {
        _totalPages  = resp.totalPages;
        _isLoading   = false;
        _isLoadingMore = false;
        _error       = '';
        if (reset) {
          _activities = resp.activities;
        } else {
          _activities.addAll(resp.activities);
          _page++;
        }
        if (reset) _page = 2;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading     = false;
        _isLoadingMore = false;
        if (reset) _error = e.toString();
      });
    }
  }

  void _onFilterChanged(String? type) {
    setState(() => _selectedType = type);
    _fetchActivities(reset: true);
  }

  void _onSearchSubmit(String value) {
    setState(() => _searchText = value);
    _fetchActivities(reset: true);
  }

  // ─── Icon & colour per activity type ────────────────────────────────────────
  static IconData _iconFor(String type) {
    switch (type) {
      case 'like_sent':          return Icons.favorite_rounded;
      case 'like_removed':       return Icons.heart_broken_rounded;
      case 'message_sent':       return Icons.chat_bubble_rounded;
      case 'request_sent':       return Icons.send_rounded;
      case 'request_accepted':   return Icons.check_circle_rounded;
      case 'request_rejected':   return Icons.cancel_rounded;
      case 'call_made':          return Icons.call_made_rounded;
      case 'call_received':      return Icons.call_received_rounded;
      case 'video_call_made':    return Icons.videocam_rounded;
      case 'video_call_received': return Icons.video_call_rounded;
      case 'profile_viewed':     return Icons.person_search_rounded;
      case 'login':              return Icons.login_rounded;
      case 'logout':             return Icons.logout_rounded;
      case 'photo_uploaded':     return Icons.photo_camera_rounded;
      case 'package_bought':     return Icons.card_membership_rounded;
      default:                   return Icons.circle_outlined;
    }
  }

  static Color _colorFor(String type) {
    switch (type) {
      case 'like_sent':          return _kRose;
      case 'like_removed':       return _kSlate400;
      case 'message_sent':       return _kSky;
      case 'request_sent':       return _kAmber;
      case 'request_accepted':   return _kEmerald;
      case 'request_rejected':   return _kRose;
      case 'call_made':          return _kEmerald;
      case 'call_received':      return _kSky;
      case 'video_call_made':    return _kViolet;
      case 'video_call_received': return _kPrimary;
      case 'profile_viewed':     return _kViolet;
      case 'login':              return _kViolet;
      case 'logout':             return _kSlate400;
      case 'photo_uploaded':     return _kPink;
      case 'package_bought':     return _kPink;
      default:                   return _kPrimary;
    }
  }

  static String _labelFor(String type) {
    switch (type) {
      case 'like_sent':          return 'Like';
      case 'like_removed':       return 'Unlike';
      case 'message_sent':       return 'Message';
      case 'request_sent':       return 'Request';
      case 'request_accepted':   return 'Accepted';
      case 'request_rejected':   return 'Rejected';
      case 'call_made':          return 'Audio Out';
      case 'call_received':      return 'Audio In';
      case 'video_call_made':    return 'Video Out';
      case 'video_call_received': return 'Video In';
      case 'profile_viewed':     return 'Viewed';
      case 'login':              return 'Login';
      case 'logout':             return 'Logout';
      case 'photo_uploaded':     return 'Photo';
      case 'package_bought':     return 'Package';
      default:                   return type;
    }
  }
  // ─── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final cs     = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(cs, isDark),
        _buildFilterBar(cs, isDark),
        Expanded(child: _buildBody(cs, isDark)),
      ],
    );
  }

  Widget _buildHeader(ColorScheme cs, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 16),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_kPrimary, _kViolet],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.timeline_rounded, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Activity Feed',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
                Text(
                  'Real-time user activities across the platform',
                  style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.55)),
                ),
              ],
            ),
          ),
          // Search box
          SizedBox(
            width: 220,
            height: 38,
            child: TextField(
              controller: _searchCtrl,
              onSubmitted: _onSearchSubmit,
              decoration: InputDecoration(
                hintText: 'Search user or description…',
                hintStyle: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.4)),
                prefixIcon: Icon(Icons.search_rounded, size: 16, color: cs.onSurface.withOpacity(0.4)),
                suffixIcon: _searchText.isNotEmpty
                    ? GestureDetector(
                        onTap: () {
                          _searchCtrl.clear();
                          _onSearchSubmit('');
                        },
                        child: Icon(Icons.close_rounded, size: 14, color: cs.onSurface.withOpacity(0.4)),
                      )
                    : null,
                filled: true,
                fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: cs.outlineVariant),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: cs.outlineVariant),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _kPrimary),
                ),
              ),
              style: TextStyle(fontSize: 12, color: cs.onSurface),
            ),
          ),
          const SizedBox(width: 10),
          // Refresh button
          SizedBox(
            width: 38,
            height: 38,
            child: Tooltip(
              message: 'Refresh',
              child: ElevatedButton(
                onPressed: () => _fetchActivities(reset: true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kPrimary,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
                child: const Icon(Icons.refresh_rounded, size: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(ColorScheme cs, bool isDark) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _filterChips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final chip      = _filterChips[i];
          final isActive  = _selectedType == chip.type;
          return GestureDetector(
            onTap: () => _onFilterChanged(chip.type),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color:  isActive ? chip.color : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isActive ? chip.color : cs.outlineVariant,
                ),
              ),
              child: Text(
                chip.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  color: isActive ? Colors.white : cs.onSurface.withOpacity(0.7),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBody(ColorScheme cs, bool isDark) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded, size: 48, color: _kRose),
            const SizedBox(height: 12),
            Text('Failed to load activities', style: TextStyle(color: cs.onSurface)),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => _fetchActivities(reset: true),
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    if (_activities.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.timeline_rounded, size: 48, color: cs.onSurface.withOpacity(0.25)),
            const SizedBox(height: 12),
            Text(
              'No activities found',
              style: TextStyle(fontSize: 15, color: cs.onSurface.withOpacity(0.5)),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _fetchActivities(reset: true),
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.only(top: 16),
        itemCount: _activities.length + (_isLoadingMore ? 1 : 0),
        itemBuilder: (ctx, i) {
          if (i == _activities.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return _buildActivityTile(_activities[i], cs, isDark);
        },
      ),
    );
  }

  Widget _buildActivityTile(UserActivity activity, ColorScheme cs, bool isDark) {
    // Derive the display type: distinguish video calls from audio calls by
    // checking the description that the server stores (e.g. "… video call …").
    final baseType = activity.activityType;
    final isVideoCall = (baseType == 'call_made' || baseType == 'call_received') &&
        activity.description.toLowerCase().contains('video call');
    final String displayType;
    if (isVideoCall) {
      displayType = baseType == 'call_made' ? 'video_call_made' : 'video_call_received';
    } else {
      displayType = baseType;
    }

    final color  = _colorFor(displayType);
    final icon   = _iconFor(displayType);
    final label  = _labelFor(displayType);
    final timeStr = DateFormat('MMM d, HH:mm').format(activity.createdAt.toLocal());

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color:        isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border:       Border.all(color: cs.outlineVariant.withOpacity(0.6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Activity icon badge
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color:        color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 12),
          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // User name
                    Flexible(
                      child: Text(
                        activity.userName.isNotEmpty
                            ? activity.userName
                            : 'User ${activity.userId}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Type badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color:        color.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  activity.description.isNotEmpty
                      ? activity.description
                      : activity.activityType,
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface.withOpacity(0.65),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // Timestamp
          Text(
            timeStr,
            style: TextStyle(
              fontSize: 11,
              color: cs.onSurface.withOpacity(0.4),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Internal model for filter chips ─────────────────────────────────────────
class _FilterChip {
  final String  label;
  final String? type;
  final Color   color;
  const _FilterChip({required this.label, required this.type, required this.color});
}
