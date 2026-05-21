import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'tokengenerator.dart';
import 'package:permission_handler/permission_handler.dart'
    if (dart.library.html) 'package:ms2026/utils/web_permission_stub.dart';
import '../Chat/call_overlay_manager.dart';
import '../navigation/app_navigation.dart';
import 'call_foreground_service.dart';
import 'widgets/connection_status_overlay.dart';
import '../service/socket_service.dart';
import '../pushnotification/pushservice.dart';

class ActiveCallScreen extends StatefulWidget {
  final String channel;
  final int localUid;
  final int remoteUid;
  final String currentUserId;
  final String otherUserId;
  final String callerName;
  final String recipientName;

  const ActiveCallScreen({
    super.key,
    required this.channel,
    required this.localUid,
    required this.remoteUid,
    required this.currentUserId,
    required this.otherUserId,
    required this.callerName,
    required this.recipientName,
  });

  @override
  State<ActiveCallScreen> createState() => _ActiveCallScreenState();
}

class _ActiveCallScreenState extends State<ActiveCallScreen> {
  late RtcEngine _engine;
  bool _engineInitialized = false;
  bool _joined = false;
  bool _micMuted = false;
  bool _speakerOn = false;
  bool _foregroundServiceStarted = false;
  bool _ending = false;
  Timer? _callTimer;
  Duration _duration = Duration.zero;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  StreamSubscription<Map<String, dynamic>>? _socketEndedSub;
  StreamSubscription<Map<String, dynamic>>? _socketCancelledSub;
  StreamSubscription<Map<String, dynamic>>? _callResponseSub;
  String? _connectionStatus;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _initEngine();
    _startCallTimer();
    _initializeOverlay();
    _listenConnectivity();
    _listenForRemoteEnd();
  }

  void _listenForRemoteEnd() {
    _socketEndedSub = SocketService().onCallEnded.listen((data) {
      final channelName = data['channelName']?.toString() ?? '';
      if (channelName.isNotEmpty && channelName != widget.channel) return;
      if (!_ending) {
        unawaited(_endCall());
      }
    });

    _socketCancelledSub = SocketService().onCallCancelled.listen((data) {
      final channelName = data['channelName']?.toString() ?? '';
      if (channelName.isNotEmpty && channelName != widget.channel) return;
      if (!_ending) {
        unawaited(_endCall());
      }
    });

    _callResponseSub = NotificationService.callResponses.listen((data) {
      final type = data['type']?.toString() ?? '';
      const endTypes = {
        'call_ended',
        'video_call_ended',
        'call_cancelled',
        'video_call_cancelled',
      };
      if (!endTypes.contains(type)) return;
      final channelName = data['channelName']?.toString() ?? '';
      if (channelName.isNotEmpty && channelName != widget.channel) return;
      if (!_ending) {
        unawaited(_endCall());
      }
    });
  }

  void _initializeOverlay() {
    CallOverlayManager().startCall(
      callType: 'audio',
      otherUserName: widget.recipientName,
      otherUserId: widget.otherUserId,
      currentUserId: widget.currentUserId,
      currentUserName: widget.callerName,
      onMaximize: () {
        navigatorKey.currentState?.popUntil(
          (route) =>
              route.settings.name == activeCallRouteName || route.isFirst,
        );
      },
      onEnd: _endCall,
      onToggleMute: _toggleMute,
      isMicMuted: _micMuted,
    );
    _syncOverlayState();
  }

  void _syncOverlayState() {
    final statusText = _joined ? 'Connected' : 'Connecting...';
    CallOverlayManager().updateCallState(
      statusText: statusText,
      duration: _duration,
      isMicMuted: _micMuted,
    );
  }

  Future<void> _minimizeCall() async {
    await openMinimizedCallHost(context);
  }

  Future<void> _toggleMute() async {
    setState(() => _micMuted = !_micMuted);
    if (_engineInitialized) {
      await _engine.muteLocalAudioStream(_micMuted);
    }
    _syncOverlayState();
  }

  Future<void> _initEngine() async {
    try {
      // Check microphone permission
      if (!(await Permission.microphone.request()).isGranted) {
        debugPrint('❌ No mic permission');
        _endCall();
        return;
      }

      // Create Agora engine
      _engine = createAgoraRtcEngine();
      await _engine.initialize(RtcEngineContext(
        appId: AgoraTokenService.appId,
        channelProfile: ChannelProfileType.channelProfileCommunication,
      ));
      _engineInitialized = true;

      // Event handlers
      _engine.registerEventHandler(RtcEngineEventHandler(
        onJoinChannelSuccess: (conn, elapsed) {
          debugPrint('✅ Active call joined');
          if (mounted) setState(() => _joined = true);
          _syncOverlayState();
          unawaited(_startForegroundService());
        },
        onUserOffline: (conn, remoteUid, reason) {
          debugPrint('👋 Remote user left');
          _endCall();
        },
        onError: (err, msg) {
          debugPrint('❌ Active call error: $err - $msg');
          if (_isFatalAgoraError(err, msg)) {
            _endCall();
            return;
          }
          if (mounted) {
            setState(() => _connectionStatus = 'Reconnecting...');
          }
        },
        onConnectionStateChanged: (connection, state, reason) {
          debugPrint('🔌 Active call state: $state, reason: $reason');
          if (!mounted) return;
          if (state == ConnectionStateType.connectionStateConnected) {
            setState(() => _connectionStatus = null);
          } else if (state == ConnectionStateType.connectionStateReconnecting) {
            setState(() => _connectionStatus = 'Reconnecting...');
          } else if (state == ConnectionStateType.connectionStateFailed) {
            _endCall();
          }
        },
      ));

      // Enable audio
      await _engine.enableAudio();
      // Start with earpiece route; user can switch to loudspeaker manually.
      await _engine.setEnableSpeakerphone(_speakerOn);
      await _engine.setClientRole(role: ClientRoleType.clientRoleBroadcaster);

      // Fetch token from your server
      final token = await AgoraTokenService.getToken(
        channelName: widget.channel,
        uid: widget.localUid,
        userId: widget.currentUserId,
        callType: 'audio',
      );
      debugPrint('🔑 Token received: ${token.substring(0, 20)}...');

      // Join channel with token
      await _engine.joinChannel(
        token: token,
        channelId: widget.channel,
        uid: widget.localUid,
        options: const ChannelMediaOptions(
          autoSubscribeAudio: true,
          publishMicrophoneTrack: true,
        ),
      );
    } catch (e) {
      debugPrint('❌ Init engine error: $e');
      _endCall();
    }
  }

  bool _isFatalAgoraError(ErrorCodeType code, String message) {
    final msg = message.toLowerCase();
    final codeText = code.toString().toLowerCase();
    // Authentication/channel errors are unrecoverable without new credentials.
    return msg.contains('token') ||
        msg.contains('invalid') ||
        msg.contains('expired') ||
        codeText.contains('token') ||
        codeText.contains('invalid') ||
        codeText.contains('expired') ||
        codeText.contains('rejected');
  }

  void _startCallTimer() {
    _callTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() => _duration += const Duration(seconds: 1));
        _syncOverlayState();
      }
    });
  }

  Future<void> _endCall() async {
    if (_ending) return;
    _ending = true;
    _callTimer?.cancel();
    _socketEndedSub?.cancel();
    _socketCancelledSub?.cancel();
    _callResponseSub?.cancel();

    // Navigate away FIRST so the user never sees stale connected UI.
    CallOverlayManager().reset();
    _dismissCallRoutes();

    // Release engine resources after navigation (fire-and-forget)
    if (_engineInitialized) unawaited(_releaseEngineAsync());
    unawaited(_stopForegroundService());
  }

  void _dismissCallRoutes() {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;
    if (navigator.canPop()) {
      navigator.pop();
    }
    navigator.popUntil((route) {
      final name = route.settings.name;
      final isCallRoute =
          name == activeCallRouteName || name == minimizedCallHostRouteName;
      return route.isFirst || !isCallRoute;
    });
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _callTimer?.cancel();
    _connectivitySubscription?.cancel();
    _socketEndedSub?.cancel();
    _socketCancelledSub?.cancel();
    _callResponseSub?.cancel();
    // Release Agora engine if not already released by _endCall
    if (_engineInitialized) {
      unawaited(_releaseEngineAsync());
    }
    unawaited(_stopForegroundService());
    super.dispose();
  }

  /// Releases the Agora engine; safe to call fire-and-forget from dispose().
  Future<void> _releaseEngineAsync() async {
    try {
      if (_joined) await _engine.leaveChannel();
      await _engine.release();
    } catch (_) {}
  }

  Future<void> _startForegroundService() async {
    if (widget.channel.isEmpty) return;
    if (_foregroundServiceStarted) return;
    _foregroundServiceStarted = true;
    await CallForegroundServiceManager.startOngoingCall(
      callType: 'audio',
      otherUserName: widget.recipientName,
      callId: widget.channel,
    );
  }

  Future<void> _stopForegroundService() async {
    if (!_foregroundServiceStarted) return;
    try {
      await CallForegroundServiceManager.stopCallService();
      _foregroundServiceStarted = false;
    } catch (e) {
      debugPrint('Error stopping call foreground service: $e');
    }
  }

  void _listenConnectivity() {
    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen((results) {
      if (!mounted) return;
      final hasConnection = results.any((r) => r != ConnectivityResult.none);
      setState(() {
        _connectionStatus = hasConnection ? null : 'Reconnecting...';
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, _) async {
        if (didPop) return;
        // When back button is pressed, minimize the call instead of closing
        await _minimizeCall();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  // Minimize button at the top
                  Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 16, top: 12),
                      child: CallMinimizeButton(onPressed: _minimizeCall),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.phone_in_talk,
                              color: Colors.white, size: 80),
                          const SizedBox(height: 20),
                          Text(
                            'Call with ${widget.callerName}',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 24),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _formatDuration(_duration),
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 18),
                          ),
                          const SizedBox(height: 40),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              IconButton(
                                icon: Icon(
                                    _micMuted ? Icons.mic_off : Icons.mic,
                                    color: Colors.white,
                                    size: 40),
                                onPressed: _toggleMute,
                              ),
                              IconButton(
                                icon: const Icon(Icons.call_end,
                                    color: Colors.red, size: 60),
                                onPressed: _endCall,
                              ),
                              IconButton(
                                icon: Icon(
                                    _speakerOn
                                        ? Icons.volume_up
                                        : Icons.volume_off,
                                    color: Colors.white,
                                    size: 40),
                                onPressed: _engineInitialized
                                    ? () {
                                        setState(
                                            () => _speakerOn = !_speakerOn);
                                        _engine
                                            .setEnableSpeakerphone(_speakerOn);
                                      }
                                    : null,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              // Connectivity overlay banner
              ConnectionStatusOverlay(message: _connectionStatus),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return '${twoDigits(duration.inMinutes)}:${twoDigits(duration.inSeconds % 60)}';
  }
}
