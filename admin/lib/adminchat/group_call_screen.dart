// group_call_screen.dart
//
// Professional group-call UI for the matchmaking admin panel.
//
// Features:
//  • Large active-speaker video (only one video rendered at a time — performance)
//  • Horizontal participant strip at the bottom (avatar + first name only)
//  • Floating "Add User" FAB with search modal (online users first)
//  • Glassmorphism control bar — mic, video, mute-all, settings, end-call
//  • Per-participant admin actions — mute / remove (long-press the avatar)
//  • Active-speaker detection via Agora audio volume indication
//  • Privacy: first name only shown everywhere; no user-IDs in the UI
//  • Smooth AnimatedSwitcher / fade / scale transitions

import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:adminmrz/adminchat/services/admin_socket_service.dart';
import 'package:adminmrz/adminchat/services/pushservice.dart';
import 'package:adminmrz/settings/call_settings_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:provider/provider.dart';
import 'package:adminmrz/adminchat/tokengenerator.dart';
import 'package:adminmrz/config/app_endpoints.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

// ─── colour palette (matches video_call_page.dart) ────────────────────────────
const _kPrimary = Color(0xFF6366F1);
const _kPrimaryDark = Color(0xFF4F46E5);
const _kViolet = Color(0xFF8B5CF6);
const _kEmerald = Color(0xFF10B981);
const _kAmber = Color(0xFFF59E0B);
const _kRose = Color(0xFFEF4444);
const _kSlate = Color(0xFF0F172A);
const _kSlateDark = Color(0xFF1E293B);

// ─── Participant model ────────────────────────────────────────────────────────

/// Represents one person in the group call.
class _GParticipant {
  final String userId;
  final String displayName; // first name only
  final String? photoUrl;
  int? agoraUid; // null until they join the channel
  bool micMuted = false;
  bool videoOff = false;
  bool hasRemoteVideo = false;
  bool isSpeaking = false;
  Widget? videoView; // populated lazily when remote user joins

  _GParticipant({
    required this.userId,
    required this.displayName,
    this.photoUrl,
    this.agoraUid,
  });
}

// ─── Widget ───────────────────────────────────────────────────────────────────

class GroupCallScreen extends StatefulWidget {
  /// Admin (local) user info.
  final String adminId;
  final String adminName;

  /// Initial participants to invite (from the picker dialog).
  /// Each entry: {'id': userId, 'name': firstName, 'photoUrl'?: url}
  final List<Map<String, String>> initialParticipants;

  /// Set to true for a video call; false for audio-only.
  final bool isVideo;

  /// Called when the call ends (to pop / remove overlay).
  final VoidCallback? onEnd;

  /// Called when the call ends with metadata.
  final void Function(String callType, String status, int durationSeconds)?
  onCallEnded;

  /// Called when the user taps the minimise button.
  final VoidCallback? onMinimize;

  const GroupCallScreen({
    super.key,
    required this.adminId,
    required this.adminName,
    required this.initialParticipants,
    this.isVideo = true,
    this.onEnd,
    this.onCallEnded,
    this.onMinimize,
  });

  @override
  State<GroupCallScreen> createState() => _GroupCallScreenState();
}

class _GroupCallScreenState extends State<GroupCallScreen>
    with TickerProviderStateMixin {
  // ── Agora ──────────────────────────────────────────────────────────────────
  late RtcEngine _engine;
  int _localUid = 0;
  String _channel = '';
  String _token = '';
  bool _joined = false;

  // ── Local controls ─────────────────────────────────────────────────────────
  bool _micMuted = false;
  bool _videoEnabled = true;
  bool _controlsVisible = true;
  bool _ending = false;

  // ── Call state ─────────────────────────────────────────────────────────────
  bool _callActive = false;
  Timer? _callTimer;
  Duration _duration = Duration.zero;
  Timer? _controlsHideTimer;
  Timer? _speakingHoldTimer;

  // ── Participants ────────────────────────────────────────────────────────────
  // Index 0 is always the local (admin) participant.
  final List<_GParticipant> _participants = [];
  String? _activeSpeakerId; // userId of the current active speaker
  String? _pinnedUserId; // manually focused participant in video grid
  Widget? _localVideoView;

  // Map from Agora UID → userId (built as remote users join)
  final Map<int, String> _uidToUserId = {};

  // ── Socket ──────────────────────────────────────────────────────────────────
  final AdminSocketService _socket = AdminSocketService();
  StreamSubscription<Map<String, dynamic>>? _participantAcceptedSub;
  StreamSubscription<Map<String, dynamic>>? _participantRejectedSub;
  StreamSubscription<Map<String, dynamic>>? _participantLeftSub;
  StreamSubscription<Map<String, dynamic>>? _callEndedSub;

  // ── Calling tone (plays until first participant joins) ────────────────────
  late AudioPlayer _ringtonePlayer;
  bool _isPlayingRingtone = false;
  Timer? _ringtoneRepeatTimer;
  StreamSubscription<PlayerState>? _ringtoneStateSubscription;

  // ── Animation controllers ──────────────────────────────────────────────────
  late AnimationController _fadeCtrls;
  late Animation<double> _fadeAnim;
  late AnimationController _speakingPulseCtrl;
  late Animation<double> _speakingPulse;

  // ── Scroll (participant strip) ─────────────────────────────────────────────
  final ScrollController _stripScrollCtrl = ScrollController();

  // ── Add-user inline panel ─────────────────────────────────────────────────
  bool _showingAddUserPanel = false;
  bool _isLoadingAddUser = false;
  List<Map<String, dynamic>> _addableUsers = [];

  // ── Participant-actions inline panel ──────────────────────────────────────
  bool _showingParticipantActions = false;
  _GParticipant? _pendingActionParticipant;

  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();

    _fadeCtrls = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      value: 1.0,
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrls, curve: Curves.easeInOut);

    _speakingPulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _speakingPulse = CurvedAnimation(
      parent: _speakingPulseCtrl,
      curve: Curves.easeInOut,
    );

    _ringtonePlayer = AudioPlayer();
    _ringtonePlayer.setReleaseMode(ReleaseMode.stop);
    _ringtoneStateSubscription = _ringtonePlayer.onPlayerStateChanged.listen((
      state,
    ) {
      if (state == PlayerState.completed &&
          _isPlayingRingtone &&
          !_callActive &&
          !_ending) {
        // Repeat after a short gap for a realistic ringback tone experience.
        _ringtoneRepeatTimer?.cancel();
        _ringtoneRepeatTimer = Timer(
          const Duration(milliseconds: 800),
          _playRingtoneSingle,
        );
      }
    });

    // Add admin (local) participant first.
    _participants.add(
      _GParticipant(userId: widget.adminId, displayName: 'You'),
    );
    _activeSpeakerId = widget.adminId;

    // Add invited participants with pending status.
    for (final p in widget.initialParticipants) {
      _participants.add(
        _GParticipant(
          userId: p['id'] ?? '',
          displayName: _firstName(p['name'] ?? ''),
          photoUrl: p['photoUrl'],
        ),
      );
    }

    _startCall();
    _scheduleControlsHide();
  }

  // ─── Calling tone helpers ──────────────────────────────────────────────────

  Future<void> _playRingtone() async {
    if (_isPlayingRingtone || _callActive || _ending) return;
    _isPlayingRingtone = true;
    await _playRingtoneSingle();
  }

  Future<void> _playRingtoneSingle() async {
    if (!_isPlayingRingtone || _callActive || _ending || !mounted) return;
    // Capture context-dependent values before any await to avoid using context
    // after the widget may have been unmounted.
    final settings = context.read<CallSettingsProvider>();
    try {
      await _ringtonePlayer.stop();
      if (settings.hasCustomTone) {
        try {
          await _ringtonePlayer.play(UrlSource(settings.customToneUrl));
          return;
        } catch (_) {}
      }
      await _ringtonePlayer.play(AssetSource(settings.selectedTone.asset));
    } catch (_) {}
  }

  Future<void> _stopRingtone() async {
    _ringtoneRepeatTimer?.cancel();
    _ringtoneRepeatTimer = null;
    _isPlayingRingtone = false;
    try {
      await _ringtonePlayer.stop();
    } catch (_) {}
  }

  // ─── First name helper ─────────────────────────────────────────────────────
  static String _firstName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'User';
    return trimmed.split(' ').first;
  }

  // ─── Control auto-hide ─────────────────────────────────────────────────────
  void _scheduleControlsHide() {
    _controlsHideTimer?.cancel();
    _controlsHideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _callActive) {
        setState(() => _controlsVisible = false);
        _fadeCtrls.reverse();
      }
    });
  }

  void _showControls() {
    if (!_controlsVisible) {
      setState(() => _controlsVisible = true);
      _fadeCtrls.forward();
    }
    _scheduleControlsHide();
  }

  // ─── Start call ────────────────────────────────────────────────────────────
  Future<void> _startCall() async {
    try {
      _localUid = (DateTime.now().millisecondsSinceEpoch % 999_999) + 1;

      final firstPeer = widget.initialParticipants.isNotEmpty
          ? widget.initialParticipants.first['id'] ?? ''
          : 'group';
      _channel =
          'grp_${widget.adminId.substring(0, min(4, widget.adminId.length))}'
          '_${firstPeer.substring(0, min(4, firstPeer.length))}'
          '_${DateTime.now().millisecondsSinceEpoch}';
      if (_channel.length > 64) _channel = _channel.substring(0, 64);

      _token = await AgoraTokenService.getToken(
        channelName: _channel,
        uid: _localUid,
      );

      // Start calling tone while waiting for first participant to join.
      _playRingtone();

      // Invite all initial participants via socket + push.
      final socketReady = await _socket.ensureConnected();
      for (final p in widget.initialParticipants) {
        final pId = p['id'] ?? '';
        if (pId.isEmpty) continue;
        if (socketReady) {
          _socket.emitAddParticipantToCall(
            newParticipantId: pId,
            channelName: _channel,
            callType: widget.isVideo ? 'video' : 'audio',
            adminId: widget.adminId,
            adminName: widget.adminName,
            newParticipantName: p['name'],
            agoraAppId: AgoraTokenService.appId,
            callerUid: _localUid.toString(),
          );
        }
        // Fire FCM push in parallel — don't block the next participant's
        // socket invite on a slow/failing FCM endpoint.
        if (widget.isVideo) {
          unawaited(
            NotificationService.sendGroupVideoCallNotification(
              recipientUserId: pId,
              callerName: widget.adminName,
              channelName: _channel,
              callerId: widget.adminId,
              callerUid: _localUid.toString(),
              agoraAppId: AgoraTokenService.appId,
              agoraCertificate: 'SERVER_ONLY',
            ),
          );
        } else {
          unawaited(
            NotificationService.sendGroupCallNotification(
              recipientUserId: pId,
              callerName: widget.adminName,
              channelName: _channel,
              callerId: widget.adminId,
              callerUid: _localUid.toString(),
              agoraAppId: AgoraTokenService.appId,
            ),
          );
        }
      }

      // Subscribe to socket events.
      _participantAcceptedSub?.cancel();
      _participantAcceptedSub = _socket.onParticipantAcceptedCall.listen(
        _onParticipantAccepted,
      );

      _participantRejectedSub?.cancel();
      _participantRejectedSub = _socket.onParticipantRejectedCall.listen(
        _onParticipantRejected,
      );

      _participantLeftSub?.cancel();
      _participantLeftSub = _socket.onParticipantLeftCall.listen(
        _onParticipantLeft,
      );

      _callEndedSub?.cancel();
      _callEndedSub = _socket.onCallEnded.listen((data) {
        if (data['channelName']?.toString() == _channel)
          _endCall(notifyPeers: false);
      });

      // Initialise Agora.
      _engine = createAgoraRtcEngine();
      await _engine.initialize(
        RtcEngineContext(
          appId: AgoraTokenService.appId,
          channelProfile: ChannelProfileType.channelProfileCommunication,
        ),
      );

      await _engine.disableAudio(); // re-enabled once first peer joins
      if (widget.isVideo) {
        await _engine.enableVideo();
        await _engine.startPreview();
      }

      // Enable audio-volume indication so we can detect the active speaker.
      await _engine.enableAudioVolumeIndication(
        interval: 400,
        smooth: 3,
        reportVad: true,
      );

      _engine.registerEventHandler(
        RtcEngineEventHandler(
          onJoinChannelSuccess: (_, __) {
            if (mounted) {
              setState(() => _joined = true);
              if (widget.isVideo) _buildLocalVideo();
            }
          },
          onUserJoined: (_, uid, __) => _onRemoteUserJoined(uid),
          onUserOffline: (_, uid, __) => _onRemoteUserOffline(uid),
          onAudioVolumeIndication: (_, speakers, __, ___) =>
              _onAudioVolumeIndication(speakers),
          onRemoteVideoStateChanged: (_, uid, state, __, ___) {
            final userId = _uidToUserId[uid];
            if (userId == null) return;
            final idx = _participants.indexWhere((p) => p.userId == userId);
            if (idx < 0) return;
            // Track camera on/off state only.
            // We do NOT hide the AgoraVideoView widget itself (that would break
            // the HTML video element's stream on Flutter Web). Instead we show
            // an avatar overlay when videoOff = true.
            final bool isStopped =
                state == RemoteVideoState.remoteVideoStateStopped ||
                state == RemoteVideoState.remoteVideoStateFailed;
            final bool isActive =
                state == RemoteVideoState.remoteVideoStateDecoding ||
                state == RemoteVideoState.remoteVideoStateStarting;
            if (mounted && (isStopped || isActive)) {
              setState(() {
                _participants[idx].videoOff = isStopped;
                _participants[idx].hasRemoteVideo = !isStopped;
              });
            }
          },
          onFirstRemoteVideoFrame: (_, uid, __, ___, ____) {
            final userId = _uidToUserId[uid];
            if (userId == null) return;
            final idx = _participants.indexWhere((p) => p.userId == userId);
            if (idx < 0 || !mounted) return;
            setState(() {
              _participants[idx].hasRemoteVideo = true;
              _participants[idx].videoOff = false;
            });
          },
          onError: (_, __) {},
        ),
      );

      await _engine.setClientRole(role: ClientRoleType.clientRoleBroadcaster);
      await _engine.joinChannel(
        token: _token,
        channelId: _channel,
        uid: _localUid,
        options: ChannelMediaOptions(
          publishMicrophoneTrack: false,
          publishCameraTrack: widget.isVideo,
          autoSubscribeAudio: true,
          autoSubscribeVideo: widget.isVideo,
        ),
      );
    } catch (e, stackTrace) {
      debugPrint('❌ GROUP CALL INITIALIZATION ERROR: $e');
      debugPrint('Stack trace: $stackTrace');

      if (mounted) {
        // Show error dialog before exiting
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Group Call Error'),
            content: SingleChildScrollView(
              child: Text(
                'Failed to initialize group call:\n\n${e.toString()}\n\nPlease check your connection and try again.',
                style: const TextStyle(fontSize: 14),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _exit();
                },
                child: const Text('OK'),
              ),
            ],
          ),
        );
      } else {
        _exit();
      }
    }
  }

  // ─── Agora event handlers ──────────────────────────────────────────────────

  void _buildLocalVideo() {
    final view = AgoraVideoView(
      controller: VideoViewController(
        rtcEngine: _engine,
        canvas: const VideoCanvas(
          uid: 0,
          renderMode: RenderModeType.renderModeHidden,
        ),
      ),
    );
    if (mounted) setState(() => _localVideoView = view);
    _participants.first.videoView = view;
  }

  void _onRemoteUserJoined(int uid) {
    if (_ending) return;

    // Try to match Agora uid to a known participant by order of join.
    // We use the first participant without an Agora UID yet.
    String? matchedUserId;
    for (final p in _participants) {
      if (p.userId == widget.adminId) continue; // skip local
      if (p.agoraUid == null) {
        p.agoraUid = uid;
        matchedUserId = p.userId;
        break;
      }
    }

    if (matchedUserId == null) {
      // Unknown participant — add a placeholder.
      matchedUserId = 'remote_$uid';
      if (mounted) {
        setState(() {
          _participants.add(
            _GParticipant(
              userId: matchedUserId!,
              displayName: 'Guest',
              agoraUid: uid,
            ),
          );
        });
      }
    }

    _uidToUserId[uid] = matchedUserId;

    // Build the remote video view.
    if (widget.isVideo) {
      final videoView = AgoraVideoView(
        controller: VideoViewController.remote(
          rtcEngine: _engine,
          canvas: VideoCanvas(
            uid: uid,
            renderMode: RenderModeType.renderModeHidden,
          ),
          connection: RtcConnection(channelId: _channel),
        ),
      );
      final capturedUserId = matchedUserId;
      final idx = _participants.indexWhere((p) => p.userId == capturedUserId);
      if (idx >= 0 && mounted) {
        // Always keep AgoraVideoView in the widget tree on Flutter Web.
        // Removing/re-adding it breaks the HTML video element's stream
        // attachment. Set immediately; videoOff only when camera turns off.
        setState(() {
          _participants[idx].videoView = videoView;
          _participants[idx].hasRemoteVideo = true;
          _participants[idx].videoOff = false;
        });
      }
    }

    if (!_callActive) {
      _callActive = true;
      // First participant joined — stop the calling tone.
      _stopRingtone();
      _engine.enableAudio();
      _engine.updateChannelMediaOptions(
        ChannelMediaOptions(
          publishMicrophoneTrack: !_micMuted,
          publishCameraTrack: widget.isVideo && _videoEnabled,
          autoSubscribeAudio: true,
          autoSubscribeVideo: widget.isVideo,
        ),
      );
      _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _duration += const Duration(seconds: 1));
      });
    }

    if (mounted) setState(() {});
  }

  void _onRemoteUserOffline(int uid) {
    if (_ending) return;
    final userId = _uidToUserId.remove(uid);
    if (userId == null) return;
    if (mounted) {
      setState(() {
        final idx = _participants.indexWhere((p) => p.userId == userId);
        if (idx >= 0) {
          _participants[idx].agoraUid = null;
          _participants[idx].hasRemoteVideo = false;
          _participants[idx].videoOff = true;
          _participants[idx].videoView = null;
        }
        if (_pinnedUserId == userId) _pinnedUserId = null;
      });
    }
    // If no remote peers remain, end the call.
    if (_uidToUserId.isEmpty && _callActive) _endCall();
  }

  void _onAudioVolumeIndication(List<AudioVolumeInfo> speakers) {
    if (!mounted || _ending) return;

    // Find loudest speaker above a threshold.
    // Keep threshold low so normal voice on mobile/web still triggers effect.
    const int kThreshold = 4;
    int? bestUid;
    int bestVolume = 0;

    for (final s in speakers) {
      final vol = s.volume;
      final uid = s.uid;
      if (vol != null && uid != null && vol > bestVolume) {
        bestVolume = vol;
        bestUid = uid;
      }
    }

    String? newSpeakerId;
    if (bestUid != null && bestVolume > kThreshold) {
      if (bestUid == 0 || bestUid == _localUid) {
        newSpeakerId = widget.adminId;
      } else {
        newSpeakerId = _uidToUserId[bestUid];
      }
    }

    // Do not immediately clear on quiet frames; keep effect briefly so users
    // can visually notice who is speaking.
    if (newSpeakerId != null) {
      setState(() {
        for (final p in _participants) {
          p.isSpeaking = (p.userId == newSpeakerId);
        }
        _activeSpeakerId = newSpeakerId;
      });

      _speakingHoldTimer?.cancel();
      _speakingHoldTimer = Timer(const Duration(milliseconds: 1200), () {
        if (!mounted || _ending) return;
        setState(() {
          for (final p in _participants) {
            p.isSpeaking = false;
          }
        });
      });
    }
  }

  // ─── Socket event handlers ─────────────────────────────────────────────────

  void _onParticipantAccepted(Map<String, dynamic> data) {
    if (data['channelName']?.toString() != _channel) return;
    // Mark participant as accepted (UI already shows them; no extra action needed).
  }

  void _onParticipantRejected(Map<String, dynamic> data) {
    if (data['channelName']?.toString() != _channel) return;
    final rejectedId = data['rejectedById']?.toString() ?? '';
    if (rejectedId.isEmpty) return;
    // Show a brief snackbar and remove after delay.
    if (mounted) {
      final idx = _participants.indexWhere((p) => p.userId == rejectedId);
      final name = idx >= 0 ? _participants[idx].displayName : 'User';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$name declined the call'),
          duration: const Duration(seconds: 3),
          backgroundColor: _kRose.withOpacity(0.9),
        ),
      );
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted) {
          setState(() {
            _participants.removeWhere((p) => p.userId == rejectedId);
            if (_pinnedUserId == rejectedId) _pinnedUserId = null;
          });
        }
      });
    }
  }

  void _onParticipantLeft(Map<String, dynamic> data) {
    if (data['channelName']?.toString() != _channel) return;
    final leftId = data['leftUserId']?.toString() ?? '';
    if (leftId.isEmpty) return;
    if (mounted) {
      setState(() {
        _participants.removeWhere((p) => p.userId == leftId);
        if (_pinnedUserId == leftId) _pinnedUserId = null;
      });
    }
  }

  // ─── Admin actions ─────────────────────────────────────────────────────────

  void _muteParticipant(_GParticipant p) {
    if (p.userId == widget.adminId) return;
    // Toggle the local mute indicator. In Agora group calls the admin cannot
    // directly mute a remote participant's microphone — only the user's own
    // client can do that. We track the state locally so the admin UI reflects
    // the admin's intent and can inform the user out-of-band if a custom
    // server-side "mute_request" event is wired up later.
    if (mounted) setState(() => p.micMuted = !p.micMuted);
  }

  void _removeParticipant(_GParticipant p) {
    if (p.userId == widget.adminId) return;
    // Notify the peer (and the server) that THIS participant is leaving the
    // group call. Using `leave_group_call` ensures the rest of the call
    // continues for the remaining participants — unlike `call_end`, which
    // would broadcast `call_ended` to every member and tear the call down.
    _socket.emitLeaveGroupCall(channelName: _channel, userId: p.userId);
    if (mounted) {
      setState(() {
        _participants.removeWhere((x) => x.userId == p.userId);
        if (_pinnedUserId == p.userId) _pinnedUserId = null;
      });
    }
  }

  // ─── Add participant flow ──────────────────────────────────────────────────
  //
  // Previously used showModalBottomSheet which inserts a Navigator route that
  // renders BELOW the OverlayEntry hosting this call screen.  We now drive
  // the user-list entirely from state, rendering it as the top-most child of
  // the main Stack so it is always visible above the call UI.

  Future<void> _addUser() async {
    if (_isLoadingAddUser) return;
    setState(() => _isLoadingAddUser = true);

    final excludeIds = _participants.map((p) => p.userId).toSet();
    // Use the first non-admin participant's ID for gender-based filtering so
    // the add-user list shows users of the opposite gender (matchmaking rule:
    // male ↔ female only).  Falls back to the PHP user list if unavailable.
    String? filterUserId;
    for (final p in widget.initialParticipants) {
      final id = p['id'];
      if (id != null && id.isNotEmpty && id != widget.adminId) {
        filterUserId = id;
        break;
      }
    }
    final users = await _fetchUsers(
      excludeIds: excludeIds,
      filterByUserId: filterUserId,
    );
    if (!mounted) return;
    setState(() {
      _addableUsers = users;
      _isLoadingAddUser = false;
      _showingAddUserPanel = true;
    });
  }

  /// Called by the inline add-user panel when the admin selects a user.
  Future<void> _onAddUserConfirmed(Map<String, String> selected) async {
    setState(() => _showingAddUserPanel = false);

    final newId = selected['id'] ?? '';
    if (newId.isEmpty) return;
    final newName = _firstName(selected['name'] ?? '');
    final photoUrl = selected['photoUrl'];

    setState(() {
      _participants.add(
        _GParticipant(userId: newId, displayName: newName, photoUrl: photoUrl),
      );
    });

    final socketReady = await _socket.ensureConnected();
    if (socketReady) {
      _socket.emitAddParticipantToCall(
        newParticipantId: newId,
        channelName: _channel,
        callType: widget.isVideo ? 'video' : 'audio',
        adminId: widget.adminId,
        adminName: widget.adminName,
        newParticipantName: newName,
        agoraAppId: AgoraTokenService.appId,
        callerUid: _localUid.toString(),
      );
    }
    if (widget.isVideo) {
      await NotificationService.sendGroupVideoCallNotification(
        recipientUserId: newId,
        callerName: widget.adminName,
        channelName: _channel,
        callerId: widget.adminId,
        callerUid: _localUid.toString(),
        agoraAppId: AgoraTokenService.appId,
        agoraCertificate: 'SERVER_ONLY',
      );
    } else {
      await NotificationService.sendGroupCallNotification(
        recipientUserId: newId,
        callerName: widget.adminName,
        channelName: _channel,
        callerId: widget.adminId,
        callerUid: _localUid.toString(),
        agoraAppId: AgoraTokenService.appId,
      );
    }
  }

  /// Fetch the list of users available to add to this group call.
  ///
  /// When [filterByUserId] is provided the socket server's gender-filtered
  /// `/api/call-join-list` endpoint is used, which returns online users first
  /// and applies the matchmaking gender rule (male ↔ female only).
  /// When no filter user is available the method falls back to the PHP
  /// `get_users.php` endpoint so existing behaviour is preserved.
  ///
  /// [excludeIds] – user IDs already in the call; filtered out client-side.
  static Future<List<Map<String, dynamic>>> _fetchUsers({
    Set<String> excludeIds = const {},
    String? filterByUserId,
  }) async {
    // ── Attempt 1: socket server's gender-filtered, online-first list ─────────
    if (filterByUserId != null && filterByUserId.isNotEmpty) {
      try {
        final uri = Uri.parse(
          '$kAdminSocketBaseUrl/api/call-join-list',
        ).replace(queryParameters: {'userId': filterByUserId, 'limit': '50'});
        final res = await http.get(uri);
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          if (data['success'] == true) {
            final List<dynamic> raw = (data['users'] as List<dynamic>?) ?? [];
            return raw
                .map((u) {
                  final m = Map<String, dynamic>.from(u as Map);
                  // Normalise to the keys that _AddUserModal already reads.
                  m['_isOnline'] = m['isOnline'] == true;
                  m['_firstName'] = (m['firstName'] ?? '').toString().trim();
                  m['_fullName'] = (m['name'] ?? '').toString().trim();
                  m['profile_picture'] = m['profilePicture']?.toString();
                  final lastSeenStr = m['lastSeen']?.toString();
                  m['_lastSeen'] = lastSeenStr != null && lastSeenStr.isNotEmpty
                      ? DateTime.tryParse(lastSeenStr)
                      : null;
                  return m;
                })
                .where((u) => !excludeIds.contains(u['id']?.toString()))
                .where((u) => u['_isOnline'] == true)
                .toList();
          }
        }
      } catch (_) {
        // Fall through to PHP fallback below.
      }
    }

    // ── Fallback: existing PHP get_users.php endpoint ─────────────────────────
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? '';
      final res = await http.get(
        Uri.parse('$kAdminApi9BaseUrl/get_users.php'),
        headers: {
          'Content-Type': 'application/json',
          if (token.isNotEmpty) 'Authorization': 'Bearer $token',
        },
      );
      if (res.statusCode != 200) return [];
      final data = jsonDecode(res.body);
      final List<dynamic> raw = (data['data'] as List<dynamic>?) ?? [];
      final users = raw
          .where((u) => !excludeIds.contains(u['id']?.toString()))
          .map((u) {
            final m = Map<String, dynamic>.from(u as Map);
            final fn = (m['firstName'] ?? '').toString().trim();
            final ln = (m['lastName'] ?? '').toString().trim();
            m['_isOnline'] =
                m['isOnline'] == 1 ||
                m['isOnline'] == '1' ||
                m['isOnline'] == true;
            m['_firstName'] = fn;
            m['_fullName'] = [fn, ln].where((s) => s.isNotEmpty).join(' ');
            final lastSeenRaw = m['lastSeen']?.toString();
            m['_lastSeen'] = (lastSeenRaw != null && lastSeenRaw.isNotEmpty)
                ? DateTime.tryParse(lastSeenRaw)
                : null;
            return m;
          })
          .where((u) => u['_isOnline'] == true)
          .toList();
      users.sort((a, b) {
        final aLastSeen = a['_lastSeen'] as DateTime?;
        final bLastSeen = b['_lastSeen'] as DateTime?;
        if (aLastSeen != null && bLastSeen != null) {
          final cmp = bLastSeen.compareTo(aLastSeen);
          if (cmp != 0) return cmp;
        } else if (aLastSeen != null) {
          return -1;
        } else if (bLastSeen != null) {
          return 1;
        }
        return (a['_firstName'] as String).compareTo(b['_firstName'] as String);
      });
      return users;
    } catch (_) {
      return [];
    }
  }

  // ─── Local control toggles ─────────────────────────────────────────────────

  void _toggleMic() {
    setState(() => _micMuted = !_micMuted);
    _engine.muteLocalAudioStream(_micMuted);
    _engine.updateChannelMediaOptions(
      ChannelMediaOptions(publishMicrophoneTrack: !_micMuted),
    );
    _participants.first.micMuted = _micMuted;
  }

  void _toggleVideo() {
    setState(() => _videoEnabled = !_videoEnabled);
    _engine.muteLocalVideoStream(!_videoEnabled);
    _participants.first.videoOff = !_videoEnabled;
    if (_videoEnabled) _engine.startPreview();
  }

  void _muteAll() {
    // Track mute state locally for all remote participants.
    // Agora does not allow the admin to remotely silence other clients' mics;
    // this reflects the admin's intent in the UI. A server-side "mute_request"
    // event can be wired up later to relay the action to the user apps.
    for (final p in _participants) {
      if (p.userId == widget.adminId) continue;
      p.micMuted = true;
    }
    if (mounted) setState(() {});
  }

  // ─── End call ─────────────────────────────────────────────────────────────

  Future<void> _endCall({bool notifyPeers = true}) async {
    if (_ending) return;
    _ending = true;
    _callTimer?.cancel();
    await _stopRingtone();

    await _participantAcceptedSub?.cancel();
    await _participantRejectedSub?.cancel();
    await _participantLeftSub?.cancel();
    await _callEndedSub?.cancel();

    if (notifyPeers) {
      for (final p in _participants) {
        if (p.userId == widget.adminId) continue;
        _socket.emitCallEnd(
          callerId: widget.adminId,
          recipientId: p.userId,
          channelName: _channel,
          callType: widget.isVideo ? 'video' : 'audio',
          duration: _duration.inSeconds,
        );
      }
    }

    final status = _callActive ? 'answered' : 'missed';
    widget.onCallEnded?.call(
      widget.isVideo ? 'video' : 'audio',
      status,
      _duration.inSeconds,
    );

    if (_joined) {
      await _engine.leaveChannel();
      await _engine.release();
    }

    _exit();
  }

  void _exit() {
    if (widget.onEnd != null) {
      widget.onEnd!();
    } else if (mounted) {
      Navigator.pop(context);
    }
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kSlate,
      body: SafeArea(
        child: GestureDetector(
          onTap: _showControls,
          behavior: HitTestBehavior.opaque,
          child: Stack(
            children: [
              // ── Main call stage ─────────────────────────────────────────────
              // Both audio and video use the same professional grid layout.
              // Audio tiles show avatars; video tiles show camera streams.
              Positioned.fill(
                child: _buildVideoGridArea(),
              ),

              // ── Gradient vignette ───────────────────────────────────────────
              Positioned.fill(child: IgnorePointer(child: _buildVignette())),

              // ── Top bar ─────────────────────────────────────────────────────
              Positioned(
                top: 12,
                left: 16,
                right: widget.onMinimize != null ? 64 : 16,
                child: _buildTopBar(),
              ),

              // ── Minimise button ─────────────────────────────────────────────
              if (widget.onMinimize != null)
                Positioned(
                  top: 16,
                  right: 16,
                  child: _MinimiseButton(onTap: widget.onMinimize!),
                ),

              // ── Bottom: participant strip + controls ─────────────────────────
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: FadeTransition(
                  opacity: _fadeAnim,
                  child: IgnorePointer(
                    ignoring: !_controlsVisible,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildParticipantStrip(),
                        const SizedBox(height: 8),
                        _buildControls(),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),
              ),

              // ── Floating Add User button ────────────────────────────────────
              Positioned(
                right: 20,
                bottom: 140,
                child: AnimatedOpacity(
                  opacity: _controlsVisible ? 1 : 0,
                  duration: const Duration(milliseconds: 220),
                  child: IgnorePointer(
                    ignoring: !_controlsVisible,
                    child: _buildAddUserFab(),
                  ),
                ),
              ),

              // ── Add-user inline panel (always on top of call UI) ────────────
              // Rendered as the last Stack child so it sits above all other
              // call-screen content.  Using showModalBottomSheet / showDialog
              // here would push a Navigator route which lands *below* this
              // OverlayEntry, making the list invisible.
              if (_showingAddUserPanel)
                Positioned.fill(child: _buildAddUserPanelOverlay()),

              // ── Participant-actions inline panel ────────────────────────────
              if (_showingParticipantActions &&
                  _pendingActionParticipant != null)
                Positioned.fill(
                  child: _buildParticipantActionsOverlay(
                    _pendingActionParticipant!,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Active speaker area ──────────────────────────────────────────────────

  Widget _buildActiveSpeakerArea() {
    final activeCandidates = _activeSpeakerId == null
        ? <_GParticipant>[]
        : _participants.where((p) => p.userId == _activeSpeakerId).toList();
    final active = activeCandidates.isNotEmpty ? activeCandidates.first : null;

    final bool isLocal = active?.userId == widget.adminId;
    final Widget videoContent;

    if (isLocal && !_videoEnabled) {
      videoContent = _buildAvatarView(active!);
    } else if (isLocal && _localVideoView != null) {
      videoContent = _localVideoView!;
    } else if (!isLocal &&
        active != null &&
        active.videoView != null &&
        !active.videoOff) {
      videoContent = active.videoView!;
    } else if (active != null) {
      videoContent = _buildAvatarView(active);
    } else {
      videoContent = _buildWaitingView();
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 380),
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: KeyedSubtree(
        key: ValueKey(_activeSpeakerId ?? 'none'),
        child: Stack(
          fit: StackFit.expand,
          children: [
            videoContent,
            // Speaking indicator ring
            if (active != null && active.isSpeaking)
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _speakingPulse,
                  builder: (_, __) {
                    final glow = 0.45 + (_speakingPulse.value * 0.55);
                    return IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: _kEmerald.withOpacity(0.45 + (0.45 * glow)),
                            width: 2.2 + (1.6 * glow),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: _kEmerald.withOpacity(0.22 + (0.3 * glow)),
                              blurRadius: 16 + (18 * glow),
                              spreadRadius: 0.4 + (1.4 * glow),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpeakingBadge(double glow, {required bool isVideoCall}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: _kEmerald.withOpacity(0.2 + (0.2 * glow)),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _kEmerald.withOpacity(0.5 + (0.35 * glow))),
        boxShadow: [
          BoxShadow(
            color: _kEmerald.withOpacity(0.2 + (0.28 * glow)),
            blurRadius: 8 + (10 * glow),
            spreadRadius: 0.4 + (1.2 * glow),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isVideoCall ? Icons.graphic_eq : Icons.multitrack_audio,
            size: 12,
            color: Colors.white,
          ),
          const SizedBox(width: 4),
          const Text(
            'Speaking',
            style: TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  _GParticipant _resolveMainVideoParticipant(List<_GParticipant> visible) {
    if (_pinnedUserId != null) {
      for (final p in visible) {
        if (p.userId == _pinnedUserId) return p;
      }
    }
    if (_activeSpeakerId != null) {
      for (final p in visible) {
        if (p.userId == _activeSpeakerId) return p;
      }
    }
    return visible.first;
  }

  Widget _buildThreeParticipantLayout(
    List<_GParticipant> visible, {
    required double gap,
    required bool compact,
  }) {
    _GParticipant? admin;
    for (final p in visible) {
      if (p.userId == widget.adminId) {
        admin = p;
        break;
      }
    }
    final _GParticipant adminParticipant =
        admin ?? _resolveMainVideoParticipant(visible);

    final others = visible
        .where((p) => p.userId != adminParticipant.userId)
        .toList();
    final _GParticipant left = others.isNotEmpty
        ? others.first
        : adminParticipant;
    final _GParticipant right = others.length > 1
        ? others[1]
        : adminParticipant;

    return LayoutBuilder(
      builder: (context, constraints) {
        final double maxRowHeight = compact ? 300 : 360;
        final double rowHeight = min(maxRowHeight, constraints.maxHeight);

        return Center(
          child: SizedBox(
            height: rowHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: AspectRatio(
                    aspectRatio: 9 / 16,
                    child: _buildVideoGridTile(
                      left,
                      onTap: () {
                        setState(() {
                          _pinnedUserId = left.userId;
                          _activeSpeakerId = left.userId;
                        });
                      },
                    ),
                  ),
                ),
                SizedBox(width: gap),
                Expanded(
                  child: AspectRatio(
                    aspectRatio: 9 / 16,
                    child: _buildVideoGridTile(
                      adminParticipant,
                      isPrimary: true,
                      onTap: () {
                        setState(() {
                          _pinnedUserId = adminParticipant.userId;
                          _activeSpeakerId = adminParticipant.userId;
                        });
                      },
                    ),
                  ),
                ),
                SizedBox(width: gap),
                Expanded(
                  child: AspectRatio(
                    aspectRatio: 9 / 16,
                    child: _buildVideoGridTile(
                      right,
                      onTap: () {
                        setState(() {
                          _pinnedUserId = right.userId;
                          _activeSpeakerId = right.userId;
                        });
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildVideoGridArea() {
    final visible = _participants;
    if (visible.isEmpty) return _buildWaitingView();

    final media = MediaQuery.of(context);
    final bool compact = media.size.height < 760;

    const double kSidePad = 12.0;
    const double kGap = 10.0;
    final double kTopPad = compact ? 64.0 : 74.0;
    // Keep stage inside safe area and avoid overlap with strip/controls.
    final double kBottomPad = _controlsVisible
        ? (compact ? 198.0 : 216.0)
        : (compact ? 34.0 : 42.0);

    // Dedicated 3-person layout: admin centered, others on left/right.
    if (visible.length == 3) {
      return Padding(
        padding: EdgeInsets.fromLTRB(kSidePad, kTopPad, kSidePad, kBottomPad),
        child: _buildThreeParticipantLayout(
          visible,
          gap: kGap,
          compact: compact,
        ),
      );
    }

    final mainParticipant = _resolveMainVideoParticipant(visible);
    final others = visible
        .where((p) => p.userId != mainParticipant.userId)
        .toList();

    final double thumbHeight;
    if (others.isEmpty) {
      thumbHeight = 0;
    } else if (others.length <= 2) {
      thumbHeight = compact ? 86 : 94;
    } else if (others.length <= 4) {
      thumbHeight = compact ? 98 : 108;
    } else {
      thumbHeight = compact ? 112 : 122;
    }
    final double thumbWidth = compact ? 132 : 148;

    return Padding(
      padding: EdgeInsets.fromLTRB(kSidePad, kTopPad, kSidePad, kBottomPad),
      child: Column(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.25),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: _buildVideoGridTile(
                mainParticipant,
                isPrimary: true,
                onTap: () {
                  setState(() {
                    if (_pinnedUserId == mainParticipant.userId) {
                      _pinnedUserId = null;
                    } else {
                      _pinnedUserId = mainParticipant.userId;
                    }
                    _activeSpeakerId = mainParticipant.userId;
                  });
                },
              ),
            ),
          ),
          if (others.isNotEmpty) const SizedBox(height: kGap),
          if (others.isNotEmpty)
            SizedBox(
              height: thumbHeight,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: others.length,
                separatorBuilder: (_, __) => const SizedBox(width: kGap),
                itemBuilder: (_, i) => SizedBox(
                  width: thumbWidth,
                  child: _buildVideoGridTile(
                    others[i],
                    onTap: () {
                      setState(() {
                        _pinnedUserId = others[i].userId;
                        _activeSpeakerId = others[i].userId;
                      });
                    },
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildVideoGridTile(
    _GParticipant p, {
    bool isPrimary = false,
    VoidCallback? onTap,
  }) {
    final bool isLocal = p.userId == widget.adminId;

    Widget videoLayer;
    bool showAvatarOverlay;

    if (!widget.isVideo) {
      // Audio-only call — always display avatar, never video surface.
      videoLayer = const SizedBox.shrink();
      showAvatarOverlay = true;
    } else if (isLocal) {
      if (_videoEnabled && _localVideoView != null) {
        videoLayer = _localVideoView!;
        showAvatarOverlay = false;
      } else {
        videoLayer = const SizedBox.shrink();
        showAvatarOverlay = true;
      }
    } else {
      if (p.videoView != null) {
        // Always keep AgoraVideoView in the widget tree — removing and
        // re-adding it breaks the HTML video element's stream on Flutter Web.
        videoLayer = p.videoView!;
        // Show avatar overlay only when camera is explicitly turned off.
        showAvatarOverlay = p.videoOff;
      } else {
        videoLayer = const SizedBox.shrink();
        showAvatarOverlay = true;
      }
    }

    final bool isPinned = _pinnedUserId == p.userId;
    final double borderRadius = isPrimary ? 18 : 12;
    final double avatarRadius = isPrimary ? 42 : 30;
    final double avatarFontSize = isPrimary ? 26 : 20;

    return AnimatedBuilder(
      animation: _speakingPulse,
      builder: (_, __) {
        final glow = 0.45 + (_speakingPulse.value * 0.55);
        final borderColor = isPinned
            ? _kPrimary.withOpacity(0.95)
            : (p.isSpeaking
                  ? _kEmerald.withOpacity(0.62 + (0.35 * glow))
                  : Colors.white.withOpacity(0.12));
        final double borderWidth = isPinned
            ? 2.6
            : (p.isSpeaking ? 2.2 + glow : 1.0);

        // Outer AnimatedContainer carries the border + speaking glow shadow.
        // ClipRRect is placed INSIDE so it only clips the content — not the
        // shadow.  If ClipRRect wrapped AnimatedContainer, the boxShadow
        // (which renders outside the box) would be clipped and invisible.
        return GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            clipBehavior: Clip.none,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(color: borderColor, width: borderWidth),
              boxShadow: [
                if (p.isSpeaking)
                  BoxShadow(
                    color: _kEmerald.withOpacity(0.2 + (0.32 * glow)),
                    blurRadius: 14 + (16 * glow),
                    spreadRadius: 0.6 + (1.4 * glow),
                  ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(borderRadius),
              child: ColoredBox(
                color: _kSlateDark,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Video surface — always present in tree when view exists.
                    videoLayer,
                    // Avatar shown on top when camera is off / audio call.
                    if (showAvatarOverlay)
                      Container(
                        color: _kSlateDark,
                        alignment: Alignment.center,
                        child: _buildAvatarWithGlow(
                          p,
                          radius: avatarRadius,
                          fontSize: avatarFontSize,
                          glow: glow,
                          speaking: p.isSpeaking,
                        ),
                      ),
                    if (p.isSpeaking)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: _buildSpeakingBadge(
                          glow,
                          isVideoCall: widget.isVideo,
                        ),
                      ),
                    Positioned(
                      left: 8,
                      right: 8,
                      bottom: 8,
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.55),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              p.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: isPrimary ? 12 : 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const Spacer(),
                          if (isPinned)
                            Container(
                              margin: const EdgeInsets.only(right: 6),
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.55),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.push_pin,
                                size: isPrimary ? 13 : 12,
                                color: _kPrimary,
                              ),
                            ),
                          if (p.micMuted)
                            Container(
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.55),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.mic_off,
                                size: 12,
                                color: _kAmber,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAvatarView(_GParticipant p) {
    final initial = p.displayName.isNotEmpty
        ? p.displayName[0].toUpperCase()
        : '?';
    return Container(
      color: _kSlateDark,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildAvatarCircle(p, radius: 52, fontSize: 30),
          const SizedBox(height: 16),
          Text(
            p.displayName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (p.micMuted) ...[
            const SizedBox(height: 8),
            const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.mic_off, color: _kAmber, size: 16),
                SizedBox(width: 4),
                Text('Muted', style: TextStyle(color: _kAmber, fontSize: 13)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Avatar circle wrapped in a green pulsing glow ring when [speaking].
  /// Used inside grid tiles (both audio and video-off mode).
  Widget _buildAvatarWithGlow(
    _GParticipant p, {
    required double radius,
    required double fontSize,
    required double glow,
    required bool speaking,
  }) {
    final avatar = _buildAvatarCircle(p, radius: radius, fontSize: fontSize);
    if (!speaking) return avatar;

    // Pulsing green ring + subtle outer glow around the avatar circle.
    final double ringWidth = 2.5 + (1.5 * glow);
    final double blurSigma = 6.0 + (10.0 * glow);
    final Color ringColor = _kEmerald.withOpacity(0.65 + (0.30 * glow));
    final Color glowColor = _kEmerald.withOpacity(0.18 + (0.28 * glow));

    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: ringColor, width: ringWidth),
        boxShadow: [
          BoxShadow(color: glowColor, blurRadius: blurSigma, spreadRadius: 2),
        ],
      ),
      child: avatar,
    );
  }

  Widget _buildWaitingView() {
    return Container(
      color: _kSlateDark,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.groups, color: Colors.white24, size: 80),
          const SizedBox(height: 16),
          Text(
            _participants.length > 1
                ? 'Waiting for participants…'
                : 'Starting group call…',
            style: const TextStyle(color: Colors.white54, fontSize: 16),
          ),
        ],
      ),
    );
  }

  // ─── Top bar ───────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    final peerCount = _participants.length; // includes local
    final duration = _callActive ? _formatDuration(_duration) : 'Connecting…';

    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.38),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: Colors.white.withOpacity(0.13)),
          ),
          child: Row(
            children: [
              const Icon(Icons.groups, color: _kPrimary, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Group Call',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '$peerCount participant${peerCount == 1 ? '' : 's'} · $duration',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              // Live / connecting badge
              _StatusBadge(active: _callActive),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Participant strip ────────────────────────────────────────────────────

  Widget _buildParticipantStrip() {
    if (_participants.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 100,
      child: ListView.separated(
        controller: _stripScrollCtrl,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _participants.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, idx) {
          final p = _participants[idx];
          return _StripParticipantTile(
            participant: p,
            isActive: p.userId == _activeSpeakerId,
            speakingPulse: _speakingPulse,
            onTap: () => setState(() => _activeSpeakerId = p.userId),
            onLongPress: p.userId == widget.adminId
                ? null
                : () => _showParticipantActions(p),
          );
        },
      ),
    );
  }

  void _showParticipantActions(_GParticipant p) {
    setState(() {
      _pendingActionParticipant = p;
      _showingParticipantActions = true;
    });
  }

  // ─── Controls bar ─────────────────────────────────────────────────────────

  Widget _buildControls() {
    final bool enabled = _callActive || !_ending;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.38),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: Colors.white.withOpacity(0.13)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Mic
                _ControlButton(
                  icon: _micMuted ? Icons.mic_off : Icons.mic,
                  onTap: enabled ? _toggleMic : null,
                  tint: _micMuted ? _kAmber : Colors.white,
                ),
                // Video
                if (widget.isVideo)
                  _ControlButton(
                    icon: _videoEnabled ? Icons.videocam : Icons.videocam_off,
                    onTap: enabled ? _toggleVideo : null,
                    tint: _videoEnabled ? Colors.white : _kAmber,
                  ),
                // Mute all (admin)
                _ControlButton(
                  icon: Icons.volume_off,
                  onTap: enabled ? _muteAll : null,
                  tint: Colors.white70,
                  tooltip: 'Mute all',
                ),
                // End call
                _ControlButton(
                  icon: Icons.call_end,
                  onTap: () => _endCall(),
                  tint: Colors.white,
                  background: _kRose,
                  size: 64,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Add user FAB ──────────────────────────────────────────────────────────

  Widget _buildAddUserFab() {
    return GestureDetector(
      onTap: _isLoadingAddUser ? null : _addUser,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: _isLoadingAddUser
                ? [_kPrimary.withOpacity(0.6), _kViolet.withOpacity(0.6)]
                : const [_kPrimary, _kViolet],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: _kPrimaryDark.withOpacity(0.45),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: _isLoadingAddUser
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
              )
            : const Icon(Icons.person_add_alt_1, color: Colors.white, size: 24),
      ),
    );
  }

  // ─── Vignette ─────────────────────────────────────────────────────────────

  Widget _buildVignette() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.black.withOpacity(0.25),
            Colors.transparent,
            Colors.black.withOpacity(0.6),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0.0, 0.45, 1.0],
        ),
      ),
    );
  }

  // ─── Avatar helper ─────────────────────────────────────────────────────────

  static Widget _buildAvatarCircle(
    _GParticipant p, {
    double radius = 26,
    double fontSize = 16,
  }) {
    final initial = p.displayName.isNotEmpty
        ? p.displayName[0].toUpperCase()
        : '?';
    return CircleAvatar(
      radius: radius,
      backgroundColor: _kPrimary.withOpacity(0.22),
      backgroundImage: (p.photoUrl != null && p.photoUrl!.isNotEmpty)
          ? NetworkImage(p.photoUrl!)
          : null,
      child: (p.photoUrl == null || p.photoUrl!.isEmpty)
          ? Text(
              initial,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: fontSize,
              ),
            )
          : null,
    );
  }

  // ─── Utilities ─────────────────────────────────────────────────────────────

  static String _formatDuration(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  // ─── Inline overlay panels ─────────────────────────────────────────────────
  //
  // Both panels are rendered as Positioned.fill children at the END of the
  // main Stack, guaranteeing they appear on top of every other call-screen
  // element.  Because this whole screen lives inside an OverlayEntry,
  // showModalBottomSheet / showDialog cannot be used — those push Navigator
  // routes that land below the OverlayEntry in the Flutter rendering tree.

  /// Full-screen dimmed backdrop + slide-up add-user sheet.
  Widget _buildAddUserPanelOverlay() {
    void close() => setState(() => _showingAddUserPanel = false);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 1.0, end: 0.0),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      builder: (_, t, __) {
        return Stack(
          children: [
            // Dimmed backdrop – tap to dismiss
            GestureDetector(
              onTap: close,
              behavior: HitTestBehavior.opaque,
              child: Container(color: Colors.black.withOpacity(0.65 * (1 - t))),
            ),
            // Slide-up panel
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Transform.translate(
                offset: Offset(
                  0,
                  MediaQuery.of(context).size.height * 0.35 * t,
                ),
                child: GestureDetector(
                  // Prevent backdrop-tap from propagating through the panel.
                  onTap: () {},
                  child: Material(
                    color: Colors.transparent,
                    child: _AddUserModal(
                      users: _addableUsers,
                      onSelected: _onAddUserConfirmed,
                      onClose: close,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Full-screen dimmed backdrop + slide-up participant-actions sheet.
  Widget _buildParticipantActionsOverlay(_GParticipant p) {
    void close() => setState(() {
      _showingParticipantActions = false;
      _pendingActionParticipant = null;
    });
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 1.0, end: 0.0),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
      builder: (_, t, __) {
        return Stack(
          children: [
            // Dimmed backdrop – tap to dismiss
            GestureDetector(
              onTap: close,
              behavior: HitTestBehavior.opaque,
              child: Container(color: Colors.black.withOpacity(0.65 * (1 - t))),
            ),
            // Slide-up actions panel
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Transform.translate(
                offset: Offset(
                  0,
                  MediaQuery.of(context).size.height * 0.25 * t,
                ),
                child: GestureDetector(
                  onTap: () {},
                  child: Material(
                    color: Colors.transparent,
                    child: SafeArea(
                      top: false,
                      child: Container(
                        decoration: BoxDecoration(
                          color: _kSlateDark,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(22),
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Drag handle
                            Container(
                              width: 38,
                              height: 4,
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: Colors.white24,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            ListTile(
                              leading: const Icon(
                                Icons.person,
                                color: Colors.white70,
                              ),
                              title: Text(
                                p.displayName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                p.agoraUid != null ? 'In call' : 'Invited',
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            const Divider(color: Colors.white12),
                            ListTile(
                              leading: Icon(
                                p.micMuted ? Icons.mic : Icons.mic_off,
                                color: _kAmber,
                              ),
                              title: Text(
                                p.micMuted ? 'Unmute' : 'Mute',
                                style: const TextStyle(color: Colors.white),
                              ),
                              onTap: () {
                                close();
                                _muteParticipant(p);
                              },
                            ),
                            ListTile(
                              leading: const Icon(
                                Icons.person_remove,
                                color: _kRose,
                              ),
                              title: const Text(
                                'Remove from call',
                                style: TextStyle(color: _kRose),
                              ),
                              onTap: () {
                                close();
                                _removeParticipant(p);
                              },
                            ),
                            const SizedBox(height: 8),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _callTimer?.cancel();
    _controlsHideTimer?.cancel();
    _speakingHoldTimer?.cancel();
    _fadeCtrls.dispose();
    _speakingPulseCtrl.dispose();
    _stripScrollCtrl.dispose();
    _participantAcceptedSub?.cancel();
    _participantRejectedSub?.cancel();
    _participantLeftSub?.cancel();
    _callEndedSub?.cancel();
    _ringtoneRepeatTimer?.cancel();
    _ringtoneStateSubscription?.cancel();
    _ringtonePlayer.dispose();
    super.dispose();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Strip participant tile
// ─────────────────────────────────────────────────────────────────────────────

class _StripParticipantTile extends StatelessWidget {
  final _GParticipant participant;
  final bool isActive;
  final Animation<double> speakingPulse;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const _StripParticipantTile({
    required this.participant,
    required this.isActive,
    required this.speakingPulse,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final p = participant;
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        width: 72,
        decoration: BoxDecoration(
          color: isActive
              ? _kPrimary.withOpacity(0.25)
              : Colors.black.withOpacity(0.35),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive ? _kPrimary : Colors.white.withOpacity(0.12),
            width: isActive ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                _GroupCallScreenState._buildAvatarCircle(
                  p,
                  radius: 22,
                  fontSize: 14,
                ),
                // Speaking ring
                if (p.isSpeaking)
                  AnimatedBuilder(
                    animation: speakingPulse,
                    builder: (_, __) {
                      final glow = 0.45 + (speakingPulse.value * 0.55);
                      return Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _kEmerald.withOpacity(0.52 + (0.36 * glow)),
                            width: 2 + (1.8 * glow),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: _kEmerald.withOpacity(0.2 + (0.25 * glow)),
                              blurRadius: 8 + (9 * glow),
                              spreadRadius: 0.2 + (1.0 * glow),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                // Mute indicator
                if (p.micMuted)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: _kAmber,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.mic_off,
                        size: 9,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              p.displayName.length > 8
                  ? '${p.displayName.substring(0, 8)}…'
                  : p.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isActive ? Colors.white : Colors.white70,
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Control button
// ─────────────────────────────────────────────────────────────────────────────

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final Color? tint;
  final Color? background;
  final double size;
  final String? tooltip;

  const _ControlButton({
    required this.icon,
    this.onTap,
    this.tint,
    this.background,
    this.size = 54,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final bool enabled = onTap != null;
    final Color bg =
        background ??
        (enabled
            ? Colors.black.withOpacity(0.38)
            : Colors.black.withOpacity(0.2));
    final Color iconColor = (tint ?? Colors.white).withOpacity(
      enabled ? 1.0 : 0.4,
    );

    final child = SizedBox(
      width: size,
      height: size,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(size / 2),
          side: BorderSide(
            color: Colors.white.withOpacity(enabled ? 0.16 : 0.07),
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(size / 2),
          child: Icon(icon, color: iconColor, size: size * 0.44),
        ),
      ),
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: child);
    }
    return child;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Status badge (Live / Connecting)
// ─────────────────────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final bool active;
  const _StatusBadge({required this.active});

  @override
  Widget build(BuildContext context) {
    final color = active ? _kEmerald : _kAmber;
    final label = active ? 'Live' : 'Connecting';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.18),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Minimise button
// ─────────────────────────────────────────────────────────────────────────────

class _MinimiseButton extends StatelessWidget {
  final VoidCallback onTap;
  const _MinimiseButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.4),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withOpacity(0.18)),
        ),
        alignment: Alignment.center,
        child: const Icon(
          Icons.picture_in_picture_alt,
          color: Colors.white70,
          size: 20,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Add User Modal
//  Shows online users first. Displays first name only (privacy).
//
//  Uses callbacks (onSelected / onClose) instead of Navigator.pop so that it
//  can be embedded directly inside the call-screen Stack without needing to
//  push a Navigator route (which would appear *behind* the OverlayEntry).
// ─────────────────────────────────────────────────────────────────────────────

class _AddUserModal extends StatefulWidget {
  final List<Map<String, dynamic>> users;
  final void Function(Map<String, String> selected) onSelected;
  final VoidCallback onClose;

  const _AddUserModal({
    required this.users,
    required this.onSelected,
    required this.onClose,
  });

  @override
  State<_AddUserModal> createState() => _AddUserModalState();
}

class _AddUserModalState extends State<_AddUserModal> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String _displayName(Map<String, dynamic> u) {
    final fn = (u['_firstName'] ?? u['firstName'] ?? '').toString().trim();
    if (fn.isNotEmpty) return fn;
    final full = (u['_fullName'] ?? u['name'] ?? '').toString().trim();
    return full.split(' ').first.isNotEmpty ? full.split(' ').first : 'User';
  }

  bool _isOnline(Map<String, dynamic> u) =>
      u['_isOnline'] == true || u['isOnline'] == 1 || u['isOnline'] == '1';

  String _lastSeenLabel(Map<String, dynamic> u) {
    final lastSeen = u['_lastSeen'] as DateTime?;
    if (lastSeen == null) return '';
    final now = DateTime.now().toUtc();
    final diff = now.difference(lastSeen.toUtc());
    if (diff.inSeconds < 60) return 'Last seen just now';
    if (diff.inMinutes < 60) return 'Last seen ${diff.inMinutes} min ago';
    if (diff.inHours < 24) return 'Last seen ${diff.inHours} hr ago';
    return 'Last seen ${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
  }

  List<Map<String, dynamic>> get _filtered {
    if (_query.isEmpty) return widget.users;
    final q = _query.toLowerCase();
    return widget.users
        .where((u) => _displayName(u).toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      constraints: BoxConstraints(maxHeight: screenHeight * 0.85),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Drag handle ──────────────────────────────────────────────────
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // ── Header ──────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 8, 16),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [_kPrimary, _kViolet],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.person_add_alt_1,
                  color: Colors.white,
                  size: 26,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Add to Group Call',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Only online users shown',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: widget.onClose,
                ),
              ],
            ),
          ),

          // ── Search ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: TextField(
              controller: _search,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Search by name…',
                prefixIcon: const Icon(Icons.search, size: 20),
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 16,
                ),
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _search.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),

          // ── User list ────────────────────────────────────────────────────
          Flexible(
            child: filtered.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.search_off,
                          size: 52,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _query.isEmpty
                              ? 'No online users available'
                              : 'No online users match "$_query"',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, indent: 72),
                    itemBuilder: (_, idx) {
                      final u = filtered[idx];
                      final userId = u['id']?.toString() ?? '';
                      final name = _displayName(u);
                      final photo = u['profile_picture']?.toString();
                      final online = _isOnline(u);
                      final lastSeenLabel = online ? '' : _lastSeenLabel(u);
                      final initial = name.isNotEmpty
                          ? name[0].toUpperCase()
                          : '?';

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        leading: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            CircleAvatar(
                              radius: 24,
                              backgroundColor: _kPrimary.withOpacity(0.15),
                              backgroundImage:
                                  (photo != null && photo.isNotEmpty)
                                  ? NetworkImage(photo)
                                  : null,
                              child: (photo == null || photo.isEmpty)
                                  ? Text(
                                      initial,
                                      style: const TextStyle(
                                        color: _kPrimary,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 16,
                                      ),
                                    )
                                  : null,
                            ),
                            if (online)
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: Container(
                                  width: 11,
                                  height: 11,
                                  decoration: BoxDecoration(
                                    color: _kEmerald,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 2,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        title: Text(
                          name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              online ? 'Online' : 'Offline',
                              style: TextStyle(
                                color: online
                                    ? _kEmerald
                                    : Colors.grey.shade400,
                                fontSize: 12,
                              ),
                            ),
                            if (!online && lastSeenLabel.isNotEmpty)
                              Text(
                                lastSeenLabel,
                                style: TextStyle(
                                  color: Colors.grey.shade500,
                                  fontSize: 11,
                                ),
                              ),
                          ],
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: _kPrimary.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'Add',
                            style: TextStyle(
                              color: _kPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        onTap: () => widget.onSelected({
                          'id': userId,
                          'name': name,
                          'photoUrl': photo ?? '',
                        }),
                      );
                    },
                  ),
          ),
          // ── Safe area padding at the bottom ──────────────────────────────
          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ],
      ),
    );
  }
}
