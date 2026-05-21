import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
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
import '../service/audio_manager.dart';
import 'tokengenerator.dart';
import 'call_history_model.dart';
import 'call_history_service.dart';
import 'call_foreground_service.dart';
import 'package:ms2026/utils/web_call_ringtone_player_stub.dart'
    if (dart.library.html) 'package:ms2026/utils/web_ringtone_player.dart';
import '../utils/image_utils.dart';

class IncomingVideoCallScreen extends StatefulWidget {
  final Map<String, dynamic> callData;
  const IncomingVideoCallScreen({super.key, required this.callData});

  @override
  State<IncomingVideoCallScreen> createState() =>
      _IncomingVideoCallScreenState();
}

class _IncomingVideoCallScreenState extends State<IncomingVideoCallScreen> {
  late RtcEngine _engine;
  bool _engineInitialized = false;
  late final AudioPlayer _ringtonePlayer;

  int _localUid = 0;
  int? _remoteUid;
  final Set<int> _remoteUids = <int>{};
  final Map<int, bool> _remoteVideoStoppedByUid = <int, bool>{};

  late String _channel;
  late String _callerId;
  late String _callerName;
  late String _recipientName;
  late bool _isVideoCall;

  bool _joined = false;
  bool _callActive = false;
  bool _micMuted = false;
  bool _speakerOn = false;
  bool _cameraOn = true;
  bool _frontCamera = true;
  bool _processing = false;
  bool _foregroundServiceStarted = false;
  bool _ending = false;
  bool _engineReleaseInProgress = false;
  bool _remoteVideoStopped = false;
  bool _connecting = false;

  Timer? _ringTimer;
  Timer? _callTimer;
  Timer? _connectionFailureTimer;
  Timer? _noPeerJoinTimer;
  bool _noPeerJoinRetryUsed = false;
  Duration _duration = Duration.zero;
  StreamSubscription<Map<String, dynamic>>? _cancelSubscription;
  StreamSubscription<Map<String, dynamic>>? _socketCancelSubscription;
  StreamSubscription<Map<String, dynamic>>? _socketEndedSubscription;

  bool _isPlayingRingtone = false;
  Timer? _vibrationTimer;
  bool _allowIncomingRingtone = true;

  // Network quality tracking
  int _networkQuality =
      0; // 0=unknown, 1=excellent, 2=good, 3=poor, 4=bad, 5=very bad, 6=down
  Timer? _qualityUpdateTimer;

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
      'video=$_isVideoCall',
    ];
    extra.forEach((k, v) => parts.add('$k=${v ?? 'null'}'));
    debugPrint('CALL_DIAG_IN_VIDEO ${parts.join(' ')}');
  }

  bool get _isConferenceCall =>
      widget.callData['isConferenceCall'] == true ||
      widget.callData['isConferenceCall'] == 'true';

  @override
  void initState() {
    super.initState();
    // Prevent duplicate ringtone from compact incoming overlay.
    IncomingCallOverlayManager().dismiss();
    // Cancel the system notification immediately so the heads-up banner
    // does not overlap the full-screen call UI.
    _cancelCallNotification();
    AudioManager.instance.stopCallRingtone();
    _ringtonePlayer = AudioPlayer();
    _ringtonePlayer.setReleaseMode(ReleaseMode.loop);
    WakelockPlus.enable();
    _parseData();
    _localUid = Random().nextInt(999998) + 1;

    final isUpgrade =
        widget.callData['isAudioToVideoUpgrade']?.toString() == 'true';
    if (isUpgrade) {
      // Came from an audio call; no ringing needed, accept immediately.
      _loadUserDataAndLogCall();
      _listenForCallCancelled();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _acceptCall();
      });
      return;
    }

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
      if (_callerId.isNotEmpty && _currentUserId.isNotEmpty) {
        unawaited(() async {
          await _ensureSocketConnectedForCurrentUser();
          SocketService().emitCallRinging(
            callerId: _callerId,
            recipientId: _currentUserId,
            channelName: _channel,
            callType: _isVideoCall ? 'video' : 'audio',
          );
        }());
      } else {
        _pendingEmitRinging = true;
      }
    });
  }

  void _cancelCallNotification() {
    try {
      // Cancel the video call notification (ID: 1002)
      final plugin = FlutterLocalNotificationsPlugin();
      plugin.cancel(1002);
      // Also cancel the OS-side banner that the FCM SDK posted from
      // the call push's `notification` block. Its internal id is
      // opaque so we cancel by tag (= channelName) via native API.
      if (_channel.isNotEmpty) {
        // ignore: unawaited_futures
        CallForegroundServiceManager.cancelNotificationsByTag(_channel);
      }
      // ignore: unawaited_futures
      CallForegroundServiceManager.cancelAllCallBanners();
      debugPrint('✅ Cancelled video call notification after screen mounted');
    } catch (e) {
      debugPrint('Error cancelling video call notification: $e');
    }
  }

  Future<void> _playRingtone() async {
    if (!_allowIncomingRingtone || _processing || _connecting || _ending) {
      return;
    }
    try {
      _isPlayingRingtone = true;

      // Repeating vibration while the call is ringing (1.5s interval).
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
          if (kIsWeb) {
            await WebRingtonePlayer.instance.play(customUrl);
          } else {
            await _ringtonePlayer.setReleaseMode(ReleaseMode.loop);
            await _ringtonePlayer.play(UrlSource(customUrl));
          }
          debugPrint('✅ Incoming video custom ringtone started: $customUrl');
          return;
        } catch (e) {
          debugPrint('⚠️ Custom incoming video ringtone failed: $e');
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
        debugPrint('✅ Incoming video system default ringtone started');
      }
    } catch (e) {
      debugPrint('Error playing incoming video call ringtone: $e');
    }
  }

  Future<void> _stopRingtone() async {
    try {
      _isPlayingRingtone = false;
      _vibrationTimer?.cancel();
      _vibrationTimer = null;
      if (kIsWeb) {
        await WebRingtonePlayer.instance.stop();
      } else {
        await _ringtonePlayer.stop();
      }
      debugPrint('✅ Incoming video call ringtone stopped');
    } catch (e) {
      debugPrint('Error stopping incoming video call ringtone: $e');
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
    // FCM path
    _cancelSubscription = NotificationService.callResponses.listen((data) {
      final type = data['type']?.toString();
      if (type == 'video_call_cancelled' || type == 'video_call_ended') {
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

    // Socket.IO path (real-time for online callers)
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

        // Deferred ringing notification: emit now that we have the user ID.
        if (_pendingEmitRinging &&
            _callerId.isNotEmpty &&
            _currentUserId.isNotEmpty) {
          _pendingEmitRinging = false;
          await _ensureSocketConnectedForCurrentUser();
          SocketService().emitCallRinging(
            callerId: _callerId,
            recipientId: _currentUserId,
            channelName: _channel,
            callType: _isVideoCall ? 'video' : 'audio',
          );
        }

        // Log call history only for group/conference calls.
        // Regular 1-on-1 calls are logged by the caller (VideoCallScreen)
        // to prevent duplicate entries in call history.
        if (_isConferenceCall) {
          _callHistoryId = await CallHistoryService.logCall(
            callerId: _callerId,
            callerName: _callerName,
            callerImage: widget.callData['callerImage'] ?? '',
            recipientId: _currentUserId,
            recipientName: _currentUserName,
            recipientImage: _currentUserImage,
            callType: CallType.video,
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
        // Admin → user calls: display the real admin name as the server sent
        // it.  No member-code prefix or last-name munging.
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
      _isVideoCall = widget.callData['type'] == 'video_call' ||
          (widget.callData['isVideoCall']?.toString() == 'true');
      _currentUserId = widget.callData['recipientId']?.toString() ??
          widget.callData['recipientUid']?.toString() ??
          _currentUserId;

      debugPrint(
          'Parsed incoming video call: caller=$_callerId, channel=$_channel, recipient=$_currentUserId, isVideo=$_isVideoCall');
    } catch (e) {
      debugPrint('❌ CRITICAL ERROR in _parseData: $e – screen will not render');
      // Set safe defaults so late variables are initialized
      _channel = '';
      _callerId = '';
      _callerName = 'Incoming Call';
      _recipientName = 'You';
      _isVideoCall = true;
    }
  }

  void _initializeOverlay() {
    CallOverlayManager().startCall(
      callType: _isVideoCall ? 'video' : 'audio',
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
      onToggleCamera: _toggleVideo,
      isMicMuted: _micMuted,
      isCameraEnabled: _cameraOn,
    );
    _syncOverlayState();
  }

  void _syncOverlayState() {
    CallOverlayManager().updateCallState(
      statusText: _callActive ? 'Connected' : 'Incoming call',
      duration: _duration,
      isMicMuted: _micMuted,
      isCameraEnabled: _cameraOn,
    );
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

  Future<void> _minimizeCall() async {
    await openMinimizedCallHost(context);
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
      final requiredFeature = _isVideoCall ? 'video_call' : 'audio_call';
      var canReceiveCall =
          context.read<UserState>().hasFeature(requiredFeature);
      bool refreshedForGate = false;
      if (!canReceiveCall) {
        refreshedForGate = await _refreshUserStateForCallGate();
        if (refreshedForGate && mounted) {
          canReceiveCall =
              context.read<UserState>().hasFeature(requiredFeature);
        }
      }
      if (canReceiveCall) return false;

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
          await _shouldBlockForPackageLock(requiredFeature: requiredFeature);
      if (!shouldBlock) {
        debugPrint(
            'Call gate: allowing incoming accept (feature state uncertain).');
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
        callType: _isVideoCall ? 'video' : 'audio',
        reasonCode: 'feature_locked',
        reasonMessage:
            'Call rejected: receiver package does not include this call feature.',
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
      if (usertype == 'paid') return false;
      return usertype == 'free';
    } catch (_) {
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

// ================= ACCEPT CALL =================
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
        ? 'inv_${DateTime.now().millisecondsSinceEpoch}'
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
      debugPrint('📞 ACCEPTING VIDEO CALL');
      debugPrint('📞 Channel: $_channel');
      debugPrint('📞 Local UID: $_localUid');
      debugPrint('📞 Is Video Call: $_isVideoCall');

      await _silenceIncomingAlerts(permanently: true);

      final hasUser = await _ensureCurrentUserLoaded();
      if (!hasUser) {
        _logCallDiag('accept_fail_session_missing');
        await _notifyAcceptFailure(
          reasonCode: 'session_missing',
          reasonMessage: 'Call failed: receiver session is not available.',
        );
        await _end();
        return;
      }
      await _ensureSocketConnectedForCurrentUser();

      // Signal acceptance immediately (admin-like behavior) to avoid
      // caller timeout/cancel while token/engine setup is in progress.
      if (!_isConferenceCall) {
        await _emitCallAcceptIfNeeded();
      }

      // Permissions
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
      if (_isVideoCall && !(await Permission.camera.request()).isGranted) {
        await _notifyAcceptFailure(
          reasonCode: 'permission_denied',
          reasonMessage: 'Call rejected: camera permission denied.',
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

      debugPrint('✅ Permissions granted');

      // Token
      debugPrint('🔐 Getting Agora token...');
      final token = await AgoraTokenService.getToken(
        channelName: _channel,
        uid: _localUid,
        userId: _currentUserId,
        callType: 'video',
      ).timeout(const Duration(milliseconds: _kTokenFetchTimeoutMs));
      _logCallDiag('token_ok', {
        'latency_ms': _acceptStartedAtMs == null
            ? null
            : DateTime.now().millisecondsSinceEpoch - _acceptStartedAtMs!,
      });

      // Engine
      debugPrint('🚀 Initializing Agora engine...');
      _engine = createAgoraRtcEngine();
      await _engine.initialize(RtcEngineContext(
        appId: AgoraTokenService.appId,
        channelProfile: ChannelProfileType.channelProfileCommunication,
      ));
      _engineInitialized = true;

      // Mirror the stable outgoing/incoming-audio path: avoid enabling local
      // media before the channel join succeeds to prevent Agora not-ready races
      // on some devices during accept.
      await _engine.disableAudio();

      debugPrint('👂 Setting up event handlers...');
      _engine.registerEventHandler(
        RtcEngineEventHandler(
          onJoinChannelSuccess: (connection, elapsed) {
            debugPrint('✅ Joined channel successfully');
            _acceptRetryCount = 0;
            if (mounted) {
              setState(() => _joined = true);
            }
            unawaited(() async {
              if (!_engineInitialized) return;
              await _engine.enableAudio();
              await _engine.setEnableSpeakerphone(_speakerOn);
              if (_isVideoCall) {
                await _engine.enableVideo();
                await _engine.setVideoEncoderConfiguration(
                  const VideoEncoderConfiguration(
                    dimensions: VideoDimensions(width: 1280, height: 720),
                    frameRate: 30,
                    bitrate: 1500,
                    minBitrate: 600,
                    orientationMode: OrientationMode.orientationModeAdaptive,
                    degradationPreference:
                        DegradationPreference.maintainQuality,
                    mirrorMode: VideoMirrorModeType.videoMirrorModeAuto,
                  ),
                );
                await _engine.startPreview();
              }
              await _engine.updateChannelMediaOptions(
                ChannelMediaOptions(
                  publishMicrophoneTrack: true,
                  publishCameraTrack: _isVideoCall,
                  autoSubscribeAudio: true,
                  autoSubscribeVideo: _isVideoCall,
                ),
              );
            }()
                .catchError(
              (e) {
                debugPrint(
                    'incoming video accept post-join media setup error: $e');
                return null;
              },
            ));
            _noPeerJoinTimer?.cancel();
            _noPeerJoinRetryUsed = false;
            _noPeerJoinTimer = Timer(
              const Duration(milliseconds: _kNoPeerJoinTimeoutMs),
              () {
                if (_ending || _callActive || _remoteUids.isNotEmpty) return;
                if (!_noPeerJoinRetryUsed) {
                  _noPeerJoinRetryUsed = true;
                  _logCallDiag('no_peer_join_retry', {
                    'retry_after_ms': _kNoPeerJoinTimeoutMs,
                  });
                  _noPeerJoinTimer = Timer(
                    const Duration(milliseconds: _kNoPeerJoinTimeoutMs),
                    () {
                      if (_ending || _callActive || _remoteUids.isNotEmpty) {
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
            debugPrint('📤 Notifying caller of acceptance...');
            if (_isConferenceCall) {
              // Conference call: emit participant_call_accept so admin receives
              // participant_accepted_call without disrupting the original call.
              SocketService().emitParticipantCallAccept(
                adminId: _callerId,
                channelName: _channel,
                acceptedById: _currentUserId,
                callType: 'video',
                existingParticipantId:
                    widget.callData['existingParticipantId']?.toString(),
              );
            } else {
              // Non-conference calls send call_accept once at accept-tap time.
              // Avoid duplicate re-send here because it can create teardown races.
              unawaited(NotificationService.sendVideoCallResponseNotification(
                callerId: _callerId,
                recipientName: _recipientName,
                accepted: true,
                recipientUid: _localUid.toString(),
                channelName: _channel,
              ));
            }
          },
          onUserJoined: (connection, remoteUid, elapsed) {
            debugPrint('👤 Remote user joined: $remoteUid');
            _connectionFailureTimer?.cancel();
            _noPeerJoinTimer?.cancel();
            _logCallDiag('remote_joined', {'remote_uid': remoteUid});
            final shouldStartTimer = !_callActive;
            if (mounted) {
              setState(() {
                _remoteUids.add(remoteUid);
                _remoteUid = remoteUid;
                _callActive = true;
                _remoteVideoStopped = false;
                _remoteVideoStoppedByUid[remoteUid] = false;
                _connecting = false;
              });
            }
            if (shouldStartTimer) {
              _startCallTimer();
            }
            _syncOverlayState();
          },
          onUserOffline: (connection, remoteUid, reason) {
            debugPrint('👤 Remote user offline: $remoteUid, reason: $reason');
            if (_ending) return;
            _remoteUids.remove(remoteUid);
            _remoteVideoStoppedByUid.remove(remoteUid);

            if (_remoteUid == remoteUid) {
              _remoteUid = _remoteUids.isNotEmpty ? _remoteUids.first : null;
            }

            if (_remoteUids.isEmpty) {
              // Ignore brief offline blips before call establishment.
              if (!_callActive && !_joined) return;
              _connectionFailureTimer?.cancel();
              _connectionFailureTimer = Timer(
                  const Duration(milliseconds: _kRemoteOfflineEndDelayMs), () {
                if (_ending) return;
                if (_remoteUids.isEmpty && _callActive) {
                  _endCall();
                }
              });
            } else if (mounted) {
              setState(() {});
            }
          },
          onRemoteVideoStateChanged:
              (connection, remoteUid, state, reason, elapsed) {
            debugPrint(
                '📹 Remote video state changed: uid=$remoteUid, state=$state, reason=$reason');
            final isStopped =
                state == RemoteVideoState.remoteVideoStateStopped ||
                    state == RemoteVideoState.remoteVideoStateFailed;
            _remoteVideoStoppedByUid[remoteUid] = isStopped;

            if (state == RemoteVideoState.remoteVideoStateStopped ||
                state == RemoteVideoState.remoteVideoStateFailed) {
              debugPrint('❌ Remote video stopped/failed');
              if (_remoteUid == remoteUid && mounted) {
                setState(() => _remoteVideoStopped = true);
              } else if (mounted) {
                setState(() {});
              }
            } else if (state == RemoteVideoState.remoteVideoStateDecoding) {
              debugPrint('✅ Remote video started decoding');
              if (mounted) {
                setState(() {
                  _remoteUids.add(remoteUid);
                  _remoteUid = remoteUid;
                  _remoteVideoStopped = false;
                  _remoteVideoStoppedByUid[remoteUid] = false;
                });
              }
            }
          },
          onError: (errorCode, errorMsg) {
            debugPrint('❌ Agora error $errorCode $errorMsg');
            if (_remoteUids.isEmpty &&
                !_ending &&
                _isFatalAgoraError(errorCode, errorMsg)) {
              unawaited(_notifyAcceptFailure(
                reasonCode: 'agora_error',
                reasonMessage: 'Call failed during connection setup.',
              ));
              _endCall();
            }
          },
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
            _logCallDiag('conn_state', {
              'state': state.name,
              'reason': reason.name,
              'joined': _joined,
              'call_active': _callActive,
            });
            if (_ending) return;

            // Handle reconnection scenarios - call stays active during network switches
            if (state == ConnectionStateType.connectionStateReconnecting) {
              debugPrint('📶 Reconnecting to call...');
              _connectionFailureTimer?.cancel();
            } else if (state == ConnectionStateType.connectionStateConnected) {
              debugPrint('📶 Connected to call');
              _connectionFailureTimer?.cancel();
            } else if (state == ConnectionStateType.connectionStateConnecting) {
              _connectionFailureTimer?.cancel();
            } else if (state == ConnectionStateType.connectionStateFailed) {
              debugPrint('❌ Connection failed');
              // Avoid hard drop on transient FAILED during route/network switch.
              _connectionFailureTimer?.cancel();
              _connectionFailureTimer = Timer(
                  const Duration(milliseconds: _kConnectionFailedEndDelayMs),
                  () {
                if (_ending ||
                    _callActive ||
                    _joined ||
                    _remoteUids.isNotEmpty) {
                  return;
                }
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

      debugPrint('🚪 Joining channel...');
      await _engine
          .joinChannel(
            token: token,
            channelId: _channel,
            uid: _localUid,
            options: ChannelMediaOptions(
              publishMicrophoneTrack: false,
              publishCameraTrack: false,
              autoSubscribeAudio: true,
              autoSubscribeVideo: _isVideoCall,
            ),
          )
          .timeout(const Duration(milliseconds: _kJoinCallTimeoutMs));

      debugPrint('✅ Joined channel, waiting for remote user...');
      // Keep connecting state (already set at the beginning) until remote joins
      _initializeOverlay();
    } catch (e) {
      debugPrint('❌ Accept error: $e');
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
      callType: 'video',
    );
    _callAcceptSignalSent = true;
    _logCallDiag(forceResend ? 'accept_signal_resent' : 'accept_signal_sent');
  }

  Future<void> _notifyAcceptFailure({
    required String reasonCode,
    required String reasonMessage,
  }) async {
    if (_callActive || _ending || _isConferenceCall) return;
    final hasUser = await _ensureCurrentUserLoaded();
    if (!hasUser || _currentUserId.isEmpty) return;

    await _ensureSocketConnectedForCurrentUser();
    SocketService().emitCallReject(
      callerId: _callerId,
      recipientId: _currentUserId,
      recipientName: _recipientName,
      channelName: _channel,
      callType: _isVideoCall ? 'video' : 'audio',
      reasonCode: reasonCode,
      reasonMessage: reasonMessage,
    );
    unawaited(NotificationService.sendVideoCallResponseNotification(
      callerId: _callerId,
      recipientName: _recipientName,
      accepted: false,
      recipientUid: '0',
      channelName: _channel,
    ));
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
        msg.contains('rejected') ||
        msg.contains('not authorized') ||
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

    // CRITICAL: Guard against empty channel/callerId which would cause
    // socket operations to fail silently without informing the caller.
    if (_channel.isEmpty || _callerId.isEmpty) {
      debugPrint(
          '⚠️ Cannot send reject signal: missing channel ($_channel) or callerId ($_callerId)');
      await _end();
      return;
    }

    try {
      if (_isConferenceCall) {
        // Conference call: notify admin via participant_call_reject so the
        // admin's original call is NOT accidentally terminated.
        SocketService().emitParticipantCallReject(
          adminId: _callerId,
          channelName: _channel,
          rejectedById: _currentUserId,
          existingParticipantId:
              widget.callData['existingParticipantId']?.toString(),
        );
      } else {
        await _ensureSocketConnectedForCurrentUser();
        // Notify caller via Socket.IO (fast) + FCM (fallback)
        SocketService().emitCallReject(
          callerId: _callerId,
          recipientId: _currentUserId,
          recipientName: _recipientName,
          channelName: _channel,
          callType: 'video',
          reasonCode: 'user_declined',
          reasonMessage: 'Call declined by receiver.',
        );
        await NotificationService.sendVideoCallResponseNotification(
          callerId: _callerId,
          recipientName: _recipientName,
          accepted: false,
          recipientUid: '0',
          channelName: _channel,
        );

        // Call history & inline chat message are handled by the caller side.
      }
    } catch (e) {
      debugPrint('❌ Error sending reject signal: $e');
    }

    await _end();
  }

  // ================= MISSED =================
  Future<void> _missedCall() async {
    await _stopRingtone();

    if (_isConferenceCall) {
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

    await NotificationService.sendMissedVideoCallNotification(
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
      'remote_count': _remoteUids.length,
    });
    _ending = true;
    _ringTimer?.cancel(); // prevent the missed-call timer from firing after end
    _callTimer?.cancel();
    _connectionFailureTimer?.cancel();
    _noPeerJoinTimer?.cancel();
    _cancelSubscription?.cancel();
    _socketCancelSubscription?.cancel();
    _socketEndedSubscription?.cancel();

    if (_callActive || _callAcceptSignalSent) {
      final isConference = _isConferenceCall;
      if (isConference) {
        // Group call: only notify the admin/peers that THIS user left,
        // do NOT end the entire call for everyone else.
        SocketService().emitLeaveGroupCall(
          channelName: _channel,
          userId: _currentUserId,
        );
      } else {
        await _ensureSocketConnectedForCurrentUser();
        // Notify caller via Socket.IO (fast) + FCM (fallback)
        SocketService().emitCallEnd(
          callerId: _callerId,
          recipientId: _currentUserId,
          channelName: _channel,
          callType: 'video',
          duration: _duration.inSeconds,
        );
        unawaited(NotificationService.sendVideoCallEndedNotification(
          recipientUserId: _callerId,
          callerName: _recipientName,
          reason: 'ended',
          duration: _duration.inSeconds,
          channelName: _channel,
        ));
      }
    }

    // Update call history for group/conference calls only.
    // Regular 1-on-1 call status is updated by the caller (VideoCallScreen).
    if (_callHistoryId != null && _callHistoryId!.isNotEmpty) {
      await CallHistoryService.updateCallEnd(
        callId: _callHistoryId!,
        status: CallStatus.completed,
        duration: _duration.inSeconds,
      );
    }

    // Navigate away FIRST so the user never sees the black AgoraRTC screen
    await _end();

    // Release engine resources after navigation (fire-and-forget)
    unawaited(_releaseEngineAsync());
  }

  Future<void> _end() async {
    _noPeerJoinTimer?.cancel();
    await _stopRingtone();
    // Final sweep: remove any incoming-call banner (FCM OS heads-up
    // and our own full-screen notification) before tearing down so
    // nothing remains in the shade after the call ends.
    _cancelCallNotification();
    // Ensure the incoming-call banner is gone regardless of how we got here
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

  // ================= TOGGLE CAMERA =================
  Future<void> _toggleCamera() async {
    if (_joined && _isVideoCall) {
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
    if (_engineInitialized && _isVideoCall) {
      await _engine.enableLocalVideo(_cameraOn);
    }
    _syncOverlayState();
  }

  // ================= UI =================
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, _) async {
        if (didPop) return;
        // When back button is pressed during incoming video call
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
        backgroundColor: const Color(0xFF060B16),
        body: SafeArea(
          child: _callActive
              ? _buildActiveCallUI()
              : (_connecting ? _buildConnectingUI() : _buildIncomingCallUI()),
        ),
      ),
    );
  }

  Widget _buildConnectingUI() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const SizedBox(height: 40),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildCallerAvatar(size: 130, icon: Icons.videocam_rounded),
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
                        color: Color(0xFF00E5FF), strokeWidth: 2),
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
          child: _modernAcceptRejectButton(
            icon: Icons.call_end,
            color: const Color(0xFFFF1744),
            onPressed: _endCall,
            size: 72,
            label: 'End',
          ),
        ),
      ],
    );
  }

  Widget _buildIncomingCallUI() {
    return Column(
      children: [
        const SizedBox(height: 52),
        // Incoming video call badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
          decoration: BoxDecoration(
            color: const Color(0xFF00E5FF).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: const Color(0xFF00E5FF).withValues(alpha: 0.45),
              width: 1,
            ),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.videocam_rounded, color: Color(0xFF00E5FF), size: 14),
              SizedBox(width: 6),
              Text(
                'Incoming Video Call',
                style: TextStyle(
                  color: Color(0xFF00E5FF),
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
              // Video pulse rings (cyan)
              _VideoPulseWidget(
                size: 148,
                child: _buildCallerAvatar(
                    size: 148, icon: Icons.videocam_rounded),
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
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _modernAcceptRejectButton(
                icon: Icons.call_end,
                color: const Color(0xFFFF1744),
                onPressed: _rejectCall,
                size: 76,
                label: 'Decline',
              ),
              _modernAcceptRejectButton(
                icon: Icons.videocam_rounded,
                color: const Color(0xFF00C853),
                onPressed: _acceptCall,
                size: 76,
                loading: _processing,
                label: 'Answer',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActiveCallUI() {
    if (_isConferenceCall && _isVideoCall) {
      return _buildConferenceCallUI();
    }

    return Stack(
      children: [
        // Remote video (when active and video not stopped)
        if (_remoteUid != null && _isVideoCall && !_remoteVideoStopped)
          AgoraVideoView(
            controller: VideoViewController.remote(
              rtcEngine: _engine,
              canvas: VideoCanvas(uid: _remoteUid),
              connection: RtcConnection(channelId: _channel),
            ),
          )
        else
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
                    _callerName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _isVideoCall ? 'Video call connected' : 'Voice call',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _format(_duration),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            ),
          ),

        // Local preview (when active and video)
        if (_isVideoCall && _cameraOn)
          Positioned(
            top: 40,
            right: 20,
            width: 120,
            height: 160,
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

        // Top info (when active)
        Positioned(
          top: 40,
          left: 20,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Icon(
                  _isVideoCall ? Icons.videocam : Icons.call,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  _format(_duration),
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
        ),

        Positioned(
          top: 40,
          right: 20,
          child: CallMinimizeButton(onPressed: _minimizeCall),
        ),

        // Bottom controls
        Positioned(
          bottom: 40,
          left: 0,
          right: 0,
          child: _activeControls(),
        ),
      ],
    );
  }

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
                  child: Icon(icon, size: size * 0.45, color: Colors.white70),
                ),
              )
            : Center(
                child: Icon(icon, size: size * 0.45, color: Colors.white70),
              ),
      ),
    );
  }

  Widget _buildConferenceCallUI() {
    final remoteUids = _remoteUids.toList()..sort();
    final participantCount = remoteUids.length + 1; // + local user

    return Stack(
      children: [
        GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(10, 70, 10, 140),
          itemCount: participantCount,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: participantCount <= 2 ? 1 : 2,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: participantCount <= 2 ? 0.68 : 0.86,
          ),
          itemBuilder: (context, index) {
            if (index == 0) {
              return _buildLocalConferenceTile();
            }
            final uid = remoteUids[index - 1];
            return _buildRemoteConferenceTile(uid);
          },
        ),
        Positioned(
          top: 18,
          left: 14,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'Group video · $participantCount participants',
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ),
        Positioned(
          top: 18,
          right: 14,
          child: CallMinimizeButton(onPressed: _minimizeCall),
        ),
        Positioned(
          bottom: 40,
          left: 0,
          right: 0,
          child: _activeControls(),
        ),
      ],
    );
  }

  Widget _buildLocalConferenceTile() {
    final showLocalVideo = _isVideoCall && _cameraOn;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (showLocalVideo)
            AgoraVideoView(
              controller: VideoViewController(
                rtcEngine: _engine,
                canvas: const VideoCanvas(uid: 0),
              ),
            )
          else
            _buildConferenceFallbackTile('You'),
          _buildConferenceTileFooter('You', _micMuted),
        ],
      ),
    );
  }

  Widget _buildRemoteConferenceTile(int uid) {
    final videoStopped = _remoteVideoStoppedByUid[uid] ?? false;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (!videoStopped)
            AgoraVideoView(
              controller: VideoViewController.remote(
                rtcEngine: _engine,
                canvas: VideoCanvas(uid: uid),
                connection: RtcConnection(channelId: _channel),
              ),
            )
          else
            _buildConferenceFallbackTile('User $uid'),
          _buildConferenceTileFooter('User $uid', false),
        ],
      ),
    );
  }

  Widget _buildConferenceFallbackTile(String name) {
    return Container(
      color: Colors.black,
      child: Center(
        child: CircleAvatar(
          radius: 34,
          backgroundColor: Colors.blueGrey.shade700,
          child: Text(
            name.isNotEmpty ? name[0].toUpperCase() : '?',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildConferenceTileFooter(String name, bool micMuted) {
    return Positioned(
      left: 8,
      right: 8,
      bottom: 8,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Spacer(),
          if (micMuted)
            Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.mic_off, color: Colors.amber, size: 12),
            ),
        ],
      ),
    );
  }

  Widget _modernAcceptRejectButton({
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
    double size = 72,
    bool loading = false,
    String? label,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: loading ? null : onPressed,
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

  Widget _modernControlButton({
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
    double size = 56,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.25),
          shape: BoxShape.circle,
          border: Border.all(
            color: color,
            width: 2.5,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.4),
              blurRadius: 15,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Icon(
          icon,
          color: color,
          size: size * 0.55,
        ),
      ),
    );
  }

  Widget _activeControls() => Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _modernControlButton(
            icon: _micMuted ? Icons.mic_off : Icons.mic,
            color: _micMuted ? const Color(0xFFFF9800) : Colors.white,
            onPressed: _toggleMute,
          ),
          if (_isVideoCall)
            _modernControlButton(
              icon: _cameraOn ? Icons.videocam : Icons.videocam_off,
              color: _cameraOn ? Colors.white : const Color(0xFFFF9800),
              onPressed: _toggleVideo,
            ),
          _modernAcceptRejectButton(
            icon: Icons.call_end,
            color: const Color(0xFFF44336),
            onPressed: _endCall,
            size: 68,
          ),
          if (_isVideoCall)
            _modernControlButton(
              icon: Icons.switch_camera,
              color: Colors.white,
              onPressed: _toggleCamera,
            ),
          _modernControlButton(
            icon: _speakerOn ? Icons.volume_up : Icons.volume_off,
            color: _speakerOn ? const Color(0xFF2196F3) : Colors.white,
            onPressed: () {
              setState(() => _speakerOn = !_speakerOn);
              if (_engineInitialized) {
                _engine.setEnableSpeakerphone(_speakerOn);
              }
            },
          ),
        ],
      );

  String _format(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  Future<void> _adaptVideoQuality(int quality) async {
    if (!_engineInitialized || !_joined || !_isVideoCall) return;

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
          orientationMode: OrientationMode.orientationModeAdaptive,
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
          orientationMode: OrientationMode.orientationModeAdaptive,
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
          orientationMode: OrientationMode.orientationModeAdaptive,
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
    WakelockPlus.disable();
    _ringTimer?.cancel();
    _callTimer?.cancel();
    _connectionFailureTimer?.cancel();
    _qualityUpdateTimer?.cancel();
    _cancelSubscription?.cancel();
    _socketCancelSubscription?.cancel();
    _socketEndedSubscription?.cancel();
    // Force-stop any ringing/vibration even if teardown raced with route pop.
    unawaited(_stopRingtone());
    _vibrationTimer?.cancel();
    unawaited(_ringtonePlayer.dispose());
    // Release Agora engine if not already released by _endCall
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
      callType: _isVideoCall ? 'video' : 'audio',
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

/// Cyan 3-ring pulse for incoming video calls.
class _VideoPulseWidget extends StatefulWidget {
  final Widget child;
  final double size;
  const _VideoPulseWidget({required this.child, this.size = 148});

  @override
  State<_VideoPulseWidget> createState() => _VideoPulseWidgetState();
}

class _VideoPulseWidgetState extends State<_VideoPulseWidget>
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
                border:
                    Border.all(color: const Color(0xFF00E5FF), width: 2),
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
