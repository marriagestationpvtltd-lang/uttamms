import 'dart:async';
import 'dart:convert';
import 'dart:math';
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
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    if (dart.library.html) 'package:ms2026/utils/web_local_notifications_stub.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:provider/provider.dart';
import '../core/user_state.dart';
import '../Chat/call_overlay_manager.dart';
import '../navigation/app_navigation.dart';
import '../Package/PackageScreen.dart';
import '../pushnotification/pushservice.dart';
import '../service/socket_service.dart';
import '../service/sound_settings_service.dart';
import '../service/app_sound_tone_service.dart';
import '../service/device_sound_policy_service.dart';
import '../service/audio_manager.dart';
import 'tokengenerator.dart';
import 'call_history_model.dart';
import 'call_history_service.dart';
import 'call_foreground_service.dart';
import 'incomingvideocall.dart';
import '../utils/image_utils.dart';

class IncomingCallScreen extends StatefulWidget {
  final Map<String, dynamic> callData;
  const IncomingCallScreen({super.key, required this.callData});

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen> {
  late RtcEngine _engine;
  late final AudioPlayer _ringtonePlayer;
  bool _engineInitialized = false;

  int _localUid = 0;
  late String _channel;
  late String _callerId;
  late String _callerName;
  late String _recipientName;

  bool _joined = false;
  bool _callActive = false;
  bool _micMuted = false;
  bool _speakerOn = false;
  bool _processing = false;
  bool _foregroundServiceStarted = false;
  bool _ending = false;
  bool _connecting = false;
  bool _engineReleaseInProgress = false;
  bool _isSwitchingToVideo = false; // true while transitioning to a video call
  bool _videoSwitchDialogActive =
      false; // true while the switch-to-video dialog is on screen

  Timer? _ringTimer;
  Timer? _callTimer;
  Timer? _connectionFailureTimer;
  Timer? _noPeerJoinTimer;
  bool _noPeerJoinRetryUsed = false;
  Duration _duration = Duration.zero;
  StreamSubscription<Map<String, dynamic>>? _cancelSubscription;
  StreamSubscription<Map<String, dynamic>>? _socketCancelSubscription;
  StreamSubscription<Map<String, dynamic>>? _socketEndedSubscription;
  StreamSubscription<Map<String, dynamic>>? _socketSwitchToVideoSub;

  bool _isPlayingRingtone = false;
  Timer? _vibrationTimer; // Repeating vibration while ringing
  bool _allowIncomingRingtone = true;

  // Call history tracking
  String? _callHistoryId;
  String _currentUserId = '';
  String _currentUserName = '';
  String _currentUserImage = '';
  String _callerImageUrl = '';
  bool _pendingEmitRinging = false;
  bool _callAcceptSignalSent = false;
  String _diagSessionId = '';
  int? _acceptStartedAtMs;
  static const int _kEarlyTeardownIgnoreMs = 35000;
  static const int _kRemoteOfflineEndDelayMs = 8000;
  static const int _kConnectionFailedEndDelayMs = 10000;
  static const int _kMaxAcceptRetryCount = 1;
  static const int _kAcceptRetryDelayMs = 800;
  static const int _kTokenFetchTimeoutMs = 12000;
  static const int _kJoinCallTimeoutMs = 15000;
  static const int _kNoPeerJoinTimeoutMs = 25000;
  int _acceptRetryCount = 0;

  void _logCallDiag(String event, [Map<String, Object?> extra = const {}]) {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final parts = <String>[
      'event=$event',
      'ts=$ts',
      'session=${_diagSessionId.isEmpty ? '-' : _diagSessionId}',
      'channel=${_channel.isEmpty ? '-' : _channel}',
      'caller=${_callerId.isEmpty ? '-' : _callerId}',
      'recipient=${_currentUserId.isEmpty ? '-' : _currentUserId}',
    ];
    extra.forEach((k, v) => parts.add('$k=${v ?? 'null'}'));
    debugPrint('CALL_DIAG_IN_AUDIO ${parts.join(' ')}');
  }

  @override
  void initState() {
    super.initState();
    // Prevent duplicate ringtone from compact incoming overlay.
    IncomingCallOverlayManager().dismiss();
    // Cancel the system notification immediately so the heads-up banner
    // does not overlap the full-screen call UI (Android fires both when
    // fullScreenIntent: true and the screen is already on).
    _cancelCallNotification();
    AudioManager.instance.stopCallRingtone();
    _ringtonePlayer = AudioPlayer();
    _ringtonePlayer.setReleaseMode(ReleaseMode.loop);
    WakelockPlus.enable();
    _parseData();
    _localUid = Random().nextInt(999998) + 1;
    _ringTimer = Timer(const Duration(seconds: 60), _missedCall);
    _loadUserDataAndLogCall();
    _listenForCallCancelled();

    // Start the looping ringtone after the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_allowIncomingRingtone || _processing || _connecting || _ending) {
        return;
      }
      _playRingtone();
      // Notify the caller that this device is actively ringing.
      // This is a fallback for FCM-delivered calls where the server could not
      // confirm socket presence at call_invite time.
      if (_callerId.isNotEmpty && _currentUserId.isNotEmpty) {
        unawaited(() async {
          await _ensureSocketConnectedForCurrentUser();
          SocketService().emitCallRinging(
            callerId: _callerId,
            recipientId: _currentUserId,
            channelName: _channel,
            callType: 'audio',
          );
        }());
      } else {
        // _currentUserId may not be loaded yet; emit after user data is ready
        _pendingEmitRinging = true;
      }
    });
  }

  void _cancelCallNotification() {
    try {
      // Cancel the audio call notification (ID: 1001)
      final plugin = FlutterLocalNotificationsPlugin();
      plugin.cancel(1001);
      // Also cancel the OS-side banner that the FCM SDK posted from
      // the call push's `notification` block. Its internal id is
      // opaque so we cancel by tag (= channelName) via native API.
      if (_channel.isNotEmpty) {
        // ignore: unawaited_futures
        CallForegroundServiceManager.cancelNotificationsByTag(_channel);
      }
      // Belt-and-braces: clear any other lingering call banners
      // (e.g. when the same recipient gets a stray duplicate push).
      // ignore: unawaited_futures
      CallForegroundServiceManager.cancelAllCallBanners();
      debugPrint('✅ Cancelled call notification after screen mounted');
    } catch (e) {
      debugPrint('Error cancelling call notification: $e');
    }
  }

  Future<void> _playRingtone() async {
    if (!_allowIncomingRingtone || _processing || _connecting || _ending) {
      return;
    }
    try {
      _isPlayingRingtone = true;

      final canPlay = await DeviceSoundPolicyService.canPlayInAppSound();
      if (!canPlay) {
        _isPlayingRingtone = false;
        debugPrint('📴 Phone silent/vibrate/DND – skipping incoming ringtone');
        return;
      }

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

      if (!SoundSettingsService.instance.callSoundEnabled) {
        debugPrint('📴 Call sound disabled by user – skipping ringtone');
        return;
      }

      final customUrl = await AppSoundToneService.instance
          .customUrl(AppSoundToneType.incomingCall);

      if (customUrl.isNotEmpty) {
        try {
          await _ringtonePlayer.setReleaseMode(ReleaseMode.loop);
          await _ringtonePlayer.play(UrlSource(customUrl));
          debugPrint('✅ Incoming custom ringtone started: $customUrl');
          return;
        } catch (e) {
          debugPrint('⚠️ Custom incoming ringtone failed: $e');
          AppSoundToneService.instance
              .reportBrokenRemoteTone(AppSoundToneType.incomingCall, customUrl);
        }
      }

      // No custom URL (or playback failed) → device system ringtone.
      if (!kIsWeb) {
        await FlutterRingtonePlayer().play(
          android: AndroidSounds.ringtone,
          looping: true,
        );
        debugPrint('✅ Incoming system default ringtone started');
      }
    } catch (e) {
      debugPrint('Error playing incoming call ringtone: $e');
    }
  }

  Future<void> _stopRingtone() async {
    try {
      _isPlayingRingtone = false;
      _vibrationTimer?.cancel();
      _vibrationTimer = null;
      await _ringtonePlayer.stop();
      if (!kIsWeb) {
        await FlutterRingtonePlayer().stop();
      }
      debugPrint('✅ Incoming call ringtone stopped');
    } catch (e) {
      debugPrint('Error stopping incoming call ringtone: $e');
    }
  }

  Future<void> _silenceIncomingAlerts({bool permanently = false}) async {
    if (permanently) {
      _allowIncomingRingtone = false;
    }
    _ringTimer?.cancel();
    IncomingCallOverlayManager().dismiss();
    await _stopRingtone();
    // Overlay ringtone is driven by AudioManager; force-stop it as well.
    await AudioManager.instance.stopCallRingtone();
  }

  void _listenForCallCancelled() {
    // FCM path (for background/offline)
    _cancelSubscription = NotificationService.callResponses.listen((data) {
      final type = data['type']?.toString();
      if (type == 'call_cancelled' || type == 'call_ended') {
        final channelName = data['channelName']?.toString();
        if (channelName == _channel) {
          if (_shouldIgnoreEarlyTeardown()) {
            _logCallDiag('ignore_early_teardown_fcm', {'type': type});
            return;
          }
          if (!_ending) _endCall();
        }
      }
    });

    // Socket.IO path (real-time for online users)
    _socketCancelSubscription = SocketService().onCallCancelled.listen((data) {
      final channelName = data['channelName']?.toString();
      if (channelName == _channel) {
        if (_shouldIgnoreEarlyTeardown()) {
          _logCallDiag(
              'ignore_early_teardown_socket', {'type': 'call_cancelled'});
          return;
        }
        if (!_ending) _endCall();
      }
    });
    _socketEndedSubscription = SocketService().onCallEnded.listen((data) {
      final channelName = data['channelName']?.toString();
      if (channelName == _channel) {
        if (_shouldIgnoreEarlyTeardown()) {
          _logCallDiag('ignore_early_teardown_socket', {'type': 'call_ended'});
          return;
        }
        if (!_ending) _endCall();
      }
    });

    // Listen for audio→video switch request from the other party.
    _socketSwitchToVideoSub =
        SocketService().onSwitchToVideoRequest.listen((data) {
      final channelName = data['channelName']?.toString();
      if (channelName != _channel) return;
      if (!_callActive || _ending || !mounted) return;
      if (_videoSwitchDialogActive || _isSwitchingToVideo) {
        return; // dialog already shown or navigating
      }
      _showSwitchToVideoDialog(data);
    });
  }

  bool _shouldIgnoreEarlyTeardown() {
    if (_ending || _callActive) return false;
    final startedAt = _acceptStartedAtMs;
    if (startedAt == null) return false;
    final elapsed = DateTime.now().millisecondsSinceEpoch - startedAt;
    return elapsed >= 0 && elapsed < _kEarlyTeardownIgnoreMs;
  }

  Future<void> _loadUserDataAndLogCall() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataString = prefs.getString('user_data');
      if (userDataString != null) {
        final userData = jsonDecode(userDataString);
        _currentUserId = userData['id']?.toString() ?? '';
        _currentUserName = userData['name']?.toString() ?? '';
        _currentUserImage = userData['image']?.toString() ?? '';

        // If emitCallRinging was deferred (user data wasn't ready at initState),
        // send it now.
        if (_pendingEmitRinging &&
            _callerId.isNotEmpty &&
            _currentUserId.isNotEmpty) {
          _pendingEmitRinging = false;
          await _ensureSocketConnectedForCurrentUser();
          SocketService().emitCallRinging(
            callerId: _callerId,
            recipientId: _currentUserId,
            channelName: _channel,
            callType: 'audio',
          );
        }

        // Log call history only for group/conference calls.
        // Regular 1-on-1 calls are logged by the caller (OutgoingCall.dart)
        // to prevent duplicate entries in call history.
        final isConference = widget.callData['isConferenceCall'] == true ||
            widget.callData['isConferenceCall'] == 'true';
        if (isConference) {
          _callHistoryId = await CallHistoryService.logCall(
            callerId: _callerId,
            callerName: _callerName,
            callerImage: widget.callData['callerImage'] ?? '',
            recipientId: _currentUserId,
            recipientName: _currentUserName,
            recipientImage: _currentUserImage,
            callType: CallType.audio,
            initiatedBy: _callerId,
            isGroup: true,
          );
        }
      }
    } catch (e) {
      debugPrint('Error loading user data for call history: $e');
    }
  }

  Future<bool> _ensureCurrentUserLoaded() async {
    if (_currentUserId.isNotEmpty) return true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataString = prefs.getString('user_data');
      if (userDataString != null && userDataString.isNotEmpty) {
        final userData = jsonDecode(userDataString);
        _currentUserId = userData['id']?.toString() ??
            userData['userid']?.toString() ??
            userData['userId']?.toString() ??
            '';
        _currentUserName = userData['name']?.toString() ?? '';
        _currentUserImage = userData['image']?.toString() ?? '';
      }
      if (_currentUserId.isEmpty) {
        _currentUserId = widget.callData['recipientId']?.toString() ??
            widget.callData['recipientUid']?.toString() ??
            '';
      }
      return _currentUserId.isNotEmpty;
    } catch (_) {
      if (_currentUserId.isEmpty) {
        _currentUserId = widget.callData['recipientId']?.toString() ??
            widget.callData['recipientUid']?.toString() ??
            '';
      }
      return _currentUserId.isNotEmpty;
    }
  }

  Future<void> _ensureSocketConnectedForCurrentUser() async {
    final hasUser = await _ensureCurrentUserLoaded();
    if (!hasUser) return;

    final socketService = SocketService();
    if (socketService.isConnected &&
        socketService.currentUserId == _currentUserId) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('bearer_token');
    socketService.connect(_currentUserId, token: token);

    try {
      await socketService.onConnectionChange
          .firstWhere((connected) => connected)
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      // FCM fallback still handles call signaling if socket connect is delayed.
    }
  }

  String _buildReceiverCallerDisplayName({
    required String callerId,
    required String callerName,
  }) {
    final compactId = callerId.trim().replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    String memberCode = compactId;
    if (RegExp(r'^\d+$').hasMatch(compactId)) {
      memberCode = 'ms$compactId';
    } else if (RegExp(r'^ms\d+$', caseSensitive: false).hasMatch(compactId)) {
      memberCode = 'ms${compactId.substring(2)}';
    }

    final nameParts = callerName
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .where((part) => !part.startsWith('#'))
        .where((part) {
      final compactPart = part.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
      return compactPart.isNotEmpty &&
          !RegExp(r'^(ms)?\d+$', caseSensitive: false).hasMatch(compactPart);
    }).toList();
    final lastName = nameParts.isNotEmpty ? nameParts.last : 'Member';

    if (memberCode.isEmpty) return lastName;
    return '$memberCode $lastName';
  }

  void _parseData() {
    try {
      // CRITICAL: These values come from the FCM notification payload, which
      // may have missing or null keys. Use null coalescing (??) with sensible
      // fallbacks to prevent null assignment errors to non-nullable `late String`
      // variables. A null assignment here crashes initState and prevents the
      // entire screen from rendering (no build() call), leaving the user with
      // a blank screen and no Accept/Reject buttons.
      _channel = widget.callData['channelName']?.toString() ?? '';
      if (_channel.isEmpty) {
        debugPrint(
            '⚠️ CRITICAL: Missing channelName in callData – call cannot proceed');
      }

      _callerId = widget.callData['callerId']?.toString() ?? '';
      if (_callerId.isEmpty) {
        debugPrint(
            '⚠️ CRITICAL: Missing callerId in callData – call cannot proceed');
      }

      final rawCallerImage = widget.callData['callerImage']?.toString() ??
          widget.callData['caller_image']?.toString() ??
          widget.callData['senderImage']?.toString() ??
          widget.callData['profile_picture']?.toString() ??
          '';
      _callerImageUrl = resolveApiImageUrl(rawCallerImage);

      final rawCallerName = widget.callData['callerName']?.toString() ?? '';
      final callerRole = widget.callData['callerRole']?.toString() ?? '';
      final isAdminCaller = callerRole == 'admin' || _callerId == '1';

      if (isAdminCaller) {
        // Admin → user calls: display the real admin name (e.g. "Ramesh")
        // exactly as the server provided it.  No member-code prefixing.
        _callerName =
            rawCallerName.trim().isNotEmpty ? rawCallerName.trim() : 'Admin';
      } else {
        _callerName = rawCallerName.trim().isNotEmpty
            ? _buildReceiverCallerDisplayName(
                callerId: _callerId,
                callerName: rawCallerName,
              )
            : 'Caller';
      }

      if (_callerName.isEmpty) {
        debugPrint(
            '⚠️ WARNING: Unable to determine caller name – using default');
        _callerName = 'Incoming Call';
      }

      _recipientName = widget.callData['recipientName']?.toString() ?? 'You';
      _currentUserId = widget.callData['recipientId']?.toString() ??
          widget.callData['recipientUid']?.toString() ??
          _currentUserId;

      debugPrint(
          'Parsed incoming call: caller=$_callerId, channel=$_channel, recipient=$_currentUserId');
    } catch (e) {
      debugPrint('❌ CRITICAL ERROR in _parseData: $e – screen will not render');
      // Set safe defaults so late variables are initialized
      _channel = '';
      _callerId = '';
      _callerName = 'Incoming Call';
      _recipientName = 'You';
    }
  }

  void _initializeOverlay() {
    CallOverlayManager().startCall(
      callType: 'audio',
      otherUserName: _callerName,
      otherUserId: _callerId,
      currentUserId: '',
      currentUserName: _recipientName,
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
    CallOverlayManager().updateCallState(
      statusText: _callActive ? 'Connected' : 'Incoming call',
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

  // ================= ACCEPT CALL =================

  /// Returns true if the current user (recipient) is a free/unpaid member
  /// and the call is a user-to-user call (not from admin).
  /// On free plan, the call accept is blocked with an upgrade prompt.
  Future<bool> _blockIfFreeUser() async {
    final callerRole = widget.callData['callerRole']?.toString() ?? '';
    final callerId = widget.callData['callerId']?.toString() ?? _callerId;
    final recipientId = widget.callData['recipientId']?.toString() ??
        widget.callData['receiverId']?.toString() ??
        widget.callData['adminId']?.toString() ??
        '';
    final isAdminSupportCall = callerRole == 'admin' ||
        callerId == '1' ||
        recipientId == '1' ||
        _currentUserId == '1';
    if (isAdminSupportCall) {
      return false; // admin support calls are always allowed
    }

    try {
      if (!mounted) return false;
      // Use the global UserState instead of making a separate API call.
      // UserState is refreshed on app start and kept in sync by all screens
      // that call masterdata.php, so this value is always up to date.
      var canAudioCall = context.read<UserState>().hasFeature('audio_call');
      bool refreshedForGate = false;
      if (!canAudioCall) {
        refreshedForGate = await _refreshUserStateForCallGate();
        if (refreshedForGate && mounted) {
          canAudioCall = context.read<UserState>().hasFeature('audio_call');
        }
      }
      if (canAudioCall) return false;

      // If live refresh failed, avoid rejecting based on potentially stale
      // local cache; backend call gate remains the source of truth.
      if (!refreshedForGate) {
        debugPrint(
            'Call gate: skipping local package block (state refresh failed).');
        return false;
      }

      // Avoid false declines when feature state is stale/unavailable.
      // Block only if we can confidently determine package lock.
      final shouldBlock =
          await _shouldBlockForPackageLock(requiredFeature: 'audio_call');
      if (!shouldBlock) {
        debugPrint(
            'Call gate: allowing incoming audio accept (feature state uncertain).');
        return false;
      }

      // Free user – determine the userId for the reject event.
      String userId = _currentUserId;
      if (userId.isEmpty) {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString('user_data');
        if (raw != null) {
          final data = jsonDecode(raw);
          userId = data['id']?.toString() ??
              data['userid']?.toString() ??
              data['userId']?.toString() ??
              '';
        }
      }
      if (userId.isEmpty) return false; // unknown user — allow the call

      _ringTimer?.cancel();
      await _stopRingtone();
      // Notify caller that the call was not accepted
      SocketService().emitCallReject(
        callerId: _callerId,
        recipientId: userId,
        recipientName: _recipientName,
        channelName: _channel,
        callType: 'audio',
        reasonCode: 'feature_locked',
        reasonMessage:
            'Call rejected: receiver package does not include audio calling.',
      );
      _showUpgradeCallDialog();
      return true;
    } catch (e) {
      debugPrint('Membership check error: $e');
    }
    return false;
  }

  Future<bool> _refreshUserStateForCallGate() async {
    try {
      final hasUser = await _ensureCurrentUserLoaded();
      if (!hasUser) return false;
      final uid = int.tryParse(_currentUserId);
      if (uid == null || !mounted) return false;
      await context.read<UserState>().refresh(uid);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _shouldBlockForPackageLock({
    required String requiredFeature,
  }) async {
    try {
      if (mounted) {
        final state = context.read<UserState>();
        if (state.hasFeature(requiredFeature)) return false;
        if (!state.hasPackage) return true;
        return false;
      }

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('user_data');
      if (raw == null || raw.isEmpty) return false;

      final data = jsonDecode(raw);
      final usertype = (data['usertype'] ?? '').toString().toLowerCase();
      final featuresRaw = data['features'];

      bool? explicitFeature;
      if (featuresRaw is Map) {
        final key = requiredFeature.toLowerCase();
        if (featuresRaw.containsKey(key)) {
          final value = featuresRaw[key];
          if (value is bool) {
            explicitFeature = value;
          } else if (value is num) {
            explicitFeature = value == 1;
          } else if (value is String) {
            final v = value.trim().toLowerCase();
            explicitFeature =
                v == '1' || v == 'true' || v == 'yes' || v == 'enabled';
          }
        }
      }

      if (explicitFeature == true) return false;
      if (explicitFeature == false) return true;

      // If package is paid but explicit feature is missing, fail open.
      if (usertype == 'paid') return false;

      // For free users with no explicit feature grant, block.
      return usertype == 'free';
    } catch (_) {
      // On parse/read errors, fail open to prevent false declines.
      return false;
    }
  }

  void _showUpgradeCallDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              colors: [Color(0xFFff0000), Color(0xFF2575FC)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.phone_locked_rounded,
                    color: Colors.white, size: 36),
              ),
              const SizedBox(height: 20),
              const Text(
                'Upgrade Your Package',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                'This feature is available in Premium Plan.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _end();
                      },
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Close',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context); // close dialog
                        _end().then((_) {
                          navigatorKey.currentState?.push(
                            MaterialPageRoute(
                                builder: (_) => SubscriptionPage()),
                          );
                        });
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Upgrade',
                          style: TextStyle(
                              color: Color(0xFFff0000),
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _acceptCall() async {
    if (_processing) return;
    if (!mounted) return;
    // Stop every possible ringtone/vibration source immediately on accept.
    _allowIncomingRingtone = false;
    unawaited(_silenceIncomingAlerts(permanently: true));
    // Remove BOTH the FCM-delivered OS banner and our local heads-up so
    // the small accept/decline notification cannot linger behind the
    // full-screen call UI after the user taps Accept.
    _cancelCallNotification();
    _diagSessionId = _diagSessionId.isEmpty
        ? 'ina_${DateTime.now().millisecondsSinceEpoch}'
        : _diagSessionId;
    _acceptStartedAtMs = DateTime.now().millisecondsSinceEpoch;
    _logCallDiag('accept_tap');

    // Show connecting UI immediately for instant feedback
    setState(() {
      _processing = true;
      _connecting = true;
    });

    // Block free users from accepting user-to-user calls
    if (await _blockIfFreeUser()) {
      if (mounted) {
        setState(() {
          _processing = false;
          _connecting = false;
        });
      }
      return;
    }

    try {
      await _silenceIncomingAlerts(permanently: true);

      final hasUser = await _ensureCurrentUserLoaded();
      if (!hasUser) {
        _logCallDiag('accept_fail_session_missing');
        await _notifyAcceptFailure(
          reasonCode: 'session_missing',
          reasonMessage: 'Call failed: receiver session is not available.',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('User session missing. Please login again.')),
          );
          setState(() {
            _processing = false;
            _connecting = false;
          });
        }
        await _end();
        return;
      }
      await _ensureSocketConnectedForCurrentUser();

      // Signal acceptance immediately (admin-like behavior) so caller-side
      // timeout/cancel races are avoided while Agora setup is in progress.
      if (!(widget.callData['isConferenceCall'] == true ||
          widget.callData['isConferenceCall'] == 'true')) {
        await _emitCallAcceptIfNeeded();
      }

      if (!(await Permission.microphone.request()).isGranted) {
        await _notifyAcceptFailure(
          reasonCode: 'permission_denied',
          reasonMessage: 'Call rejected: microphone permission denied.',
        );
        if (mounted) {
          setState(() {
            _processing = false;
            _connecting = false;
          });
        }
        await _end();
        return;
      }

      // Token
      final token = await AgoraTokenService.getToken(
        channelName: _channel,
        uid: _localUid,
        userId: _currentUserId,
        callType: 'audio',
      ).timeout(const Duration(milliseconds: _kTokenFetchTimeoutMs));
      _logCallDiag('token_ok', {
        'latency_ms': _acceptStartedAtMs == null
            ? null
            : DateTime.now().millisecondsSinceEpoch - _acceptStartedAtMs!,
      });

      // Engine
      _engine = createAgoraRtcEngine();
      await _engine.initialize(RtcEngineContext(
        appId: AgoraTokenService.appId,
        channelProfile: ChannelProfileType.channelProfileCommunication,
      ));
      _engineInitialized = true;

      // Mirror the stable outgoing-call path: keep audio disabled until the
      // channel join succeeds so the native stack does not race with teardown
      // of the ringtone/audio-focus state on accept.
      await _engine.disableAudio();

      _engine.registerEventHandler(
        RtcEngineEventHandler(
          onJoinChannelSuccess: (_, __) {
            _acceptRetryCount = 0;
            if (mounted) setState(() => _joined = true);
            // Agora is now ready; enable local audio and microphone publish.
            unawaited(() async {
              if (!_engineInitialized) return;
              await _engine.enableAudio();
              await _engine.setEnableSpeakerphone(_speakerOn);
              await _engine.updateChannelMediaOptions(
                const ChannelMediaOptions(
                  publishMicrophoneTrack: true,
                  autoSubscribeAudio: true,
                ),
              );
            }()
                .catchError(
              (e) {
                debugPrint('incoming accept post-join audio setup error: $e');
                return null;
              },
            ));
            _noPeerJoinTimer?.cancel();
            _noPeerJoinRetryUsed = false;
            _noPeerJoinTimer = Timer(
              const Duration(milliseconds: _kNoPeerJoinTimeoutMs),
              () {
                if (_ending || _callActive) return;
                if (!_noPeerJoinRetryUsed) {
                  _noPeerJoinRetryUsed = true;
                  _logCallDiag('no_peer_join_retry', {
                    'retry_after_ms': _kNoPeerJoinTimeoutMs,
                  });
                  _noPeerJoinTimer = Timer(
                    const Duration(milliseconds: _kNoPeerJoinTimeoutMs),
                    () {
                      if (_ending || _callActive) return;
                      _logCallDiag('no_peer_join_timeout');
                      unawaited(_notifyAcceptFailure(
                        reasonCode: 'peer_join_timeout',
                        reasonMessage:
                            'Call failed: other participant did not join in time.',
                      ));
                      _endCall();
                    },
                  );
                  return;
                }
                _logCallDiag('no_peer_join_timeout');
                unawaited(_notifyAcceptFailure(
                  reasonCode: 'peer_join_timeout',
                  reasonMessage:
                      'Call failed: other participant did not join in time.',
                ));
                _endCall();
              },
            );
            _logCallDiag('agora_join_success', {
              'latency_ms': _acceptStartedAtMs == null
                  ? null
                  : DateTime.now().millisecondsSinceEpoch - _acceptStartedAtMs!,
            });
            unawaited(_startForegroundService());
            // Request audio focus once the call is confirmed connected on our side.
            unawaited(CallForegroundServiceManager.enableAudioFocus());
            // setEnableSpeakerphone must be called after joining the channel (Agora SDK v4.x)
            unawaited(_engine.setEnableSpeakerphone(_speakerOn).catchError(
                (e) => debugPrint('setEnableSpeakerphone error: $e')));

            // Notify caller AFTER successfully joining Agora channel
            // This prevents race condition where caller receives accept before recipient joins
            if (widget.callData['isConferenceCall'] == true ||
                widget.callData['isConferenceCall'] == 'true') {
              // Conference call: emit participant_call_accept so admin receives
              // participant_accepted_call without disrupting the original call.
              SocketService().emitParticipantCallAccept(
                adminId: _callerId,
                channelName: _channel,
                acceptedById: _currentUserId,
                callType: 'audio',
                existingParticipantId:
                    widget.callData['existingParticipantId']?.toString(),
              );
            } else {
              // Non-conference calls send call_accept once at accept-tap time.
              // Avoid duplicate re-send here because it can create teardown races.
              unawaited(NotificationService.sendCallResponseNotification(
                callerId: _callerId,
                recipientName: _recipientName,
                accepted: true,
                recipientUid: _localUid.toString(),
                channelName: _channel,
              ));
            }
          },
          onUserJoined: (_, uid, __) {
            _connectionFailureTimer?.cancel();
            _noPeerJoinTimer?.cancel();
            _logCallDiag('remote_joined', {'remote_uid': uid});
            if (mounted) {
              setState(() {
                _callActive = true;
                _connecting = false;
              });
            }
            _startCallTimer();
            _syncOverlayState();
          },
          onUserOffline: (_, __, ___) {
            if (_isSwitchingToVideo || _ending) return;
            // Ignore transient offline events before the call is actually active.
            if (!_callActive && !_joined) return;
            _connectionFailureTimer?.cancel();
            _connectionFailureTimer = Timer(
                const Duration(milliseconds: _kRemoteOfflineEndDelayMs), () {
              if (_isSwitchingToVideo || _ending) return;
              if (_callActive) {
                _endCall();
              }
            });
          },
          onError: (c, m) {
            debugPrint('Agora error $c $m');
            if (_isFatalAgoraError(c, m) && !_ending) {
              unawaited(_notifyAcceptFailure(
                reasonCode: 'agora_error',
                reasonMessage: 'Call failed during connection setup.',
              ));
              _endCall();
            }
          },
          onConnectionStateChanged: (connection, state, reason) {
            debugPrint('Incoming call state: $state, reason: $reason');
            _logCallDiag('conn_state', {
              'state': state.name,
              'reason': reason.name,
              'joined': _joined,
              'call_active': _callActive,
            });
            if (_ending) return;

            if (state == ConnectionStateType.connectionStateConnected ||
                state == ConnectionStateType.connectionStateReconnecting ||
                state == ConnectionStateType.connectionStateConnecting) {
              _connectionFailureTimer?.cancel();
              return;
            }

            if (state == ConnectionStateType.connectionStateFailed) {
              // Some devices briefly emit FAILED during route/network transition.
              // Wait a bit before ending so fast recoveries can still connect.
              _connectionFailureTimer?.cancel();
              _connectionFailureTimer = Timer(
                  const Duration(milliseconds: _kConnectionFailedEndDelayMs),
                  () {
                if (_ending || _callActive || _joined) return;
                _logCallDiag('conn_failed_timeout');
                unawaited(_notifyAcceptFailure(
                  reasonCode: 'connection_failed',
                  reasonMessage:
                      'Call failed: network/channel connection error.',
                ));
                _endCall();
              });
            }
          },
        ),
      );

      await _engine.setClientRole(role: ClientRoleType.clientRoleBroadcaster);
      await _engine
          .joinChannel(
            token: token,
            channelId: _channel,
            uid: _localUid,
            options: const ChannelMediaOptions(
              autoSubscribeAudio: true,
              publishMicrophoneTrack: false,
            ),
          )
          .timeout(const Duration(milliseconds: _kJoinCallTimeoutMs));

      // Keep connecting state (already set at the beginning) until remote joins
      _initializeOverlay();
    } catch (e) {
      debugPrint('Accept error $e');
      _logCallDiag('accept_exception', {'error': e.toString()});
      if (_isRetryableAgoraAcceptError(e) &&
          _acceptRetryCount < _kMaxAcceptRetryCount &&
          mounted &&
          !_ending) {
        _acceptRetryCount += 1;
        _logCallDiag('accept_retry_scheduled', {
          'attempt': _acceptRetryCount,
          'delay_ms': _kAcceptRetryDelayMs,
        });
        await _releaseEngineAsync();
        if (mounted) {
          setState(() {
            _processing = false;
            _connecting = true;
          });
        }
        await Future.delayed(
            const Duration(milliseconds: _kAcceptRetryDelayMs));
        if (mounted && !_ending) {
          unawaited(_acceptCall());
        }
        return;
      }
      final failure = _deriveAcceptFailureFromError(e);
      if (failure != null) {
        await _notifyAcceptFailure(
          reasonCode: failure['code']!,
          reasonMessage: failure['message']!,
        );
      }
      if (mounted) {
        setState(() {
          _processing = false;
          _connecting = false;
        });
      }
      await _end();
    }
  }

  Future<void> _emitCallAcceptIfNeeded({bool forceResend = false}) async {
    if (_callAcceptSignalSent && !forceResend) return;
    final hasUser = await _ensureCurrentUserLoaded();
    if (!hasUser ||
        _currentUserId.isEmpty ||
        _callerId.isEmpty ||
        _channel.isEmpty) {
      return;
    }

    SocketService().emitCallAccept(
      callerId: _callerId,
      recipientId: _currentUserId,
      recipientName: _recipientName,
      recipientUid: _localUid.toString(),
      channelName: _channel,
      callType: 'audio',
    );
    _callAcceptSignalSent = true;
    _logCallDiag(forceResend ? 'accept_signal_resent' : 'accept_signal_sent');
  }

  Future<void> _notifyAcceptFailure({
    required String reasonCode,
    required String reasonMessage,
  }) async {
    if (_callActive || _ending) return;
    final isConference = widget.callData['isConferenceCall'] == true ||
        widget.callData['isConferenceCall'] == 'true';
    if (isConference) return;
    final hasUser = await _ensureCurrentUserLoaded();
    if (!hasUser || _currentUserId.isEmpty) return;

    // CRITICAL: Guard against empty channel/callerId to prevent silent socket failures
    if (_callerId.isEmpty || _channel.isEmpty) {
      debugPrint(
          '⚠️ Cannot notify accept failure: missing channel ($_channel) or callerId ($_callerId)');
      return;
    }

    try {
      await _ensureSocketConnectedForCurrentUser();
      SocketService().emitCallReject(
        callerId: _callerId,
        recipientId: _currentUserId,
        recipientName: _recipientName,
        channelName: _channel,
        callType: 'audio',
        reasonCode: reasonCode,
        reasonMessage: reasonMessage,
      );
      unawaited(NotificationService.sendCallResponseNotification(
        callerId: _callerId,
        recipientName: _recipientName,
        accepted: false,
        recipientUid: '0',
        channelName: _channel,
      ));
    } catch (e) {
      debugPrint('❌ Error notifying accept failure: $e');
    }
  }

  Map<String, String>? _deriveAcceptFailureFromError(Object error) {
    final raw = error.toString();
    final msg = raw.toLowerCase();

    if (msg.contains('token') ||
        msg.contains('invalid') ||
        msg.contains('expired') ||
        msg.contains('not authorized') ||
        msg.contains('permission')) {
      return {
        'code': 'agora_error',
        'message': 'Call failed: token/permission validation error.',
      };
    }

    if (msg.contains('socket') ||
        msg.contains('network') ||
        msg.contains('timeout') ||
        msg.contains('connection') ||
        msg.contains('joinchannel')) {
      return {
        'code': 'connection_failed',
        'message': 'Call failed: network/channel connection error.',
      };
    }

    // Unknown local exceptions should not force a remote decline message.
    return null;
  }

  bool _isFatalAgoraError(ErrorCodeType code, String message) {
    final msg = message.toLowerCase();
    final codeText = code.toString().toLowerCase();
    return msg.contains('token') ||
        msg.contains('invalid') ||
        msg.contains('expired') ||
        codeText.contains('token') ||
        codeText.contains('invalid') ||
        codeText.contains('expired') ||
        codeText.contains('rejected');
  }

  bool _isRetryableAgoraAcceptError(Object error) {
    final msg = error.toString().toLowerCase();
    return msg.contains('agorartcexception(-3') ||
        msg.contains(' not ready') ||
        msg.contains('rtc not ready');
  }

  // ================= TIMERS =================
  void _startCallTimer() {
    // Update the foreground-service notification to show a running
    // chronometer starting from now — the user sees the same call timer
    // both inside the app and on the notification shade.
    unawaited(CallForegroundServiceManager.markCallConnected(
      callType: 'audio',
      otherUserName: _callerName,
    ));
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _duration += const Duration(seconds: 1));
        _syncOverlayState();
      }
    });
  }

  Future<void> _rejectCall() async {
    _ringTimer?.cancel();
    await _stopRingtone();
    await _end();

    // Send decline signal in background so UI closes instantly.
    // CRITICAL: Guard against empty channel/callerId which would cause
    // socket operations to fail silently without informing the caller.
    if (_channel.isEmpty || _callerId.isEmpty) {
      debugPrint(
          '⚠️ Cannot send reject signal: missing channel ($_channel) or callerId ($_callerId)');
      return;
    }

    unawaited(() async {
      try {
        if (widget.callData['isConferenceCall'] == true ||
            widget.callData['isConferenceCall'] == 'true') {
          SocketService().emitParticipantCallReject(
            adminId: _callerId,
            channelName: _channel,
            rejectedById: _currentUserId,
            existingParticipantId:
                widget.callData['existingParticipantId']?.toString(),
          );
        } else {
          await _ensureSocketConnectedForCurrentUser();
          SocketService().emitCallReject(
            callerId: _callerId,
            recipientId: _currentUserId,
            recipientName: _recipientName,
            channelName: _channel,
            callType: 'audio',
            reasonCode: 'user_declined',
            reasonMessage: 'Call declined by receiver.',
          );
          await NotificationService.sendCallResponseNotification(
            callerId: _callerId,
            recipientName: _recipientName,
            accepted: false,
            recipientUid: '0',
            channelName: _channel,
          );
        }
      } catch (e) {
        debugPrint('❌ Error sending reject signal: $e');
      }
    }());
  }

  // ================= MISSED =================
  Future<void> _missedCall() async {
    await _stopRingtone();

    if (widget.callData['isConferenceCall'] == true ||
        widget.callData['isConferenceCall'] == 'true') {
      // Conference call: notify admin the invitation was not answered so admin
      // knows without ending its original active call.
      SocketService().emitParticipantCallReject(
        adminId: _callerId,
        channelName: _channel,
        rejectedById: _currentUserId,
        existingParticipantId:
            widget.callData['existingParticipantId']?.toString(),
      );
      await _end();
      return;
    }

    await NotificationService.sendMissedCallNotification(
      callerId: _callerId,
      callerName: _callerName,
      senderId: _currentUserId,
    );

    // Call history & inline chat message are handled by the caller side.
    await _end();
  }

  // ================= END =================
  Future<void> _endCall() async {
    if (_ending) return;
    _logCallDiag('end_call_start', {
      'call_active': _callActive,
      'joined': _joined,
      'duration_s': _duration.inSeconds,
    });
    _ending = true;
    _ringTimer?.cancel(); // prevent the missed-call timer from firing after end
    _callTimer?.cancel();
    _connectionFailureTimer?.cancel();
    _noPeerJoinTimer?.cancel();
    _cancelSubscription?.cancel();
    _socketCancelSubscription?.cancel();
    _socketEndedSubscription?.cancel();
    _socketSwitchToVideoSub?.cancel();

    if (_callActive || _callAcceptSignalSent) {
      final isConference = widget.callData['isConferenceCall'] == true ||
          widget.callData['isConferenceCall'] == 'true';
      unawaited(() async {
        if (isConference) {
          // Group call: only notify the admin/peers that THIS user left,
          // do NOT end the entire call for everyone else.
          SocketService().emitLeaveGroupCall(
            channelName: _channel,
            userId: _currentUserId,
          );
        } else {
          await _ensureSocketConnectedForCurrentUser();
          SocketService().emitCallEnd(
            callerId: _callerId,
            recipientId: _currentUserId,
            channelName: _channel,
            callType: 'audio',
            duration: _duration.inSeconds,
          );
          // No FCM 'call ended' push: the socket event above tears down the
          // peer's UI instantly, and an end-of-call notification is just noise
          // to the user (the call is already over).
        }
      }());
    }

    // Update call history in background so UI does not block on network.
    if (_callHistoryId != null && _callHistoryId!.isNotEmpty) {
      unawaited(CallHistoryService.updateCallEnd(
        callId: _callHistoryId!,
        status: CallStatus.completed,
        duration: _duration.inSeconds,
      ));
    }

    await _releaseEngineAsync();
    await _stopForegroundService();

    await _end();
  }

  Future<void> _end() async {
    _noPeerJoinTimer?.cancel();
    await _stopRingtone();
    // Final sweep: remove any incoming-call banner (FCM OS heads-up
    // and our own full-screen notification) before tearing down so
    // nothing remains in the shade after the call ends.
    _cancelCallNotification();
    IncomingCallOverlayManager().dismiss();
    CallOverlayManager().reset();
    _dismissActiveCallRoute();
    unawaited(_stopForegroundService());
  }

  void _dismissActiveCallRoute() {
    final navigator = navigatorKey.currentState;
    if (navigator != null) {
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
  }

  // ================= SWITCH TO VIDEO =================
  /// Show dialog when the other party requests an audio→video upgrade.
  void _showSwitchToVideoDialog(Map<String, dynamic> data) {
    final requesterId = data['requesterId']?.toString() ?? _callerId;
    if (!mounted) return;
    _videoSwitchDialogActive = true;
    showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Switch to Video'),
        content: Text('$_callerName wants to switch to a video call. Accept?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Decline'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Accept'),
          ),
        ],
      ),
    ).then((accepted) {
      _videoSwitchDialogActive = false;
      if (!mounted || _ending) return;
      if (accepted == true) {
        SocketService().emitSwitchToVideoResponse(
          requesterId: requesterId,
          responderId: _currentUserId,
          channelName: _channel,
          accepted: true,
        );
        _navigateToVideoCall();
      } else if (accepted == false) {
        SocketService().emitSwitchToVideoResponse(
          requesterId: requesterId,
          responderId: _currentUserId,
          channelName: _channel,
          accepted: false,
        );
      }
    });
  }

  /// Navigate to IncomingVideoCallScreen on the same Agora channel.
  Future<void> _navigateToVideoCall() async {
    if (_ending) return;
    _isSwitchingToVideo = true; // Prevent onUserOffline from ending the call
    // Cancel all subscriptions to avoid interference.
    _ringTimer?.cancel();
    _callTimer?.cancel();
    _connectionFailureTimer?.cancel();
    _cancelSubscription?.cancel();
    _socketCancelSubscription?.cancel();
    _socketEndedSubscription?.cancel();
    _socketSwitchToVideoSub?.cancel();

    // Leave the audio Agora channel.
    try {
      if (_joined) await _engine.leaveChannel();
      if (_engineInitialized) await _engine.release();
    } catch (e) {
      debugPrint('Error releasing audio engine for video switch: $e');
    }
    CallOverlayManager().reset();
    unawaited(_stopForegroundService());

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        settings: RouteSettings(name: activeCallRouteName),
        fullscreenDialog: true,
        builder: (_) => IncomingVideoCallScreen(
          callData: {
            ...widget.callData,
            'channelName': _channel,
            'callerId': _callerId,
            'callerName': _callerName,
            'isVideoCall': 'true',
            'type': 'video_call',
            // Mark as upgraded so IncomingVideoCallScreen skips emitting accept again
            'isAudioToVideoUpgrade': 'true',
          },
        ),
      ),
    );
  }

  // ================= UI =================
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, _) async {
        if (didPop) return;
        // When back button is pressed during incoming call
        if (_callActive) {
          // If call is active, minimize it
          await _minimizeCall();
        } else if (_connecting) {
          // If still connecting, end the call
          await _endCall();
        } else {
          // If call is not yet accepted, reject it
          await _rejectCall();
        }
      },
      child: Scaffold(
        body: AnimatedContainer(
          duration: const Duration(milliseconds: 500),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
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
            child: Column(
              children: [
                if (_callActive)
                  Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 16, top: 12),
                      child: CallMinimizeButton(onPressed: _minimizeCall),
                    ),
                  ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    transitionBuilder: (child, animation) =>
                        FadeTransition(opacity: animation, child: child),
                    child: _callActive
                        ? _buildActiveCallUI()
                        : (_connecting
                            ? _buildConnectingUI()
                            : _buildIncomingCallUI()),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildConnectingUI() {
    return Column(
      key: const ValueKey('connecting'),
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const SizedBox(height: 40),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildCallerAvatar(size: 130, icon: Icons.phone_in_talk),
              const SizedBox(height: 32),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  _callerName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ),
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        color: Color(0xFF29B6F6), strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Text(
                    'Connecting...',
                    style: TextStyle(
                      color: Color(0xFF78909C),
                      fontSize: 17,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 56, left: 20, right: 20),
          child: _modernCallBtn(
            icon: Icons.call_end,
            color: const Color(0xFFFF1744),
            onPressed: _endCall,
            label: 'End',
          ),
        ),
      ],
    );
  }

  Widget _buildIncomingCallUI() {
    return Column(
      key: const ValueKey('incoming'),
      children: [
        const SizedBox(height: 52),
        // Incoming call badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
          decoration: BoxDecoration(
            color: const Color(0xFF00C853).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: const Color(0xFF00C853).withValues(alpha: 0.45),
              width: 1,
            ),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.call_rounded, color: Color(0xFF00C853), size: 14),
              SizedBox(width: 6),
              Text(
                'Incoming Voice Call',
                style: TextStyle(
                  color: Color(0xFF00C853),
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
              // Pulse rings + avatar
              _PulseWidget(
                size: 148,
                child: _buildCallerAvatar(
                    size: 148, icon: Icons.call_rounded),
              ),
              const SizedBox(height: 36),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  _callerName,
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
              const SizedBox(height: 12),
              Text(
                'Ringing...',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 56, left: 24, right: 24),
          child: _incomingControls(),
        ),
      ],
    );
  }

  Widget _buildActiveCallUI() {
    return Column(
      key: const ValueKey('active'),
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const SizedBox(height: 40),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildCallerAvatar(size: 96, icon: Icons.phone_in_talk),
              const SizedBox(height: 20),
              // Connected badge
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
                _callerName,
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
          child: _activeControls(),
        ),
      ],
    );
  }

  Widget _incomingControls() => Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _modernCallBtn(
            icon: Icons.call_end,
            color: const Color(0xFFFF1744),
            onPressed: _rejectCall,
            label: 'Decline',
            size: 76,
          ),
          _modernCallBtn(
            icon: Icons.call,
            color: const Color(0xFF00C853),
            onPressed: _acceptCall,
            loading: _processing,
            label: 'Answer',
            size: 76,
          ),
        ],
      );

  Widget _activeControls() => Padding(
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
              onPressed: _engineInitialized
                  ? () {
                      setState(() => _speakerOn = !_speakerOn);
                      _engine.setEnableSpeakerphone(_speakerOn);
                    }
                  : null,
              label: 'Speaker',
              active: _speakerOn,
            ),
          ],
        ),
      );

  Widget _buildCallerAvatar({required double size, required IconData icon}) {
    final hasImage = _callerImageUrl.isNotEmpty;
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
                _callerImageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Center(
                  child:
                      Icon(icon, size: size * 0.45, color: Colors.white70),
                ),
              )
            : Center(
                child:
                    Icon(icon, size: size * 0.45, color: Colors.white70),
              ),
      ),
    );
  }

  Widget _modernCallBtn({
    required IconData icon,
    required Color color,
    required VoidCallback? onPressed,
    bool loading = false,
    String? label,
    double size = 72,
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
            child: loading
                ? Center(
                    child: SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5),
                    ),
                  )
                : Icon(icon, color: Colors.white, size: size * 0.44),
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
              color: active ? color : Colors.white.withValues(alpha: 0.8),
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

  String _format(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  void dispose() {
    WakelockPlus.disable();
    _ringTimer?.cancel();
    _callTimer?.cancel();
    _cancelSubscription?.cancel();
    _socketCancelSubscription?.cancel();
    _socketEndedSubscription?.cancel();
    // Force-stop any ringing/vibration even if teardown raced with route pop.
    unawaited(_stopRingtone());
    _vibrationTimer?.cancel();
    unawaited(_ringtonePlayer.dispose());
    // Release Agora engine if not already released
    unawaited(_releaseEngineAsync());
    unawaited(_stopForegroundService());
    super.dispose();
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
    } catch (_) {
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
      otherUserName: _callerName,
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
}

/// Wraps [child] with 3 staggered expanding ring animations (pulse effect).
/// [size] should match the child's diameter.
class _PulseWidget extends StatefulWidget {
  final Widget child;
  final double size;
  const _PulseWidget({
    required this.child,
    this.size = 148,
  });

  @override
  State<_PulseWidget> createState() => _PulseWidgetState();
}

class _PulseWidgetState extends State<_PulseWidget>
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
        final opacity = ((1.0 - v) * 0.4).clamp(0.0, 1.0);
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
                    color: const Color(0xFF00C853), width: 2),
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
