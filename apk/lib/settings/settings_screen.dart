import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../Auth/Screen/Edit/3edit.dart';
import '../Auth/Screen/Edit/Community.dart';
import '../Auth/Screen/Edit/Personal.dart' show PersonalDetailsPageEdit;
import '../Auth/Screen/Edit/edit5.dart';
import '../Auth/Screen/Edit/edit6.dart';
import '../Auth/Screen/Edit/edit7.dart';
import '../Auth/Screen/Edit/edit8.dart';
import '../Auth/SuignupModel/signup_model.dart';
import '../DeleteAccount/deleteAccointScreen.dart';
import '../Package/PackageScreen.dart';
import '../Startup/onboarding.dart';
import '../constant/app_colors.dart';
import '../core/user_state.dart';
import '../otherenew/blocked_users_screen.dart';
import '../service/sound_settings_service.dart';
import 'package:ms2026/config/app_endpoints.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // User profile info
  String _userName = '';
  String _userEmail = '';
  String _profilePicture = '';
  String _memberType = 'Free';

  // Notification toggles
  bool _pushEnabled = true;
  bool _emailEnabled = true;
  bool _smsEnabled = false;
  bool _loadingNotifications = true;

  // Sound & Vibration settings (local, stored via SoundSettingsService)
  bool _soundEnabled   = true;
  bool _callSound      = true;
  bool _messageSound   = true;
  bool _typingSound    = true;
  bool _vibration      = true;

  // Privacy
  String _currentPrivacy = 'Private';
  bool _loadingPrivacy = true;

  final String _baseUrl = '${kApiBaseUrl}/Api2';
  final String _privacyGetUrl = '${kApiBaseUrl}/Api3/get_privacy.php';
  final String _privacyUpdateUrl = '${kApiBaseUrl}/Api3/privacy.php';

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadNotificationSettings();
    _loadPrivacySettings();
    _loadSoundSettings();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final userDataString = prefs.getString('user_data');
    if (userDataString == null || userDataString.isEmpty) return;
    final userData = jsonDecode(userDataString);
    if (!mounted) return;
    // Prefer the global UserState for usertype so it's always in sync.
    final utFromState = context.read<UserState>().usertype.toLowerCase();
    final utFromPrefs = userData['personalDetail']?['usertype']?.toString().toLowerCase() ?? 'free';
    final ut = utFromState.isNotEmpty ? utFromState : utFromPrefs;
    setState(() {
      _userName =
          '${userData['firstName'] ?? ''} ${userData['lastName'] ?? ''}'.trim();
      _userEmail = userData['email']?.toString() ?? '';
      _profilePicture = userData['profile_picture']?.toString() ?? '';
      _memberType = _mapMemberType(ut);
    });
  }

  Future<void> _loadSoundSettings() async {
    await SoundSettingsService.instance.load();
    if (!mounted) return;
    final s = SoundSettingsService.instance;
    setState(() {
      _soundEnabled = s.soundEnabled;
      _callSound    = s.callSoundRaw;
      _messageSound = s.messageSoundRaw;
      _typingSound  = s.typingSoundRaw;
      _vibration    = s.vibrationEnabled;
    });
  }

  String _mapMemberType(String ut) {
    switch (ut) {
      case 'premium':
        return 'Premium';
      case 'gold':
        return 'Gold';
      case 'platinum':
        return 'Platinum';
      default:
        return 'Free';
    }
  }

  Future<String?> _getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    final userDataString = prefs.getString('user_data');
    if (userDataString == null || userDataString.isEmpty) return null;
    final userData = jsonDecode(userDataString);
    return userData['id']?.toString();
  }

  // ── Notification Settings ─────────────────────────────────────────────────

  Future<void> _loadNotificationSettings() async {
    final userId = await _getUserId();
    if (userId == null) {
      if (!mounted) return;
      setState(() => _loadingNotifications = false);
      return;
    }
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/get_notifications.php?user_id=$userId'),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (!mounted) return;
        setState(() {
          _pushEnabled = _toBool(data['settings']?['push_enabled'], true);
          _emailEnabled = _toBool(data['settings']?['email_enabled'], true);
          _smsEnabled = _toBool(data['settings']?['sms_enabled'], false);
        });
      }
    } catch (e) {
      debugPrint('Error loading notification settings: $e');
    } finally {
      if (mounted) setState(() => _loadingNotifications = false);
    }
  }

  Future<void> _saveNotificationSettings() async {
    final userId = await _getUserId();
    if (userId == null) return;
    try {
      await http.post(
        Uri.parse('$_baseUrl/update_notification_settings.php'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'user_id': userId,
          'push_enabled': _pushEnabled ? 1 : 0,
          'email_enabled': _emailEnabled ? 1 : 0,
          'sms_enabled': _smsEnabled ? 1 : 0,
        }),
      );
    } catch (e) {
      debugPrint('Error updating notification settings: $e');
    }
  }

  bool _toBool(dynamic value, bool fallback) {
    if (value == null) return fallback;
    if (value is bool) return value;
    if (value is int) return value == 1;
    if (value is String) return value == '1' || value.toLowerCase() == 'true';
    return fallback;
  }

  // ── Privacy Settings ──────────────────────────────────────────────────────

  Future<void> _loadPrivacySettings() async {
    final userId = await _getUserId();
    if (userId == null) {
      if (!mounted) return;
      setState(() => _loadingPrivacy = false);
      return;
    }
    try {
      final response = await http.get(
        Uri.parse('$_privacyGetUrl?userid=$userId'),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'success') {
          final privacy =
              data['data']['privacy']?.toString().toLowerCase() ?? 'private';
          if (!mounted) return;
          setState(() {
            _currentPrivacy = _apiToLabel(privacy);
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading privacy: $e');
    } finally {
      if (mounted) setState(() => _loadingPrivacy = false);
    }
  }

  String _apiToLabel(String api) {
    switch (api) {
      case 'free':
        return 'All Users';
      case 'paid':
        return 'Premium Users Only';
      case 'verified':
        return 'Verified Users Only';
      default:
        return 'Private';
    }
  }

  String _labelToApi(String label) {
    switch (label) {
      case 'All Users':
        return 'free';
      case 'Premium Users Only':
        return 'paid';
      case 'Verified Users Only':
        return 'verified';
      default:
        return 'private';
    }
  }

  Future<void> _updatePrivacy(String label) async {
    final userId = await _getUserId();
    if (userId == null) return;
    final privacyValue = _labelToApi(label);
    try {
      final response = await http.get(
        Uri.parse('$_privacyUpdateUrl?userid=$userId&privacy=$privacyValue'),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (!mounted) return;
        if (data['status'] == 'success') {
          setState(() => _currentPrivacy = label);
          _showSnackBar('Privacy settings updated successfully!');
        } else {
          _showSnackBar('Failed: ${data['message']}', isError: true);
        }
      }
    } catch (e) {
      debugPrint('Error updating privacy: $e');
      _showSnackBar('Error updating privacy', isError: true);
    }
  }

  void _showPrivacyDialog() {
    String selected = _currentPrivacy;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'Profile Picture Visibility',
            style: TextStyle(
              color: AppColors.primary,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Choose who can see your profile picture',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 16),
              ...['All Users', 'Premium Users Only', 'Verified Users Only', 'Private']
                  .map(
                    (option) => RadioListTile<String>(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      activeColor: AppColors.primary,
                      title: Text(option,
                          style: const TextStyle(fontSize: 14)),
                      value: option,
                      groupValue: selected,
                      onChanged: (v) {
                        if (v != null) setDialogState(() => selected = v);
                      },
                    ),
                  )
                  .toList(),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel',
                  style: TextStyle(color: AppColors.textSecondary)),
            ),
            Container(
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(8),
              ),
              child: TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _updatePrivacy(selected);
                },
                child: const Text('Save',
                    style: TextStyle(color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Logout ────────────────────────────────────────────────────────────────

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Logout',
            style: TextStyle(
                color: AppColors.primary, fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.logout, color: Colors.orange, size: 56),
            const SizedBox(height: 16),
            const Text(
              'Are you sure you want to logout?',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(8),
            ),
            child: TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await _logout();
              },
              child: const Text('Logout',
                  style: TextStyle(color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _logout() async {
    // Clear the global UserState before wiping SharedPreferences.
    if (mounted) {
      await context.read<UserState>().clear();
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    // Preserve fast-start flag so subsequent opens still use the short animation.
    await prefs.setBool('has_launched_before', true);
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    _showSnackBar('Logged out successfully');
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.error : AppColors.primary,
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      body: CustomScrollView(
        slivers: [
          _buildSliverAppBar(),
          SliverPadding(
            padding: const EdgeInsets.only(bottom: 32),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _buildProfileCard(),
                const SizedBox(height: 8),
                _buildSectionHeader('Account Settings'),
                _buildAccountSection(),
                const SizedBox(height: 8),
                _buildSectionHeader('Privacy & Security'),
                _buildPrivacySection(),
                const SizedBox(height: 8),
                _buildSectionHeader('Notifications'),
                _buildNotificationsSection(),
                const SizedBox(height: 8),
                _buildSectionHeader('Sound & Vibration'),
                _buildSoundSection(),
                const SizedBox(height: 8),
                _buildSectionHeader('Membership'),
                _buildMembershipSection(),
                const SizedBox(height: 8),
                _buildSectionHeader('Help & Support'),
                _buildHelpSection(),
                const SizedBox(height: 8),
                _buildSectionHeader('Account Management'),
                _buildAccountManagementSection(),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSliverAppBar() {
    return SliverAppBar(
      expandedHeight: 120,
      floating: false,
      pinned: true,
      elevation: 0,
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.white,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemStatusBarContrastEnforced: false,
      ),
      flexibleSpace: FlexibleSpaceBar(
        titlePadding:
            const EdgeInsets.only(left: 56, bottom: 16),
        title: const Text(
          'Settings',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        background: Container(
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
          ),
        ),
      ),
    );
  }

  Widget _buildProfileCard() {
    Color memberColor;
    IconData memberIcon;
    switch (_memberType) {
      case 'Platinum':
        memberColor = const Color(0xFF9C27B0);
        memberIcon = Icons.diamond;
        break;
      case 'Gold':
        memberColor = AppColors.premium;
        memberIcon = Icons.workspace_premium;
        break;
      case 'Premium':
        memberColor = AppColors.secondary;
        memberIcon = Icons.star;
        break;
      default:
        memberColor = AppColors.textSecondary;
        memberIcon = Icons.person;
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowLight,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 32,
            backgroundColor: AppColors.borderLight,
            backgroundImage: _profilePicture.isNotEmpty
                ? NetworkImage(_profilePicture)
                : null,
            child: _profilePicture.isEmpty
                ? Icon(Icons.person, size: 36, color: AppColors.textHint)
                : null,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _userName.isEmpty ? 'Loading…' : _userName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF212121),
                  ),
                ),
                if (_userEmail.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    _userEmail,
                    style: TextStyle(
                        fontSize: 13, color: AppColors.textSecondary),
                  ),
                ],
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(memberIcon, size: 14, color: memberColor),
                    const SizedBox(width: 4),
                    Text(
                      '$_memberType Member',
                      style: TextStyle(
                        fontSize: 12,
                        color: memberColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }

  Widget _buildCard({required List<Widget> children}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowLight,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: children,
      ),
    );
  }

  Widget _buildTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
    bool isLast = false,
  }) {
    return Column(
      children: [
        ListTile(
          leading: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          title: Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Color(0xFF212121),
            ),
          ),
          subtitle: subtitle != null
              ? Text(
                  subtitle,
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                )
              : null,
          trailing: trailing ??
              Icon(Icons.chevron_right,
                  color: AppColors.textHint, size: 20),
          onTap: onTap,
        ),
        if (!isLast)
          Divider(
            height: 1,
            indent: 66,
            color: AppColors.borderLight,
          ),
      ],
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool isLast = false,
  }) {
    return Column(
      children: [
        ListTile(
          leading: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          title: Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Color(0xFF212121),
            ),
          ),
          subtitle: Text(
            subtitle,
            style:
                TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          trailing: Switch.adaptive(
            value: value,
            activeColor: AppColors.primary,
            onChanged: onChanged,
          ),
        ),
        if (!isLast)
          Divider(
            height: 1,
            indent: 66,
            color: AppColors.borderLight,
          ),
      ],
    );
  }

  // ── Sections ──────────────────────────────────────────────────────────────

  Widget _buildAccountSection() {
    return _buildCard(children: [
      _buildTile(
        icon: Icons.person_outline,
        iconColor: AppColors.secondary,
        title: 'Personal Details',
        subtitle: 'Update your personal information',
        onTap: () => _openEdit(PersonalDetailsPageEdit()),
      ),
      _buildTile(
        icon: Icons.people_outline,
        iconColor: Colors.teal,
        title: 'Community Details',
        subtitle: 'Religion, caste, mother tongue',
        onTap: () => _openEdit(CommunityDetailsPageEdit()),
      ),
      _buildTile(
        icon: Icons.work_outline,
        iconColor: Colors.indigo,
        title: 'Education & Career',
        subtitle: 'Degree, designation, income',
        onTap: () => _openEdit(EducationCareerPagee()),
      ),
      _buildTile(
        icon: Icons.family_restroom,
        iconColor: Colors.deepOrange,
        title: 'Family Details',
        subtitle: 'Family background information',
        onTap: () => _openEdit(FamilyDetailsPagee()),
      ),
      _buildTile(
        icon: Icons.favorite_outline,
        iconColor: Colors.pink,
        title: 'Lifestyle',
        subtitle: 'Habits and lifestyle preferences',
        onTap: () => _openEdit(LifestylePagee()),
      ),
      _buildTile(
        icon: Icons.search,
        iconColor: Colors.purple,
        title: 'Partner Preferences',
        subtitle: 'What you are looking for',
        onTap: () => _openEdit(PartnerPreferencesPagee()),
        isLast: true,
      ),
    ]);
  }

  Widget _buildPrivacySection() {
    return _buildCard(children: [
      _buildTile(
        icon: Icons.visibility_outlined,
        iconColor: AppColors.primary,
        title: 'Profile Picture Visibility',
        subtitle: _loadingPrivacy ? 'Loading…' : _currentPrivacy,
        onTap: _loadingPrivacy ? null : _showPrivacyDialog,
      ),
      _buildTile(
        icon: Icons.block,
        iconColor: Colors.red.shade700,
        title: 'Blocked Users',
        subtitle: 'Manage your blocked list',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const BlockedUsersScreen()),
        ),
        isLast: true,
      ),
    ]);
  }

  Widget _buildNotificationsSection() {
    if (_loadingNotifications) {
      return _buildCard(children: [
        const Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: CircularProgressIndicator()),
        ),
      ]);
    }
    return _buildCard(children: [
      _buildSwitchTile(
        icon: Icons.notifications_outlined,
        iconColor: Colors.orange,
        title: 'Push Notifications',
        subtitle: 'Receive alerts on your device',
        value: _pushEnabled,
        onChanged: (v) {
          setState(() => _pushEnabled = v);
          _saveNotificationSettings();
        },
      ),
      _buildSwitchTile(
        icon: Icons.email_outlined,
        iconColor: Colors.blue,
        title: 'Email Notifications',
        subtitle: 'Receive updates via email',
        value: _emailEnabled,
        onChanged: (v) {
          setState(() => _emailEnabled = v);
          _saveNotificationSettings();
        },
      ),
      _buildSwitchTile(
        icon: Icons.sms_outlined,
        iconColor: Colors.green,
        title: 'SMS Notifications',
        subtitle: 'Receive alerts via text message',
        value: _smsEnabled,
        onChanged: (v) {
          setState(() => _smsEnabled = v);
          _saveNotificationSettings();
        },
        isLast: true,
      ),
    ]);
  }

  Widget _buildSoundSection() {
    return _buildCard(children: [
      _buildSwitchTile(
        icon: Icons.volume_up_outlined,
        iconColor: Colors.deepPurple,
        title: 'Sound',
        subtitle: 'Enable or disable all in-app sounds',
        value: _soundEnabled,
        onChanged: (v) {
          setState(() => _soundEnabled = v);
          SoundSettingsService.instance.setSoundEnabled(v);
        },
      ),
      _buildSwitchTile(
        icon: Icons.call_outlined,
        iconColor: Colors.green,
        title: 'Call Sound',
        subtitle: 'Play ringtone on incoming/outgoing calls',
        value: _callSound,
        onChanged: (v) {
          setState(() => _callSound = v);
          SoundSettingsService.instance.setCallSoundEnabled(v);
        },
      ),
      _buildSwitchTile(
        icon: Icons.message_outlined,
        iconColor: Colors.blue,
        title: 'Message Sound',
        subtitle: 'Play sound when a new message arrives',
        value: _messageSound,
        onChanged: (v) {
          setState(() => _messageSound = v);
          SoundSettingsService.instance.setMessageSoundEnabled(v);
        },
      ),
      _buildSwitchTile(
        icon: Icons.keyboard_outlined,
        iconColor: Colors.orange,
        title: 'Typing Sound',
        subtitle: 'Play a short tick when someone is typing',
        value: _typingSound,
        onChanged: (v) {
          setState(() => _typingSound = v);
          SoundSettingsService.instance.setTypingSoundEnabled(v);
        },
      ),
      _buildSwitchTile(
        icon: Icons.vibration,
        iconColor: Colors.teal,
        title: 'Vibration',
        subtitle: 'Vibrate on messages and calls',
        value: _vibration,
        onChanged: (v) {
          setState(() => _vibration = v);
          SoundSettingsService.instance.setVibrationEnabled(v);
        },
        isLast: true,
      ),
    ]);
  }

  Widget _buildMembershipSection() {
    return _buildCard(children: [
      _buildTile(
        icon: Icons.workspace_premium,
        iconColor: AppColors.premium,
        title: 'Membership Plans',
        subtitle: 'View and upgrade your plan',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SubscriptionPage()),
        ),
        isLast: true,
      ),
    ]);
  }

  Widget _buildHelpSection() {
    return _buildCard(children: [
      _buildTile(
        icon: Icons.info_outline,
        iconColor: AppColors.secondary,
        title: 'About App',
        subtitle: 'Version and app information',
        onTap: _showAboutDialog,
      ),
      _buildTile(
        icon: Icons.headset_mic_outlined,
        iconColor: Colors.teal,
        title: 'Contact Support',
        subtitle: 'Get help from our team',
        onTap: _showContactSupportDialog,
      ),
      _buildTile(
        icon: Icons.star_rate_outlined,
        iconColor: Colors.amber,
        title: 'Rate the App',
        subtitle: 'Share your feedback on the store',
        onTap: _showRateAppDialog,
        isLast: true,
      ),
    ]);
  }

  Widget _buildAccountManagementSection() {
    return _buildCard(children: [
      _buildTile(
        icon: Icons.delete_outline,
        iconColor: AppColors.error,
        title: 'Delete Account',
        subtitle: 'Permanently remove your account',
        trailing: Icon(Icons.chevron_right,
            color: AppColors.error, size: 20),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => DeleteAccountPage()),
        ),
      ),
      _buildTile(
        icon: Icons.logout,
        iconColor: Colors.orange,
        title: 'Logout',
        subtitle: 'Sign out from this device',
        trailing:
            Icon(Icons.chevron_right, color: Colors.orange, size: 20),
        onTap: _showLogoutDialog,
        isLast: true,
      ),
    ]);
  }

  // ── Dialogs ───────────────────────────────────────────────────────────────

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(Icons.favorite,
                  color: Colors.white, size: 40),
            ),
            const SizedBox(height: 16),
            const Text(
              'Marriage Station',
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'Your trusted partner in finding life-long companionship.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            Divider(color: AppColors.borderLight),
            _aboutRow('Developer', 'Marriage Station Pvt. Ltd.'),
            _aboutRow('Website', 'digitallami.com'),
            _aboutRow('Support', 'support@digitallami.com'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Close',
                style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  Widget _aboutRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label,
                style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF212121))),
          ),
        ],
      ),
    );
  }

  void _showContactSupportDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.headset_mic_outlined,
                color: AppColors.primary, size: 22),
            const SizedBox(width: 8),
            const Text('Contact Support',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Our support team is available to help you. Reach out via:',
              style: TextStyle(
                  fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            _contactRow(Icons.email_outlined, Colors.blue,
                'Email', 'support@digitallami.com'),
            const SizedBox(height: 8),
            _contactRow(Icons.language, Colors.teal,
                'Website', 'digitallami.com'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Close',
                style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  Widget _contactRow(
      IconData icon, Color color, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600)),
            Text(value,
                style: const TextStyle(
                    fontSize: 13, color: Color(0xFF212121))),
          ],
        ),
      ],
    );
  }

  void _showRateAppDialog() {
    int selectedStars = 5;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          title: const Text('Rate Marriage Station',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'How would you rate your experience?',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) {
                  final star = i + 1;
                  return GestureDetector(
                    onTap: () =>
                        setDialogState(() => selectedStars = star),
                    child: Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(
                        star <= selectedStars
                            ? Icons.star
                            : Icons.star_border,
                        color: Colors.amber,
                        size: 36,
                      ),
                    ),
                  );
                }),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Later',
                  style: TextStyle(color: AppColors.textSecondary)),
            ),
            Container(
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(8),
              ),
              child: TextButton(
                onPressed: () {
                  final stars = selectedStars;
                  Navigator.pop(ctx);
                  _showSnackBar(
                      'Thank you for rating us $stars stars! ⭐');
                },
                child: const Text('Submit',
                    style: TextStyle(color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Navigation helpers ────────────────────────────────────────────────────

  Future<void> _openEdit(Widget page) async {
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => page));
  }
}
