// ignore_for_file: curly_braces_in_flow_control_structures, deprecated_member_use
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart'
    if (dart.library.html) 'package:ms2026/utils/web_ringtone_player_stub.dart';
import 'package:permission_handler/permission_handler.dart'
    if (dart.library.html) 'package:ms2026/utils/web_permission_stub.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../Chat/call_overlay_manager.dart';
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
import 'videocall.dart';
import 'widgets/connection_status_overlay.dart';

enum _OutgoingTonePhase {
  dialing,
  ringing,
}

class CallScreen extends StatefulWidget {
  final String currentUserId;
  final String currentUserName;
  final String currentUserImage;
  final String otherUserId;
  final String otherUserName;
  final String otherUserImage;
  final bool isOutgoingCall; // Add this to identify outgoing call
  final String? chatRoomId; // For writing inline call message to chat
  final bool isAdminChat; // True when called from AdminChatScreen
  final String? adminChatReceiverId; // Receiver ID for admin chat call messages

  const CallScreen({
    super.key,
    required this.currentUserId,
    required this.currentUserName,
    required this.currentUserImage,
    required this.otherUserId,
    required this.otherUserName,
    required this.otherUserImage,
    this.isOutgoingCall = true, // Default to outgoing call
    this.chatRoomId,
    this.isAdminChat = false,
    this.adminChatReceiverId,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> with WidgetsBindingObserver {
  late RtcEngine _engine;
  bool _engineInitialized = false;
  bool _engineReleaseInProgress = false;
  late final AudioPlayer _ringtonePlayer;

  int _localUid = 0;
  int? _remoteUid;

  String _channel = '';
  String _token = '';

  bool _joined = false;
  bool _callActive = false;
  bool _micMuted = false;
  bool _speakerOn = false;
  bool _ending = false;
  bool _isCallRinging = true; // New state for ringing
  bool _foregroundServiceStarted = false;

  Timer? _timeoutTimer;
  Timer? _callTimer;
  Duration _duration = Duration.zero;

  // Ringtone state
  bool _isPlayingRingtone = false;
  Timer? _vibrationTimer; // Repeating vibration while ringing
  StreamSubscription<Map<String, dynamic>>? _responseSubscription;
  StreamSubscription<Map<String, dynamic>>? _socketAcceptedSub;
  StreamSubscription<Map<String, dynamic>>? _socketRejectedSub;
  StreamSubscription<Map<String, dynamic>>? _socketEndedSub;
  StreamSubscription<Map<String, dynamic>>? _socketRingingSub;
  StreamSubscription<Map<String, dynamic>>? _socketUserOfflineSub;
  StreamSubscription<Map<String, dynamic>>? _socketBusySub;
  StreamSubscription<Map<String, dynamic>>? _socketBlockedSub;
  StreamSubscription<Map<String, dynamic>>? _socketFeatureDeniedSub;
  StreamSubscription<Map<String, dynamic>>? _socketSwitchToVideoResponseSub;
  StreamSubscription<Map<String, dynamic>>? _socketAllAdminsBusySub;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  String? _connectionStatus;
  bool _remoteAccepted = false;
  bool _recipientOffline =
      false; // true when server confirmed recipient is offline
  bool _recipientBusy =
      false; // true when server confirmed recipient is on another call
  bool _callBlocked = false; // true when server rejected the call due to block
  bool _isSwitchingToVideo =
      false; // true while awaiting switch-to-video response
  bool _navigatingToVideo =
      false; // true once _navigateToVideoCall has been triggered
  _OutgoingTonePhase _outgoingTonePhase = _OutgoingTonePhase.dialing;

  static const Duration _kConnectivityLossTimeout = Duration(seconds: 30);
  static const Duration _kOutgoingCallTimeout = Duration(seconds: 45);
  // Give the recipient enough time to complete permission prompts, token
  // fetch, and Agora join before treating post-accept as failed.
  static const Duration _kPostAcceptConnectionTimeout = Duration(seconds: 90);

  // Call history tracking
  String? _callHistoryId;
  String _diagSessionId = '';
  int? _startCallAtMs;

  void _logCallDiag(String event, [Map<String, Object?> extra = const {}]) {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final parts = <String>[
      'event=$event',
      'ts=$ts',
      'session=${_diagSessionId.isEmpty ? '-' : _diagSessionId}',
      'channel=${_channel.isEmpty ? '-' : _channel}',
      'caller=${widget.currentUserId}',
      'recipient=${widget.otherUserId}',
    ];
    extra.forEach((k, v) => parts.add('$k=${v ?? 'null'}'));
    debugPrint('CALL_DIAG_OUT_AUDIO ${parts.join(' ')}');
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
    WidgetsBinding.instance.addObserver(this);
    _ringtonePlayer = AudioPlayer();
    _ringtonePlayer.setReleaseMode(ReleaseMode.loop);
    _listenForCallResponse();
    _startCall();
    _listenConnectivity();
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

  bool _callDeclined = false; // true when remote explicitly rejected
  bool _isRecipientRinging = false; // true when recipient device is ringing

  void _listenForCallResponse() {
    // Listen via FCM push (for when recipient was offline / app in background)
    _responseSubscription = NotificationService.callResponses.listen((data) {
      _handleCallResponseData(data);
    });

    // Listen via Socket.IO (low-latency path for online recipients)
    _socketAcceptedSub = SocketService().onCallAccepted.listen((data) {
      final channelName = data['channelName']?.toString();
      if (_channel.isNotEmpty &&
          channelName != null &&
          channelName.isNotEmpty &&
          channelName != _channel) return;
      _handleCallResponseData(
          {...data, 'type': 'call_response', 'accepted': 'true'});
    });
    _socketRejectedSub = SocketService().onCallRejected.listen((data) {
      final channelName = data['channelName']?.toString();
      if (_channel.isNotEmpty &&
          channelName != null &&
          channelName.isNotEmpty &&
          channelName != _channel) return;
      _handleCallResponseData(
          {...data, 'type': 'call_response', 'accepted': 'false'});
    });
    _socketEndedSub = SocketService().onCallEnded.listen((data) {
      final channelName = data['channelName']?.toString();
      if (_channel.isNotEmpty &&
          channelName != null &&
          channelName.isNotEmpty &&
          channelName != _channel) return;
      if (!_ending) _endCall();
    });
    // Recipient device started ringing â†' advance from "Calling..." to "Ringing..."
    // Also send FCM as fallback now that we know the server allowed the call
    // (recipient is online via socket but the app may be backgrounded).
    _socketRingingSub = SocketService().onCallRinging.listen((data) {
      final channelName = data['channelName']?.toString();
      if (_channel.isNotEmpty &&
          channelName != null &&
          channelName.isNotEmpty &&
          channelName != _channel) return;
      if (!_isRecipientRinging && mounted) {
        setState(() => _isRecipientRinging = true);
        _syncOverlayState();
      }
      // Distinct feedback for caller: switch from dialing tone to ringing tone.
      unawaited(_switchToRingingTone());
      // NOTE: FCM push is now dispatched by the socket server itself the
      // moment `call_invite` is received (see Backend/socket-server/
      // lib/socket/call-events.js dispatchCallPush). Firing it again here
      // would cause duplicate banners / racing full-screen intents on the
      // recipient, so the client-side fallback was removed.
    });
    // Server confirmed the recipient was offline when the call was sent.
    // Send FCM push now  -  this is the primary delivery path for offline users.
    _socketUserOfflineSub = SocketService().onCallUserOffline.listen((data) {
      final channelName = data['channelName']?.toString();
      if (_channel.isNotEmpty &&
          channelName != null &&
          channelName.isNotEmpty &&
          channelName != _channel) return;
      if (!_callActive && !_ending && mounted) {
        setState(() => _recipientOffline = true);
        _syncOverlayState();
      }
      // FCM is dispatched server-side on call_invite for offline recipients
      // too; no client-side fallback needed (see call-events.js).
    });
    // Server confirmed the recipient is busy on another call.
    _socketBusySub = SocketService().onCallBusy.listen((data) {
      final channelName = data['channelName']?.toString();
      if (_channel.isNotEmpty &&
          channelName != null &&
          channelName.isNotEmpty &&
          channelName != _channel) return;
      if (!_ending && mounted) {
        setState(() => _recipientBusy = true);
        _syncOverlayState();
        unawaited(_stopRingtone());
        // Log "User is busy" message to chat history
        if (widget.chatRoomId != null && widget.chatRoomId!.isNotEmpty) {
          unawaited(CallHistoryService.logCallMessageInChat(
            callerId: widget.currentUserId,
            callType: 'audio',
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
          channelName != _channel) return;
      if (!_ending && mounted) {
        unawaited(_stopRingtone());
        final message = data['busyTextNp']?.toString() ??
            'हामीसँग सबै एडमिनहरु अहिले कलमा व्यस्त छन्। कृपया केही समयपछि प्रयास गर्नुहोला।';
        final audioUrl = data['busyAudioUrl']?.toString();
        debugPrint('All admins busy - audioUrl: $audioUrl, message: $message');
        // Dialog is shown without auto-playing audio; we play+watch here so
        // the call ends precisely when the busy tone finishes.
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
          channelName != _channel) return;
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
          : 'Call could not be started.';
      _callBlocked = true;
      if (!_ending && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
        unawaited(_stopRingtone());
        _endCall();
      }
    });
    // Response to switch-to-video request
    _socketSwitchToVideoResponseSub =
        SocketService().onSwitchToVideoResponse.listen((data) {
      final channelName = data['channelName']?.toString();
      if (_channel.isNotEmpty &&
          channelName != null &&
          channelName.isNotEmpty &&
          channelName != _channel) return;
      final accepted = data['accepted'] == true || data['accepted'] == 'true';
      if (!mounted) return;
      if (accepted && _callActive && !_ending) {
        _navigateToVideoCall();
      } else if (!accepted) {
        if (!_isSwitchingToVideo) return;
        setState(() => _isSwitchingToVideo = false);
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Video switch declined'),
              duration: Duration(seconds: 2)),
        );
      }
    });
  }

  void _handleCallResponseData(Map<String, dynamic> data) {
    final type = data['type']?.toString();
    final channelName = data['channelName']?.toString();
    if (_channel.isNotEmpty &&
        channelName != null &&
        channelName.isNotEmpty &&
        channelName != _channel) {
      return;
    }

    if (type == 'call_response') {
      final accepted = data['accepted'] == 'true';
      if (accepted) {
        _logCallDiag('remote_accepted', {
          'latency_ms': _startCallAtMs == null
              ? null
              : DateTime.now().millisecondsSinceEpoch - _startCallAtMs!,
        });
        if (mounted) {
          setState(() {
            _remoteAccepted = true;
            _isCallRinging = false;
          });
        }
        unawaited(_stopRingtone());
        _armOutgoingTimeout(_kPostAcceptConnectionTimeout);
        _syncOverlayState();
      } else {
        _logCallDiag('remote_rejected', {
          'reason_code': data['reasonCode']?.toString(),
          'reason_message': data['reasonMessage']?.toString(),
        });
        if (mounted) {
          setState(() {
            _remoteAccepted = false;
            _callDeclined = true;
          });
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
      }
    } else if (type == 'call_ended') {
      _endCall();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_ending) {
      _checkPendingCallEvent();
    }
  }

  static const int _kCallEventExpiryMs = 300000; // 5 minutes

  /// Reads any call-termination event that was saved by the background isolate
  /// and processes it to close the call screen.
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

      // If we know our channel, make sure this event belongs to it
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
          setState(() => _callDeclined = true);
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
      debugPrint('âŒ Error checking pending call event: $e');
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
      callType: 'audio',
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
      isMicMuted: _micMuted,
    );
    _syncOverlayState();
  }

  String _getOutgoingStatusText() {
    if (_callActive) {
      if (_isSwitchingToVideo) return 'Switching to video...';
      return 'Connected';
    }
    if (_recipientBusy) return 'User is busy, please try again later';
    if (_remoteAccepted) return 'Connecting...';
    if (_recipientOffline) return 'User is not online';
    if (_isRecipientRinging) return 'Ringing...';
    return 'Calling...';
  }

  void _syncOverlayState() {
    CallOverlayManager().updateCallState(
      statusText: _getOutgoingStatusText(),
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

  // ================= PLAY RINGTONE =================
  Future<void> _playRingtone() async {
    if (!widget.isOutgoingCall) return;

    try {
      await _stopRingtone();

      if (!SoundSettingsService.instance.callSoundEnabled) {
        debugPrint('Call sound disabled by user - skipping ringtone');
        return;
      }

      final canPlay = await DeviceSoundPolicyService.canPlayInAppSound();
      if (!canPlay) {
        debugPrint('Phone silent/vibrate/DND - skipping outgoing ringtone');
        return;
      }

      if (mounted) setState(() => _isPlayingRingtone = true);
      _outgoingTonePhase = _OutgoingTonePhase.dialing;

      // Start repeating vibration while the call is ringing (1.5s interval).
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

      // Caller-side pre-ring tone: indicate "placing call" before recipient
      // confirms ringing. Plays admin-uploaded custom outgoing tone if set,
      // otherwise falls back to the device system notification tone. No
      // bundled audio asset is used here.
      await _ringtonePlayer.setReleaseMode(ReleaseMode.loop);
      final outgoingCustom = await AppSoundToneService.instance
          .customUrl(AppSoundToneType.outgoingCall);
      var dialingToneStarted = false;
      if (outgoingCustom.isNotEmpty) {
        try {
          await _ringtonePlayer.play(UrlSource(outgoingCustom));
          dialingToneStarted = true;
          debugPrint('Started custom outgoing tone: $outgoingCustom');
        } catch (e) {
          debugPrint('Custom outgoing tone failed: $e');
          AppSoundToneService.instance.reportBrokenRemoteTone(
              AppSoundToneType.outgoingCall, outgoingCustom);
        }
      }
      if (!dialingToneStarted && !kIsWeb) {
        await FlutterRingtonePlayer().play(
          android: AndroidSounds.notification,
          looping: true,
        );
        debugPrint('System notification (dialing default)');
      }
    } catch (e) {
      debugPrint('âŒ Error playing calling tone: $e');
    }
  }

  Future<void> _switchToRingingTone() async {
    if (!widget.isOutgoingCall || _ending || !_isPlayingRingtone) return;
    if (_outgoingTonePhase == _OutgoingTonePhase.ringing) return;

    try {
      _outgoingTonePhase = _OutgoingTonePhase.ringing;

      // Vibration is useful for dialing feedback, but should stop once we know
      // the recipient device is actually ringing.
      _vibrationTimer?.cancel();
      _vibrationTimer = null;

      if (!SoundSettingsService.instance.callSoundEnabled) return;

      // Strict policy: admin custom URL OR system default. No bundled asset
      // is ever played as a ringback.
      final ringbackCustom = await AppSoundToneService.instance
          .customUrl(AppSoundToneType.outgoingCall);
      if (!_isPlayingRingtone || _ending) return;

      if (ringbackCustom.isNotEmpty) {
        try {
          await _ringtonePlayer.setReleaseMode(ReleaseMode.loop);
          await _ringtonePlayer.play(UrlSource(ringbackCustom));
          debugPrint('Switched to custom ringback tone: $ringbackCustom');
          return;
        } catch (e) {
          debugPrint('Custom ringback failed: $e');
          AppSoundToneService.instance.reportBrokenRemoteTone(
              AppSoundToneType.outgoingCall, ringbackCustom);
        }
      }

      if (!kIsWeb) {
        await FlutterRingtonePlayer().play(
          android: AndroidSounds.notification,
          looping: true,
        );
        debugPrint('System notification (ringback default)');
      }
    } catch (e) {
      debugPrint('âŒ Error switching to ringback tone: $e');
    }
  }

  // ================= STOP RINGTONE =================
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
      _outgoingTonePhase = _OutgoingTonePhase.dialing;

      debugPrint('Stopped ringtone');
    } catch (e) {
      debugPrint('Error stopping ringtone: $e');
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

  // ================= ONE-SHOT TONES (CONNECTED / ENDED) =================
  // Plays the admin-uploaded custom tone for the given category exactly once
  // using a dedicated short-lived AudioPlayer. Strict custom-only: when no
  // URL is configured this method is a no-op (no bundled assets, no system
  // default — these are intentionally optional "blip" sounds).
  Future<void> _playOneShotCustomTone(AppSoundToneType type) async {
    try {
      final url = await AppSoundToneService.instance.customUrl(type);
      if (url.isEmpty) return;
      final player = AudioPlayer();
      try {
        await player.play(UrlSource(url));
        // Auto-release after a generous timeout so we don't leak the player
        // even if onPlayerComplete never fires.
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
      // No audio supplied â€” still allow the busy status to render briefly.
      _busyAutoEndTimer = Timer(const Duration(seconds: 2), finish);
    }
  }

  // ================= START CALL =================
  Future<void> _startCall() async {
    try {
      _diagSessionId = 'outa_${DateTime.now().millisecondsSinceEpoch}';
      _startCallAtMs = DateTime.now().millisecondsSinceEpoch;
      _logCallDiag('start_call');
      // Request microphone permission BEFORE starting ringtone so that a
      // first-time permission dialog does not interrupt audio playback.
      final micStatus = await Permission.microphone.status;
      if (micStatus.isDenied) {
        final result = await Permission.microphone.request();
        if (!result.isGranted) {
          debugPrint("Microphone permission denied");
          return; // âŒ DO NOT call _exit()
        }
      } else if (micStatus.isPermanentlyDenied) {
        debugPrint("Microphone permanently denied");
        await openAppSettings();
        return; // âŒ DO NOT call _exit()
      }

      // â”€â”€ Step 1: Generate channel + UID immediately so the call invite can
      // be sent to the recipient without waiting for ringtone/token fetches.
      _localUid = Random().nextInt(999999);
      _channel =
          'call_${widget.currentUserId.substring(0, min(4, widget.currentUserId.length))}'
          '_${widget.otherUserId.substring(0, min(4, widget.otherUserId.length))}'
          '_${DateTime.now().millisecondsSinceEpoch}';

      if (_channel.length > 64) {
        _channel = _channel.substring(0, 64);
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

      // â”€â”€ Step 2: Emit socket invite immediately (instant delivery to admin).
      // FCM push is sent later once the server confirms the call is allowed
      // (see _socketRingingSub / _socketUserOfflineSub handlers below).
      if (widget.isOutgoingCall) {
        SocketService().emitCallInvite(
          recipientId: widget.otherUserId,
          callerId: widget.currentUserId,
          callerName: widget.currentUserName,
          callerImage: widget.currentUserImage,
          channelName: _channel,
          callerUid: _localUid.toString(),
          callType: 'audio',
          chatRoomId: widget.chatRoomId,
        );
        _logCallDiag('invite_emitted', {'caller_uid': _localUid});
      }

      // â”€â”€ Step 3: Start ringtone concurrently (don't await  -  network fetch
      // for tone settings must not block Agora setup or the invite emit).
      if (widget.isOutgoingCall) {
        unawaited(_playRingtone());
      }

      // â”€â”€ Step 4: Log call history in parallel (fire-and-forget).
      if (widget.isOutgoingCall) {
        CallHistoryService.logCall(
          callerId: widget.currentUserId,
          callerName: widget.currentUserName,
          callerImage: widget.currentUserImage,
          recipientId: widget.otherUserId,
          recipientName: widget.otherUserName,
          recipientImage: widget.otherUserImage,
          callType: CallType.audio,
          initiatedBy: widget.currentUserId,
        ).then((id) {
          _callHistoryId = id;
        }).catchError((e) {
          debugPrint('logCall error (non-fatal): $e');
        });
      }

      // â”€â”€ Step 5: Fetch Agora token.
      _token = await AgoraTokenService.getToken(
        channelName: _channel,
        uid: _localUid,
        userId: widget.currentUserId,
      );

      // â”€â”€ Step 6: Init Agora engine.
      _engine = createAgoraRtcEngine();
      await _engine.initialize(RtcEngineContext(
        appId: AgoraTokenService.appId,
        channelProfile: ChannelProfileType.channelProfileCommunication,
      ));
      _engineInitialized = true;

      // Agora enables audio by default after initialize(). Explicitly disable it
      // so the SDK does not take audio focus (and kill the ringtone) before the
      // remote peer joins. It is re-enabled in onUserJoined.
      await _engine.disableAudio();

      _engine.registerEventHandler(
        RtcEngineEventHandler(
          onJoinChannelSuccess: (_, __) {
            if (mounted) setState(() => _joined = true);
            _logCallDiag('agora_join_success', {
              'latency_ms': _startCallAtMs == null
                  ? null
                  : DateTime.now().millisecondsSinceEpoch - _startCallAtMs!,
            });
            _syncOverlayState();
            unawaited(_startForegroundService());
          },
          onUserJoined: (_, uid, __) async {
            _logCallDiag('remote_joined', {
              'remote_uid': uid,
              'latency_ms': _startCallAtMs == null
                  ? null
                  : DateTime.now().millisecondsSinceEpoch - _startCallAtMs!,
            });
            if (mounted) {
              setState(() {
                _remoteUid = uid;
                _isCallRinging = false; // Stop ringing state
                _callActive = true;
              });
            }
            await _stopRingtone(); // Stop ringtone when user joins
            // Play the admin-configured "call connected" tone, if any. Strict
            // custom-only: silent when no URL is uploaded.
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
                publishMicrophoneTrack: true,
                autoSubscribeAudio: true,
              ));
            }
            // Request audio focus now that call is connected (delayed to prevent
            // the foreground service from stealing focus away from the ringtone).
            unawaited(CallForegroundServiceManager.enableAudioFocus());
            _startCallTimer(); // Start call duration timer
            _syncOverlayState();
          },
          onUserOffline: (_, __, ___) {
            if (!_isSwitchingToVideo) _endCall();
          },
          onError: (code, msg) {
            debugPrint('Agora error: $code $msg');
          },
        ),
      );

      await _engine.setClientRole(role: ClientRoleType.clientRoleBroadcaster);

      await _engine.joinChannel(
        token: _token,
        channelId: _channel,
        uid: _localUid,
        options: const ChannelMediaOptions(
          publishMicrophoneTrack: false, // Keep mic OFF during IVR/ringtone
          autoSubscribeAudio: true,
        ),
      );

      _armOutgoingTimeout(_kOutgoingCallTimeout);
    } catch (e) {
      debugPrint('Init error: $e');
      _logCallDiag('start_call_exception', {'error': e.toString()});
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
        _logCallDiag('outgoing_timeout', {
          'duration_s': duration.inSeconds,
          'remote_accepted': _remoteAccepted,
        });
        if (_remoteAccepted && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Connection is slow. Please try calling again.'),
            ),
          );
        }
        if (widget.isOutgoingCall) {
          NotificationService.sendMissedCallNotification(
            callerId: widget.otherUserId,
            callerName: widget.currentUserName,
            senderId: widget.currentUserId,
          );
        }
        _endCall();
      }
    });
  }

  // ================= CALL TIMER =================
  void _startCallTimer() {
    _timeoutTimer?.cancel();
    _callActive = true;
    _syncOverlayState();

    // Show a running chronometer on the foreground-service notification so
    // it mirrors the in-app call timer.
    unawaited(CallForegroundServiceManager.markCallConnected(
      callType: 'audio',
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
    _logCallDiag('end_call_start', {
      'call_active': _callActive,
      'joined': _joined,
      'duration_s': _duration.inSeconds,
      'declined': _callDeclined,
    });
    _ending = true;
    final wasDeclined = _callDeclined;
    final wasNoAnswer = !_callActive && !_callDeclined;

    // Play the admin-configured "call ended" tone, if any. Strict custom-only:
    // silent when no URL is uploaded. Done before tearing down the ringtone
    // player below so we get our own dedicated short-shot player.
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
    _socketSwitchToVideoResponseSub?.cancel();
    _socketAcceptedSub = null;
    _socketRejectedSub = null;
    _socketEndedSub = null;
    _socketRingingSub = null;
    _socketUserOfflineSub = null;
    _socketBusySub = null;
    _socketBlockedSub = null;
    _socketAllAdminsBusySub = null;
    _socketFeatureDeniedSub = null;
    _socketSwitchToVideoResponseSub = null;

    await _stopRingtone();

    // If the call was never answered, notify the receiver to dismiss their incoming call screen.
    // Skip cancel when recipient was busy  -  no screen to dismiss.
    // Skip entirely when the call was blocked  -  the recipient never received the call.
    if (!_callActive &&
        !_recipientBusy &&
        !_callBlocked &&
        widget.isOutgoingCall &&
        _channel.isNotEmpty) {
      if (_remoteAccepted) {
        // The recipient already accepted, so treat this as a real call end to
        // release busy state immediately even if media never connected.
        SocketService().emitCallEnd(
          callerId: widget.currentUserId,
          recipientId: widget.otherUserId,
          channelName: _channel,
          callType: 'audio',
          duration: _duration.inSeconds,
        );
      } else {
        // Socket.IO (instant for online users)
        SocketService().emitCallCancel(
          recipientId: widget.otherUserId,
          callerId: widget.currentUserId,
          callerName: widget.currentUserName,
          channelName: _channel,
          callType: 'audio',
        );
        // No FCM 'call cancelled' push: the socket event dismisses the
        // incoming-call UI for online recipients. For offline recipients
        // the incoming-call FCM TTL (45s) expires on its own — sending an
        // extra cancel banner is just noise.
      }
    } else if (_callActive && _channel.isNotEmpty) {
      // Notify other party that call ended
      SocketService().emitCallEnd(
        callerId: widget.currentUserId,
        recipientId: widget.otherUserId,
        channelName: _channel,
        callType: 'audio',
        duration: _duration.inSeconds,
      );
    }

    // Navigate away FIRST so the user never sees stale/full-screen call UI.
    CallOverlayManager().reset();
    _dismissCallRoutes();

    // Persist call history in background so the hangup button always feels
    // instant even on slow networks.
    if (widget.isOutgoingCall &&
        _callHistoryId != null &&
        _callHistoryId!.isNotEmpty &&
        !_recipientBusy) {
      final callStatus = _callActive
          ? CallStatus.completed
          : wasDeclined
              ? CallStatus.declined
              : CallStatus.missed;
      unawaited(() async {
        await CallHistoryService.updateCallEnd(
          callId: _callHistoryId!,
          status: callStatus,
          duration: _duration.inSeconds,
        );
        await CallHistoryService.logCallMessageInChat(
          callerId: widget.currentUserId,
          callType: 'audio',
          callStatus: callStatus.toString().split('.').last,
          duration: _duration.inSeconds,
          chatRoomId: widget.chatRoomId,
          isAdminChat: widget.isAdminChat,
          adminChatSenderId: widget.isAdminChat ? widget.currentUserId : null,
          adminChatReceiverId:
              widget.isAdminChat ? widget.adminChatReceiverId : null,
          messageDocId: _channel.isNotEmpty ? 'call_$_channel' : null,
        );
      }());
    }

    // Show feedback snackbar after stack cleanup
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final scaffoldCtx = navigatorKey.currentContext;
      if (scaffoldCtx != null) {
        ScaffoldMessenger.of(scaffoldCtx).showSnackBar(
          SnackBar(
            content: Text(_buildCallEndMessage(
                wasDeclined: wasDeclined, wasNoAnswer: wasNoAnswer)),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    });

    // Release engine resources after navigation (fire-and-forget)
    unawaited(_releaseEngineAsync());
    unawaited(_stopForegroundService());
  }

  Future<void> _exit() async {
    CallOverlayManager().reset();
    _dismissCallRoutes();
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

  String _buildCallEndMessage(
      {required bool wasDeclined, required bool wasNoAnswer}) {
    if (_recipientBusy) return 'User is busy, please try again later';
    if (wasDeclined) return 'Call declined';
    if (wasNoAnswer) return 'No answer';
    return 'Call ended';
  }

  // ================= SWITCH TO VIDEO =================
  /// Sends a switch-to-video request to the other party.
  void _requestSwitchToVideo() {
    if (!_callActive || _isSwitchingToVideo || _ending) return;
    setState(() => _isSwitchingToVideo = true);
    _syncOverlayState();
    SocketService().emitSwitchToVideoRequest(
      recipientId: widget.otherUserId,
      requesterId: widget.currentUserId,
      channelName: _channel,
    );
  }

  /// Called when the other party accepts the switch.  Leaves the current
  /// Agora audio channel and opens the VideoCallScreen with the same channel.
  Future<void> _navigateToVideoCall() async {
    if (_ending || _navigatingToVideo) return;
    _navigatingToVideo = true;
    // Cancel all subscriptions so the audio call doesn't interfere with the
    // new video call.
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
    _socketSwitchToVideoResponseSub?.cancel();

    // Leave audio Agora channel so the video screen can join with video enabled.
    try {
      await _releaseEngineAsync();
    } catch (e) {
      debugPrint('Error releasing audio engine for video switch: $e');
    }

    CallOverlayManager().reset();
    unawaited(_stopForegroundService());

    if (!mounted) return;
    // Navigate to VideoCallScreen, replacing the current route.
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        settings: RouteSettings(name: activeCallRouteName),
        fullscreenDialog: true,
        builder: (_) => VideoCallScreen(
          currentUserId: widget.currentUserId,
          currentUserName: widget.currentUserName,
          currentUserImage: widget.currentUserImage,
          otherUserId: widget.otherUserId,
          otherUserName: widget.otherUserName,
          otherUserImage: widget.otherUserImage,
          isOutgoingCall: true,
          chatRoomId: widget.chatRoomId,
          isAdminChat: widget.isAdminChat,
          adminChatReceiverId: widget.adminChatReceiverId,
          forcedChannelName: _channel,
        ),
      ),
    );
  }

  /// Releases the Agora engine; safe to call fire-and-forget from dispose().
  Future<void> _releaseEngineAsync() async {
    if (!_engineInitialized || _engineReleaseInProgress) {
      _logCallDiag('engine_release_skip', {
        'initialized': _engineInitialized,
        'in_progress': _engineReleaseInProgress,
      });
      return;
    }
    _engineReleaseInProgress = true;
    _logCallDiag('engine_release_start');
    final shouldLeave = _joined;
    _joined = false;
    _engineInitialized = false;
    try {
      if (shouldLeave) await _engine.leaveChannel();
      await _engine.release();
    } catch (e) {
      debugPrint("Engine cleanup error: $e");
      _logCallDiag('engine_release_error', {'error': e.toString()});
    } finally {
      _engineReleaseInProgress = false;
      _logCallDiag('engine_release_done');
    }
  }

  Future<void> _startForegroundService() async {
    if (_channel.isEmpty) return;
    if (_foregroundServiceStarted) return;
    _foregroundServiceStarted = true;
    await CallForegroundServiceManager.startOngoingCall(
      callType: 'audio',
      otherUserName: widget.otherUserName,
      callId: _channel,
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

  // ================= ALL ADMINS BUSY DIALOG =================
  void _showAllAdminsBusyDialog(String message, String? audioUrl) {
    if (!mounted) return;

    // Play busy audio if available
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
      if (!hasConnection && _callActive) {
        // Auto-end if connectivity fully drops for too long
        Future.delayed(_kConnectivityLossTimeout, () {
          if (mounted && _connectionStatus != null) _endCall();
        });
      }
    });
  }

  // ================= UI =================
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
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: _callActive
                  ? [
                      const Color(0xFF080D18),
                      const Color(0xFF0D1829),
                      const Color(0xFF0A1624),
                    ]
                  : [
                      const Color(0xFF050B18),
                      const Color(0xFF0C1529),
                      const Color(0xFF101E35),
                    ],
            ),
          ),
          child: SafeArea(
            child: Stack(
              children: [
                Column(
                  children: [
                    // Top minimize button
                    Align(
                      alignment: Alignment.topRight,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 16, top: 12),
                        child: CallMinimizeButton(onPressed: _minimizeCall),
                      ),
                    ),
                    const SizedBox(height: 40),
                    // Main content
                    Expanded(
                      child: _callActive
                          ? _buildActiveCallUI()
                          : _buildOutgoingCallUI(),
                    ),
                  ],
                ),
                // Connectivity overlay banner
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: ConnectionStatusOverlay(message: _connectionStatus),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOutgoingCallUI() {
    return Column(
      children: [
        const SizedBox(height: 52),
        // Outgoing call badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
          decoration: BoxDecoration(
            color: const Color(0xFF29B6F6).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: const Color(0xFF29B6F6).withValues(alpha: 0.45),
              width: 1,
            ),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.phone_forwarded_rounded,
                  color: Color(0xFF29B6F6), size: 14),
              SizedBox(width: 6),
              Text(
                'Outgoing Voice Call',
                style: TextStyle(
                  color: Color(0xFF29B6F6),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _OutgoingPulseWidget(
                size: 148,
                child: _buildRecipientAvatar(148),
              ),
              const SizedBox(height: 36),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  _sanitizeName(widget.otherUserName),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 34,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                _getOutgoingStatusText(),
                style: TextStyle(
                  color: _recipientOffline
                      ? const Color(0xFFFF9800)
                      : const Color(0xFF78909C),
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 56),
          child: _buildOutgoingControls(),
        ),
      ],
    );
  }

  Widget _buildRecipientAvatar(double size) {
    final hasImage = widget.otherUserImage.isNotEmpty;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF1E3A5F),
        border: Border.all(
            color: Colors.white.withValues(alpha: 0.2), width: 2.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 24,
            spreadRadius: 4,
          ),
        ],
      ),
      child: ClipOval(
        child: hasImage
            ? Image.network(
                widget.otherUserImage,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Center(
                  child: Icon(Icons.phone_forwarded_rounded,
                      size: size * 0.45, color: Colors.white70),
                ),
              )
            : Center(
                child: Icon(Icons.phone_forwarded_rounded,
                    size: size * 0.45, color: Colors.white70),
              ),
      ),
    );
  }

  Widget _buildActiveCallUI() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const SizedBox(height: 40),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildRecipientAvatar(96),
              const SizedBox(height: 20),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF00C853).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.fiber_manual_record,
                        color: Color(0xFF00C853), size: 9),
                    SizedBox(width: 6),
                    Text(
                      'Connected',
                      style: TextStyle(
                        color: Color(0xFF00C853),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _sanitizeName(widget.otherUserName),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                _format(_duration),
                style: const TextStyle(
                  color: Color(0xFF69F0AE),
                  fontSize: 24,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 52),
          child: _buildActiveControls(),
        ),
      ],
    );
  }

  Widget _buildOutgoingControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _modernControlBtn(
            icon: _micMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
            color: _micMuted ? const Color(0xFFFF6F00) : Colors.white,
            onPressed: _callActive ? _toggleMute : null,
            label: _micMuted ? 'Unmute' : 'Mute',
            active: !_micMuted && _callActive,
          ),
          _modernCallBtn(
            icon: Icons.call_end,
            color: const Color(0xFFFF1744),
            onPressed: _endCall,
            size: 72,
            label: 'End Call',
          ),
          _modernControlBtn(
            icon: _speakerOn ? Icons.volume_up_rounded : Icons.volume_off_rounded,
            color: _speakerOn ? const Color(0xFF29B6F6) : Colors.white,
            onPressed: (_callActive || _isCallRinging) ? _toggleSpeaker : null,
            label: 'Speaker',
            active: _speakerOn,
          ),
        ],
      ),
    );
  }

  Widget _buildActiveControls() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _modernControlBtn(
                icon: _micMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                color: _micMuted ? const Color(0xFFFF6F00) : Colors.white,
                onPressed: _toggleMute,
                label: _micMuted ? 'Unmute' : 'Mute',
                active: !_micMuted,
              ),
              _modernCallBtn(
                icon: Icons.call_end,
                color: const Color(0xFFFF1744),
                onPressed: _endCall,
                size: 72,
                label: 'End Call',
              ),
              _modernControlBtn(
                icon: _speakerOn ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                color: _speakerOn ? const Color(0xFF29B6F6) : Colors.white,
                onPressed: _toggleSpeaker,
                label: 'Speaker',
                active: _speakerOn,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: _isSwitchingToVideo ? null : _requestSwitchToVideo,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            decoration: BoxDecoration(
              color: _isSwitchingToVideo
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.2)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isSwitchingToVideo
                      ? Icons.hourglass_empty
                      : Icons.videocam_rounded,
                  color: Colors.white.withValues(alpha: 0.65),
                  size: 17,
                ),
                const SizedBox(width: 8),
                Text(
                  _isSwitchingToVideo
                      ? 'Waiting for response...'
                      : 'Switch to Video',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.65),
                      fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _modernCallBtn({
    required IconData icon,
    required Color color,
    required VoidCallback? onPressed,
    double size = 72,
    String? label,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.45),
                  blurRadius: 22,
                  spreadRadius: 0,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: size * 0.44),
          ),
        ),
        if (label != null) ...[
          const SizedBox(height: 10),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }

  Widget _modernControlBtn({
    required IconData icon,
    required Color color,
    required VoidCallback? onPressed,
    bool active = false,
    String? label,
    double size = 62,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onPressed,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: active
                  ? color.withValues(alpha: 0.22)
                  : Colors.white.withValues(alpha: 0.1),
              shape: BoxShape.circle,
              border: Border.all(
                color: active
                    ? color.withValues(alpha: 0.65)
                    : Colors.white.withValues(alpha: 0.2),
                width: 1.5,
              ),
            ),
            child: Icon(
              icon,
              color: onPressed == null
                  ? Colors.white.withValues(alpha: 0.3)
                  : (active ? color : Colors.white.withValues(alpha: 0.8)),
              size: size * 0.45,
            ),
          ),
        ),
        if (label != null) ...[
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 12,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ],
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timeoutTimer?.cancel();
    _callTimer?.cancel();
    _responseSubscription?.cancel();
    _socketAcceptedSub?.cancel();
    _socketRejectedSub?.cancel();
    _socketEndedSub?.cancel();
    _socketRingingSub?.cancel();
    _socketUserOfflineSub?.cancel();
    _connectivitySubscription?.cancel();
    _socketBusySub?.cancel();
    _socketBlockedSub?.cancel();
    _socketAllAdminsBusySub?.cancel();
    _socketFeatureDeniedSub?.cancel();
    _socketSwitchToVideoResponseSub?.cancel();
    _busyAutoEndTimer?.cancel();
    _busyAutoEndSub?.cancel();
    // Force-stop any ringing/vibration even if teardown raced with route pop.
    unawaited(_stopRingtone());
    _vibrationTimer?.cancel();
    unawaited(_ringtonePlayer.dispose());
    // Release Agora engine if not already released by _endCall
    unawaited(_releaseEngineAsync());
    unawaited(_stopForegroundService());
    super.dispose();
  }

  String _format(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
}

/// Teal-colored 3-ring pulse for outgoing calls.
class _OutgoingPulseWidget extends StatefulWidget {
  final Widget child;
  final double size;
  const _OutgoingPulseWidget({required this.child, this.size = 148});

  @override
  State<_OutgoingPulseWidget> createState() => _OutgoingPulseWidgetState();
}

class _OutgoingPulseWidgetState extends State<_OutgoingPulseWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _ring(double phase) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) {
        final v = (_controller.value + phase) % 1.0;
        final scale = 1.0 + v * 0.65;
        final opacity = ((1.0 - v) * 0.38).clamp(0.0, 1.0);
        return Transform.scale(
          scale: scale,
          child: Opacity(
            opacity: opacity,
            child: Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: const Color(0xFF29B6F6), width: 2),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        _ring(0.0),
        _ring(0.33),
        _ring(0.66),
        widget.child,
      ],
    );
  }
}
