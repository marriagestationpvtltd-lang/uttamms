import 'package:adminmrz/users/userdetails/detailscreen.dart';
import 'package:adminmrz/users/userdetails/userdetailprovider.dart';
import 'package:adminmrz/users/userprovider.dart';
import 'package:adminmrz/auth/service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'model/usermodel.dart';
import 'userdetails/detailmodel.dart';
import 'package:adminmrz/config/app_endpoints.dart';

const _kPrimary = Color(0xFF6366F1);
const _kPrimaryDark = Color(0xFF4F46E5);
const _kViolet = Color(0xFF8B5CF6);
const _kEmerald = Color(0xFF10B981);
const _kAmber = Color(0xFFF59E0B);
const _kRose = Color(0xFFEF4444);
const _kSky = Color(0xFF0EA5E9);
const _kActionButtonTextBlendFactor = 0.25;
const _kActionButtonMinWidth = 118.0;
const _kActionButtonSpacing = 10.0;
const _kActionButtonVerticalSpacing = 8.0;

class UsersPage extends StatefulWidget {
  /// Called when admin taps "Direct Chat" on a member card.
  /// The [userId] is the member's ID. DashboardPage should switch to the
  /// Chat tab and open that user's conversation.
  final void Function(int userId)? onOpenChat;

  const UsersPage({Key? key, this.onOpenChat}) : super(key: key);

  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<UserProvider>().fetchUsers();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _navigateToUser(User user) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChangeNotifierProvider(
          create: (context) => UserDetailsProvider(),
          child: UserDetailsScreen(
            userId: user.id,
            myId: user.id,
            onOpenChat: widget.onOpenChat,
            email: user.email,
            phone: user.phone,
          ),
        ),
      ),
    );
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty || dateStr == 'null') return '—';
    try {
      final dt = DateTime.parse(dateStr);
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
    } catch (_) {
      return dateStr.length > 10 ? dateStr.substring(0, 10) : dateStr;
    }
  }

  String _cleanPhone(String? phone) {
    if (phone == null || phone.isEmpty || phone == 'null') return '';
    return phone.replaceAll(RegExp(r'[^\d+]'), '');
  }

  /// Normalises a profile-picture path that may be either a full URL or a
  /// server-relative path (e.g. "/uploads/photo.jpg").  The chat section uses
  /// ${kAdminApiBaseUrl}/get.php which returns full URLs; the admin API
  /// may return relative paths – we handle both here.
  static const _kImgBase = '${kAdminApiBaseUrl}';

  String? _normaliseImageUrl(String? raw) {
    if (raw == null || raw.isEmpty || raw == 'null') return null;
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    // Relative path: prepend domain
    final path = raw.startsWith('/') ? raw : '/$raw';
    return '$_kImgBase$path';
  }

  Future<void> _launchWhatsApp(String phone) async {
    final cleaned = _cleanPhone(phone);
    if (cleaned.isEmpty) return;
    final uri = Uri.parse('https://wa.me/$cleaned');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _launchViber(String phone) async {
    final cleaned = _cleanPhone(phone);
    if (cleaned.isEmpty) return;
    final uri = Uri.parse('viber://chat?number=$cleaned');
    bool launched = false;
    if (await canLaunchUrl(uri)) {
      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Viber app is not installed on this device'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _launchEmail(String email) async {
    if (email.isEmpty) return;
    final uri = Uri(scheme: 'mailto', path: email);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  // ─── Verification badge ──────────────────────────────────────────────────

  Widget _verifiedBadge(bool isVerified) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isVerified
            ? Colors.green.withOpacity(0.1)
            : Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isVerified
              ? Colors.green.withOpacity(0.4)
              : Colors.red.withOpacity(0.4),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isVerified ? Icons.verified_rounded : Icons.cancel_outlined,
            size: 10,
            color: isVerified ? Colors.green : Colors.red,
          ),
          const SizedBox(width: 3),
          Text(
            isVerified ? 'Verified' : 'Unverified',
            style: TextStyle(
              fontSize: 10,
              color: isVerified ? Colors.green.shade700 : Colors.red.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sendVerifyBtn(BuildContext ctx, String type) {
    return GestureDetector(
      onTap: () {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
            content: Text('Verification request sent for $type'),
            backgroundColor: _kPrimary,
            duration: const Duration(seconds: 2),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: _kPrimary.withOpacity(0.08),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: _kPrimary.withOpacity(0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.send_rounded, size: 10, color: _kPrimaryDark),
            const SizedBox(width: 3),
            Text(
              'Send Verification Request',
              style: TextStyle(
                fontSize: 10,
                color: _kPrimaryDark,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Communication button ────────────────────────────────────────────────

  Widget _commBtn({
    required IconData icon,
    required String tooltip,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: color.withOpacity(0.10),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.25)),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
      ),
    );
  }

  // ─── User Card ───────────────────────────────────────────────────────────

  Widget _buildUserCard(User user, UserProvider provider) {
    provider.preloadActivity(user.id);
    final activity = provider.activityFor(user.id);
    final isActivityLoading = provider.isActivityLoading(user.id);
    final bool isSelected = provider.isUserSelected(user.id);
    final Color statusColor = user.statusColor;
    final bool isFemale = user.gender.toLowerCase() == 'female';
    final String cleanedPhone = _cleanPhone(user.phone);
    final bool hasPhone = cleanedPhone.isNotEmpty;
    final bool isEmailVerified = user.emailVerified == 1;
    final bool isPhoneVerified = user.phoneVerified == 1;
    final Color genderAccentColor = isFemale ? _kRose : _kSky;
    final String? profileImageUrl = _normaliseImageUrl(user.profilePicture);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = Theme.of(context).colorScheme.surface;
    final bool hasPhoto = user.hasProfilePicture;
    final bool isActioning = provider.isPhotoActioning(user.id);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            cardBg,
            isDark ? const Color(0xFF0B1222) : Colors.grey.shade50
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected
              ? _kPrimary.withOpacity(0.7)
              : (isDark
                  ? Colors.white.withOpacity(0.06)
                  : Colors.grey.shade200),
          width: isSelected ? 1.4 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isSelected ? 0.10 : 0.06),
            blurRadius: isSelected ? 14 : 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _navigateToUser(user),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── THREE-COLUMN LAYOUT ───────────────────────────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── LEFT: Checkbox + Photo + Status ──────────────────
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Checkbox
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => provider.toggleUserSelection(user.id),
                          child: Container(
                            height: 24,
                            width: 24,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? _kPrimary.withOpacity(0.12)
                                  : (isDark
                                      ? Colors.white.withOpacity(0.04)
                                      : Colors.grey.shade100),
                              borderRadius: BorderRadius.circular(7),
                              border: Border.all(
                                color: isSelected
                                    ? _kPrimary
                                    : Colors.grey.shade400.withOpacity(0.6),
                              ),
                            ),
                            child: Checkbox(
                              value: isSelected,
                              onChanged: (_) =>
                                  provider.toggleUserSelection(user.id),
                              activeColor: _kPrimary,
                              checkColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(5),
                              ),
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Profile photo with popup menu for approve/reject
                        PopupMenuButton<String>(
                          offset: const Offset(44, 44),
                          tooltip: 'Photo actions',
                          enabled: !isActioning,
                          onSelected: (action) =>
                              _handleCardPhotoAction(action, user, provider),
                          itemBuilder: (_) => [
                            if (hasPhoto && user.status != 'approved')
                              PopupMenuItem(
                                value: 'approve',
                                height: 40,
                                child: Row(children: [
                                  Icon(Icons.check_circle_outline,
                                      color: _kEmerald, size: 17),
                                  const SizedBox(width: 8),
                                  const Text('Approve Photo',
                                      style: TextStyle(fontSize: 13)),
                                ]),
                              ),
                            if (hasPhoto && user.status != 'rejected')
                              PopupMenuItem(
                                value: 'reject',
                                height: 40,
                                child: Row(children: [
                                  Icon(Icons.cancel_outlined,
                                      color: _kRose, size: 17),
                                  const SizedBox(width: 8),
                                  const Text('Reject Photo',
                                      style: TextStyle(fontSize: 13)),
                                ]),
                              ),
                            if (hasPhoto) const PopupMenuDivider(height: 1),
                            PopupMenuItem(
                              value: 'view',
                              height: 40,
                              child: Row(children: [
                                Icon(Icons.person_outline,
                                    color: _kPrimary, size: 17),
                                const SizedBox(width: 8),
                                const Text('View Profile',
                                    style: TextStyle(fontSize: 13)),
                              ]),
                            ),
                          ],
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                width: 62,
                                height: 62,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    colors: isFemale
                                        ? [
                                            const Color(0xFFFCE7F3),
                                            const Color(0xFFFFF1F2)
                                          ]
                                        : [
                                            const Color(0xFFE0F2FE),
                                            const Color(0xFFEEF2FF)
                                          ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  border: Border.all(
                                    color: genderAccentColor.withOpacity(0.45),
                                    width: 2,
                                  ),
                                ),
                                child: ClipOval(
                                  child: profileImageUrl != null
                                      ? Image.network(
                                          profileImageUrl,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) =>
                                              _avatarIcon(isFemale),
                                        )
                                      : _avatarIcon(isFemale),
                                ),
                              ),
                              if (isActioning)
                                Positioned.fill(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.4),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Center(
                                      child: SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white),
                                      ),
                                    ),
                                  ),
                                )
                              else
                                Positioned(
                                  bottom: -2,
                                  right: -2,
                                  child: Container(
                                    padding: const EdgeInsets.all(3),
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? const Color(0xFF0F172A)
                                          : Colors.white,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                            color:
                                                Colors.black.withOpacity(0.08),
                                            blurRadius: 4)
                                      ],
                                    ),
                                    child: Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        color: user.isOnline == 1
                                            ? _kEmerald
                                            : Colors.grey.shade400,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                            color: Colors.white, width: 1.5),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 5),
                        // Photo status label
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                                color: statusColor.withOpacity(0.30)),
                          ),
                          child: Text(
                            user.status.replaceAll('_', ' ').toUpperCase(),
                            style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: statusColor),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    // ── MIDDLE: Identity + Contact + Info chips ───────────
                    Expanded(
                      flex: 5,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Name + status badge
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  user.fullName,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: isDark
                                        ? Colors.white
                                        : const Color(0xFF0B1222),
                                    letterSpacing: 0.2,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              _badge(user.formattedStatus, statusColor),
                            ],
                          ),
                          const SizedBox(height: 4),
                          // ID + gender + last active
                          Wrap(
                            spacing: 5,
                            runSpacing: 4,
                            children: [
                              _softChip('#${user.id}',
                                  icon: Icons.badge_outlined, color: _kPrimary),
                              _softChip(user.gender,
                                  icon: isFemale ? Icons.female : Icons.male,
                                  color: genderAccentColor),
                              _softChip(
                                  'Active: ${_formatDate(user.lastLogin)}',
                                  icon: Icons.access_time,
                                  color: _kSky),
                            ],
                          ),
                          const SizedBox(height: 6),
                          // Email contact row
                          _contactRow(
                            icon: Icons.email_outlined,
                            value: user.email.isNotEmpty
                                ? user.email
                                : 'No email',
                            color: _kPrimary,
                            verified: isEmailVerified,
                            isDark: isDark,
                          ),
                          const SizedBox(height: 3),
                          // Phone contact row
                          _contactRow(
                            icon: Icons.phone_outlined,
                            value: hasPhone ? cleanedPhone : 'No phone',
                            color: _kEmerald,
                            verified: isPhoneVerified,
                            isDark: isDark,
                          ),
                          const SizedBox(height: 6),
                          // Info chips
                          Wrap(
                            spacing: 5,
                            runSpacing: 4,
                            children: [
                              _infoChip(
                                  Icons.calendar_today_outlined,
                                  'Reg: ${_formatDate(user.registrationDate)}',
                                  _kEmerald),
                              _infoChip(
                                user.isOnline == 1
                                    ? Icons.wifi_tethering
                                    : Icons.wifi_off,
                                user.isOnline == 1 ? 'Online' : 'Offline',
                                user.isOnline == 1 ? _kEmerald : Colors.grey,
                              ),
                              _infoChip(
                                  Icons.verified_outlined,
                                  user.isVerified == 1
                                      ? 'Verified'
                                      : 'Needs Review',
                                  user.isVerified == 1 ? _kEmerald : _kRose),
                              _infoChip(
                                user.usertype == 'paid'
                                    ? Icons.workspace_premium
                                    : Icons.person_outline,
                                user.usertype.toUpperCase(),
                                user.usertype == 'paid'
                                    ? _kAmber
                                    : Colors.grey.shade500,
                              ),
                              _accessLevelChip(user),
                              if (user.expiryDate != null &&
                                  user.expiryDate!.isNotEmpty &&
                                  user.expiryDate != 'null')
                                _infoChip(
                                    Icons.event_outlined,
                                    'Exp: ${_formatDate(user.expiryDate)}',
                                    _kViolet),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    // ── RIGHT: Compact activity stats ─────────────────────
                    Expanded(
                      flex: 3,
                      child: _buildCompactActivityGrid(
                          activity, isActivityLoading, isDark),
                    ),
                  ],
                ),

                // ── DIVIDER + ACTION BUTTONS ──────────────────────────────
                const SizedBox(height: 10),
                _divider(isDark),
                const SizedBox(height: 8),
                Wrap(
                  spacing: _kActionButtonSpacing,
                  runSpacing: _kActionButtonVerticalSpacing,
                  children: [
                    if (hasPhone) ...[
                      _actionIconBtn(
                        Icons.chat_rounded,
                        'WhatsApp',
                        const Color(0xFF25D366),
                        () => _launchWhatsApp(cleanedPhone),
                      ),
                      _actionIconBtn(
                        Icons.videocam_rounded,
                        'Viber',
                        const Color(0xFF7360F2),
                        () => _launchViber(cleanedPhone),
                      ),
                    ],
                    if (user.email.isNotEmpty)
                      _actionIconBtn(
                        Icons.email_outlined,
                        'Send Email',
                        _kAmber,
                        () => _launchEmail(user.email),
                      ),
                    _actionIconBtn(
                      Icons.chat_bubble_outline,
                      'Direct Chat',
                      _kEmerald,
                      () {
                        if (widget.onOpenChat != null) {
                          widget.onOpenChat!(user.id);
                        }
                      },
                    ),
                    _actionIconBtn(
                      Icons.visibility_outlined,
                      'View Profile',
                      _kPrimary,
                      () => _navigateToUser(user),
                    ),
                    if (hasPhoto && user.status == 'pending') ...[
                      _actionIconBtn(
                        Icons.check_circle_outline,
                        'Approve',
                        _kEmerald,
                        isActioning
                            ? null
                            : () => _handleCardPhotoAction(
                                'approve', user, provider),
                      ),
                      _actionIconBtn(
                        Icons.cancel_outlined,
                        'Reject',
                        _kRose,
                        isActioning
                            ? null
                            : () => _handleCardPhotoAction(
                                'reject', user, provider),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── New helpers for 3-column card ─────────────────────────────────────────

  Widget _contactRow({
    required IconData icon,
    required String value,
    required Color color,
    required bool verified,
    required bool isDark,
  }) {
    final missing = value == 'No email' || value == 'No phone';
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: color.withOpacity(0.10),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 12, color: color),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12,
              color: missing
                  ? Colors.grey.shade500
                  : (isDark
                      ? Colors.grey.shade200
                      : const Color(0xFF1F2937)),
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (!missing) _miniVerifiedDot(verified),
      ],
    );
  }

  Widget _buildCompactActivityGrid(
      ActivityStats? stats, bool loading, bool isDark) {
    final s = stats ?? ActivityStats.empty();
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : _kPrimary.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kPrimary.withOpacity(0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.timeline_outlined, color: _kPrimary, size: 13),
              const SizedBox(width: 4),
              const Text(
                'Activity',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                    color: _kPrimary),
              ),
              if (loading) ...[
                const Spacer(),
                const SizedBox(
                  height: 11,
                  width: 11,
                  child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(_kPrimary)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 7),
          _miniStatRow('Sent', s.requestsSent, _kPrimary, 'Rcvd',
              s.requestsReceived, _kViolet),
          const SizedBox(height: 4),
          _miniStatRow('Chat', s.chatRequestsSent, _kSky, 'Acc\'d',
              s.chatRequestsAccepted, _kEmerald),
          const SizedBox(height: 4),
          _miniStatRow('Views', s.profileViews, _kAmber, 'Match',
              s.matchesCount, _kRose),
        ],
      ),
    );
  }

  Widget _miniStatRow(
      String l1, int v1, Color c1, String l2, int v2, Color c2) {
    return Row(
      children: [
        Expanded(child: _miniStat(l1, v1, c1)),
        const SizedBox(width: 4),
        Expanded(child: _miniStat(l2, v2, c2)),
      ],
    );
  }

  Widget _miniStat(String label, int value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          Text(
            '$value',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: color),
          ),
          const SizedBox(width: 3),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                  fontSize: 10,
                  color: color.withOpacity(0.75),
                  fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleCardPhotoAction(
      String action, User user, UserProvider provider) async {
    if (action == 'view') {
      _navigateToUser(user);
      return;
    }
    if (action == 'approve') {
      final ok = await provider.approvePhoto(user.id, 'approve');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ok ? 'Photo approved' : 'Failed to approve photo'),
          backgroundColor: ok ? _kEmerald : _kRose,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          duration: const Duration(seconds: 3),
        ));
      }
      return;
    }
    if (action == 'reject') {
      final ctrl = TextEditingController();
      final reason = await showDialog<String>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Reject Profile Photo'),
          content: TextField(
            controller: ctrl,
            maxLines: 3,
            autofocus: true,
            decoration:
                const InputDecoration(hintText: 'Reason for rejection'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              style: ElevatedButton.styleFrom(backgroundColor: _kRose),
              child: const Text('Reject'),
            ),
          ],
        ),
      );
      ctrl.dispose();
      if (reason == null || reason.isEmpty) return;
      final ok =
          await provider.approvePhoto(user.id, 'reject', reason: reason);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ok ? 'Photo rejected' : 'Failed to reject photo'),
          backgroundColor: ok ? _kAmber : _kRose,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          duration: const Duration(seconds: 3),
        ));
      }
    }
  }

  Widget _avatarIcon(bool isFemale) {
    return Center(
      child: Icon(
        isFemale ? Icons.face_2 : Icons.person,
        size: 24,
        color: isFemale ? Colors.pink.shade300 : _kPrimary.withOpacity(0.7),
      ),
    );
  }

  Widget _miniVerifiedDot(bool isVerified) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isVerified
            ? Colors.green.withOpacity(0.15)
            : Colors.red.withOpacity(0.12),
      ),
      child: Icon(
        isVerified ? Icons.check : Icons.close,
        size: 9,
        color: isVerified ? Colors.green.shade600 : Colors.red.shade400,
      ),
    );
  }

  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _infoChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: color.withOpacity(0.9),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _accessLevelChip(User user) {
    final String label;
    final Color color;
    final IconData icon;
    if (user.isVerified != 1) {
      label = 'Docs Required';
      color = _kRose;
      icon = Icons.description_outlined;
    } else if (user.isActive != 1) {
      label = 'Browse Only';
      color = _kAmber;
      icon = Icons.lock_outline;
    } else {
      label = 'Full Access';
      color = _kEmerald;
      icon = Icons.verified_user_outlined;
    }
    return _infoChip(icon, label, color);
  }

  Widget _actionIconBtn(
      IconData icon, String label, Color color, VoidCallback? onTap) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bool disabled = onTap == null;
    final Color textColor = isDark
        ? Color.lerp(color, Colors.white, _kActionButtonTextBlendFactor)!
        : Color.lerp(color, Colors.black, _kActionButtonTextBlendFactor)!;
    return Tooltip(
      message: label,
      child: Opacity(
        opacity: disabled ? 0.4 : 1.0,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            constraints: const BoxConstraints(minWidth: _kActionButtonMinWidth),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.10),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withOpacity(0.22)),
              boxShadow: disabled
                  ? []
                  : [
                      BoxShadow(
                        color: color.withOpacity(0.08),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 7),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: textColor,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
  }

  Widget _divider(bool isDark) {
    return Divider(
      height: 1,
      thickness: 1,
      color: isDark ? Colors.white.withOpacity(0.08) : Colors.grey.shade200,
    );
  }

  Widget _softChip(String label, {required IconData icon, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _activityPill({
    required String label,
    required IconData icon,
    required Color color,
    int? value,
    bool loading = false,
    double? width,
  }) {
    return Container(
      width: width ?? 160,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                loading
                    ? SizedBox(
                        height: 14,
                        width: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(color),
                        ),
                      )
                    : Text(
                        value != null ? value.toString() : '—',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: color,
                        ),
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivityBoard(ActivityStats? stats, bool loading, bool isDark) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double tileWidth = constraints.maxWidth < 680
            ? (constraints.maxWidth - 12) / 2
            : (constraints.maxWidth - 24) / 3;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A) : _kPrimary.withOpacity(0.04),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _kPrimary.withOpacity(0.12)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _kPrimary.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child:
                        const Icon(Icons.timeline_outlined, color: _kPrimary, size: 18),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Activity Snapshot',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: _kPrimary,
                    ),
                  ),
                  const Spacer(),
                  if (loading)
                    const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(_kPrimary),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _activityPill(
                    label: 'Requests Sent',
                    icon: Icons.send_rounded,
                    color: _kPrimary,
                    value: stats?.requestsSent,
                    loading: loading && stats == null,
                    width: tileWidth,
                  ),
                  _activityPill(
                    label: 'Requests Received',
                    icon: Icons.inbox_outlined,
                    color: _kViolet,
                    value: stats?.requestsReceived,
                    loading: loading && stats == null,
                    width: tileWidth,
                  ),
                  _activityPill(
                    label: 'Chat Requests',
                    icon: Icons.chat_bubble_outline,
                    color: _kSky,
                    value: stats?.chatRequestsSent,
                    loading: loading && stats == null,
                    width: tileWidth,
                  ),
                  _activityPill(
                    label: 'Chats Accepted',
                    icon: Icons.check_circle_outline,
                    color: _kEmerald,
                    value: stats?.chatRequestsAccepted,
                    loading: loading && stats == null,
                    width: tileWidth,
                  ),
                  _activityPill(
                    label: 'Profile Views',
                    icon: Icons.visibility_outlined,
                    color: _kAmber,
                    value: stats?.profileViews,
                    loading: loading && stats == null,
                    width: tileWidth,
                  ),
                  _activityPill(
                    label: 'Matches',
                    icon: Icons.favorite_outline,
                    color: _kRose,
                    value: stats?.matchesCount,
                    loading: loading && stats == null,
                    width: tileWidth,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // ─── Filter chips row ────────────────────────────────────────────────────

  Widget _buildFilterRow(UserProvider provider) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor =
        isDark ? Colors.white.withOpacity(0.08) : Colors.grey.shade200;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.04)
            : const Color(0xFFF6F7FB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _selectAllChip(provider),
          _filterDivider(isDark),
          ...[
            ('all', 'All'),
            ('approved', 'Approved'),
            ('pending', 'Pending'),
            ('rejected', 'Rejected'),
            ('not_uploaded', 'Not Uploaded'),
          ].expand((e) {
            final (key, label) = e;
            return [
              _filterChip(
                label,
                provider.statusFilter == key,
                _statusColor(key),
                () => provider.setStatusFilter(key),
              ),
            ];
          }),
          _filterDivider(isDark),
          ...[
            ('all', 'All Plans'),
            ('paid', 'Paid'),
            ('free', 'Free'),
          ].expand((e) {
            final (key, label) = e;
            return [
              _filterChip(
                label,
                provider.userTypeFilter == key,
                _planColor(key),
                () => provider.setUserTypeFilter(key),
              ),
            ];
          }),
          if (provider.statusFilter != 'all' ||
              provider.userTypeFilter != 'all')
            _filterChip('✕ Clear', true, _kRose, provider.clearFilters),
        ],
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'approved':
        return _kEmerald;
      case 'pending':
        return _kAmber;
      case 'rejected':
        return _kRose;
      case 'not_uploaded':
        return Colors.grey.shade600;
      default:
        return _kPrimaryDark;
    }
  }

  Color _planColor(String plan) {
    switch (plan) {
      case 'paid':
        return _kPrimary;
      case 'free':
        return _kSky;
      default:
        return _kPrimaryDark;
    }
  }

  Widget _filterDivider(bool isDark) {
    return Container(
      width: 1,
      height: 18,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      color: isDark
          ? Colors.white.withOpacity(0.16)
          : Colors.grey.shade300,
    );
  }

  Widget _selectAllChip(UserProvider provider) {
    final bool allSelected = provider.areAllFilteredSelected;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: provider.filteredUsers.isNotEmpty
          ? () => provider.selectAllUsers()
          : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: allSelected ? _kPrimary.withOpacity(0.12) : (isDark ? const Color(0xFF1C2339) : Colors.grey.shade100),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: allSelected ? _kPrimary.withOpacity(0.8) : (isDark ? Colors.white.withOpacity(0.15) : Colors.grey.shade300),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              allSelected ? Icons.check_box_rounded : Icons.check_box_outline_blank,
              size: 14,
              color: allSelected ? _kPrimary : Colors.grey,
            ),
            const SizedBox(width: 5),
            Text(
              'All',
              style: TextStyle(
                fontSize: 12,
                color: allSelected ? _kPrimary : (isDark ? Colors.grey.shade300 : Colors.grey.shade700),
                fontWeight: allSelected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(
      String label, bool selected, Color color, VoidCallback onTap) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.14) : (isDark ? const Color(0xFF263248) : Colors.grey.shade100),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? color.withOpacity(0.45) : (isDark ? Colors.white.withOpacity(0.15) : Colors.grey.shade300),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: selected ? color : (isDark ? Colors.grey.shade300 : Colors.grey.shade700),
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  // ─── Bulk action bar ─────────────────────────────────────────────────────

  Widget _buildBulkActionBar(UserProvider provider) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      child: provider.selectedCount > 0
          ? Container(
              margin: const EdgeInsets.fromLTRB(12, 6, 12, 2),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF111827) : _kPrimary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _kPrimary.withOpacity(0.25)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _kPrimary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${provider.selectedCount} selected',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: _kPrimary,
                      fontSize: 13,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => provider.suspendSelectedUsers(context),
                    icon: const Icon(Icons.pause_circle_outline, size: 15),
                    label: const Text('Suspend'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.orange,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  const SizedBox(width: 2),
                  TextButton.icon(
                    onPressed: () => provider.deleteSelectedUsers(context),
                    icon: const Icon(Icons.delete_outline, size: 15),
                    label: const Text('Delete'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: provider.clearSelection,
                    child: Icon(Icons.close,
                        size: 18, color: Colors.grey.shade600),
                  ),
                ],
              ),
            )
          : const SizedBox.shrink(),
    );
  }

  // ─── Empty state ─────────────────────────────────────────────────────────

  Widget _buildEmptyState(UserProvider provider) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_search_outlined,
                size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              provider.searchQuery.isNotEmpty
                  ? 'No results for "${provider.searchQuery}"'
                  : 'No members found',
              style: TextStyle(fontSize: 15, color: Colors.grey.shade500),
            ),
            if (provider.statusFilter != 'all' ||
                provider.userTypeFilter != 'all')
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: TextButton(
                  onPressed: provider.clearFilters,
                  child: const Text('Clear Filters'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ─── Top section: title + search + stats + filters ───────────────────────

  Widget _buildTopSection(UserProvider provider) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor =
        isDark ? Colors.white.withOpacity(0.08) : Colors.grey.shade200;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: _kPrimary.withOpacity(0.06),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Compact title row ──────────────────────────────────────────
          Row(
            children: [
              Container(
                height: 32,
                width: 32,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_kPrimaryDark, _kViolet],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(Icons.people_alt_rounded,
                    color: Colors.white, size: 17),
              ),
              const SizedBox(width: 8),
              Text(
                'Member Directory',
                style: TextStyle(
                  color: isDark ? Colors.white : _kPrimaryDark,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              _statPill('Total', provider.totalCount,
                  isDark ? Colors.white70 : _kPrimaryDark),
              const SizedBox(width: 6),
              _statPill('Shown', provider.filteredCount, _kEmerald),
              if (provider.selectedCount > 0) ...[
                const SizedBox(width: 6),
                _statPill('Selected', provider.selectedCount, _kAmber),
              ],
              const SizedBox(width: 8),
              Tooltip(
                message: 'Refresh',
                child: InkWell(
                  onTap: () => provider.fetchUsers(),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withOpacity(0.06)
                          : _kPrimary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withOpacity(0.14)
                            : _kPrimary.withOpacity(0.25),
                      ),
                    ),
                    child: Icon(Icons.refresh_rounded,
                        size: 16,
                        color: isDark ? Colors.white : _kPrimaryDark),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // ── Compact search bar ─────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withOpacity(0.04)
                  : _kPrimary.withOpacity(0.04),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: borderColor),
            ),
            child: TextField(
              controller: _searchController,
              style: TextStyle(
                color: isDark ? Colors.white : Colors.grey.shade900,
                fontSize: 13,
              ),
              decoration: InputDecoration(
                hintText: 'Search by name, email, phone or ID…',
                hintStyle: TextStyle(
                  fontSize: 13,
                  color: isDark
                      ? Colors.white.withOpacity(0.5)
                      : Colors.grey.shade500,
                ),
                prefixIcon: Icon(Icons.search_rounded,
                    color: isDark ? Colors.white70 : _kPrimaryDark, size: 17),
                border: InputBorder.none,
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear_rounded,
                            size: 15,
                            color: isDark
                                ? Colors.white70
                                : Colors.grey.shade500),
                        onPressed: () {
                          setState(() {});
                          _searchController.clear();
                          provider.setSearchQuery('');
                        },
                      )
                    : null,
              ),
              onChanged: (v) {
                setState(() {});
                provider.setSearchQuery(v);
              },
            ),
          ),
          const SizedBox(height: 8),
          _buildFilterRow(provider),
        ],
      ),
    );
  }


  Widget _statPill(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$count ',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            TextSpan(
              text: label,
              style: TextStyle(
                fontSize: 11,
                color: color.withOpacity(0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<UserProvider>();

    // Handle session expiry — redirect to login.
    if (provider.isSessionExpired) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.read<AuthProvider>().logout();
      });
    }

    // Plain Column — no Scaffold/AppBar to avoid duplicating the "Members"
    // title already shown in dashboard.dart's top bar.
    return Column(
      children: [
        // ── Top section: title + search + stats + filters ─────────────────
        _buildTopSection(provider),

        Divider(height: 1, thickness: 1, color: Colors.grey.shade200),

        // ── Scrollable list ──────────────────────────────────────────────
        Expanded(
          child: provider.isLoading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: () => provider.fetchUsers(),
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(
                        child: _buildBulkActionBar(provider),
                      ),
                      if (provider.filteredUsers.isEmpty)
                        SliverToBoxAdapter(
                          child: _buildEmptyState(provider),
                        )
                      else ...[
                        SliverPadding(
                          padding: EdgeInsets.zero,
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) => _buildUserCard(
                                provider.pagedUsers[index],
                                provider,
                              ),
                              childCount: provider.pagedUsers.length,
                            ),
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: _buildLoadMoreFooter(provider),
                        ),
                      ],
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildLoadMoreFooter(UserProvider provider) {
    if (!provider.hasMoreToShow) {
      return const SizedBox(height: 24);
    }
    final remaining = provider.filteredCount - provider.pagedUsers.length;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
      child: Center(
        child: OutlinedButton.icon(
          onPressed: provider.loadMoreUsers,
          icon: const Icon(Icons.expand_more_rounded, size: 18),
          label: Text('Load More ($remaining remaining)'),
          style: OutlinedButton.styleFrom(
            foregroundColor: _kPrimary,
            side: const BorderSide(color: _kPrimary),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ),
    );
  }
}
