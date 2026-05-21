import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:permission_handler/permission_handler.dart'
    if (dart.library.html) 'package:ms2026/utils/web_permission_stub.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../Chat/call_overlay_manager.dart';
import '../Package/PackageScreen.dart';
import '../core/user_state.dart';
import '../navigation/app_navigation.dart';
import '../pushnotification/pushservice.dart';
import '../service/socket_service.dart';
import '../service/device_sound_policy_service.dart';
import '../service/sound_settings_service.dart';
import '../service/app_sound_tone_service.dart';
import 'tokengenerator.dart';
import 'call_history_model.dart';
import 'call_history_service.dart';
import 'call_foreground_service.dart';
import 'widgets/connection_status_overlay.dart';
import '../features/shorts/camera_filters.dart';

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

class _VideoCallScreenState extends State<VideoCallScreen>
    with WidgetsBindingObserver {
  late RtcEngine _engine;
  bool _engineInitialized = false;
  late final AudioPlayer _ringtonePlayer;

  int _localUid = 0;
  int? _remoteUid;

  String _channel = '';
  String _token = '';

  bool _joined = false;
  bool _callActive = false;
  bool _micMuted = false;
  bool _speakerOn = false; // Start on earpiece; user can switch to loudspeaker.
  bool _cameraOn = true;
  bool _frontCamera = true;
  bool _ending = false;
  bool _remoteAccepted = false;
  bool _isCallRinging = true; // ringing state: false once remote joins
  bool _isRecipientRinging = false; // true when recipient device is ringing
  bool _recipientOffline =
      false; // true when server confirmed recipient is offline
  bool _recipientBusy = false; // true when server confirmed recipient is busy
  bool _callBlocked = false; // true when server rejected the call due to block
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
  StreamSubscription<Map<String, dynamic>>? _socketAllAdminsBusySub;
  StreamSubscription<Map<String, dynamic>>? _socketFeatureDeniedSub;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  String? _connectionStatus;

  // Network quality tracking
  int _networkQuality =
      0; // 0=unknown, 1=excellent, 2=good, 3=poor, 4=bad, 5=very bad, 6=down
  Timer? _qualityUpdateTimer;

  // Ringtone state
  bool _isPlayingRingtone = false;
  Timer? _vibrationTimer;

  // Camera filter
  int _filterIdx = 0;
  bool _showFilterPanel = false;

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
  static const Duration _kOutgoingCallTimeout = Duration(seconds: 30);
  // Allow slower devices/networks to complete recipient join after accept.
  static const Duration _kPostAcceptConnectionTimeout = Duration(seconds: 60);

  bool get _isAdminSupportCall {
    final targetId = (widget.adminChatReceiverId ?? '').trim().isNotEmpty
        ? (widget.adminChatReceiverId ?? '').trim()
        : widget.otherUserId.trim();
    return widget.isAdminChat ||
        targetId == '1' ||
        widget.currentUserId.trim() == '1' ||
        widget.otherUserId.trim() == '1';
  }

  /// Sanitize caller display name (remove hash, format member codes)
  String _sanitizeName(String? rawName) {
    if (rawName == null || rawName.isEmpty) return 'Unknown';

    final trimmed = rawName.trim();
    final parts = trimmed
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty && !p.startsWith('#'))
        .toList();

    if (parts.isEmpty) return 'Unknown';

    final nameParts = parts.where((p) {
      final clean = p.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
      return !RegExp(r'^(ms)?\d+$', caseSensitive: false).hasMatch(clean);
    }).toList();

    final lastName = nameParts.isNotEmpty ? nameParts.last : 'Member';

    final firstPart = parts.first;
    final compactFirst = firstPart.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');

    if (RegExp(r'^\d+$').hasMatch(compactFirst)) {
      return 'ms$compactFirst $lastName';
    } else if (RegExp(r'^ms\d+$', caseSensitive: false)
        .hasMatch(compactFirst)) {
      return '$compactFirst $lastName';
    }

    return lastName;
  }

  @override
  void initState() {
    super.initState();
    // Lock portrait so Agora never re-encodes on device tilt.
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    WidgetsBinding.instance.addObserver(this);
    _ringtonePlayer = AudioPlayer();
    _ringtonePlayer.setReleaseMode(ReleaseMode.loop);
    unawaited(_startCallWithFeatureGuard());
    _listenForCallResponse();
    _listenConnectivity();
    _scheduleControlsHide();
  }

  Future<bool> _ensureSocketConnected() async {
    final socketService = SocketService();
    if (socketService.isConnected &&
        socketService.currentUserId == widget.currentUserId) {
      return true;
    }

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('bearer_token');
    socketService.connect(widget.currentUserId, token: token);

    try {
      await socketService.onConnectionChange
          .firstWhere((connected) => connected)
          .timeout(const Duration(seconds: 10));
      return true;
    } catch (_) {
      // FCM fallback still handles call signaling if socket connect is delayed.
      return false;
    }
  }

  Future<void> _startCallWithFeatureGuard() async {
    if (!mounted) return;
    var canVideoCall = context.read<UserState>().canVideoCall;
    if (!_isAdminSupportCall && !canVideoCall) {
      // After a successful package purchase, local cache may still be stale for a
      // brief moment. Force one refresh before showing the upgrade gate.
      final refreshed = await _refreshUserStateForCallGate();
      if (refreshed && mounted) {
        canVideoCall = context.read<UserState>().canVideoCall;
      }
    }
    if (!_isAdminSupportCall && !canVideoCall) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('This feature is available in Premium Plan')),
        );
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const SubscriptionPage()),
        );
      }
      return;
    }
    await _startCall();
  }

  Future<bool> _refreshUserStateForCallGate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataString = prefs.getString('user_data');
      int? userId;

      if (userDataString != null && userDataString.trim().isNotEmpty) {
        final userData = jsonDecode(userDataString);
        if (userData is Map<String, dynamic>) {
          userId = int.tryParse(
            (userData['id'] ?? userData['userid'] ?? userData['userId'] ?? '')
                .toString(),
          );
        }
      }

      userId ??= int.tryParse(widget.currentUserId);
      if (userId == null || !mounted) return false;

      await context.read<UserState>().refresh(userId);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ================= PLAY RINGTONE =================
  Future<void> _playRingtone() async {
    if (!widget.isOutgoingCall) return;

    try {
      await _stopRingtone();

      if (!SoundSettingsService.instance.callSoundEnabled) {
        debugPrint('📴 Call sound disabled by user – skipping ringtone');
        return;
      }

      final canPlay = await DeviceSoundPolicyService.canPlayInAppSound();
      if (!canPlay) {
        debugPrint('📴 Phone silent/vibrate/DND – skipping video ringtone');
        return;
      }

      if (mounted) setState(() => _isPlayingRingtone = true);

      // Start vibration
      if (SoundSettingsService.instance.vibrationEnabled && !kIsWeb) {
        HapticFeedback.vibrate();
        _vibrationTimer?.cancel();
        _vibrationTimer =
            Timer.periodic(const Duration(milliseconds: 1500), (_) {
          if (_isPlayingRingtone && !_ending && mounted) {
            HapticFeedback.vibrate();
          }
        });
      }

      await _ringtonePlayer.setReleaseMode(ReleaseMode.loop);
      await _ringtonePlayer.setVolume(_speakerOn ? 1.0 : 0.35);

      // Outgoing video call ringback: strict custom-or-system-default. No
      // bundled audio assets are played here.
      final outgoingCustom = await AppSoundToneService.instance
          .customUrl(AppSoundToneType.outgoingCall);
      if (outgoingCustom.isNotEmpty) {
        try {
          await _ringtonePlayer.play(UrlSource(outgoingCustom));
          debugPrint(
              '🎵 Outgoing video tone (custom) started: $outgoingCustom');
          return;
        } catch (e) {
          debugPrint('⚠️ Custom outgoing video tone failed: $e');
          AppSoundToneService.instance.reportBrokenRemoteTone(
              AppSoundToneType.outgoingCall, outgoingCustom);
        }
      }

      if (!kIsWeb) {
        await FlutterRingtonePlayer().play(
          android: AndroidSounds.notification,
          looping: true,
        );
        debugPrint('🎵 Outgoing video tone fallback: system notification');
      }
    } catch (e) {
      debugPrint('❌ Error playing calling tone: $e');
    }
  }

  Future<void> _stopRingtone() async {
    try {
      _vibrationTimer?.cancel();
      _vibrationTimer = null;
      await _ringtonePlayer.stop();
      if (!kIsWeb) {
        await FlutterRingtonePlayer().stop();
      }

      if (!mounted) return;
      setState(() => _isPlayingRingtone = false);
    } catch (e) {
      debugPrint('Error stopping calling tone: $e');
    }
  }

  // ================= STOP RINGTONE =================

  // ================= ONE-SHOT TONES (CONNECTED / ENDED) =================
  // Plays the admin-uploaded custom tone for the given category exactly once
  // using a dedicated short-lived AudioPlayer. Strict custom-only: when no
  // URL is configured this method is a no-op.
  Future<void> _playOneShotCustomTone(AppSoundToneType type) async {
    try {
      final url = await AppSoundToneService.instance.customUrl(type);
      if (url.isEmpty) return;
      final player = AudioPlayer();
      try {
        await player.play(UrlSource(url));
        Timer(const Duration(seconds: 8), () {
          try {
            player.dispose();
          } catch (_) {}
        });
        player.onPlayerComplete.first.then((_) {
          try {
            player.dispose();
          } catch (_) {}
        }).catchError((_) {});
      } catch (e) {
        debugPrint('one-shot tone $type failed: $e');
        try {
          await player.dispose();
        } catch (_) {}
        AppSoundToneService.instance.reportBrokenRemoteTone(type, url);
      }
    } catch (e) {
      debugPrint('one-shot tone error: $e');
    }
  }

  // ================= BUSY-TONE AUTO-END =================
  // Plays the supplied busy-tone URL (if any) and tears the call down when
  // playback completes, so the auto-end timing matches the audio length.
  // A 15s safety cap covers slow streams / codec failures, and when no audio
  // URL is supplied a short 2s fallback keeps the status visible briefly.
  StreamSubscription<void>? _busyAutoEndSub;
  Timer? _busyAutoEndTimer;
  bool _busyAutoEndScheduled = false;

  void _playBusyToneThenEnd(String? busyAudioUrl) {
    if (_busyAutoEndScheduled) return;
    _busyAutoEndScheduled = true;

    void finish() {
      _busyAutoEndTimer?.cancel();
      _busyAutoEndTimer = null;
      _busyAutoEndSub?.cancel();
      _busyAutoEndSub = null;
      if (mounted && !_ending) _endCall();
    }

    if (busyAudioUrl != null && busyAudioUrl.isNotEmpty) {
      debugPrint('Playing busy tone from: $busyAudioUrl');
      _busyAutoEndSub =
          _ringtonePlayer.onPlayerComplete.listen((_) => finish());
      _busyAutoEndTimer = Timer(const Duration(seconds: 15), finish);
      _ringtonePlayer.play(UrlSource(busyAudioUrl)).catchError((e) {
        debugPrint('Error playing busy tone: $e');
        finish();
      });
    } else {
      _busyAutoEndTimer = Timer(const Duration(seconds: 2), finish);
    }
  }

  // ================= LISTEN FOR CALL RESPONSE =================
  void _listenForCallResponse() {
    // FCM path (fallback for background/offline)
    _responseSubscription = NotificationService.callResponses.listen((data) {
      _handleVideoCallResponseData(data);
    });

    // Socket.IO path (fast, for online recipients)
    _socketAcceptedSub = SocketService().onCallAccepted.listen((data) {
      final channelName = data['channelName']?.toString();
      if (_channel.isNotEmpty &&
          channelName != null &&
          channelName.isNotEmpty &&
          channelName != _channel) {
        return;
      }
      _handleVideoCallResponseData(
          {...data, 'type': 'video_call_response', 'accepted': 'true'});
    });
    _socketRejectedSub = SocketService().onCallRejected.listen((data) {
      final channelName = data['channelName']?.toString();
      if (_channel.isNotEmpty &&
          channelName != null &&
          channelName.isNotEmpty &&
          channelName != _channel) {
        return;
      }
      _handleVideoCallResponseData(
          {...data, 'type': 'video_call_response', 'accepted': 'false'});
    });
    _socketEndedSub = SocketService().onCallEnded.listen((data) {
      final channelName = data['channelName']?.toString();
      if (_channel.isNotEmpty &&
          channelName != null &&
          channelName.isNotEmpty &&
          channelName != _channel) {
        return;
      }
      if (!_ending) _endCall();
    });
    // Recipient device started ringing → advance from "Calling..." to "Ringing..."
    _socketRingingSub = SocketService().onCallRinging.listen((data) {
      final channelName = data['channelName']?.toString();
      if (_channel.isNotEmpty &&
          channelName != null &&
          channelName.isNotEmpty &&
          channelName != _channel) {
        return;
      }
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
      if (_channel.isNotEmpty &&
          channelName != null &&
          channelName.isNotEmpty &&
          channelName != _channel) {
        return;
      }
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
      if (_channel.isNotEmpty &&
          channelName != null &&
          channelName.isNotEmpty &&
          channelName != _channel) {
        return;
      }
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
            adminChatReceiverId:
                widget.isAdminChat ? widget.adminChatReceiverId : null,
            messageDocId: _channel.isNotEmpty ? 'call_busy_$_channel' : null,
          ));
        }
        // Play busy tone (if backend supplied a URL) and end the call exactly
        // when the tone finishes; fall back to a short delay if no audio.
        final busyAudioUrl = data['busyAudioUrl']?.toString();
        _playBusyToneThenEnd(busyAudioUrl);
      }
    });
    // ─ MULTI-ADMIN: all admins currently busy
    _socketAllAdminsBusySub =
        SocketService().onCallAllAdminsBusy.listen((data) {
      final channelName = data['channelName']?.toString();
      if (_channel.isNotEmpty &&
          channelName != null &&
          channelName.isNotEmpty &&
          channelName != _channel) {
        return;
      }
      if (!_ending && mounted) {
        unawaited(_stopRingtone());
        final message = data['busyTextNp']?.toString() ??
            'हामीसँग सबै एडमिनहरु अहिले कलमा व्यस्त छन्। कृपया केही समयपछि प्रयास गर्नुहोला।';
        final audioUrl = data['busyAudioUrl']?.toString();
        debugPrint('All admins busy - audioUrl: $audioUrl, message: $message');
        _showAllAdminsBusyDialog(message, null);
        _playBusyToneThenEnd(audioUrl);
      }
    });
    // Server rejected the call because either party has blocked the other.
    _socketBlockedSub = SocketService().onCallBlocked.listen((data) {
      final channelName = data['channelName']?.toString();
      if (_channel.isNotEmpty &&
          channelName != null &&
          channelName.isNotEmpty &&
          channelName != _channel) {
        return;
      }
      _callBlocked = true;
      if (!_ending && mounted) {
        unawaited(_stopRingtone());
        _endCall();
      }
    });

    // Server denied call due to missing package feature.
    _socketFeatureDeniedSub =
        SocketService().onCallFeatureDenied.listen((data) {
      final channelName = data['channelName']?.toString();
      if (_channel.isNotEmpty &&
          channelName != null &&
          channelName.isNotEmpty &&
          channelName != _channel) {
        return;
      }
      final error = data['error']?.toString().trim();
      final message = (error != null && error.isNotEmpty)
          ? error
          : 'Video call could not be started.';
      _callBlocked = true;
      if (!_ending && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
        unawaited(_stopRingtone());
        _endCall();
        if (message.contains('Premium Plan')) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const SubscriptionPage()),
          );
        }
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
        if (mounted) {
          final reasonText = _resolveRejectReasonText(data);
          if (reasonText.isNotEmpty) {
            ScaffoldMessenger.of(context).clearSnackBars();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(reasonText)),
            );
          }
        }
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

      if (_channel.isNotEmpty &&
          eventChannel.isNotEmpty &&
          eventChannel != _channel) {
        return;
      }

      // Remove the event before acting on it
      await prefs.remove('pending_call_event');

      // Don't process rejection if call is already connected
      if (_callActive) return;

      if ((eventType == 'call_response' ||
              eventType == 'video_call_response') &&
          event['accepted'] == 'false') {
        if (mounted) {
          setState(() {
            _remoteAccepted = false;
          });
          final reasonText = _resolveRejectReasonText(event);
          if (reasonText.isNotEmpty) {
            ScaffoldMessenger.of(context).clearSnackBars();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(reasonText)),
            );
          }
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

  String _resolveRejectReasonText(Map<String, dynamic> data) {
    final reasonCode = (data['reasonCode'] ?? data['reason'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final reasonMessage =
        (data['reasonMessage'] ?? data['message'] ?? data['error'] ?? '')
            .toString()
            .trim();

    switch (reasonCode) {
      case 'feature_locked':
      case 'subscription_required':
      case 'package_required':
        return 'Call rejected: receiver package/feature does not allow calling.';
      case 'user_declined':
        return 'Call declined by receiver.';
      case 'blocked':
      case 'call_blocked':
        return 'Call blocked by privacy settings.';
      case 'busy':
      case 'call_busy':
        return 'User is busy on another call.';
      default:
        if (reasonMessage.isNotEmpty) return reasonMessage;
        return 'Call was rejected.';
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
          (route) =>
              route.settings.name == activeCallRouteName || route.isFirst,
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
    if (_remoteAccepted) {
      return isVideoConnect ? 'Connecting video...' : 'Connecting...';
    }
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

      // ── Step 1: Generate channel + UID immediately so the invite can be
      // sent without waiting for ringtone/token fetches.
      _localUid = Random().nextInt(999999);

      // Use forced channel for audio→video upgrades; generate new otherwise.
      if (widget.forcedChannelName != null &&
          widget.forcedChannelName!.isNotEmpty) {
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

      final socketReady = await _ensureSocketConnected();
      if (!socketReady) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Call server unavailable. Please try again.'),
            ),
          );
        }
        await _exit();
        return;
      }

      // ── Step 2: Emit socket invite immediately (instant delivery to admin).
      // Skip invite/notification when this is an audio→video upgrade.
      if (widget.isOutgoingCall && widget.forcedChannelName == null) {
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
      }

      // ── Step 3: Start ringtone concurrently (don't await).
      if (widget.isOutgoingCall && widget.forcedChannelName == null) {
        unawaited(_playRingtone());
      }

      // ── Step 4: Log call history in parallel (fire-and-forget).
      if (widget.isOutgoingCall && widget.forcedChannelName == null) {
        CallHistoryService.logCall(
          callerId: widget.currentUserId,
          callerName: widget.currentUserName,
          callerImage: widget.currentUserImage,
          recipientId: widget.otherUserId,
          recipientName: widget.otherUserName,
          recipientImage: widget.otherUserImage,
          callType: CallType.video,
          initiatedBy: widget.currentUserId,
        ).then((id) {
          _callHistoryId = id;
        }).catchError((e) {
          debugPrint('⚠️ logCall error (non-fatal): $e');
        });
      }

      // ── Step 5: Fetch Agora token.
      _token = await AgoraTokenService.getToken(
        channelName: _channel,
        uid: _localUid,
        userId: widget.currentUserId,
        callType: 'video',
      );

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
            if (!kIsWeb) {
              // Enforce initial route immediately after join.
              unawaited(_engine.setEnableSpeakerphone(_speakerOn).catchError(
                  (e) => debugPrint('setEnableSpeakerphone error: $e')));
            }
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
            // Admin-configured "call connected" blip (silent if not uploaded).
            unawaited(_playOneShotCustomTone(AppSoundToneType.callConnected));
            // Enable microphone only after call connects to avoid interrupting ringtone
            if (_engineInitialized) {
              await _engine.enableAudio();
              // Re-assert speaker routing: enableAudio() resets Agora's audio
              // routing to its default (earpiece), so we must re-apply the
              // current speaker state immediately after enabling audio.
              unawaited(_engine.setEnableSpeakerphone(_speakerOn).catchError(
                  (e) => debugPrint('setEnableSpeakerphone error: $e')));
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

      // Configure video encoder: Full HD 1280×720 @ 30fps
      await _engine.setVideoEncoderConfiguration(
        const VideoEncoderConfiguration(
          dimensions: VideoDimensions(width: 1280, height: 720),
          frameRate: 30,
          bitrate: 1500, // 1500 kbps for 720p 30fps
          minBitrate: 600,
          orientationMode: OrientationMode.orientationModeFixedPortrait,
          degradationPreference: DegradationPreference.maintainQuality,
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
      if (_channel.isNotEmpty && widget.isOutgoingCall) {
        // If invite was already emitted, end gracefully so recipient gets cancel.
        await _endCall();
      } else {
        await _exit();
      }
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

    // Show a running chronometer on the foreground-service notification so
    // it mirrors the in-app call timer.
    unawaited(CallForegroundServiceManager.markCallConnected(
      callType: 'video',
      otherUserName: widget.otherUserName,
    ));

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
    // Admin-configured "call ended" blip (silent if not uploaded).
    unawaited(_playOneShotCustomTone(AppSoundToneType.callEnded));
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
    _socketAllAdminsBusySub?.cancel();
    _socketFeatureDeniedSub?.cancel();
    _socketAcceptedSub = null;
    _socketRejectedSub = null;
    _socketEndedSub = null;
    _socketRingingSub = null;
    _socketUserOfflineSub = null;
    _socketBusySub = null;
    _socketBlockedSub = null;
    _socketAllAdminsBusySub = null;
    _socketFeatureDeniedSub = null;

    // Always stop ringtone when ending call
    await _stopRingtone();

    // Update call history and write inline call message to chat (outgoing only).
    // Skip when recipient was busy — the busy listener already logged the message.
    if (_callHistoryId != null &&
        _callHistoryId!.isNotEmpty &&
        !_recipientBusy) {
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
          adminChatReceiverId:
              widget.isAdminChat ? widget.adminChatReceiverId : null,
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
      // No FCM 'video call ended' push — socket event tears down the peer's
      // UI; an end-of-call notification is just noise to the user.
    } else if (!_callActive &&
        !_recipientBusy &&
        !_callBlocked &&
        widget.isOutgoingCall &&
        _channel.isNotEmpty) {
      if (_remoteAccepted) {
        SocketService().emitCallEnd(
          callerId: widget.currentUserId,
          recipientId: widget.otherUserId,
          channelName: _channel,
          callType: 'video',
          duration: _duration.inSeconds,
        );
        // No FCM 'video call ended' push (socket handles teardown).
      } else {
        SocketService().emitCallCancel(
          recipientId: widget.otherUserId,
          callerId: widget.currentUserId,
          callerName: widget.currentUserName,
          channelName: _channel,
          callType: 'video',
        );
        // No FCM 'video call cancelled' push — socket dismisses the
        // incoming-call UI for online recipients; offline recipients have
        // the original 45s FCM TTL.
      }
    }

    // Navigate away FIRST so the user never sees stale/full-screen call UI.
    CallOverlayManager().reset();
    _dismissCallRoutes();
    await _exit();

    // Release engine resources after navigation (fire-and-forget)
    if (_engineInitialized) unawaited(_releaseEngineAsync());
    unawaited(_stopForegroundService());
  }

  Future<void> _exit() async {
    _dismissCallRoutes();
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

  // ================= ALL ADMINS BUSY DIALOG =================
  void _showAllAdminsBusyDialog(String message, String? audioUrl) {
    if (!mounted) return;
    // Play busy audio from URL if provided
    if (audioUrl != null && audioUrl.isNotEmpty) {
      debugPrint('Playing busy audio from: $audioUrl');
      _ringtonePlayer.play(UrlSource(audioUrl)).then((_) {
        debugPrint('Busy audio started playing');
      }).catchError((e) {
        debugPrint('Error playing busy audio: $e');
        // Audio failed but continue with message display
      });
    }
    showDialog<void>(
      context: context,
      barrierDismissible: true, // Allow dismissal by tapping outside
      builder: (ctx) => AlertDialog(
        title: const Text('कल उपलब्ध छैन'),
        content: Text(message),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        actions: [
          TextButton(
            onPressed: () {
              debugPrint('User dismissed busy dialog');
              Navigator.of(ctx, rootNavigator: true).pop();
              if (!_ending) _endCall();
            },
            child: const Text('ठीक छ'),
          ),
        ],
      ),
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
    if (_isPlayingRingtone) {
      await _ringtonePlayer.setVolume(_speakerOn ? 1.0 : 0.35);
    }
    if (_engineInitialized) {
      await _engine.setEnableSpeakerphone(_speakerOn);
    }
  }

  // ================= CAMERA FILTERS =================
  void _toggleFilterPanel() {
    setState(() => _showFilterPanel = !_showFilterPanel);
    _scheduleControlsHide();
  }

  Future<void> _selectFilter(int idx) async {
    setState(() { _filterIdx = idx; }); // panel stays open for multi-try
    if (!_engineInitialized) return;
    final f = kCameraFilters[idx];
    final beauty = f.beauty;
    if (beauty != null) {
      try {
        await _engine.setBeautyEffectOptions(
          enabled: true,
          options: BeautyOptions(
            smoothnessLevel: beauty.smoothness,
            lighteningLevel: beauty.lightening,
            rednessLevel: beauty.redness,
            lighteningContrastLevel: LighteningContrastLevel.lighteningContrastNormal,
          ),
        );
      } catch (_) {}
    } else if (idx == 0) {
      try {
        await _engine.setBeautyEffectOptions(
          enabled: false,
          options: const BeautyOptions(),
        );
      } catch (_) {}
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
    if (_showFilterPanel) {
      setState(() { _showFilterPanel = false; _showControls = true; });
      _scheduleControlsHide();
      return;
    }
    setState(() => _showControls = true);
    _scheduleControlsHide();
  }

  // ================= UI =================
  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final hasRemoteVideo = _remoteUid != null && !_remoteCameraOff;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, _) async {
        if (didPop) return;
        await _minimizeCall();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A10),
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _onTapScreen,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // ── 1. Blurred background ────────────────────────────
              _buildBackground(),

              // ── 2. Remote full-screen video ──────────────────────
              if (hasRemoteVideo)
                RepaintBoundary(
                  child: AgoraVideoView(
                    key: const ValueKey('remote_video'),
                    controller: VideoViewController.remote(
                      rtcEngine: _engine,
                      canvas: VideoCanvas(uid: _remoteUid),
                      connection: RtcConnection(channelId: _channel),
                    ),
                  ),
                ),

              // ── 3. Persistent gradient overlays ─────────────────
              _buildGradients(),

              // ── 4. Center avatar / status ────────────────────────
              if (!hasRemoteVideo) _buildCenterState(),

              // ── 5. Draggable local PiP ───────────────────────────
              if (_cameraOn && _joined) _buildPip(mq),

              // ── 6. Controls overlay (auto-hide) ──────────────────
              AnimatedOpacity(
                opacity: _showControls ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 280),
                child: IgnorePointer(
                  ignoring: !_showControls,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      SafeArea(
                        child: Column(
                          children: [
                            _buildTopBar(),
                            const Spacer(),
                            if (_showFilterPanel && _cameraOn && _joined)
                              _buildFilterPanel(),
                            _buildBottomControls(mq),
                          ],
                        ),
                      ),
                      if (_cameraOn && _joined) _buildFilterBtn(),
                    ],
                  ),
                ),
              ),

              // ── 7. Network / connection overlay ──────────────────
              ConnectionStatusOverlay(message: _connectionStatus),
            ],
          ),
        ),
      ),
    );
  }

  // ── Background: blurred profile photo + dark vignette ──────────────
  Widget _buildBackground() {
    final photo = widget.otherUserImage;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (photo.isNotEmpty)
          ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 32, sigmaY: 32),
            child: Image.network(
              photo,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  const ColoredBox(color: Color(0xFF0A0A10)),
            ),
          )
        else
          const ColoredBox(color: Color(0xFF0A0A10)),
        // Dark vignette so the blur doesn't overpower
        Container(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.center,
              radius: 1.0,
              colors: [Color(0x55000000), Color(0xCC000000)],
            ),
          ),
        ),
      ],
    );
  }

  // ── Gradient overlays: top darken + bottom darken ──────────────────
  Widget _buildGradients() {
    return Stack(
      fit: StackFit.expand,
      children: [
        Align(
          alignment: Alignment.topCenter,
          child: Container(
            height: 220,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xCC000000), Colors.transparent],
              ),
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            height: 280,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Color(0xDD000000), Colors.transparent],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Center state: avatar + name + status ────────────────────────────
  Widget _buildCenterState() {
    final photo = widget.otherUserImage;
    final name  = _sanitizeName(widget.otherUserName);

    final String statusText;
    final Color  statusColor;
    if (_recipientOffline || _recipientBusy) {
      statusText  = _getOutgoingStatusText(isVideoConnect: true);
      statusColor = Colors.orangeAccent;
    } else if (_callActive && _remoteCameraOff) {
      statusText  = 'Camera turned off';
      statusColor = Colors.white54;
    } else if (_callActive) {
      statusText  = _format(_duration);
      statusColor = Colors.white70;
    } else if (_isCallRinging) {
      statusText  = widget.isOutgoingCall ? 'Calling…' : 'Incoming video call';
      statusColor = Colors.white70;
    } else {
      statusText  = 'Connecting…';
      statusColor = Colors.white60;
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PulseAvatar(
            photoUrl: photo,
            name: name,
            animate: !_callActive,
            radius: 56,
          ),
          const SizedBox(height: 26),
          Text(
            name,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              shadows: [Shadow(blurRadius: 12, color: Color(0x66000000))],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            statusText,
            style: TextStyle(
              color: statusColor,
              fontSize: 15,
              fontWeight: FontWeight.w400,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }

  // ── Draggable local PiP ─────────────────────────────────────────────
  Widget _buildPip(MediaQueryData mq) {
    return Positioned(
      top: _pipOffset.dy,
      right: _pipOffset.dx,
      width: _kPipWidth,
      height: _kPipHeight,
      child: GestureDetector(
        onPanUpdate: (d) {
          setState(() {
            double r = _pipOffset.dx - d.delta.dx;
            double t = _pipOffset.dy + d.delta.dy;
            r = r.clamp(_kPipPadding, mq.size.width  - _kPipWidth  - _kPipPadding);
            t = t.clamp(_kPipPadding, mq.size.height - _kPipHeight - _kPipPadding);
            _pipOffset = Offset(r, t);
          });
        },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.8), width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.55),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: RepaintBoundary(
              child: applyFilterStable(
                _filterIdx,
                AgoraVideoView(
                  key: const ValueKey('local_video'),
                  controller: VideoViewController(
                    rtcEngine: _engine,
                    canvas: const VideoCanvas(uid: 0),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Top bar: caller info + timer + network ──────────────────────────
  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Row(
        children: [
          // Minimize
          _GlassBtn(
            icon: Icons.keyboard_arrow_down_rounded,
            size: 40,
            onTap: () => _minimizeCall(),
          ),
          const SizedBox(width: 10),
          // Info pill
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(30),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.18)),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 13,
                        backgroundImage: widget.otherUserImage.isNotEmpty
                            ? NetworkImage(widget.otherUserImage)
                                as ImageProvider
                            : null,
                        backgroundColor: Colors.grey.shade700,
                        child: widget.otherUserImage.isEmpty
                            ? const Icon(Icons.person,
                                size: 13, color: Colors.white70)
                            : null,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          _sanitizeName(widget.otherUserName),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (_callActive) ...[
                        const SizedBox(width: 8),
                        Text(
                          _format(_duration),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ] else ...[
                        const SizedBox(width: 8),
                        Text(
                          _isCallRinging ? 'Calling…' : 'Connecting…',
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Network quality dot
          _buildNetworkDot(),
        ],
      ),
    );
  }

  Widget _buildNetworkDot() {
    if (!_callActive || _networkQuality == 0) return const SizedBox(width: 8);
    final q = _networkQuality;
    final Color c = q <= 2
        ? const Color(0xFF34C759)
        : q == 3
            ? const Color(0xFFFF9500)
            : const Color(0xFFFF3B30);
    return Container(
      width: 10,
      height: 10,
      margin: const EdgeInsets.only(left: 2),
      decoration: BoxDecoration(
        color: c,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: c.withValues(alpha: 0.7), blurRadius: 7)],
      ),
    );
  }

  // ── Filter panel ─────────────────────────────────────────────────────
  Widget _buildFilterPanel() {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withValues(alpha: 0.7),
            Colors.transparent,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 10, 0, 6),
            child: Text(
              'FILTERS',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.6,
              ),
            ),
          ),
          FilterPickerBar(
            selectedIndex: _filterIdx,
            onSelect: _selectFilter,
            accentColor: const Color(0xFF00C2FF),
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  // ── Filter floating button (right side, above bottom bar) ─────────
  Widget _buildFilterBtn() {
    return Positioned(
      right: 16,
      bottom: 160,
      child: GestureDetector(
        onTap: _toggleFilterPanel,
        child: ClipOval(
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: _filterIdx > 0
                    ? const Color(0xFF00C2FF).withValues(alpha: 0.22)
                    : Colors.white.withValues(alpha: 0.13),
                shape: BoxShape.circle,
                border: Border.all(
                  color: _filterIdx > 0
                      ? const Color(0xFF00C2FF).withValues(alpha: 0.7)
                      : Colors.white.withValues(alpha: 0.2),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.auto_fix_high_rounded,
                    color: _filterIdx > 0
                        ? const Color(0xFF00C2FF)
                        : Colors.white,
                    size: 18,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    _filterIdx > 0
                        ? kCameraFilters[_filterIdx].name
                        : 'Filter',
                    style: TextStyle(
                      color: _filterIdx > 0
                          ? const Color(0xFF00C2FF)
                          : Colors.white70,
                      fontSize: 8,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Bottom control bar ──────────────────────────────────────────────
  Widget _buildBottomControls(MediaQueryData mq) {
    final navPad = mq.padding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, (navPad > 0 ? navPad : 24) + 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _CallBtn(
            icon: _micMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
            label: _micMuted ? 'Unmute' : 'Mute',
            active: _micMuted,
            activeColor: const Color(0xFFFF3B30),
            onTap: _callActive ? _toggleMute : null,
          ),
          _CallBtn(
            icon: _cameraOn ? Icons.videocam_rounded : Icons.videocam_off_rounded,
            label: _cameraOn ? 'Camera' : 'No Video',
            active: !_cameraOn,
            activeColor: const Color(0xFFFF3B30),
            onTap: _joined ? _toggleVideo : null,
          ),
          _CallBtn(
            icon: Icons.call_end_rounded,
            label: 'End',
            onTap: _endCall,
            isEndCall: true,
          ),
          _CallBtn(
            icon: Icons.flip_camera_ios_rounded,
            label: 'Flip',
            onTap: _joined ? _toggleCamera : null,
          ),
          _CallBtn(
            icon: _speakerOn ? Icons.volume_up_rounded : Icons.volume_off_rounded,
            label: _speakerOn ? 'Speaker' : 'Earpiece',
            active: _speakerOn,
            activeColor: const Color(0xFF00C2FF),
            onTap: (_joined || _isCallRinging) ? _toggleSpeaker : null,
          ),
        ],
      ),
    );
  }

  String _format(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  Future<void> _adaptVideoQuality(int quality) async {
    if (!_engineInitialized || !_joined) return;

    try {
      // Adaptive bitrate based on network quality
      // Quality: 1=excellent, 2=good, 3=poor, 4=bad, 5=very bad, 6=down
      VideoEncoderConfiguration config;

      if (quality <= 2) {
        // Excellent or Good – Full HD 1280×720 @ 30fps
        config = const VideoEncoderConfiguration(
          dimensions: VideoDimensions(width: 1280, height: 720),
          frameRate: 30,
          bitrate: 1500,
          minBitrate: 600,
          orientationMode: OrientationMode.orientationModeFixedPortrait,
          degradationPreference: DegradationPreference.maintainQuality,
          mirrorMode: VideoMirrorModeType.videoMirrorModeAuto,
        );
        debugPrint(
            '📶 Network quality $quality: Full HD video (1280×720@30fps)');
      } else if (quality == 3) {
        // Poor – Drop to SD 854×480 @ 24fps
        config = const VideoEncoderConfiguration(
          dimensions: VideoDimensions(width: 854, height: 480),
          frameRate: 24,
          bitrate: 800,
          minBitrate: 400,
          orientationMode: OrientationMode.orientationModeFixedPortrait,
          degradationPreference: DegradationPreference.maintainBalanced,
          mirrorMode: VideoMirrorModeType.videoMirrorModeAuto,
        );
        debugPrint('📶 Network quality $quality: SD video (854×480@24fps)');
      } else if (quality >= 4) {
        // Bad or Very Bad – Low quality 640×360 @ 15fps
        config = const VideoEncoderConfiguration(
          dimensions: VideoDimensions(width: 640, height: 360),
          frameRate: 15,
          bitrate: 400,
          minBitrate: 200,
          orientationMode: OrientationMode.orientationModeFixedPortrait,
          degradationPreference: DegradationPreference.maintainFramerate,
          mirrorMode: VideoMirrorModeType.videoMirrorModeAuto,
        );
        debugPrint('📶 Network quality $quality: Low video (640×360@15fps)');
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
    _socketAllAdminsBusySub?.cancel();
    _socketFeatureDeniedSub?.cancel();
    _connectivitySubscription?.cancel();
    _controlsHideTimer?.cancel();
    _busyAutoEndTimer?.cancel();
    _busyAutoEndSub?.cancel();
    // Force-stop any ringing/vibration even if teardown raced with route pop.
    unawaited(_stopRingtone());
    _vibrationTimer?.cancel();
    unawaited(_ringtonePlayer.dispose());
    // Release Agora engine if not already released by _endCall
    if (_engineInitialized) {
      unawaited(_releaseEngineAsync());
    }
    unawaited(_stopForegroundService());
    // Restore full orientation support after leaving the call.
    SystemChrome.setPreferredOrientations([]);
    super.dispose();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared UI widgets
// ─────────────────────────────────────────────────────────────────────────────

/// Frosted-glass icon button used in the top bar (minimize, etc.)
class _GlassBtn extends StatelessWidget {
  final IconData icon;
  final double size;
  final VoidCallback? onTap;

  const _GlassBtn({required this.icon, this.size = 44, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipOval(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
            ),
            child: Icon(icon, color: Colors.white, size: size * 0.48),
          ),
        ),
      ),
    );
  }
}

/// Labeled call control button — mic, camera, end, speaker, filter.
class _CallBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;
  final Color activeColor;
  final bool isEndCall;

  const _CallBtn({
    required this.icon,
    required this.label,
    this.onTap,
    this.active = false,
    this.activeColor = Colors.white,
    this.isEndCall = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final double btnSize = isEndCall ? 64.0 : 56.0;

    Color bgColor;
    Color iconColor;
    if (!enabled) {
      bgColor   = Colors.white.withValues(alpha: 0.06);
      iconColor = Colors.white24;
    } else if (isEndCall) {
      bgColor   = const Color(0xFFFF3B30);
      iconColor = Colors.white;
    } else if (active) {
      bgColor   = activeColor.withValues(alpha: 0.22);
      iconColor = activeColor;
    } else {
      bgColor   = Colors.white.withValues(alpha: 0.13);
      iconColor = Colors.white;
    }

    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipOval(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                width: btnSize,
                height: btnSize,
                decoration: BoxDecoration(
                  color: bgColor,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isEndCall
                        ? Colors.transparent
                        : Colors.white.withValues(alpha: enabled ? 0.18 : 0.07),
                  ),
                  boxShadow: isEndCall && enabled
                      ? [
                          BoxShadow(
                            color: const Color(0xFFFF3B30).withValues(alpha: 0.4),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          )
                        ]
                      : null,
                ),
                child: Icon(icon, color: iconColor, size: btnSize * 0.44),
              ),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            label,
            style: TextStyle(
              color: enabled ? Colors.white70 : Colors.white30,
              fontSize: 10,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}

/// Animated pulsing avatar — used while the call is connecting / ringing.
class _PulseAvatar extends StatefulWidget {
  final String photoUrl;
  final String name;
  final bool animate;
  final double radius;

  const _PulseAvatar({
    required this.photoUrl,
    required this.name,
    this.animate = true,
    this.radius = 52,
  });

  @override
  State<_PulseAvatar> createState() => _PulseAvatarState();
}

class _PulseAvatarState extends State<_PulseAvatar>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale1;
  late Animation<double> _scale2;
  late Animation<double> _opacity1;
  late Animation<double> _opacity2;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _scale1   = Tween<double>(begin: 1.0, end: 1.55)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _scale2   = Tween<double>(begin: 1.0, end: 1.9)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _opacity1 = Tween<double>(begin: 0.35, end: 0.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _opacity2 = Tween<double>(begin: 0.18, end: 0.0)
        .animate(CurvedAnimation(
            parent: _ctrl,
            curve: const Interval(0.2, 1.0, curve: Curves.easeOut)));
    if (widget.animate) _ctrl.repeat();
  }

  @override
  void didUpdateWidget(_PulseAvatar old) {
    super.didUpdateWidget(old);
    if (widget.animate && !_ctrl.isAnimating) {
      _ctrl.repeat();
    } else if (!widget.animate && _ctrl.isAnimating) {
      _ctrl.stop();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.radius;
    return SizedBox(
      width: r * 4,
      height: r * 4,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer pulse ring
          if (widget.animate)
            AnimatedBuilder(
              animation: _ctrl,
              builder: (_, __) => Transform.scale(
                scale: _scale2.value,
                child: Container(
                  width: r * 2,
                  height: r * 2,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: _opacity2.value),
                      width: 1.5,
                    ),
                  ),
                ),
              ),
            ),
          // Inner pulse ring
          if (widget.animate)
            AnimatedBuilder(
              animation: _ctrl,
              builder: (_, __) => Transform.scale(
                scale: _scale1.value,
                child: Container(
                  width: r * 2,
                  height: r * 2,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: _opacity1.value),
                      width: 2,
                    ),
                  ),
                ),
              ),
            ),
          // Avatar
          Container(
            width: r * 2,
            height: r * 2,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.55), width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ClipOval(
              child: widget.photoUrl.isNotEmpty
                  ? Image.network(
                      widget.photoUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _initials(r),
                    )
                  : _initials(r),
            ),
          ),
        ],
      ),
    );
  }

  Widget _initials(double r) {
    final initials = widget.name.trim().isNotEmpty
        ? widget.name.trim().split(' ').take(2).map((w) => w[0]).join()
        : '?';
    return Container(
      color: const Color(0xFF1E3A5F),
      child: Center(
        child: Text(
          initials.toUpperCase(),
          style: TextStyle(
            color: Colors.white,
            fontSize: r * 0.65,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
