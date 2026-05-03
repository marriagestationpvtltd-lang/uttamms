import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class StoryViewerScreen extends StatefulWidget {
  final String userName;
  final String profilePicture;
  final List<Map<String, dynamic>> stories;
  final int currentUserId;
  final Future<bool> Function(int storyId, String privacy)? onEditPrivacy;
  final Future<bool> Function(int storyId)? onDeleteStory;

  const StoryViewerScreen({
    super.key,
    required this.userName,
    required this.profilePicture,
    required this.stories,
    this.currentUserId = 0,
    this.onEditPrivacy,
    this.onDeleteStory,
  });

  @override
  State<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<StoryViewerScreen> {
  int _index = 0;
  VideoPlayerController? _videoCtrl;
  bool _videoReady = false;
  late List<Map<String, dynamic>> _stories;

  @override
  void initState() {
    super.initState();
    _stories = widget.stories.map((e) => Map<String, dynamic>.from(e)).toList();
    _setupCurrentStory();
  }

  @override
  void dispose() {
    _videoCtrl?.dispose();
    super.dispose();
  }

  Future<void> _setupCurrentStory() async {
    if (_stories.isEmpty) return;
    final story = _stories[_index];
    final mediaType =
        (story['media_type']?.toString() ?? 'image').toLowerCase();
    final mediaUrl = story['media_url']?.toString() ?? '';

    _videoCtrl?.dispose();
    _videoCtrl = null;
    setState(() => _videoReady = false);

    if (mediaType != 'video' || mediaUrl.isEmpty) {
      return;
    }

    final ctrl = kIsWeb
        ? VideoPlayerController.networkUrl(Uri.parse(mediaUrl))
        : VideoPlayerController.networkUrl(Uri.parse(mediaUrl));
    _videoCtrl = ctrl;
    try {
      await ctrl.initialize();
      ctrl.setLooping(true);
      await ctrl.play();
      if (mounted) setState(() => _videoReady = true);
    } catch (_) {
      if (mounted) setState(() => _videoReady = false);
    }
  }

  void _next() {
    if (_index >= _stories.length - 1) {
      Navigator.pop(context);
      return;
    }
    setState(() => _index += 1);
    _setupCurrentStory();
  }

  void _prev() {
    if (_index <= 0) return;
    setState(() => _index -= 1);
    _setupCurrentStory();
  }

  bool _isOwnerStory(Map<String, dynamic> story) {
    final uid = int.tryParse(story['user_id']?.toString() ?? '') ?? 0;
    return widget.currentUserId > 0 && uid == widget.currentUserId;
  }

  Future<void> _changePrivacy(Map<String, dynamic> story) async {
    final callback = widget.onEditPrivacy;
    if (callback == null) return;

    final current = story['privacy']?.toString() ?? 'public';
    final privacy = await showModalBottomSheet<String>(
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
            const SizedBox(height: 14),
            const Text('Change story privacy',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16)),
            const SizedBox(height: 10),
            for (final p in const [
              'public',
              'matches_only',
              'paid_only',
              'verified_only',
              'private'
            ])
              ListTile(
                title: Text(p.replaceAll('_', ' '),
                    style: const TextStyle(color: Colors.white)),
                trailing: current == p
                    ? const Icon(Icons.check, color: Colors.greenAccent)
                    : null,
                onTap: () => Navigator.pop(context, p),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (privacy == null || privacy == current) return;

    final ok = await callback(
        int.tryParse(story['id']?.toString() ?? '') ?? 0, privacy);
    if (!mounted) return;
    if (!ok) return;
    setState(() {
      _stories[_index]['privacy'] = privacy;
    });
  }

  Future<void> _deleteCurrentStory(Map<String, dynamic> story) async {
    final callback = widget.onDeleteStory;
    if (callback == null) return;
    final id = int.tryParse(story['id']?.toString() ?? '') ?? 0;
    if (id <= 0) return;

    final confirm = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Delete story?'),
            content:
                const Text('This story will be removed from your profile.'),
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

    final ok = await callback(id);
    if (!mounted || !ok) return;

    setState(() {
      _stories.removeAt(_index);
      if (_stories.isEmpty) {
        Navigator.pop(context);
        return;
      }
      if (_index >= _stories.length) {
        _index = _stories.length - 1;
      }
    });
    if (mounted && _stories.isNotEmpty) {
      _setupCurrentStory();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_stories.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white70)),
      );
    }

    final story = _stories[_index];
    final mediaType =
        (story['media_type']?.toString() ?? 'image').toLowerCase();
    final mediaUrl = story['media_url']?.toString() ?? '';
    final caption = story['caption']?.toString() ?? '';

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (mediaType == 'video')
              _buildVideo(mediaUrl)
            else
              _buildImage(mediaUrl),
            Positioned(
              top: 10,
              left: 12,
              right: 12,
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundImage: widget.profilePicture.isNotEmpty
                        ? NetworkImage(widget.profilePicture)
                        : null,
                    child: widget.profilePicture.isEmpty
                        ? const Icon(Icons.person, size: 18)
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.userName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  if (_isOwnerStory(story))
                    PopupMenuButton<String>(
                      color: const Color(0xFF2C2C2E),
                      icon: const Icon(Icons.more_vert, color: Colors.white),
                      onSelected: (v) {
                        if (v == 'privacy') {
                          _changePrivacy(story);
                        } else if (v == 'delete') {
                          _deleteCurrentStory(story);
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                            value: 'privacy',
                            child: Text('Edit privacy',
                                style: TextStyle(color: Colors.white))),
                        PopupMenuItem(
                            value: 'delete',
                            child: Text('Delete story',
                                style: TextStyle(color: Colors.redAccent))),
                      ],
                    ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),
            if (caption.isNotEmpty)
              Positioned(
                left: 16,
                right: 16,
                bottom: 32,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    caption,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: _prev,
                    child: const SizedBox.expand(),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: _next,
                    child: const SizedBox.expand(),
                  ),
                ),
              ],
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  children: List.generate(_stories.length, (i) {
                    final progress = i <= _index ? 1.0 : 0.0;
                    return Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        height: 3,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: progress,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImage(String mediaUrl) {
    if (mediaUrl.isEmpty) {
      return const Center(
        child: Icon(Icons.broken_image, color: Colors.white54, size: 56),
      );
    }

    return kIsWeb
        ? Image.network(mediaUrl, fit: BoxFit.contain)
        : Image.network(mediaUrl, fit: BoxFit.contain,
            errorBuilder: (_, __, ___) {
            return const Center(
              child: Icon(Icons.broken_image, color: Colors.white54, size: 56),
            );
          });
  }

  Widget _buildVideo(String mediaUrl) {
    final ctrl = _videoCtrl;
    if (ctrl == null || !_videoReady || !ctrl.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white70),
      );
    }

    return Center(
      child: AspectRatio(
        aspectRatio:
            ctrl.value.aspectRatio == 0 ? 9 / 16 : ctrl.value.aspectRatio,
        child: VideoPlayer(ctrl),
      ),
    );
  }
}
