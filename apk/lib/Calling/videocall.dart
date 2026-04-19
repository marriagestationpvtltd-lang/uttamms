import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:permission_handler/permission_handler.dart'
    if (dart.library.html) 'package:ms2026/utils/web_permission_stub.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../Chat/call_overlay_manager.dart';
import '../navigation/app_navigation.dart';
import '../pushnotification/pushservice.dart';
import '../service/socket_service.dart';
import 'call_tone_settings.dart';
import 'tokengenerator.dart';
import 'call_history_model.dart';
import 'call_history_service.dart';
import 'call_foreground_service.dart';
import 'widgets/connection_status_overlay.dart';

class VideoCallScreen extends StatefulWidget {
  final String currentUserId;
  final String currentUserName;
  final String currentUserImage;
  final String otherUserId;
  final String otherUserName;
  final String otherUserImage;
  final bool isOutgoingCall; // Add this
  final String? chatRoomId; // For writing inline call message to chat
  final bool isAdminChat; // True when called from AdminChatScreen
  final String? adminChatReceiverId; // Receiver ID for admin chat call messages
  /// When set, use this channel name instead of generating a new one.
  /// Used when upgrading an audio call to video (same Agora channel).
  final String? forcedChannelName;

  const VideoCallScreen({
    super.key,
    required this.currentUserId,
    required this.currentUserName,
    required this.currentUserImage,
    required this.otherUserId,
    required this.otherUserName,
    required this.otherUserImage,
    this.isOutgoingCall = true, // Default to outgoing
    this.chatRoomId,
    this.isAdminChat = false,
    this.adminChatReceiverId,
    this.forcedChannelName,
  });

  @override
  State<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen> with WidgetsBindingObserver {
  late RtcEngine _engine;
  bool _engineInitialized = false;

  int _localUid = 0;
  int? _remoteUid;

  String _channel = '';
  String _token = '';

  bool _joined = false;
  bool _callActive = false;
  bool _micMuted = false;
  bool _speakerOn = true; // Video calls default to loudspeaker (consistent with incoming video call)
  bool _cameraOn = true;
  bool _frontCamera = true;
  bool _ending = false;
  bool _remoteAccepted = false;
  bool _isCallRinging = true; // ringing state: false once remote joins
  bool _isRecipientRinging = false; // true when recipient device is ringing
  bool _recipientOffline = false; // true when server confirmed recipient is offline
  bool _recipientBusy = false;     // true when server confirmed recipient is busy
  bool _callBlocked = false;       // true when server rejected the call due to block
  bool _foregroundServiceStarted = false;

  Timer? _timeoutTimer;
  Timer? _callTimer;
  Duration _duration = Duration.zero;

  StreamSubscription? _responseSubscription;
  StreamSubscription<Map<String, dynamic>>? _socketAcceptedSub;
  StreamSubscription<Map<String, dynamic>>? _socketRejectedSub;
  StreamSubscription<Map<String, dynamic>>? _socketEndedSub;
  StreamSubscription<Map<String, dynamic>>? _socketRingingSub;
  StreamSubscription<Map<String, dynamic>>? _socketUserOfflineSub;
  StreamSubscription<Map<String, dynamic>>? _socketBusySub;
  StreamSubscription<Map<String, dynamic>>? _socketBlockedSub;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  String? _connectionStatus;

  // Network quality tracking
  int _networkQuality = 0; // 0=unknown, 1=excellent, 2=good, 3=poor, 4=bad, 5=very bad, 6=down
  String _networkQualityText = 'Unknown';
  Timer? _qualityUpdateTimer;

  // Ringtone state
  final AudioPlayer _ringtonePlayer = AudioPlayer();
  bool _isPlayingRingtone = false;
  bool _isRestartingRingtone = false;
  CallToneSettings _callToneSettings = const CallToneSettings();
  bool _callToneSettingsLoaded = false;
  StreamSubscription<PlayerState>? _playerStateSub;
  Timer? _ringtoneRestartTimer;

  // PiP (local video preview) draggable offset (from top-right)
  Offset _pipOffset = const Offset(20, 40);
  static const double _kPipWidth = 120.0;
  static const double _kPipHeight = 160.0;
  static const double _kPipPadding = 8.0;

  // Auto-hide controls after 3 s idle
  static const Duration _kControlsHideDelay = Duration(seconds: 3);
  bool _showControls = true;
  Timer? _controlsHideTimer;

  // Remote camera muted state
  bool _remoteCameraOff = false;

  // Call history tracking
  String? _callHistoryId;
  DateTime? _callStartTime;
  static const Duration _kOutgoingCallTimeout = Duration(seconds: 30);
  static const Duration _kPostAcceptConnectionTimeout = Duration(seconds: 20);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startCall();
    _listenForCallResponse();
    _listenConnectivity();
    _scheduleControlsHide();
  }

  // ================= PLAY RINGTONE =================
  Future<void> _playRingtone() async {
    if (!widget.isOutgoingCall) return;

    try {
      await _ensureCallToneSettingsLoaded();
      await _stopRingtone();

      // Use ReleaseMode.stop + timer-based repeat instead of ReleaseMode.loop.
      // ReleaseMode.loop is unreliable on some Android devices and does not
      // recover when Agora's enableAudio() takes over the audio session
      // (audio-focus loss fires PlayerState.stopped, not .completed).
      await _ringtonePlayer.setReleaseMode(ReleaseMode.stop);

      _playerStateSub?.cancel();
      _playerStateSub = _ringtonePlayer.onPlayerStateChanged.listen((state) {
        debugPrint('🔊 Ringtone player state changed: $state');
        // Restart on both .completed (normal end) and .stopped (audio focus
        // lost, e.g. when Agora initializes) so the caller always hears the
        // ringing tone while waiting for the recipient.
        if ((state == PlayerState.completed || state == PlayerState.stopped) &&
            _isPlayingRingtone &&
            !_isRestartingRingtone &&
            !_ending &&
            mounted) {
          _isRestartingRingtone = true;
          _ringtoneRestartTimer?.cancel();
          // Small delay lets the audio session stabilize after Agora init
          // and avoids rapid-fire restart loops.
          _ringtoneRestartTimer = Timer(const Duration(milliseconds: 500), () {
            if (!_ending && mounted && _isPlayingRingtone) {
              debugPrint('🔁 Ringtone interrupted/completed – restarting');
              _playConfiguredTone().whenComplete(() {
                _isRestartingRingtone = false;
                debugPrint('✅ Ringtone restart complete');
              });
            } else {
              _isRestartingRingtone = false;
            }
          });
        }
      });

      // Set the flag BEFORE starting playback so the state listener can
      // detect completion/stop events even if the tone finishes very quickly.
      if (mounted) {
        setState(() => _isPlayingRingtone = true);
      }

      await _playConfiguredTone();
      debugPrint('🎵 Started playing calling tone');
    } catch (e) {
      debugPrint('❌ Error playing calling tone: $e');
    }
  }

  Future<void> _ensureCallToneSettingsLoaded() async {
    if (_callToneSettingsLoaded) return;
    _callToneSettings = await CallToneSettingsService.instance.load();
    _callToneSettingsLoaded = true;
  }

  Future<void> _playConfiguredTone() async {
    Object? lastError;
    for (final source in _callToneSettings.playbackSources) {
      try {
        await _ringtonePlayer.play(
          source.isRemote ? UrlSource(source.value) : AssetSource(source.value),
        );
        return;
      } catch (e) {
        lastError = e;
      }
    }
    if (lastError != null) throw lastError;
  }

  Future<void> _stopRingtone() async {
    try {
      _ringtoneRestartTimer?.cancel();
      _ringtoneRestartTimer = null;
      _playerStateSub?.cancel();
      _playerStateSub = null;
      await _ringtonePlayer.stop();

      if (!mounted) return;
      setState(() {
        _isPlayingRingtone = false;
        _isRestartingRingtone = false;
      });
    } catch (e) {
      debugPrint('Error stopping calling tone: $e');
    }
  }

  // ================= STOP RINGTONE =================


  // ================= LISTEN FOR CALL RESPONSE =================
  void _listenForCallResponse() {
    // FCM path (fallback for background/offline)
    _responseSubscription = NotificationService.callResponses.listen((data) {
      _handleVideoCallResponseData(data);
    });

    // Socket.IO path (fast, for online recipients)
    _socketAcceptedSub = SocketService().onCallAccepted.listen((data) {
      final channelName = data['channelName']?.toString();
      if (_channel.isNotEmpty && channelName != null && channelName.isNotEmpty && channelName != _channel) return;
      _handleVideoCallResponseData({...data, 'type': 'video_call_response', 'accepted': 'true'});
    });
    _socketRejectedSub = SocketService().onCallRejected.listen((data) {
      final channelName = data['channelName']?.toString();
      if (_channel.isNotEmpty && channelName != null && channelName.isNotEmpty && channelName != _channel) return;
      _handleVideoCallResponseData({...data, 'type': 'video_call_response', 'accepted': 'false'});
    });
    _socketEndedSub = SocketService().onCallEnded.listen((data) {
      final channelName = data['channelName']?.toString();
      if (_channel.isNotEmpty && channelName != null && channelName.isNotEmpty && channelName != _channel) return;
      if (!_ending) _endCall();
    });
    // Recipient device started ringing → advance from "Calling..." to "Ringing..."
    _socketRingingSub = SocketService().onCallRinging.listen((data) {
      final channelName = data['channelName']?.toString();
      if (_channel.isNotEmpty && channelName != null && channelName.isNotEmpty && channelName != _channel) return;
      if (!_isRecipientRinging && mounted) {
        setState(() => _isRecipientRinging = true);
        _syncOverlayState();
      }
      // FCM fallback so the call wakes the app if it is truly backgrounded/killed.
      if (widget.isOutgoingCall && widget.forcedChannelName == null) {
        unawaited(NotificationService.sendVideoCallNotification(
          recipientUserId: widget.otherUserId,
          callerName: widget.currentUserName,
          channelName: _channel,
          callerId: widget.currentUserId,
          callerUid: _localUid.toString(),
          agoraAppId: AgoraTokenService.appId,
          agoraCertificate: 'SERVER_ONLY',
          chatRoomId: widget.chatRoomId,
        ));
      }
    });
    // Server confirmed the recipient was offline when the call was sent.
    // Send FCM push now — this is the primary delivery path for offline users.
    _socketUserOfflineSub = SocketService().onCallUserOffline.listen((data) {
      final channelName = data['channelName']?.toString();
      if (_channel.isNotEmpty && channelName != null && channelName.isNotEmpty && channelName != _channel) return;
      if (!_callActive && !_ending && mounted) {
        setState(() => _recipientOffline = true);
        _syncOverlayState();
      }
      if (widget.isOutgoingCall && widget.forcedChannelName == null) {
        unawaited(NotificationService.sendVideoCallNotification(
          recipientUserId: widget.otherUserId,
          callerName: widget.currentUserName,
          channelName: _channel,
          callerId: widget.currentUserId,
          callerUid: _localUid.toString(),
          agoraAppId: AgoraTokenService.appId,
          agoraCertificate: 'SERVER_ONLY',
          chatRoomId: widget.chatRoomId,
        ));
      }
    });
    // Server confirmed the recipient is busy on another call.
    _socketBusySub = SocketService().onCallBusy.listen((data) {
      final channelName = data['channelName']?.toString();
      if (_channel.isNotEmpty && channelName != null && channelName.isNotEmpty && channelName != _channel) return;
      if (!_ending && mounted) {
        setState(() => _recipientBusy = true);
        _syncOverlayState();
        unawaited(_stopRingtone());
        // Log "User is busy" message to chat history
        if (widget.chatRoomId != null && widget.chatRoomId!.isNotEmpty) {
          unawaited(CallHistoryService.logCallMessageInChat(
            callerId: widget.currentUserId,
            callType: 'video',
            callStatus: 'busy',
            duration: 0,
            chatRoomId: widget.chatRoomId,
            isAdminChat: widget.isAdminChat,
            adminChatSenderId: widget.isAdminChat ? widget.currentUserId : null,
            adminChatReceiverId: widget.isAdminChat ? widget.adminChatReceiverId : null,
            messageDocId: _channel.isNotEmpty ? 'call_busy_$_channel' : null,
          ));
        }
        // Auto-end after a short delay so the user sees the busy message
        Future.delayed(const Duration(seconds: 2), () {
          if (!_ending) _endCall();
        });
      }
    });
    // Server rejected the call because either party has blocked the other.
    _socketBlockedSub = SocketService().onCallBlocked.listen((data) {
      final channelName = data['channelName']?.toString();
      if (_channel.isNotEmpty && channelName != null && channelName.isNotEmpty && channelName != _channel) return;
      _callBlocked = true;
      if (!_ending && mounted) {
        unawaited(_stopRingtone());
        _endCall();
      }
    });
  }

  void _handleVideoCallResponseData(Map<String, dynamic> data) {
    final type = data['type']?.toString();
    final channelName = data['channelName']?.toString();
    if (_channel.isNotEmpty &&
        channelName != null &&
        channelName.isNotEmpty &&
        channelName != _channel) {
      return;
    }

    if (type == 'video_call_response') {
      final accepted = data['accepted'] == 'true';
      if (mounted) {
        setState(() {
          _remoteAccepted = accepted;
          if (accepted) {
            _isCallRinging = false;
          }
        });
      }

      if (!accepted) {
        unawaited(_stopRingtone());
        _endCall();
      } else {
        unawaited(_stopRingtone());
        _armOutgoingTimeout(_kPostAcceptConnectionTimeout);
        _syncOverlayState();
      }
    } else if (type == 'video_call_ended') {
      _endCall();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_ending) {
      _checkPendingCallEvent();
    }
  }

  /// Reads any call-termination event that was saved by the background isolate
  /// and processes it to close the video call screen.
  static const int _kCallEventExpiryMs = 300000; // 5 minutes

  /// Reads any call-termination event that was saved by the background isolate
  /// and processes it to close the video call screen.
  Future<void> _checkPendingCallEvent() async {
    if (_ending) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final eventStr = prefs.getString('pending_call_event');
      if (eventStr == null) return;

      final event = json.decode(eventStr) as Map<String, dynamic>;
      final receivedAt = event['_receivedAt'] as int?;
      final now = DateTime.now().millisecondsSinceEpoch;

      // Always remove stale / expired events to prevent re-processing
      if (receivedAt == null || now - receivedAt > _kCallEventExpiryMs) {
        await prefs.remove('pending_call_event');
        return;
      }

      final eventType = event['type']?.toString() ?? '';
      final eventChannel = event['channelName']?.toString() ?? '';

      if (_channel.isNotEmpty && eventChannel.isNotEmpty && eventChannel != _channel) {
        return;
      }

      // Remove the event before acting on it
      await prefs.remove('pending_call_event');

      // Don't process rejection if call is already connected
      if (_callActive) return;

      if ((eventType == 'call_response' || eventType == 'video_call_response') &&
          event['accepted'] == 'false') {
        if (mounted) {
          setState(() {
            _remoteAccepted = false;
          });
        }
        unawaited(_stopRingtone());
        _endCall();
      } else if (eventType == 'call_ended' ||
          eventType == 'video_call_ended' ||
          eventType == 'call_cancelled' ||
          eventType == 'video_call_cancelled') {
        _endCall();
      }
    } catch (e) {
      debugPrint('❌ Error checking pending call event: $e');
    }
  }

  void _initializeOverlay() {
    CallOverlayManager().startCall(
      callType: 'video',
      otherUserName: widget.otherUserName,
      otherUserId: widget.otherUserId,
      currentUserId: widget.currentUserId,
      currentUserName: widget.currentUserName,
      onMaximize: () {
        navigatorKey.currentState?.popUntil(
          (route) => route.settings.name == activeCallRouteName || route.isFirst,
        );
      },
      onEnd: _endCall,
      onToggleMute: _toggleMute,
      onToggleCamera: _toggleVideo,
      isMicMuted: _micMuted,
      isCameraEnabled: _cameraOn,
    );
    _syncOverlayState();
  }

  void _syncOverlayState() {
    final String statusText;
    if (_callActive) {
      statusText = 'Connected';
    } else if (_recipientBusy) {
      statusText = 'User is busy, please try again later';
    } else if (_remoteAccepted) {
      statusText = 'Connecting video...';
    } else if (_recipientOffline) {
      statusText = 'User is not online';
    } else if (_isRecipientRinging) {
      statusText = 'Ringing...';
    } else {
      statusText = 'Calling...';
    }

    CallOverlayManager().updateCallState(
      statusText: statusText,
      duration: _duration,
      isMicMuted: _micMuted,
      isCameraEnabled: _cameraOn,
    );
  }

  String _getOutgoingStatusText({bool isVideoConnect = false}) {
    if (_callActive) return 'Connected';
    if (_recipientBusy) return 'User is busy, please try again later';
    if (_remoteAccepted) return isVideoConnect ? 'Connecting video...' : 'Connecting...';
    if (_recipientOffline) return 'User is not online';
    if (_isRecipientRinging) return 'Ringing...';
    return 'Calling...';
  }

  Future<void> _minimizeCall() async {
    await openMinimizedCallHost(context);
  }

  // ================= START CALL =================
  Future<void> _startCall() async {
    try {
      // Request permissions BEFORE starting ringtone so that a first-time
      // permission dialog does not interrupt audio/video playback.
      final micStatus = await Permission.microphone.status;
      if (micStatus.isDenied) {
        if (!(await Permission.microphone.request()).isGranted) {
          debugPrint("Microphone permission denied");
          return;
        }
      } else if (micStatus.isPermanentlyDenied) {
        debugPrint("Microphone permanently denied");
        await openAppSettings();
        return;
      }

      final camStatus = await Permission.camera.status;
      if (camStatus.isDenied) {
        if (!(await Permission.camera.request()).isGranted) {
          debugPrint("Camera permission denied");
          return;
        }
      } else if (camStatus.isPermanentlyDenied) {
        debugPrint("Camera permanently denied");
        await openAppSettings();
        return;
      }

      // Skip ringtone for audio→video upgrades (call already connected)
      if (widget.isOutgoingCall && widget.forcedChannelName == null) {
        await _ensureCallToneSettingsLoaded();
        await _playRingtone();
      }

      // ✅ UID FIRST
      _localUid = Random().nextInt(999999);

      // ✅ CHANNEL FIRST — use forced channel for audio→video upgrades
      if (widget.forcedChannelName != null && widget.forcedChannelName!.isNotEmpty) {
        _channel = widget.forcedChannelName!;
      } else {
        _channel =
        'videocall_${widget.currentUserId.substring(0, min(4, widget.currentUserId.length))}'
            '_${widget.otherUserId.substring(0, min(4, widget.otherUserId.length))}'
            '_${DateTime.now().millisecondsSinceEpoch}';

        if (_channel.length > 64) {
          _channel = _channel.substring(0, 64);
        }
      }

      _initializeOverlay();

      // ✅ TOKEN
      _token = await AgoraTokenService.getToken(
        channelName: _channel,
        uid: _localUid,
      );

      // ✅ SEND NOTIFICATION AFTER CHANNEL EXISTS
      // Skip invite/notification when this is an audio→video upgrade (forcedChannelName set).
      if (widget.isOutgoingCall && widget.forcedChannelName == null) {
        // Socket.IO (instant delivery for online users).
        // FCM push is sent later once the server confirms the call is allowed
        // (see _socketRingingSub / _socketUserOfflineSub handlers below).
        // This prevents sending a push notification to a blocked user.
        SocketService().emitCallInvite(
          recipientId: widget.otherUserId,
          callerId: widget.currentUserId,
          callerName: widget.currentUserName,
          callerImage: widget.currentUserImage,
          channelName: _channel,
          callerUid: _localUid.toString(),
          callType: 'video',
          chatRoomId: widget.chatRoomId,
        );

        // Log call to history
        _callHistoryId = await CallHistoryService.logCall(
          callerId: widget.currentUserId,
          callerName: widget.currentUserName,
          callerImage: widget.currentUserImage,
          recipientId: widget.otherUserId,
          recipientName: widget.otherUserName,
          recipientImage: widget.otherUserImage,
          callType: CallType.video,
          initiatedBy: widget.currentUserId,
        );
        _callStartTime = DateTime.now();
      }

      // Agora init
      _engine = createAgoraRtcEngine();

      await _engine.initialize(
        RtcEngineContext(
          appId: AgoraTokenService.appId,
          channelProfile: ChannelProfileType.channelProfileCommunication,
        ),
      );
      _engineInitialized = true;

      // Agora enables audio by default after initialize(). Explicitly disable it
      // so the SDK does not take audio focus (and kill the ringtone) before the
      // remote peer joins. It is re-enabled in onUserJoined.
      await _engine.disableAudio();

      _engine.registerEventHandler(
        RtcEngineEventHandler(
          onJoinChannelSuccess: (_, __) {
            if (mounted) setState(() => _joined = true);
            _syncOverlayState();
            unawaited(_startForegroundService());
          },
          onUserJoined: (_, uid, __) async {
            if (mounted) {
              setState(() {
                _remoteUid = uid;
                _isCallRinging = false;
                _callActive = true;
              });
            }
            await _stopRingtone();
            // Enable microphone only after call connects to avoid interrupting ringtone
            if (_engineInitialized) {
              await _engine.enableAudio();
              // Re-assert speaker routing: enableAudio() resets Agora's audio
              // routing to its default (earpiece), so we must re-apply the
              // current speaker state immediately after enabling audio.
              unawaited(_engine.setEnableSpeakerphone(_speakerOn)
                  .catchError((e) => debugPrint('setEnableSpeakerphone error: $e')));
              // Now enable microphone publishing
              await _engine.updateChannelMediaOptions(const ChannelMediaOptions(
                publishCameraTrack: true,
                publishMicrophoneTrack: true,
                autoSubscribeAudio: true,
                autoSubscribeVideo: true,
              ));
            }
            _startCallTimer();
            _syncOverlayState();
            _scheduleControlsHide(); // Start auto-hide once call is active
            // Request audio focus now that call is connected (delayed to prevent
            // the foreground service from stealing focus away from the ringtone).
            unawaited(CallForegroundServiceManager.enableAudioFocus());
          },
          onUserOffline: (_, __, ___) => _endCall(),
          onUserMuteVideo: (_, uid, muted) {
            if (uid == _remoteUid && mounted) {
              setState(() => _remoteCameraOff = muted);
            }
          },
          onError: (code, msg) => debugPrint('Agora error: $code $msg'),
          onNetworkQuality: (connection, remoteUid, txQuality, rxQuality) {
            // Track network quality for adaptive bitrate
            final quality = max(txQuality.index, rxQuality.index);
            if (mounted && quality != _networkQuality) {
              setState(() {
                _networkQuality = quality;
                _networkQualityText = _getQualityText(quality);
              });
              _adaptVideoQuality(quality);
            }
          },
          onConnectionStateChanged: (connection, state, reason) {
            debugPrint('Connection state: $state, reason: $reason');
            // Handle reconnection scenarios
            if (state == ConnectionStateType.connectionStateReconnecting) {
              if (mounted) {
                setState(() => _connectionStatus = 'Reconnecting...');
              }
            } else if (state == ConnectionStateType.connectionStateConnected) {
              if (mounted) {
                setState(() => _connectionStatus = null);
              }
            } else if (state == ConnectionStateType.connectionStateFailed) {
              if (mounted) {
                setState(() => _connectionStatus = 'Connection failed');
              }
            }
          },
        ),
      );

      await _engine.enableVideo();
      await _engine.setClientRole(role: ClientRoleType.clientRoleBroadcaster);

      // Configure video encoder with adaptive bitrate support
      await _engine.setVideoEncoderConfiguration(
        const VideoEncoderConfiguration(
          dimensions: VideoDimensions(width: 640, height: 480),
          frameRate: 15,
          bitrate: 0, // 0 = let SDK determine based on resolution
          minBitrate: -1, // -1 = SDK default minimum
          orientationMode: OrientationMode.orientationModeAdaptive,
          degradationPreference: DegradationPreference.maintainBalanced, // Balance quality and framerate
          mirrorMode: VideoMirrorModeType.videoMirrorModeAuto,
        ),
      );

      await _engine.startPreview();

      await _engine.joinChannel(
        token: _token,
        channelId: _channel,
        uid: _localUid,
        options: const ChannelMediaOptions(
          publishCameraTrack: true,
          publishMicrophoneTrack: false, // Keep mic OFF during IVR/ringtone
          autoSubscribeAudio: true,
          autoSubscribeVideo: true,
        ),
      );

      _armOutgoingTimeout(_kOutgoingCallTimeout);

    } catch (e) {
      debugPrint("Video call init error: $e");
      await _exit();
    }
  }

  void _armOutgoingTimeout(Duration duration) {
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(duration, () {
      if (_remoteUid == null) {
        _endCall();
      }
    });
  }


  // ================= CALL TIMER =================
  void _startCallTimer() {
    _timeoutTimer?.cancel();
    if (mounted) setState(() => _callActive = true);
    _syncOverlayState();

    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _duration += const Duration(seconds: 1));
        _syncOverlayState();
      }
    });
  }

  // ================= END CALL =================
  Future<void> _endCall() async {
    if (_ending) return;
    _ending = true;
    final wasMinimized = CallOverlayManager().isMinimized;

    _callTimer?.cancel();
    _timeoutTimer?.cancel();
    _responseSubscription?.cancel();
    _socketAcceptedSub?.cancel();
    _socketRejectedSub?.cancel();
    _socketEndedSub?.cancel();
    _socketRingingSub?.cancel();
    _socketUserOfflineSub?.cancel();
    _socketBusySub?.cancel();
    _socketBlockedSub?.cancel();
    _socketAcceptedSub = null;
    _socketRejectedSub = null;
    _socketEndedSub = null;
    _socketRingingSub = null;
    _socketUserOfflineSub = null;
    _socketBusySub = null;
    _socketBlockedSub = null;

    // Always stop ringtone when ending call
    await _stopRingtone();

    // Update call history and write inline call message to chat (outgoing only).
    // Skip when recipient was busy — the busy listener already logged the message.
    if (_callHistoryId != null && _callHistoryId!.isNotEmpty && !_recipientBusy) {
      CallStatus callStatus;
      if (_callActive && _remoteUid != null) {
        callStatus = CallStatus.completed;
      } else if (_remoteUid == null) {
        callStatus = CallStatus.missed;
      } else {
        callStatus = CallStatus.cancelled;
      }

      await CallHistoryService.updateCallEnd(
        callId: _callHistoryId!,
        status: callStatus,
        duration: _duration.inSeconds,
      );

      if (widget.isOutgoingCall) {
        unawaited(CallHistoryService.logCallMessageInChat(
          callerId: widget.currentUserId,
          callType: 'video',
          callStatus: callStatus.toString().split('.').last,
          duration: _duration.inSeconds,
          chatRoomId: widget.chatRoomId,
          isAdminChat: widget.isAdminChat,
          adminChatSenderId: widget.isAdminChat ? widget.currentUserId : null,
          adminChatReceiverId: widget.isAdminChat ? widget.adminChatReceiverId : null,
          messageDocId: _channel.isNotEmpty ? 'call_$_channel' : null,
        ));
      }
    }

    // Send end/cancel via Socket.IO (fast) + FCM (fallback).
    // Skip cancel when recipient was busy — no screen to dismiss.
    if (_callActive) {
      SocketService().emitCallEnd(
        callerId: widget.currentUserId,
        recipientId: widget.otherUserId,
        channelName: _channel,
        callType: 'video',
        duration: _duration.inSeconds,
      );
      unawaited(NotificationService.sendVideoCallEndedNotification(
        recipientUserId: widget.otherUserId,
        callerName: widget.currentUserName,
        reason: 'ended',
        duration: _duration.inSeconds,
        channelName: _channel,
      ));
    } else if (!_callActive && !_recipientBusy && !_callBlocked && widget.isOutgoingCall && _channel.isNotEmpty) {
      SocketService().emitCallCancel(
        recipientId: widget.otherUserId,
        callerId: widget.currentUserId,
        callerName: widget.currentUserName,
        channelName: _channel,
        callType: 'video',
      );
      unawaited(NotificationService.sendVideoCallCancelledNotification(
        recipientUserId: widget.otherUserId,
        callerName: widget.currentUserName,
        channelName: _channel,
        callerId: widget.currentUserId,
      ));
    }

    // Navigate away FIRST so the user never sees the black AgoraRTC screen
    if (wasMinimized) {
      navigatorKey.currentState?.popUntil(
        (route) => route.settings.name == activeCallRouteName || route.isFirst,
      );
    }
    CallOverlayManager().reset();
    await _exit();

    // Release engine resources after navigation (fire-and-forget)
    if (_engineInitialized) unawaited(_releaseEngineAsync());
    unawaited(_stopForegroundService());
  }

  Future<void> _exit() async {
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _startForegroundService() async {
    if (_channel.isEmpty) return;
    if (_foregroundServiceStarted) return;
    _foregroundServiceStarted = true;
    await CallForegroundServiceManager.startOngoingCall(
      callType: 'video',
      otherUserName: widget.otherUserName,
      callId: _channel,
    );
  }

  /// Releases the Agora engine; safe to call fire-and-forget from dispose().
  Future<void> _releaseEngineAsync() async {
    try {
      if (_joined) await _engine.leaveChannel();
      await _engine.release();
    } catch (_) {}
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

  // ================= TOGGLE CAMERA =================
  Future<void> _toggleCamera() async {
    if (_joined) {
      await _engine.switchCamera();
      setState(() => _frontCamera = !_frontCamera);
    }
  }

  Future<void> _toggleMute() async {
    setState(() => _micMuted = !_micMuted);
    if (_engineInitialized) {
      await _engine.muteLocalAudioStream(_micMuted);
    }
    _syncOverlayState();
  }

  Future<void> _toggleVideo() async {
    setState(() => _cameraOn = !_cameraOn);
    if (_engineInitialized) {
      await _engine.enableLocalVideo(_cameraOn);
    }
    _syncOverlayState();
  }

  // ================= TOGGLE SPEAKER =================
  Future<void> _toggleSpeaker() async {
    setState(() => _speakerOn = !_speakerOn);
    if (_engineInitialized) {
      await _engine.setEnableSpeakerphone(_speakerOn);
    }
  }

  // ================= CONNECTIVITY =================
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

  // ================= AUTO-HIDE CONTROLS =================
  void _scheduleControlsHide() {
    _controlsHideTimer?.cancel();
    if (_callActive) {
      _controlsHideTimer = Timer(_kControlsHideDelay, () {
        if (mounted) setState(() => _showControls = false);
      });
    }
  }

  void _onTapScreen() {
    setState(() => _showControls = true);
    _scheduleControlsHide();
  }

  // ================= UI =================
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (bool didPop) async {
        if (didPop) return;
        // When back button is pressed, minimize the call instead of closing
        await _minimizeCall();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: GestureDetector(
            onTap: _onTapScreen,
            child: Stack(
              children: [
              // Remote video (full screen) — show avatar when camera is off
              if (_remoteUid != null && !_remoteCameraOff)
                AgoraVideoView(
                  controller: VideoViewController.remote(
                    rtcEngine: _engine,
                    canvas: VideoCanvas(uid: _remoteUid),
                    connection: RtcConnection(channelId: _channel),
                  ),
                )
              else if (_remoteUid != null && _remoteCameraOff)
                Container(
                  color: Colors.black87,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircleAvatar(
                          radius: 55,
                          backgroundImage: widget.otherUserImage.isNotEmpty
                              ? NetworkImage(widget.otherUserImage) as ImageProvider
                              : null,
                          backgroundColor: Colors.grey.shade700,
                          child: widget.otherUserImage.isEmpty
                              ? const Icon(Icons.person, size: 60, color: Colors.white70)
                              : null,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          widget.otherUserName,
                          style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        const Text('Camera off', style: TextStyle(color: Colors.white60)),
                      ],
                    ),
                  ),
                )
              else if (_callActive)
                Container(
                  color: Colors.black,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircleAvatar(
                          radius: 50,
                          backgroundColor: Colors.blue.shade800,
                          child: const Icon(
                            Icons.person,
                            size: 60,
                            color: Colors.white70,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          widget.otherUserName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _getOutgoingStatusText(isVideoConnect: true),
                          style: TextStyle(color: (_recipientOffline || _recipientBusy) ? Colors.orangeAccent : Colors.white70),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Container(
                  color: Colors.black,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Ringing animation for outgoing calls
                        if (_isCallRinging && widget.isOutgoingCall)
                          _buildRingingAnimation(),

                        Icon(
                          _isCallRinging ? Icons.videocam_outlined : Icons.videocam,
                          color: Colors.white54,
                          size: 100,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          widget.otherUserName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _getOutgoingStatusText(),
                          style: TextStyle(color: _recipientOffline ? Colors.orangeAccent : Colors.white70, fontSize: 18),
                        ),
                        const SizedBox(height: 10),
                        if (_isCallRinging && _joined)
                          Text(
                            'Waiting for answer...',
                            style: TextStyle(color: Colors.orange.shade300),
                          ),

                        // Ringtone status indicator
                        if (_isPlayingRingtone && widget.isOutgoingCall)
                          Padding(
                            padding: const EdgeInsets.only(top: 20),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.music_note, color: Colors.green, size: 16),
                                const SizedBox(width: 8),
                                Text(
                                  'Playing ringtone ${_speakerOn ? '(Speaker)' : '(Earpiece)'}',
                                  style: const TextStyle(color: Colors.green, fontSize: 14),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

              // Draggable local video preview (PiP)
              if (_cameraOn && _joined)
                Positioned(
                  top: _pipOffset.dy,
                  right: _pipOffset.dx,
                  width: _kPipWidth,
                  height: _kPipHeight,
                  child: GestureDetector(
                    onPanUpdate: (details) {
                      final size = MediaQuery.sizeOf(context);
                      setState(() {
                        double newRight = _pipOffset.dx - details.delta.dx;
                        double newTop = _pipOffset.dy + details.delta.dy;
                        newRight = newRight.clamp(
                            _kPipPadding, size.width - _kPipWidth - _kPipPadding);
                        newTop = newTop.clamp(
                            _kPipPadding, size.height - _kPipHeight - _kPipPadding);
                        _pipOffset = Offset(newRight, newTop);
                      });
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: AgoraVideoView(
                          controller: VideoViewController(
                            rtcEngine: _engine,
                            canvas: const VideoCanvas(uid: 0),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

              // Animated controls overlay (auto-hide)
              AnimatedOpacity(
                opacity: _showControls ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: Stack(
                  children: [
                    // Top info bar
                    Positioned(
                      top: 40,
                      left: 20,
                      right: 20,
                      child: Row(
                        children: [
                          Container(
                           padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                           decoration: BoxDecoration(
                             color: Colors.black54,
                             borderRadius: BorderRadius.circular(20),
                           ),
                           child: Row(
                             children: [
                               Icon(
                                 _callActive ? Icons.videocam :
                                 (_isCallRinging ? Icons.videocam_outlined : Icons.videocam),
                                 color: Colors.white,
                                 size: 20,
                               ),
                               const SizedBox(width: 8),
                               Text(
                                 _callActive
                                     ? _format(_duration)
                                     : (_isCallRinging ? 'Calling...' : 'Connecting...'),
                                 style: const TextStyle(color: Colors.white),
                               ),
                             ],
                           ),
                          ),
                          const Spacer(),
                          CallMinimizeButton(onPressed: _minimizeCall),
                        ],
                      ),
                    ),

                    // Bottom controls
                    Positioned(
                      bottom: 40,
                      left: 0,
                      right: 0,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                           _controlButton(
                             icon: _micMuted ? Icons.mic_off : Icons.mic,
                             color: Colors.white,
                             onPressed: _callActive ? _toggleMute : null,
                           ),
                           _controlButton(
                             icon: _cameraOn ? Icons.videocam : Icons.videocam_off,
                             color: Colors.white,
                             onPressed: _joined ? _toggleVideo : null,
                           ),
                          _controlButton(
                            icon: Icons.call_end,
                            color: Colors.red,
                            onPressed: _endCall,
                            size: 56,
                          ),
                          _controlButton(
                            icon: Icons.switch_camera,
                            color: Colors.white,
                            onPressed: _joined ? _toggleCamera : null,
                          ),
                          _controlButton(
                            icon: _speakerOn ? Icons.volume_up : Icons.volume_off,
                            color: Colors.white,
                            onPressed: (_joined || _isCallRinging) ? _toggleSpeaker : null,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Connectivity overlay banner (always on top)
              ConnectionStatusOverlay(message: _connectionStatus),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ================= RINGING ANIMATION =================
  Widget _buildRingingAnimation() {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(3, (index) {
          return TweenAnimationBuilder<double>(
            tween: Tween(begin: 8.0, end: 12.0),
            duration: Duration(milliseconds: 600 + (index * 200)),
            curve: Curves.easeInOut,
            builder: (context, size, child) {
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: Colors.blue,
                  borderRadius: BorderRadius.circular(size / 2),
                ),
              );
            },
            child: null,
          );
        }),
      ),
    );
  }

  Widget _controlButton({
    required IconData icon,
    required Color color,
    required VoidCallback? onPressed,
    double size = 48,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: onPressed != null ? Colors.black54 : Colors.black26,
        shape: BoxShape.circle,
      ),
      child: IconButton(
        icon: Icon(icon, color: onPressed != null ? color : Colors.white30, size: size * 0.6),
        onPressed: onPressed,
        padding: EdgeInsets.zero,
      ),
    );
  }

  String _format(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  // ================= ADAPTIVE VIDEO QUALITY =================
  String _getQualityText(int quality) {
    switch (quality) {
      case 0: return 'Unknown';
      case 1: return 'Excellent';
      case 2: return 'Good';
      case 3: return 'Poor';
      case 4: return 'Bad';
      case 5: return 'Very Bad';
      case 6: return 'Disconnected';
      default: return 'Unknown';
    }
  }

  Future<void> _adaptVideoQuality(int quality) async {
    if (!_engineInitialized || !_joined) return;

    try {
      // Adaptive bitrate based on network quality
      // Quality: 1=excellent, 2=good, 3=poor, 4=bad, 5=very bad, 6=down
      VideoEncoderConfiguration config;

      if (quality <= 2) {
        // Excellent or Good - HD quality
        config = const VideoEncoderConfiguration(
          dimensions: VideoDimensions(width: 640, height: 480),
          frameRate: 15,
          bitrate: 0, // SDK determines optimal
          minBitrate: -1,
          orientationMode: OrientationMode.orientationModeAdaptive,
          degradationPreference: DegradationPreference.maintainBalanced,
          mirrorMode: VideoMirrorModeType.videoMirrorModeAuto,
        );
        debugPrint('📶 Network quality $quality: Maintaining HD video (640x480@15fps)');
      } else if (quality == 3) {
        // Poor - Reduce to standard quality
        config = const VideoEncoderConfiguration(
          dimensions: VideoDimensions(width: 480, height: 360),
          frameRate: 12,
          bitrate: 0,
          minBitrate: -1,
          orientationMode: OrientationMode.orientationModeAdaptive,
          degradationPreference: DegradationPreference.maintainBalanced,
          mirrorMode: VideoMirrorModeType.videoMirrorModeAuto,
        );
        debugPrint('📶 Network quality $quality: Reducing to standard video (480x360@12fps)');
      } else if (quality >= 4) {
        // Bad or Very Bad - Reduce to low quality
        config = const VideoEncoderConfiguration(
          dimensions: VideoDimensions(width: 320, height: 240),
          frameRate: 10,
          bitrate: 0,
          minBitrate: -1,
          orientationMode: OrientationMode.orientationModeAdaptive,
          degradationPreference: DegradationPreference.maintainFramerate, // Prioritize smooth video
          mirrorMode: VideoMirrorModeType.videoMirrorModeAuto,
        );
        debugPrint('📶 Network quality $quality: Reducing to low video (320x240@10fps)');
      } else {
        return; // Unknown quality
      }

      await _engine.setVideoEncoderConfiguration(config);
    } catch (e) {
      debugPrint('Error adapting video quality: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _callTimer?.cancel();
    _timeoutTimer?.cancel();
    _qualityUpdateTimer?.cancel();
    _responseSubscription?.cancel();
    _socketAcceptedSub?.cancel();
    _socketRejectedSub?.cancel();
    _socketEndedSub?.cancel();
    _socketRingingSub?.cancel();
    _socketUserOfflineSub?.cancel();
    _socketBusySub?.cancel();
    _socketBlockedSub?.cancel();
    _connectivitySubscription?.cancel();
    _controlsHideTimer?.cancel();
    _ringtoneRestartTimer?.cancel();
    _playerStateSub?.cancel();
    _ringtonePlayer.dispose();
    // Release Agora engine if not already released by _endCall
    if (_engineInitialized) {
      unawaited(_releaseEngineAsync());
    }
    unawaited(_stopForegroundService());
    super.dispose();
  }
}
