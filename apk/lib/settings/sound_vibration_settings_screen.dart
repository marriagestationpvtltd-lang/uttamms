import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constant/app_colors.dart';
import '../service/sound_settings_service.dart';

/// Standalone screen for Sound & Vibration notification settings.
/// Accessible from the Chat list via the gear icon in the AppBar.
class SoundVibrationSettingsScreen extends StatefulWidget {
  const SoundVibrationSettingsScreen({Key? key}) : super(key: key);

  @override
  State<SoundVibrationSettingsScreen> createState() =>
      _SoundVibrationSettingsScreenState();
}

class _SoundVibrationSettingsScreenState
    extends State<SoundVibrationSettingsScreen> {
  bool _soundEnabled  = true;
  bool _callSound     = true;
  bool _messageSound  = true;
  bool _typingSound   = true;
  bool _vibration     = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    await SoundSettingsService.instance.load();
    if (!mounted) return;
    final s = SoundSettingsService.instance;
    setState(() {
      _soundEnabled  = s.soundEnabled;
      _callSound     = s.callSoundRaw;
      _messageSound  = s.messageSoundRaw;
      _typingSound   = s.typingSoundRaw;
      _vibration     = s.vibrationEnabled;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF0F0),
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFF90E18), Color(0xFFD00D15)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.white,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
          systemStatusBarContrastEnforced: false,
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Sound & Vibration',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: [
          _buildSectionHeader('Sound & Vibration'),
          _buildCard(
            children: [
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
            ],
          ),
        ],
      ),
    );
  }

  // ── Helper builders ────────────────────────────────────────────────────────

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
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
      child: Column(children: children),
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
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
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
}
