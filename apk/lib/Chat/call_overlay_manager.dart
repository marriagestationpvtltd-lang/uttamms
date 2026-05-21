import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    if (dart.library.html) 'package:ms2026/utils/web_local_notifications_stub.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../pushnotification/pushservice.dart';
import '../Calling/callmanager.dart';
import '../Calling/incommingcall.dart';
import '../Calling/incomingvideocall.dart';
import '../navigation/app_navigation.dart';
import '../Startup/MainControllere.dart';
import '../service/socket_service.dart';
import '../service/audio_manager.dart';

part 'call_overlay_manager_incoming.dart';
part 'call_overlay_manager_actions.dart';
part 'call_overlay_manager_widgets.dart';
part 'call_overlay_manager_ringtone.dart';
part 'call_overlay_manager_controls.dart';

const String activeCallRouteName = '/active-call';
const String minimizedCallHostRouteName = '/minimized-call-host';

// ─────────────────────────────────────────────────────────────────────────────
// Sanitize caller display name (remove hash, format member codes)

String _sanitizeCallerName(String? rawName) {
  if (rawName == null || rawName.isEmpty) return 'Unknown';

  final trimmed = rawName.trim();
  final parts = trimmed
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty && !p.startsWith('#'))
      .toList();

  if (parts.isEmpty) return 'Unknown';

  // Try to find non-numeric parts for a real name
  final nameParts = parts.where((p) {
    final clean = p.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    return !RegExp(r'^(ms)?\d+$', caseSensitive: false).hasMatch(clean);
  }).toList();

  final lastName = nameParts.isNotEmpty ? nameParts.last : 'Member';

  // Check if first part is a member code
  final firstPart = parts.first;
  final compactFirst = firstPart.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');

  if (RegExp(r'^\d+$').hasMatch(compactFirst)) {
    return 'ms$compactFirst $lastName';
  } else if (RegExp(r'^ms\d+$', caseSensitive: false).hasMatch(compactFirst)) {
    return '$compactFirst $lastName';
  }

  return lastName;
}

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
  Timer? _ringTimer;

  bool get isVisible => _visible;
  Map<String, dynamic>? get callData => _callData;
  bool get isVideo => _isVideo;

  String get callerName =>
      _callData?['callerName']?.toString() ?? 'Unknown Caller';

  String get sanitizedCallerName => _sanitizeCallerName(callerName);

  void show(Map<String, dynamic> data, {required bool isVideo}) {
    // Guard: never show the compact banner when the full-screen incoming /
    // active call screen is already on top. Otherwise the two UIs stack and
    // dismissing the banner can also end the call (banner Reject button ➜
    // emitCallReject) even though the user has already accepted in the
    // full-screen UI. Fixes the dual-UI bug on cold-start-from-notification.
    if (CallManager().isCallScreenShowing) {
      debugPrint(
          'IncomingCallOverlayManager.show suppressed — full-screen call already visible');
      return;
    }
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
    // Cancel any lingering call notification (voice ID:1001, video ID:1002) so
    // it cannot be tapped to re-open a call screen after the call has ended.
    try {
      final plugin = FlutterLocalNotificationsPlugin();
      plugin.cancel(1001);
      plugin.cancel(1002);
    } catch (_) {}
    // Clear the pending-incoming-call SharedPrefs key so
    // _checkPendingIncomingCall does not re-surface this call on app resume.
    SharedPreferences.getInstance()
        .then((p) => p.remove('pending_incoming_call'))
        .catchError((_) => false);
    notifyListeners();
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
                border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.40),
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
                          ? const Color(0xFF7C4DFF).withValues(alpha: 0.20)
                          : const Color(0xFF00C853).withValues(alpha: 0.20),
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
                            _sanitizeCallerName(callerName),
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
                                  color: Colors.white.withValues(alpha: 0.72),
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
}

/// Widget that displays minimized call overlay
class MinimizedCallOverlay extends StatelessWidget {
  const MinimizedCallOverlay({super.key});

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
            ? formatCallDuration(manager.duration)
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
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.28),
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
                                  color: Colors.white.withValues(alpha: 0.12),
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
                                      _sanitizeCallerName(
                                          manager.otherUserName),
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
                                        color: Colors.white
                                            .withValues(alpha: 0.10),
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
