import 'dart:io' if (dart.library.html) 'package:ms2026/utils/web_io_stub.dart';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:audioplayers/audioplayers.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart'
    if (dart.library.html) 'package:ms2026/utils/web_permission_stub.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'package:uuid/uuid.dart';
import '../Calling/OutgoingCall.dart';
import '../service/verification_service.dart';
import '../Calling/videocall.dart';
import '../Calling/call_history_model.dart';
import '../Calling/call_history_service.dart';
import '../Calling/callmanager.dart';
import '../Calling/incommingcall.dart';
import '../Calling/incomingvideocall.dart';
import '../core/user_state.dart';
import '../pushnotification/pushservice.dart';
import '../service/chat_message_cache.dart';
import '../service/socket_service.dart';
import '../service/chat_message_cache.dart';
import '../service/sound_settings_service.dart';
import 'call_overlay_manager.dart';
import 'ChatdetailsScreen.dart';
import 'screen_state_manager.dart';
import '../Models/masterdata.dart';
import '../Package/PackageScreen.dart';
import '../otherenew/othernew.dart';
import '../utils/image_utils.dart';
import '../utils/privacy_utils.dart';
import '../utils/time_utils.dart';
import 'package:ms2026/config/app_endpoints.dart';
import 'widgets/typing_indicator.dart';
import 'package:cached_network_image/cached_network_image.dart';

class AdminChatScreen extends StatefulWidget {
  final String senderID;
  final String userName;
  final bool isAdmin;
  final Map<String, dynamic>? initialProfileData; // Optional profile card data

  const AdminChatScreen({
    super.key,
    required this.senderID,
    required this.userName,
    this.isAdmin = false,
    this.initialProfileData, // Make it optional
  });

  @override
  State<AdminChatScreen> createState() => _AdminChatScreenState();
}

class _AdminChatScreenState extends State<AdminChatScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  static const String _adminUserId = '1';
  static const String _adminUserName = 'Admin';

  final SocketService _socketService = SocketService();
  final Uuid _uuid = Uuid();

  final TextEditingController _controller = TextEditingController();
  final FocusNode _messageFocusNode = FocusNode();
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isSending = false;

  // Voice message playback tracking
  String? _playingMessageId;
  bool _isPlaying = false;
  Duration _playbackPosition = Duration.zero;
  Duration _playbackDuration = Duration.zero;
  StreamSubscription? _audioPlayerStateSub;
  StreamSubscription? _audioPlayerPositionSub;
  StreamSubscription? _audioPlayerDurationSub;

  // Voice message recording
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  bool _isSendingVoice = false;
  int _recordDuration = 0;
  Timer? _recordTimer;
  AnimationController? _recordingAnimController;
  String? _replyToID;
  Map<String, dynamic>? _replyToMessage;
  final ScrollController _scrollController = ScrollController();
  final List<String> _suggestedMessages = [
    "How can I verify my profile?",
    "I need help with subscription plans",
    "How do I contact a potential match?",
    "I want to report a suspicious profile",
    "Can you help me with profile suggestions?",
    "How do I reset my password?",
    "I'm having technical issues with the app"
  ];
  bool _showSuggestedMessages = true;
  bool _isFirstLoad = true;
  bool _profileCardSent = false; // Track if profile card was sent
  String _currentUserImage = ''; // Store current user image
  String _currentUserName = ''; // Store current user's full name for calls

  static const int _messagePageSize = 30;

  // Pagination & cache
  List<Map<String, dynamic>> _cachedMessages = [];
  bool _isLoadingMore = false;
  bool _hasMoreMessages = true;
  int _currentPage = 1;
  StreamSubscription<Map<String, dynamic>>? _msgSubscription;
  StreamSubscription<Map<String, dynamic>>? _msgLikedSubscription;
  StreamSubscription<Map<String, dynamic>>? _msgReactionSubscription;
  StreamSubscription<Map<String, dynamic>>? _msgReadSubscription;
  bool _streamLoading = true;
  bool _streamHasError = false;

  // Scroll lock during message loading to prevent screen shaking
  bool _scrollLocked = true;
  bool _initialScrollDone = false;

  // Admin online status
  bool _adminOnline = false;
  DateTime? _adminLastSeen;
  StreamSubscription<Map<String, dynamic>>? _adminStatusSubscription;

  // Typing indicator
  bool _isAdminTyping = false;
  Timer? _typingTimer;
  Timer? _typingStopTimer;
  Timer? _typingRepeatTimer; // Repeating click while admin is typing
  StreamSubscription<Map<String, dynamic>>? _typingStartSubscription;
  StreamSubscription<Map<String, dynamic>>? _typingStopSubscription;
  final AudioPlayer _typingAudioPlayer = AudioPlayer();
  final AudioPlayer _receiveAudioPlayer = AudioPlayer();

  // Swipe-to-reply offsets (keyed by message ID)
  final Map<String, double> _swipeOffsets = {};

  // Message long-press action overlay state
  bool _showMsgOverlay = false;
  Map<String, dynamic>? _selectedMsg;
  Offset _selectedMsgOffset = Offset.zero;
  bool _selectedMsgIsMe = false;

  // Call history
  List<CallHistory> _callHistory = [];
  bool _showCallHistory = false;
  bool _callHistoryLoaded = false;

  // Incoming call listener (backup for when CallOverlayWrapper doesn't fire)
  StreamSubscription<Map<String, dynamic>>? _incomingCallSubscription;

  // Current user verification state is read from the global UserState provider.
  /// The chat room ID shared between this user and admin, generated by sorting
  /// both participant IDs lexicographically and joining with '_'.
  String get _chatRoomId {
    final ids = [widget.senderID, _adminUserId]..sort();
    return ids.join('_');
  }

  /// The ID of whoever is currently sending (this device's user).
  String get _mySenderId => widget.isAdmin ? _adminUserId : widget.senderID;

  /// The ID of the other side.
  String get _otherPartyId => widget.isAdmin ? widget.senderID : _adminUserId;

// Updated color scheme with gradients
  final LinearGradient _primaryGradient = const LinearGradient(
    colors: [Color(0xFF6B46C1), Color(0xFF9F7AEA)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  final LinearGradient _secondaryGradient = const LinearGradient(
    colors: [Color(0xFFE9D5FF), Color(0xFFD6BCFA)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
  final Color _accentColor = const Color(0xFFEC4899);
  final Color _backgroundColor = const Color(0xFFF8FAFC);
  final Color _textColor = const Color(0xFF1F2937);
  final Color _lightTextColor = const Color(0xFF6B7280);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadUserImage();
    _scrollController.addListener(_onScroll);

    _recordingAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    // Load cached messages synchronously from the pre-warmed singleton so the
    // screen shows content immediately on the first frame — no spinner flash.
    final syncCached = ChatMessageCache.instance.getMessages(_chatRoomId);
    if (syncCached.isNotEmpty) {
      _cachedMessages = syncCached;
      _isFirstLoad = false;
      _streamLoading = false;
      _showSuggestedMessages = false;
      // Position scroll to bottom after the first frame, then unlock.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _initialScrollDone = true;
        if (mounted && _scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
        if (mounted) setState(() => _scrollLocked = false);
      });
    }

    // Voice audio player listeners
    _audioPlayerStateSub = _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state == PlayerState.playing;
          if (state == PlayerState.completed) {
            _playingMessageId = null;
            _playbackPosition = Duration.zero;
          }
        });
      }
    });
    _audioPlayerPositionSub = _audioPlayer.onPositionChanged.listen((pos) {
      if (mounted) setState(() => _playbackPosition = pos);
    });
    _audioPlayerDurationSub = _audioPlayer.onDurationChanged.listen((dur) {
      if (mounted) setState(() => _playbackDuration = dur);
    });

    _startAdminStatusListener();
    _setupCallListener();
    _setupMessageListeners();
    _setupTypingListeners();
    ScreenStateManager().onChatScreenOpened(
      _chatRoomId,
      _mySenderId,
      partnerUserId: _otherPartyId,
    );

    // Connect / ensure socket is authenticated for this user
    if (!_socketService.isConnected) {
      SharedPreferences.getInstance().then((prefs) {
        final token = prefs.getString('bearer_token');
        _socketService.connect(_mySenderId, token: token);
      });
      // Load messages once the socket successfully connects
      StreamSubscription<bool>? connSub;
      connSub = _socketService.onConnectionChange.listen((connected) {
        if (connected && mounted) {
          connSub?.cancel();
          _socketService.joinRoom(_chatRoomId);
          _socketService.setActiveChat(_mySenderId, _chatRoomId);
          _loadMessages(reset: true);
          // Re-check admin online status now that the socket is up.
          // getUserStatus() returned false immediately when called earlier
          // because the socket wasn't connected yet.
          _startAdminStatusListener();
        }
      });
      // Timeout fallback: if socket doesn't connect within 15s, show error
      Future.delayed(const Duration(seconds: 15), () {
        if (mounted && _streamLoading) {
          connSub?.cancel();
          setState(() { _streamHasError = true; _streamLoading = false; });
        }
      });
    } else {
      _socketService.joinRoom(_chatRoomId);
      _socketService.setActiveChat(_mySenderId, _chatRoomId);
      _loadMessages(reset: true);
    }

    // Automatically send profile card if provided (optional)
    if (widget.initialProfileData != null && !_profileCardSent) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _sendProfileCard();
      });
    }
  }


  Future<void> _handleProfileCardChat(BuildContext context, String userId, String displayName) async {
    if (!context.mounted) return;

    final userState = context.read<UserState>();
    if (!await VerificationService.requireVerification(context)) return;
    if (!context.mounted) return;

    if (userState.usertype != 'paid') {
      _showUpgradeChatDialog(context);
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProfileScreen(userId: userId),
      ),
    );
  }

  Future<void> _handleProfileCardViewProfile(BuildContext context, String userId) async {
    if (!context.mounted) return;

    if (!await VerificationService.requireVerification(context)) return;
    if (!context.mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ProfileScreen(userId: userId)),
    );
  }

  void _showUpgradeChatDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Premium Membership Required'),
        content: const Text(
          'You have not taken a premium membership, therefore you cannot chat. '
          'Please upgrade your plan to start chatting.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SubscriptionPage()),
              );
            },
            child: const Text('Upgrade'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadUserImage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataString = prefs.getString('user_data');
      if (userDataString != null) {
        final userData = jsonDecode(userDataString);
        final firstName = userData['firstName']?.toString() ?? '';
        final lastName = userData['lastName']?.toString() ?? '';
        setState(() {
          _currentUserImage = userData['image']?.toString() ?? '';
          _currentUserName = '$firstName $lastName'.trim();
        });
      }
    } catch (e) {
      debugPrint('Error loading user image: $e');
    }
  }

  @override
  void dispose() {
    ScreenStateManager().onChatScreenClosed();
    WidgetsBinding.instance.removeObserver(this);
    _msgSubscription?.cancel();
    _msgLikedSubscription?.cancel();
    _msgReactionSubscription?.cancel();
    _msgReadSubscription?.cancel();
    _adminStatusSubscription?.cancel();
    _incomingCallSubscription?.cancel();
    _typingStartSubscription?.cancel();
    _typingStopSubscription?.cancel();
    _typingTimer?.cancel();
    _typingStopTimer?.cancel();
    _typingRepeatTimer?.cancel();
    _socketService.setActiveChat(_mySenderId, _chatRoomId, isActive: false);
    _socketService.leaveRoom(_chatRoomId);
    _scrollController.removeListener(_onScroll);
    _controller.dispose();
    _messageFocusNode.dispose();
    _audioPlayer.dispose();
    _typingAudioPlayer.dispose();
    _receiveAudioPlayer.dispose();
    _recordTimer?.cancel();
    _audioRecorder.dispose();
    _recordingAnimController?.dispose();
    _audioPlayerStateSub?.cancel();
    _audioPlayerPositionSub?.cancel();
    _audioPlayerDurationSub?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!_socketService.isConnected) {
        SharedPreferences.getInstance().then((prefs) {
          final token = prefs.getString('bearer_token');
          _socketService.connect(_mySenderId, token: token);
        });
      }
      ScreenStateManager().onChatScreenOpened(
        _chatRoomId,
        _mySenderId,
        partnerUserId: _otherPartyId,
      );
      _socketService.setActiveChat(_mySenderId, _chatRoomId);
      // Refresh admin online status on resume (status may have changed while
      // the app was in the background).
      _startAdminStatusListener();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      ScreenStateManager().onChatScreenClosed();
      _socketService.setActiveChat(_mySenderId, _chatRoomId, isActive: false);
    }
  }

  void _startAdminStatusListener() {
    _adminStatusSubscription?.cancel();

    // Fetch initial admin status
    _socketService.getUserStatus(_adminUserId).then((statusData) {
      if (!mounted) return;
      final bool online = statusData['isOnline'] == true;
      final DateTime? lastSeen = SocketService.parseTimestamp(statusData['lastSeen']);
      setState(() {
        _adminOnline = online;
        if (!online && lastSeen != null) _adminLastSeen = lastSeen;
      });
    }).catchError((e) {
      debugPrint('Error fetching admin status: $e');
    });

    // Listen for status changes
    _adminStatusSubscription =
        _socketService.onUserStatusChange.listen((data) {
      if (!mounted) return;
      final uid = data['userId']?.toString() ?? '';
      if (uid != _adminUserId) return;
      final bool online = data['isOnline'] == true;
      final DateTime? lastSeen = SocketService.parseTimestamp(data['lastSeen']);
      setState(() {
        _adminOnline = online;
        if (!online && lastSeen != null) _adminLastSeen = lastSeen;
      });
    });
  }

  // Set up Socket.IO listeners for new messages, likes, and read receipts.
  void _setupMessageListeners() {
    _msgSubscription?.cancel();
    _msgSubscription = _socketService.onNewMessage.listen((data) {
      if (!mounted) return;
      if (data['chatRoomId'] != _chatRoomId) return;
      final String msgId = data['messageId']?.toString() ?? '';
      if (msgId.isEmpty) return;
      // Avoid duplicates
      if (_cachedMessages.any((m) => m['messageId'] == msgId)) return;
      setState(() {
        _cachedMessages = [..._cachedMessages, data];
        if (_showSuggestedMessages) _showSuggestedMessages = false;
      });
      // Persist updated message list to cache
      ChatMessageCache.instance.saveMessages(_chatRoomId, _cachedMessages);
      // Auto-mark as read if the message is incoming
      final bool isMe = data['senderId']?.toString() == _mySenderId;
      if (!isMe) {
        _socketService.markRead(_chatRoomId, _mySenderId);
        _playReceiveSound();
      }
      _scrollToBottom();
    });

    _msgLikedSubscription?.cancel();
    _msgLikedSubscription = _socketService.onMessageLiked.listen((data) {
      if (!mounted) return;
      if (data['chatRoomId'] != _chatRoomId) return;
      final String msgId = data['messageId']?.toString() ?? '';
      final bool liked = data['liked'] == true;
      setState(() {
        _cachedMessages = _cachedMessages.map((m) {
          if (m['messageId'] == msgId) {
            return {...m, 'liked': liked};
          }
          return m;
        }).toList();
      });
    });

    _msgReactionSubscription?.cancel();
    _msgReactionSubscription = _socketService.onMessageReaction.listen((data) {
      if (!mounted) return;
      if (data['chatRoomId'] != _chatRoomId) return;
      final String msgId = data['messageId']?.toString() ?? '';
      final Map<String, dynamic> reactions =
          (data['reactions'] is Map) ? Map<String, dynamic>.from(data['reactions'] as Map) : {};
      setState(() {
        _cachedMessages = _cachedMessages.map((m) {
          if (m['messageId'] == msgId) {
            return {...m, 'reactions': reactions};
          }
          return m;
        }).toList();
      });
      ChatMessageCache.instance.saveMessages(_chatRoomId, _cachedMessages);
    });

    _msgReadSubscription?.cancel();
    _msgReadSubscription = _socketService.onMessagesRead.listen((data) {
      if (!mounted) return;
      if (data['chatRoomId'] != _chatRoomId) return;
      // Mark all messages sent by me as read
      setState(() {
        _cachedMessages = _cachedMessages.map((m) {
          if (m['senderId']?.toString() == _mySenderId) {
            return {...m, 'isRead': true};
          }
          return m;
        }).toList();
      });
    });
  }

  // Set up typing event listeners
  void _setupTypingListeners() {
    _typingStartSubscription?.cancel();
    _typingStartSubscription = _socketService.onTypingStart.listen((data) {
      if (!mounted) return;
      if (data['chatRoomId'] != _chatRoomId) return;
      // Only show typing indicator if it's from the admin (other party)
      if (data['userId']?.toString() == _adminUserId) {
        if (!_isAdminTyping) {
          setState(() => _isAdminTyping = true);
          _startTypingRepeat();
        }
        // Auto-hide after 3 seconds if no stop event received
        _typingStopTimer?.cancel();
        _typingStopTimer = Timer(const Duration(seconds: 3), () {
          _stopTypingRepeat();
          if (mounted) setState(() => _isAdminTyping = false);
        });
      }
    });

    _typingStopSubscription?.cancel();
    _typingStopSubscription = _socketService.onTypingStop.listen((data) {
      if (!mounted) return;
      if (data['chatRoomId'] != _chatRoomId) return;
      if (data['userId']?.toString() == _adminUserId) {
        _typingStopTimer?.cancel();
        _stopTypingRepeat();
        setState(() => _isAdminTyping = false);
      }
    });
  }

  // Start the repeating typewriter-click sound while the admin is typing.
  void _startTypingRepeat() {
    _typingRepeatTimer?.cancel();
    _playTypingSound(); // Immediate first click
    _typingRepeatTimer = Timer.periodic(const Duration(milliseconds: 130), (_) {
      if (!_isAdminTyping || !SoundSettingsService.instance.typingSoundEnabled) {
        _stopTypingRepeat();
        return;
      }
      _playTypingSound();
    });
  }

  // Cancel the repeating timer.
  void _stopTypingRepeat() {
    _typingRepeatTimer?.cancel();
    _typingRepeatTimer = null;
  }

  // Play typing sound — short, soft, Messenger-style
  void _playTypingSound() async {
    if (!SoundSettingsService.instance.typingSoundEnabled) return;
    try {
      await _typingAudioPlayer.stop();
      await _typingAudioPlayer.setVolume(0.3);
      await _typingAudioPlayer.play(AssetSource('audio/typing_tick.wav'));
    } catch (e) {
      debugPrint('Error playing typing sound: $e');
    }
  }

  // Play message-received sound and vibrate
  void _playReceiveSound() async {
    if (SoundSettingsService.instance.messageSoundEnabled) {
      try {
        await _receiveAudioPlayer.stop();
        await _receiveAudioPlayer.setVolume(0.6);
        await _receiveAudioPlayer.play(AssetSource('audio/message_received.wav'));
      } catch (e) {
        debugPrint('Error playing receive sound: $e');
      }
    }
    if (SoundSettingsService.instance.vibrationEnabled && !kIsWeb) {
      HapticFeedback.mediumImpact();
    }
  }

  // Emit typing start event
  void _onUserTyping() {
    _typingTimer?.cancel();
    _socketService.startTyping(_chatRoomId, _mySenderId);
    // Auto-stop typing after 3 seconds
    _typingTimer = Timer(const Duration(seconds: 3), () {
      _socketService.stopTyping(_chatRoomId, _mySenderId);
    });
  }

  // Emit typing stop event
  void _onUserStopTyping() {
    _typingTimer?.cancel();
    _socketService.stopTyping(_chatRoomId, _mySenderId);
  }

  // Backup incoming call listener so that calls ring even while the user is
  // typing on this screen.  The global CallOverlayWrapper handles calls for
  // the rest of the app; this method ensures that if it does not fire (e.g.
  // due to a timing edge-case), AdminChatScreen still shows the call UI.
  void _setupCallListener() {
    _incomingCallSubscription?.cancel();
    _incomingCallSubscription = NotificationService.incomingCalls.listen((data) {
      final isVideoCall =
          data['type'] == 'video_call' || data['isVideoCall'] == 'true';
      FocusManager.instance.primaryFocus?.unfocus();
      WidgetsBinding.instance.scheduleFrame();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (CallManager().isCallScreenShowing) return;
        CallManager().isCallScreenShowing = true;
        try {
          Navigator.of(context)
              .push(
                MaterialPageRoute(
                  settings: const RouteSettings(name: activeCallRouteName),
                  fullscreenDialog: true,
                  builder: (_) => isVideoCall
                      ? IncomingVideoCallScreen(callData: data)
                      : IncomingCallScreen(callData: data),
                ),
              )
              .whenComplete(() {
            CallManager().isCallScreenShowing = false;
          });
        } catch (_) {
          CallManager().isCallScreenShowing = false;
        }
      });
    });
  }

  void _scrollToBottom() {
    // Don't auto-scroll if scroll is locked during initial load
    if (_scrollLocked) return;

    if (_scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;
        _scrollController.jumpTo(
          _scrollController.position.maxScrollExtent,
        );
      });
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels <=
        _scrollController.position.minScrollExtent + 200) {
      _loadMoreMessages();
    }
  }

  /// Load a page of messages from the server via Socket.IO ack.
  Future<void> _loadMessages({bool reset = false}) async {
    // Only reset scroll lock if the sync-cache path hasn't already unlocked it.
    if (reset) {
      setState(() {
        _streamLoading = true;
        _streamHasError = false;
        _currentPage = 1;
        _hasMoreMessages = true;
        // Don't re-lock or reset scroll if sync cache already positioned it.
        if (!_initialScrollDone) {
          _scrollLocked = true;
        }
      });
    }
    try {
      final result = await _socketService.getMessages(
        _chatRoomId,
        page: _currentPage,
        limit: _messagePageSize,
      );
      if (!mounted) return;
      final msgs = (result['messages'] as List? ?? [])
          .map((m) => Map<String, dynamic>.from(m as Map))
          .toList();
      final hasMore = result['hasMore'] == true;
      setState(() {
        if (reset) {
          _cachedMessages = msgs;
        } else {
          // Prepend older messages, avoid duplicates
          final existingIds = _cachedMessages.map((m) => m['messageId']).toSet();
          final newMsgs = msgs.where((m) => !existingIds.contains(m['messageId'])).toList();
          _cachedMessages = [...newMsgs, ..._cachedMessages];
        }
        _streamLoading = false;
        _hasMoreMessages = hasMore;
        if (reset && _isFirstLoad && _cachedMessages.isNotEmpty) {
          _isFirstLoad = false;
        }
        if (_showSuggestedMessages && _cachedMessages.isNotEmpty) {
          _showSuggestedMessages = false;
        }
      });
      if (reset) {
        if (_initialScrollDone) {
          // Sync-cache already positioned scroll; just jump to bottom for fresh data.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _scrollController.hasClients) {
              _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
            }
            if (mounted && _scrollLocked) setState(() => _scrollLocked = false);
          });
        } else {
          // Perform initial scroll only once, then unlock
          _performInitialScroll();
        }
      }
      // Persist fresh messages to the singleton cache so the next open is instant.
      if (reset) {
        ChatMessageCache.instance.saveMessages(_chatRoomId, _cachedMessages);
      }
      // After loading, join room and mark read
      _socketService.joinRoom(_chatRoomId);
      _socketService.setActiveChat(_mySenderId, _chatRoomId);
      _socketService.markRead(_chatRoomId, _mySenderId);
    } catch (e) {
      debugPrint('Error loading messages: $e');
      if (mounted) {
        setState(() {
          _streamHasError = true;
          _streamLoading = false;
          _scrollLocked = false;
        });
      }
    }
  }

  /// Performs the initial scroll to bottom only once, then unlocks scrolling.
  /// This prevents screen shaking from multiple scroll attempts.
  void _performInitialScroll() {
    if (_initialScrollDone) return;
    _initialScrollDone = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        // Jump again before unlocking in case layout changed between frames
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
          }
          if (mounted) setState(() => _scrollLocked = false);
        });
      } else {
        // Controller not yet attached; retry after layout
        Future.delayed(const Duration(milliseconds: 50), () {
          if (mounted && _scrollController.hasClients) {
            _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
          }
          if (mounted) setState(() => _scrollLocked = false);
        });
      }
    });
  }

  Future<void> _loadMoreMessages() async {
    if (_isLoadingMore || !_hasMoreMessages) return;
    setState(() => _isLoadingMore = true);
    final prevOffset = _scrollController.hasClients
        ? _scrollController.position.pixels
        : 0.0;
    final prevMaxExtent = _scrollController.hasClients
        ? _scrollController.position.maxScrollExtent
        : 0.0;
    _currentPage++;
    try {
      final result = await _socketService.getMessages(
        _chatRoomId,
        page: _currentPage,
        limit: _messagePageSize,
      );
      if (!mounted) return;
      final msgs = (result['messages'] as List? ?? [])
          .map((m) => Map<String, dynamic>.from(m as Map))
          .toList();
      final hasMore = result['hasMore'] == true;
      final existingIds = _cachedMessages.map((m) => m['messageId']).toSet();
      final newMsgs = msgs.where((m) => !existingIds.contains(m['messageId'])).toList();
      setState(() {
        _cachedMessages = [...newMsgs, ..._cachedMessages];
        _hasMoreMessages = hasMore;
        _isLoadingMore = false;
      });
      // Preserve scroll position by adjusting for new content added at top
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          final newMaxExtent = _scrollController.position.maxScrollExtent;
          _scrollController.jumpTo(prevOffset + (newMaxExtent - prevMaxExtent));
        }
      });
    } catch (e) {
      _currentPage--;
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _loadCallHistory() async {
    try {
      final all = await CallHistoryService.getCallHistoryPaginated(
          userId: widget.senderID, limit: 50);
      final filtered = all
          .where((c) =>
              (c.callerId == widget.senderID && c.recipientId == _adminUserId) ||
              (c.callerId == _adminUserId && c.recipientId == widget.senderID))
          .toList();
      if (mounted) setState(() {
        _callHistory = filtered;
        _callHistoryLoaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _callHistoryLoaded = true);
    }
  }

  String _formatDateForGrouping(DateTime dt) {
    final localDt = dt.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final d = DateTime(localDt.year, localDt.month, localDt.day);
    if (d == today) return 'Today';
    if (d == yesterday) return 'Yesterday';
    return DateFormat('MMM d, yyyy').format(localDt);
  }

  String _formatCallDateTime(DateTime dt) {
    return DateFormat('MMM d, h:mm a').format(dt.toLocal());
  }

  /// Send a profile card to admin.
  Future<void> _sendProfileCard() async {
    if (widget.initialProfileData == null || _profileCardSent) return;
    setState(() { _profileCardSent = true; });
    final profileData = Map<String, dynamic>.from(widget.initialProfileData!);
    profileData['timestamp'] = DateTime.now().toIso8601String();
    await _sendMessage('profile_card', jsonEncode(profileData));
  }

  /// Core send method — routes through Socket.IO.
  Future<void> _sendMessage(String type, String content, {String? imageUrl}) async {
    final messageId = _uuid.v4();
    // Determine receiver
    final receiverId = widget.isAdmin ? widget.senderID : _adminUserId;
    // Encode imageUrl into content for image messages
    String finalContent = content;
    if (type == 'image' && imageUrl != null) {
      finalContent = imageUrl;
    }
    // profile_card/report/call: content is already JSON-encoded message
    _socketService.sendMessage(
      chatRoomId: _chatRoomId,
      senderId: _mySenderId,
      receiverId: receiverId,
      message: finalContent,
      messageType: type,
      messageId: messageId,
      repliedTo: _replyToID != null
          ? _buildReplyPayload(_replyToID!, _replyToMessage ?? {})
          : null,
      user1Name: widget.isAdmin ? _adminUserName : widget.userName,
      user2Name: widget.isAdmin ? widget.userName : _adminUserName,
      user1Image: widget.isAdmin ? '' : _currentUserImage,
      user2Image: '',
    );
    setState(() {
      _replyToID = null;
      _replyToMessage = null;
      if (_showSuggestedMessages) _showSuggestedMessages = false;
    });
    _scrollToBottom();
  }

  Future<void> _sendText() async {
    if (_isSending) return;
    final text = _controller.text.trim();
    if (text.isNotEmpty) {
      _controller.clear();
      _messageFocusNode.requestFocus();
      setState(() { _isSending = true; });
      try {
        await _sendMessage('text', text);
      } finally {
        if (mounted) setState(() { _isSending = false; });
      }
    }
  }

  Future<void> _sendSuggestedMessage(String message) async {
    await _sendMessage('text', message);
  }

  Future<void> _sendDoc() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'jpg', 'jpeg', 'png'],
      withData: kIsWeb,
    );
    if (result != null) {
      final fileName = result.files.single.name;
      try {
        Uint8List bytes;
        if (kIsWeb) {
          bytes = result.files.single.bytes!;
        } else {
          bytes = await File(result.files.single.path!).readAsBytes();
        }
        final url = await _socketService.uploadChatImage(
          bytes: bytes,
          filename: fileName,
          userId: _mySenderId,
          chatRoomId: _chatRoomId,
        );
        await _sendMessage('doc', jsonEncode({'url': url, 'name': fileName}));
      } catch (e) {
        debugPrint('Doc upload error: $e');
      }
    }
  }

  Future<void> _sendImage() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: kIsWeb,
    );
    if (result == null || result.files.isEmpty) return;

    // Show preview before sending
    final confirmed = await _showImagePreviewSheet(result.files);
    if (confirmed != true || !mounted) return;

    setState(() => _isSending = true);
    try {
      final List<String> urls = [];
      for (final file in result.files) {
        Uint8List bytes;
        if (kIsWeb) {
          bytes = file.bytes!;
        } else {
          bytes = await File(file.path!).readAsBytes();
        }
        final url = await _socketService.uploadChatImage(
          bytes: bytes,
          filename: file.name,
          userId: _mySenderId,
          chatRoomId: _chatRoomId,
        );
        urls.add(url);
      }
      if (urls.length == 1) {
        await _sendMessage('image', urls[0], imageUrl: urls[0]);
      } else {
        await _sendMessage('image_gallery', jsonEncode(urls));
      }
    } catch (e) {
      debugPrint('Image upload error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send image: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  /// Shows a bottom sheet preview of selected images and returns true if user
  /// confirms sending.
  Future<bool?> _showImagePreviewSheet(List<PlatformFile> files) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ImagePreviewSheet(
        files: files,
        accentColor: _primaryGradient.colors[0],
      ),
    );
  }

  void _addReaction(String messageId, String emoji) {
    _socketService.addReaction(_chatRoomId, messageId, emoji);
  }

  // Facebook Messenger-style overlay: emoji bar near message, actions at bottom
  Widget _buildMsgActionOverlay() {
    const emojis = ['❤️', '😂', '😮', '😢', '👍', '😡'];
    final msgId = _selectedMsg?['messageId']?.toString() ??
        _selectedMsg?['id']?.toString() ?? '';
    final existingReactions = _selectedMsg?['reactions'];
    final Map<String, dynamic> reactions = (existingReactions is Map)
        ? Map<String, dynamic>.from(existingReactions as Map)
        : {};
    final myReaction = reactions[_mySenderId]?.toString() ?? '';
    final msgType =
        _selectedMsg?['messageType']?.toString() ?? _selectedMsg?['type']?.toString() ?? 'text';

    final screenHeight = MediaQuery.of(context).size.height;
    final tapY = _selectedMsgOffset.dy;

    const double emojiBarHeight = 56.0;
    const double gap = 10.0;
    double emojiTop;
    if (tapY - emojiBarHeight - gap < 80) {
      emojiTop = tapY + gap;
    } else {
      emojiTop = tapY - emojiBarHeight - gap;
    }
    emojiTop = emojiTop.clamp(60.0, screenHeight - emojiBarHeight - 180.0);

    return GestureDetector(
      onTap: () {
        if (mounted) setState(() => _showMsgOverlay = false);
      },
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: double.infinity,
        height: double.infinity,
        child: ColoredBox(
          color: Colors.black.withOpacity(0.45),
          child: Stack(
            children: [
              // Emoji bar near the long-pressed message
              Positioned(
                top: emojiTop,
                left: 0,
                right: 0,
                child: Center(
                  child: GestureDetector(
                    onTap: () {},
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.18),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: emojis.map((e) {
                          final isSelected = myReaction == e;
                          return GestureDetector(
                            onTap: () {
                              if (mounted) setState(() => _showMsgOverlay = false);
                              if (msgId.isNotEmpty) _addReaction(msgId, e);
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? _accentColor.withOpacity(0.15)
                                    : Colors.transparent,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                e,
                                style: TextStyle(fontSize: isSelected ? 28 : 24),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
              ),
              // Action panel anchored at the bottom
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: GestureDetector(
                  onTap: () {},
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFF1E1E1E),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        if (_selectedMsg != null)
                          _overlayMenuItem(Icons.reply_rounded, "Reply", () {
                            if (mounted) setState(() => _showMsgOverlay = false);
                            if (_selectedMsg != null) {
                              _setReplyTo(
                                _selectedMsg!['messageId']?.toString() ??
                                    _selectedMsg!['id']?.toString() ?? '',
                                _selectedMsg!,
                              );
                            }
                          }),
                        if (_selectedMsg != null && msgType == 'text')
                          _overlayMenuItem(Icons.copy, "Copy", () {
                            final text = _selectedMsg?['message']?.toString() ?? '';
                            if (text.isNotEmpty) {
                              Clipboard.setData(ClipboardData(text: text));
                              if (mounted) setState(() => _showMsgOverlay = false);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Message copied'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          }),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _overlayMenuItem(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 18),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 14),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 15)),
          ],
        ),
      ),
    );
  }

  // ── VOICE MESSAGE RECORDING ──────────────────────────────────────────────

  Future<void> _startRecording() async {
    if (_isRecording) return;
    if (!kIsWeb) {
      final status = await Permission.microphone.request();
      if (status != PermissionStatus.granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Microphone permission is required to send voice messages.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
    }
    try {
      String path;
      if (kIsWeb) {
        path = 'voice_${DateTime.now().millisecondsSinceEpoch}.webm';
      } else {
        final dir = await getTemporaryDirectory();
        path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      }
      await _audioRecorder.start(
        kIsWeb
            ? const RecordConfig(encoder: AudioEncoder.opus, bitRate: 64000, sampleRate: 44100)
            : const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000, sampleRate: 44100),
        path: path,
      );
      setState(() {
        _isRecording = true;
        _recordDuration = 0;
      });
      _recordingAnimController?.repeat();
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _recordDuration++);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start recording: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _stopAndSendRecording() async {
    if (!_isRecording) return;
    _recordTimer?.cancel();
    _recordTimer = null;
    _recordingAnimController?.stop();
    _recordingAnimController?.reset();
    try {
      final path = await _audioRecorder.stop();
      setState(() {
        _isRecording = false;
        _isSendingVoice = true;
      });
      if (path == null || path.isEmpty) return;
      Uint8List voiceBytes;
      if (kIsWeb) {
        voiceBytes = await XFile(path).readAsBytes();
      } else {
        voiceBytes = await File(path).readAsBytes();
      }
      final url = await _socketService.uploadVoiceMessage(
        bytes: voiceBytes,
        filename: 'voice_${DateTime.now().millisecondsSinceEpoch}.mp3',
        userId: _mySenderId,
        chatRoomId: _chatRoomId,
      );
      await _sendMessage('voice', url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send voice message: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() { _isRecording = false; _isSendingVoice = false; });
    }
  }

  void _cancelRecording() {
    if (!_isRecording) return;
    _recordTimer?.cancel();
    _recordTimer = null;
    _recordingAnimController?.stop();
    _recordingAnimController?.reset();
    _audioRecorder.stop();
    setState(() { _isRecording = false; _recordDuration = 0; });
  }

  String _formatRecordDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }


  Future<void> _setReplyTo(
      String messageID, Map<String, dynamic> messageData) async {
    setState(() {
      _replyToID = messageID;
      _replyToMessage = messageData;
    });
  }

  /// Returns a human-readable preview text for a message (used in reply bubbles
  /// and the chat list — mirrors WhatsApp convention).
  String _messagePreviewText(Map<String, dynamic> data) {
    final type = data['messageType'] ?? data['type'] ?? 'text';
    switch (type) {
      case 'image':
        return '📷 Photo';
      case 'image_gallery':
        return '📷 Photos';
      case 'voice':
        return '🎤 Voice message';
      case 'doc':
        return '📄 Document';
      case 'profile_card':
        return '👤 Profile shared';
      case 'report':
        return '🚩 Profile reported';
      default:
        return data['message']?.toString() ?? '';
    }
  }

  /// Builds the `repliedTo` map that gets stored with the outgoing message.
  /// For image/voice/doc types the `message` field holds a human-readable
  /// label rather than the raw URL so that every receiver can display it
  /// nicely without knowing the message type.
  Map<String, dynamic> _buildReplyPayload(
      String messageId, Map<String, dynamic> data) {
    final type = data['messageType'] ?? data['type'] ?? 'text';
    final senderIdR =
        data['senderId']?.toString() ?? data['senderid']?.toString() ?? '';
    final bool isFromMe = senderIdR == _mySenderId;
    final bool isFromAdmin = senderIdR == _adminUserId;
    final String senderName = isFromAdmin
        ? 'Admin'
        : (isFromMe ? 'You' : widget.userName);
    return {
      'messageId': messageId,
      'message': _messagePreviewText(data),
      'messageType': type,
      'senderName': senderName,
      if (type == 'image')
        // For image messages the socket server stores the URL in 'message';
        // 'imageUrl' is the redundant alias written by admin chathome.dart.
        'imageUrl': data['message']?.toString() ?? data['imageUrl']?.toString(),
      if (type == 'image_gallery')
        // For gallery messages, extract the first URL for the reply thumbnail.
        'imageUrl': _firstGalleryUrl(data['message']?.toString() ?? ''),
    };
  }

  Future<void> _playVoice(String url) async {
    try {
      await _audioPlayer.play(UrlSource(url));
    } catch (e) {
      print('Error playing audio: $e');
    }
  }

  Future<void> _toggleVoicePlayback(String voiceUrl) async {
    if (_playingMessageId == voiceUrl && _isPlaying) {
      await _audioPlayer.pause();
    } else if (_playingMessageId == voiceUrl && !_isPlaying) {
      await _audioPlayer.resume();
    } else {
      _playbackPosition = Duration.zero;
      _playbackDuration = Duration.zero;
      if (mounted) setState(() => _playingMessageId = voiceUrl);
      await _audioPlayer.play(UrlSource(voiceUrl));
    }
  }

// Updated message builder with swipe-to-reply
  Widget _buildMessageItem(Map<String, dynamic> data) {
    // Support both Socket.IO field names (senderId) and legacy (senderid)
    final String senderId = data['senderId']?.toString() ?? data['senderid']?.toString() ?? '';
    bool isMe = senderId == _mySenderId;
    final String msgID = data['messageId']?.toString() ?? data['id']?.toString() ?? '';
    // Parse timestamp: ISO string from Socket.IO; convert UTC → device local time
    final dynamic tsRaw = data['timestamp'];
    DateTime? tsDate;
    if (tsRaw is String) tsDate = DateTime.tryParse(tsRaw)?.toLocal();
    else if (tsRaw is DateTime) tsDate = tsRaw.isUtc ? tsRaw.toLocal() : tsRaw;
    String formattedTime = tsDate != null ? DateFormat('HH:mm').format(tsDate) : '';

    // Check if message is read
    final bool isRead = data['isRead'] == true || data['read'] == true;

    // Determine if message is from admin
    final bool isFromAdmin = senderId == _adminUserId;
    final String senderName =
        isFromAdmin ? "Admin Support" : (isMe ? "You" : widget.userName);

    // Render call events inline (WhatsApp-style)
    if (data['messageType'] == 'call' || data['type'] == 'call') {
      return _buildInlineCallBubble(data, tsDate);
    }

    // Render report messages as a special card
    // Also detect legacy messages stored as 'text' where content is a report JSON payload
    {
      final msgType = data['messageType']?.toString() ?? data['type']?.toString() ?? '';
      final rawMessage = data['message']?.toString() ?? '';
      Map<String, dynamic>? decodedReport;
      if (msgType == 'report') {
        try {
          final decoded = jsonDecode(rawMessage) as Map<String, dynamic>;
          if (decoded.containsKey('reportReason')) decodedReport = decoded;
        } catch (_) {}
      } else if (msgType == 'text' || msgType.isEmpty) {
        // Legacy: report was stored as text because server whitelist was missing 'report'
        try {
          final decoded = jsonDecode(rawMessage) as Map<String, dynamic>;
          if (decoded.containsKey('reportReason')) decodedReport = decoded;
        } catch (_) {}
      }
      if (decodedReport != null) {
        final reportData = {...data, ...decodedReport};
        return _buildReportMessageCard(reportData, isMe, formattedTime);
      }
    }

    double swipeOffset = _swipeOffsets[msgID] ?? 0.0;
    final Map<String, dynamic> reactions =
        (data['reactions'] is Map) ? Map<String, dynamic>.from(data['reactions'] as Map) : {};

    final String effectiveType = data['messageType']?.toString() ?? data['type']?.toString() ?? 'text';
    final String effectiveMessage = data['message'] ?? '';

    return StatefulBuilder(
      builder: (context, setItemState) {
        swipeOffset = _swipeOffsets[msgID] ?? 0.0;
        return GestureDetector(
          onLongPressStart: (details) {
            if (mounted) {
              setState(() {
                _selectedMsg = data;
                _selectedMsgIsMe = isMe;
                _selectedMsgOffset = details.globalPosition;
                _showMsgOverlay = true;
              });
            }
          },
          onHorizontalDragUpdate: (details) {
            if (details.delta.dx > 0) {
              setItemState(() {
                final newOffset = (swipeOffset + details.delta.dx).clamp(0.0, 70.0);
                _swipeOffsets[msgID] = newOffset;
                swipeOffset = newOffset;
              });
            }
          },
          onHorizontalDragEnd: (details) {
            if (swipeOffset > 50) {
              _setReplyTo(msgID, data);
            }
            setItemState(() {
              _swipeOffsets[msgID] = 0.0;
              swipeOffset = 0.0;
            });
          },
          child: Stack(
            children: [
              if (swipeOffset > 10)
                Positioned(
                  left: isMe ? null : 16,
                  right: isMe ? 16 : null,
                  top: 0, bottom: 0,
                  child: Center(
                    child: AnimatedOpacity(
                      opacity: (swipeOffset / 50).clamp(0.0, 1.0),
                      duration: const Duration(milliseconds: 100),
                      child: Icon(Icons.reply,
                          color: _primaryGradient.colors[0], size: 24),
                    ),
                  ),
                ),
              Transform.translate(
                offset: Offset(isMe ? -swipeOffset : swipeOffset, 0),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                  child: Row(
                    mainAxisAlignment:
                        isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
            if (!isMe)
              CircleAvatar(
                backgroundColor: Colors.transparent,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient:
                        isFromAdmin ? _primaryGradient : _secondaryGradient,
                  ),
                  child: Icon(
                    isFromAdmin ? Icons.support_agent : Icons.person,
                    color: Colors.white,
                  ),
                ),
              ),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment:
                    isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  if (!isMe)
                    Padding(
                      padding: const EdgeInsets.only(left: 12, bottom: 6),
                      child: Text(
                        senderName,
                        style: TextStyle(
                          fontSize: 14,
                          color: isRead ? _lightTextColor.withOpacity(0.8) : _lightTextColor,
                          fontWeight: isRead ? FontWeight.w500 : FontWeight.w700,
                         ),
                      ),
                    ),
                  // Profile card: render directly without gradient bubble
                  if (effectiveType == 'profile_card') ...[
                    _buildProfileCardMessage(_parseProfileCardData(data), isMe),
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        mainAxisAlignment:
                            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                        children: [
                          Text(
                            formattedTime,
                            style: TextStyle(
                              fontSize: 12,
                              color: _lightTextColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else if (effectiveType == 'image') ...[
                    // Single image: rendered outside the gradient bubble (fixes border issue)
                    _buildChatImageMessage(
                      data['message']?.toString() ?? data['imageUrl']?.toString(),
                      isMe,
                    ),
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        mainAxisAlignment:
                            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                        children: [
                          Text(
                            formattedTime,
                            style: TextStyle(fontSize: 12, color: _lightTextColor),
                          ),
                        ],
                      ),
                    ),
                  ] else if (effectiveType == 'image_gallery') ...[
                    // Multiple images: rendered as WhatsApp-style grid outside the gradient bubble
                    _buildChatGalleryGrid(
                      _parseGalleryUrls(data['message']?.toString() ?? '[]'),
                    ),
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        mainAxisAlignment:
                            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                        children: [
                          Text(
                            formattedTime,
                            style: TextStyle(fontSize: 12, color: _lightTextColor),
                          ),
                        ],
                      ),
                    ),
                  ] else
                  Container(
                    constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.75),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: isMe
                          ? (isRead
                              // Read messages: lighter, faded gradient
                              ? const LinearGradient(
                                  colors: [Color(0xFFF3E8FF), Color(0xFFEDE0FA)],
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                )
                              // Unread messages: darker, bolder gradient
                              : const LinearGradient(
                                  colors: [Color(0xFFD6BCFA), Color(0xFFC4B0E8)],
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                ))
                          : _primaryGradient,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(20),
                        topRight: const Radius.circular(20),
                        bottomLeft: isMe
                            ? const Radius.circular(20)
                            : const Radius.circular(4),
                        bottomRight: isMe
                            ? const Radius.circular(4)
                            : const Radius.circular(20),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(isMe || !isRead ? 0.15 : 0.08),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        )
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Reply preview — support both Socket.IO repliedTo map and legacy replyto string
                        Builder(builder: (_) {
                          final repliedToMap = data['repliedTo'] is Map
                              ? Map<String, dynamic>.from(data['repliedTo'] as Map)
                              : null;
                          final replyToId = repliedToMap?['messageId']?.toString()
                              ?? data['replyto']?.toString() ?? '';
                          if (replyToId.isNotEmpty) {
                            return Column(children: [
                              _buildReplyPreview(replyToId, isMe, inlinePayload: repliedToMap),
                              const SizedBox(height: 8),
                            ]);
                          }
                          return const SizedBox.shrink();
                        }),
                        if (effectiveType == 'text')
                          Text(
                            effectiveMessage,
                            style: TextStyle(
                              color: isMe
                                  ? (isRead
                                      ? _textColor.withOpacity(0.7)
                                      : _textColor)
                                  : Colors.white,
                              fontSize: 17,
                              fontWeight: !isMe || !isRead
                                  ? FontWeight.w500
                                  : FontWeight.w400,
                            ),
                          ),
                        if (effectiveType == 'voice')
                          _buildVoiceMessage(effectiveMessage, isMe),
                        if (effectiveType == 'doc')
                          _buildDocumentMessage(effectiveMessage, isMe),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              formattedTime,
                              style: TextStyle(
                                fontSize: 12,
                                color: isMe
                                    ? (isRead
                                        ? _lightTextColor.withOpacity(0.7)
                                        : _lightTextColor)
                                    : Colors.white70,
                                fontWeight: isMe && !isRead ? FontWeight.w500 : FontWeight.normal,
                              ),
                            ),
                          ],
                      ),
                    ],
                  ),
                ),
                  if (reactions.isNotEmpty)
                    _buildReactionBadge(reactions, isMe),
                ],
              ),
            ),
            if (isMe) const SizedBox(width: 8),
            if (isMe)
              CircleAvatar(
                backgroundColor: Colors.transparent,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient:
                        widget.isAdmin ? _primaryGradient : _secondaryGradient,
                  ),
                  child: Icon(
                    widget.isAdmin ? Icons.support_agent : Icons.person,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
              ),
            ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildReactionBadge(Map<String, dynamic> reactions, bool isMe) {
    // Group reactions by emoji and count them
    final Map<String, int> emojiCounts = {};
    for (final emoji in reactions.values) {
      final e = emoji.toString();
      emojiCounts[e] = (emojiCounts[e] ?? 0) + 1;
    }
    if (emojiCounts.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.only(
        top: 2,
        left: isMe ? 0 : 4,
        right: isMe ? 4 : 0,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: emojiCounts.entries.map((entry) {
          final count = entry.value;
          return Container(
            margin: const EdgeInsets.only(right: 4),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _accentColor.withOpacity(0.3), width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(entry.key, style: const TextStyle(fontSize: 13)),
                if (count > 1) ...[
                  const SizedBox(width: 3),
                  Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 11,
                      color: _textColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _dateSeparator(String date) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(child: Divider(color: _lightTextColor.withOpacity(0.3))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              date,
              style: TextStyle(
                  fontSize: 12,
                  color: _lightTextColor,
                  fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(child: Divider(color: _lightTextColor.withOpacity(0.3))),
        ],
      ),
    );
  }

  List<Widget> _buildMessagesFromCache() {
    final items = <Widget>[];

    String? lastDateLabel;
    for (final data in _cachedMessages) {
      final tsRaw = data['timestamp'];
      if (tsRaw != null) {
        DateTime? dt;
        if (tsRaw is String) dt = DateTime.tryParse(tsRaw)?.toLocal();
        else if (tsRaw is DateTime) dt = tsRaw.isUtc ? tsRaw.toLocal() : tsRaw;
        if (dt != null) {
          final label = _formatDateForGrouping(dt);
          if (label != lastDateLabel) {
            items.add(_dateSeparator(label));
            lastDateLabel = label;
          }
        }
      }

      // User-to-admin chat is always free — no masking applied here regardless
      // of the user's membership status.
      items.add(_buildMessageItem(data));
    }
    return items;
  }

  Widget _buildReportMessageCard(
      Map<String, dynamic> data, bool isMe, String formattedTime) {
    final reportReason = data['reportReason']?.toString() ?? '';
    final reportedUserName = data['reportedUserName']?.toString() ?? '';
    final reportedUserId = data['reportedUserId']?.toString() ?? '';
    final initials = reportedUserName.isNotEmpty
        ? reportedUserName.trim().split(' ').map((w) => w.isEmpty ? '' : w[0].toUpperCase()).take(2).join()
        : '?';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.78),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFDE7),
            border: Border.all(color: const Color(0xFFF9A825), width: 1.2),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft:
                  isMe ? const Radius.circular(16) : const Radius.circular(4),
              bottomRight:
                  isMe ? const Radius.circular(4) : const Radius.circular(16),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.amber.withOpacity(0.20),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header banner
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFF9A825), Color(0xFFF57F17)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(14),
                    topRight: Radius.circular(14),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.flag_rounded, color: Colors.white, size: 16),
                    SizedBox(width: 6),
                    Text(
                      'PROFILE REPORTED',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
              // Reported user section
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: const Color(0xFFF9A825),
                      child: Text(
                        initials,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (reportedUserName.isNotEmpty)
                            Text(
                              reportedUserName,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF4A3000),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          if (reportedUserId.isNotEmpty)
                            Text(
                              'User ID: $reportedUserId',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade600,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Divider
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Divider(
                  color: const Color(0xFFF9A825).withOpacity(0.4),
                  height: 1,
                ),
              ),
              // Reason section
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'REPORT REASON',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFF57F17),
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      reportReason.isNotEmpty ? reportReason : 'No reason provided',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF4A3000),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(right: 12, bottom: 8),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    formattedTime,
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey.shade600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInlineCallBubble(Map<String, dynamic> data, DateTime? tsDate) {
    // Call fields are stored as a JSON payload inside data['message'].
    // Fall back to top-level keys for backwards compat with cached data.
    Map<String, dynamic> callPayload = {};
    final rawCallMsg = data['message']?.toString() ?? '';
    if (rawCallMsg.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawCallMsg);
        if (decoded is Map) callPayload = Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }

    final callType = callPayload['callType']?.toString() ?? data['callType']?.toString() ?? 'audio';
    final callStatus = callPayload['callStatus']?.toString() ?? data['callStatus']?.toString() ?? 'missed';
    final callerId = callPayload['callerId']?.toString() ?? data['callerId']?.toString() ?? data['senderId']?.toString() ?? '';
    final duration = (callPayload['duration'] as num?)?.toInt() ?? (data['duration'] as num?)?.toInt() ?? 0;
    final timeStr = tsDate != null ? DateFormat('HH:mm').format(tsDate) : '';

    final isVideo = callType == 'video';
    // Use _mySenderId so both admin-view and user-view get the correct perspective
    final isOutgoing = callerId == _mySenderId;
    final callLabel = isVideo ? 'Video' : 'Voice';

    Color iconColor;
    IconData directionIcon;
    String label;
    String subtitle = '';
    Color bubbleColor;
    Color borderColor;

    switch (callStatus) {
      case 'completed':
        iconColor = const Color(0xFF25D366);
        directionIcon = isOutgoing
            ? (isVideo ? Icons.videocam : Icons.call_made)
            : (isVideo ? Icons.videocam : Icons.call_received);
        label = isOutgoing ? 'Outgoing $callLabel Call' : 'Incoming $callLabel Call';
        if (duration > 0) {
          final m = duration ~/ 60;
          final s = duration % 60;
          subtitle = m > 0 ? '${m}m ${s}s' : '${s}s';
        }
        bubbleColor = Colors.white;
        borderColor = Colors.grey.withOpacity(0.25);
        break;

      case 'missed':
        if (isOutgoing) {
          iconColor = Colors.amber[700]!;
          directionIcon = isVideo ? Icons.videocam_off : Icons.call_missed_outgoing;
          label = 'No Answer';
          subtitle = isVideo ? 'They didn\'t pick up the video call' : 'They didn\'t pick up';
          bubbleColor = Colors.amber.withOpacity(0.06);
          borderColor = Colors.amber.withOpacity(0.35);
        } else {
          iconColor = Colors.red;
          directionIcon = isVideo ? Icons.videocam_off : Icons.call_missed;
          label = 'Missed $callLabel Call';
          bubbleColor = Colors.red.withOpacity(0.06);
          borderColor = Colors.red.withOpacity(0.3);
        }
        break;

      case 'declined':
        if (isOutgoing) {
          iconColor = Colors.red[600]!;
          directionIcon = isVideo ? Icons.videocam_off : Icons.call_end;
          label = '$callLabel Call Declined';
          subtitle = 'Declined by recipient';
          bubbleColor = Colors.red.withOpacity(0.06);
          borderColor = Colors.red.withOpacity(0.3);
        } else {
          iconColor = Colors.indigo[400]!;
          directionIcon = isVideo ? Icons.videocam_off : Icons.call_end;
          label = 'You Declined';
          subtitle = isVideo ? 'You declined the video call' : 'You declined the call';
          bubbleColor = Colors.indigo.withOpacity(0.05);
          borderColor = Colors.indigo.withOpacity(0.22);
        }
        break;

      case 'cancelled':
        if (isOutgoing) {
          iconColor = Colors.grey[600]!;
          directionIcon = isVideo ? Icons.videocam_off : Icons.call_end;
          label = 'Call Cancelled';
          subtitle = 'You cancelled before connecting';
          bubbleColor = Colors.grey.withOpacity(0.06);
          borderColor = Colors.grey.withOpacity(0.25);
        } else {
          iconColor = Colors.orange[700]!;
          directionIcon = isVideo ? Icons.videocam_off : Icons.call_missed;
          label = 'Missed $callLabel Call';
          subtitle = 'Caller cancelled';
          bubbleColor = Colors.orange.withOpacity(0.06);
          borderColor = Colors.orange.withOpacity(0.3);
        }
        break;

      case 'busy':
        iconColor = Colors.orange[700]!;
        directionIcon = isVideo ? Icons.videocam_off : Icons.phone_locked;
        label = isOutgoing ? 'User Was Busy' : 'You Were Busy';
        subtitle = isOutgoing
            ? 'Recipient was on another call'
            : 'You were on another call';
        bubbleColor = Colors.orange.withOpacity(0.06);
        borderColor = Colors.orange.withOpacity(0.3);
        break;

      default:
        iconColor = Colors.grey[500]!;
        directionIcon = isVideo ? Icons.videocam_off : Icons.phone_missed;
        label = '$callLabel Call';
        bubbleColor = Colors.grey.withOpacity(0.05);
        borderColor = Colors.grey.withOpacity(0.2);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 280),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: borderColor, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(directionIcon, color: iconColor, size: 16),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: iconColor,
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                timeStr,
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Parse profile card data from a Socket.IO message.
  /// Socket.IO stores the profile JSON in the `message` field as a string.
  /// Legacy Firestore format stored it in `profileData` as a map.
  Map<String, dynamic>? _parseProfileCardData(Map<String, dynamic> data) {
    // Socket.IO format: message is JSON string
    if (data.containsKey('message') && data['message'] is String) {
      try {
        final decoded = jsonDecode(data['message'] as String);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    // Legacy Firestore format
    if (data['profileData'] is Map) {
      return Map<String, dynamic>.from(data['profileData'] as Map);
    }
    return null;
  }

  Widget _buildCallHistorySection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.07),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () {
              if (!_callHistoryLoaded) {
                _loadCallHistory();
              }
              setState(() => _showCallHistory = !_showCallHistory);
            },
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.history, color: _primaryGradient.colors[0], size: 20),
                  const SizedBox(width: 10),
                  Text('Call History (${_callHistory.length})',
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: _textColor,
                          fontSize: 14)),
                  const Spacer(),
                  Icon(
                    _showCallHistory
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: _lightTextColor,
                  ),
                ],
              ),
            ),
          ),
          if (_showCallHistory)
            _callHistoryLoaded
                ? (_callHistory.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text('No call history',
                            style: TextStyle(
                                color: _lightTextColor, fontSize: 13)),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _callHistory.length,
                        separatorBuilder: (_, __) =>
                            Divider(height: 1, color: Colors.grey.shade100),
                        itemBuilder: (context, i) =>
                            _buildCallHistoryItem(_callHistory[i]),
                      ))
                : const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
        ],
      ),
    );
  }

  Widget _buildCallHistoryItem(CallHistory call) {
    final isVideo = call.callType == CallType.video;
    // Use _mySenderId for correct perspective (admin vs user view)
    final outgoing = call.callerId == _mySenderId;
    final callLabel = isVideo ? 'video' : 'voice';

    Color iconColor;
    IconData directionIcon;
    String statusLabel;

    switch (call.status) {
      case CallStatus.completed:
        iconColor = outgoing ? Colors.blue : Colors.green;
        directionIcon = outgoing
            ? (isVideo ? Icons.videocam : Icons.call_made)
            : (isVideo ? Icons.videocam : Icons.call_received);
        statusLabel = outgoing
            ? 'Outgoing $callLabel call'
            : 'Incoming $callLabel call';
        break;
      case CallStatus.missed:
        if (outgoing) {
          iconColor = Colors.amber[700]!;
          directionIcon = isVideo ? Icons.videocam_off : Icons.call_missed_outgoing;
          statusLabel = 'No Answer';
        } else {
          iconColor = Colors.red;
          directionIcon = isVideo ? Icons.videocam_off : Icons.call_missed;
          statusLabel = 'Missed $callLabel call';
        }
        break;
      case CallStatus.declined:
        if (outgoing) {
          iconColor = Colors.red[600]!;
          directionIcon = isVideo ? Icons.videocam_off : Icons.call_end;
          statusLabel = '$callLabel call declined';
        } else {
          iconColor = Colors.indigo[400]!;
          directionIcon = isVideo ? Icons.videocam_off : Icons.call_end;
          statusLabel = 'You declined';
        }
        break;
      case CallStatus.cancelled:
        if (outgoing) {
          iconColor = Colors.grey[600]!;
          directionIcon = isVideo ? Icons.videocam_off : Icons.call_end;
          statusLabel = 'Call cancelled';
        } else {
          iconColor = Colors.orange[700]!;
          directionIcon = isVideo ? Icons.videocam_off : Icons.call_missed;
          statusLabel = 'Missed $callLabel call';
        }
        break;
    }

    String durationStr = '';
    if (call.status == CallStatus.completed && call.duration > 0) {
      final m = call.duration ~/ 60;
      final s = call.duration % 60;
      durationStr = '${m}m ${s}s';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(directionIcon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  statusLabel,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: _textColor),
                ),
                if (durationStr.isNotEmpty)
                  Text(durationStr,
                      style: TextStyle(fontSize: 11, color: _lightTextColor)),
              ],
            ),
          ),
          Text(
            _formatCallDateTime(call.startTime),
            style: TextStyle(fontSize: 11, color: _lightTextColor),
          ),
        ],
      ),
    );
  }

// Reply preview uses cache (no async fetch)
  Widget _buildReplyPreview(String replyToID, bool isMe,
      {Map<String, dynamic>? inlinePayload}) {
    // Look up from cache by messageId for full message data.
    Map<String, dynamic>? replyData;
    try {
      replyData = _cachedMessages.firstWhere(
        (m) => m['messageId'] == replyToID || m['id'] == replyToID,
      );
    } catch (_) {}

    // Fall back to the repliedTo map passed directly (from the parent message).
    if (replyData == null && inlinePayload == null) {
      // Minimal placeholder – no network call
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isMe
              ? Colors.white.withOpacity(0.9)
              : _primaryGradient.colors[0].withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.reply, size: 14,
                color: isMe ? _primaryGradient.colors[0] : _primaryGradient.colors[0]),
            const SizedBox(width: 6),
            Text('Replied message',
                style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: isMe ? Colors.black87 : _lightTextColor)),
          ],
        ),
      );
    }

    // Prefer the full cached message for type detection; fall back to inline.
    final Map<String, dynamic> source = replyData ?? inlinePayload!;

    final String msgType =
        source['messageType']?.toString() ?? source['type']?.toString() ?? 'text';

    final String senderName;
    if (replyData != null) {
      final String senderIdR =
          replyData['senderId']?.toString() ?? replyData['senderid']?.toString() ?? '';
      final bool isReplyFromMe = senderIdR == _mySenderId;
      final bool isReplyFromAdmin = senderIdR == _adminUserId;
      senderName = isReplyFromAdmin
          ? 'Admin'
          : (isReplyFromMe ? 'You' : widget.userName);
    } else {
      senderName = inlinePayload!['senderName']?.toString() ?? 'User';
    }

    // Preview text — human-readable label (never a raw URL)
    final String previewText = replyData != null
        ? _messagePreviewText(replyData)
        : (inlinePayload!['message']?.toString() ?? '📷 Photo');

    // Image URL for the thumbnail, present only for image-type replies.
    // Cached message stores the URL under 'message'; inline payload stores it
    // under 'imageUrl' (set by _buildReplyPayload).
    String? imageUrl;
    if (msgType == 'image') {
      imageUrl = replyData != null
          ? (replyData['message']?.toString() ?? replyData['imageUrl']?.toString())
          : inlinePayload!['imageUrl']?.toString();
    }
    final bool hasImage = imageUrl != null && imageUrl.isNotEmpty;

    return Container(
      constraints: BoxConstraints(
        minWidth: 100,
        maxWidth: MediaQuery.of(context).size.width * 0.6,
      ),
      decoration: BoxDecoration(
        color: isMe
            ? Colors.white.withOpacity(0.9)
            : _primaryGradient.colors[0].withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isMe
              ? Colors.white.withOpacity(0.95)
              : _primaryGradient.colors[0].withOpacity(0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Left accent bar (WhatsApp-style)
          Container(
            width: 3,
            height: hasImage ? 64 : 46,
            decoration: BoxDecoration(
              color: isMe
                  ? _primaryGradient.colors[0]
                  : _primaryGradient.colors[0],
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                bottomLeft: Radius.circular(12),
              ),
            ),
          ),
          Flexible(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(senderName,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isMe
                            ? _primaryGradient.colors[0]
                            : _primaryGradient.colors[0],
                      )),
                  const SizedBox(height: 3),
                  Text(previewText,
                      style: TextStyle(
                        fontSize: 12,
                        color: isMe
                            ? Colors.black87
                            : _lightTextColor,
                        fontStyle: FontStyle.italic,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ),
          // Image thumbnail (WhatsApp-style) for image replies
          if (hasImage) ...[
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
              child: CachedNetworkImage(
                imageUrl: imageUrl!,
                width: 56,
                height: 64,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Container(
                  width: 56,
                  height: 64,
                  color: Colors.grey.shade300,
                  child: Icon(Icons.image, color: Colors.grey.shade500),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVoiceMessage(String content, bool isMe) {
    // Support both plain URL (new) and JSON-encoded format (legacy)
    String voiceUrl = content;
    try {
      final decoded = jsonDecode(content) as Map<String, dynamic>;
      voiceUrl = decoded['url']?.toString() ?? content;
    } catch (_) {
      // plain URL - use as-is
    }

    final isCurrentlyPlaying = _playingMessageId == voiceUrl && _isPlaying;
    final isCurrentMessage = _playingMessageId == voiceUrl;
    final progressValue = isCurrentMessage && _playbackDuration.inSeconds > 0
        ? (_playbackPosition.inMilliseconds / _playbackDuration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    final displaySecs = isCurrentMessage && _playbackDuration.inSeconds > 0
        ? _playbackPosition.inSeconds
        : 0;
    final displayTime = '${(displaySecs ~/ 60).toString().padLeft(2, '0')}:${(displaySecs % 60).toString().padLeft(2, '0')}';

    return GestureDetector(
      onTap: () => _toggleVoicePlayback(voiceUrl),
      child: Container(
        width: 200,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isMe ? Colors.white.withOpacity(0.25) : _primaryGradient.colors[0].withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isCurrentlyPlaying ? Icons.pause : Icons.play_arrow,
                color: isMe ? Colors.white : _primaryGradient.colors[0],
                size: 22,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progressValue,
                      minHeight: 3,
                      backgroundColor: (isMe ? Colors.white : _primaryGradient.colors[0]).withOpacity(0.25),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isMe ? Colors.white : _primaryGradient.colors[0],
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    displayTime,
                    style: TextStyle(
                      color: isMe ? Colors.white70 : _lightTextColor,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDocumentMessage(String content, bool isMe) {
    try {
      Map<String, dynamic> docData = jsonDecode(content);
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          gradient: isMe ? _primaryGradient : _secondaryGradient,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.insert_drive_file,
                color: isMe ? Colors.white : _primaryGradient.colors[0],
                size: 28),
            const SizedBox(width: 12),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Document',
                    style: TextStyle(
                      color: isMe ? Colors.white : _textColor,
                      fontWeight: FontWeight.w500,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    docData['name'] ?? 'Unknown file',
                    style: TextStyle(
                      color: isMe ? Colors.white70 : _lightTextColor,
                      fontSize: 13,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    } catch (e) {
      return Text('Document',
          style: TextStyle(
            color: isMe ? Colors.white : _textColor,
          ));
    }
  }

  /// Extracts the first URL from a JSON-encoded gallery list.
  /// Returns an empty string if parsing fails.
  String _firstGalleryUrl(String json) {
    try {
      final decoded = jsonDecode(json);
      if (decoded is List && decoded.isNotEmpty) {
        return decoded.first?.toString() ?? '';
      }
    } catch (_) {}
    return '';
  }

  /// Parses a JSON-encoded gallery message into a list of URL strings.
  List<String> _parseGalleryUrls(String message) {
    try {
      final decoded = jsonDecode(message);
      if (decoded is List) return decoded.whereType<String>().toList();
    } catch (_) {}
    return [message];
  }

  /// Renders a single chat image (outside the gradient bubble).
  /// Tapping opens the fullscreen swipeable viewer.
  Widget _buildChatImageMessage(String? imageUrl, bool isMe) {
    if (imageUrl == null || imageUrl.isEmpty) {
      return const SizedBox.shrink();
    }
    final double imgW = MediaQuery.of(context).size.width * 0.60;
    return GestureDetector(
      onTap: () => _openPhotoViewer(context, [imageUrl], 0),
      child: ClipRRect(
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: isMe ? const Radius.circular(16) : const Radius.circular(4),
          bottomRight: isMe ? const Radius.circular(4) : const Radius.circular(16),
        ),
        child: CachedNetworkImage(
          imageUrl: imageUrl,
          width: imgW,
          height: imgW * 0.75,
          fit: BoxFit.cover,
          placeholder: (context, url) => Container(
            width: imgW,
            height: imgW * 0.75,
            color: Colors.grey.shade200,
            child: Center(
              child: CircularProgressIndicator(
                color: _primaryGradient.colors[0],
                strokeWidth: 2,
              ),
            ),
          ),
          errorWidget: (context, url, error) => Container(
            width: imgW,
            height: imgW * 0.75,
            color: Colors.grey.shade200,
            child: Icon(Icons.broken_image, color: Colors.grey.shade400, size: 40),
          ),
        ),
      ),
    );
  }

  /// Renders a WhatsApp-style gallery grid for `image_gallery` messages
  /// (outside the gradient bubble). Tapping any cell opens the fullscreen viewer.
  Widget _buildChatGalleryGrid(List<String> urls) {
    if (urls.isEmpty) return const SizedBox.shrink();
    final double gridW = MediaQuery.of(context).size.width * 0.60;
    const double gap = 2;

    Widget thumb(int index, {bool showOverlay = false, int extra = 0}) {
      final url = urls[index];
      Widget img = CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        placeholder: (ctx, url) => Container(
          color: Colors.grey.shade200,
          child: Center(
            child: CircularProgressIndicator(
              color: _primaryGradient.colors[0],
              strokeWidth: 2,
            ),
          ),
        ),
        errorWidget: (_, __, ___) => Container(
          color: Colors.grey.shade200,
          child: Icon(Icons.broken_image, color: Colors.grey.shade400),
        ),
      );
      return GestureDetector(
        onTap: () => _openPhotoViewer(context, urls, index),
        child: showOverlay
            ? Stack(
                fit: StackFit.expand,
                children: [
                  img,
                  Container(color: Colors.black54),
                  Center(
                    child: Text(
                      '+$extra',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              )
            : img,
      );
    }

    if (urls.length == 1) {
      return SizedBox(
        width: gridW,
        height: gridW * 0.75,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: thumb(0),
        ),
      );
    }
    if (urls.length == 2) {
      final h = gridW / 2 - gap / 2;
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: gridW,
          child: Row(children: [
            Expanded(child: SizedBox(height: h, child: thumb(0))),
            SizedBox(width: gap),
            Expanded(child: SizedBox(height: h, child: thumb(1))),
          ]),
        ),
      );
    }
    if (urls.length == 3) {
      final h = gridW * 0.6;
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: gridW,
          height: h,
          child: Row(children: [
            Expanded(flex: 2, child: SizedBox(height: h, child: thumb(0))),
            SizedBox(width: gap),
            Expanded(
              flex: 1,
              child: Column(children: [
                Expanded(child: thumb(1)),
                SizedBox(height: gap),
                Expanded(child: thumb(2)),
              ]),
            ),
          ]),
        ),
      );
    }
    if (urls.length == 4) {
      final cellW = (gridW - gap) / 2;
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: gridW,
          child: Column(children: [
            Row(children: [
              SizedBox(width: cellW, height: cellW, child: thumb(0)),
              SizedBox(width: gap),
              SizedBox(width: cellW, height: cellW, child: thumb(1)),
            ]),
            SizedBox(height: gap),
            Row(children: [
              SizedBox(width: cellW, height: cellW, child: thumb(2)),
              SizedBox(width: gap),
              SizedBox(width: cellW, height: cellW, child: thumb(3)),
            ]),
          ]),
        ),
      );
    }

    // 5+ images: 2-column grid, last visible cell shows "+N"
    const int maxVisible = 6;
    final int displayCount = urls.length > maxVisible ? maxVisible : urls.length;
    final int extraCount = urls.length > maxVisible ? urls.length - maxVisible + 1 : 0;
    final double cellW = (gridW - gap) / 2;
    final List<Widget> cells = List.generate(displayCount, (i) {
      final isLast = i == displayCount - 1 && extraCount > 0;
      return SizedBox(
        width: cellW,
        height: cellW,
        child: thumb(i, showOverlay: isLast, extra: extraCount),
      );
    });
    final List<Widget> rows = [];
    for (int i = 0; i < cells.length; i += 2) {
      if (i > 0) rows.add(SizedBox(height: gap));
      rows.add(Row(children: [
        cells[i],
        SizedBox(width: gap),
        if (i + 1 < cells.length) cells[i + 1] else SizedBox(width: cellW),
      ]));
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(width: gridW, child: Column(children: rows)),
    );
  }

  Widget _buildImageMessage(String? imageUrl, bool isMe) {
    if (imageUrl == null) {
      return Text('Image',
          style: TextStyle(
            color: isMe ? Colors.white : _textColor,
          ));
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 8,
              offset: const Offset(0, 3),
            )
          ],
        ),
        child: CachedNetworkImage(
          imageUrl: imageUrl,
          width: 220,
          height: 160,
          fit: BoxFit.cover,
          placeholder: (context, url) => Container(
            width: 220,
            height: 160,
            decoration: BoxDecoration(
              gradient: _secondaryGradient,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: CircularProgressIndicator(color: _accentColor),
            ),
          ),
          errorWidget: (context, url, error) => Container(
            width: 220,
            height: 160,
            decoration: BoxDecoration(
              gradient: _secondaryGradient,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(Icons.broken_image, color: _lightTextColor, size: 40),
          ),
        ),
      ),
    );
  }

// Updated Profile Card Message with Pro-Level Design
  Widget _buildProfileCardMessage(
      Map<String, dynamic>? profileData, bool isMe) {
    if (profileData == null) {
      return Text('Profile Card',
          style: TextStyle(
            color: isMe ? Colors.white : _textColor,
          ));
    }

    final bool shouldBlurPhotoFallback = profileData['shouldBlurPhoto'] ?? true;
    final String privacy = profileData['privacy']?.toString() ?? '';
    final String photoRequest = profileData['photo_request']?.toString() ?? '';
    // Determine visibility: use PrivacyUtils when either privacy or photo_request
    // field is present in the data; otherwise fall back to the legacy
    // shouldBlurPhoto flag that older messages or admin-shared profiles carry.
    final bool hasPrivacyData = profileData.containsKey('privacy') ||
        profileData.containsKey('photo_request');
    final bool shouldShowClear = hasPrivacyData
        ? PrivacyUtils.shouldShowClearImage(
            privacy: privacy, photoRequest: photoRequest)
        : !shouldBlurPhotoFallback;

    final String userId = (profileData['userId'] ?? profileData['id'] ?? '').toString();
    final String firstName = (profileData['firstName'] ?? profileData['first'] ?? '').toString();
    final String lastName = (profileData['lastName'] ?? profileData['last'] ?? '').toString();
    final String fullName = '$firstName $lastName'.trim();
    final String displayName =
        fullName.isNotEmpty ? fullName : (profileData['name']?.toString() ?? 'Unknown');
    final String? photoUrl = profileData['profileImage']?.toString();
    final bool hasPhoto = photoUrl != null && photoUrl.isNotEmpty;

    // Gallery images: list of URL strings
    final List<String> galleryImages = [];
    final rawGallery = profileData['galleryImages'];
    if (rawGallery is List) {
      for (final item in rawGallery) {
        final url = item?.toString() ?? '';
        if (url.isNotEmpty) galleryImages.add(url);
      }
    }
    // Build all viewable images (main photo first, then gallery)
    final List<String> allImages = [
      if (hasPhoto) photoUrl!,
      ...galleryImages.where((u) => u != photoUrl),
    ];

    return Container(
      width: 300,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _primaryGradient.colors[0].withOpacity(0.18),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Gradient header banner ──
            Container(
              height: 60,
              decoration: BoxDecoration(
                gradient: _primaryGradient,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.favorite, color: Colors.white.withOpacity(0.7), size: 16),
                  const SizedBox(width: 6),
                  Text(
                    'Profile Card',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.25),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'MS-$userId',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Profile photo + name (Centered layout) ──
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
              child: Column(
                children: [
                  Transform.translate(
                    offset: const Offset(0, -30),
                    child: Column(
                      children: [
                        // Profile photo - centered, tappable to open fullscreen viewer
                        // (shows privacy dialog instead if photo is private and viewer is a non-admin user)
                        GestureDetector(
                          onTap: allImages.isNotEmpty
                              ? () {
                                  if (!shouldShowClear && !widget.isAdmin) {
                                    _showPhotoPrivacyDialog(
                                        context, userId, photoRequest);
                                  } else {
                                    _openPhotoViewer(context, allImages, 0);
                                  }
                                }
                              : null,
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.15),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child: !shouldShowClear
                                  ? ImageFiltered(
                                      imageFilter: ImageFilter.blur(
                                        sigmaX: PrivacyUtils.kStandardBlurSigmaX,
                                        sigmaY: PrivacyUtils.kStandardBlurSigmaY,
                                      ),
                                      child: Container(
                                        width: 80,
                                        height: 80,
                                        color: Colors.grey.shade200,
                                        child: hasPhoto
                                            ? CachedNetworkImage(
                                                imageUrl: photoUrl!,
                                                fit: BoxFit.cover,
                                                errorWidget: (_, __, ___) =>
                                                    Icon(Icons.person, size: 40, color: Colors.grey.shade400),
                                              )
                                            : Icon(Icons.person, size: 40, color: Colors.grey.shade400),
                                      ),
                                    )
                                  : Container(
                                      width: 80,
                                      height: 80,
                                      color: Colors.grey.shade200,
                                      child: hasPhoto
                                          ? CachedNetworkImage(
                                              imageUrl: photoUrl!,
                                              fit: BoxFit.cover,
                                              errorWidget: (_, __, ___) =>
                                                  Icon(Icons.person, size: 40, color: Colors.grey.shade400),
                                            )
                                          : Icon(Icons.person, size: 40, color: Colors.grey.shade400),
                                    ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Name + meta - centered below
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Flexible(
                                  child: Text(
                                    displayName,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: _textColor,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                // Photo lock/unlock badge
                                Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: shouldShowClear ? Colors.green.shade100 : Colors.orange.shade100,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    shouldShowClear ? Icons.lock_open_outlined : Icons.lock_outline,
                                    size: 12,
                                    color: shouldShowClear ? Colors.green.shade700 : Colors.orange.shade700,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            if (profileData['age'] != null && profileData['age'] != 'N/A')
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.cake_outlined, size: 13, color: _lightTextColor),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${profileData['age']} years',
                                    style: TextStyle(fontSize: 13, color: _lightTextColor, fontWeight: FontWeight.w500),
                                  ),
                                ],
                              ),
                            if ((profileData['location'] ?? profileData['country']) != null &&
                                (profileData['location'] ?? profileData['country']).toString().isNotEmpty &&
                                (profileData['location'] ?? profileData['country']) != 'Location not specified')
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.location_on_outlined, size: 13, color: _lightTextColor),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        (profileData['location'] ?? profileData['country']).toString(),
                                        style: TextStyle(fontSize: 12, color: _lightTextColor),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // ── Info chips ──
                  Transform.translate(
                    offset: const Offset(0, -22),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (profileData['religion'] != null && profileData['religion'] != 'N/A')
                          _buildInfoChip(Icons.menu_book_outlined, profileData['religion']),
                        if (profileData['community'] != null && profileData['community'] != 'N/A')
                          _buildInfoChip(Icons.groups_outlined, profileData['community']),
                        if (profileData['occupation'] != null && profileData['occupation'] != 'N/A')
                          _buildInfoChip(Icons.work_outline, profileData['occupation']),
                        if (profileData['education'] != null && profileData['education'] != 'N/A')
                          _buildInfoChip(Icons.school_outlined, profileData['education']),
                        if (profileData['height'] != null && profileData['height'] != 'N/A')
                          _buildInfoChip(Icons.height, profileData['height']),
                      ],
                    ),
                  ),

                  // ── Bio ──
                  if (profileData['bio'] != null &&
                      profileData['bio'].toString().isNotEmpty &&
                      profileData['bio'] != 'No bio available')
                    Transform.translate(
                      offset: const Offset(0, -14),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: _primaryGradient.colors[0].withOpacity(0.06),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '"${profileData['bio']}"',
                          style: TextStyle(
                            fontSize: 11,
                            color: _lightTextColor,
                            fontStyle: FontStyle.italic,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),

                  // ── Gallery strip (only when there are extra photos) ──
                  if (allImages.length > 1)
                    Transform.translate(
                      offset: const Offset(0, -10),
                      child: _buildGalleryStrip(allImages, shouldShowClear,
                          onPrivateTap: !widget.isAdmin
                              ? () => _showPhotoPrivacyDialog(
                                  context, userId, photoRequest)
                              : null),
                    ),
                ],
              ),
            ),

            // ── Divider ──
            Divider(height: 1, color: Colors.grey.shade200),

            // ── Action buttons ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () {
                        if (userId.isNotEmpty) {
                          if (widget.isAdmin) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => AdminChatScreen(
                                  senderID: userId,
                                  userName: displayName,
                                  isAdmin: widget.isAdmin,
                                ),
                              ),
                            );
                          } else {
                            _handleProfileCardChat(context, userId, displayName);
                          }
                        }
                      },
                      icon: Icon(Icons.chat_bubble_outline,
                          size: 16, color: _primaryGradient.colors[0]),
                      label: Text(
                        'Chat',
                        style: TextStyle(
                          color: _primaryGradient.colors[0],
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                  Container(width: 1, height: 28, color: Colors.grey.shade200),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () {
                        if (userId.isNotEmpty) {
                          if (widget.isAdmin) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ProfileScreen(userId: userId),
                              ),
                            );
                          } else {
                            _handleProfileCardViewProfile(context, userId);
                          }
                        }
                      },
                      icon: Icon(Icons.person_outline,
                          size: 16, color: _primaryGradient.colors[0]),
                      label: Text(
                        'View Profile',
                        style: TextStyle(
                          color: _primaryGradient.colors[0],
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _primaryGradient.colors[0].withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _primaryGradient.colors[0].withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: _primaryGradient.colors[0]),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: _primaryGradient.colors[0],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  /// Horizontal thumbnail strip showing extra gallery images.
  /// Tapping any thumbnail opens the fullscreen viewer at that index.
  /// If [onPrivateTap] is provided and the photo is private, it is called instead.
  Widget _buildGalleryStrip(List<String> images, bool shouldShowClear,
      {VoidCallback? onPrivateTap}) {
    return SizedBox(
      height: 56,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: images.length,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemBuilder: (context, index) {
          return GestureDetector(
            onTap: () {
              if (!shouldShowClear && onPrivateTap != null) {
                onPrivateTap();
              } else {
                _openPhotoViewer(context, images, index);
              }
            },
            child: Container(
              width: 50,
              height: 50,
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _primaryGradient.colors[0].withOpacity(0.3),
                  width: 1.5,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: !shouldShowClear
                    ? ImageFiltered(
                        imageFilter: ImageFilter.blur(
                          sigmaX: PrivacyUtils.kStandardBlurSigmaX,
                          sigmaY: PrivacyUtils.kStandardBlurSigmaY,
                        ),
                        child: CachedNetworkImage(
                          imageUrl: images[index],
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Container(
                            color: Colors.grey.shade200,
                            child: Icon(Icons.image, size: 20, color: Colors.grey.shade400),
                          ),
                        ),
                      )
                    : CachedNetworkImage(
                        imageUrl: images[index],
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(
                          color: Colors.grey.shade200,
                          child: Icon(Icons.image, size: 20, color: Colors.grey.shade400),
                        ),
                      ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Shows a privacy dialog when the user taps on a private (blurred) photo
  /// in a profile card. Displays the current request status and allows sending
  /// a new photo request if one has not been sent yet.
  Future<void> _showPhotoPrivacyDialog(
      BuildContext context, String targetUserId, String currentRequest) async {
    String photoRequestStatus = currentRequest.toLowerCase().trim();
    bool isSending = false;

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final bool isPending = photoRequestStatus == 'pending';
          final bool isRejected = photoRequestStatus == 'rejected';
          final bool notSent =
              !isPending && !isRejected && photoRequestStatus != 'accepted';

          IconData statusIcon;
          Color statusColor;
          String nepaliTitle;
          String englishTitle;
          String nepaliMessage;
          String englishMessage;

          if (isPending) {
            statusIcon = Icons.hourglass_bottom;
            statusColor = Colors.orange;
            nepaliTitle = 'रिक्वेस्ट पठाइएको छ';
            englishTitle = 'Request Sent';
            nepaliMessage = 'तपाईंको फोटो हेर्ने रिक्वेस्ट पेन्डिङ छ।';
            englishMessage = 'Your photo request is pending approval.';
          } else if (isRejected) {
            statusIcon = Icons.cancel_outlined;
            statusColor = Colors.grey.shade600;
            nepaliTitle = 'रिक्वेस्ट अस्वीकार गरियो';
            englishTitle = 'Request Rejected';
            nepaliMessage =
                'यो युजरले तपाईंको फोटो रिक्वेस्ट अस्वीकार गरेको छ।';
            englishMessage = 'Your photo request was rejected by this user.';
          } else {
            statusIcon = Icons.lock_outline;
            statusColor = Colors.red.shade600;
            nepaliTitle = 'यो फोटो प्राइभेट छ';
            englishTitle = 'Photo is Private';
            nepaliMessage = 'यो फोटो हेर्नको लागि रिक्वेस्ट पठाउनुहोस्।';
            englishMessage = 'Send a request to view this photo.';
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            contentPadding:
                const EdgeInsets.fromLTRB(24, 20, 24, 0),
            actionsPadding:
                const EdgeInsets.fromLTRB(16, 0, 16, 12),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(statusIcon, color: statusColor, size: 36),
                ),
                const SizedBox(height: 14),
                Text(
                  nepaliTitle,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 2),
                Text(
                  englishTitle,
                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  nepaliMessage,
                  style:
                      TextStyle(fontSize: 13, color: Colors.grey.shade800),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 2),
                Text(
                  englishMessage,
                  style:
                      TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('बन्द गर्नुहोस् / Close'),
              ),
              if (notSent)
                ElevatedButton(
                  onPressed: isSending
                      ? null
                      : () async {
                          setDialogState(() {
                            isSending = true;
                          });
                          try {
                            final prefs =
                                await SharedPreferences.getInstance();
                            final userDataString =
                                prefs.getString('user_data');
                            if (userDataString == null) {
                              setDialogState(() {
                                isSending = false;
                              });
                              return;
                            }
                            final userData = jsonDecode(userDataString);
                            final senderId =
                                userData['id']?.toString() ?? '';
                            if (senderId.isEmpty ||
                                targetUserId.isEmpty) {
                              setDialogState(() {
                                isSending = false;
                              });
                              return;
                            }
                            final response = await http.post(
                              Uri.parse(
                                  '${kApiBaseUrl}/Api2/send_request.php'),
                              headers: {
                                'Content-Type': 'application/json'
                              },
                              body: jsonEncode({
                                'sender_id': senderId,
                                'receiver_id': targetUserId,
                                'request_type': 'Photo',
                              }),
                            );
                            if (response.statusCode == 200) {
                              final data = jsonDecode(response.body);
                              if (data['success'] == true) {
                                setDialogState(() {
                                  photoRequestStatus = 'pending';
                                  isSending = false;
                                });
                                return;
                              }
                            }
                            setDialogState(() {
                              isSending = false;
                            });
                          } catch (e) {
                            debugPrint('Error sending photo request: $e');
                            setDialogState(() {
                              isSending = false;
                            });
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryGradient.colors[0],
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  child: isSending
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : const Text('Photo Request पठाउनुहोस्'),
                ),
            ],
          );
        },
      ),
    );
  }

  /// Opens a fullscreen photo viewer with swipeable [PageView].
  /// [images] is the ordered list of image URLs; [initialIndex] is the
  /// starting page.
  void _openPhotoViewer(
      BuildContext context, List<String> images, int initialIndex) {
    final PageController pageCtrl = PageController(initialPage: initialIndex);
    final ValueNotifier<int> currentIndex = ValueNotifier<int>(initialIndex);
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'close',
      barrierColor: Colors.black87,
      transitionDuration: const Duration(milliseconds: 200),
      transitionBuilder: (ctx, anim, _, child) => FadeTransition(
        opacity: anim,
        child: child,
      ),
      pageBuilder: (ctx, _, __) {
        return GestureDetector(
          onTap: () => Navigator.of(ctx).pop(),
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: Stack(
              children: [
                PageView.builder(
                  controller: pageCtrl,
                  itemCount: images.length,
                  onPageChanged: (i) => currentIndex.value = i,
                  itemBuilder: (ctx, i) {
                    return GestureDetector(
                      // Prevent closing when tapping the image itself
                      onTap: () {},
                      child: Center(
                        child: InteractiveViewer(
                          child: CachedNetworkImage(
                            imageUrl: images[i],
                            fit: BoxFit.contain,
                            placeholder: (_, __) => const Center(
                              child: CircularProgressIndicator(color: Colors.white),
                            ),
                            errorWidget: (_, __, ___) => const Icon(
                                Icons.broken_image,
                                color: Colors.white54,
                                size: 64),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                // Close button
                Positioned(
                  top: MediaQuery.of(ctx).padding.top + 8,
                  right: 12,
                  child: GestureDetector(
                    onTap: () => Navigator.of(ctx).pop(),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close,
                          color: Colors.white, size: 22),
                    ),
                  ),
                ),
                // Page indicator (reactive via ValueListenableBuilder)
                if (images.length > 1)
                  Positioned(
                    bottom: MediaQuery.of(ctx).padding.bottom + 16,
                    left: 0,
                    right: 0,
                    child: ValueListenableBuilder<int>(
                      valueListenable: currentIndex,
                      builder: (ctx, idx, _) => Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          images.length,
                          (i) => AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: i == idx ? 18 : 7,
                            height: 7,
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            decoration: BoxDecoration(
                              color: i == idx
                                  ? Colors.white
                                  : Colors.white38,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
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

  void _showOfficeHoursDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.schedule, color: _primaryGradient.colors[0]),
            const SizedBox(width: 8),
            const Text('Office Hours'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _officeHoursDialogRow(Icons.calendar_today, 'Sunday – Friday'),
            const SizedBox(height: 6),
            _officeHoursDialogRow(Icons.access_time, '10:00 AM – 5:00 PM'),
            const Divider(height: 20),
            _officeHoursDialogRow(Icons.block, 'Saturday: Closed',
                color: Colors.red.shade700),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget _officeHoursDialogRow(IconData icon, String text, {Color? color}) {
    final Color iconColor = color ?? _primaryGradient.colors[0];
    return Row(
      children: [
        Icon(icon, size: 16, color: iconColor),
        const SizedBox(width: 8),
        Text(text,
            style: TextStyle(
                fontSize: 14,
                color: color ?? _textColor)),
      ],
    );
  }

  /// Shows a bottom sheet listing all profiles shared by Admin to this user.
  void _showSharedProfilesSheet() {
    final uid = widget.senderID;
    if (uid.isEmpty) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.35,
        maxChildSize: 0.9,
        builder: (ctx, scrollCtrl) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    const Icon(Icons.share, color: Color(0xFFF90E18)),
                    const SizedBox(width: 8),
                    const Text(
                      'Shared Profiles',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(),
              Expanded(
                child: FutureBuilder<QuerySnapshot>(
                  future: FirebaseFirestore.instance
                      .collection('profile_shares')
                      .where('shared_by', isEqualTo: '1')
                      .where('shared_to', isEqualTo: uid)
                      .orderBy('timestamp', descending: true)
                      .get(),
                  builder: (ctx, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snap.hasError) {
                      return Center(
                        child: Text(
                          'Could not load shared profiles',
                          style: TextStyle(color: Colors.grey.shade500),
                        ),
                      );
                    }
                    final docs = snap.data?.docs ?? [];
                    if (docs.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.person_search,
                                size: 56, color: Colors.grey.shade300),
                            const SizedBox(height: 12),
                            Text(
                              'No profiles shared yet',
                              style: TextStyle(
                                  fontSize: 15, color: Colors.grey.shade500),
                            ),
                          ],
                        ),
                      );
                    }
                    return ListView.separated(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      itemCount: docs.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (ctx, i) {
                        final data =
                            docs[i].data() as Map<String, dynamic>;
                        final profileName =
                            data['profile_name']?.toString() ?? 'Unknown';
                        final memberId =
                            data['profile_member_id']?.toString() ?? '';
                        final ts = data['timestamp'];
                        String timeLabel = '';
                        if (ts is Timestamp) {
                          final dt = ts.toDate();
                          timeLabel = DateFormat('MMM d, yyyy').format(dt);
                        }
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          leading: CircleAvatar(
                            backgroundColor:
                                const Color(0xFFF90E18).withOpacity(0.12),
                            child: const Icon(Icons.person,
                                color: Color(0xFFF90E18)),
                          ),
                          title: Text(
                            profileName,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                          subtitle: memberId.isNotEmpty
                              ? Text(
                                  'MS-$memberId',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade500),
                                )
                              : null,
                          trailing: timeLabel.isNotEmpty
                              ? Text(
                                  timeLabel,
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade400),
                                )
                              : null,
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: _primaryGradient,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.white,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
          systemStatusBarContrastEnforced: false,
        ),
        title: Row(
          children: [
            GestureDetector(
              onTap: widget.isAdmin ? null : () => _showSharedProfilesSheet(),
              child: CircleAvatar(
                radius: 18,
                backgroundColor: Colors.white.withOpacity(0.25),
                child: const Icon(Icons.support_agent,
                    color: Colors.white, size: 20),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Admin Support',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          fontSize: 17)),
                  if (_adminOnline)
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(right: 5),
                          decoration: const BoxDecoration(
                            color: Color(0xFF22C55E),
                            shape: BoxShape.circle,
                          ),
                        ),
                        Text(
                          'Online',
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withOpacity(0.9)),
                        ),
                      ],
                    )
                  else if (_adminLastSeen != null)
                    Text(
                      formatLastSeen(_adminLastSeen!),
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.85)),
                    )
                  else if (!widget.isAdmin)
                    Text(
                      'Replies within 10 minutes',
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.9)),
                    )
                  else
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(right: 5),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade400,
                            shape: BoxShape.circle,
                          ),
                        ),
                        Text(
                          'Offline',
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withOpacity(0.9)),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.phone, color: Colors.white),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CallScreen(
                    currentUserId: widget.senderID,
                    currentUserName: _currentUserName.isNotEmpty ? _currentUserName : widget.senderID,
                    currentUserImage: _currentUserImage,
                    otherUserId: _adminUserId,
                    otherUserName: _adminUserName,
                    otherUserImage: '',
                    isOutgoingCall: true,
                    isAdminChat: true,
                    adminChatReceiverId: _adminUserId,
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.videocam, color: Colors.white),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => VideoCallScreen(
                    currentUserId: widget.senderID,
                    currentUserName: _currentUserName.isNotEmpty ? _currentUserName : widget.senderID,
                    currentUserImage: _currentUserImage,
                    otherUserId: _adminUserId,
                    otherUserName: _adminUserName,
                    otherUserImage: '',
                    isOutgoingCall: true,
                    isAdminChat: true,
                    adminChatReceiverId: _adminUserId,
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.info_outline, color: Colors.white),
            tooltip: 'Office Hours',
            onPressed: _showOfficeHoursDialog,
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [_backgroundColor, _backgroundColor.withOpacity(0.9)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Column(
                children: [
                  Expanded(
                    child: _buildMessageList(),
                  ),
                  if (_replyToMessage != null) _buildReplyBar(),
                  _buildInputBar(),
                ],
              ),
            ),
            if (_showMsgOverlay) _buildMsgActionOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageList() {
    if (_streamHasError) {
      return Center(
          child: Text('Error loading messages',
              style: TextStyle(color: _textColor)));
    }

    if (_streamLoading && _cachedMessages.isEmpty) {
      return Center(child: CircularProgressIndicator(color: _accentColor));
    }

    if (_cachedMessages.isEmpty && _showSuggestedMessages && !widget.isAdmin) {
      return Column(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(gradient: _primaryGradient),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.support_agent,
                        size: 72,
                        color: Colors.white.withOpacity(0.9)),
                    const SizedBox(height: 20),
                    Text('How can we help you?',
                        style: const TextStyle(
                            fontSize: 20,
                            color: Colors.white,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40),
                      child: Text(
                          'Start a conversation or choose from common questions below',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 15,
                              color: Colors.white.withOpacity(0.8))),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _buildSuggestedMessages(),
        ],
      );
    }

    final messageWidgets = _buildMessagesFromCache();

    // Wrap in Opacity so the list is invisible while the scroll position is
    // being set to the bottom on first load (like WhatsApp). The ListView
    // remains in the tree so the scroll controller stays attached.
    return Opacity(
      opacity: _scrollLocked ? 0.0 : 1.0,
      child: Container(
        decoration: BoxDecoration(
          color: _backgroundColor,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        child: ListView(
          controller: _scrollController,
          // Use ClampingScrollPhysics to prevent bounce effect that causes shaking
          physics: const ClampingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          padding: const EdgeInsets.only(top: 16, bottom: 12),
          children: [
            if (_isLoadingMore)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: _accentColor),
                  ),
                ),
              ),
            ...messageWidgets,
            if (_isAdminTyping) _buildTypingIndicator(),
          ],
        ),
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(left: 12, bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          gradient: _secondaryGradient,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(20),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const TypingIndicatorWidget(
          dotColor: Color(0xFF6B7280),
          dotSize: 7.0,
        ),
      ),
    );
  }

  Widget _buildSuggestedMessages() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 10,
            offset: const Offset(0, -3),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Suggested questions',
              style: TextStyle(
                  fontSize: 15,
                  color: _textColor,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _suggestedMessages.map((message) {
              return InkWell(
                onTap: () => _sendSuggestedMessage(message),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: _secondaryGradient,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(message,
                      style: TextStyle(
                          fontSize: 13,
                          color: _primaryGradient.colors[0],
                          fontWeight: FontWeight.w500)),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildReplyBar() {
    final String msgType =
        _replyToMessage!['messageType'] ?? _replyToMessage!['type'] ?? 'text';
    final String previewText = _messagePreviewText(_replyToMessage!);
    final String? imageUrl = msgType == 'image'
        ? (_replyToMessage!['message']?.toString() ??
            _replyToMessage!['imageUrl']?.toString())
        : null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: _secondaryGradient,
        border: Border(bottom: BorderSide(color: Colors.grey.withOpacity(0.2))),
      ),
      child: Row(
        children: [
          Icon(Icons.reply, color: _primaryGradient.colors[0], size: 22),
          const SizedBox(width: 10),
          // Thumbnail for image replies
          if (imageUrl != null && imageUrl.isNotEmpty) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                width: 40,
                height: 40,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) =>
                    Icon(Icons.image, size: 40, color: _lightTextColor),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Replying to',
                    style: TextStyle(
                        fontSize: 13,
                        color: _lightTextColor,
                        fontWeight: FontWeight.w500)),
                Text(
                  previewText,
                  style: TextStyle(
                      fontSize: 15,
                      color: _textColor,
                      fontWeight: FontWeight.w400),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, size: 22, color: _lightTextColor),
            onPressed: () => setState(() {
              _replyToID = null;
              _replyToMessage = null;
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    const kAccent = Color(0xFF9C27B0);
    if (_isRecording && _recordingAnimController != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF3E8FF),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 10,
              offset: const Offset(0, -3),
            )
          ],
        ),
        child: Row(
          children: [
            IconButton(
              onPressed: _cancelRecording,
              icon: const Icon(Icons.delete_outline, color: Colors.red, size: 26),
              tooltip: 'Cancel',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                height: 50,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: kAccent.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: kAccent.withOpacity(0.3), width: 1),
                ),
                child: Row(
                  children: [
                    // Pulsing red dot – opacity oscillates between 0.4 and 1.0
                    AnimatedBuilder(
                      animation: _recordingAnimController!,
                      builder: (context, _) {
                        // maps sin output [-1,1] → opacity [0.4, 1.0]
                        final pulse = 0.4 + 0.6 * (0.5 + 0.5 * sin(2 * pi * _recordingAnimController!.value));
                        return Opacity(
                          opacity: pulse,
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _formatRecordDuration(_recordDuration),
                      style: const TextStyle(
                        color: kAccent,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Animated waveform bars – each bar's height is a staggered sin wave
                    Expanded(
                      child: AnimatedBuilder(
                        animation: _recordingAnimController!,
                        builder: (context, _) {
                          const barCount = 22;
                          const maxH = 22.0;
                          const minH = 4.0;
                          final t = _recordingAnimController!.value;
                          return Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: List.generate(barCount, (i) {
                              // phase offset per bar creates a travelling-wave effect
                              final phase = (i / barCount) * 2 * pi;
                              // maps sin output [-1,1] → [minH, maxH]
                              final h = minH + (maxH - minH) * (0.5 + 0.5 * sin(2 * pi * t + phase));
                              return Container(
                                width: 3,
                                height: h,
                                decoration: BoxDecoration(
                                  color: kAccent.withOpacity(0.75),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              );
                            }),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            _isSendingVoice
                ? const SizedBox(
                    width: 48,
                    height: 48,
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: kAccent,
                      ),
                    ),
                  )
                : Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: _primaryGradient,
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.send, color: Colors.white, size: 22),
                      onPressed: _stopAndSendRecording,
                    ),
                  ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF3E8FF),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 10,
            offset: const Offset(0, -3),
          )
        ],
      ),
      child: Row(
        children: [
          if (!widget.isAdmin)
            PopupMenuButton(
              icon: Icon(Icons.add_circle_outlined,
                  color: _primaryGradient.colors[0]),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'document',
                  child: ListTile(
                    leading: Icon(Icons.insert_drive_file,
                        color: _primaryGradient.colors[0]),
                    title: Text('Document',
                        style: TextStyle(
                            color: _textColor, fontWeight: FontWeight.w500)),
                  ),
                ),
                PopupMenuItem(
                  value: 'image',
                  child: ListTile(
                    leading:
                        Icon(Icons.image, color: _primaryGradient.colors[0]),
                    title: Text('Image',
                        style: TextStyle(
                            color: _textColor, fontWeight: FontWeight.w500)),
                  ),
                ),
              ],
              onSelected: (value) {
                if (value == 'document') _sendDoc();
                if (value == 'image') _sendImage();
              },
            ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                gradient: _secondaryGradient,
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: TextField(
                controller: _controller,
                focusNode: _messageFocusNode,
                maxLines: null,
                minLines: 1,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                onChanged: (text) {
                  if (text.trim().isNotEmpty) {
                    _onUserTyping();
                  } else {
                    _onUserStopTyping();
                  }
                },
                decoration: InputDecoration(
                  hintText: 'Type a message...',
                  border: InputBorder.none,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  hintStyle: TextStyle(
                      color: _lightTextColor.withOpacity(0.7), fontSize: 15),
                ),
                style: TextStyle(color: _textColor, fontSize: 15),
              ),
            ),
          ),
          const SizedBox(width: 12),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _controller,
            builder: (context, value, child) {
              final hasText = value.text.trim().isNotEmpty;
              if (!hasText) {
                return GestureDetector(
                  onTap: _startRecording,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: _primaryGradient,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.mic, color: Colors.white, size: 22),
                  ),
                );
              }
              return Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: _primaryGradient,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: IconButton(
                  icon: const Icon(Icons.send, color: Colors.white, size: 22),
                  onPressed: _sendText,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// A bottom-sheet widget that previews selected images before sending.
/// Returns `true` when the user taps "Send", `false` / null otherwise.
class _ImagePreviewSheet extends StatelessWidget {
  final List<PlatformFile> files;
  final Color accentColor;

  const _ImagePreviewSheet({
    required this.files,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        top: 12,
        left: 16,
        right: 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(
            '${files.length} photo${files.length == 1 ? '' : 's'} selected',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          // Scrollable thumbnail row
          SizedBox(
            height: 180,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: files.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (ctx, index) {
                final file = files[index];
                Widget imgWidget;
                if (kIsWeb && file.bytes != null) {
                  imgWidget = Image.memory(
                    file.bytes!,
                    fit: BoxFit.cover,
                  );
                } else if (!kIsWeb && file.path != null) {
                  imgWidget = FutureBuilder<Uint8List>(
                    future: File(file.path!).readAsBytes(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return Container(
                          color: Colors.grey.shade200,
                          child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                        );
                      }
                      if (snapshot.hasData) {
                        return Image.memory(
                          snapshot.data!,
                          fit: BoxFit.cover,
                        );
                      }
                      return Container(
                        color: Colors.grey.shade200,
                        child: const Icon(Icons.broken_image, color: Colors.grey),
                      );
                    },
                  );
                } else {
                  imgWidget = Container(
                    color: Colors.grey.shade200,
                    child: const Icon(Icons.image, color: Colors.grey),
                  );
                }
                return ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(width: 140, height: 180, child: imgWidget),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentColor,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.send, size: 18, color: Colors.white),
                  label: Text(
                    'Send ${files.length} Photo${files.length == 1 ? '' : 's'}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
