import 'dart:async';
import 'package:flutter/material.dart';
import 'package:adminmrz/activity/activity_service.dart';
import 'package:adminmrz/activity/activity_model.dart';

const _kPrimary = Color(0xFF6366F1);
const _kAmber   = Color(0xFFF59E0B);

// Returns a human-readable "time ago" string for the given [dateTime].
String _timeAgo(DateTime dateTime) {
  final diff = DateTime.now().difference(dateTime);
  if (diff.inSeconds < 60)  return '${diff.inSeconds}s ago';
  if (diff.inMinutes < 60)  return '${diff.inMinutes}m ago';
  if (diff.inHours < 24)    return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

// Returns a suitable icon for an activity type.
IconData _iconForType(String type) {
  switch (type.toLowerCase()) {
    case 'login':           return Icons.login_rounded;
    case 'logout':          return Icons.logout_rounded;
    case 'profile_update':  return Icons.person_rounded;
    case 'photo_upload':    return Icons.photo_rounded;
    case 'match_request':   return Icons.favorite_rounded;
    case 'payment':         return Icons.payments_rounded;
    case 'document_upload': return Icons.description_rounded;
    case 'chat':            return Icons.chat_bubble_rounded;
    default:                return Icons.circle_notifications_rounded;
  }
}

class NotificationCenter extends StatefulWidget {
  /// Called when the user taps "View All Activities".
  final VoidCallback? onViewAll;

  const NotificationCenter({Key? key, this.onViewAll}) : super(key: key);

  @override
  State<NotificationCenter> createState() => _NotificationCenterState();
}

class _NotificationCenterState extends State<NotificationCenter> {
  final ActivityService _service = ActivityService();
  final GlobalKey _buttonKey = GlobalKey();

  List<UserActivity> _activities = [];
  bool _loading = false;
  bool _hasError = false;

  // IDs that have been "read" – tracked only for the current session.
  final Set<int> _readIds = {};

  Timer? _pollTimer;
  OverlayEntry? _overlayEntry;
  bool _isOpen = false;

  @override
  void initState() {
    super.initState();
    _fetchActivities();
    _pollTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      _fetchActivities();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _removeOverlay();
    super.dispose();
  }

  Future<void> _fetchActivities() async {
    setState(() {
      _loading = true;
      _hasError = false;
    });
    try {
      final response = await _service.getActivities(limit: 10, page: 1);
      if (mounted) {
        setState(() {
          _activities = response.activities;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _hasError = true;
        });
      }
    }
  }

  int get _unreadCount =>
      _activities.where((a) => !_readIds.contains(a.id)).length;

  void _markAllRead() {
    setState(() {
      for (final a in _activities) {
        _readIds.add(a.id);
      }
    });
    // Rebuild overlay so the badge and list update.
    _overlayEntry?.markNeedsBuild();
  }

  // ── Overlay management ─────────────────────────────────────────────────────

  void _toggleOverlay() {
    if (_isOpen) {
      _removeOverlay();
    } else {
      _showOverlay();
    }
  }

  void _showOverlay() {
    final overlay = Overlay.of(context);
    final renderBox =
        _buttonKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final size   = renderBox.size;
    final offset = renderBox.localToGlobal(Offset.zero);

    _overlayEntry = OverlayEntry(
      builder: (_) => _NotificationDropdown(
        offset: offset,
        buttonSize: size,
        activities: _activities,
        readIds: _readIds,
        loading: _loading,
        hasError: _hasError,
        onMarkAllRead: () {
          _markAllRead();
        },
        onViewAll: () {
          _removeOverlay();
          widget.onViewAll?.call();
        },
        onDismiss: _removeOverlay,
      ),
    );

    overlay.insert(_overlayEntry!);
    setState(() => _isOpen = true);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    if (mounted) setState(() => _isOpen = false);
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs        = Theme.of(context).colorScheme;
    final isDark    = Theme.of(context).brightness == Brightness.dark;
    final iconBg    = isDark ? const Color(0xFF263248) : const Color(0xFFF8FAFC);
    final border    = cs.outlineVariant;
    final mutedColor = cs.onSurface.withOpacity(0.45);

    return SizedBox(
      key: _buttonKey,
      width: 36,
      height: 36,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            decoration: BoxDecoration(
              color: _isOpen ? _kPrimary.withOpacity(0.12) : iconBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _isOpen ? _kPrimary.withOpacity(0.4) : border,
              ),
            ),
            child: _loading
                ? Padding(
                    padding: const EdgeInsets.all(9),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: mutedColor,
                      ),
                    ),
                  )
                : _hasError
                    ? Icon(
                        Icons.error_outline,
                        size: 18,
                        color: Colors.red.withOpacity(0.7),
                      )
                    : IconButton(
                        onPressed: _toggleOverlay,
                        icon: Icon(
                          Icons.notifications_outlined,
                          size: 18,
                          color: _isOpen ? _kPrimary : mutedColor,
                        ),
                        padding: EdgeInsets.zero,
                        tooltip: 'Notifications',
                      ),
          ),
          if (_unreadCount > 0 && !_loading)
            Positioned(
              top: -4,
              right: -4,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  color: _kAmber,
                  shape: BoxShape.circle,
                ),
                constraints:
                    const BoxConstraints(minWidth: 16, minHeight: 16),
                child: Text(
                  _unreadCount > 9 ? '9+' : '$_unreadCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Dropdown panel ──────────────────────────────────────────────────────────

class _NotificationDropdown extends StatelessWidget {
  final Offset offset;
  final Size buttonSize;
  final List<UserActivity> activities;
  final Set<int> readIds;
  final bool loading;
  final bool hasError;
  final VoidCallback onMarkAllRead;
  final VoidCallback onViewAll;
  final VoidCallback onDismiss;

  const _NotificationDropdown({
    required this.offset,
    required this.buttonSize,
    required this.activities,
    required this.readIds,
    required this.loading,
    required this.hasError,
    required this.onMarkAllRead,
    required this.onViewAll,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    const double panelWidth  = 340;
    final double top  = offset.dy + buttonSize.height + 6;
    // Align right edge of panel with right edge of button.
    final double left = offset.dx + buttonSize.width - panelWidth;

    return Stack(
      children: [
        // Dismiss barrier.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: onDismiss,
          ),
        ),
        Positioned(
          top: top,
          left: left.clamp(8, double.infinity),
          width: panelWidth,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              constraints: const BoxConstraints(maxHeight: 420),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildHeader(context),
                  const Divider(height: 1),
                  Flexible(child: _buildBody(context)),
                  const Divider(height: 1),
                  _buildFooter(context),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    final unread = activities.where((a) => !readIds.contains(a.id)).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 10),
      child: Row(
        children: [
          const Icon(Icons.notifications_rounded, size: 16, color: _kPrimary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Notifications',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          if (unread > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _kAmber.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$unread unread',
                style: const TextStyle(
                  fontSize: 10,
                  color: _kAmber,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          const SizedBox(width: 4),
          TextButton(
            onPressed: unread > 0 ? onMarkAllRead : null,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'Mark all read',
              style: TextStyle(
                fontSize: 11,
                color: unread > 0
                    ? _kPrimary
                    : Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (loading) {
      return const SizedBox(
        height: 80,
        child: Center(
          child: CircularProgressIndicator(strokeWidth: 2, color: _kPrimary),
        ),
      );
    }
    if (hasError) {
      return SizedBox(
        height: 80,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline,
                  color: Colors.red.withOpacity(0.6), size: 24),
              const SizedBox(height: 4),
              Text(
                'Failed to load notifications',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withOpacity(0.45),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (activities.isEmpty) {
      return SizedBox(
        height: 80,
        child: Center(
          child: Text(
            'No recent activity',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.45),
            ),
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: activities.length,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, indent: 48),
      itemBuilder: (context, i) => _ActivityTile(
        activity: activities[i],
        isRead: readIds.contains(activities[i].id),
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    return InkWell(
      onTap: onViewAll,
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.timeline_rounded, size: 14, color: _kPrimary),
            const SizedBox(width: 6),
            const Text(
              'View All Activities',
              style: TextStyle(
                fontSize: 12,
                color: _kPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Single activity row ─────────────────────────────────────────────────────

class _ActivityTile extends StatelessWidget {
  final UserActivity activity;
  final bool isRead;

  const _ActivityTile({required this.activity, required this.isRead});

  @override
  Widget build(BuildContext context) {
    final cs      = Theme.of(context).colorScheme;
    final bgColor = isRead
        ? Colors.transparent
        : _kPrimary.withOpacity(0.04);

    return Container(
      color: bgColor,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: _kPrimary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _iconForType(activity.activityType),
              size: 16,
              color: _kPrimary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  activity.description,
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface,
                    fontWeight: isRead ? FontWeight.w400 : FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${activity.userName}  •  ${_timeAgo(activity.createdAt)}',
                  style: TextStyle(
                    fontSize: 10,
                    color: cs.onSurface.withOpacity(0.5),
                  ),
                ),
              ],
            ),
          ),
          if (!isRead)
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.only(top: 4, left: 4),
              decoration: const BoxDecoration(
                color: _kAmber,
                shape: BoxShape.circle,
              ),
            ),
        ],
      ),
    );
  }
}
