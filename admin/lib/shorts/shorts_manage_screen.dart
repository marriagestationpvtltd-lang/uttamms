import 'dart:convert';

import 'package:adminmrz/auth/service.dart';
import 'package:adminmrz/config/app_endpoints.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

class ShortsManageScreen extends StatefulWidget {
  const ShortsManageScreen({super.key});

  @override
  State<ShortsManageScreen> createState() => _ShortsManageScreenState();
}

class _AdminReelsViewer extends StatefulWidget {
  const _AdminReelsViewer({
    required this.reels,
    required this.initialIndex,
    required this.resolveUrl,
    required this.onChangePrivacy,
    required this.onDelete,
    required this.privacyLabel,
    required this.toast,
  });

  final List<Map<String, dynamic>> reels;
  final int initialIndex;
  final String Function(String) resolveUrl;
  final Future<void> Function(Map<String, dynamic>, String) onChangePrivacy;
  final Future<void> Function(Map<String, dynamic>) onDelete;
  final String Function(String?) privacyLabel;
  final void Function(String) toast;

  @override
  State<_AdminReelsViewer> createState() => _AdminReelsViewerState();
}

class _AdminReelsViewerState extends State<_AdminReelsViewer> {
  late final PageController _page;
  final Map<int, VideoPlayerController> _controllers = {};
  final Map<int, bool> _errors = {};
  int _idx = 0;
  bool _flashIcon = false;

  @override
  void initState() {
    super.initState();
    _idx = widget.initialIndex.clamp(0, widget.reels.length - 1);
    _page = PageController(initialPage: _idx);
    _prime(_idx);
    _prime(_idx + 1);
  }

  Future<void> _prime(int i) async {
    if (i < 0 || i >= widget.reels.length) return;
    if (_controllers.containsKey(i) || _errors[i] == true) return;
    final raw = (widget.reels[i]['video_url']?.toString() ?? '').trim();
    final url = widget.resolveUrl(raw);
    if (url.isEmpty) {
      if (mounted) setState(() => _errors[i] = true);
      return;
    }
    final c = VideoPlayerController.networkUrl(Uri.parse(url));
    _controllers[i] = c;
    try {
      await c.initialize();
      await c.setLooping(true);
      if (!mounted) return;
      if (i == _idx) await c.play();
      setState(() {});
    } catch (_) {
      _controllers.remove(i);
      if (mounted) setState(() => _errors[i] = true);
    }
  }

  void _syncPlay() {
    for (final e in _controllers.entries) {
      e.key == _idx ? e.value.play() : e.value.pause();
    }
  }

  @override
  void dispose() {
    _page.dispose();
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<String?> _privacyDialog(String current) => showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF1F2937),
      title: const Text('Privacy', style: TextStyle(color: Colors.white)),
      content: SizedBox(
        width: 280,
        child: ListView(
          shrinkWrap: true,
          children: ['public', 'matches_only', 'paid_only', 'verified_only', 'private']
              .map(
                (p) => RadioListTile<String>(
                  value: p,
                  groupValue: current,
                  onChanged: (v) => Navigator.of(ctx).pop(v),
                  title: Text(widget.privacyLabel(p),
                      style: const TextStyle(color: Colors.white)),
                  activeColor: Colors.white,
                  dense: true,
                ),
              )
              .toList(),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (widget.reels.isEmpty) {
      return const Scaffold(
          backgroundColor: Colors.black,
          body: Center(child: Text('No reels', style: TextStyle(color: Colors.white))));
    }
    final screenW = MediaQuery.sizeOf(context).width;
    final isWide = screenW > 640;

    // Core viewer: video-only PageView + fixed overlay Stack
    Widget viewer = Stack(
      children: [
        // ── Layer 1: video-only PageView — this is what scrolls ──────────
        PageView.builder(
          controller: _page,
          scrollDirection: Axis.vertical,
          itemCount: widget.reels.length,
          onPageChanged: (i) {
            setState(() => _idx = i);
            _prime(i);
            _prime(i + 1);
            _syncPlay();
          },
          itemBuilder: (_, i) => _buildVideoSlot(i),
        ),
        // ── Layer 2: fixed overlay — never moves when swiping ────────────
        _buildOverlay(),
      ],
    );

    // On wide screens (web) constrain to phone frame, centered
    if (isWide) {
      viewer = ColoredBox(
        color: Colors.black,
        child: Center(
          child: SizedBox(
            width: 420,
            child: ClipRect(child: viewer),
          ),
        ),
      );
    }

    return Scaffold(backgroundColor: Colors.black, body: viewer);
  }

  Widget _buildVideoSlot(int i) {
    if (_errors[i] == true) {
      return ColoredBox(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.videocam_off_outlined, color: Colors.white30, size: 56),
              SizedBox(height: 12),
              Text('Video unavailable',
                  style: TextStyle(color: Colors.white38, fontSize: 14)),
            ],
          ),
        ),
      );
    }
    final c = _controllers[i];
    if (c == null || !c.value.isInitialized) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(child: CircularProgressIndicator(color: Colors.white54, strokeWidth: 2)),
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        setState(() => _flashIcon = true);
        c.value.isPlaying ? c.pause() : c.play();
        Future.delayed(
          const Duration(milliseconds: 800),
          () { if (mounted) setState(() => _flashIcon = false); },
        );
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: c.value.size.width,
              height: c.value.size.height,
              child: VideoPlayer(c),
            ),
          ),
          if (_flashIcon && i == _idx)
            Center(
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  c.value.isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                  size: 44,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOverlay() {
    final reel = widget.reels[_idx];
    final caption = (reel['caption']?.toString() ?? '').trim();
    final privacy = (reel['privacy']?.toString() ?? 'public').trim();
    final userId = reel['user_id']?.toString() ?? '-';
    final likes = reel['like_count']?.toString() ?? '0';
    final views = reel['view_count']?.toString() ?? '0';
    final c = _controllers[_idx];
    final hasProgress = c != null && c.value.isInitialized;

    return Stack(
      children: [
        // top gradient
        Positioned(
          top: 0, left: 0, right: 0, height: 120,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black.withOpacity(0.55), Colors.transparent],
              ),
            ),
          ),
        ),
        // bottom gradient
        Positioned(
          bottom: 0, left: 0, right: 0, height: 240,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Colors.black.withOpacity(0.85), Colors.transparent],
              ),
            ),
          ),
        ),
        // back button
        Positioned(
          top: 0, left: 0,
          child: SafeArea(
            child: IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
            ),
          ),
        ),
        // counter
        Positioned(
          top: 0, left: 0, right: 0,
          child: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Text(
                  '${_idx + 1} / ${widget.reels.length}',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            ),
          ),
        ),
        // menu
        Positioned(
          top: 0, right: 0,
          child: SafeArea(
            child: PopupMenuButton<String>(
              color: const Color(0xFF1F2937),
              icon: const Icon(Icons.more_vert, color: Colors.white),
              onSelected: (v) async {
                if (v == 'privacy') {
                  final sel = await _privacyDialog(privacy);
                  if (sel != null && sel != privacy) {
                    await widget.onChangePrivacy(reel, sel);
                    if (mounted) setState(() => reel['privacy'] = sel);
                  }
                } else if (v == 'delete') {
                  await widget.onDelete(reel);
                  if (mounted) Navigator.of(context).pop();
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'privacy',
                  child: Row(children: [
                    Icon(Icons.lock_outline, size: 18, color: Colors.white70),
                    SizedBox(width: 8),
                    Text('Change Privacy', style: TextStyle(color: Colors.white)),
                  ]),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(children: [
                    Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                    SizedBox(width: 8),
                    Text('Delete', style: TextStyle(color: Colors.redAccent)),
                  ]),
                ),
              ],
            ),
          ),
        ),
        // caption + user info
        Positioned(
          left: 16, right: 76, bottom: hasProgress ? 52 : 28,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (caption.isNotEmpty)
                Text(
                  caption,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    shadows: [Shadow(blurRadius: 6, color: Colors.black)],
                  ),
                ),
              const SizedBox(height: 6),
              Row(children: [
                const Icon(Icons.person_outline, size: 13, color: Colors.white60),
                const SizedBox(width: 4),
                Text('User $userId',
                    style: const TextStyle(color: Colors.white60, fontSize: 12)),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(widget.privacyLabel(privacy),
                      style: const TextStyle(color: Colors.white, fontSize: 11)),
                ),
              ]),
            ],
          ),
        ),
        // side stats
        Positioned(
          right: 10, bottom: hasProgress ? 52 : 28,
          child: Column(children: [
            _viewerBadge(Icons.favorite_border, likes),
            const SizedBox(height: 10),
            _viewerBadge(Icons.visibility_outlined, views),
          ]),
        ),
        // progress bar
        if (hasProgress)
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: VideoProgressIndicator(
              c!,
              allowScrubbing: true,
              colors: const VideoProgressColors(
                playedColor: Colors.white,
                bufferedColor: Colors.white24,
                backgroundColor: Colors.white12,
              ),
              padding: const EdgeInsets.symmetric(vertical: 8),
            ),
          ),
      ],
    );
  }
}

class _AdminStoriesViewer extends StatefulWidget {
  const _AdminStoriesViewer({
    required this.stories,
    required this.initialIndex,
    required this.resolveUrl,
    required this.onChangePrivacy,
    required this.onDelete,
    required this.privacyLabel,
    required this.toast,
  });

  final List<Map<String, dynamic>> stories;
  final int initialIndex;
  final String Function(String) resolveUrl;
  final Future<void> Function(Map<String, dynamic>, String) onChangePrivacy;
  final Future<void> Function(Map<String, dynamic>) onDelete;
  final String Function(String?) privacyLabel;
  final void Function(String) toast;

  @override
  State<_AdminStoriesViewer> createState() => _AdminStoriesViewerState();
}

class _AdminStoriesViewerState extends State<_AdminStoriesViewer> {
  late final PageController _page;
  final Map<int, VideoPlayerController> _controllers = {};
  final Map<int, bool> _errors = {};
  int _idx = 0;
  bool _flashIcon = false;

  @override
  void initState() {
    super.initState();
    _idx = widget.initialIndex.clamp(0, widget.stories.length - 1);
    _page = PageController(initialPage: _idx);
    _prime(_idx);
    _prime(_idx + 1);
  }

  Future<void> _prime(int i) async {
    if (i < 0 || i >= widget.stories.length) return;
    if (_controllers.containsKey(i) || _errors[i] == true) return;
    final s = widget.stories[i];
    final isVideo = (s['media_type']?.toString() ?? 'image').trim() == 'video';
    if (!isVideo) return; // images don't need a controller
    final raw = (s['media_url']?.toString() ?? '').trim();
    final url = widget.resolveUrl(raw);
    if (url.isEmpty) {
      if (mounted) setState(() => _errors[i] = true);
      return;
    }
    final c = VideoPlayerController.networkUrl(Uri.parse(url));
    _controllers[i] = c;
    try {
      await c.initialize();
      await c.setLooping(true);
      if (!mounted) return;
      if (i == _idx) await c.play();
      setState(() {});
    } catch (_) {
      _controllers.remove(i);
      if (mounted) setState(() => _errors[i] = true);
    }
  }

  void _syncPlay() {
    for (final e in _controllers.entries) {
      e.key == _idx ? e.value.play() : e.value.pause();
    }
  }

  @override
  void dispose() {
    _page.dispose();
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<String?> _privacyDialog(String current) => showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF1F2937),
      title: const Text('Privacy', style: TextStyle(color: Colors.white)),
      content: SizedBox(
        width: 280,
        child: ListView(
          shrinkWrap: true,
          children: ['public', 'matches_only', 'paid_only', 'verified_only', 'private']
              .map(
                (p) => RadioListTile<String>(
                  value: p,
                  groupValue: current,
                  onChanged: (v) => Navigator.of(ctx).pop(v),
                  title: Text(widget.privacyLabel(p),
                      style: const TextStyle(color: Colors.white)),
                  activeColor: Colors.white,
                  dense: true,
                ),
              )
              .toList(),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (widget.stories.isEmpty) {
      return const Scaffold(
          backgroundColor: Colors.black,
          body: Center(child: Text('No stories', style: TextStyle(color: Colors.white))));
    }
    final screenW = MediaQuery.sizeOf(context).width;
    final isWide = screenW > 640;

    Widget viewer = Stack(
      children: [
        // ── Layer 1: media-only PageView — this is what scrolls ──────────
        PageView.builder(
          controller: _page,
          scrollDirection: Axis.vertical,
          itemCount: widget.stories.length,
          onPageChanged: (i) {
            setState(() => _idx = i);
            _prime(i);
            _prime(i + 1);
            _syncPlay();
          },
          itemBuilder: (_, i) => _buildMediaSlot(i),
        ),
        // ── Layer 2: fixed overlay — never moves when swiping ────────────
        _buildOverlay(),
      ],
    );

    if (isWide) {
      viewer = ColoredBox(
        color: Colors.black,
        child: Center(
          child: SizedBox(
            width: 420,
            child: ClipRect(child: viewer),
          ),
        ),
      );
    }

    return Scaffold(backgroundColor: Colors.black, body: viewer);
  }

  Widget _buildMediaSlot(int i) {
    final s = widget.stories[i];
    final isVideo = (s['media_type']?.toString() ?? 'image').trim() == 'video';
    final mediaUrl = widget.resolveUrl((s['media_url']?.toString() ?? '').trim());

    if (!isVideo) {
      // Image story
      if (mediaUrl.isEmpty) {
        return const ColoredBox(
            color: Colors.black,
            child: Center(child: Icon(Icons.broken_image, color: Colors.white30, size: 56)));
      }
      return ColoredBox(
        color: Colors.black,
        child: Image.network(mediaUrl, fit: BoxFit.contain,
            errorBuilder: (_, __, ___) =>
                const Center(child: Icon(Icons.broken_image, color: Colors.white30, size: 56))),
      );
    }

    if (_errors[i] == true) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.videocam_off_outlined, color: Colors.white30, size: 56),
              SizedBox(height: 12),
              Text('Video unavailable', style: TextStyle(color: Colors.white38, fontSize: 14)),
            ],
          ),
        ),
      );
    }

    final c = _controllers[i];
    if (c == null || !c.value.isInitialized) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(child: CircularProgressIndicator(color: Colors.white54, strokeWidth: 2)),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        setState(() => _flashIcon = true);
        c.value.isPlaying ? c.pause() : c.play();
        Future.delayed(
          const Duration(milliseconds: 800),
          () { if (mounted) setState(() => _flashIcon = false); },
        );
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: c.value.size.width,
              height: c.value.size.height,
              child: VideoPlayer(c),
            ),
          ),
          if (_flashIcon && i == _idx)
            Center(
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  c.value.isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                  size: 44,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOverlay() {
    final s = widget.stories[_idx];
    final caption = (s['caption']?.toString() ?? '').trim();
    final privacy = (s['privacy']?.toString() ?? 'public').trim();
    final userId = s['user_id']?.toString() ?? '-';
    final isVideo = (s['media_type']?.toString() ?? 'image').trim() == 'video';
    final c = isVideo ? _controllers[_idx] : null;
    final hasProgress = c != null && c.value.isInitialized;

    return Stack(
      children: [
        Positioned(
          top: 0, left: 0, right: 0, height: 120,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black.withOpacity(0.55), Colors.transparent],
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 0, left: 0, right: 0, height: 200,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Colors.black.withOpacity(0.85), Colors.transparent],
              ),
            ),
          ),
        ),
        Positioned(
          top: 0, left: 0,
          child: SafeArea(
            child: IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
            ),
          ),
        ),
        Positioned(
          top: 0, left: 0, right: 0,
          child: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Text(
                  '${_idx + 1} / ${widget.stories.length}',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: 0, right: 0,
          child: SafeArea(
            child: PopupMenuButton<String>(
              color: const Color(0xFF1F2937),
              icon: const Icon(Icons.more_vert, color: Colors.white),
              onSelected: (v) async {
                if (v == 'privacy') {
                  final sel = await _privacyDialog(privacy);
                  if (sel != null && sel != privacy) {
                    await widget.onChangePrivacy(s, sel);
                    if (mounted) setState(() => s['privacy'] = sel);
                  }
                } else if (v == 'delete') {
                  await widget.onDelete(s);
                  if (mounted) Navigator.of(context).pop();
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'privacy',
                  child: Row(children: [
                    Icon(Icons.lock_outline, size: 18, color: Colors.white70),
                    SizedBox(width: 8),
                    Text('Change Privacy', style: TextStyle(color: Colors.white)),
                  ]),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(children: [
                    Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                    SizedBox(width: 8),
                    Text('Delete', style: TextStyle(color: Colors.redAccent)),
                  ]),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          left: 16, right: 16, bottom: hasProgress ? 52 : 28,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (caption.isNotEmpty)
                Text(
                  caption,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    shadows: [Shadow(blurRadius: 6, color: Colors.black)],
                  ),
                ),
              const SizedBox(height: 6),
              Row(children: [
                const Icon(Icons.person_outline, size: 13, color: Colors.white60),
                const SizedBox(width: 4),
                Text('User $userId',
                    style: const TextStyle(color: Colors.white60, fontSize: 12)),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(widget.privacyLabel(privacy),
                      style: const TextStyle(color: Colors.white, fontSize: 11)),
                ),
              ]),
            ],
          ),
        ),
        if (hasProgress)
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: VideoProgressIndicator(
              c!,
              allowScrubbing: true,
              colors: const VideoProgressColors(
                playedColor: Colors.white,
                bufferedColor: Colors.white24,
                backgroundColor: Colors.white12,
              ),
              padding: const EdgeInsets.symmetric(vertical: 8),
            ),
          ),
      ],
    );
  }
}

Widget _viewerBadge(IconData icon, String text) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
  decoration: BoxDecoration(
    color: Colors.black.withOpacity(0.45),
    borderRadius: BorderRadius.circular(20),
    border: Border.all(color: Colors.white24),
  ),
  child: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 15, color: Colors.white),
      const SizedBox(width: 6),
      Text(text, style: const TextStyle(color: Colors.white, fontSize: 12)),
    ],
  ),
);

class _ShortsManageScreenState extends State<ShortsManageScreen>
    with SingleTickerProviderStateMixin {
  // ── palette ──────────────────────────────────────────────────────────────
  static const Color _cBlue = Color(0xFF1D4ED8);
  static const Color _cViolet = Color(0xFF7C3AED);
  static const Color _cGreen = Color(0xFF059669);
  static const Color _cAmber = Color(0xFFD97706);
  static const Color _cRed = Color(0xFFDC2626);
  static const Color _cPink = Color(0xFFDB2777);
  static const Color _cBorder = Color(0xFFE5E7EB);
  static const Color _cMuted = Color(0xFF6B7280);

  late final TabController _tab;
  bool _didInitSession = false;
  int _sessionAdminId = 0;
  ScaffoldMessengerState? _messenger;

  // Reel upload
  final _reelUserCtrl = TextEditingController();
  final _reelCaptionCtrl = TextEditingController();
  PlatformFile? _reelFile;
  String _reelPrivacy = 'public';
  bool _uploadingReel = false;
  bool _reelPostAsAdminSelf = false;

  // Story upload
  final _storyUserCtrl = TextEditingController();
  final _storyCaptionCtrl = TextEditingController();
  PlatformFile? _storyFile;
  String _storyPrivacy = 'public';
  bool _uploadingStory = false;
  bool _storyPostAsAdminSelf = false;

  // Browse
  final _filterUserCtrl = TextEditingController();
  bool _browseAll = true;
  bool _loadingReels = false;
  bool _loadingStories = false;
  List<Map<String, dynamic>> _reels = [];
  List<Map<String, dynamic>> _stories = [];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _messenger = ScaffoldMessenger.maybeOf(context);
    if (_didInitSession) return;
    final admin = context.read<AuthProvider>().adminData;
    final adminId = int.tryParse(admin?['id']?.toString() ?? '') ?? 1;
    _sessionAdminId = adminId;
    // Leave user ID fields empty — admin must enter a real user ID from the
    // users table (admin IDs are not in users and will violate the FK).
    _reelUserCtrl.text = '';
    _storyUserCtrl.text = '';
    _didInitSession = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadReels();
      _loadStories();
    });
  }

  @override
  void dispose() {
    _tab.dispose();
    _reelUserCtrl.dispose();
    _reelCaptionCtrl.dispose();
    _storyUserCtrl.dispose();
    _storyCaptionCtrl.dispose();
    _filterUserCtrl.dispose();
    super.dispose();
  }

  // ── file pickers ─────────────────────────────────────────────────────────
  Future<void> _pickReel() async {
    final r = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['mp4', 'mov', 'webm', 'avi', 'mkv', '3gp'],
    );
    if (r != null && r.files.isNotEmpty)
      setState(() => _reelFile = r.files.single);
  }

  Future<void> _pickStory() async {
    final r = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: const [
        'jpg',
        'jpeg',
        'png',
        'webp',
        'mp4',
        'mov',
        'webm',
      ],
    );
    if (r != null && r.files.isNotEmpty)
      setState(() => _storyFile = r.files.single);
  }

  MediaType _mtype(String name, {required bool story}) {
    final e = name.split('.').last.toLowerCase();
    if (story && ['jpg', 'jpeg', 'png', 'webp'].contains(e)) {
      return MediaType('image', e == 'jpg' ? 'jpeg' : e);
    }
    return MediaType('video', e.isEmpty ? 'mp4' : e);
  }

  // ── upload reel ──────────────────────────────────────────────────────────
  Future<void> _uploadReel() async {
    final uid = int.tryParse(_reelUserCtrl.text.trim()) ?? 0;
    if (_reelFile == null || (!_reelPostAsAdminSelf && uid <= 0)) {
      _toast(
        _reelPostAsAdminSelf
            ? 'Select a video file'
            : 'Select a video file and enter a valid user ID',
      );
      return;
    }
    final effectiveUid = _reelPostAsAdminSelf ? _sessionAdminId : uid;
    setState(() => _uploadingReel = true);
    try {
      final req = http.MultipartRequest(
        'POST',
        Uri.parse(kAdminEndpointUploadReel),
      );
      req.fields.addAll({
        'user_id': '$effectiveUid',
        'caption': _reelCaptionCtrl.text.trim(),
        'privacy': _reelPrivacy,
        'as_admin': '1',
        'admin_id': '$_sessionAdminId',
        'post_as_admin_self': _reelPostAsAdminSelf ? '1' : '0',
      });
      final f = _reelFile!;
      if (f.bytes != null) {
        req.files.add(
          http.MultipartFile.fromBytes(
            'reel',
            f.bytes!,
            filename: f.name,
            contentType: _mtype(f.name, story: false),
          ),
        );
      } else if (f.path != null) {
        req.files.add(
          await http.MultipartFile.fromPath(
            'reel',
            f.path!,
            contentType: _mtype(f.name, story: false),
          ),
        );
      } else {
        throw Exception('File not readable');
      }
      final res = await req.send();
      final body = await res.stream.bytesToString();
      final j = jsonDecode(body) as Map<String, dynamic>;
      if (res.statusCode < 300 && j['success'] == true) {
        _toast('Reel uploaded successfully');
        setState(() => _reelFile = null);
        _reelCaptionCtrl.clear();
        await _loadReels();
        _tab.animateTo(2);
      } else {
        _toast(j['message']?.toString() ?? 'Upload failed');
      }
    } catch (e) {
      _toast('Error: $e');
    } finally {
      if (mounted) setState(() => _uploadingReel = false);
    }
  }

  // ── upload story ─────────────────────────────────────────────────────────
  Future<void> _uploadStory() async {
    final uid = int.tryParse(_storyUserCtrl.text.trim()) ?? 0;
    if (_storyFile == null || (!_storyPostAsAdminSelf && uid <= 0)) {
      _toast(
        _storyPostAsAdminSelf
            ? 'Select a media file'
            : 'Select a media file and enter a valid user ID',
      );
      return;
    }
    final effectiveUid = _storyPostAsAdminSelf ? _sessionAdminId : uid;
    setState(() => _uploadingStory = true);
    try {
      final req = http.MultipartRequest(
        'POST',
        Uri.parse(kAdminEndpointUploadStory),
      );
      req.fields.addAll({
        'user_id': '$effectiveUid',
        'caption': _storyCaptionCtrl.text.trim(),
        'privacy': _storyPrivacy,
        'as_admin': '1',
        'admin_id': '$_sessionAdminId',
        'post_as_admin_self': _storyPostAsAdminSelf ? '1' : '0',
      });
      final f = _storyFile!;
      if (f.bytes != null) {
        req.files.add(
          http.MultipartFile.fromBytes(
            'story',
            f.bytes!,
            filename: f.name,
            contentType: _mtype(f.name, story: true),
          ),
        );
      } else if (f.path != null) {
        req.files.add(
          await http.MultipartFile.fromPath(
            'story',
            f.path!,
            contentType: _mtype(f.name, story: true),
          ),
        );
      } else {
        throw Exception('File not readable');
      }
      final res = await req.send();
      final body = await res.stream.bytesToString();
      final j = jsonDecode(body) as Map<String, dynamic>;
      if (res.statusCode < 300 && j['success'] == true) {
        _toast('Story uploaded successfully');
        setState(() => _storyFile = null);
        _storyCaptionCtrl.clear();
        await _loadStories();
        _tab.animateTo(2);
      } else {
        _toast(j['message']?.toString() ?? 'Upload failed');
      }
    } catch (e) {
      _toast('Error: $e');
    } finally {
      if (mounted) setState(() => _uploadingStory = false);
    }
  }

  // ── loaders ──────────────────────────────────────────────────────────────
  Future<void> _loadReels() async {
    setState(() => _loadingReels = true);
    try {
      final params = <String, String>{
        'sort': 'recent',
        'limit': '50',
        'as_admin': '1',
      };
      final fuid = int.tryParse(_filterUserCtrl.text.trim()) ?? 0;
      if (!_browseAll && fuid > 0) params['user_id'] = '$fuid';
      final uri = Uri.parse(
        kAdminEndpointReelFeed,
      ).replace(queryParameters: params);
      final res = await http.get(uri);
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode == 200 && j['success'] == true) {
        setState(() {
          _reels = (j['data'] as List? ?? [])
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingReels = false);
    }
  }

  Future<void> _loadStories() async {
    setState(() => _loadingStories = true);
    try {
      final fuid = int.tryParse(_filterUserCtrl.text.trim()) ?? 0;
      final params = <String, String>{'as_admin': '1'};
      if (!_browseAll && fuid > 0) {
        params['user_id'] = '$fuid';
        params['target_user_id'] = '$fuid';
      } else {
        params['user_id'] = '0';
        params['target_user_id'] = '0';
      }
      final uri = Uri.parse(
        kAdminEndpointUserStories,
      ).replace(queryParameters: params);
      final res = await http.get(uri);
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode == 200 && j['success'] == true) {
        final data = j['data'];
        if (data is Map && data['stories'] != null) {
          setState(() {
            _stories = (data['stories'] as List? ?? [])
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
          });
        } else if (data is List) {
          setState(() {
            _stories = data
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
          });
        }
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingStories = false);
    }
  }

  // ── helpers ──────────────────────────────────────────────────────────────
  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  String _absoluteMediaUrl(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return '';
    final uri = Uri.tryParse(value);
    if (uri != null && uri.hasScheme) return uri.toString();
    final clean = value.startsWith('/') ? value.substring(1) : value;
    return Uri.parse(kAdminApiBaseUrl).resolve('../$clean').toString();
  }

  int _toInt(dynamic v) => int.tryParse('${v ?? ''}') ?? 0;

  Future<String?> _pickPrivacyDialog(String current) async {
    final options = [
      'public',
      'matches_only',
      'paid_only',
      'verified_only',
      'private',
    ];
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Change Privacy'),
        content: SizedBox(
          width: 280,
          child: ListView(
            shrinkWrap: true,
            children: options
                .map(
                  (p) => RadioListTile<String>(
                    value: p,
                    groupValue: current,
                    onChanged: (v) => Navigator.of(ctx).pop(v),
                    title: Text(_privacyLabel(p)),
                    dense: true,
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
  }

  Future<void> _updateReelPrivacy(
    Map<String, dynamic> reel,
    String privacy,
  ) async {
    final reelId = _toInt(reel['id']);
    final userId = _toInt(reel['user_id']);
    if (reelId <= 0 || userId <= 0) return;
    try {
      final res = await http.post(
        Uri.parse(kAdminEndpointReelUpdatePrivacy),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'as_admin': 1,
          'admin_id': _sessionAdminId,
          'user_id': userId,
          'reel_id': reelId,
          'privacy': privacy,
        }),
      );
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode < 300 && j['success'] == true) {
        _toast('Reel privacy updated');
        await _loadReels();
      } else {
        _toast(j['message']?.toString() ?? 'Failed to update reel privacy');
      }
    } catch (e) {
      _toast('Error: $e');
    }
  }

  Future<void> _deleteReel(Map<String, dynamic> reel) async {
    final reelId = _toInt(reel['id']);
    final userId = _toInt(reel['user_id']);
    if (reelId <= 0 || userId <= 0) return;
    final ok =
        await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete Reel?'),
            content: const Text('This reel will be removed from active feed.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: FilledButton.styleFrom(backgroundColor: _cRed),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    try {
      final res = await http.post(
        Uri.parse(kAdminEndpointReelDelete),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'as_admin': 1,
          'admin_id': _sessionAdminId,
          'user_id': userId,
          'reel_id': reelId,
        }),
      );
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode < 300 && j['success'] == true) {
        _toast('Reel deleted');
        await _loadReels();
      } else {
        _toast(j['message']?.toString() ?? 'Failed to delete reel');
      }
    } catch (e) {
      _toast('Error: $e');
    }
  }

  Future<void> _updateStoryPrivacy(
    Map<String, dynamic> story,
    String privacy,
  ) async {
    final storyId = _toInt(story['id']);
    final userId = _toInt(story['user_id']);
    if (storyId <= 0 || userId <= 0) return;
    try {
      final res = await http.post(
        Uri.parse(kAdminEndpointStoryUpdatePrivacy),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'as_admin': 1,
          'admin_id': _sessionAdminId,
          'user_id': userId,
          'story_id': storyId,
          'privacy': privacy,
        }),
      );
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode < 300 && j['success'] == true) {
        _toast('Story privacy updated');
        await _loadStories();
      } else {
        _toast(j['message']?.toString() ?? 'Failed to update story privacy');
      }
    } catch (e) {
      _toast('Error: $e');
    }
  }

  Future<void> _deleteStory(Map<String, dynamic> story) async {
    final storyId = _toInt(story['id']);
    final userId = _toInt(story['user_id']);
    if (storyId <= 0 || userId <= 0) return;
    final ok =
        await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete Story?'),
            content: const Text('This story will be removed from active feed.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: FilledButton.styleFrom(backgroundColor: _cRed),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    try {
      final res = await http.post(
        Uri.parse(kAdminEndpointStoryDelete),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'as_admin': 1,
          'admin_id': _sessionAdminId,
          'user_id': userId,
          'story_id': storyId,
        }),
      );
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode < 300 && j['success'] == true) {
        _toast('Story deleted');
        await _loadStories();
      } else {
        _toast(j['message']?.toString() ?? 'Failed to delete story');
      }
    } catch (e) {
      _toast('Error: $e');
    }
  }

  Future<void> _openReelsViewer(int initialIndex) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _AdminReelsViewer(
          reels: _reels,
          initialIndex: initialIndex,
          resolveUrl: _absoluteMediaUrl,
          onChangePrivacy: (reel, privacy) => _updateReelPrivacy(reel, privacy),
          onDelete: (reel) => _deleteReel(reel),
          privacyLabel: _privacyLabel,
          toast: _toast,
        ),
      ),
    );
    if (mounted) {
      await _loadReels();
    }
  }

  Future<void> _openStoriesViewer(int initialIndex) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _AdminStoriesViewer(
          stories: _stories,
          initialIndex: initialIndex,
          resolveUrl: _absoluteMediaUrl,
          onChangePrivacy: (story, privacy) =>
              _updateStoryPrivacy(story, privacy),
          onDelete: (story) => _deleteStory(story),
          privacyLabel: _privacyLabel,
          toast: _toast,
        ),
      ),
    );
    if (mounted) {
      await _loadStories();
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    _messenger?.hideCurrentSnackBar();
    _messenger?.showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  List<DropdownMenuItem<String>> get _privacyItems => const [
    DropdownMenuItem(value: 'public', child: Text('Public')),
    DropdownMenuItem(value: 'matches_only', child: Text('Matches Only')),
    DropdownMenuItem(value: 'paid_only', child: Text('Paid Only')),
    DropdownMenuItem(value: 'verified_only', child: Text('Verified Only')),
    DropdownMenuItem(value: 'private', child: Text('Private')),
  ];

  String _privacyLabel(String? p) {
    switch ((p ?? '').trim()) {
      case 'matches_only':
        return 'Matches';
      case 'paid_only':
        return 'Paid';
      case 'verified_only':
        return 'Verified';
      case 'private':
        return 'Private';
      default:
        return 'Public';
    }
  }

  Color _privacyColor(String? p) {
    switch ((p ?? '').trim()) {
      case 'private':
        return _cRed;
      case 'matches_only':
        return _cPink;
      case 'paid_only':
        return _cAmber;
      case 'verified_only':
        return _cViolet;
      default:
        return _cGreen;
    }
  }

  String _fmtBytes(int b) {
    if (b < 1024) return '$b B';
    if (b < 1 << 20) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '${(b / (1 << 20)).toStringAsFixed(1)} MB';
  }

  // ── main build ───────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(isDark),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDark ? const Color(0xFF334155) : _cBorder,
            ),
          ),
          child: TabBar(
            controller: _tab,
            dividerColor: Colors.transparent,
            padding: EdgeInsets.zero,
            indicator: BoxDecoration(
              gradient: const LinearGradient(colors: [_cBlue, _cViolet]),
              borderRadius: BorderRadius.circular(10),
            ),
            labelColor: Colors.white,
            unselectedLabelColor: isDark ? const Color(0xFFCBD5E1) : _cMuted,
            tabs: const [
              Tab(
                icon: Icon(Icons.movie_creation_outlined, size: 17),
                text: 'Upload Reel',
              ),
              Tab(
                icon: Icon(Icons.add_photo_alternate_outlined, size: 17),
                text: 'Upload Story',
              ),
              Tab(
                icon: Icon(Icons.grid_view_rounded, size: 17),
                text: 'Browse All',
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: [
              _reelUploadTab(isDark, cs),
              _storyUploadTab(isDark, cs),
              _browseTab(isDark, cs),
            ],
          ),
        ),
      ],
    );
  }

  // ── header ────────────────────────────────────────────────────────────────
  Widget _buildHeader(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1D4ED8), Color(0xFF7C3AED)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.play_circle_fill_rounded,
              color: Colors.white,
              size: 30,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Reels & Stories Studio',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.3,
                  ),
                ),
                Text(
                  'Upload, manage and preview all media content',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.75),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            children: [
              _hdrBadge(Icons.movie_outlined, '${_reels.length}', 'Reels'),
              const SizedBox(height: 6),
              _hdrBadge(
                Icons.auto_stories_outlined,
                '${_stories.length}',
                'Stories',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _hdrBadge(IconData icon, String val, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.18),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            '$label: $val',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ── Upload Reel tab ───────────────────────────────────────────────────────
  Widget _reelUploadTab(bool isDark, ColorScheme cs) {
    return LayoutBuilder(
      builder: (ctx, box) {
        final wide = box.maxWidth >= 900;
        final form = _uploadForm(
          isDark: isDark,
          accentColor: _cBlue,
          icon: Icons.movie_creation_outlined,
          title: 'Upload Reel',
          subtitle: 'MP4 · MOV · WebM · AVI · MKV · 3GP',
          file: _reelFile,
          fileIcon: Icons.video_file_rounded,
          fileHint: 'Click to select a reel video',
          userCtrl: _reelUserCtrl,
          postAsAdminSelf: _reelPostAsAdminSelf,
          captionCtrl: _reelCaptionCtrl,
          privacy: _reelPrivacy,
          uploading: _uploadingReel,
          onPickFile: _pickReel,
          onClearFile: () => setState(() => _reelFile = null),
          onTogglePostAsSelf: (v) => setState(() => _reelPostAsAdminSelf = v),
          onPrivacyChanged: (v) => setState(() => _reelPrivacy = v ?? 'public'),
          onUpload: _uploadReel,
        );
        final preview = _previewPanel(
          isDark: isDark,
          title: 'Recent Reels',
          icon: Icons.smart_display_outlined,
          accentColor: _cBlue,
          loading: _loadingReels,
          isEmpty: _reels.isEmpty,
          emptyMsg: 'No reels found',
          emptyIcon: Icons.movie_outlined,
          onRefresh: _loadReels,
          list: ListView.builder(
            itemCount: _reels.length,
            itemBuilder: (_, i) => _reelCard(_reels[i], isDark, i),
          ),
        );
        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 420, child: form),
              const SizedBox(width: 16),
              Expanded(child: preview),
            ],
          );
        }
        return SingleChildScrollView(
          child: Column(
            children: [
              form,
              const SizedBox(height: 14),
              SizedBox(height: 480, child: preview),
            ],
          ),
        );
      },
    );
  }

  // ── Upload Story tab ──────────────────────────────────────────────────────
  Widget _storyUploadTab(bool isDark, ColorScheme cs) {
    return LayoutBuilder(
      builder: (ctx, box) {
        final wide = box.maxWidth >= 900;
        final form = _uploadForm(
          isDark: isDark,
          accentColor: _cViolet,
          icon: Icons.auto_stories_outlined,
          title: 'Upload Story',
          subtitle: 'Image: JPG · PNG · WebP   Video: MP4 · MOV',
          file: _storyFile,
          fileIcon: Icons.add_photo_alternate_rounded,
          fileHint: 'Click to select image or video',
          userCtrl: _storyUserCtrl,
          postAsAdminSelf: _storyPostAsAdminSelf,
          captionCtrl: _storyCaptionCtrl,
          privacy: _storyPrivacy,
          uploading: _uploadingStory,
          onPickFile: _pickStory,
          onClearFile: () => setState(() => _storyFile = null),
          onTogglePostAsSelf: (v) => setState(() => _storyPostAsAdminSelf = v),
          onPrivacyChanged: (v) =>
              setState(() => _storyPrivacy = v ?? 'public'),
          onUpload: _uploadStory,
        );
        final preview = _previewPanel(
          isDark: isDark,
          title: 'Recent Stories',
          icon: Icons.collections_bookmark_outlined,
          accentColor: _cViolet,
          loading: _loadingStories,
          isEmpty: _stories.isEmpty,
          emptyMsg: 'No stories found',
          emptyIcon: Icons.auto_stories_outlined,
          onRefresh: _loadStories,
          list: ListView.builder(
            itemCount: _stories.length,
            itemBuilder: (_, i) => _storyCard(_stories[i], isDark, i),
          ),
        );
        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 420, child: form),
              const SizedBox(width: 16),
              Expanded(child: preview),
            ],
          );
        }
        return SingleChildScrollView(
          child: Column(
            children: [
              form,
              const SizedBox(height: 14),
              SizedBox(height: 480, child: preview),
            ],
          ),
        );
      },
    );
  }

  // ── Browse All tab ────────────────────────────────────────────────────────
  Widget _browseTab(bool isDark, ColorScheme cs) {
    return Column(
      children: [
        _filterBar(isDark, cs),
        const SizedBox(height: 12),
        Expanded(
          child: LayoutBuilder(
            builder: (ctx, box) {
              final wide = box.maxWidth >= 700;
              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _previewPanel(
                        isDark: isDark,
                        title: 'Reels (${_reels.length})',
                        icon: Icons.movie_outlined,
                        accentColor: _cBlue,
                        loading: _loadingReels,
                        isEmpty: _reels.isEmpty,
                        emptyMsg: 'No reels found',
                        emptyIcon: Icons.movie_outlined,
                        onRefresh: _loadReels,
                        list: ListView.builder(
                          itemCount: _reels.length,
                          itemBuilder: (_, i) =>
                              _reelCard(_reels[i], isDark, i),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    SizedBox(
                      width: 340,
                      child: _previewPanel(
                        isDark: isDark,
                        title: 'Stories (${_stories.length})',
                        icon: Icons.auto_stories_outlined,
                        accentColor: _cViolet,
                        loading: _loadingStories,
                        isEmpty: _stories.isEmpty,
                        emptyMsg: 'No stories found',
                        emptyIcon: Icons.auto_stories_outlined,
                        onRefresh: _loadStories,
                        list: ListView.builder(
                          itemCount: _stories.length,
                          itemBuilder: (_, i) =>
                              _storyCard(_stories[i], isDark, i),
                        ),
                      ),
                    ),
                  ],
                );
              }
              return DefaultTabController(
                length: 2,
                child: Column(
                  children: [
                    TabBar(
                      tabs: [
                        Tab(text: 'Reels (${_reels.length})'),
                        Tab(text: 'Stories (${_stories.length})'),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _previewPanel(
                            isDark: isDark,
                            title: 'Reels',
                            icon: Icons.movie_outlined,
                            accentColor: _cBlue,
                            loading: _loadingReels,
                            isEmpty: _reels.isEmpty,
                            emptyMsg: 'No reels',
                            emptyIcon: Icons.movie_outlined,
                            onRefresh: _loadReels,
                            list: ListView.builder(
                              itemCount: _reels.length,
                              itemBuilder: (_, i) =>
                                  _reelCard(_reels[i], isDark, i),
                            ),
                          ),
                          _previewPanel(
                            isDark: isDark,
                            title: 'Stories',
                            icon: Icons.auto_stories_outlined,
                            accentColor: _cViolet,
                            loading: _loadingStories,
                            isEmpty: _stories.isEmpty,
                            emptyMsg: 'No stories',
                            emptyIcon: Icons.auto_stories_outlined,
                            onRefresh: _loadStories,
                            list: ListView.builder(
                              itemCount: _stories.length,
                              itemBuilder: (_, i) =>
                                  _storyCard(_stories[i], isDark, i),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _filterBar(bool isDark, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? const Color(0xFF334155) : _cBorder),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 10,
        runSpacing: 8,
        children: [
          SizedBox(
            width: 180,
            child: TextField(
              controller: _filterUserCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                labelText: 'Filter by User ID',
                labelStyle: const TextStyle(fontSize: 12),
                prefixIcon: const Icon(Icons.person_search_outlined, size: 18),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: isDark ? const Color(0xFF475569) : _cBorder,
                  ),
                ),
                filled: true,
                fillColor: isDark
                    ? const Color(0xFF1E293B)
                    : const Color(0xFFFAFAFA),
              ),
            ),
          ),
          FilterChip(
            label: const Text('All Users', style: TextStyle(fontSize: 12)),
            selected: _browseAll,
            onSelected: (v) {
              setState(() => _browseAll = v);
              _loadReels();
              _loadStories();
            },
            selectedColor: _cBlue.withOpacity(0.15),
            checkmarkColor: _cBlue,
          ),
          FilledButton.icon(
            onPressed: () {
              _loadReels();
              _loadStories();
            },
            icon: const Icon(Icons.search, size: 16),
            label: const Text('Search'),
            style: FilledButton.styleFrom(
              backgroundColor: _cBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          Text(
            '${_reels.length} reels · ${_stories.length} stories',
            style: TextStyle(
              color: isDark ? Colors.white54 : _cMuted,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  // ── generic upload form ───────────────────────────────────────────────────
  Widget _uploadForm({
    required bool isDark,
    required Color accentColor,
    required IconData icon,
    required String title,
    required String subtitle,
    required PlatformFile? file,
    required IconData fileIcon,
    required String fileHint,
    required TextEditingController userCtrl,
    required bool postAsAdminSelf,
    required TextEditingController captionCtrl,
    required String privacy,
    required bool uploading,
    required VoidCallback onPickFile,
    required VoidCallback onClearFile,
    required ValueChanged<bool> onTogglePostAsSelf,
    required ValueChanged<String?> onPrivacyChanged,
    required Future<void> Function() onUpload,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? const Color(0xFF334155) : _cBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: accentColor, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(fontSize: 11, color: _cMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            _step('1', 'Choose File', accentColor),
            const SizedBox(height: 8),
            _fileZone(
              isDark: isDark,
              file: file,
              icon: fileIcon,
              hint: fileHint,
              accentColor: accentColor,
              onPick: onPickFile,
              onClear: onClearFile,
            ),
            const SizedBox(height: 18),
            _step('2', 'Fill Details', accentColor),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _field(
                    ctrl: userCtrl,
                    label: 'Target User ID',
                    hint: 'Enter or search a user',
                    icon: Icons.person_outline,
                    keyboard: TextInputType.number,
                    enabled: !postAsAdminSelf,
                    isDark: isDark,
                    accentColor: accentColor,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: postAsAdminSelf
                        ? null
                        : () => _showUserSearchDialog(userCtrl, accentColor),
                    icon: const Icon(Icons.search, size: 16),
                    label: const Text('Search', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: accentColor,
                      side: BorderSide(color: accentColor),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              dense: true,
              value: postAsAdminSelf,
              onChanged: onTogglePostAsSelf,
              contentPadding: EdgeInsets.zero,
              activeColor: accentColor,
              title: const Text(
                'Post as my admin profile',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                'No target user ID needed',
                style: TextStyle(fontSize: 11),
              ),
            ),
            const SizedBox(height: 10),
            _field(
              ctrl: captionCtrl,
              label: 'Caption (optional)',
              icon: Icons.short_text_rounded,
              maxLines: 2,
              isDark: isDark,
              accentColor: accentColor,
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: privacy,
              items: _privacyItems,
              onChanged: onPrivacyChanged,
              decoration: _fieldDeco(
                label: 'Privacy',
                icon: Icons.lock_outline,
                isDark: isDark,
                accentColor: accentColor,
              ),
            ),
            const SizedBox(height: 20),
            _step('3', 'Upload', accentColor),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: uploading
                  ? _progressBtn(accentColor)
                  : ElevatedButton.icon(
                      onPressed: file == null ? null : onUpload,
                      icon: const Icon(Icons.cloud_upload_outlined),
                      label: Text(
                        'Upload $title',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentColor,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: _cBorder,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ── generic preview panel ─────────────────────────────────────────────────
  // ── user search dialog ────────────────────────────────────────────────────
  Future<void> _showUserSearchDialog(
    TextEditingController targetCtrl,
    Color accentColor,
  ) async {
    final queryCtrl = TextEditingController();
    List<Map<String, dynamic>> results = [];
    bool searching = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setS) {
            Future<void> doSearch() async {
              final q = queryCtrl.text.trim();
              if (q.length < 2) return;
              setS(() => searching = true);
              try {
                final uri = Uri.parse(
                  kAdminEndpointUserSearch,
                ).replace(queryParameters: {'q': q, 'limit': '20'});
                final res = await http.get(uri);
                final j = jsonDecode(res.body) as Map<String, dynamic>;
                if (j['success'] == true) {
                  setS(() {
                    results = (j['users'] as List? ?? [])
                        .whereType<Map>()
                        .map((e) => Map<String, dynamic>.from(e))
                        .toList();
                  });
                }
              } catch (_) {
              } finally {
                setS(() => searching = false);
              }
            }

            return AlertDialog(
              title: const Text('Search User'),
              contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              content: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: queryCtrl,
                            autofocus: true,
                            decoration: InputDecoration(
                              hintText: 'Name or email...',
                              prefixIcon: const Icon(Icons.search, size: 18),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 12,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            onSubmitted: (_) => doSearch(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: doSearch,
                          style: FilledButton.styleFrom(
                            backgroundColor: accentColor,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 14,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: searching
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Go'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (results.isEmpty && !searching)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          'Type a name or email and press Go',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      )
                    else
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 280),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: results.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final u = results[i];
                            return ListTile(
                              dense: true,
                              leading: CircleAvatar(
                                radius: 16,
                                backgroundColor: accentColor.withOpacity(0.15),
                                child: Text(
                                  (u['display_name']?.toString() ?? '?')
                                      .substring(0, 1)
                                      .toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: accentColor,
                                  ),
                                ),
                              ),
                              title: Text(
                                u['display_name']?.toString() ?? '',
                                style: const TextStyle(fontSize: 13),
                              ),
                              subtitle: Text(
                                'ID: ${u['id']}  ·  ${u['email'] ?? ''}',
                                style: const TextStyle(fontSize: 11),
                              ),
                              onTap: () {
                                targetCtrl.text = '${u['id']}';
                                Navigator.of(ctx).pop();
                              },
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
              ],
            );
          },
        );
      },
    );
    queryCtrl.dispose();
  }

  Widget _previewPanel({
    required bool isDark,
    required String title,
    required IconData icon,
    required Color accentColor,
    required bool loading,
    required bool isEmpty,
    required String emptyMsg,
    required IconData emptyIcon,
    required VoidCallback onRefresh,
    required Widget list,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? const Color(0xFF334155) : _cBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: accentColor),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
              SizedBox(
                width: 32,
                height: 32,
                child: loading
                    ? Padding(
                        padding: const EdgeInsets.all(6),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: accentColor,
                        ),
                      )
                    : IconButton(
                        icon: const Icon(Icons.refresh_rounded, size: 20),
                        tooltip: 'Refresh',
                        onPressed: onRefresh,
                        padding: EdgeInsets.zero,
                      ),
              ),
            ],
          ),
          const Divider(height: 14),
          Expanded(
            child: loading
                ? Center(child: CircularProgressIndicator(color: accentColor))
                : isEmpty
                ? _empty(emptyMsg, emptyIcon)
                : list,
          ),
        ],
      ),
    );
  }

  // ── reel card ─────────────────────────────────────────────────────────────
  Widget _reelCard(Map<String, dynamic> r, bool isDark, int index) {
    final thumb = (r['thumbnail_url']?.toString() ?? '').trim();
    final video = (r['video_url']?.toString() ?? '').trim();
    final caption = (r['caption']?.toString() ?? '').trim();
    final privacy = r['privacy']?.toString() ?? 'public';
    final userId = r['user_id']?.toString() ?? '-';
    final likes = r['like_count']?.toString() ?? '0';
    final views = r['view_count']?.toString() ?? '0';
    final fn = (r['firstName'] ?? '').toString().trim();
    final ln = (r['lastName'] ?? '').toString().trim();
    final name = [fn, ln].where((s) => s.isNotEmpty).join(' ');

    return GestureDetector(
      onTap: () => _openReelsViewer(index),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? const Color(0xFF334155) : _cBorder,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(12),
              ),
              child: SizedBox(
                width: 100,
                height: 76,
                child: thumb.isNotEmpty
                    ? Image.network(
                        thumb,
                        fit: BoxFit.cover,
                        loadingBuilder: (_, child, p) =>
                            p == null ? child : _thumbLoading(isDark),
                        errorBuilder: (_, __, ___) =>
                            _thumbIcon(isDark, Icons.movie_outlined),
                      )
                    : _thumbIcon(isDark, Icons.movie_outlined),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            caption.isEmpty ? '(No caption)' : caption,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF111827),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        _badge(_privacyLabel(privacy), _privacyColor(privacy)),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      children: [
                        _iconText(
                          Icons.person_outline,
                          name.isEmpty ? 'User $userId' : name,
                        ),
                        _iconText(Icons.visibility_outlined, views),
                        _iconText(Icons.favorite_border_rounded, likes),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 6, top: 4),
              child: Column(
                children: [
                  if (video.isNotEmpty)
                    IconButton(
                      icon: Icon(
                        Icons.play_circle_outline_rounded,
                        color: _cBlue,
                        size: 24,
                      ),
                      tooltip: 'Play viewer',
                      onPressed: () => _openReelsViewer(index),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 36,
                      ),
                    ),
                  PopupMenuButton<String>(
                    tooltip: 'Controls',
                    icon: Icon(
                      Icons.more_vert_rounded,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                    onSelected: (value) async {
                      if (value == 'privacy') {
                        final selected = await _pickPrivacyDialog(privacy);
                        if (selected != null && selected != privacy) {
                          await _updateReelPrivacy(r, selected);
                        }
                      } else if (value == 'delete') {
                        await _deleteReel(r);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'privacy',
                        child: Text('Make Private/Public'),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete Reel'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── story card ────────────────────────────────────────────────────────────
  Widget _storyCard(Map<String, dynamic> s, bool isDark, int index) {
    final media = (s['media_url']?.toString() ?? '').trim();
    final thumb = (s['thumbnail_url']?.toString() ?? '').trim();
    final mtype = (s['media_type']?.toString() ?? 'image');
    final caption = (s['caption']?.toString() ?? '').trim();
    final privacy = s['privacy']?.toString() ?? 'public';
    final userId = s['user_id']?.toString() ?? '-';
    final isImg = mtype != 'video';
    final display = isImg ? media : (thumb.isNotEmpty ? thumb : media);

    return GestureDetector(
      onTap: () => _openStoriesViewer(index),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? const Color(0xFF334155) : _cBorder,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(12),
              ),
              child: SizedBox(
                width: 76,
                height: 76,
                child: display.isNotEmpty
                    ? Image.network(
                        display,
                        fit: BoxFit.cover,
                        loadingBuilder: (_, child, p) =>
                            p == null ? child : _thumbLoading(isDark),
                        errorBuilder: (_, __, ___) => _thumbIcon(
                          isDark,
                          isImg
                              ? Icons.image_outlined
                              : Icons.video_collection_outlined,
                        ),
                      )
                    : _thumbIcon(
                        isDark,
                        isImg
                            ? Icons.image_outlined
                            : Icons.video_collection_outlined,
                      ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            caption.isEmpty ? '(No caption)' : caption,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF111827),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        _badge(_privacyLabel(privacy), _privacyColor(privacy)),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      children: [
                        _iconText(
                          isImg
                              ? Icons.image_outlined
                              : Icons.video_collection_outlined,
                          isImg ? 'Image' : 'Video',
                        ),
                        _iconText(Icons.person_outline, 'User $userId'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 6, top: 4),
              child: Column(
                children: [
                  if (media.isNotEmpty)
                    IconButton(
                      icon: Icon(
                        Icons.play_circle_outline,
                        color: _cViolet,
                        size: 22,
                      ),
                      tooltip: 'Open viewer',
                      onPressed: () => _openStoriesViewer(index),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 36,
                      ),
                    ),
                  PopupMenuButton<String>(
                    tooltip: 'Controls',
                    icon: Icon(
                      Icons.more_vert_rounded,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                    onSelected: (value) async {
                      if (value == 'privacy') {
                        final selected = await _pickPrivacyDialog(privacy);
                        if (selected != null && selected != privacy) {
                          await _updateStoryPrivacy(s, selected);
                        }
                      } else if (value == 'delete') {
                        await _deleteStory(s);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'privacy',
                        child: Text('Make Private/Public'),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete Story'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── small helpers ─────────────────────────────────────────────────────────
  Widget _step(String num, String label, Color color) {
    return Row(
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: Text(
            num,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
      ],
    );
  }

  Widget _fileZone({
    required bool isDark,
    required PlatformFile? file,
    required IconData icon,
    required String hint,
    required Color accentColor,
    required VoidCallback onPick,
    required VoidCallback onClear,
  }) {
    if (file != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: accentColor.withOpacity(0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: accentColor.withOpacity(0.35)),
        ),
        child: Row(
          children: [
            Icon(icon, color: accentColor, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  if (file.size > 0)
                    Text(
                      _fmtBytes(file.size),
                      style: TextStyle(fontSize: 11, color: _cMuted),
                    ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.close_rounded, size: 20, color: accentColor),
              onPressed: onClear,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      );
    }
    return InkWell(
      onTap: onPick,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 28),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFD1D5DB),
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 36, color: accentColor.withOpacity(0.45)),
            const SizedBox(height: 8),
            Text(hint, style: TextStyle(color: _cMuted, fontSize: 13)),
            const SizedBox(height: 3),
            Text(
              'Browse Files',
              style: TextStyle(
                color: accentColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController ctrl,
    required String label,
    required IconData icon,
    String? hint,
    TextInputType keyboard = TextInputType.text,
    int maxLines = 1,
    bool enabled = true,
    required bool isDark,
    Color? accentColor,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboard,
      maxLines: maxLines,
      enabled: enabled,
      decoration: _fieldDeco(
        label: label,
        hint: hint,
        icon: icon,
        isDark: isDark,
        accentColor: accentColor,
      ),
    );
  }

  InputDecoration _fieldDeco({
    required String label,
    required IconData icon,
    String? hint,
    required bool isDark,
    Color? accentColor,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, size: 18),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(
          color: isDark ? const Color(0xFF475569) : _cBorder,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: accentColor ?? _cBlue, width: 1.5),
      ),
      filled: true,
      fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFFAFAFA),
    );
  }

  Widget _progressBtn(Color color) {
    return Container(
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: color),
          ),
          const SizedBox(width: 10),
          Text(
            'Uploading…',
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
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

  Widget _iconText(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: _cMuted),
        const SizedBox(width: 3),
        Text(text, style: TextStyle(fontSize: 11, color: _cMuted)),
      ],
    );
  }

  Widget _thumbLoading(bool isDark) {
    return Container(
      color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
      child: const Center(child: CircularProgressIndicator(strokeWidth: 1.5)),
    );
  }

  Widget _thumbIcon(bool isDark, IconData icon) {
    return Container(
      color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
      child: Icon(
        icon,
        size: 28,
        color: isDark ? Colors.white24 : Colors.black26,
      ),
    );
  }

  Widget _empty(String msg, IconData icon) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 42, color: _cMuted.withOpacity(0.35)),
          const SizedBox(height: 10),
          Text(msg, style: TextStyle(color: _cMuted, fontSize: 14)),
        ],
      ),
    );
  }
}
