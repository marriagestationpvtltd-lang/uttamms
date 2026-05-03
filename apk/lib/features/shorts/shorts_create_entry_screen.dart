import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

import 'services/shorts_service.dart';

class ShortsCreateEntryScreen extends StatefulWidget {
  final String soundUrl;
  final String soundTitle;
  final bool fromCamera;
  final bool textMode;

  const ShortsCreateEntryScreen({
    super.key,
    this.soundUrl = '',
    this.soundTitle = '',
    this.fromCamera = false,
    this.textMode = false,
  });

  @override
  State<ShortsCreateEntryScreen> createState() =>
      _ShortsCreateEntryScreenState();
}

class _ShortsCreateEntryScreenState extends State<ShortsCreateEntryScreen>
    with SingleTickerProviderStateMixin {
  final ImagePicker _picker = ImagePicker();
  XFile? _selected;
  String _mode = 'reel';
  bool _uploading = false;
  int _userId = 0;
  bool _isAdminUploader = false;
  int _adminId = 0;
  final TextEditingController _captionCtrl = TextEditingController();
  final TextEditingController _textPostCtrl = TextEditingController();
  String _privacy = 'public';
  bool _allowComments = true;
  bool _allowDuet = true;
  bool _allowDownload = true;
  bool _textPostMode = false;
  int _textBgIdx = 0;
  static const List<List<Color>> _textBgs = [
    [Color(0xFF1a1a2e), Color(0xFF16213e)],
    [Color(0xFF200122), Color(0xFF6f0000)],
    [Color(0xFF0f2027), Color(0xFF203a43)],
    [Color(0xFF0d0d0d), Color(0xFF2e2e2e)],
    [Color(0xFF3a1c71), Color(0xFFd76d77)],
  ];

  VideoPlayerController? _videoCtrl;
  bool _videoInitialized = false;
  AudioPlayer? _audioPlayer;
  bool _soundPlaying = false;
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _loadUserId().then((_) {
      if (widget.textMode) {
        setState(() => _textPostMode = true);
      } else if (widget.fromCamera) {
        _pickMedia(mode: 'reel', fromCamera: true);
      }
    });
  }

  @override
  void dispose() {
    _captionCtrl.dispose();
    _textPostCtrl.dispose();
    _audioPlayer?.dispose();
    _videoCtrl?.dispose();
    _tabCtrl.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _loadUserId() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('user_data') ?? '';
    if (raw.isEmpty) return;
    try {
      final parsed = jsonDecode(raw) as Map<String, dynamic>;
      final uid = int.tryParse(parsed['id']?.toString() ?? '') ?? 0;
      final role = (parsed['role']?.toString() ?? '').toLowerCase();
      final isAdmin = parsed['isAdmin'] == true || role == 'admin';
      final aid = int.tryParse(
            parsed['admin_id']?.toString() ?? parsed['id']?.toString() ?? '',
          ) ??
          0;
      if (mounted) {
        setState(() {
          _userId = uid;
          _isAdminUploader = isAdmin;
          _adminId = aid;
        });
      }
    } catch (_) {}
  }

  Future<void> _initVideoPreview(String path) async {
    _videoCtrl?.dispose();
    _videoCtrl = null;
    setState(() => _videoInitialized = false);
    final ctrl = VideoPlayerController.file(File(path));
    _videoCtrl = ctrl;
    try {
      await ctrl.initialize();
      ctrl.setLooping(true);
      ctrl.play();
      if (mounted) setState(() => _videoInitialized = true);
    } catch (_) {
      if (mounted) setState(() => _videoInitialized = false);
    }
  }

  Future<void> _pickMedia(
      {required String mode, required bool fromCamera}) async {
    XFile? file;
    if (mode == 'story') {
      file = fromCamera
          ? await _picker.pickImage(
              source: ImageSource.camera, imageQuality: 85)
          : await _picker.pickImage(
              source: ImageSource.gallery, imageQuality: 90);
    } else {
      file = fromCamera
          ? await _picker.pickVideo(
              source: ImageSource.camera,
              maxDuration: const Duration(seconds: 60))
          : await _picker.pickVideo(
              source: ImageSource.gallery,
              maxDuration: const Duration(seconds: 60));
    }
    if (!mounted || file == null) return;
    setState(() {
      _mode = mode;
      _selected = file;
      _videoInitialized = false;
    });
    if (mode != 'story') await _initVideoPreview(file.path);
  }

  void _clearSelection() {
    _videoCtrl?.dispose();
    _videoCtrl = null;
    setState(() {
      _selected = null;
      _videoInitialized = false;
      _captionCtrl.clear();
    });
  }

  Future<void> _uploadNow() async {
    if (_textPostMode) {
      final text = _textPostCtrl.text.trim();
      if (text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please write something first.')));
        return;
      }
      setState(() => _uploading = true);
      try {
        await ShortsService.uploadReel(
            userId: _userId,
            filePath: '',
            caption: text,
            privacy: _privacy,
            allowComments: _allowComments,
            allowDuet: false,
            allowDownload: false,
            asAdmin: _isAdminUploader,
            adminId: _adminId > 0 ? _adminId : null);
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Posted!')));
        Navigator.pop(context);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      } finally {
        if (mounted) setState(() => _uploading = false);
      }
      return;
    }
    if (_selected == null) return;
    if (_userId <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Please login again.')));
      return;
    }
    setState(() => _uploading = true);
    try {
      if (_mode == 'story') {
        final isImage = (_selected!.mimeType ?? '').startsWith('image/');
        await ShortsService.uploadStory(
            userId: _userId,
            filePath: _selected!.path,
            isImage: isImage,
            caption: _captionCtrl.text.trim(),
            privacy: _privacy);
      } else {
        await ShortsService.uploadReel(
            userId: _userId,
            filePath: _selected!.path,
            caption: _captionCtrl.text.trim(),
            privacy: _privacy,
            allowComments: _allowComments,
            allowDuet: _allowDuet,
            allowDownload: _allowDownload,
            soundUrl: widget.soundUrl,
            soundTitle: widget.soundTitle,
            asAdmin: _isAdminUploader,
            adminId: _adminId > 0 ? _adminId : null);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_mode == 'reel' ? 'Reel posted!' : 'Story posted!')));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: true,
      body: _textPostMode
          ? _buildTextScreen()
          : _selected != null
              ? _buildPreviewScreen()
              : _buildPickerScreen(),
    );
  }

  Widget _buildPickerScreen() {
    return Container(
      decoration: const BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF0a0a0a), Color(0xFF111111)])),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(children: [
                _IconBtn(
                    icon: Icons.close, onTap: () => Navigator.pop(context)),
                const Spacer(),
                const Text('Create',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700)),
                const Spacer(),
                const SizedBox(width: 40),
              ]),
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(30)),
              child: TabBar(
                controller: _tabCtrl,
                indicator: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [Color(0xFFFF0050), Color(0xFFFF4081)]),
                    borderRadius: BorderRadius.circular(26)),
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white54,
                labelStyle:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                unselectedLabelStyle:
                    const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                dividerColor: Colors.transparent,
                tabs: const [Tab(text: 'Reel'), Tab(text: 'Story')],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabCtrl,
                children: [
                  _buildTypeTab(
                      mode: 'reel',
                      icon: Icons.play_circle_fill_rounded,
                      headline: 'Short Video',
                      tagline: 'Up to 60 seconds',
                      gradientColors: const [
                        Color(0xFFFF0050),
                        Color(0xFFFF6B6B)
                      ]),
                  _buildTypeTab(
                      mode: 'story',
                      icon: Icons.auto_stories_rounded,
                      headline: 'Story',
                      tagline: 'Disappears in 24 hours',
                      gradientColors: const [
                        Color(0xFF00C6FF),
                        Color(0xFF0072FF)
                      ]),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: GestureDetector(
                onTap: () => setState(() => _textPostMode = true),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white12)),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.text_fields_rounded,
                          color: Colors.deepPurpleAccent, size: 22),
                      SizedBox(width: 10),
                      Text('Write a text post',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 15)),
                    ],
                  ),
                ),
              ),
            ),
            if (widget.soundUrl.isNotEmpty)
              Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: _buildSoundCard()),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeTab(
      {required String mode,
      required IconData icon,
      required String headline,
      required String tagline,
      required List<Color> gradientColors}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      child: Column(
        children: [
          Container(
            width: 110,
            height: 110,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                  colors: gradientColors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                    color: gradientColors.first.withOpacity(0.4),
                    blurRadius: 28,
                    spreadRadius: 2,
                    offset: const Offset(0, 6))
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 56),
          ),
          const SizedBox(height: 18),
          Text(headline,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(tagline,
              style: const TextStyle(color: Colors.white54, fontSize: 14),
              textAlign: TextAlign.center),
          const Spacer(),
          Row(
            children: [
              Expanded(
                  child: _BigPickBtn(
                      icon: Icons.videocam_rounded,
                      label: 'Camera',
                      gradientColors: gradientColors,
                      onTap: () => _pickMedia(mode: mode, fromCamera: true))),
              const SizedBox(width: 14),
              Expanded(
                  child: _BigPickBtn(
                      icon: Icons.photo_library_rounded,
                      label: 'Gallery',
                      gradientColors: const [
                        Color(0xFF1c1c1e),
                        Color(0xFF2c2c2e)
                      ],
                      bordered: true,
                      onTap: () => _pickMedia(mode: mode, fromCamera: false))),
            ],
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildTextScreen() {
    final bg = _textBgs[_textBgIdx];
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
            decoration: BoxDecoration(
                gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: bg))),
        SafeArea(
          child: Column(
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    _IconBtn(
                        icon: Icons.close,
                        onTap: () => setState(() => _textPostMode = false)),
                    const Spacer(),
                    const Text('Text',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w700)),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => setState(() =>
                          _textBgIdx = (_textBgIdx + 1) % _textBgs.length),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                            color: Colors.white12,
                            borderRadius: BorderRadius.circular(10)),
                        child: const Icon(Icons.palette_outlined,
                            color: Colors.white, size: 22),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: TextField(
                      controller: _textPostCtrl,
                      autofocus: true,
                      maxLines: null,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          height: 1.4),
                      decoration: const InputDecoration(
                          hintText: 'Say something...',
                          hintStyle:
                              TextStyle(color: Colors.white38, fontSize: 22),
                          border: InputBorder.none),
                    ),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                color: Colors.black45,
                child: Row(
                    children: [_privacyPill(), const Spacer(), _postButton()]),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewScreen() {
    final isVideo = _mode == 'reel';
    return Stack(
      fit: StackFit.expand,
      children: [
        if (isVideo && _videoInitialized && _videoCtrl != null)
          GestureDetector(
            onTap: () {
              final ctrl = _videoCtrl;
              if (ctrl == null) return;
              if (ctrl.value.isPlaying) {
                ctrl.pause();
              } else {
                ctrl.play();
              }
              setState(() {});
            },
            child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                    width: _videoCtrl!.value.size.width,
                    height: _videoCtrl!.value.size.height,
                    child: VideoPlayer(_videoCtrl!))),
          )
        else if (!isVideo)
          Image.file(File(_selected!.path),
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity)
        else
          const Center(
              child: CircularProgressIndicator(
                  color: Colors.white54, strokeWidth: 2)),
        Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 160,
            child: Container(
                decoration: const BoxDecoration(
                    gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.black87, Colors.transparent])))),
        Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 430,
            child: Container(
                decoration: const BoxDecoration(
                    gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Colors.black, Colors.transparent])))),
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                _IconBtn(icon: Icons.arrow_back, onTap: _clearSelection),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white24)),
                  child: Text(_mode == 'reel' ? '🎬  Reel' : '📖  Story',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 13)),
                ),
              ],
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                  top: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.soundUrl.isNotEmpty) ...[
                    _buildSoundCard(),
                    const SizedBox(height: 10)
                  ],
                  Container(
                    decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white12)),
                    child: TextField(
                      controller: _captionCtrl,
                      maxLines: 4,
                      minLines: 2,
                      style: const TextStyle(color: Colors.white, fontSize: 15),
                      decoration: const InputDecoration(
                        hintText:
                            'Describe your video, add #hashtags @mentions',
                        hintStyle:
                            TextStyle(color: Colors.white38, fontSize: 14),
                        border: InputBorder.none,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.07),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white10)),
                    child: Column(
                      children: [
                        _SettingRow(
                          icon: _privacy == 'public'
                              ? Icons.public
                              : _privacy == 'private'
                                  ? Icons.lock_outline
                                  : (_privacy == 'paid_only' ||
                                          _privacy == 'paid')
                                      ? Icons.workspace_premium_outlined
                                      : (_privacy == 'verified_only' ||
                                              _privacy == 'verified')
                                          ? Icons.verified_outlined
                                          : Icons.people_outline,
                          label: 'Who can watch',
                          value: _privacy == 'public'
                              ? 'Everyone'
                              : _privacy == 'private'
                                  ? 'Only me'
                                  : _privacy == 'matches_only'
                                      ? 'Matches only'
                                      : (_privacy == 'paid_only' ||
                                              _privacy == 'paid')
                                          ? 'Paid members only'
                                          : 'Verified members only',
                          onTap: _showPrivacySheet,
                          showChevron: true,
                        ),
                        if (_mode == 'reel') ...[
                          Container(
                              height: 1,
                              margin:
                                  const EdgeInsets.symmetric(horizontal: 14),
                              color: Colors.white10),
                          _SettingToggle(
                              icon: Icons.comment_outlined,
                              label: 'Allow comments',
                              value: _allowComments,
                              onChange: (v) =>
                                  setState(() => _allowComments = v)),
                          Container(
                              height: 1,
                              margin:
                                  const EdgeInsets.symmetric(horizontal: 14),
                              color: Colors.white10),
                          _SettingToggle(
                              icon: Icons.call_split_rounded,
                              label: 'Allow duet',
                              value: _allowDuet,
                              onChange: (v) => setState(() => _allowDuet = v)),
                          Container(
                              height: 1,
                              margin:
                                  const EdgeInsets.symmetric(horizontal: 14),
                              color: Colors.white10),
                          _SettingToggle(
                              icon: Icons.download_outlined,
                              label: 'Allow save',
                              value: _allowDownload,
                              onChange: (v) =>
                                  setState(() => _allowDownload = v)),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed:
                              _uploading ? null : () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.white38),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(28))),
                          child: const Text('Discard',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w600)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: GestureDetector(
                          onTap: _uploading ? null : _uploadNow,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            decoration: BoxDecoration(
                              gradient: _uploading
                                  ? null
                                  : const LinearGradient(colors: [
                                      Color(0xFFFF0050),
                                      Color(0xFFFF4081)
                                    ]),
                              color: _uploading ? Colors.white24 : null,
                              borderRadius: BorderRadius.circular(28),
                              boxShadow: _uploading
                                  ? null
                                  : [
                                      BoxShadow(
                                          color: const Color(0xFFFF0050)
                                              .withOpacity(0.5),
                                          blurRadius: 16)
                                    ],
                            ),
                            child: Center(
                                child: _uploading
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2))
                                    : const Text('Post',
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 17))),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _privacyPill() {
    final privacyLabel = _privacy == 'public'
        ? 'Everyone'
        : _privacy == 'private'
            ? 'Only me'
            : _privacy == 'matches_only'
                ? 'Matches'
                : (_privacy == 'paid_only' || _privacy == 'paid')
                    ? 'Paid only'
                    : 'Verified only';

    final privacyIcon = _privacy == 'public'
        ? Icons.public
        : _privacy == 'private'
            ? Icons.lock_outline
            : (_privacy == 'paid_only' || _privacy == 'paid')
                ? Icons.workspace_premium_outlined
                : (_privacy == 'verified_only' || _privacy == 'verified')
                    ? Icons.verified_outlined
                    : Icons.people_outline;

    return GestureDetector(
      onTap: _showPrivacySheet,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
            color: Colors.white12,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white24)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(privacyIcon, color: Colors.white70, size: 16),
            const SizedBox(width: 6),
            Text(privacyLabel,
                style: const TextStyle(color: Colors.white, fontSize: 13)),
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down,
                color: Colors.white54, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _postButton() {
    return GestureDetector(
      onTap: _uploading ? null : _uploadNow,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 11),
        decoration: BoxDecoration(
          gradient: _uploading
              ? null
              : const LinearGradient(
                  colors: [Color(0xFFFF0050), Color(0xFFFF4081)]),
          color: _uploading ? Colors.white24 : null,
          borderRadius: BorderRadius.circular(28),
          boxShadow: _uploading
              ? null
              : [
                  BoxShadow(
                      color: const Color(0xFFFF0050).withOpacity(0.5),
                      blurRadius: 14)
                ],
        ),
        child: _uploading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2))
            : const Text('Post',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16)),
      ),
    );
  }

  Widget _buildSoundCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white24)),
      child: Row(
        children: [
          Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                  color: Color(0xFFFF0050), shape: BoxShape.circle),
              child: Icon(_soundPlaying ? Icons.pause : Icons.music_note,
                  color: Colors.white, size: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    widget.soundTitle.isNotEmpty
                        ? widget.soundTitle
                        : 'Original Sound',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const Text('Added sound',
                    style: TextStyle(color: Colors.white54, fontSize: 11)),
              ],
            ),
          ),
          GestureDetector(
            onTap: () async {
              if (_soundPlaying) {
                await _audioPlayer?.stop();
                setState(() => _soundPlaying = false);
              } else {
                _audioPlayer ??= AudioPlayer();
                await _audioPlayer!.play(UrlSource(widget.soundUrl));
                setState(() => _soundPlaying = true);
                _audioPlayer!.onPlayerComplete.listen((_) {
                  if (mounted) setState(() => _soundPlaying = false);
                });
              }
            },
            child: Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                  color: Colors.white12,
                  borderRadius: BorderRadius.circular(8)),
              child: Icon(_soundPlaying ? Icons.stop : Icons.play_arrow,
                  color: Colors.white, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  void _showPrivacySheet() {
    _videoCtrl?.pause();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1c1c1e),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) {
        const opts = [
          ('public', Icons.public, 'Everyone', 'All users can see this'),
          (
            'matches_only',
            Icons.people_outline,
            'Matches only',
            'Only your matches'
          ),
          (
            'paid_only',
            Icons.workspace_premium_outlined,
            'Paid members only',
            'Visible to paid members'
          ),
          (
            'verified_only',
            Icons.verified_outlined,
            'Verified members only',
            'Visible to verified users'
          ),
          ('private', Icons.lock_outline, 'Only me', 'Just you'),
        ];
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            const Text('Who can watch this?',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            for (final opt in opts)
              ListTile(
                leading: Icon(opt.$2,
                    color: _privacy == opt.$1
                        ? const Color(0xFFFF0050)
                        : Colors.white70),
                title: Text(opt.$3,
                    style: TextStyle(
                        color:
                            _privacy == opt.$1 ? Colors.white : Colors.white70,
                        fontWeight: _privacy == opt.$1
                            ? FontWeight.bold
                            : FontWeight.normal)),
                subtitle: Text(opt.$4,
                    style:
                        const TextStyle(color: Colors.white38, fontSize: 12)),
                trailing: _privacy == opt.$1
                    ? const Icon(Icons.check_circle, color: Color(0xFFFF0050))
                    : null,
                onTap: () {
                  setState(() => _privacy = opt.$1);
                  Navigator.pop(context);
                },
              ),
            const SizedBox(height: 16),
          ],
        );
      },
    ).then((_) => _videoCtrl?.play());
  }
}

class _BigPickBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final List<Color> gradientColors;
  final bool bordered;
  final VoidCallback onTap;
  const _BigPickBtn(
      {required this.icon,
      required this.label,
      required this.gradientColors,
      this.bordered = false,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          gradient: bordered
              ? null
              : LinearGradient(
                  colors: gradientColors,
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight),
          color: bordered ? Colors.transparent : null,
          borderRadius: BorderRadius.circular(16),
          border: bordered ? Border.all(color: Colors.white30) : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 22),
            const SizedBox(width: 8),
            Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15)),
          ],
        ),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _IconBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
            color: Colors.white12, borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;
  final bool showChevron;
  const _SettingRow(
      {required this.icon,
      required this.label,
      required this.value,
      required this.onTap,
      this.showChevron = false});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            Icon(icon, color: Colors.white70, size: 20),
            const SizedBox(width: 12),
            Text(label,
                style: const TextStyle(color: Colors.white, fontSize: 14)),
            const Spacer(),
            Text(value,
                style: const TextStyle(color: Colors.white54, fontSize: 14)),
            if (showChevron) ...[
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, color: Colors.white38, size: 18)
            ],
          ],
        ),
      ),
    );
  }
}

class _SettingToggle extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChange;
  const _SettingToggle(
      {required this.icon,
      required this.label,
      required this.value,
      required this.onChange});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: Colors.white70, size: 20),
          const SizedBox(width: 12),
          Text(label,
              style: const TextStyle(color: Colors.white, fontSize: 14)),
          const Spacer(),
          Switch(
            value: value,
            onChanged: onChange,
            activeColor: const Color(0xFFFF0050),
            activeTrackColor: Color.fromRGBO(255, 0, 80, 0.35),
            inactiveThumbColor: Colors.white38,
            inactiveTrackColor: Colors.white12,
          ),
        ],
      ),
    );
  }
}
