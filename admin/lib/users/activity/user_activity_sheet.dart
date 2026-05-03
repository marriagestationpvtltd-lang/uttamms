import 'package:flutter/material.dart';
import 'activity_detail_model.dart';
import 'activity_detail_service.dart';

// ─── Colour palette (matches userscreen.dart constants) ──────────────────────
const _kPrimary = Color(0xFF6366F1);
const _kPrimaryDark = Color(0xFF4F46E5);
const _kViolet = Color(0xFF8B5CF6);
const _kEmerald = Color(0xFF10B981);
const _kAmber = Color(0xFFF59E0B);
const _kRose = Color(0xFFEF4444);
const _kSky = Color(0xFF0EA5E9);

/// Opens a modal bottom sheet showing per-section activity detail
/// for [userId] / [userName].
///
/// [initialSection] controls which tab is shown first.
void showUserActivitySheet(
  BuildContext context, {
  required int userId,
  required String userName,
  ActivitySection initialSection = ActivitySection.requestsSent,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _UserActivitySheet(
      userId: userId,
      userName: userName,
      initialSection: initialSection,
    ),
  );
}

// ─── Private sheet widget ─────────────────────────────────────────────────────
class _UserActivitySheet extends StatefulWidget {
  final int userId;
  final String userName;
  final ActivitySection initialSection;

  const _UserActivitySheet({
    required this.userId,
    required this.userName,
    required this.initialSection,
  });

  @override
  State<_UserActivitySheet> createState() => _UserActivitySheetState();
}

class _UserActivitySheetState extends State<_UserActivitySheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _service = ActivityDetailService();

  // Per-section state
  final _pages = <ActivitySection, _SectionState>{};

  static const _sections = ActivitySection.values;

  @override
  void initState() {
    super.initState();
    final initIndex = _sections.indexOf(widget.initialSection);
    _tabs = TabController(
      length: _sections.length,
      vsync: this,
      initialIndex: initIndex < 0 ? 0 : initIndex,
    );
    _tabs.addListener(_onTabChanged);
    _loadSection(_sections[_tabs.index]);
  }

  @override
  void dispose() {
    _tabs.removeListener(_onTabChanged);
    _tabs.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (!_tabs.indexIsChanging) return;
    final section = _sections[_tabs.index];
    if (_pages[section] == null) _loadSection(section);
  }

  Future<void> _loadSection(
    ActivitySection section, {
    bool reset = false,
  }) async {
    final current = _pages[section];
    if (current?.loading == true) return;
    if (!reset && current?.page != null && !current!.hasMore) return;

    final page = reset ? 1 : (current?.page ?? 0) + 1;

    setState(() {
      _pages[section] = (_pages[section] ?? _SectionState()).copyWith(
        loading: true,
      );
    });

    final result = await _service.fetchSection(
      userId: widget.userId,
      section: section,
      page: page,
    );

    if (!mounted) return;
    setState(() {
      final prev = _pages[section] ?? _SectionState();
      final items = (reset || page == 1)
          ? result.items
          : [...prev.items, ...result.items];
      _pages[section] = _SectionState(
        items: items,
        total: result.total,
        page: result.page,
        totalPages: result.totalPages,
        loading: false,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0F172A) : Colors.white;

    return DraggableScrollableSheet(
      initialChildSize: 0.82,
      minChildSize: 0.45,
      maxChildSize: 0.97,
      builder: (ctx, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.14),
              blurRadius: 24,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          children: [
            // ── Drag handle ──────────────────────────────────────────────
            const SizedBox(height: 10),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // ── Header ───────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [_kPrimaryDark, _kViolet],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: const Icon(
                      Icons.timeline_outlined,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Activity Detail',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            color: _kPrimaryDark,
                          ),
                        ),
                        Text(
                          widget.userName,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? Colors.grey.shade400
                                : Colors.grey.shade600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                    color: isDark ? Colors.white60 : Colors.grey.shade600,
                    iconSize: 20,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // ── Tab bar ──────────────────────────────────────────────────
            _buildTabBar(isDark),
            const Divider(height: 1),

            // ── Tab views ────────────────────────────────────────────────
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: _sections.map((s) {
                  return _SectionView(
                    section: s,
                    state: _pages[s] ?? _SectionState(),
                    scrollController: scrollCtrl,
                    onLoadMore: () => _loadSection(s),
                    onRefresh: () => _loadSection(s, reset: true),
                    isDark: isDark,
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabBar(bool isDark) {
    return TabBar(
      controller: _tabs,
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      labelColor: _kPrimary,
      unselectedLabelColor: isDark
          ? Colors.grey.shade400
          : Colors.grey.shade600,
      indicatorColor: _kPrimary,
      indicatorWeight: 2.5,
      labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      unselectedLabelStyle: const TextStyle(fontSize: 12),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      tabs: _sections.map((s) {
        final state = _pages[s];
        final count = state?.total;
        return Tab(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_sectionIcon(s), size: 14),
              const SizedBox(width: 5),
              Text(s.label),
              if (count != null && count > 0) ...[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: _kPrimary.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    count > 999 ? '999+' : '$count',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: _kPrimary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ─── Per-section list view ────────────────────────────────────────────────────
class _SectionView extends StatelessWidget {
  final ActivitySection section;
  final _SectionState state;
  final ScrollController scrollController;
  final VoidCallback onLoadMore;
  final Future<void> Function() onRefresh;
  final bool isDark;

  const _SectionView({
    required this.section,
    required this.state,
    required this.scrollController,
    required this.onLoadMore,
    required this.onRefresh,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    if (state.items.isEmpty && state.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.items.isEmpty) {
      return _buildEmpty();
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n is ScrollEndNotification &&
            n.metrics.pixels >= n.metrics.maxScrollExtent - 200) {
          if (state.hasMore) onLoadMore();
        }
        return false;
      },
      child: RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView.separated(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          itemCount: state.items.length + (state.hasMore ? 1 : 0),
          separatorBuilder: (_, __) => const SizedBox(height: 6),
          itemBuilder: (ctx, i) {
            if (i == state.items.length) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              );
            }
            return _ItemTile(
              item: state.items[i],
              section: section,
              isDark: isDark,
            );
          },
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(_sectionIcon(section), size: 52, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(
            'No ${section.label.toLowerCase()} activity yet',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }
}

// ─── Single activity row ──────────────────────────────────────────────────────
class _ItemTile extends StatelessWidget {
  final ActivityDetailItem item;
  final ActivitySection section;
  final bool isDark;

  const _ItemTile({
    required this.item,
    required this.section,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final Color accent = _sectionAccent(section, item);
    final String dateStr = _fmtDate(item.date);
    final String other = item.otherUserName?.isNotEmpty == true
        ? item.otherUserName!
        : (item.otherUserId != null ? 'User #${item.otherUserId}' : '—');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C2339) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.07) : Colors.grey.shade200,
        ),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar/Icon
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                other.isNotEmpty ? other[0].toUpperCase() : '?',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: accent,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Other user name + badge
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        other,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: isDark ? Colors.white : Colors.grey.shade900,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    _buildBadge(accent),
                  ],
                ),
                const SizedBox(height: 3),
                // Description
                Text(
                  item.description,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Date
          Text(
            dateStr,
            style: TextStyle(
              fontSize: 10,
              color: isDark ? Colors.grey.shade500 : Colors.grey.shade400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBadge(Color accent) {
    String? text;
    Color? color;

    if (item.status != null) {
      text = item.status!;
      color = switch (item.status) {
        'accepted' => _kEmerald,
        'rejected' => _kRose,
        'pending' => _kAmber,
        _ => Colors.grey,
      };
    } else if (item.callType != null) {
      text = item.callType == 'call_made' ? 'Outgoing' : 'Incoming';
      color = item.callType == 'call_made' ? _kSky : _kViolet;
    } else if (item.likeAction != null) {
      text = item.likeAction == 'like_sent' ? '♥ Liked' : '♡ Unliked';
      color = item.likeAction == 'like_sent' ? _kRose : Colors.grey;
    } else if (item.requestType != null) {
      text = item.requestType;
      color = _kPrimary;
    }

    if (text == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color!.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  String _fmtDate(DateTime dt) {
    if (dt.year == 0) return '';
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return 'Today $h:$m';
    }
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${dt.day} ${months[dt.month - 1]}\n${dt.year}';
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────
IconData _sectionIcon(ActivitySection s) {
  switch (s) {
    case ActivitySection.requestsSent:
      return Icons.send_rounded;
    case ActivitySection.requestsReceived:
      return Icons.inbox_outlined;
    case ActivitySection.chats:
      return Icons.chat_bubble_outline;
    case ActivitySection.calls:
      return Icons.call_outlined;
    case ActivitySection.likes:
      return Icons.favorite_outline;
    case ActivitySection.profileViews:
      return Icons.visibility_outlined;
    case ActivitySection.logins:
      return Icons.login_rounded;
  }
}

Color _sectionAccent(ActivitySection section, ActivityDetailItem item) {
  switch (section) {
    case ActivitySection.requestsSent:
    case ActivitySection.requestsReceived:
      return switch (item.status) {
        'accepted' => _kEmerald,
        'rejected' => _kRose,
        _ => _kAmber,
      };
    case ActivitySection.chats:
      return _kSky;
    case ActivitySection.calls:
      return item.callType == 'call_made' ? _kSky : _kViolet;
    case ActivitySection.likes:
      return item.likeAction == 'like_sent' ? _kRose : Colors.grey;
    case ActivitySection.profileViews:
      return _kAmber;
    case ActivitySection.logins:
      return _kEmerald;
  }
}

// ─── Section state ────────────────────────────────────────────────────────────
class _SectionState {
  final List<ActivityDetailItem> items;
  final int total;
  final int page;
  final int totalPages;
  final bool loading;

  const _SectionState({
    this.items = const [],
    this.total = 0,
    this.page = 0,
    this.totalPages = 1,
    this.loading = false,
  });

  bool get hasMore => page < totalPages;

  _SectionState copyWith({
    List<ActivityDetailItem>? items,
    int? total,
    int? page,
    int? totalPages,
    bool? loading,
  }) => _SectionState(
    items: items ?? this.items,
    total: total ?? this.total,
    page: page ?? this.page,
    totalPages: totalPages ?? this.totalPages,
    loading: loading ?? this.loading,
  );
}
