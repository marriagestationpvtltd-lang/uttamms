import 'package:adminmrz/users/userdetails/detailscreen.dart';
import 'package:adminmrz/users/userdetails/userdetailprovider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../docprovider/docmodel.dart';
import '../docprovider/docservice.dart';

// ─────────────────────────── colour palette ──────────────────────────────────
const _kPrimary   = Color(0xFF6366F1);
const _kPageBg    = Color(0xFFF1F5F9);
const _kPending   = Color(0xFFF59E0B);
const _kApproved  = Color(0xFF10B981);
const _kRejected  = Color(0xFFEF4444);

class DocumentsPage extends StatefulWidget {
  const DocumentsPage({super.key});

  @override
  State<DocumentsPage> createState() => _DocumentsPageState();
}

class _DocumentsPageState extends State<DocumentsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _rejectReasonController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.toLowerCase());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final dp = context.read<DocumentsProvider>();
      // Only fetch once per session; manual refresh button is always available.
      if (!dp.isInitialized) {
        dp.fetchDocuments();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _rejectReasonController.dispose();
    super.dispose();
  }

  // ── search filter ────────────────────────────────────────────────────────────
  List<Document> _filter(List<Document> list) {
    if (_query.isEmpty) return list;
    return list.where((d) =>
        d.fullName.toLowerCase().contains(_query) ||
        d.email.toLowerCase().contains(_query) ||
        d.documentType.toLowerCase().contains(_query) ||
        d.documentIdNumber.toLowerCase().contains(_query)).toList();
  }

  // ── navigate to profile ──────────────────────────────────────────────────────
  void _openProfile(Document doc) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider(
          create: (_) => UserDetailsProvider(),
          child: UserDetailsScreen(
            userId: doc.userId,
            myId: doc.userId,
            email: doc.email,
          ),
        ),
      ),
    );
  }

  // ── approve ──────────────────────────────────────────────────────────────────
  Future<void> _approveDocument(Document doc) async {
    final provider = context.read<DocumentsProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Approve Document',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: Text("Approve ${doc.fullName}'s document?"),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: _kApproved, foregroundColor: Colors.white),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await provider.updateDocumentStatus(
        documentId: doc.documentId, action: 'approve');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok
            ? 'Document approved for ${doc.fullName}'
            : 'Failed: ${provider.error}'),
        backgroundColor: ok ? _kApproved : _kRejected,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        margin: const EdgeInsets.all(16),
      ));
    }
  }

  // ── reject ───────────────────────────────────────────────────────────────────
  Future<void> _rejectDocument(Document doc) async {
    _rejectReasonController.clear();
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Reject Document',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Document for ${doc.fullName}",
                style: const TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 14),
            const Text('Reason for rejection:',
                style: TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 8),
            TextField(
              controller: _rejectReasonController,
              maxLines: 3,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Enter rejection reason…',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (_rejectReasonController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Please enter a rejection reason'),
                  backgroundColor: _kRejected,
                ));
                return;
              }
              Navigator.pop(context);
              await _performReject(doc);
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: _kRejected, foregroundColor: Colors.white),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
  }

  Future<void> _performReject(Document doc) async {
    final provider = context.read<DocumentsProvider>();
    final ok = await provider.updateDocumentStatus(
      documentId: doc.documentId,
      action: 'reject',
      rejectReason: _rejectReasonController.text.trim(),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok
            ? 'Document rejected for ${doc.fullName}'
            : 'Failed: ${provider.error}'),
        backgroundColor: ok ? _kPending : _kRejected,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        margin: const EdgeInsets.all(16),
      ));
    }
  }

  // ── image preview ────────────────────────────────────────────────────────────
  void _showImagePreview(String url) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dialogBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.82,
                maxWidth: MediaQuery.of(context).size.width * 0.9,
              ),
              decoration: BoxDecoration(
                  color: dialogBg,
                  borderRadius: BorderRadius.circular(12)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Expanded(
                    child: InteractiveViewer(
                      panEnabled: true,
                      minScale: 0.5,
                      maxScale: 4,
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(12)),
                        child: Image.network(
                          url,
                          fit: BoxFit.contain,
                          loadingBuilder: (_, child, prog) {
                            if (prog == null) return child;
                            return Center(
                              child: CircularProgressIndicator(
                                value: prog.expectedTotalBytes != null
                                    ? prog.cumulativeBytesLoaded /
                                        prog.expectedTotalBytes!
                                    : null,
                              ),
                            );
                          },
                          errorBuilder: (_, __, ___) => Container(
                            color: isDark ? const Color(0xFF263248) : Colors.grey[100],
                            child: const Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.broken_image,
                                      size: 48, color: Colors.grey),
                                  SizedBox(height: 8),
                                  Text('Image not available',
                                      style: TextStyle(color: Colors.grey)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: dialogBg,
                      borderRadius:
                          const BorderRadius.vertical(bottom: Radius.circular(12)),
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close, size: 16),
                        label: const Text('Close'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kPrimary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                      color: Colors.black54, shape: BoxShape.circle),
                  child: const Icon(Icons.close,
                      color: Colors.white, size: 20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── stat chip ────────────────────────────────────────────────────────────────
  Widget _statChip(String label, int count, Color color) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.30)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                    color: color, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text('$label  $count',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: color)),
          ],
        ),
      );

  // ── top bar ──────────────────────────────────────────────────────────────────
  Widget _buildTopBar(DocumentsProvider provider) {
    final total = provider.documents.length;
    final cardBg = Theme.of(context).colorScheme.surface;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: cardBg,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.description_rounded,
                  size: 20, color: _kPrimary),
              const SizedBox(width: 8),
              const Text('Document Verification',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF4F46E5))),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 20),
                tooltip: 'Refresh',
                onPressed: provider.isLoading
                    ? null
                    : () => provider.fetchDocuments(),
                color: Colors.grey.shade600,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _statChip('Total', total, _kPrimary),
              _statChip('Pending',
                  provider.pendingDocuments.length, _kPending),
              _statChip('Approved',
                  provider.approvedDocuments.length, _kApproved),
              _statChip('Rejected',
                  provider.rejectedDocuments.length, _kRejected),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 38,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by name, email, document type…',
                hintStyle:
                    TextStyle(fontSize: 13, color: Colors.grey.shade400),
                prefixIcon: Icon(Icons.search,
                    size: 18, color: Colors.grey.shade400),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        onPressed: () => _searchController.clear(),
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: isDark ? Colors.white.withOpacity(0.10) : Colors.grey.shade200),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: isDark ? Colors.white.withOpacity(0.10) : Colors.grey.shade200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                      const BorderSide(color: _kPrimary, width: 1.5),
                ),
                fillColor: isDark ? const Color(0xFF263248) : Colors.grey.shade50,
                filled: true,
                contentPadding: EdgeInsets.zero,
                isDense: true,
              ),
              style: const TextStyle(fontSize: 13),
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  // ── tab bar ──────────────────────────────────────────────────────────────────
  Widget _buildTabBar(DocumentsProvider provider) => Container(
        color: Theme.of(context).colorScheme.surface,
        child: Column(
          children: [
            const Divider(height: 1, thickness: 1),
            TabBar(
              controller: _tabController,
              labelColor: _kPrimary,
              unselectedLabelColor: Colors.grey.shade500,
              indicatorColor: _kPrimary,
              indicatorWeight: 2.5,
              labelStyle: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600),
              tabs: [
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Pending'),
                      const SizedBox(width: 6),
                      _tabBadge(provider.pendingDocuments.length, _kPending),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Approved'),
                      const SizedBox(width: 6),
                      _tabBadge(
                          provider.approvedDocuments.length, _kApproved),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Rejected'),
                      const SizedBox(width: 6),
                      _tabBadge(
                          provider.rejectedDocuments.length, _kRejected),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _tabBadge(int count, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text('$count',
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: color)),
      );

  // ── document row ─────────────────────────────────────────────────────────────
  Widget _buildDocumentRow(Document doc, bool isPending) {
    final statusColor = doc.isApproved
        ? _kApproved
        : doc.isRejected
            ? _kRejected
            : _kPending;
    final cardBg = Theme.of(context).colorScheme.surface;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border(
          left: BorderSide(color: statusColor, width: 3),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // ── document thumbnail ─────────────────────────────────────────
            GestureDetector(
              onTap: () => _showImagePreview(doc.fullPhotoUrl),
              child: Stack(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: isDark ? const Color(0xFF263248) : Colors.grey.shade100,
                      border: Border.all(color: isDark ? Colors.white.withOpacity(0.10) : Colors.grey.shade200),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(7),
                      child: Image.network(
                        doc.fullPhotoUrl,
                        fit: BoxFit.cover,
                        loadingBuilder: (_, child, prog) {
                          if (prog == null) return child;
                          return const Center(
                            child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2)),
                          );
                        },
                        errorBuilder: (_, __, ___) => Container(
                          color: isDark ? const Color(0xFF263248) : Colors.grey.shade100,
                          child: Icon(Icons.insert_drive_file_outlined,
                              size: 28, color: Colors.grey.shade400),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(4),
                            bottomRight: Radius.circular(7),
                          )),
                      child: const Icon(Icons.zoom_in,
                          size: 12, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 14),

            // ── user info ──────────────────────────────────────────────────
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: () => _openProfile(doc),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            doc.fullName,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: _kPrimary,
                              decoration: TextDecoration.underline,
                              decorationColor: _kPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.open_in_new,
                            size: 11, color: _kPrimary),
                      ],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    doc.email,
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _infoChip(
                          Icons.person_outline,
                          doc.gender.isNotEmpty ? doc.gender : '—',
                          Colors.indigo),
                      const SizedBox(width: 6),
                      _infoChip(Icons.tag, '#${doc.userId}',
                          Colors.blueGrey),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(width: 10),

            // ── document details ───────────────────────────────────────────
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _docDetailRow(
                      Icons.badge_outlined, doc.documentType, Colors.blue),
                  const SizedBox(height: 4),
                  _docDetailRow(Icons.numbers_outlined,
                      doc.documentIdNumber, Colors.teal),
                  if (doc.rejectReason.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    _docDetailRow(Icons.info_outline,
                        doc.rejectReason, _kRejected),
                  ],
                ],
              ),
            ),

            const SizedBox(width: 10),

            // ── status + actions ───────────────────────────────────────────
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _statusBadge(doc.status),
                const SizedBox(height: 8),
                Consumer<DocumentsProvider>(
                  builder: (_, provider, __) {
                    if (provider.isActionLoading) {
                      return const SizedBox(
                        width: 20,
                        height: 20,
                        child:
                            CircularProgressIndicator(strokeWidth: 2),
                      );
                    }
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _actionBtn(
                          icon: Icons.visibility_outlined,
                          tooltip: 'View Document',
                          color: _kPrimary,
                          onTap: () => _showImagePreview(doc.fullPhotoUrl),
                        ),
                        const SizedBox(width: 4),
                        _actionBtn(
                          icon: Icons.person_outlined,
                          tooltip: 'View Profile',
                          color: Colors.indigo,
                          onTap: () => _openProfile(doc),
                        ),
                        if (isPending) ...[
                          const SizedBox(width: 4),
                          _actionBtn(
                            icon: Icons.check_circle_outline,
                            tooltip: 'Approve',
                            color: _kApproved,
                            onTap: () => _approveDocument(doc),
                          ),
                          const SizedBox(width: 4),
                          _actionBtn(
                            icon: Icons.cancel_outlined,
                            tooltip: 'Reject',
                            color: _kRejected,
                            onTap: () => _rejectDocument(doc),
                          ),
                        ] else if (doc.isApproved) ...[
                          const SizedBox(width: 4),
                          Tooltip(
                            message: 'Document is permanently locked after verification',
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: _kApproved.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                    color: _kApproved.withOpacity(0.20)),
                              ),
                              child: const Icon(Icons.lock_rounded,
                                  size: 16, color: _kApproved),
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoChip(IconData icon, String label, Color color) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color.withOpacity(0.7)),
          const SizedBox(width: 3),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color: color.withOpacity(0.9),
                  fontWeight: FontWeight.w500)),
        ],
      );

  Widget _docDetailRow(IconData icon, String label, Color color) => Row(
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              label.isNotEmpty ? label : '—',
              style: const TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w500),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );

  Widget _statusBadge(String status) {
    final color = status == 'approved'
        ? _kApproved
        : status == 'rejected'
            ? _kRejected
            : _kPending;
    final icon = status == 'approved'
        ? Icons.lock_rounded
        : status == 'rejected'
            ? Icons.cancel_outlined
            : Icons.pending_outlined;
    final label = status == 'approved'
        ? 'VERIFIED + LOCKED'
        : status.toUpperCase();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }

  Widget _actionBtn({
    required IconData icon,
    required String tooltip,
    required Color color,
    required VoidCallback onTap,
  }) =>
      Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.08),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: color.withOpacity(0.20)),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
        ),
      );

  // ── empty state ──────────────────────────────────────────────────────────────
  Widget _buildEmpty(String message) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF263248) : Colors.grey.shade100,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.folder_open_outlined,
                size: 40, color: Colors.grey.shade400),
          ),
          const SizedBox(height: 16),
          Text(message,
              style: TextStyle(
                  fontSize: 15,
                  color: Colors.grey.shade500,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          Text(
            _query.isNotEmpty
                ? 'Try different search terms'
                : 'Pull down to refresh',
            style: TextStyle(
                fontSize: 12, color: Colors.grey.shade400),
          ),
        ],
      ),
    );
  }

  // ── list ─────────────────────────────────────────────────────────────────────
  Widget _buildList(List<Document> docs, bool isPending) {
    final filtered = _filter(docs);
    if (filtered.isEmpty) {
      return _buildEmpty(
          isPending ? 'No pending documents' : 'No documents found');
    }
    return RefreshIndicator(
      onRefresh: () => context.read<DocumentsProvider>().fetchDocuments(),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 12),
        itemCount: filtered.length,
        itemBuilder: (_, i) => _buildDocumentRow(filtered[i], isPending),
      ),
    );
  }

  // ── build ─────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Consumer<DocumentsProvider>(
      builder: (_, provider, __) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        if (provider.isLoading) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(
                    valueColor:
                        AlwaysStoppedAnimation<Color>(_kPrimary)),
                SizedBox(height: 16),
                Text('Loading documents…',
                    style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                        fontWeight: FontWeight.w500)),
              ],
            ),
          );
        }

        if (provider.error != null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline,
                      size: 48, color: Colors.red.shade400),
                  const SizedBox(height: 16),
                  Text(provider.error!,
                      style: const TextStyle(
                          fontSize: 14, color: Colors.red),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Retry'),
                    onPressed: () => provider.fetchDocuments(),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: _kPrimary,
                        foregroundColor: Colors.white),
                  ),
                ],
              ),
            ),
          );
        }

        return Container(
          color: isDark ? const Color(0xFF0F172A) : _kPageBg,
          child: Column(
            children: [
              _buildTopBar(provider),
              _buildTabBar(provider),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildList(provider.pendingDocuments, true),
                    _buildList(provider.approvedDocuments, false),
                    _buildList(provider.rejectedDocuments, false),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
