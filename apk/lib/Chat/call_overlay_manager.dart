import 'dart:async';
import 'dart:convert';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../pushnotification/pushservice.dart';
import '../Calling/callmanager.dart';
import '../Calling/incommingcall.dart';
import '../Calling/incomingvideocall.dart';
import '../navigation/app_navigation.dart';
import '../Startup/MainControllere.dart';
import '../service/socket_service.dart';
import '../service/sound_settings_service.dart';
import '../service/app_sound_tone_service.dart';
import '../service/device_sound_policy_service.dart';

const String activeCallRouteName = '/active-call';
const String minimizedCallHostRouteName = '/minimized-call-host';

// ─────────────────────────────────────────────────────────────────────────────
// IncomingCallOverlayManager
// Singleton that controls the WhatsApp-style incoming-call banner.
// ─────────────────────────────────────────────────────────────────────────────
class IncomingCallOverlayManager extends ChangeNotifier {
  static final IncomingCallOverlayManager _instance =
      IncomingCallOverlayManager._internal();
  factory IncomingCallOverlayManager() => _instance;
  IncomingCallOverlayManager._internal();

  Map<String, dynamic>? _callData;
  bool _visible = false;
  bool _isVideo = false;
  AudioPlayer? _ringtonePlayer;
  Timer? _ringTimer;
  Timer? _vibrationTimer;

  bool get isVisible => _visible;
  Map<String, dynamic>? get callData => _callData;
  bool get isVideo => _isVideo;

  String get callerName =>
      _callData?['callerName']?.toString() ?? 'Unknown Caller';

  void show(Map<String, dynamic> data, {required bool isVideo}) {
    _callData = data;
    _isVideo = isVideo;
    _visible = true;
    notifyListeners();
    _playRingtone();
    // Auto-dismiss after 60 seconds (missed call)
    _ringTimer?.cancel();
    _ringTimer = Timer(const Duration(seconds: 60), dismiss);
  }

  void dismiss() {
    if (!_visible) return;
    _visible = false;
    _callData = null;
    _ringTimer?.cancel();
    _ringTimer = null;
    _stopRingtone();
    notifyListeners();
  }

  Future<void> _playRingtone() async {
    try {
      await _stopRingtone();
      if (!SoundSettingsService.instance.callSoundEnabled) return;

      final canPlay = await DeviceSoundPolicyService.canPlayInAppSound();
      if (!canPlay) {
        debugPrint(
            'IncomingCallOverlayManager: phone silent/vibrate/DND, skipping ringtone');
        return;
      }

      _ringtonePlayer = AudioPlayer();
      await _ringtonePlayer!.setReleaseMode(ReleaseMode.loop);

      if (SoundSettingsService.instance.vibrationEnabled && !kIsWeb) {
        HapticFeedback.vibrate();
        _vibrationTimer?.cancel();
        _vibrationTimer =
            Timer.periodic(const Duration(milliseconds: 1500), (_) {
          if (_visible) HapticFeedback.vibrate();
        });
      }

      final sources = await AppSoundToneService.instance
          .playbackSources(AppSoundToneType.incomingCall);
      for (final src in sources) {
        try {
          if (src.isRemote) {
            await _ringtonePlayer!.play(UrlSource(src.value));
          } else {
            await _ringtonePlayer!.play(AssetSource(src.value));
          }
          return;
        } catch (_) {}
      }
      // Fallback default asset
      await _ringtonePlayer!.play(
        AssetSource(AppSoundToneService.instance
            .defaultAsset(AppSoundToneType.incomingCall)),
      );
    } catch (e) {
      debugPrint('IncomingCallOverlayManager: ringtone error: $e');
    }
  }

  Future<void> _stopRingtone() async {
    _vibrationTimer?.cancel();
    _vibrationTimer = null;
    try {
      await _ringtonePlayer?.stop();
      await _ringtonePlayer?.dispose();
    } catch (_) {}
    _ringtonePlayer = null;
  }

  @override
  void dispose() {
    _ringTimer?.cancel();
    _stopRingtone();
    super.dispose();
  }
}

/// Singleton class to manage call overlay state across the app
class CallOverlayManager extends ChangeNotifier {
  static final CallOverlayManager _instance = CallOverlayManager._internal();
  factory CallOverlayManager() => _instance;
  CallOverlayManager._internal();

  bool _isCallActive = false;
  bool _isMinimized = false;
  String? _callType;
  String? _otherUserName;
  String? _otherUserId;
  String? _currentUserId;
  String? _currentUserName;
  String _statusText = 'Calling...';
  Duration _duration = Duration.zero;
  bool _isMicMuted = false;
  bool _isCameraEnabled = true;

  VoidCallback? _onMaximize;
  VoidCallback? _onEnd;
  VoidCallback? _onToggleMute;
  VoidCallback? _onToggleCamera;

  bool get isCallActive => _isCallActive;
  bool get isMinimized => _isMinimized;
  String? get callType => _callType;
  String? get otherUserName => _otherUserName;
  String? get otherUserId => _otherUserId;
  String get statusText => _statusText;
  Duration get duration => _duration;
  bool get isConnected =>
      _duration > Duration.zero || _statusText == 'Connected';
  bool get isMicMuted => _isMicMuted;
  bool get isCameraEnabled => _isCameraEnabled;
  bool get isVideoCall => _callType == 'video';

  void startCall({
    required String callType,
    required String otherUserName,
    required String otherUserId,
    required String currentUserId,
    required String currentUserName,
    required VoidCallback onMaximize,
    required VoidCallback onEnd,
    VoidCallback? onToggleMute,
    VoidCallback? onToggleCamera,
    bool isMicMuted = false,
    bool isCameraEnabled = true,
  }) {
    _isCallActive = true;
    _isMinimized = false;
    _callType = callType;
    _otherUserName = otherUserName;
    _otherUserId = otherUserId;
    _currentUserId = currentUserId;
    _currentUserName = currentUserName;
    _onMaximize = onMaximize;
    _onEnd = onEnd;
    _onToggleMute = onToggleMute;
    _onToggleCamera = onToggleCamera;
    _isMicMuted = isMicMuted;
    _isCameraEnabled = isCameraEnabled;
    notifyListeners();
  }

  void updateCallState({
    required String statusText,
    Duration? duration,
    bool? isMinimized,
    bool? isMicMuted,
    bool? isCameraEnabled,
  }) {
    if (!_isCallActive) {
      return;
    }
    _statusText = statusText;
    if (duration != null) {
      _duration = duration;
    }
    if (isMinimized != null) {
      _isMinimized = isMinimized;
    }
    if (isMicMuted != null) {
      _isMicMuted = isMicMuted;
    }
    if (isCameraEnabled != null) {
      _isCameraEnabled = isCameraEnabled;
    }
    notifyListeners();
  }

  void minimizeCall() {
    if (_isCallActive && !_isMinimized) {
      _isMinimized = true;
      notifyListeners();
    }
  }

  void maximizeCall() {
    if (_isCallActive && _isMinimized) {
      _isMinimized = false;
      notifyListeners();
      _onMaximize?.call();
    }
  }

  void endCall() {
    final onEnd = _onEnd;
    if (onEnd != null) {
      onEnd();
      return;
    }
    reset();
  }

  void toggleMute() {
    _onToggleMute?.call();
  }

  void toggleCamera() {
    _onToggleCamera?.call();
  }

  void reset() {
    _isCallActive = false;
    _isMinimized = false;
    _callType = null;
    _otherUserName = null;
    _otherUserId = null;
    _currentUserId = null;
    _currentUserName = null;
    _statusText = 'Calling...';
    _duration = Duration.zero;
    _isMicMuted = false;
    _isCameraEnabled = true;
    _onMaximize = null;
    _onEnd = null;
    _onToggleMute = null;
    _onToggleCamera = null;
    notifyListeners();
  }
}

Future<void> openMinimizedCallHost(BuildContext context) async {
  CallOverlayManager().minimizeCall();
  await Navigator.of(context).push(
    MaterialPageRoute(
      settings: const RouteSettings(name: minimizedCallHostRouteName),
      builder: (_) => const MainControllerScreen(initialIndex: 0),
    ),
  );
}

class CallMinimizeButton extends StatelessWidget {
  final VoidCallback onPressed;

  const CallMinimizeButton({
    super.key,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF7C4DFF), Color(0xFF00C6FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7C4DFF).withOpacity(0.35),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(22),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.picture_in_picture_alt_rounded,
                    color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text(
                  'Minimize',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// IncomingCallOverlay  — WhatsApp-style incoming-call banner
// ─────────────────────────────────────────────────────────────────────────────
class IncomingCallOverlay extends StatelessWidget {
  const IncomingCallOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final mgr = IncomingCallOverlayManager();

    return AnimatedBuilder(
      animation: mgr,
      builder: (context, _) {
        // Hide if dismissed or if the fullscreen call screen is already open
        if (!mgr.isVisible || CallManager().isCallScreenShowing) {
          return const SizedBox.shrink();
        }

        final callerName = mgr.callerName;
        final isVideo = mgr.isVideo;
        final data = mgr.callData!;

        return Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          left: 12,
          right: 12,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0D1B2A), Color(0xFF1B3A4B)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.white.withOpacity(0.10)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.40),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // Icon + pulse
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: isVideo
                          ? const Color(0xFF7C4DFF).withOpacity(0.20)
                          : const Color(0xFF00C853).withOpacity(0.20),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                      color: isVideo
                          ? const Color(0xFF7C4DFF)
                          : const Color(0xFF00C853),
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Caller info
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _openFullScreen(context, data, isVideo),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            callerName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.circle,
                                size: 8,
                                color: const Color(0xFF69F0AE),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                isVideo
                                    ? 'Incoming video call'
                                    : 'Incoming voice call',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.72),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Reject button
                  _RoundButton(
                    icon: Icons.call_end_rounded,
                    color: const Color(0xFFFF4F4F),
                    onPressed: () => _reject(data, isVideo),
                  ),
                  const SizedBox(width: 10),
                  // Accept button
                  _RoundButton(
                    icon: isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                    color: const Color(0xFF00C853),
                    onPressed: () => _accept(context, data, isVideo),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _reject(Map<String, dynamic> data, bool isVideo) {
    IncomingCallOverlayManager().dismiss();
    CallManager().clearCallData();

    final callerId = data['callerId']?.toString() ?? '';
    final channelName = data['channelName']?.toString() ?? '';
    // Read current user from socket service
    final currentUserId = SocketService().currentUserId ?? '';

    if (callerId.isNotEmpty && currentUserId.isNotEmpty) {
      SocketService().emitCallReject(
        callerId: callerId,
        recipientId: currentUserId,
        recipientName: '',
        channelName: channelName,
        callType: isVideo ? 'video' : 'audio',
      );
    }
    NotificationService.sendCallResponseNotification(
      callerId: callerId,
      recipientName: '',
      accepted: false,
      recipientUid: '0',
      channelName: channelName,
    ).catchError((_) => false);
  }

  void _accept(BuildContext context, Map<String, dynamic> data, bool isVideo) {
    IncomingCallOverlayManager().dismiss();
    _openFullScreen(context, data, isVideo);
  }

  void _openFullScreen(
      BuildContext context, Map<String, dynamic> data, bool isVideo) {
    // Dismiss the compact banner first so it doesn't coexist with the full-screen.
    IncomingCallOverlayManager().dismiss();
    if (CallManager().isCallScreenShowing) return;
    CallManager().isCallScreenShowing = true;

    // Wait one frame so the overlay widget rebuilds to hidden before pushing
    // the fullscreen route — otherwise the banner renders on top of the call UI.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final currentState = navigatorKey.currentState;
      if (currentState == null) {
        CallManager().isCallScreenShowing = false;
        return;
      }
      final route = MaterialPageRoute(
        settings: const RouteSettings(name: activeCallRouteName),
        fullscreenDialog: true,
        builder: (_) => isVideo
            ? IncomingVideoCallScreen(callData: data)
            : IncomingCallScreen(callData: data),
      );
      currentState.push(route).whenComplete(() {
        CallManager().isCallScreenShowing = false;
      });
    });
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  const _RoundButton({
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withOpacity(0.18),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(icon, color: color, size: 24),
        ),
      ),
    );
  }
}

/// Widget that displays minimized call overlay
class MinimizedCallOverlay extends StatelessWidget {
  const MinimizedCallOverlay({super.key});

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final manager = CallOverlayManager();

    return AnimatedBuilder(
      animation: manager,
      builder: (context, child) {
        if (!manager.isCallActive || !manager.isMinimized) {
          return const SizedBox.shrink();
        }

        final subtitle = manager.isConnected
            ? _formatDuration(manager.duration)
            : manager.statusText;

        return Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          left: 12,
          right: 12,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1F1C2C), Color(0xFF2B5876)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.28),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: manager.maximizeCall,
                          borderRadius: BorderRadius.circular(16),
                          child: Row(
                            children: [
                              Container(
                                width: 46,
                                height: 46,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  manager.isVideoCall
                                      ? Icons.videocam_rounded
                                      : Icons.call_rounded,
                                  color: Colors.white,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      manager.otherUserName ?? 'Unknown',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.10),
                                        borderRadius:
                                            BorderRadius.circular(999),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            manager.isConnected
                                                ? Icons
                                                    .fiber_manual_record_rounded
                                                : Icons.wifi_calling_3_rounded,
                                            size: 12,
                                            color: manager.isConnected
                                                ? const Color(0xFF52E5A3)
                                                : const Color(0xFFFFD166),
                                          ),
                                          const SizedBox(width: 6),
                                          Flexible(
                                            child: Text(
                                              subtitle,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      _OverlayIconButton(
                        icon: Icons.open_in_full_rounded,
                        color: const Color(0xFF00C2FF),
                        onPressed: manager.maximizeCall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _OverlayActionButton(
                          icon: manager.isMicMuted
                              ? Icons.mic_off_rounded
                              : Icons.mic_rounded,
                          label: manager.isMicMuted ? 'Unmute' : 'Mute',
                          color: manager.isMicMuted
                              ? const Color(0xFFFFB703)
                              : const Color(0xFF5D9CEC),
                          onPressed: manager.toggleMute,
                        ),
                      ),
                      if (manager.isVideoCall) ...[
                        const SizedBox(width: 10),
                        Expanded(
                          child: _OverlayActionButton(
                            icon: manager.isCameraEnabled
                                ? Icons.videocam_rounded
                                : Icons.videocam_off_rounded,
                            label: manager.isCameraEnabled
                                ? 'Camera on'
                                : 'Camera off',
                            color: manager.isCameraEnabled
                                ? const Color(0xFF8E7CFF)
                                : const Color(0xFF6C757D),
                            onPressed: manager.toggleCamera,
                          ),
                        ),
                      ],
                      const SizedBox(width: 10),
                      Expanded(
                        child: _OverlayActionButton(
                          icon: Icons.call_end_rounded,
                          label: 'End',
                          color: const Color(0xFFFF5A5F),
                          onPressed: manager.endCall,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _OverlayIconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  const _OverlayIconButton({
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withOpacity(0.18),
      shape: const CircleBorder(),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, color: color, size: 20),
      ),
    );
  }
}

class _OverlayActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;

  const _OverlayActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withOpacity(0.08),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Wrapper widget that adds minimized call overlay to any screen and listens for incoming calls
class CallOverlayWrapper extends StatefulWidget {
  final Widget child;

  const CallOverlayWrapper({
    super.key,
    required this.child,
  });

  @override
  State<CallOverlayWrapper> createState() => _CallOverlayWrapperState();
}

class _CallOverlayWrapperState extends State<CallOverlayWrapper>
    with WidgetsBindingObserver {
  StreamSubscription<Map<String, dynamic>>? _incomingCallSubscription;
  StreamSubscription<Map<String, dynamic>>? _callCancelledSubscription;
  // Prevent multiple simultaneous call-screen pushes
  bool _isNavigatingToCall = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setupIncomingCallListener();
    _setupCallCancelledListener();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When the app comes to the foreground, check if a call notification
    // arrived while the app was in the background (separate Dart isolate),
    // which would NOT have triggered the in-app stream.
    if (state == AppLifecycleState.resumed) {
      _checkPendingIncomingCall();
    }
  }

  static const int _kIncomingCallExpiryMs = 60000; // 60 seconds

  /// Reads any incoming-call data that was saved by the background isolate
  /// and navigates to the appropriate call screen.
  Future<void> _checkPendingIncomingCall() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingStr = prefs.getString('pending_incoming_call');
      if (pendingStr == null) return;

      final data = json.decode(pendingStr) as Map<String, dynamic>;
      final receivedAt = data['_receivedAt'] as int?;
      final now = DateTime.now().millisecondsSinceEpoch;

      // Discard stale entries (> 60 s – after which the call would time out)
      if (receivedAt == null || now - receivedAt > _kIncomingCallExpiryMs) {
        await prefs.remove('pending_incoming_call');
        return;
      }

      // Remove before navigating to prevent re-processing
      await prefs.remove('pending_incoming_call');

      final isVideoCall =
          data['type'] == 'video_call' || data['isVideoCall'] == 'true';
      // Guard: if banner or full-screen already open (e.g. notification action fired first)
      if (IncomingCallOverlayManager().isVisible ||
          CallManager().isCallScreenShowing) {
        return;
      }
      // Show the compact overlay banner on background-resume
      _showIncomingOverlay(data, isVideoCall);
    } catch (e) {
      debugPrint('❌ Error checking pending incoming call: $e');
    }
  }

  void _setupCallCancelledListener() {
    _callCancelledSubscription?.cancel();
    _callCancelledSubscription = SocketService().onCallCancelled.listen((data) {
      // If the overlay is showing and belongs to this cancelled call, dismiss it
      if (IncomingCallOverlayManager().isVisible) {
        final overlayChannel =
            IncomingCallOverlayManager().callData?['channelName']?.toString();
        final cancelledChannel = data['channelName']?.toString();
        if (overlayChannel == null ||
            cancelledChannel == null ||
            overlayChannel == cancelledChannel) {
          IncomingCallOverlayManager().dismiss();
          CallManager().clearCallData();
        }
      }
    });
  }

  void _setupIncomingCallListener() {
    // Cancel any existing subscription before creating a new one
    _incomingCallSubscription?.cancel();
    _incomingCallSubscription = NotificationService.incomingCalls.listen(
      (data) {
        print('📱 CallOverlayWrapper: Incoming call received: $data');
        final isVideoCall =
            data['type'] == 'video_call' || data['isVideoCall'] == 'true';
        // Dismiss keyboard so the call overlay is not hidden behind it.
        FocusManager.instance.primaryFocus?.unfocus();
        WidgetsBinding.instance.scheduleFrame();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showIncomingOverlay(data, isVideoCall);
        });
      },
      onError: (error, stackTrace) {
        print('❌ Error in incoming call stream: $error');
        print('Stack trace: $stackTrace');
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) _setupIncomingCallListener();
        });
      },
      cancelOnError: false,
    );
  }

  /// Shows the compact WhatsApp-style incoming-call banner overlay.
  /// Falls back to full-screen when the app is being resumed from background
  /// (called from _checkPendingIncomingCall).
  void _showIncomingOverlay(
    Map<String, dynamic> data,
    bool isVideoCall, {
    bool forceFullScreen = false,
    int retryCount = 0,
    int maxRetries = 3,
  }) {
    // Guard: don't show if already in an active call → auto-reject as busy
    if (CallOverlayManager().isCallActive) {
      final callerId = data['callerId']?.toString() ?? '';
      final currentUserId = CallOverlayManager()._currentUserId ?? '';
      final channelName = data['channelName']?.toString() ?? '';
      if (callerId.isNotEmpty && currentUserId.isNotEmpty) {
        SocketService().emitCallReject(
          callerId: callerId,
          recipientId: currentUserId,
          recipientName: CallOverlayManager()._currentUserName ?? '',
          channelName: channelName,
          callType: isVideoCall ? 'video' : 'audio',
        );
      }
      CallManager().clearCallData();
      return;
    }

    // Guard: don't show if call screen already visible
    if (CallManager().isCallScreenShowing) return;

    // Guard: don't show if overlay already visible for this channel
    if (IncomingCallOverlayManager().isVisible) {
      final existingChannel =
          IncomingCallOverlayManager().callData?['channelName']?.toString();
      final newChannel = data['channelName']?.toString();
      if (existingChannel == newChannel) return;
      // Different call — dismiss old and show new
      IncomingCallOverlayManager().dismiss();
    }

    if (forceFullScreen) {
      // Background-resume path: go directly to full-screen incoming call screen
      _pushCallScreen(data, isVideoCall,
          retryCount: retryCount, maxRetries: maxRetries);
      return;
    }

    // Show the compact overlay banner (foreground / active app)
    IncomingCallOverlayManager().show(data, isVideo: isVideoCall);
  }

  /// Pushes the incoming call full-screen.  Used by _showIncomingOverlay
  /// (force path) and also called from IncomingCallOverlay when user taps Accept.
  void _pushCallScreen(
    Map<String, dynamic> data,
    bool isVideoCall, {
    int retryCount = 0,
    int maxRetries = 3,
  }) {
    if (_isNavigatingToCall) return;
    if (CallManager().isCallScreenShowing) return;

    final currentState = navigatorKey.currentState;
    if (currentState == null) {
      if (retryCount < maxRetries) {
        Future.delayed(Duration(milliseconds: 400 * (retryCount + 1)), () {
          if (mounted) {
            _pushCallScreen(data, isVideoCall,
                retryCount: retryCount + 1, maxRetries: maxRetries);
          }
        });
      } else {
        print('❌ Navigator state unavailable after $maxRetries retries');
      }
      return;
    }

    _isNavigatingToCall = true;
    CallManager().isCallScreenShowing = true;
    final route = MaterialPageRoute(
      settings: const RouteSettings(name: activeCallRouteName),
      fullscreenDialog: true,
      builder: (context) => isVideoCall
          ? IncomingVideoCallScreen(callData: data)
          : IncomingCallScreen(callData: data),
    );
    try {
      currentState.push(route).whenComplete(() {
        _isNavigatingToCall = false;
        CallManager().isCallScreenShowing = false;
      });
    } catch (_) {
      _isNavigatingToCall = false;
      CallManager().isCallScreenShowing = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _incomingCallSubscription?.cancel();
    _callCancelledSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        const MinimizedCallOverlay(),
        const IncomingCallOverlay(),
      ],
    );
  }
}
