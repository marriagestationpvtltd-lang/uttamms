import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'call_settings_provider.dart';

const _kPrimary = Color(0xFF6366F1);
const _kSlate700 = Color(0xFF334155);
const _kSlate500 = Color(0xFF64748B);
const _kSlate200 = Color(0xFFE2E8F0);
const _kSurface = Colors.white;
const _kAllowedCustomToneExtensions = ['mp3', 'mp4', 'ogg', 'webm', 'aac', 'wav', 'm4a'];

class CallSettingsScreen extends StatefulWidget {
  const CallSettingsScreen({super.key});

  @override
  State<CallSettingsScreen> createState() => _CallSettingsScreenState();
}

class _CallSettingsScreenState extends State<CallSettingsScreen> {
  late AudioPlayer _previewPlayer;
  String? _playingToneId;
  Timer? _previewTimer;

  @override
  void initState() {
    super.initState();
    _previewPlayer = AudioPlayer();
    _previewPlayer.onPlayerStateChanged.listen((state) {
      if (state == PlayerState.completed || state == PlayerState.stopped) {
        if (mounted) setState(() => _playingToneId = null);
      }
    });
  }

  @override
  void dispose() {
    _previewTimer?.cancel();
    _previewPlayer.dispose();
    super.dispose();
  }

  Future<void> _previewAssetTone(RingtoneTone tone) async {
    await _previewSource(
      tone.id,
      () => _previewPlayer.play(AssetSource(tone.asset), volume: 1.0),
    );
  }

  Future<void> _previewCustomTone(String url) async {
    await _previewSource(
      'custom',
      () => _previewPlayer.play(UrlSource(url), volume: 1.0),
    );
  }

  Future<void> _previewSource(
    String sourceKey,
    Future<void> Function() play,
  ) async {
    if (_playingToneId == sourceKey) {
      await _previewPlayer.stop();
      if (mounted) setState(() => _playingToneId = null);
      return;
    }

    await _previewPlayer.stop();
    if (mounted) setState(() => _playingToneId = sourceKey);

    try {
      await play();
      _previewTimer?.cancel();
      _previewTimer = Timer(const Duration(seconds: 4), () async {
        await _previewPlayer.stop();
        if (mounted) setState(() => _playingToneId = null);
      });
    } catch (e) {
      if (mounted) {
        setState(() => _playingToneId = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Preview failed: $e')),
        );
      }
    }
  }

  Future<void> _pickAndUploadCustomTone() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _kAllowedCustomToneExtensions,
      withData: true,
    );

    if (result == null || result.files.isEmpty || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final provider = context.read<CallSettingsProvider>();
    final file = result.files.single;

    try {
      await provider.uploadCustomTone(
            fileName: file.name,
            bytes: file.bytes,
            path: file.path,
          );
      messenger.showSnackBar(
        const SnackBar(content: Text('Custom ringtone uploaded.')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Upload failed: $e')),
      );
    }
  }

  Future<void> _removeCustomTone() async {
    final messenger = ScaffoldMessenger.of(context);
    final provider = context.read<CallSettingsProvider>();
    try {
      await provider.clearCustomTone();
      if (mounted && _playingToneId == 'custom') {
        await _previewPlayer.stop();
        setState(() => _playingToneId = null);
      }
      messenger.showSnackBar(
        const SnackBar(content: Text('Custom ringtone removed.')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Remove failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<CallSettingsProvider>();
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final cardBg = isDark ? cs.surface : _kSurface;
    final labelColor = isDark ? cs.onSurface : _kSlate700;
    final mutedColor = isDark ? cs.onSurface.withOpacity(0.55) : _kSlate500;
    final divColor = isDark ? cs.outlineVariant : _kSlate200;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader('Ringtone Selection', Icons.music_note_rounded, labelColor),
          _card(
            isDark: isDark,
            cardBg: cardBg,
            divColor: divColor,
            child: Column(
              children: [
                for (int i = 0; i < CallSettingsProvider.availableTones.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: divColor),
                  _ToneRow(
                    tone: CallSettingsProvider.availableTones[i],
                    isSelected: settings.selectedToneId ==
                        CallSettingsProvider.availableTones[i].id,
                    isPlaying: _playingToneId ==
                        CallSettingsProvider.availableTones[i].id,
                    onSelect: () => settings.setTone(
                      CallSettingsProvider.availableTones[i].id,
                    ),
                    onPreview: () => _previewAssetTone(
                      CallSettingsProvider.availableTones[i],
                    ),
                    labelColor: labelColor,
                    mutedColor: mutedColor,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          _sectionHeader('Custom Ringtone', Icons.upload_file_rounded, labelColor),
          _card(
            isDark: isDark,
            cardBg: cardBg,
            divColor: divColor,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (settings.hasCustomTone) ...[
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: _kPrimary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.audio_file_rounded,
                            size: 18,
                            color: _kPrimary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                settings.customToneName.isEmpty
                                    ? 'Uploaded custom ringtone'
                                    : settings.customToneName,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: labelColor,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'This uploaded tone plays first for calls. If it fails to load, the selected ringtone above is used as fallback.',
                                style: TextStyle(fontSize: 12, color: mutedColor),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: settings.isUploadingCustomTone
                              ? null
                              : () => _previewCustomTone(settings.customToneUrl),
                          icon: Icon(
                            _playingToneId == 'custom'
                                ? Icons.stop_rounded
                                : Icons.play_arrow_rounded,
                            color: _playingToneId == 'custom'
                                ? _kPrimary
                                : mutedColor,
                          ),
                        ),
                        IconButton(
                          onPressed: settings.isUploadingCustomTone
                              ? null
                              : _removeCustomTone,
                          icon: Icon(Icons.delete_outline_rounded, color: mutedColor),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                  ] else
                    Text(
                      'No custom ringtone uploaded yet. If you upload one, it will play first during calls, with the selected ringtone as fallback.',
                      style: TextStyle(fontSize: 12, color: mutedColor),
                    ),
                  SizedBox(
                    height: 40,
                    child: FilledButton.icon(
                      onPressed: settings.isUploadingCustomTone
                          ? null
                          : _pickAndUploadCustomTone,
                      icon: settings.isUploadingCustomTone
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.upload_rounded, size: 18),
                      label: Text(
                        settings.hasCustomTone ? 'Replace tone' : 'Upload tone',
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: _kPrimary,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          _sectionHeader('Repeat Interval', Icons.repeat_rounded, labelColor),
          _card(
            isDark: isDark,
            cardBg: cardBg,
            divColor: divColor,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.timer_outlined, size: 18, color: mutedColor),
                      const SizedBox(width: 8),
                      Text(
                        'Repeat after',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: labelColor,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _kPrimary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: _kPrimary.withOpacity(0.3)),
                        ),
                        child: Text(
                          '${settings.repeatIntervalSeconds} sec',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _kPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: _kPrimary,
                      inactiveTrackColor: _kPrimary.withOpacity(0.2),
                      thumbColor: _kPrimary,
                      overlayColor: _kPrimary.withOpacity(0.12),
                      valueIndicatorColor: _kPrimary,
                      valueIndicatorTextStyle: const TextStyle(color: Colors.white),
                    ),
                    child: Slider(
                      value: settings.repeatIntervalSeconds.toDouble(),
                      min: 1,
                      max: 30,
                      divisions: 29,
                      label: '${settings.repeatIntervalSeconds}s',
                      onChanged: (v) => settings.setRepeatInterval(v.round()),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('1s', style: TextStyle(fontSize: 11, color: mutedColor)),
                      Text('30s', style: TextStyle(fontSize: 11, color: mutedColor)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'The ringtone plays once, then waits this many seconds before repeating.',
                    style: TextStyle(fontSize: 12, color: mutedColor),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          _card(
            isDark: isDark,
            cardBg: cardBg,
            divColor: divColor,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _kPrimary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.info_outline_rounded,
                      size: 18,
                      color: _kPrimary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'The selected tone is saved automatically for user-to-user audio and video calls. Uploaded custom tones play first; the selected tone is used as fallback if no custom tone is uploaded or if playback fails.',
                      style: TextStyle(fontSize: 12, color: mutedColor),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 16, color: _kPrimary),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({
    required bool isDark,
    required Color cardBg,
    required Color divColor,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: divColor),
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
      child: child,
    );
  }
}

class _ToneRow extends StatelessWidget {
  final RingtoneTone tone;
  final bool isSelected;
  final bool isPlaying;
  final VoidCallback onSelect;
  final VoidCallback onPreview;
  final Color labelColor;
  final Color mutedColor;

  const _ToneRow({
    required this.tone,
    required this.isSelected,
    required this.isPlaying,
    required this.onSelect,
    required this.onPreview,
    required this.labelColor,
    required this.mutedColor,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onSelect,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? _kPrimary : mutedColor,
                  width: isSelected ? 5 : 2,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                tone.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isSelected ? _kPrimary : labelColor,
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 36,
              height: 36,
              child: Material(
                color: isPlaying ? _kPrimary.withOpacity(0.12) : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  onTap: onPreview,
                  borderRadius: BorderRadius.circular(8),
                  child: Icon(
                    isPlaying ? Icons.stop_rounded : Icons.play_arrow_rounded,
                    size: 22,
                    color: isPlaying ? _kPrimary : mutedColor,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
