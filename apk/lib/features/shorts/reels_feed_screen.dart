import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:ms2026/otherenew/othernew.dart';

import 'models/reel_item.dart';
import 'services/shorts_service.dart';
import 'shorts_create_entry_screen.dart';

class ReelsFeedScreen extends StatefulWidget {
  const ReelsFeedScreen({super.key});

  @override
  State<ReelsFeedScreen> createState() => _ReelsFeedScreenState();
}

class _ReelsFeedScreenState extends State<ReelsFeedScreen> {
  final List<ReelItem> _items = [];
  bool _loading = true;
  bool _loadingMore = false;
  String _error = '';
  int? _nextCursor;
  int? _nextOffset;
  int _userId = 0;
  String _sort = 'recent'; // 'recent' | 'trending'

  late final PageController _pageCtrl;
  int _currentPage = 0;
  final Map<int, VideoPlayerController> _controllers = {};
  final Set<int> _initFailed = {};
  Timer? _viewTimer;
  int _viewTimerPage = -1;

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _boot();
  }

  @override
  void dispose() {
    _viewTimer?.cancel();
    for (final c in _controllers.values) {
      c.dispose();
    }
    _pageCtrl.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _boot() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('user_data') ?? '';
    try {
      final parsed = jsonDecode(raw) as Map<String, dynamic>;
      _userId = int.tryParse(parsed['id']?.toString() ?? '') ?? 0;
    } catch (_) {}
    await _loadInitial();
  }

  Future<void> _loadInitial({String? sort}) async {
    final newSort = sort ?? _sort;
    _viewTimer?.cancel();
    setState(() {
      _loading = true;
      _error = '';
      _sort = newSort;
    });
    for (final c in _controllers.values) {
      c.dispose();
    }
    _controllers.clear();
    _initFailed.clear();
    _currentPage = 0;
    _nextCursor = null;
    _nextOffset = null;
    try {
      final (rows, cursor, offset) = await ShortsService.fetchReelFeed(
          userId: _userId, sort: newSort, limit: 10);
      setState(() {
        _items
          ..clear()
          ..addAll(rows);
        _nextCursor = cursor;
        _nextOffset = offset;
      });
      if (_items.isNotEmpty) {
        await _initController(0);
        _initController(1);
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    final hasMore =
        _sort == 'recent' ? _nextCursor != null : _nextOffset != null;
    if (_loadingMore || !hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final (rows, cursor, offset) = await ShortsService.fetchReelFeed(
        userId: _userId,
        sort: _sort,
        cursorId: _sort == 'recent' ? _nextCursor : null,
        offset: _sort == 'trending' ? _nextOffset : null,
        limit: 10,
      );
      setState(() {
        _items.addAll(rows);
        _nextCursor = cursor;
        _nextOffset = offset;
      });
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _initController(int index) async {
    if (_controllers.containsKey(index)) return;
    if (_initFailed.contains(index)) return;
    if (index < 0 || index >= _items.length) return;
    final url = _items[index].videoUrl;
    if (url.isEmpty) {
      _initFailed.add(index);
      if (mounted) setState(() {});
      return;
    }
    final ctrl = VideoPlayerController.networkUrl(
      Uri.parse(url),
      videoPlayerOptions: VideoPlayerOptions(
        mixWithOthers: true,
        allowBackgroundPlayback: false,
      ),
    );
    _controllers[index] = ctrl;
    // Listener: repaint widget when controller state changes (e.g. isInitialized)
    ctrl.addListener(() {
      if (mounted) setState(() {});
    });
    try {
      await ctrl.initialize().timeout(const Duration(seconds: 12));
      await ctrl.setLooping(true);
      await ctrl.setVolume(1.0);
      if (!mounted) return;
      setState(() {});
      if (index == _currentPage) ctrl.play();
    } on TimeoutException catch (_) {
      _controllers.remove(index);
      ctrl.dispose();
      if (mounted) {
        _initFailed.add(index);
        setState(() {});
      }
      debugPrint('[ReelsFeed] timeout idx=$index');
    } catch (e) {
      _controllers.remove(index);
      ctrl.dispose();
      if (mounted) {
        _initFailed.add(index);
        setState(() {});
      }
      debugPrint('[ReelsFeed] init failed idx=$index err=$e');
    }
  }

  void _retryController(int index) {
    if (_initFailed.remove(index)) _initController(index);
  }

  void _onPageChanged(int page) {
    _viewTimer?.cancel();
    _controllers[_currentPage]?.pause();
    _currentPage = page;
    // Keep [page-2 â€¦ page+4] in memory, evict the rest
    final toRemove =
        _controllers.keys.where((k) => k < page - 2 || k > page + 4).toList();
    for (final k in toRemove) {
      _controllers[k]?.dispose();
      _controllers.remove(k);
      _initFailed.remove(k); // allow retry if user scrolls back
    }
    // Preload: 1 behind + current + 3 ahead
    if (page > 0) _initController(page - 1);
    _initController(page);
    _initController(page + 1);
    _initController(page + 2);
    _initController(page + 3);
    // Play if already ready
    final ctrl = _controllers[page];
    if (ctrl != null && ctrl.value.isInitialized) ctrl.play();
    // Load more when near the end
    if (page >= _items.length - 4) _loadMore();
    // Start 2-second view timer
    _viewTimerPage = page;
    _viewTimer = Timer(const Duration(seconds: 2), () {
      if (_viewTimerPage == page && mounted) _trackView(page);
    });
  }

  Future<void> _trackView(int index) async {
    if (index < 0 || index >= _items.length) return;
    final count = await ShortsService.trackView(
      userId: _userId,
      reelId: _items[index].id,
      watchedSeconds: 2,
    );
    if (count > 0 && mounted) {
      setState(() => _items[index] = _items[index].copyWith(viewCount: count));
    }
  }

  Future<void> _toggleLike(int index) async {
    final item = _items[index];
    final optimistic = item.copyWith(
      myLike: !item.myLike,
      likeCount: item.myLike ? item.likeCount - 1 : item.likeCount + 1,
    );
    setState(() => _items[index] = optimistic);
    try {
      final (liked, count) =
          await ShortsService.react(userId: _userId, reelId: item.id);
      setState(() => _items[index] =
          _items[index].copyWith(myLike: liked, likeCount: count));
    } catch (_) {
      if (mounted) setState(() => _items[index] = item); // rollback
    }
  }

  Future<void> _comment(int index) async {
    _controllers[_currentPage]?.pause();
    final newCount = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _CommentSheet(
        reelId: _items[index].id,
        userId: _userId,
        initialCount: _items[index].commentCount,
      ),
    );
    _controllers[_currentPage]?.play();
    if (newCount != null && mounted) {
      setState(
          () => _items[index] = _items[index].copyWith(commentCount: newCount));
    }
  }

  Future<void> _share(int index) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final count =
          await ShortsService.share(userId: _userId, reelId: _items[index].id);
      if (!mounted) return;
      setState(() => _items[index] = _items[index].copyWith(shareCount: count));
      messenger?.showSnackBar(const SnackBar(content: Text('Share recorded')));
    } catch (e) {
      if (!mounted) return;
      messenger?.showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _report(int index) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    _controllers[_currentPage]?.pause();
    final reason = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.grey.shade900,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 16),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: Colors.white30, borderRadius: BorderRadius.circular(2)),
          ),
          const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Report Reel',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold))),
          for (final r in [
            'sexual',
            'violence',
            'spam',
            'hate_speech',
            'other'
          ])
            ListTile(
              leading:
                  const Icon(Icons.flag_outlined, color: Colors.orangeAccent),
              title: Text(r.replaceAll('_', ' ').toUpperCase(),
                  style: const TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(context, r),
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
    _controllers[_currentPage]?.play();
    if (reason == null) return;
    try {
      await ShortsService.report(
          userId: _userId, reelId: _items[index].id, reason: reason);
      if (!mounted) return;
      messenger
          ?.showSnackBar(const SnackBar(content: Text('Reported. Thank you!')));
    } catch (e) {
      if (!mounted) return;
      messenger?.showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _changeReelPrivacy(int index) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (index < 0 || index >= _items.length) return;
    final item = _items[index];
    if (item.userId != _userId) return;

    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.white30,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 12),
            const Text('Edit reel privacy',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16)),
            const SizedBox(height: 8),
            for (final p in const [
              'public',
              'matches_only',
              'paid_only',
              'verified_only',
              'private'
            ])
              ListTile(
                title: Text(p.replaceAll('_', ' ').toUpperCase(),
                    style: const TextStyle(color: Colors.white)),
                trailing: item.privacy == p
                    ? const Icon(Icons.check, color: Colors.greenAccent)
                    : null,
                onTap: () => Navigator.pop(context, p),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (selected == null || selected == item.privacy) return;

    try {
      await ShortsService.updateReelPrivacy(
        userId: _userId,
        reelId: item.id,
        privacy: selected,
      );
      if (!mounted) return;
      setState(() {
        _items[index] = ReelItem(
          id: item.id,
          userId: item.userId,
          userName: item.userName,
          profilePicture: item.profilePicture,
          videoUrl: item.videoUrl,
          thumbnailUrl: item.thumbnailUrl,
          soundUrl: item.soundUrl,
          soundTitle: item.soundTitle,
          caption: item.caption,
          privacy: selected,
          allowComments: item.allowComments,
          allowDuet: item.allowDuet,
          allowDownload: item.allowDownload,
          viewCount: item.viewCount,
          likeCount: item.likeCount,
          commentCount: item.commentCount,
          shareCount: item.shareCount,
          myLike: item.myLike,
          createdAt: item.createdAt,
        );
      });
      messenger?.showSnackBar(
        const SnackBar(content: Text('Reel privacy updated')),
      );
    } catch (e) {
      if (!mounted) return;
      messenger?.showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _deleteReelPost(int index) async {
    if (index < 0 || index >= _items.length) return;
    final item = _items[index];
    if (item.userId != _userId) return;
    final messenger = ScaffoldMessenger.maybeOf(context);

    final confirm = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Delete reel?'),
            content: const Text(
                'This reel will be removed from your profile and feed.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel')),
              TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Delete')),
            ],
          ),
        ) ??
        false;
    if (!confirm) return;

    try {
      await ShortsService.deleteReel(userId: _userId, reelId: item.id);
      if (!mounted) return;
      messenger?.showSnackBar(const SnackBar(content: Text('Reel deleted')));
      await _loadInitial(sort: _sort);
    } catch (e) {
      if (!mounted) return;
      messenger?.showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  void _openReelProfile(int index) {
    if (index < 0 || index >= _items.length) return;
    final reelUserId = _items[index].userId;
    if (reelUserId <= 0) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProfileScreen(userId: reelUserId.toString()),
      ),
    );
  }

  void _showCreateSheet(BuildContext ctx) {
    showModalBottomSheet(
      context: ctx,
      backgroundColor: const Color(0xFF161616),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 18),
            const Text(
              'Create',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 18),
            _CreateOption(
              icon: Icons.videocam_rounded,
              label: 'Camera',
              sublabel: 'Record a video',
              color: const Color(0xFFFF0050),
              onTap: () {
                Navigator.pop(_);
                Navigator.push(
                  ctx,
                  MaterialPageRoute(
                    builder: (_) =>
                        const ShortsCreateEntryScreen(fromCamera: true),
                  ),
                );
              },
            ),
            _CreateOption(
              icon: Icons.photo_library_rounded,
              label: 'Upload',
              sublabel: 'Pick from gallery',
              color: const Color(0xFF00C6FF),
              onTap: () {
                Navigator.pop(_);
                Navigator.push(
                  ctx,
                  MaterialPageRoute(
                    builder: (_) =>
                        const ShortsCreateEntryScreen(fromCamera: false),
                  ),
                );
              },
            ),
            _CreateOption(
              icon: Icons.text_fields_rounded,
              label: 'Text',
              sublabel: 'Write a text post',
              color: Colors.deepPurpleAccent,
              onTap: () {
                Navigator.pop(_);
                Navigator.push(
                  ctx,
                  MaterialPageRoute(
                    builder: (_) =>
                        const ShortsCreateEntryScreen(textMode: true),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SortTab(
              label: 'Recent',
              selected: _sort == 'recent',
              onTap: () {
                if (_sort != 'recent') _loadInitial(sort: 'recent');
              },
            ),
            const SizedBox(width: 4),
            _SortTab(
              label: 'Trending',
              selected: _sort == 'trending',
              onTap: () {
                if (_sort != 'trending') _loadInitial(sort: 'trending');
              },
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: () => _loadInitial(sort: _sort),
            icon: const Icon(Icons.refresh, color: Colors.white),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreateSheet(context),
        backgroundColor: const Color(0xFFFF0050),
        shape: const CircleBorder(),
        child: const Icon(Icons.add, color: Colors.white, size: 32),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : _error.isNotEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error, style: const TextStyle(color: Colors.white)),
                      const SizedBox(height: 12),
                      ElevatedButton(
                          onPressed: () => _loadInitial(sort: _sort),
                          child: const Text('Retry')),
                    ],
                  ),
                )
              : _items.isEmpty
                  ? const Center(
                      child: Text('No reels yet. Be the first!',
                          style: TextStyle(color: Colors.white)))
                  : PageView.builder(
                      controller: _pageCtrl,
                      scrollDirection: Axis.vertical,
                      onPageChanged: _onPageChanged,
                      itemCount: _items.length,
                      itemBuilder: (_, i) => _ReelPage(
                        item: _items[i],
                        currentUserId: _userId,
                        controller: _controllers[i],
                        initFailed: _initFailed.contains(i),
                        onRetry: () => _retryController(i),
                        onOpenProfile: () => _openReelProfile(i),
                        onManagePrivacy: () => _changeReelPrivacy(i),
                        onDelete: () => _deleteReelPost(i),
                        onLike: () => _toggleLike(i),
                        onComment: () => _comment(i),
                        onShare: () => _share(i),
                        onReport: () => _report(i),
                        onUseAudio: () {
                          final item = _items[i];
                          final soundUrl = item.soundUrl.isNotEmpty
                              ? item.soundUrl
                              : item.videoUrl;
                          final soundTitle = item.soundTitle.isNotEmpty
                              ? item.soundTitle
                              : '${item.userName}\u2019s sound';
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ShortsCreateEntryScreen(
                                soundUrl: soundUrl,
                                soundTitle: soundTitle,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}

// â”€â”€â”€ Individual reel page â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _ReelPage extends StatefulWidget {
  final ReelItem item;
  final int currentUserId;
  final VideoPlayerController? controller;
  final bool initFailed;
  final VoidCallback onRetry;
  final VoidCallback onOpenProfile;
  final VoidCallback onManagePrivacy;
  final VoidCallback onDelete;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onShare;
  final VoidCallback onReport;
  final VoidCallback onUseAudio;

  const _ReelPage({
    required this.item,
    required this.currentUserId,
    required this.controller,
    this.initFailed = false,
    required this.onRetry,
    required this.onOpenProfile,
    required this.onManagePrivacy,
    required this.onDelete,
    required this.onLike,
    required this.onComment,
    required this.onShare,
    required this.onReport,
    required this.onUseAudio,
  });

  @override
  State<_ReelPage> createState() => _ReelPageState();
}

class _ReelPageState extends State<_ReelPage> with TickerProviderStateMixin {
  bool _showPauseIcon = false;
  bool _showHeart = false;
  Timer? _pauseIconTimer;
  late AnimationController _heartAnim;
  late Animation<double> _heartScale;
  final List<_FloatingHeartData> _floatingHearts = [];

  @override
  void initState() {
    super.initState();
    _heartAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _heartScale = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.5), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.5, end: 1.0), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 30),
    ]).animate(_heartAnim);
    widget.controller?.addListener(_onControllerUpdate);
  }

  void _onControllerUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant _ReelPage old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller?.removeListener(_onControllerUpdate);
      widget.controller?.addListener(_onControllerUpdate);
    }
  }

  @override
  void dispose() {
    _pauseIconTimer?.cancel();
    _heartAnim.dispose();
    // Copy list before clearing to avoid concurrent modification;
    // controllers that already completed are removed from list by then-callback.
    final hearts = List<_FloatingHeartData>.from(_floatingHearts);
    _floatingHearts.clear();
    for (final h in hearts) {
      h.ctrl.stop();
      h.ctrl.dispose();
    }
    widget.controller?.removeListener(_onControllerUpdate);
    super.dispose();
  }

  void _spawnFloatingHeart() {
    final ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400));
    final rng = math.Random();
    final xOff = (rng.nextDouble() - 0.5) * 48.0;
    final data = _FloatingHeartData(ctrl: ctrl, xOffset: xOff);
    setState(() => _floatingHearts.add(data));
    ctrl.forward().whenCompleteOrCancel(() {
      final needsDispose = !_floatingHearts.contains(data);
      if (mounted) {
        setState(() => _floatingHearts.remove(data));
        if (needsDispose || !_floatingHearts.contains(data)) ctrl.dispose();
      } else {
        _floatingHearts.remove(data);
        ctrl.dispose();
      }
    });
  }

  void _onTap() {
    final ctrl = widget.controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    if (ctrl.value.isPlaying) {
      ctrl.pause();
      setState(() => _showPauseIcon = true);
      _pauseIconTimer?.cancel();
      _pauseIconTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _showPauseIcon = false);
      });
    } else {
      ctrl.play();
      setState(() => _showPauseIcon = false);
    }
  }

  void _onDoubleTap() {
    widget.onLike();
    setState(() => _showHeart = true);
    _heartAnim.forward(from: 0).then((_) {
      if (mounted) setState(() => _showHeart = false);
    });
    // spawn 3 floating hearts with slight delay
    _spawnFloatingHeart();
    Future.delayed(const Duration(milliseconds: 120), () {
      if (mounted) _spawnFloatingHeart();
    });
    Future.delayed(const Duration(milliseconds: 240), () {
      if (mounted) _spawnFloatingHeart();
    });
  }

  String _formatReelUserLabel(ReelItem item) {
    final parts = item.userName.trim().split(RegExp(r'\s+'));
    final lastName = parts.isNotEmpty ? parts.last : '';
    return 'ID ${item.userId}${lastName.isNotEmpty ? ' $lastName' : ''}';
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;
    final item = widget.item;
    final initialized = ctrl?.value.isInitialized ?? false;

    return GestureDetector(
      onTap: _onTap,
      onDoubleTap: _onDoubleTap,
      child: Container(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Video or thumbnail poster
            if (initialized)
              FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: ctrl!.value.size.width,
                  height: ctrl.value.size.height,
                  child: VideoPlayer(ctrl),
                ),
              )
            else if (item.thumbnailUrl.isNotEmpty)
              CachedNetworkImage(
                imageUrl: item.thumbnailUrl,
                fit: BoxFit.cover,
                placeholder: (_, __) => const ColoredBox(color: Colors.black),
                errorWidget: (_, __, ___) =>
                    const ColoredBox(color: Colors.black),
              )
            else
              const ColoredBox(color: Colors.black),

            // Loading indicator / error state
            if (!initialized)
              Center(
                child: widget.initFailed
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.refresh,
                              color: Colors.white54, size: 40),
                          const SizedBox(height: 8),
                          const Text('Tap to retry',
                              style: TextStyle(color: Colors.white54)),
                          GestureDetector(
                            onTap: widget.onRetry,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 9),
                              decoration: BoxDecoration(
                                color: Colors.white24,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Text('Retry',
                                  style: TextStyle(color: Colors.white)),
                            ),
                          ),
                        ],
                      )
                    : const CircularProgressIndicator(
                        color: Colors.white54, strokeWidth: 2),
              ),

            // Top gradient
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 130,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black54, Colors.transparent],
                  ),
                ),
              ),
            ),

            // Bottom gradient
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 240,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black87, Colors.transparent],
                  ),
                ),
              ),
            ),

            // Bottom-left: avatar + username + caption
            Positioned(
              bottom: 88,
              left: 16,
              right: 90,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: widget.onOpenProfile,
                    behavior: HitTestBehavior.opaque,
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundImage: item.profilePicture.isNotEmpty
                              ? CachedNetworkImageProvider(item.profilePicture)
                              : null,
                          backgroundColor: Colors.grey.shade800,
                          child: item.profilePicture.isEmpty
                              ? const Icon(Icons.person,
                                  color: Colors.white, size: 18)
                              : null,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _formatReelUserLabel(item),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              shadows: [
                                Shadow(blurRadius: 4, color: Colors.black)
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (item.caption.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      item.caption,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        shadows: [Shadow(blurRadius: 4, color: Colors.black)],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Video progress scrubber
            if (initialized)
              Positioned(
                bottom: 80,
                left: 0,
                right: 0,
                child: VideoProgressIndicator(
                  ctrl!,
                  allowScrubbing: true,
                  colors: VideoProgressColors(
                    playedColor: Colors.redAccent,
                    bufferedColor: Colors.white30,
                    backgroundColor: Colors.white12,
                  ),
                  padding: EdgeInsets.zero,
                ),
              ),

            // Right side: like / comment / share / views / report
            Positioned(
              right: 8,
              bottom: 110,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (item.userId == widget.currentUserId) ...[
                    _ActionBtn(
                      icon: Icons.more_horiz,
                      color: Colors.white,
                      label: '',
                      onTap: () async {
                        final action = await showModalBottomSheet<String>(
                          context: context,
                          backgroundColor: const Color(0xFF1C1C1E),
                          shape: const RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.vertical(top: Radius.circular(18)),
                          ),
                          builder: (_) => SafeArea(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(height: 8),
                                Container(
                                    width: 40,
                                    height: 4,
                                    decoration: BoxDecoration(
                                        color: Colors.white30,
                                        borderRadius:
                                            BorderRadius.circular(2))),
                                const SizedBox(height: 8),
                                ListTile(
                                  leading: const Icon(
                                      Icons.privacy_tip_outlined,
                                      color: Colors.white),
                                  title: const Text('Edit privacy',
                                      style: TextStyle(color: Colors.white)),
                                  onTap: () =>
                                      Navigator.pop(context, 'privacy'),
                                ),
                                ListTile(
                                  leading: const Icon(Icons.delete_outline,
                                      color: Colors.redAccent),
                                  title: const Text('Delete reel',
                                      style:
                                          TextStyle(color: Colors.redAccent)),
                                  onTap: () => Navigator.pop(context, 'delete'),
                                ),
                                const SizedBox(height: 8),
                              ],
                            ),
                          ),
                        );
                        if (action == 'privacy') {
                          widget.onManagePrivacy();
                        } else if (action == 'delete') {
                          widget.onDelete();
                        }
                      },
                    ),
                    const SizedBox(height: 20),
                  ],
                  _ActionBtn(
                    icon: item.myLike ? Icons.favorite : Icons.favorite_border,
                    color: item.myLike ? Colors.red : Colors.white,
                    label: _formatCount(item.likeCount),
                    onTap: () {
                      widget.onLike();
                      _spawnFloatingHeart();
                    },
                  ),
                  const SizedBox(height: 20),
                  _ActionBtn(
                    icon: Icons.comment_outlined,
                    color: Colors.white,
                    label: _formatCount(item.commentCount),
                    onTap: widget.onComment,
                  ),
                  const SizedBox(height: 20),
                  _ActionBtn(
                    icon: Icons.share_outlined,
                    color: Colors.white,
                    label: _formatCount(item.shareCount),
                    onTap: widget.onShare,
                  ),
                  const SizedBox(height: 20),
                  _ActionBtn(
                    icon: Icons.visibility_outlined,
                    color: Colors.white,
                    label: _formatCount(item.viewCount),
                    onTap: () {},
                  ),
                  const SizedBox(height: 20),
                  _ActionBtn(
                    icon: Icons.flag_outlined,
                    color: Colors.orangeAccent,
                    label: '',
                    onTap: widget.onReport,
                  ),
                  const SizedBox(height: 20),
                  _ActionBtn(
                    icon: Icons.music_note,
                    color: Colors.white,
                    label: 'Sound',
                    onTap: widget.onUseAudio,
                  ),
                ],
              ),
            ),

            // Tap-to-pause icon
            if (_showPauseIcon)
              Center(
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(50),
                  ),
                  child: const Icon(Icons.pause, color: Colors.white, size: 52),
                ),
              ),

            // Double-tap heart burst
            if (_showHeart)
              Center(
                child: ScaleTransition(
                  scale: _heartScale,
                  child:
                      const Icon(Icons.favorite, color: Colors.red, size: 100),
                ),
              ),

            // Floating hearts rising from like button
            ..._floatingHearts.map((h) => Positioned(
                  right: 16,
                  bottom: 160,
                  child: _FloatingHeart(data: h),
                )),
          ],
        ),
      ),
    );
  }

  String _formatCount(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}

// â”€â”€â”€ Reusable action button â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  const _ActionBtn({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(
              color: Colors.black38,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          if (label.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                shadows: [Shadow(blurRadius: 4, color: Colors.black)],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Create option row ────────────────────────────────────────────────────────

class _CreateOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sublabel;
  final Color color;
  final VoidCallback onTap;

  const _CreateOption({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(sublabel,
                    style:
                        const TextStyle(color: Colors.white54, fontSize: 13)),
              ],
            ),
            const Spacer(),
            const Icon(Icons.chevron_right, color: Colors.white38),
          ],
        ),
      ),
    );
  }
}
// â”€â”€â”€ Sort toggle tab â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _SortTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SortTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.black : Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

// ─── Expandable caption ───────────────────────────────────────────────────────

class _ExpandableCaption extends StatefulWidget {
  final String caption;
  const _ExpandableCaption({required this.caption});

  @override
  State<_ExpandableCaption> createState() => _ExpandableCaptionState();
}

class _ExpandableCaptionState extends State<_ExpandableCaption> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Text(
        widget.caption,
        maxLines: _expanded ? null : 2,
        overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          shadows: [Shadow(blurRadius: 4, color: Colors.black)],
        ),
      ),
    );
  }
}

// ─── Comment sheet ────────────────────────────────────────────────────────────

class _CommentSheet extends StatefulWidget {
  final int reelId;
  final int userId;
  final int initialCount;

  const _CommentSheet({
    required this.reelId,
    required this.userId,
    required this.initialCount,
  });

  @override
  State<_CommentSheet> createState() => _CommentSheetState();
}

class _CommentSheetState extends State<_CommentSheet> {
  final List<Map<String, dynamic>> _comments = [];
  final TextEditingController _ctrl = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _loading = true;
  bool _posting = false;
  int? _nextCursor;
  int _count = 0;

  @override
  void initState() {
    super.initState();
    _count = widget.initialCount;
    _load();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({int? cursor}) async {
    try {
      final (rows, next) = await ShortsService.fetchComments(
        reelId: widget.reelId,
        cursorId: cursor,
        limit: 30,
      );
      if (!mounted) return;
      setState(() {
        if (cursor == null) {
          _comments
            ..clear()
            ..addAll(rows);
        } else {
          _comments.addAll(rows);
        }
        _nextCursor = next;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _post() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _posting) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _posting = true);
    try {
      final newCount = await ShortsService.addComment(
        userId: widget.userId,
        reelId: widget.reelId,
        comment: text,
      );
      _ctrl.clear();
      if (!mounted) return;
      setState(() {
        _count = newCount;
        _posting = false;
        _comments.insert(0, {
          'user_name': 'You',
          'comment': text,
          'profile_picture': '',
          'created_at': '',
        });
      });
      if (_scroll.hasClients) {
        _scroll.animateTo(0,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _posting = false);
      }
      messenger?.showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: Colors.black12, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const SizedBox(width: 16),
              Text(
                '$_count Comments',
                style: const TextStyle(
                    color: Colors.black87,
                    fontSize: 16,
                    fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              IconButton(
                onPressed: () => Navigator.pop(context, _count),
                icon: const Icon(Icons.close, color: Colors.black45),
              ),
            ],
          ),
          const Divider(color: Colors.black12, height: 1),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(
                        color: Colors.grey, strokeWidth: 2))
                : _comments.isEmpty
                    ? const Center(
                        child: Text('No comments yet. Be the first!',
                            style: TextStyle(color: Colors.black45)))
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount:
                            _comments.length + (_nextCursor != null ? 1 : 0),
                        itemBuilder: (_, i) {
                          if (i == _comments.length) {
                            return TextButton(
                              onPressed: () => _load(cursor: _nextCursor),
                              child: const Text('Load more',
                                  style: TextStyle(color: Colors.white54)),
                            );
                          }
                          final c = _comments[i];
                          final pic =
                              (c['profile_picture'] as String? ?? '').trim();
                          final name = (c['user_name'] as String? ?? '').trim();
                          final text = (c['comment'] as String? ?? '').trim();
                          final time = (c['created_at'] as String? ?? '');
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CircleAvatar(
                                  radius: 18,
                                  backgroundImage: pic.isNotEmpty
                                      ? CachedNetworkImageProvider(pic)
                                      : null,
                                  backgroundColor: Colors.grey.shade300,
                                  child: pic.isEmpty
                                      ? Text(
                                          name.isNotEmpty
                                              ? name[0].toUpperCase()
                                              : '?',
                                          style: const TextStyle(
                                              color: Colors.black87,
                                              fontWeight: FontWeight.bold),
                                        )
                                      : null,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            name,
                                            style: const TextStyle(
                                                color: Colors.black87,
                                                fontWeight: FontWeight.w600,
                                                fontSize: 13),
                                          ),
                                          if (time.isNotEmpty) ...[
                                            const SizedBox(width: 8),
                                            Text(
                                              _timeAgo(time),
                                              style: const TextStyle(
                                                  color: Colors.black45,
                                                  fontSize: 11),
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        text,
                                        style: const TextStyle(
                                            color: Colors.black87,
                                            fontSize: 14,
                                            height: 1.4),
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
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: const Border(top: BorderSide(color: Color(0xFFE5E7EB))),
            ),
            padding: EdgeInsets.fromLTRB(12, 8, 12, 8 + bottom),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    style: const TextStyle(color: Colors.black87, fontSize: 14),
                    maxLines: 3,
                    minLines: 1,
                    decoration: InputDecoration(
                      hintText: 'Add a comment...',
                      hintStyle: const TextStyle(color: Colors.black38),
                      filled: true,
                      fillColor: const Color(0xFFF3F4F6),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _post,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFF0050), Color(0xFFFF4081)],
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                            color: Colors.red.withOpacity(0.4), blurRadius: 8)
                      ],
                    ),
                    child: _posting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.send_rounded,
                            color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _timeAgo(String iso) {
    try {
      final dt = DateTime.parse(iso);
      final diff = DateTime.now().difference(dt);
      if (diff.inSeconds < 60) return '${diff.inSeconds}s';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m';
      if (diff.inHours < 24) return '${diff.inHours}h';
      return '${diff.inDays}d';
    } catch (_) {
      return '';
    }
  }
}

// ─── Floating heart data + widget ─────────────────────────────────────────────

class _FloatingHeartData {
  final AnimationController ctrl;
  final double xOffset;
  late final Animation<double> posY;
  late final Animation<double> opacity;
  late final Animation<double> scale;

  _FloatingHeartData({required this.ctrl, required this.xOffset}) {
    posY = Tween(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: ctrl, curve: Curves.easeOut));
    opacity = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 15),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 60),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 25),
    ]).animate(ctrl);
    scale = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 0.4, end: 1.3), weight: 25),
      TweenSequenceItem(tween: Tween(begin: 1.3, end: 0.9), weight: 75),
    ]).animate(ctrl);
  }
}

class _FloatingHeart extends StatelessWidget {
  final _FloatingHeartData data;
  const _FloatingHeart({required this.data});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: data.ctrl,
      builder: (_, __) => Transform.translate(
        offset: Offset(data.xOffset, -data.posY.value * 220),
        child: Opacity(
          opacity: data.opacity.value.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: data.scale.value,
            child: const Icon(Icons.favorite, color: Colors.red, size: 32),
          ),
        ),
      ),
    );
  }
}
