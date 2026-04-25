import 'dart:async' show StreamSubscription, Timer, unawaited;
import 'dart:math';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:permission_handler/permission_handler.dart'
    if (dart.library.html) 'package:ms2026/utils/web_permission_stub.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../service/socket_service.dart';
import 'tokengenerator.dart';
import 'call_history_model.dart';
import 'call_history_service.dart';
import 'call_foreground_service.dart';
import '../Chat/call_overlay_manager.dart';
import '../pushnotification/pushservice.dart';

/// Status of a participant in the group call.
enum _ParticipantStatus { inviting, ringing, joined, declined, missed, left }

/// Per-participant state.
class _ParticipantState {
  final String userId;
  final String userName;
  final String userImage;
  _ParticipantStatus status;

  _ParticipantState({
    required this.userId,
    required this.userName,
    required this.userImage,
    this.status = _ParticipantStatus.inviting,
  });
}

/// Group audio call screen.
///
/// The initiator joins an Agora channel and sends [call_invite] socket events
/// to every selected participant.  Participants receive a standard
/// [IncomingCallScreen] and, when they accept, join the same Agora channel.
/// Agora handles audio mixing for all parties automatically.
class GroupCallScreen extends StatefulWidget {
  final String currentUserId;
  final String currentUserName;
  final String currentUserImage;

  /// Pre-generated channel name for this group call.
  final String channelName;

  /// List of users to invite.  Each map must contain at minimum:
  ///   'userId', 'userName', 'userImage'
  final List<Map<String, dynamic>> participants;

  const GroupCallScreen({
    super.key,
    required this.currentUserId,
    required this.currentUserName,
    required this.currentUserImage,
    required this.channelName,
    required this.participants,
  });

  @override
  State<GroupCallScreen> createState() => _GroupCallScreenState();
}

class _GroupCallScreenState extends State<GroupCallScreen>
    with WidgetsBindingObserver {
  late RtcEngine _engine;
  bool _engineInitialized = false;

  int _localUid = 0;

  bool _joined = false;
  bool _micMuted = false;
  bool _speakerOn = false;
  bool _ending = false;
  bool _foregroundServiceStarted = false;

  Timer? _callTimer;
  Duration _duration = Duration.zero;
  bool _callActive = false; // true once at least one participant joins

  String? _callHistoryId;

  // Connected remote Agora UIDs
  final Set<int> _remoteUids = {};

  // Per-participant state (indexed by userId)
  late List<_ParticipantState> _participantStates;

  // Socket subscriptions
  StreamSubscription<Map<String, dynamic>>? _callAcceptedSub;
  StreamSubscription<Map<String, dynamic>>? _callRejectedSub;
  StreamSubscription<Map<String, dynamic>>? _callEndedSub;
  StreamSubscription<Map<String, dynamic>>? _callRingingSub;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    WidgetsBinding.instance.addObserver(this);

    _localUid = Random().nextInt(999998) + 1;

    _participantStates = widget.participants.map((p) {
      return _ParticipantState(
        userId: p['userId']?.toString() ?? '',
        userName: p['userName']?.toString() ?? 'User',
        userImage: p['userImage']?.toString() ?? '',
      );
    }).toList();

    _initAgoraAndStartCall();
  }

  // ── Agora init ────────────────────────────────────────────────────────────

  Future<void> _initAgoraAndStartCall() async {
    if (!kIsWeb) {
      await _requestPermissions();
    }
    await _initAgoraEngine();
    await _joinChannel();
    await _logCallToHistory();
    _inviteParticipants();
    _listenSocketEvents();
    _startForegroundService();
  }

  Future<void> _requestPermissions() async {
    await [Permission.microphone].request();
  }

  Future<void> _initAgoraEngine() async {
    _engine = createAgoraRtcEngine();
    await _engine.initialize(const RtcEngineContext(
      appId: AgoraTokenService.appId,
      channelProfile: ChannelProfileType.channelProfileCommunication,
    ));

    _engine.registerEventHandler(RtcEngineEventHandler(
      onJoinChannelSuccess: (connection, elapsed) {
        debugPrint('[GroupCall] Joined channel: ${connection.channelId}');
        if (mounted) setState(() => _joined = true);
      },
      onUserJoined: (connection, remoteUid, elapsed) {
        debugPrint('[GroupCall] User joined: $remoteUid');
        if (mounted) {
          setState(() {
            _remoteUids.add(remoteUid);
            if (!_callActive) {
              _callActive = true;
              _startCallTimer();
            }
          });
        }
        // Register with overlay
        CallOverlayManager().startCall(
          callType: 'group',
          otherUserName: _buildParticipantNames(),
          otherUserId: widget.participants.isNotEmpty
              ? widget.participants.first['userId']?.toString() ?? ''
              : '',
          currentUserId: widget.currentUserId,
          currentUserName: widget.currentUserName,
          onMaximize: () {
            // Already on screen
          },
          onEnd: _endCall,
        );
      },
      onUserOffline: (connection, remoteUid, reason) {
        debugPrint('[GroupCall] User offline: $remoteUid, reason: $reason');
        if (mounted) {
          setState(() {
            _remoteUids.remove(remoteUid);
            if (_remoteUids.isEmpty) {
              // All participants left
              _endCall();
            }
          });
        }
      },
      onError: (err, msg) {
        debugPrint('[GroupCall] Agora error: $err - $msg');
      },
    ));

    _engineInitialized = true;
  }

  Future<void> _joinChannel() async {
    try {
      final token = await AgoraTokenService.getToken(
        channelName: widget.channelName,
        uid: _localUid,
      );

      await _engine.setDefaultAudioRouteToSpeakerphone(_speakerOn);

      await _engine.joinChannel(
        token: token,
        channelId: widget.channelName,
        uid: _localUid,
        options: const ChannelMediaOptions(
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          channelProfile: ChannelProfileType.channelProfileCommunication,
        ),
      );
    } catch (e) {
      debugPrint('[GroupCall] Error joining channel: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start group call: $e')),
        );
        Navigator.of(context).pop();
      }
    }
  }

  // ── Call history ─────────────────────────────────────────────────────────

  Future<void> _logCallToHistory() async {
    try {
      final participantIds = widget.participants
          .map((p) => p['userId']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();

      final allParticipants = [widget.currentUserId, ...participantIds];

      // Use first participant as nominal "recipient" for DB schema compatibility
      final firstParticipant = widget.participants.isNotEmpty
          ? widget.participants.first
          : <String, dynamic>{};

      final callId = await CallHistoryService.logCall(
        callerId: widget.currentUserId,
        callerName: widget.currentUserName,
        callerImage: widget.currentUserImage,
        recipientId: firstParticipant['userId']?.toString() ?? '',
        recipientName: firstParticipant['userName']?.toString() ?? '',
        recipientImage: firstParticipant['userImage']?.toString() ?? '',
        callType: CallType.group,
        initiatedBy: widget.currentUserId,
        roomId: widget.channelName,
        participants: allParticipants,
      );

      if (mounted) setState(() => _callHistoryId = callId);
    } catch (e) {
      debugPrint('[GroupCall] Error logging call: $e');
    }
  }

  // ── Invite participants ───────────────────────────────────────────────────

  void _inviteParticipants() {
    final socketService = SocketService();
    for (final p in _participantStates) {
      if (p.userId.isEmpty) continue;

      socketService.emitCallInvite(
        recipientId: p.userId,
        callerId: widget.currentUserId,
        callerName: widget.currentUserName,
        callerImage: widget.currentUserImage,
        channelName: widget.channelName,
        callerUid: _localUid.toString(),
        callType: 'group',
      );

      // Send FCM push as fallback for offline participants.
      // 'SERVER_ONLY' is an intentional placeholder — the actual Agora certificate
      // is not sent to the client; the server generates the token server-side.
      unawaited(NotificationService.sendCallNotification(
        recipientUserId: p.userId,
        callerName: widget.currentUserName,
        channelName: widget.channelName,
        callerId: widget.currentUserId,
        callerUid: _localUid.toString(),
        agoraAppId: AgoraTokenService.appId,
        agoraCertificate: 'SERVER_ONLY',
      ));
    }
  }

  // ── Socket listeners ──────────────────────────────────────────────────────

  void _listenSocketEvents() {
    final socketService = SocketService();

    _callRingingSub = socketService.onCallRinging.listen((data) {
      final channel = data['channelName']?.toString();
      if (channel != widget.channelName) return;
      final recipientId = data['recipientId']?.toString() ?? '';
      _updateParticipantStatus(recipientId, _ParticipantStatus.ringing);
    });

    _callAcceptedSub = socketService.onCallAccepted.listen((data) {
      final channel = data['channelName']?.toString();
      if (channel != null && channel != widget.channelName) return;
      final recipientId = data['recipientId']?.toString() ?? '';
      _updateParticipantStatus(recipientId, _ParticipantStatus.joined);
    });

    _callRejectedSub = socketService.onCallRejected.listen((data) {
      final channel = data['channelName']?.toString();
      if (channel != null && channel != widget.channelName) return;
      final recipientId = data['recipientId']?.toString() ?? '';
      _updateParticipantStatus(recipientId, _ParticipantStatus.declined);
    });

    _callEndedSub = socketService.onCallEnded.listen((data) {
      final channel = data['channelName']?.toString();
      if (channel != null && channel != widget.channelName) return;
      if (!_ending) _endCall();
    });
  }

  void _updateParticipantStatus(String userId, _ParticipantStatus status) {
    if (userId.isEmpty || !mounted) return;
    setState(() {
      for (final p in _participantStates) {
        if (p.userId == userId) {
          p.status = status;
          break;
        }
      }
    });
  }

  // ── Foreground service ────────────────────────────────────────────────────

  Future<void> _startForegroundService() async {
    if (kIsWeb || _foregroundServiceStarted) return;
    try {
      await CallForegroundServiceManager.startOngoingCall(
        callType: 'audio',
        otherUserName: 'Group Call',
        callId: widget.channelName,
      );
      _foregroundServiceStarted = true;
    } catch (e) {
      debugPrint('[GroupCall] Foreground service error: $e');
    }
  }

  Future<void> _stopForegroundService() async {
    if (kIsWeb || !_foregroundServiceStarted) return;
    try {
      await CallForegroundServiceManager.stopCallService();
      _foregroundServiceStarted = false;
    } catch (e) {
      debugPrint('[GroupCall] Foreground service stop error: $e');
    }
  }

  // ── Timer ─────────────────────────────────────────────────────────────────

  void _startCallTimer() {
    _callTimer?.cancel();
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _duration += const Duration(seconds: 1));
      CallOverlayManager().updateCallState(
        statusText: 'Connected',
        duration: _duration,
      );
    });
  }

  // ── Controls ──────────────────────────────────────────────────────────────

  void _toggleMic() {
    _micMuted = !_micMuted;
    _engine.muteLocalAudioStream(_micMuted);
    if (mounted) setState(() {});
  }

  void _toggleSpeaker() {
    _speakerOn = !_speakerOn;
    _engine.setDefaultAudioRouteToSpeakerphone(_speakerOn);
    if (mounted) setState(() {});
  }

  // ── End call ──────────────────────────────────────────────────────────────

  Future<void> _endCall() async {
    if (_ending) return;
    _ending = true;

    _callTimer?.cancel();
    _callAcceptedSub?.cancel();
    _callRejectedSub?.cancel();
    _callEndedSub?.cancel();
    _callRingingSub?.cancel();

    // Notify all participants the call has ended
    final socketService = SocketService();
    for (final p in _participantStates) {
      if (p.userId.isEmpty) continue;
      socketService.emitCallEnd(
        callerId: widget.currentUserId,
        recipientId: p.userId,
        channelName: widget.channelName,
        callType: 'group',
        duration: _duration.inSeconds,
      );
    }

    // Update call history
    if (_callHistoryId != null && _callHistoryId!.isNotEmpty) {
      await CallHistoryService.updateCallEnd(
        callId: _callHistoryId!,
        status: _callActive ? CallStatus.ended : CallStatus.cancelled,
        duration: _duration.inSeconds,
        endedBy: widget.currentUserId,
      );
    }

    if (_engineInitialized) {
      await _engine.leaveChannel();
      await _engine.release();
      _engineInitialized = false;
    }

    await _stopForegroundService();
    CallOverlayManager().reset();
    WakelockPlus.disable();

    if (mounted) Navigator.of(context).pop();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _buildParticipantNames() {
    final names = _participantStates.map((p) => p.userName).toList();
    if (names.isEmpty) return 'Group Call';
    if (names.length == 1) return names.first;
    if (names.length == 2) return '${names[0]} & ${names[1]}';
    return '${names[0]}, ${names[1]} +${names.length - 2}';
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && _joined && !_ending) {
      CallOverlayManager().minimizeCall();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _callTimer?.cancel();
    _callAcceptedSub?.cancel();
    _callRejectedSub?.cancel();
    _callEndedSub?.cancel();
    _callRingingSub?.cancel();
    if (_engineInitialized) {
      _engine.leaveChannel();
      _engine.release();
    }
    WakelockPlus.disable();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) _endCall();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF1A1A2E),
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(child: _buildParticipantList()),
              _buildControls(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Column(
        children: [
          // Group icon
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFF7C4DFF), Color(0xFF00C6FF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF7C4DFF).withOpacity(0.4),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(
              Icons.group_rounded,
              color: Colors.white,
              size: 40,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Group Call',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _callActive
                ? _formatDuration(_duration)
                : (_joined ? 'Waiting for participants...' : 'Connecting...'),
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 15,
            ),
          ),
          if (_remoteUids.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '${_remoteUids.length} participant${_remoteUids.length == 1 ? '' : 's'} connected',
              style: const TextStyle(
                color: Color(0xFF52E5A3),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildParticipantList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _participantStates.length,
      itemBuilder: (context, index) {
        final p = _participantStates[index];
        return _ParticipantTile(participant: p);
      },
    );
  }

  Widget _buildControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ControlButton(
            icon: _micMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
            label: _micMuted ? 'Unmute' : 'Mute',
            color: _micMuted
                ? const Color(0xFFFFB703)
                : const Color(0xFF5D9CEC),
            onPressed: _toggleMic,
          ),
          _EndCallButton(onPressed: _endCall),
          _ControlButton(
            icon: _speakerOn
                ? Icons.volume_up_rounded
                : Icons.volume_off_rounded,
            label: _speakerOn ? 'Speaker' : 'Earpiece',
            color: _speakerOn
                ? const Color(0xFF52E5A3)
                : const Color(0xFF9E9E9E),
            onPressed: _toggleSpeaker,
          ),
        ],
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _ParticipantTile extends StatelessWidget {
  final _ParticipantState participant;

  const _ParticipantTile({required this.participant});

  @override
  Widget build(BuildContext context) {
    final (statusIcon, statusColor, statusLabel) =
        _statusDetails(participant.status);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundImage: participant.userImage.isNotEmpty
                ? NetworkImage(participant.userImage)
                : null,
            backgroundColor: const Color(0xFF7C4DFF).withOpacity(0.3),
            child: participant.userImage.isEmpty
                ? Text(
                    participant.userName.isNotEmpty
                        ? participant.userName[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  participant.userName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(statusIcon, size: 13, color: statusColor),
                    const SizedBox(width: 4),
                    Text(
                      statusLabel,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
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

  (IconData, Color, String) _statusDetails(_ParticipantStatus status) {
    switch (status) {
      case _ParticipantStatus.inviting:
        return (Icons.send_rounded, Colors.grey, 'Inviting...');
      case _ParticipantStatus.ringing:
        return (Icons.notifications_active_rounded,
            const Color(0xFFFFD166), 'Ringing...');
      case _ParticipantStatus.joined:
        return (Icons.fiber_manual_record_rounded,
            const Color(0xFF52E5A3), 'Connected');
      case _ParticipantStatus.declined:
        return (Icons.call_end_rounded, Colors.redAccent, 'Declined');
      case _ParticipantStatus.missed:
        return (Icons.call_missed_rounded, Colors.orange, 'Missed');
      case _ParticipantStatus.left:
        return (Icons.logout_rounded, Colors.grey, 'Left');
    }
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              shape: BoxShape.circle,
              border: Border.all(color: color.withOpacity(0.4), width: 1.5),
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.75),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _EndCallButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _EndCallButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFF5A5F), Color(0xFFFF0844)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF5A5F).withOpacity(0.4),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Icon(
              Icons.call_end_rounded,
              color: Colors.white,
              size: 30,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'End',
            style: TextStyle(
              color: Colors.white.withOpacity(0.75),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
