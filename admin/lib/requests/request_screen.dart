import 'package:adminmrz/auth/service.dart';
import 'package:adminmrz/dashboard/dashservice.dart' show UnauthorizedException;
import 'package:adminmrz/requests/request_model.dart';
import 'package:adminmrz/requests/request_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// ─────────────────────────── colour palette ──────────────────────────────────
const _kPrimary  = Color(0xFF6366F1);
const _kEmerald  = Color(0xFF10B981);
const _kAmber    = Color(0xFFF59E0B);
const _kRose     = Color(0xFFEF4444);
const _kSky      = Color(0xFF0EA5E9);
const _kSlate700 = Color(0xFF334155);
const _kSlate500 = Color(0xFF64748B);

class RequestsPage extends StatefulWidget {
  const RequestsPage({super.key});

  @override
  State<RequestsPage> createState() => _RequestsPageState();
}

class _RequestsPageState extends State<RequestsPage> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RequestProvider>().fetchRequests(reset: true);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ── header ────────────────────────────────────────────────────────────────
  Widget _buildHeader(RequestProvider provider) {
    final cardBg = Theme.of(context).colorScheme.surface;
    return Container(
      color: cardBg,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      child: Row(
        children: [
          const Icon(Icons.people_alt_outlined, color: _kPrimary, size: 22),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Request & Match Control',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: _kSlate700,
                letterSpacing: -0.3,
              ),
            ),
          ),
          IconButton(
            onPressed: () => provider.fetchRequests(reset: true),
            icon: const Icon(Icons.refresh_rounded, color: _kPrimary, size: 20),
            tooltip: 'Refresh',
            style: IconButton.styleFrom(
              backgroundColor: _kPrimary.withOpacity(0.08),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  // ── stats bar ─────────────────────────────────────────────────────────────
  Widget _buildStatsBar(RequestProvider provider) {
    final stats = provider.stats;
    final filters = [
      ('All', stats?.total ?? 0, _kPrimary, 'all'),
      ('Pending', stats?.pending ?? 0, _kAmber, 'pending'),
      ('Accepted', stats?.accepted ?? 0, _kEmerald, 'accepted'),
      ('Rejected', stats?.rejected ?? 0, _kRose, 'rejected'),
      ('Cancelled', stats?.cancelled ?? 0, _kSlate500, 'cancelled'),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        children: filters.map((f) {
          final (label, count, color, value) = f;
          final isSelected = provider.statusFilter == value;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => provider.setFilter(value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isSelected ? color : color.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: isSelected
                          ? color
                          : color.withOpacity(0.25),
                      width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isSelected ? Colors.white : color,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Colors.white.withOpacity(0.25)
                            : color.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        count.toString(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: isSelected ? Colors.white : color,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── search box ────────────────────────────────────────────────────────────
  Widget _buildSearchBox(RequestProvider provider) {
    final cardBg = Theme.of(context).colorScheme.surface;
    return Container(
      color: cardBg,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: _searchController,
        builder: (context, value, _) {
          return TextField(
            controller: _searchController,
            onChanged: (v) => provider.setSearch(v.trim()),
            decoration: InputDecoration(
              hintText: 'Search by name or email…',
              hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
              prefixIcon: Icon(Icons.search_rounded,
                  color: Colors.grey.shade400, size: 18),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey.shade200),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey.shade200),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _kPrimary, width: 1.5),
              ),
              filled: true,
              fillColor: Colors.grey.shade50,
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 9, horizontal: 12),
              isDense: true,
              suffixIcon: value.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 16),
                      onPressed: () {
                        _searchController.clear();
                        provider.setSearch('');
                      },
                    )
                  : null,
            ),
          );
        },
      ),
    );
  }

  // ── skeleton loading ──────────────────────────────────────────────────────
  Widget _buildSkeleton() {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 6,
      itemBuilder: (_, __) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Container(
          height: 88,
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const SizedBox(width: 12),
              _shimmerBox(40, 40, radius: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _shimmerBox(120, 12),
                    const SizedBox(height: 6),
                    _shimmerBox(80, 10),
                    const SizedBox(height: 6),
                    _shimmerBox(60, 10),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _shimmerBox(64, 28, radius: 8),
              const SizedBox(width: 8),
              _shimmerBox(64, 28, radius: 8),
              const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _shimmerBox(double w, double h, {double radius = 6}) {
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: Colors.grey.shade300,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }

  // ── empty state ───────────────────────────────────────────────────────────
  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.inbox_outlined, size: 56, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              'No requests found',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade400),
            ),
            const SizedBox(height: 4),
            Text(
              'Try changing the filter or search query',
              style:
                  TextStyle(fontSize: 12, color: Colors.grey.shade400),
            ),
          ],
        ),
      ),
    );
  }

  // ── error state ───────────────────────────────────────────────────────────
  Widget _buildErrorState(String error, RequestProvider provider) {
    final isUnauth = error.contains('UnauthorizedException');
    if (isUnauth) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.read<AuthProvider>().logout();
      });
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.error_outline_rounded,
                size: 48, color: _kRose.withOpacity(0.7)),
            const SizedBox(height: 12),
            Text(
              'Something went wrong',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _kSlate700),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                error,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: _kSlate500),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => provider.fetchRequests(reset: true),
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimary,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                textStyle: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── status badge ──────────────────────────────────────────────────────────
  Widget _statusBadge(String status) {
    Color color;
    switch (status.toLowerCase()) {
      case 'pending':
        color = _kAmber;
        break;
      case 'accepted':
        color = _kEmerald;
        break;
      case 'rejected':
        color = _kRose;
        break;
      default:
        color = _kSlate500;
    }
    final label = status.isNotEmpty
        ? status[0].toUpperCase() + status.substring(1)
        : '—';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  // ── type badge ────────────────────────────────────────────────────────────
  Widget _typeBadge(String type) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: _kSky.withOpacity(0.10),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _kSky.withOpacity(0.3)),
      ),
      child: Text(
        type,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: _kSky,
        ),
      ),
    );
  }

  // ── avatar ────────────────────────────────────────────────────────────────
  Widget _avatar(String initials, Color color, {double size = 34}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        shape: BoxShape.circle,
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Center(
        child: Text(
          initials,
          style: TextStyle(
            fontSize: size * 0.35,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ),
    );
  }

  // ── confirm dialog ────────────────────────────────────────────────────────
  Future<bool?> _showConfirmDialog(String action, RequestItem item) {
    final isAccept = action == 'accepted';
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          '${isAccept ? 'Accept' : 'Reject'} Request?',
          style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: _kSlate700),
        ),
        content: Text(
          'Are you sure you want to ${isAccept ? 'accept' : 'reject'} the request from '
          '${item.senderName} to ${item.receiverName}?',
          style: const TextStyle(fontSize: 13, color: _kSlate500),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel',
                style: TextStyle(color: _kSlate500)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: isAccept ? _kEmerald : _kRose,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            child: Text(isAccept ? 'Accept' : 'Reject',
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  // ── request card ──────────────────────────────────────────────────────────
  Widget _buildRequestCard(RequestItem item, RequestProvider provider) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = Theme.of(context).colorScheme.surface;
    final isPending = item.status.toLowerCase() == 'pending';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? Theme.of(context).colorScheme.outlineVariant
              : Colors.grey.shade200,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Sender → Receiver row
            Row(
              children: [
                _avatar(item.senderInitials, _kPrimary),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.senderName,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _kSlate700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        item.senderEmail,
                        style: const TextStyle(
                            fontSize: 10, color: _kSlate500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_rounded,
                    size: 16, color: _kSlate500),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        item.receiverName,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _kSlate700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                      ),
                      Text(
                        item.receiverEmail,
                        style: const TextStyle(
                            fontSize: 10, color: _kSlate500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                _avatar(item.receiverInitials, _kSky),
              ],
            ),
            const SizedBox(height: 8),
            // Badges + date row
            Row(
              children: [
                _typeBadge(item.requestType),
                const SizedBox(width: 6),
                _statusBadge(item.status),
                const Spacer(),
                Icon(Icons.calendar_today_outlined,
                    size: 11, color: Colors.grey.shade400),
                const SizedBox(width: 3),
                Text(
                  item.formattedDate,
                  style: TextStyle(
                      fontSize: 10, color: Colors.grey.shade400),
                ),
              ],
            ),
            // Action buttons (only for pending)
            if (isPending) ...[
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _actionButton(
                    label: 'Reject',
                    color: _kRose,
                    icon: Icons.close_rounded,
                    onTap: () async {
                      final confirm =
                          await _showConfirmDialog('rejected', item);
                      if (confirm == true && mounted) {
                        await provider.forceUpdateStatus(
                            item.id, 'rejected', context);
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                  _actionButton(
                    label: 'Accept',
                    color: _kEmerald,
                    icon: Icons.check_rounded,
                    filled: true,
                    onTap: () async {
                      final confirm =
                          await _showConfirmDialog('accepted', item);
                      if (confirm == true && mounted) {
                        await provider.forceUpdateStatus(
                            item.id, 'accepted', context);
                      }
                    },
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required Color color,
    required IconData icon,
    required VoidCallback onTap,
    bool filled = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: filled ? color : color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(filled ? 0 : 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 13, color: filled ? Colors.white : color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: filled ? Colors.white : color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── load more button ──────────────────────────────────────────────────────
  Widget _buildLoadMoreButton(RequestProvider provider) {
    final pagination = provider.pagination;
    if (pagination == null || !pagination.hasMore) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: provider.isLoading ? null : provider.loadMore,
          icon: provider.isLoading
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: _kPrimary),
                )
              : const Icon(Icons.expand_more_rounded, size: 16),
          label: Text(
            provider.isLoading
                ? 'Loading…'
                : 'Load More (${pagination.total - provider.requests.length} remaining)',
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: _kPrimary,
            side: const BorderSide(color: _kPrimary, width: 1.2),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      ),
    );
  }

  // ── build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Consumer<RequestProvider>(
      builder: (context, provider, _) {
        // Handle unauthorized at build time
        if (provider.error.contains('UnauthorizedException')) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            context.read<AuthProvider>().logout();
          });
        }

        return Scaffold(
          backgroundColor: const Color(0xFFF1F5F9),
          body: SafeArea(
            child: Column(
              children: [
                _buildHeader(provider),
                const Divider(height: 1),
                // Stats bar and search in a surface-colored section
                Container(
                  color: Theme.of(context).colorScheme.surface,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildStatsBar(provider),
                      _buildSearchBox(provider),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // Content area
                Expanded(
                  child: _buildContent(provider),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildContent(RequestProvider provider) {
    // Initial full-screen loading
    if (provider.isLoading && provider.requests.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 8),
          _buildSkeleton(),
        ],
      );
    }

    // Error with empty list
    if (provider.error.isNotEmpty && provider.requests.isEmpty) {
      return SingleChildScrollView(
        child: _buildErrorState(provider.error, provider),
      );
    }

    // Empty state
    if (!provider.isLoading && provider.requests.isEmpty) {
      return SingleChildScrollView(child: _buildEmptyState());
    }

    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 16),
      children: [
        ...provider.requests.map((item) => _buildRequestCard(item, provider)),
        // Inline loading indicator while loading more
        if (provider.isLoading && provider.requests.isNotEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: CircularProgressIndicator(color: _kPrimary, strokeWidth: 2),
            ),
          ),
        _buildLoadMoreButton(provider),
      ],
    );
  }
}
