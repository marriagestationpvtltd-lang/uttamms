import 'package:adminmrz/deleteRequests/delete_request_model.dart';
import 'package:adminmrz/deleteRequests/delete_request_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// ── Palette ──────────────────────────────────────────────────────────────────
const _kRed = Color(0xFFEF4444);
const _kGreen = Color(0xFF10B981);
const _kAmber = Color(0xFFF59E0B);
const _kSlate700 = Color(0xFF334155);
const _kSlate500 = Color(0xFF64748B);

class DeleteRequestsPage extends StatefulWidget {
  const DeleteRequestsPage({super.key});

  @override
  State<DeleteRequestsPage> createState() => _DeleteRequestsPageState();
}

class _DeleteRequestsPageState extends State<DeleteRequestsPage> {
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DeleteRequestProvider>().fetchRequests(reset: true);
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── header ────────────────────────────────────────────────────────────────
  Widget _buildHeader(DeleteRequestProvider p) {
    final stats = p.stats;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF7F1D1D), Color(0xFFB91C1C), Color(0xFFEF4444)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.person_remove_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Account Deletion Requests',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'Review and approve or reject pending requests',
                      style: TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (stats != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                _statChip('Pending', stats.pending, _kAmber),
                const SizedBox(width: 8),
                _statChip('Approved', stats.approved, _kGreen),
                const SizedBox(width: 8),
                _statChip('Rejected', stats.rejected, _kSlate500),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _statChip(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            '$label: $count',
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    );
  }

  // ── filter bar ────────────────────────────────────────────────────────────
  Widget _buildFilterBar(DeleteRequestProvider p) {
    const filters = ['all', 'pending', 'approved', 'rejected'];
    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        children: [
          TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'Search by name or email…',
              prefixIcon: const Icon(Icons.search, size: 18),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
            onChanged: (v) => p.setSearch(v.trim()),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: filters.map((f) {
                final active = p.statusFilter == f;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(f[0].toUpperCase() + f.substring(1)),
                    selected: active,
                    onSelected: (_) => p.setFilter(f),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // ── list item ─────────────────────────────────────────────────────────────
  Widget _buildItem(DeleteRequestItem item, DeleteRequestProvider p) {
    final isPending = item.status == 'pending';
    final isApproved = item.status == 'approved';

    Color statusColor = isPending
        ? _kAmber
        : isApproved
        ? _kGreen
        : _kSlate500;
    IconData statusIcon = isPending
        ? Icons.hourglass_top_rounded
        : isApproved
        ? Icons.check_circle_rounded
        : Icons.cancel_rounded;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── User row ────────────────────────────────────────────────────
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundImage:
                      (item.userPhoto != null && item.userPhoto!.isNotEmpty)
                      ? NetworkImage(item.userPhoto!)
                      : null,
                  child: (item.userPhoto == null || item.userPhoto!.isEmpty)
                      ? Text(
                          item.userName.isNotEmpty
                              ? item.userName[0].toUpperCase()
                              : '?',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        )
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.userName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        item.userEmail,
                        style: TextStyle(fontSize: 12, color: _kSlate500),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, size: 12, color: statusColor),
                      const SizedBox(width: 4),
                      Text(
                        item.status[0].toUpperCase() + item.status.substring(1),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: statusColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // ── Reason ──────────────────────────────────────────────────────
            _infoRow(Icons.info_outline_rounded, 'Reason', item.deleteReason),
            if (item.feedback != null && item.feedback!.isNotEmpty)
              _infoRow(Icons.feedback_outlined, 'Feedback', item.feedback!),
            if (item.adminNote != null && item.adminNote!.isNotEmpty)
              _infoRow(
                Icons.admin_panel_settings_outlined,
                'Admin note',
                item.adminNote!,
              ),

            const SizedBox(height: 4),
            Text(
              'Requested: ${_fmtDate(item.createdAt)}',
              style: TextStyle(fontSize: 11, color: _kSlate500),
            ),
            if (item.reviewedAt != null)
              Text(
                'Reviewed: ${_fmtDate(item.reviewedAt!)}',
                style: TextStyle(fontSize: 11, color: _kSlate500),
              ),

            // ── Action buttons (only for pending) ───────────────────────────
            if (isPending) ...[
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: p.isActing
                        ? null
                        : () => _confirmAction(
                            context: context,
                            item: item,
                            action: 'reject',
                            provider: p,
                          ),
                    icon: const Icon(Icons.undo_rounded, size: 16),
                    label: const Text('Reject'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _kSlate700,
                      side: BorderSide(color: Colors.grey.shade300),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: p.isActing
                        ? null
                        : () => _confirmAction(
                            context: context,
                            item: item,
                            action: 'approve',
                            provider: p,
                          ),
                    icon: const Icon(Icons.delete_forever_rounded, size: 16),
                    label: const Text('Approve & Delete'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kRed,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: _kSlate500),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }

  String _fmtDate(String raw) {
    try {
      final dt = DateTime.parse(raw).toLocal();
      return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return raw;
    }
  }

  // ── Confirm dialog ────────────────────────────────────────────────────────
  Future<void> _confirmAction({
    required BuildContext context,
    required DeleteRequestItem item,
    required String action,
    required DeleteRequestProvider provider,
  }) async {
    final noteCtrl = TextEditingController();
    final isApprove = action == 'approve';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              isApprove ? Icons.delete_forever_rounded : Icons.undo_rounded,
              color: isApprove ? _kRed : _kSlate700,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                isApprove ? 'Approve & Delete Account' : 'Reject Request',
                style: TextStyle(
                  fontSize: 16,
                  color: isApprove ? _kRed : _kSlate700,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isApprove
                  ? 'You are about to PERMANENTLY delete the account of:\n\n'
                        '${item.userName} (${item.userEmail})\n\n'
                        'This cannot be undone. All user data will be erased.'
                  : 'Reject the delete request from:\n\n'
                        '${item.userName} (${item.userEmail})\n\n'
                        'The account will be restored and the user can log in again.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Admin note (optional)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              FocusManager.instance.primaryFocus?.unfocus();
              Navigator.pop(ctx, false);
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              FocusManager.instance.primaryFocus?.unfocus();
              Navigator.pop(ctx, true);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: isApprove ? _kRed : _kSlate700,
              foregroundColor: Colors.white,
            ),
            child: Text(isApprove ? 'Delete Permanently' : 'Reject Request'),
          ),
        ],
      ),
    );

    noteCtrl.dispose();

    if (confirmed != true) return;

    final ok = await provider.resolveRequest(
      requestId: item.id,
      action: action,
      adminNote: noteCtrl.text.trim(),
    );

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? (isApprove
                    ? 'Account permanently deleted.'
                    : 'Request rejected. Account restored.')
              : provider.error,
        ),
        backgroundColor: ok ? (isApprove ? _kRed : _kGreen) : Colors.red,
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Consumer<DeleteRequestProvider>(
      builder: (context, p, _) {
        return Column(
          children: [
            _buildHeader(p),
            _buildFilterBar(p),
            Expanded(
              child: p.isLoading && p.items.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : p.error.isNotEmpty && p.items.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            size: 48,
                            color: Colors.red,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            p.error,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.red),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: () => p.fetchRequests(reset: true),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    )
                  : p.items.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check_circle_outline,
                            size: 56,
                            color: Colors.green.shade300,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'No delete requests found',
                            style: TextStyle(fontSize: 16, color: _kSlate500),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () => p.fetchRequests(reset: true),
                      child: ListView.builder(
                        padding: const EdgeInsets.only(top: 8, bottom: 80),
                        itemCount: p.items.length + (p.hasMore ? 1 : 0),
                        itemBuilder: (ctx, i) {
                          if (i == p.items.length) {
                            p.loadMore();
                            return const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }
                          return _buildItem(p.items[i], p);
                        },
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}
