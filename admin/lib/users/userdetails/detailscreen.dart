import 'package:adminmrz/users/userdetails/userdetailprovider.dart';
import 'package:adminmrz/document/docprovider/docmodel.dart';
import 'package:adminmrz/document/docprovider/docservice.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'detailmodel.dart';

class _BulkFieldConfig {
  final String key;
  final String label;
  final String apiField;
  final String section;
  final String initial;
  final TextInputType inputType;
  final bool multiline;

  const _BulkFieldConfig({
    required this.key,
    required this.label,
    required this.apiField,
    required this.section,
    required this.initial,
    this.inputType = TextInputType.text,
    this.multiline = false,
  });
}

String _cleanInitial(String value) {
  if (value == 'Not available' || value == 'null') return '';
  return value;
}

// ─────────────────────────── colour palette ───────────────────────────────────
const _kPrimary      = Color(0xFF6366F1); // indigo-500
const _kPrimaryDark  = Color(0xFF4F46E5);
const _kViolet       = Color(0xFF8B5CF6);
const _kEmerald      = Color(0xFF10B981);
const _kAmber        = Color(0xFFF59E0B);
const _kRose         = Color(0xFFEF4444);
const _kSky          = Color(0xFF0EA5E9);
const _kPersonal     = _kPrimary;
const _kEducation    = _kEmerald;
const _kFamily       = _kViolet;
const _kLifestyle    = _kAmber;
const _kPartner      = Color(0xFFDB2777);
const _kDocs         = _kSky;
const _kPageBg       = Color(0xFFF1F5F9);

// ──────────────────────────── Screen ─────────────────────────────────────────
class UserDetailsScreen extends StatefulWidget {
  final int userId;
  final int myId;
  final void Function(int userId)? onOpenChat;
  final String? email;
  final String? phone;
  final String? whatsapp;

  const UserDetailsScreen({
    super.key,
    required this.userId,
    required this.myId,
    this.onOpenChat,
    this.email,
    this.phone,
    this.whatsapp,
  });

  @override
  State<UserDetailsScreen> createState() => _UserDetailsScreenState();
}

class _UserDetailsScreenState extends State<UserDetailsScreen> {
  String? _editingKey;
  final TextEditingController _editCtrl = TextEditingController();
  final TextEditingController _rejectDocCtrl = TextEditingController();
  final TextEditingController _notifTitleCtrl = TextEditingController();
  final TextEditingController _notifBodyCtrl = TextEditingController();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context
          .read<UserDetailsProvider>()
          .fetchUserDetails(widget.userId, widget.myId);
      // Load documents for this user if not yet initialized
      final docProvider = context.read<DocumentsProvider>();
      if (!docProvider.isInitialized && !docProvider.isLoading) {
        docProvider.fetchDocuments();
      }
    });
  }

  @override
  void dispose() {
    context.read<UserDetailsProvider>().clearData();
    _editCtrl.dispose();
    _rejectDocCtrl.dispose();
    _notifTitleCtrl.dispose();
    _notifBodyCtrl.dispose();
    super.dispose();
  }

  // ── edit helpers ────────────────────────────────────────────────────────────

  void _startEdit(String key, String currentValue) {
    setState(() {
      _editingKey = key;
      _editCtrl.text =
          (currentValue == 'Not available' || currentValue == 'null')
              ? ''
              : currentValue;
    });
  }

  void _cancelEdit() {
    setState(() {
      _editingKey = null;
      _editCtrl.clear();
    });
  }

  Future<void> _saveEdit(String key, String section, String apiField) async {
    final newValue = _editCtrl.text.trim();
    setState(() => _isSaving = true);

    final ok = await context.read<UserDetailsProvider>().updateField(
          section: section,
          field: apiField,
          value: newValue,
        );

    setState(() {
      _isSaving = false;
      _editingKey = null;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              ok ? 'Updated successfully' : 'Update failed — please try again'),
          backgroundColor:
              ok ? Colors.green.shade700 : Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _handlePhotoAction(String action) async {
    final prov = context.read<UserDetailsProvider>();
    String? reason;
    if (action == 'reject') {
      _rejectDocCtrl.clear();
      final res = await showDialog<String>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Reject Profile Photo'),
          content: TextField(
            controller: _rejectDocCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Reason for rejection',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, _rejectDocCtrl.text.trim()),
              style: ElevatedButton.styleFrom(backgroundColor: _kRose),
              child: const Text('Reject'),
            ),
          ],
        ),
      );
      if (res == null) return;
      reason = res;
      if (reason.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Please provide a rejection reason'),
            backgroundColor: _kRose,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
        return;
      }
    }

    final ok = await prov.handleProfilePhotoRequest(action: action, reason: reason);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? 'Photo ${action == 'approve' ? 'approved' : 'rejected'}' : 'Action failed'),
          backgroundColor: ok
              ? (action == 'approve' ? _kEmerald : _kRose)
              : Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }
  }

  Future<void> _requestPhotoUpload(PersonalDetail p) async {
    if (!mounted) return;
    final prov = context.read<UserDetailsProvider>();
    final ok = await prov.sendAdminNotification(
      title: 'Please upload your profile photo',
      message:
          'Hi ${p.firstName}, please upload a clear profile photo so our team can verify and approve your profile faster.',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'Upload request sent to user' : 'Failed to send request'),
        backgroundColor: ok ? _kPrimary : _kRose,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Future<void> _showSendNotificationDialog() async {
    _notifTitleCtrl.clear();
    _notifBodyCtrl.clear();
    final prov = context.read<UserDetailsProvider>();
    final res = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Send Notification'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _notifTitleCtrl,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _notifBodyCtrl,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Message'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: _kPrimary),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    if (res != true) return;
    final ok = await prov.sendAdminNotification(
      title: _notifTitleCtrl.text.trim().isEmpty ? 'Admin Message' : _notifTitleCtrl.text.trim(),
      message: _notifBodyCtrl.text.trim(),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? 'Notification sent' : 'Failed to send notification'),
          backgroundColor: ok ? _kPrimary : Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }
  }

  // ── reusable editable row ────────────────────────────────────────────────────

  Widget _row(
    String key,
    String label,
    String rawValue, {
    required String section,
    required String apiField,
    IconData? icon,
    bool highlight = false,
  }) {
    final displayValue =
        (rawValue.isEmpty || rawValue == 'null') ? '—' : rawValue;
    final isEditing = _editingKey == key;
    final faded = displayValue == 'Not available' || displayValue == '—';

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 26,
            child: icon != null
                ? Icon(icon, size: 15, color: Colors.blueGrey.shade300)
                : null,
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 170,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: isEditing
                ? Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 34,
                          child: TextField(
                            controller: _editCtrl,
                            autofocus: true,
                            onSubmitted: (_) =>
                                _saveEdit(key, section, apiField),
                            decoration: InputDecoration(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 7),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: BorderSide(
                                    color: _kPrimary.withOpacity(0.4)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: const BorderSide(
                                    color: _kPrimary, width: 1.5),
                              ),
                              isDense: true,
                            ),
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      _btn(
                        'Save',
                        bg: _kPrimary,
                        fg: Colors.white,
                        loading: _isSaving,
                        onPressed: _isSaving
                            ? null
                            : () => _saveEdit(key, section, apiField),
                      ),
                      const SizedBox(width: 4),
                      _btn(
                        'Cancel',
                        bg: Colors.white,
                        fg: Colors.grey.shade700,
                        border: Colors.grey.shade300,
                        onPressed: _isSaving ? null : _cancelEdit,
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        child: Text(
                          displayValue,
                          style: TextStyle(
                            fontSize: 14,
                            color: faded
                                ? Colors.grey.shade400
                                : highlight
                                    ? _kPrimary
                                    : Colors.grey.shade900,
                            fontWeight: faded
                                ? FontWeight.w400
                                : highlight
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: () => _startEdit(key, rawValue),
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.all(5),
                          child: Icon(Icons.edit_outlined,
                              size: 13, color: Colors.blueGrey.shade300),
                        ),
                      ),
                      const SizedBox(width: 2),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _btn(
    String label, {
    required Color bg,
    required Color fg,
    Color? border,
    VoidCallback? onPressed,
    bool loading = false,
  }) =>
      SizedBox(
        height: 30,
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: bg,
            foregroundColor: fg,
            elevation: 0,
            shadowColor: Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            minimumSize: const Size(52, 30),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
              side: border != null ? BorderSide(color: border) : BorderSide.none,
            ),
          ),
          child: loading
              ? SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                )
              : Text(label,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600)),
        ),
      );

  Widget _chipButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    Color color = _kPrimary,
    Color? bg,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: bg ?? color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w700, color: color),
            ),
          ],
        ),
      ),
    );
  }

  // ── section wrapper ──────────────────────────────────────────────────────────

  Widget _section({
    required String title,
    required IconData icon,
    required Color color,
    required List<Widget> rows,
    Widget? trailing,
  }) {
    return Container(
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: color, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            color: color.withOpacity(0.05),
            child: Row(
              children: [
                Icon(icon, size: 17, color: color),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: color,
                    letterSpacing: 0.2,
                  ),
                ),
                const Spacer(),
                if (trailing != null) trailing,
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Column(children: rows),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _activityStatCard(String label, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.20),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade600, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(value,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _activityStatGrid(UserDetailsProvider prov) {
    final stats = prov.activityStats;
    if (prov.isLoadingActivity && stats == null) {
      return const SizedBox(
        height: 60,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final s = stats ?? ActivityStats.empty();
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _activityStatCard('Requests Sent', '${s.requestsSent}', _kPrimary, Icons.send_rounded),
        _activityStatCard('Requests Received', '${s.requestsReceived}', _kViolet, Icons.inbox_outlined),
        _activityStatCard('Chat Sent', '${s.chatRequestsSent}', _kSky, Icons.chat_bubble_outline),
        _activityStatCard('Chat Accepted', '${s.chatRequestsAccepted}', _kEmerald, Icons.check_circle_outline),
        _activityStatCard('Profile Views', '${s.profileViews}', _kAmber, Icons.visibility_outlined),
        _activityStatCard('Matches', '${s.matchesCount}', _kPartner, Icons.favorite_outline),
      ],
    );
  }

  Widget _statusPill(String label, Color color, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaAndActivity(PersonalDetail p, UserDetailsProvider prov) {
    final isPhotoMissing = !p.hasProfilePicture;
    final photoStatus = p.photoRequest.isNotEmpty
        ? p.photoRequest
        : (isPhotoMissing ? 'No profile photo' : 'Uploaded');

    Widget mediaCard = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 16,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _statusPill(
                photoStatus.toUpperCase(),
                isPhotoMissing
                    ? _kAmber
                    : photoStatus.toLowerCase().contains('approve')
                        ? _kEmerald
                        : photoStatus.toLowerCase().contains('reject')
                            ? _kRose
                            : _kSky,
                icon: Icons.photo_camera_outlined,
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Refresh',
                icon: const Icon(Icons.refresh, size: 16),
                onPressed: () => prov.fetchUserDetails(widget.userId, widget.myId),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            height: 200,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(
                colors: [
                  _kPrimary.withOpacity(0.08),
                  _kViolet.withOpacity(0.08),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: _kPrimary.withOpacity(0.18)),
            ),
            clipBehavior: Clip.antiAlias,
            child: p.hasProfilePicture
                ? Stack(
                    children: [
                      Positioned.fill(
                        child: Image.network(
                          p.profilePicture,
                          fit: BoxFit.cover,
                          loadingBuilder: (_, child, prog) =>
                              prog == null ? child : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                          errorBuilder: (_, __, ___) => const Center(
                            child: Icon(Icons.broken_image, size: 48, color: Colors.grey),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 12,
                        right: 12,
                        child: _statusPill(photoStatus, _kPrimaryDark, icon: Icons.verified_user),
                      ),
                    ],
                  )
                : Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.photo_camera_outlined, size: 42, color: _kPrimaryDark),
                        SizedBox(height: 8),
                        Text(
                          'No profile photo yet',
                          style: TextStyle(fontSize: 13, color: Color(0xFF475569), fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 12),
          if (isPhotoMissing)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.send_outlined, size: 16),
                label: const Text('Request profile photo'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kPrimary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
                onPressed: prov.isSendingNotification ? null : () => _requestPhotoUpload(p),
              ),
            )
          else if (p.photoRequest == 'approved')
            // Photo already approved — lock it, no re-approval allowed.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
              decoration: BoxDecoration(
                color: _kEmerald.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _kEmerald.withOpacity(0.25)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.lock_rounded, size: 15, color: _kEmerald),
                  SizedBox(width: 8),
                  Text(
                    'Photo approved & locked',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _kEmerald,
                    ),
                  ),
                ],
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.verified_outlined, size: 16),
                    label: const Text('Approve'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kEmerald,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                    ),
                    onPressed: prov.isPhotoActioning ? null : () => _handlePhotoAction('approve'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.cancel_outlined, size: 16),
                    label: const Text('Reject'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _kRose,
                      side: const BorderSide(color: _kRose),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: prov.isPhotoActioning ? null : () => _handlePhotoAction('reject'),
                  ),
                ),
              ],
            ),
        ],
      ),
    );

    Widget activityCard = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 16,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Engagement & Activity',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
              ),
              if (prov.isLoadingActivity) ...[
                const SizedBox(width: 8),
                const SizedBox(
                  height: 14,
                  width: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
              const Spacer(),
              IconButton(
                tooltip: 'Reload activity',
                icon: const Icon(Icons.refresh, size: 16),
                onPressed: () => prov.fetchActivityStats(widget.userId),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _activityStatGrid(prov),
        ],
      ),
    );

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _kPrimary.withOpacity(0.06),
            _kViolet.withOpacity(0.06),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kPrimary.withOpacity(0.12)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 760;
          if (isWide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 4, child: mediaCard),
                const SizedBox(width: 14),
                Expanded(flex: 6, child: activityCard),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              mediaCard,
              const SizedBox(height: 12),
              activityCard,
            ],
          );
        },
      ),
    );
  }

  Widget _buildActivityStats(UserDetailsProvider prov) {
    final stats = prov.activityStats;
    if (prov.isLoadingActivity && stats == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final s = stats ?? ActivityStats.empty();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              const Text('User Activity',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _kPrimary)),
              if (prov.isLoadingActivity) ...[
                const SizedBox(width: 8),
                const SizedBox(
                  height: 14,
                  width: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ]
            ],
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _activityStatCard('Requests Sent', '${s.requestsSent}', _kPrimary, Icons.send_rounded),
              _activityStatCard('Requests Received', '${s.requestsReceived}', const Color(0xFF8B5CF6), Icons.inbox_outlined),
              _activityStatCard('Chat Sent', '${s.chatRequestsSent}', const Color(0xFF0EA5E9), Icons.chat_bubble_outline),
              _activityStatCard('Chat Accepted', '${s.chatRequestsAccepted}', const Color(0xFF10B981), Icons.check_circle_outline),
              _activityStatCard('Profile Views', '${s.profileViews}', const Color(0xFFF59E0B), Icons.visibility_outlined),
              _activityStatCard('Matches', '${s.matchesCount}', const Color(0xFFDB2777), Icons.favorite_outline),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildAdminActions(PersonalDetail p, UserDetailsProvider prov) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Admin Actions',
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700, color: Colors.grey.shade800)),
              const SizedBox(width: 8),
              if (prov.isSendingNotification || prov.isPhotoActioning)
                const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.notifications_active_outlined, size: 16),
                label: const Text('Send Notification'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kPrimary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
                onPressed: prov.isSendingNotification ? null : _showSendNotificationDialog,
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.chat_bubble_outline, size: 16),
                label: const Text('Open Chat'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _kPrimary,
                  side: const BorderSide(color: _kPrimary),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
                onPressed: widget.onOpenChat != null
                    ? () => widget.onOpenChat!(widget.userId)
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── profile header ───────────────────────────────────────────────────────────

  Widget _buildHeader(PersonalDetail p, ContactDetail c) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: _kPrimary.withOpacity(0.25), width: 3),
                  color: _kPrimary.withOpacity(0.08),
                ),
                child: ClipOval(
                  child: p.hasProfilePicture
                      ? Image.network(
                          p.profilePicture,
                          fit: BoxFit.cover,
                          loadingBuilder: (_, child, prog) => prog == null
                              ? child
                              : Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    value: prog.expectedTotalBytes != null
                                        ? prog.cumulativeBytesLoaded /
                                            prog.expectedTotalBytes!
                                        : null,
                                  ),
                                ),
                          errorBuilder: (_, __, ___) => Icon(Icons.person,
                              size: 40, color: Colors.blue.shade300),
                        )
                      : Icon(Icons.person, size: 40, color: Colors.blue.shade300),
                ),
              ),
              const SizedBox(width: 22),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.fullName,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: _kPrimaryDark,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 18,
                      runSpacing: 4,
                      children: [
                        if (p.age != null)
                          _metaChip(Icons.cake, '${p.age} yrs', Colors.blue.shade700),
                        _metaChip(Icons.location_on, p.city, Colors.blue.shade700),
                        if (p.country != 'Not available')
                          _metaChip(Icons.public, p.country, Colors.teal.shade700),
                        _metaChip(Icons.favorite, p.maritalStatusName, Colors.pink.shade600),
                        _metaChip(Icons.badge, 'ID: ${p.memberId}', Colors.grey.shade600),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _badge(
                          label: p.userType.isEmpty ? 'FREE' : p.userType.toUpperCase(),
                          icon: p.userType == 'paid' ? Icons.workspace_premium : Icons.person_outline,
                          bg: p.userType == 'paid' ? _kAmber.withOpacity(0.15) : Colors.grey.shade100,
                          border: p.userType == 'paid' ? _kAmber.withOpacity(0.6) : Colors.grey.shade300,
                          fg: p.userType == 'paid' ? const Color(0xFF92400E) : Colors.grey.shade700,
                        ),
                        _badge(
                          label: p.isVerified == 1 ? 'Verified' : 'Pending Verification',
                          icon: p.isVerified == 1 ? Icons.verified_user : Icons.pending_actions,
                          bg: p.isVerified == 1 ? _kEmerald.withOpacity(0.12) : _kAmber.withOpacity(0.12),
                          border: p.isVerified == 1 ? _kEmerald.withOpacity(0.4) : _kAmber.withOpacity(0.4),
                          fg: p.isVerified == 1 ? const Color(0xFF065F46) : const Color(0xFFB45309),
                        ),
                        if (p.privacy.isNotEmpty)
                          _badge(
                            label: p.privacy,
                            icon: Icons.lock_outline,
                            bg: Colors.indigo.shade50,
                            border: Colors.indigo.shade200,
                            fg: Colors.indigo.shade800,
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildContactInfo(c),
                  ],
                ),
              ),
            ],
          ),
          if (p.aboutMe.isNotEmpty && p.aboutMe != 'Not available') ...[
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.blue.shade100),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('About Me',
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700, color: _kPrimary)),
                  const SizedBox(height: 6),
                  Text(p.aboutMe,
                      style: TextStyle(
                          fontSize: 14, color: Colors.blueGrey.shade800, height: 1.6)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _metaChip(IconData icon, String label, Color color) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 3),
          Text(label,
              style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w500)),
        ],
      );

  Widget _badge({
    required String label,
    required IconData icon,
    required Color bg,
    required Color border,
    required Color fg,
  }) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 5),
            Text(label,
                style:
                    TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
          ],
        ),
      );

  Widget _buildContactInfo(ContactDetail c) {
    final hasAny = c.hasEmail || c.hasPhone;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blueGrey.shade50),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.contact_mail_outlined, size: 16, color: _kPrimary),
              const SizedBox(width: 8),
              const Text(
                'Contact Information',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: _kPrimaryDark),
              ),
              if (!hasAny) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text('Missing', style: TextStyle(fontSize: 11, color: Colors.amber.shade700)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 16,
            runSpacing: 10,
            children: [
              _contactTile(
                icon: Icons.email_outlined,
                label: 'Email',
                value: c.hasEmail ? c.email : 'Not available',
              ),
              _contactTile(
                icon: Icons.phone_outlined,
                label: 'Phone',
                value: c.hasPhone ? c.preferredPhone : 'Not available',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _contactTile({
    required IconData icon,
    required String label,
    required String value,
  }) {
    final missing = value.isEmpty || value == 'Not available' || value == 'null';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: missing ? Colors.grey.shade50 : Colors.blue.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: missing ? Colors.grey.shade200 : Colors.blue.shade100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: missing ? Colors.grey.shade500 : Colors.blue.shade700),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w600,
                  )),
              const SizedBox(height: 2),
              Text(
                missing ? 'Not available' : value,
                style: TextStyle(
                  fontSize: 13,
                  color: missing ? Colors.grey.shade500 : Colors.blueGrey.shade900,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── section builders ─────────────────────────────────────────────────────────

  Widget _buildPersonal(PersonalDetail p) => _section(
        title: 'Personal Details',
        icon: Icons.person_outline,
        color: _kPersonal,
        trailing: _chipButton(
          label: 'Edit all',
          icon: Icons.edit_outlined,
          onTap: () => _openPersonalBulk(p),
          color: _kPersonal,
        ),
        rows: [
          _row('p_height', 'Height', p.heightName, section: 'personal', apiField: 'height_name', icon: Icons.height, highlight: true),
          _row('p_dob', 'Birth Date', p.birthDate, section: 'personal', apiField: 'birthDate', icon: Icons.cake),
          _row('p_birthtime', 'Birth Time', p.birthtime, section: 'personal', apiField: 'birthtime', icon: Icons.access_time),
          _row('p_birthcity', 'Birth City', p.birthcity, section: 'personal', apiField: 'birthcity', icon: Icons.place),
          _row('p_religion', 'Religion', p.religionName, section: 'personal', apiField: 'religionName', icon: Icons.flag),
          _row('p_community', 'Community', p.communityName, section: 'personal', apiField: 'communityName', icon: Icons.people),
          _row('p_subcomm', 'Sub Community', p.subCommunityName, section: 'personal', apiField: 'subCommunityName', icon: Icons.people_outline),
          _row('p_tongue', 'Mother Tongue', p.motherTongue, section: 'personal', apiField: 'motherTongue', icon: Icons.language),
          _row('p_blood', 'Blood Group', p.bloodGroup, section: 'personal', apiField: 'bloodGroup', icon: Icons.water_drop),
          _row('p_marital', 'Marital Status', p.maritalStatusName, section: 'personal', apiField: 'maritalStatusName', icon: Icons.favorite_border),
          _row('p_manglik', 'Manglik', p.manglik, section: 'personal', apiField: 'manglik', icon: Icons.star_border),
          _row('p_disability', 'Disability', p.disability, section: 'personal', apiField: 'Disability', icon: Icons.accessible),
          _row('p_photo', 'Photo Request', p.photoRequest, section: 'personal', apiField: 'photo_request', icon: Icons.photo_camera_outlined),
          _row('p_privacy', 'Privacy Setting', p.privacy, section: 'personal', apiField: 'privacy', icon: Icons.lock_outline),
        ],
      );

  Widget _buildEducation(PersonalDetail p) => _section(
        title: 'Education & Career',
        icon: Icons.school_outlined,
        color: _kEducation,
        trailing: _chipButton(
          label: 'Edit all',
          icon: Icons.edit_outlined,
          onTap: () => _openEducationBulk(p),
          color: _kEducation,
        ),
        rows: [
          _row('e_type', 'Education Type', p.educationType, section: 'personal', apiField: 'educationtype', icon: Icons.school, highlight: true),
          _row('e_degree', 'Degree', p.degree, section: 'personal', apiField: 'degree', icon: Icons.military_tech_outlined),
          _row('e_faculty', 'Faculty', p.faculty, section: 'personal', apiField: 'faculty', icon: Icons.book_outlined),
          _row('e_medium', 'Education Medium', p.educationMedium, section: 'personal', apiField: 'educationmedium', icon: Icons.translate),
          _row('e_working', 'Are You Working?', p.areYouWorking, section: 'personal', apiField: 'areyouworking', icon: Icons.work_outline),
          _row('e_occ', 'Occupation Type', p.occupationType, section: 'personal', apiField: 'occupationtype', icon: Icons.business_center_outlined, highlight: true),
          _row('e_workwith', 'Working With', p.workingWith, section: 'personal', apiField: 'workingwith', icon: Icons.corporate_fare),
          _row('e_company', 'Company Name', p.companyName, section: 'personal', apiField: 'companyname', icon: Icons.business),
          _row('e_designation', 'Designation', p.designation, section: 'personal', apiField: 'designation', icon: Icons.badge_outlined),
          _row('e_business', 'Business Name', p.businessName, section: 'personal', apiField: 'businessname', icon: Icons.store_outlined),
          _row('e_income', 'Annual Income', p.annualIncome, section: 'personal', apiField: 'annualincome', icon: Icons.currency_rupee, highlight: true),
        ],
      );

  Widget _buildFamily(FamilyDetail f) => _section(
        title: 'Family Details',
        icon: Icons.family_restroom,
        color: _kFamily,
        trailing: _chipButton(
          label: 'Edit all',
          icon: Icons.edit_outlined,
          onTap: () => _openFamilyBulk(f),
          color: _kFamily,
        ),
        rows: [
          _row('f_type', 'Family Type', f.familyType, section: 'family', apiField: 'familytype', icon: Icons.home_outlined, highlight: true),
          _row('f_background', 'Family Background', f.familyBackground, section: 'family', apiField: 'familybackground', icon: Icons.history_edu),
          _row('f_origin', 'Family Origin', f.familyOrigin, section: 'family', apiField: 'familyorigin', icon: Icons.public),
          _row('f_father_status', 'Father Status', f.fatherStatus, section: 'family', apiField: 'fatherstatus', icon: Icons.person_outline),
          _row('f_father_name', 'Father Name', f.fatherName, section: 'family', apiField: 'fathername', icon: Icons.person),
          _row('f_father_edu', 'Father Education', f.fatherEducation, section: 'family', apiField: 'fathereducation', icon: Icons.school_outlined),
          _row('f_father_occ', 'Father Occupation', f.fatherOccupation, section: 'family', apiField: 'fatheroccupation', icon: Icons.work_outline),
          _row('f_mother_status', 'Mother Status', f.motherStatus, section: 'family', apiField: 'motherstatus', icon: Icons.person_outline),
          _row('f_mother_caste', 'Mother Caste', f.motherCaste, section: 'family', apiField: 'mothercaste', icon: Icons.people_outline),
          _row('f_mother_edu', 'Mother Education', f.motherEducation, section: 'family', apiField: 'mothereducation', icon: Icons.school_outlined),
          _row('f_mother_occ', 'Mother Occupation', f.motherOccupation, section: 'family', apiField: 'motheroccupation', icon: Icons.work_outline),
        ],
      );

  Widget _buildLifestyle(Lifestyle ls) => _section(
        title: 'Lifestyle',
        icon: Icons.emoji_food_beverage,
        color: _kLifestyle,
        trailing: _chipButton(
          label: 'Edit all',
          icon: Icons.edit_outlined,
          onTap: () => _openLifestyleBulk(ls),
          color: _kLifestyle,
        ),
        rows: [
          _row('l_diet', 'Diet', ls.diet, section: 'lifestyle', apiField: 'diet', icon: Icons.restaurant, highlight: true),
          _row('l_smoke', 'Smoking', ls.smoke, section: 'lifestyle', apiField: 'smoke', icon: Icons.smoking_rooms),
          _row('l_smoke_type', 'Smoke Type', ls.smokeType, section: 'lifestyle', apiField: 'smoketype', icon: Icons.smoke_free),
          _row('l_drinks', 'Drinking', ls.drinks, section: 'lifestyle', apiField: 'drinks', icon: Icons.local_drink),
          _row('l_drink_type', 'Drink Type', ls.drinkType, section: 'lifestyle', apiField: 'drinktype', icon: Icons.wine_bar),
        ],
      );

  Future<void> _openBulkEditor({
    required String title,
    required Color color,
    required List<_BulkFieldConfig> fields,
    String description =
        'Update multiple fields in one go. Each change saves field-by-field.',
  }) async {
    final prov = context.read<UserDetailsProvider>();
    final controllers = {
      for (final f in fields)
        f.key: TextEditingController(text: _cleanInitial(f.initial)),
    };
    bool isSaving = false;
    String? error;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final viewInsets = MediaQuery.of(ctx).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: viewInsets),
          child: StatefulBuilder(
            builder: (ctx, setSheetState) {
              Future<void> submit() async {
                setSheetState(() {
                  isSaving = true;
                  error = null;
                });

                for (final f in fields) {
                  final value = controllers[f.key]!.text.trim();
                  if (value == _cleanInitial(f.initial)) continue;
                  final ok = await prov.updateField(
                    section: f.section,
                    field: f.apiField,
                    value: value,
                  );
                  if (!ok) {
                    setSheetState(() {
                      error = prov.updateError.isNotEmpty
                          ? prov.updateError
                          : 'Failed to update ${f.label}';
                      isSaving = false;
                    });
                    return;
                  }
                }

                setSheetState(() => isSaving = false);
                Navigator.pop(ctx, true);
              }

              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.tune, size: 18, color: color),
                        const SizedBox(width: 8),
                        Text(
                          title,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      description,
                      style: const TextStyle(fontSize: 13, color: Color(0xFF475569)),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: fields.map((f) {
                        return SizedBox(
                          width: MediaQuery.of(ctx).size.width > 720 ? 320 : double.infinity,
                          child: TextField(
                            controller: controllers[f.key],
                            keyboardType: f.multiline ? TextInputType.multiline : f.inputType,
                            maxLines: f.multiline ? 3 : 1,
                            decoration: InputDecoration(
                              labelText: f.label,
                              filled: true,
                              fillColor: Colors.grey.shade50,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(color: color),
                              ),
                              isDense: true,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF1F2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFFECBD3)),
                        ),
                        child: Text(
                          error ?? '',
                          style: const TextStyle(color: Color(0xFFB91C1C), fontSize: 12.5),
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: isSaving ? null : submit,
                        icon: isSaving
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.save_outlined, size: 16),
                        label: Text(isSaving ? 'Saving...' : 'Save Changes'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: color,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                ),
              );
            },
          ),
        );
      },
    );

    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$title updated'),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<void> _openPartnerEdit(PartnerPreference pp) async {
    final prov = context.read<UserDetailsProvider>();
    final fields = [
      {'key': 'minAge', 'label': 'Min Age', 'api': 'minage', 'initial': pp.minAge == 0 ? '' : pp.minAge.toString(), 'type': TextInputType.number},
      {'key': 'maxAge', 'label': 'Max Age', 'api': 'maxage', 'initial': pp.maxAge == 0 ? '' : pp.maxAge.toString(), 'type': TextInputType.number},
      {'key': 'minHeight', 'label': 'Min Height (cm)', 'api': 'minheight', 'initial': pp.minHeight == 0 ? '' : pp.minHeight.toString(), 'type': TextInputType.number},
      {'key': 'maxHeight', 'label': 'Max Height (cm)', 'api': 'maxheight', 'initial': pp.maxHeight == 0 ? '' : pp.maxHeight.toString(), 'type': TextInputType.number},
      {'key': 'maritalStatus', 'label': 'Marital Status', 'api': 'maritalstatus', 'initial': pp.maritalStatus, 'type': TextInputType.text},
      {'key': 'profileWithChild', 'label': 'Profile With Child', 'api': 'profilewithchild', 'initial': pp.profileWithChild, 'type': TextInputType.text},
      {'key': 'familyType', 'label': 'Family Type', 'api': 'familytype', 'initial': pp.familyType, 'type': TextInputType.text},
      {'key': 'religion', 'label': 'Religion', 'api': 'religion', 'initial': pp.religion, 'type': TextInputType.text},
      {'key': 'caste', 'label': 'Caste', 'api': 'caste', 'initial': pp.caste, 'type': TextInputType.text},
      {'key': 'motherTongue', 'label': 'Mother Tongue', 'api': 'mothertoungue', 'initial': pp.motherTongue, 'type': TextInputType.text},
      {'key': 'country', 'label': 'Country', 'api': 'country', 'initial': pp.country, 'type': TextInputType.text},
      {'key': 'state', 'label': 'State', 'api': 'state', 'initial': pp.state, 'type': TextInputType.text},
      {'key': 'city', 'label': 'City', 'api': 'city', 'initial': pp.city, 'type': TextInputType.text},
      {'key': 'qualification', 'label': 'Qualification', 'api': 'qualification', 'initial': pp.qualification, 'type': TextInputType.text},
      {'key': 'educationMedium', 'label': 'Education Medium', 'api': 'educationmedium', 'initial': pp.educationMedium, 'type': TextInputType.text},
      {'key': 'profession', 'label': 'Profession', 'api': 'proffession', 'initial': pp.profession, 'type': TextInputType.text},
      {'key': 'workingWith', 'label': 'Working With', 'api': 'workingwith', 'initial': pp.workingWith, 'type': TextInputType.text},
      {'key': 'annualIncome', 'label': 'Annual Income', 'api': 'annualincome', 'initial': pp.annualIncome, 'type': TextInputType.text},
      {'key': 'diet', 'label': 'Diet', 'api': 'diet', 'initial': pp.diet, 'type': TextInputType.text},
      {'key': 'smokeAccept', 'label': 'Smoke Acceptable', 'api': 'smokeaccept', 'initial': pp.smokeAccept, 'type': TextInputType.text},
      {'key': 'drinkAccept', 'label': 'Drink Acceptable', 'api': 'drinkaccept', 'initial': pp.drinkAccept, 'type': TextInputType.text},
      {'key': 'disabilityAccept', 'label': 'Disability Acceptable', 'api': 'disabilityaccept', 'initial': pp.disabilityAccept, 'type': TextInputType.text},
      {'key': 'complexion', 'label': 'Complexion', 'api': 'complexion', 'initial': pp.complexion, 'type': TextInputType.text},
      {'key': 'bodyType', 'label': 'Body Type', 'api': 'bodytype', 'initial': pp.bodyType, 'type': TextInputType.text},
      {'key': 'manglik', 'label': 'Manglik', 'api': 'manglik', 'initial': pp.manglik, 'type': TextInputType.text},
      {'key': 'hersCopeBelief', 'label': 'Horoscope Belief', 'api': 'herscopeblief', 'initial': pp.hersCopeBelief, 'type': TextInputType.text},
      {'key': 'otherExpectation', 'label': 'Other Expectations', 'api': 'otherexpectation', 'initial': pp.otherExpectation, 'type': TextInputType.multiline},
    ];

    final controllers = {
      for (final f in fields)
        f['key'] as String: TextEditingController(
          text: (f['initial'] as String).isNotEmpty && (f['initial'] as String) != 'Not available'
              ? f['initial'] as String
              : '',
        )
    };

    bool isSaving = false;
    String? error;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final viewInsets = MediaQuery.of(ctx).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: viewInsets),
          child: StatefulBuilder(
            builder: (ctx, setSheetState) {
              Future<void> submit() async {
                setSheetState(() {
                  isSaving = true;
                  error = null;
                });

                for (final f in fields) {
                  final key = f['key'] as String;
                  final api = f['api'] as String;
                  final section = 'partner';
                  final value = controllers[key]!.text.trim();
                  final initial = f['initial'] as String;
                  if (value == initial) continue;
                  final ok = await prov.updateField(
                    section: section,
                    field: api,
                    value: value,
                  );
                  if (!ok) {
                    setSheetState(() {
                      error = prov.updateError.isNotEmpty ? prov.updateError : 'Failed to update ${f['label']}';
                      isSaving = false;
                    });
                    return;
                  }
                }

                setSheetState(() => isSaving = false);
                Navigator.pop(ctx, true);
              }

              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.favorite, size: 18, color: _kPartner),
                        SizedBox(width: 8),
                        Text(
                          'Edit Partner Preferences',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Update all partner expectations in one place. Changes save field-by-field.',
                      style: TextStyle(fontSize: 13, color: Color(0xFF475569)),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: fields.map((f) {
                        final key = f['key'] as String;
                        final type = f['type'] as TextInputType;
                        return SizedBox(
                          width: MediaQuery.of(ctx).size.width > 720 ? 320 : double.infinity,
                          child: TextField(
                            controller: controllers[key],
                            keyboardType: type == TextInputType.multiline ? TextInputType.multiline : type,
                            maxLines: type == TextInputType.multiline ? 3 : 1,
                            decoration: InputDecoration(
                              labelText: f['label'] as String,
                              filled: true,
                              fillColor: Colors.grey.shade50,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: _kPrimary, width: 1.4),
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            ),
                            style: const TextStyle(fontSize: 13.5),
                          ),
                        );
                      }).toList(),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 12),
                      Text(error!, style: const TextStyle(color: _kRose, fontWeight: FontWeight.w600)),
                    ],
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: isSaving ? null : () => Navigator.pop(ctx, false),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              side: const BorderSide(color: Color(0xFFE2E8F0)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: isSaving ? null : submit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _kPartner,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              elevation: 0,
                            ),
                            child: isSaving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Text('Save All'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );

    for (final ctrl in controllers.values) {
      ctrl.dispose();
    }

    if (saved == true && mounted) {
      await prov.fetchUserDetails(widget.userId, widget.myId);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Partner preferences updated'),
          backgroundColor: _kPartner,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }
  }

  Widget _buildPartner(PartnerPreference pp) => _section(
        title: 'Partner Preferences',
        icon: Icons.favorite,
        color: _kPartner,
        trailing: _chipButton(
          label: 'Edit all',
          icon: Icons.edit_outlined,
          onTap: () => _openPartnerEdit(pp),
          color: _kPartner,
        ),
        rows: [
          _row('pp_age', 'Age Range', pp.ageRange, section: 'partner', apiField: 'age_range', icon: Icons.calendar_today, highlight: true),
          _row('pp_height', 'Height Range', pp.heightRange, section: 'partner', apiField: 'height_range', icon: Icons.height),
          _row('pp_marital', 'Marital Status', pp.maritalStatus, section: 'partner', apiField: 'maritalstatus', icon: Icons.favorite_border),
          _row('pp_child', 'Profile With Child', pp.profileWithChild, section: 'partner', apiField: 'profilewithchild', icon: Icons.child_care),
          _row('pp_family', 'Family Type', pp.familyType, section: 'partner', apiField: 'familytype', icon: Icons.home_outlined),
          _row('pp_religion', 'Religion', pp.religion, section: 'partner', apiField: 'religion', icon: Icons.flag),
          _row('pp_caste', 'Caste', pp.caste, section: 'partner', apiField: 'caste', icon: Icons.people),
          _row('pp_tongue', 'Mother Tongue', pp.motherTongue, section: 'partner', apiField: 'mothertoungue', icon: Icons.language),
          _row('pp_country', 'Country', pp.country, section: 'partner', apiField: 'country', icon: Icons.public),
          _row('pp_state', 'State', pp.state, section: 'partner', apiField: 'state', icon: Icons.map_outlined),
          _row('pp_city', 'City', pp.city, section: 'partner', apiField: 'city', icon: Icons.location_city),
          _row('pp_qual', 'Qualification', pp.qualification, section: 'partner', apiField: 'qualification', icon: Icons.school_outlined),
          _row('pp_edu_medium', 'Education Medium', pp.educationMedium, section: 'partner', apiField: 'educationmedium', icon: Icons.translate),
          _row('pp_profession', 'Profession', pp.profession, section: 'partner', apiField: 'proffession', icon: Icons.business_center_outlined),
          _row('pp_workwith', 'Working With', pp.workingWith, section: 'partner', apiField: 'workingwith', icon: Icons.corporate_fare),
          _row('pp_income', 'Annual Income', pp.annualIncome, section: 'partner', apiField: 'annualincome', icon: Icons.currency_rupee),
          _row('pp_diet', 'Diet', pp.diet, section: 'partner', apiField: 'diet', icon: Icons.restaurant_menu),
          _row('pp_smoke', 'Smoke Acceptable', pp.smokeAccept, section: 'partner', apiField: 'smokeaccept', icon: Icons.smoking_rooms),
          _row('pp_drink', 'Drink Acceptable', pp.drinkAccept, section: 'partner', apiField: 'drinkaccept', icon: Icons.local_bar),
          _row('pp_disability', 'Disability Acceptable', pp.disabilityAccept, section: 'partner', apiField: 'disabilityaccept', icon: Icons.accessible_forward),
          _row('pp_complexion', 'Complexion', pp.complexion, section: 'partner', apiField: 'complexion', icon: Icons.palette_outlined),
          _row('pp_body', 'Body Type', pp.bodyType, section: 'partner', apiField: 'bodytype', icon: Icons.accessibility_new),
          _row('pp_manglik', 'Manglik', pp.manglik, section: 'partner', apiField: 'manglik', icon: Icons.star_border),
          _row('pp_herscope', 'Hers Cope Belief', pp.hersCopeBelief, section: 'partner', apiField: 'herscopeblief', icon: Icons.psychology_outlined),
          if (pp.otherExpectation.isNotEmpty && pp.otherExpectation != 'Not available')
            _row('pp_other', 'Other Expectations', pp.otherExpectation, section: 'partner', apiField: 'otherexpectation', icon: Icons.notes),
        ],
      );

  Future<void> _openPersonalBulk(PersonalDetail p) {
    return _openBulkEditor(
      title: 'Edit Personal Details',
      color: _kPersonal,
      description: 'Quickly adjust core personal fields in a single sheet.',
      fields: [
        _BulkFieldConfig(key: 'height', label: 'Height', apiField: 'height_name', section: 'personal', initial: p.heightName),
        _BulkFieldConfig(key: 'birthDate', label: 'Birth Date', apiField: 'birthDate', section: 'personal', initial: p.birthDate),
        _BulkFieldConfig(key: 'birthTime', label: 'Birth Time', apiField: 'birthtime', section: 'personal', initial: p.birthtime),
        _BulkFieldConfig(key: 'birthCity', label: 'Birth City', apiField: 'birthcity', section: 'personal', initial: p.birthcity),
        _BulkFieldConfig(key: 'religion', label: 'Religion', apiField: 'religionName', section: 'personal', initial: p.religionName),
        _BulkFieldConfig(key: 'community', label: 'Community', apiField: 'communityName', section: 'personal', initial: p.communityName),
        _BulkFieldConfig(key: 'subCommunity', label: 'Sub Community', apiField: 'subCommunityName', section: 'personal', initial: p.subCommunityName),
        _BulkFieldConfig(key: 'motherTongue', label: 'Mother Tongue', apiField: 'motherTongue', section: 'personal', initial: p.motherTongue),
        _BulkFieldConfig(key: 'bloodGroup', label: 'Blood Group', apiField: 'bloodGroup', section: 'personal', initial: p.bloodGroup),
        _BulkFieldConfig(key: 'maritalStatus', label: 'Marital Status', apiField: 'maritalStatusName', section: 'personal', initial: p.maritalStatusName),
        _BulkFieldConfig(key: 'manglik', label: 'Manglik', apiField: 'manglik', section: 'personal', initial: p.manglik),
        _BulkFieldConfig(key: 'disability', label: 'Disability', apiField: 'Disability', section: 'personal', initial: p.disability),
        _BulkFieldConfig(key: 'photoRequest', label: 'Photo Request', apiField: 'photo_request', section: 'personal', initial: p.photoRequest),
        _BulkFieldConfig(key: 'privacy', label: 'Privacy Setting', apiField: 'privacy', section: 'personal', initial: p.privacy),
      ],
    );
  }

  Future<void> _openEducationBulk(PersonalDetail p) {
    return _openBulkEditor(
      title: 'Edit Education & Career',
      color: _kEducation,
      description: 'Bulk edit education and career information.',
      fields: [
        _BulkFieldConfig(key: 'educationType', label: 'Education Type', apiField: 'educationtype', section: 'personal', initial: p.educationType),
        _BulkFieldConfig(key: 'degree', label: 'Degree', apiField: 'degree', section: 'personal', initial: p.degree),
        _BulkFieldConfig(key: 'faculty', label: 'Faculty', apiField: 'faculty', section: 'personal', initial: p.faculty),
        _BulkFieldConfig(key: 'educationMedium', label: 'Education Medium', apiField: 'educationmedium', section: 'personal', initial: p.educationMedium),
        _BulkFieldConfig(key: 'areYouWorking', label: 'Are You Working?', apiField: 'areyouworking', section: 'personal', initial: p.areYouWorking),
        _BulkFieldConfig(key: 'occupationType', label: 'Occupation Type', apiField: 'occupationtype', section: 'personal', initial: p.occupationType),
        _BulkFieldConfig(key: 'workingWith', label: 'Working With', apiField: 'workingwith', section: 'personal', initial: p.workingWith),
        _BulkFieldConfig(key: 'companyName', label: 'Company Name', apiField: 'companyname', section: 'personal', initial: p.companyName),
        _BulkFieldConfig(key: 'designation', label: 'Designation', apiField: 'designation', section: 'personal', initial: p.designation),
        _BulkFieldConfig(key: 'businessName', label: 'Business Name', apiField: 'businessname', section: 'personal', initial: p.businessName),
        _BulkFieldConfig(key: 'annualIncome', label: 'Annual Income', apiField: 'annualincome', section: 'personal', initial: p.annualIncome),
      ],
    );
  }

  Future<void> _openFamilyBulk(FamilyDetail f) {
    return _openBulkEditor(
      title: 'Edit Family Details',
      color: _kFamily,
      description: 'Manage family background fields together.',
      fields: [
        _BulkFieldConfig(key: 'familyType', label: 'Family Type', apiField: 'familytype', section: 'family', initial: f.familyType),
        _BulkFieldConfig(key: 'familyBackground', label: 'Family Background', apiField: 'familybackground', section: 'family', initial: f.familyBackground),
        _BulkFieldConfig(key: 'familyOrigin', label: 'Family Origin', apiField: 'familyorigin', section: 'family', initial: f.familyOrigin),
        _BulkFieldConfig(key: 'fatherStatus', label: 'Father Status', apiField: 'fatherstatus', section: 'family', initial: f.fatherStatus),
        _BulkFieldConfig(key: 'fatherName', label: 'Father Name', apiField: 'fathername', section: 'family', initial: f.fatherName),
        _BulkFieldConfig(key: 'fatherEducation', label: 'Father Education', apiField: 'fathereducation', section: 'family', initial: f.fatherEducation),
        _BulkFieldConfig(key: 'fatherOccupation', label: 'Father Occupation', apiField: 'fatheroccupation', section: 'family', initial: f.fatherOccupation),
        _BulkFieldConfig(key: 'motherStatus', label: 'Mother Status', apiField: 'motherstatus', section: 'family', initial: f.motherStatus),
        _BulkFieldConfig(key: 'motherCaste', label: 'Mother Caste', apiField: 'mothercaste', section: 'family', initial: f.motherCaste),
        _BulkFieldConfig(key: 'motherEducation', label: 'Mother Education', apiField: 'mothereducation', section: 'family', initial: f.motherEducation),
        _BulkFieldConfig(key: 'motherOccupation', label: 'Mother Occupation', apiField: 'motheroccupation', section: 'family', initial: f.motherOccupation),
      ],
    );
  }

  Future<void> _openLifestyleBulk(Lifestyle ls) {
    return _openBulkEditor(
      title: 'Edit Lifestyle',
      color: _kLifestyle,
      description: 'Update diet, smoking and drinking choices together.',
      fields: [
        _BulkFieldConfig(key: 'diet', label: 'Diet', apiField: 'diet', section: 'lifestyle', initial: ls.diet),
        _BulkFieldConfig(key: 'smoke', label: 'Smoking', apiField: 'smoke', section: 'lifestyle', initial: ls.smoke),
        _BulkFieldConfig(key: 'smokeType', label: 'Smoke Type', apiField: 'smoketype', section: 'lifestyle', initial: ls.smokeType),
        _BulkFieldConfig(key: 'drinks', label: 'Drinking', apiField: 'drinks', section: 'lifestyle', initial: ls.drinks),
        _BulkFieldConfig(key: 'drinkType', label: 'Drink Type', apiField: 'drinktype', section: 'lifestyle', initial: ls.drinkType),
      ],
    );
  }

  // ── documents section ────────────────────────────────────────────────────────

  Widget _buildDocumentsSection() {
    return Container(
      decoration: const BoxDecoration(
        border: Border(left: BorderSide(color: _kDocs, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            color: _kDocs.withOpacity(0.05),
            child: Row(
              children: [
                const Icon(Icons.description_outlined, size: 17, color: _kDocs),
                const SizedBox(width: 10),
                const Text(
                  'Submitted Documents',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _kDocs,
                    letterSpacing: 0.2,
                  ),
                ),
                const Spacer(),
                Consumer<DocumentsProvider>(
                  builder: (_, dp, __) => dp.isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : IconButton(
                          icon: const Icon(Icons.refresh, size: 16),
                          color: _kDocs,
                          tooltip: 'Refresh documents',
                          onPressed: () => dp.fetchDocuments(),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Consumer<DocumentsProvider>(
              builder: (_, dp, __) {
                if (dp.isLoading) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  );
                }
                final docs = dp.documentsForUser(widget.userId);
                if (docs.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(Icons.folder_open_outlined,
                              size: 36, color: Colors.grey.shade300),
                          const SizedBox(height: 8),
                          Text('No documents submitted',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade400)),
                        ],
                      ),
                    ),
                  );
                }
                return Column(
                  children: docs.map((doc) => _docCard(doc)).toList(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _docCard(Document doc) {
    final statusColor = doc.isApproved
        ? const Color(0xFF10B981)
        : doc.isRejected
            ? const Color(0xFFEF4444)
            : const Color(0xFFF59E0B);
    final statusIcon = doc.isApproved
        ? Icons.verified_outlined
        : doc.isRejected
            ? Icons.cancel_outlined
            : Icons.pending_outlined;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail
            GestureDetector(
              onTap: () => _showDocPreview(doc.fullPhotoUrl),
              child: Stack(
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.white,
                      border: Border.all(color: Colors.grey.shade200),
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
                        errorBuilder: (_, __, ___) => Center(
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
                        ),
                      ),
                      child: const Icon(Icons.zoom_in,
                          size: 11, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 14),

            // Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.badge_outlined,
                          size: 14, color: _kDocs),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          doc.documentType.isNotEmpty
                              ? doc.documentType
                              : '—',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.numbers_outlined,
                          size: 13, color: Colors.teal.shade400),
                      const SizedBox(width: 6),
                      Text(
                        doc.documentIdNumber.isNotEmpty
                            ? doc.documentIdNumber
                            : '—',
                        style: TextStyle(
                            fontSize: 12.5,
                            color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Status badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(12),
                      border:
                          Border.all(color: statusColor.withOpacity(0.30)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(statusIcon, size: 12, color: statusColor),
                        const SizedBox(width: 4),
                        Text(
                          doc.status.toUpperCase(),
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: statusColor),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Actions for pending docs — or lock indicator for approved docs
            if (doc.isPending)
              Consumer<DocumentsProvider>(
                builder: (_, dp, __) => dp.isActionLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child:
                            CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _docActionBtn(
                            icon: Icons.check_circle_outline,
                            label: 'Approve',
                            color: const Color(0xFF10B981),
                            onTap: () => _approveDocFromProfile(doc, dp),
                          ),
                          const SizedBox(height: 6),
                          _docActionBtn(
                            icon: Icons.cancel_outlined,
                            label: 'Reject',
                            color: const Color(0xFFEF4444),
                            onTap: () => _rejectDocFromProfile(doc, dp),
                          ),
                        ],
                      ),
              )
            else if (doc.isApproved)
              Tooltip(
                message: 'Document is permanently locked after verification',
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withOpacity(0.08),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: const Color(0xFF10B981).withOpacity(0.25)),
                  ),
                  child: const Icon(Icons.lock_rounded,
                      size: 16, color: Color(0xFF10B981)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _docActionBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withOpacity(0.25)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 4),
              Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: color)),
            ],
          ),
        ),
      );

  void _showDocPreview(String url) {
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
                  color: Colors.white,
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
                            color: Colors.grey[100],
                            child: const Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.broken_image,
                                      size: 48, color: Colors.grey),
                                  SizedBox(height: 8),
                                  Text('Image not available',
                                      style:
                                          TextStyle(color: Colors.grey)),
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
                  decoration: const BoxDecoration(
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

  Future<void> _approveDocFromProfile(
      Document doc, DocumentsProvider dp) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Approve Document',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: const Text('Approve this document?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final ok = await dp.updateDocumentStatus(
        documentId: doc.documentId, action: 'approve');
    if (mounted) {
      if (ok) {
        // Sync the isVerified badge in the profile header.
        context.read<UserDetailsProvider>().fetchUserDetails(widget.userId, widget.myId);
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            ok ? 'Document approved' : 'Failed: ${dp.error}'),
        backgroundColor:
            ok ? const Color(0xFF10B981) : const Color(0xFFEF4444),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ));
    }
  }

  Future<void> _rejectDocFromProfile(
      Document doc, DocumentsProvider dp) async {
    _rejectDocCtrl.clear();
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
            const Text('Reason for rejection:',
                style: TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 8),
            TextField(
              controller: _rejectDocCtrl,
              maxLines: 3,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Enter rejection reason…',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)),
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
              if (_rejectDocCtrl.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please enter a rejection reason'),
                    backgroundColor: Color(0xFFEF4444),
                  ),
                );
                return;
              }
              Navigator.pop(context);
              if (!mounted) return;
              final ok = await dp.updateDocumentStatus(
                documentId: doc.documentId,
                action: 'reject',
                rejectReason: _rejectDocCtrl.text.trim(),
              );
              if (mounted) {
                if (ok) {
                  // Sync the isVerified badge in the profile header.
                  context.read<UserDetailsProvider>().fetchUserDetails(widget.userId, widget.myId);
                }
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(
                      ok ? 'Document rejected' : 'Failed: ${dp.error}'),
                  backgroundColor: ok
                      ? const Color(0xFFF59E0B)
                      : const Color(0xFFEF4444),
                  behavior: SnackBarBehavior.floating,
                  margin: const EdgeInsets.all(16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ));
              }
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
                foregroundColor: Colors.white),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
  }

  // ── loading / error ───────────────────────────────────────────────────────────

  Widget _buildLoading() => const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 44,
              height: 44,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(_kPrimary),
              ),
            ),
            SizedBox(height: 16),
            Text('Loading Profile…',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Colors.grey)),
          ],
        ),
      );

  Widget _buildError(UserDetailsProvider prov) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.red.shade400),
              const SizedBox(height: 16),
              Text(prov.error,
                  style: const TextStyle(fontSize: 15, color: Colors.red),
                  textAlign: TextAlign.center),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Retry'),
                onPressed: () => prov.fetchUserDetails(widget.userId, widget.myId),
                style: ElevatedButton.styleFrom(
                    backgroundColor: _kPrimary, foregroundColor: Colors.white),
              ),
            ],
          ),
        ),
      );

  // ── build ────────────────────────────────────────────────────────────────────

  Widget _buildBody(UserDetailsProvider provider, UserDetailsData data) {
    final p = data.personalDetail;
    final contact = data.contactDetail.withFallback(
      email: widget.email,
      phone: widget.phone,
      whatsapp: widget.whatsapp,
    );
    return SingleChildScrollView(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.10),
                  blurRadius: 24,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                _buildHeader(p, contact),
                _buildDocumentsSection(),
                const Divider(height: 1, thickness: 1),
                _buildMediaAndActivity(p, provider),
                _buildAdminActions(p, provider),
                const Divider(height: 1, thickness: 1),
                _buildPersonal(p),
                const Divider(height: 1, thickness: 1),
                _buildEducation(p),
                const Divider(height: 1, thickness: 1),
                _buildFamily(data.familyDetail),
                const Divider(height: 1, thickness: 1),
                _buildLifestyle(data.lifestyle),
                const Divider(height: 1, thickness: 1),
                _buildPartner(data.partner),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<UserDetailsProvider>();

    return Scaffold(
      backgroundColor: _kPageBg,
      appBar: AppBar(
        title: const Text('User Profile',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.grey.shade800,
        elevation: 0,
        scrolledUnderElevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => provider.fetchUserDetails(widget.userId, widget.myId),
          ),
        ],
      ),
      body: provider.isLoading
          ? _buildLoading()
          : provider.error.isNotEmpty
              ? _buildError(provider)
              : provider.userDetails != null
                  ? _buildBody(provider, provider.userDetails!)
                  : Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.person_off, size: 48, color: Colors.grey.shade400),
                          const SizedBox(height: 16),
                          const Text('No data available',
                              style: TextStyle(fontSize: 15, color: Colors.grey)),
                        ],
                      ),
                    ),
    );
  }
}
