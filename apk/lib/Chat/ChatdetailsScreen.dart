// lib/screens/ChatDetailScreen.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:ms2026/Chat/screen_state_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart'
    if (dart.library.html) 'package:ms2026/utils/web_permission_stub.dart';

// dart:io is only available on native platforms
import 'dart:io' if (dart.library.html) 'package:ms2026/utils/web_io_stub.dart';

import '../service/chat_message_cache.dart';
import '../service/socket_service.dart';
import '../service/chat_message_cache.dart';
import '../service/sound_settings_service.dart';
import '../utils/access_control.dart';
import '../Calling/videocall.dart';
import '../Calling/OutgoingCall.dart';
import '../Calling/call_history_model.dart';
import '../Calling/call_history_service.dart';
import '../Calling/callmanager.dart';
import '../Calling/incommingcall.dart';
import '../Calling/incomingvideocall.dart';
import '../otherenew/othernew.dart';
import '../otherenew/service.dart';
import '../pushnotification/pushservice.dart';
import 'call_overlay_manager.dart';
import '../constant/constant.dart';
import '../utils/time_utils.dart';
import '../utils/image_utils.dart';
import '../utils/privacy_utils.dart';
import 'widgets/typing_indicator.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../core/user_state.dart';

/// Immutable snapshot of audio playback state used by a single
/// [ValueNotifier] so the voice bubble can rebuild with one listener
/// instead of four nested [ValueListenableBuilder] widgets.
class _AudioPlaybackState {
  final String? playingId;
  final bool isPlaying;
  final Duration position;
  final Duration duration;

  const _AudioPlaybackState({
    this.playingId,
    this.isPlaying = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
  });

  _AudioPlaybackState copyWith({
    Object? playingId = _sentinel,
    bool? isPlaying,
    Duration? position,
    Duration? duration,
  }) {
    return _AudioPlaybackState(
      playingId: playingId == _sentinel ? this.playingId : playingId as String?,
      isPlaying: isPlaying ?? this.isPlaying,
      position: position ?? this.position,
      duration: duration ?? this.duration,
    );
  }

  static const Object _sentinel = Object();
}

/// Full chat screen – always operates in the "chat" view context.
///
/// This screen NEVER masks message text regardless of the user's premium or
/// verification status.  Masking is a list-preview-only concern handled by
/// [ChatListScreen].  Any gating on access (e.g. document verification) is
/// enforced by the calling screen before navigating here.
class ChatDetailScreen extends StatefulWidget {
  final String chatRoomId;
  final String receiverId;
  final String receiverName;
  final String receiverImage;
  final String? receiverPrivacy;
  final String? receiverPhotoRequest;
  final String currentUserId;
  final String currentUserName;
  final String currentUserImage;

  const ChatDetailScreen({
    super.key,
    required this.chatRoomId,
    required this.receiverId,
    required this.receiverName,
    required this.receiverImage,
    this.receiverPrivacy,
    this.receiverPhotoRequest,
    required this.currentUserId,
    required this.currentUserName,
    required this.currentUserImage,
  });

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final SocketService _socketService = SocketService();
  final Uuid _uuid = Uuid();

  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _messageFocusNode = FocusNode();

  String myImage = "";
  String otherUserImage = "";

  // Overlay
  bool showActionOverlay = false;
  bool showDeletePopup = false;
  Map<String, dynamic>? selectedMessage;
  bool selectedMine = false;
  Offset _selectedMessageOffset = Offset.zero;

  // Reply functionality
  Map<String, dynamic>? repliedMessage;
  bool isReplying = false;

  // Edit functionality
  Map<String, dynamic>? editingMessage;
  bool isEditing = false;
  final TextEditingController _editController = TextEditingController();

  // Send guard to prevent duplicate messages
  bool _isSending = false;

  // Audio playback
  final AudioPlayer _audioPlayer = AudioPlayer();
  // A single ValueNotifier holding all audio playback state allows the voice
  // bubble to use one ValueListenableBuilder instead of four nested ones,
  // and ensures position ticks never trigger a full message-list rebuild.
  final ValueNotifier<_AudioPlaybackState> _audioStateNotifier =
      ValueNotifier(const _AudioPlaybackState());

  // Voice recording
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  bool _isHoldRecording = false; // true when mic is being held (press-and-hold mode)
  bool _isSendingVoice = false;
  // ValueNotifiers so the recording bar updates without rebuilding all messages.
  final ValueNotifier<int> _recordDurationNotifier = ValueNotifier(0);
  Timer? _recordTimer;
  String? _recordingPath;
  AnimationController? _recordingAnimController;
  final ValueNotifier<double> _audioAmplitudeNotifier = ValueNotifier(-160.0); // dBFS
  StreamSubscription? _amplitudeSubscription;

  // Scroll lock during swipe-to-reply
  bool _isHorizontalDragging = false;

  // Scroll lock during message loading to prevent screen shaking
  bool _scrollLocked = true;
  bool _initialScrollDone = false;

  // Cached messages to prevent blinking
  List<Map<String, dynamic>> _cachedMessages = [];
  bool _isFirstLoad = true;

  // Track whether the compose field has text (avoids per-keystroke full rebuild)
  bool _hasText = false;

  // Message-widget cache: rebuilt only when messages/highlight/loading state changes
  List<Widget>? _cachedMessageWidgets;
  int _messagesCacheVersion = 0;
  int _lastBuiltVersion = -1;
  String? _lastBuiltHighlightId;
  bool _lastBuiltIsLoadingMore = false;
  bool _lastBuiltIsBlockedByReceiver = false;

  // Lazy loading variables
  bool _isLoadingMore = false;
  bool _hasMoreMessages = true;
  static const int _messagesPerPage = 20;
  // Pagination cursor – only updated on first load and during loadMore (never on stream updates)
  int _currentMessagePage = 1;

  // Call history variables
  List<CallHistory> _callHistory = [];
  bool _showCallHistory = false;
  StreamSubscription? _callHistorySubscription;

  // Backup incoming call listener (mirrors AdminChatScreen logic)
  StreamSubscription<Map<String, dynamic>>? _callListenerSubscription;

  // Messages stream subscription (replaces StreamBuilder to prevent rebuild-on-setState)
  StreamSubscription? _messagesSubscription;
  StreamSubscription? _messageEditedSubscription;
  StreamSubscription? _messageDeletedSubscription;
  StreamSubscription? _messageUnsentSubscription;
  StreamSubscription? _messageReactionSubscription;

  // Incoming-message debounce: buffer rapid socket events and flush them in a
  // single setState to avoid one rebuild per message when multiple arrive together.
  final List<Map<String, dynamic>> _pendingIncomingMessages = [];
  Timer? _incomingMessageDebounce;

  // Typing indicator
  Timer? _typingDebounce;
  Timer? _typingRepeatTimer; // Repeating click while remote user is typing
  bool _isTyping = false;
  bool _isReceiverTyping = false;
  StreamSubscription? _typingSubscription;
  StreamSubscription? _typingStopSubscription;
  bool _isMarkingMessagesAsRead = false;
  bool _isReceiverViewingThisChat = false;
  final AudioPlayer _typingAudioPlayer = AudioPlayer();
  final AudioPlayer _receiveAudioPlayer = AudioPlayer();

  // Receiver online status
  bool _isOtherUserOnline = false;
  DateTime? _otherUserLastSeen;
  StreamSubscription? _otherUserStatusSub;
  StreamSubscription? _audioPlayerStateSubscription;
  StreamSubscription? _audioPlayerPositionSubscription;
  StreamSubscription? _audioPlayerDurationSubscription;
  // Track whether the next scroll-to-bottom should be forced (own message sent)
  bool _forceScrollToBottom = false;

  // Scroll-to-reply + highlight
  final Map<String, GlobalKey> _messageKeys = {};
  String? _highlightedMessageId;

  // Delivered status (hover for web)
  String? _hoveredMessageId;

  // Block / photo-privacy state
  bool _isBlocked = false;       // I have blocked the other user
  bool _isBlockedByReceiver = false; // The other user has blocked me
  bool _isLoadingBlock = true;
  String _photoRequestStatus = 'not_sent';
  String _chatRequestStatus = 'unknown'; // 'unknown' | 'accepted' | 'pending' | 'rejected' | 'not_sent'
  String _privacyStatus = 'private';

  bool get _isEitherBlocked => _isBlocked || _isBlockedByReceiver;

  // Timing constants
  static const int _kTypingTimeoutSeconds = 5;
  static const Duration _kTypingDebounceDelay = Duration(seconds: 3);
  static const Duration _kHighlightDuration = Duration(milliseconds: 700);
  static const Duration _kActiveChatPresenceWindow = Duration(seconds: 30);
  static const Duration _kScrollToMessageDelay = Duration(milliseconds: 400);

  // Image display constants
  static const double _kImageWidthFraction = 0.65;
  static const double _kImageAspectRatio = 0.75; // 4:3
  static const double _kImageMinWidth = 120.0;
  static const double _kImageMaxHeight = 300.0;

  static const LinearGradient _primaryGradient = LinearGradient(
    colors: [Color(0xFFE91E3E), Color(0xFFC2185B)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  // Received bubbles use a clean white card instead of gradient
  static const Color _receivedBubbleColor = Color(0xFFFFFFFF);
  static const Color _receivedBubbleBorder = Color(0xFFEEEEEE);
  static const Color _accentColor = Color(0xFFE91E3E);
  static const Color _backgroundColor = Color(0xFFF0F2F5);
  static const Color _textColor = Color(0xFF1A1A2E);
  static const Color _lightTextColor = Color(0xFF757575);
  static const Color _inputFieldBackground = Color(0xFFF0F0F0);
  static const Color _sendButtonDisabled = Color(0xFFBDBDBD);
  // Keep _secondaryGradient for reply previews / edit previews only
  static const LinearGradient _secondaryGradient = LinearGradient(
    colors: [Color(0xFFFCE4EC), Color(0xFFFFF8F9)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  @override
  void initState() {
    super.initState();
    myImage = widget.currentUserImage;
    otherUserImage = widget.receiverImage;

    _recordingAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    // Load cached messages synchronously from the pre-warmed singleton so the
    // screen shows content immediately on the first frame — no skeleton flash.
    final syncCached = ChatMessageCache.instance.getMessages(widget.chatRoomId);
    if (syncCached.isNotEmpty) {
      _cachedMessages = syncCached;
      _isFirstLoad = false;
      // Position scroll to bottom after the first frame, then unlock.
      // Also mark _initialScrollDone so _performInitialScroll() (called when
      // server data arrives) skips the re-jump and only handles the unlock.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _initialScrollDone = true;
        if (mounted && _scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
        if (mounted) setState(() => _scrollLocked = false);
      });
    }

    // Defer heavy init work off the first frame so the screen opens instantly
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _markMessagesAsRead();
      _checkBlockStatus();
      _loadCallHistory();
      _fetchPhotoRequestStatus();
    });

    // Set chat as active when screen opens
    ScreenStateManager().onChatScreenOpened(
      widget.chatRoomId,
      widget.currentUserId,
      partnerUserId: widget.receiverId,
    );
    _updateActiveChatPresence(true);

    // Add observer for app lifecycle
    WidgetsBinding.instance.addObserver(this);

    // Audio player listeners — update the combined ValueNotifier directly to
    // avoid setState on every position tick, which would bypass the message-widget
    // cache and rebuild the entire message list hundreds of times per second.
    _audioPlayerStateSubscription = _audioPlayer.onPlayerStateChanged.listen((state) {
      final playing = state == PlayerState.playing;
      if (state == PlayerState.completed) {
        _audioStateNotifier.value = const _AudioPlaybackState();
      } else {
        _audioStateNotifier.value = _audioStateNotifier.value.copyWith(isPlaying: playing);
      }
    });
    _audioPlayerPositionSubscription = _audioPlayer.onPositionChanged.listen((pos) {
      _audioStateNotifier.value = _audioStateNotifier.value.copyWith(position: pos);
    });
    _audioPlayerDurationSubscription = _audioPlayer.onDurationChanged.listen((dur) {
      _audioStateNotifier.value = _audioStateNotifier.value.copyWith(duration: dur);
    });

    // Update _hasText without a full rebuild on every keystroke
    _messageController.addListener(_onMessageTextChanged);

    // Add scroll listener for lazy loading
    _scrollController.addListener(_onScroll);

    // Start listening to messages (dedicated subscription to avoid merge running on every setState)
    _listenToMessages();

    // Start listening to receiver's typing status
    _listenToTypingStatus();

    // Start listening to receiver's online status
    _startReceiverStatusListener();

    // Backup incoming call listener so calls ring while typing on this screen.
    // The global CallOverlayWrapper is the primary handler; this ensures the
    // call UI still appears if the global handler's frame callback is delayed
    // (e.g. keyboard open with no pending frames).
    _setupCallListener();
  }

  void _onMessageTextChanged() {
    final hasText = _messageController.text.trim().isNotEmpty;
    if (hasText != _hasText && mounted) {
      setState(() => _hasText = hasText);
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels <=
            _scrollController.position.minScrollExtent + 200 &&
        !_isLoadingMore &&
        _hasMoreMessages) {
      _loadMoreMessages();
    }
  }

  // ── Local message cache helpers ───────────────────────────────────────────

  /// Saves the most recent messages via the singleton cache.
  void _saveMessagesToLocalCache() {
    ChatMessageCache.instance.saveMessages(widget.chatRoomId, _cachedMessages);
  }

  // ─────────────────────────────────────────────────────────────────────────

  void _listenToMessages() {
    _socketService.joinRoom(widget.chatRoomId);

    // Load initial page via Socket.IO request-response
    _socketService.getMessages(widget.chatRoomId, page: 1, limit: _messagesPerPage).then((result) {
      if (!mounted) return;
      final messages = List<Map<String, dynamic>>.from(
        (result['messages'] as List? ?? []).map((m) => Map<String, dynamic>.from(m as Map)),
      );
      setState(() {
        _isFirstLoad = false;
        _cachedMessages = messages;
        _hasMoreMessages = result['hasMore'] == true;
        _currentMessagePage = 1;
        _messagesCacheVersion++;
      });
      // If the sync-cache path already unlocked scroll, just jump to bottom to
      // account for any layout change from fresh server data.  Otherwise use the
      // full _performInitialScroll path which also unlocks.
      if (_initialScrollDone) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _scrollController.hasClients) {
            _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
          }
          if (mounted && _scrollLocked) setState(() => _scrollLocked = false);
        });
      } else {
        _performInitialScroll();
      }
      _saveMessagesToLocalCache();
    }).catchError((e) {
      debugPrint('Error loading messages: $e');
      if (mounted) {
        setState(() {
          _isFirstLoad = false;
          _scrollLocked = false;
        });
      }
    });

    // Real-time new messages — debounced to batch rapid consecutive socket events
    // into a single setState instead of one rebuild per message.
    _messagesSubscription = _socketService.onNewMessage.listen((data) {
      if (!mounted) return;
      if (data['chatRoomId']?.toString() != widget.chatRoomId) return;

      final newMsg = Map<String, dynamic>.from(data);
      // Normalise timestamp to DateTime for UI consistency
      final ts = SocketService.parseTimestamp(newMsg['timestamp']);
      if (ts != null) newMsg['timestamp'] = ts;

      _pendingIncomingMessages.add(newMsg);

      // Reset the debounce timer; after 100 ms of silence we flush all buffered
      // messages in a single setState (one rebuild instead of one per message).
      _incomingMessageDebounce?.cancel();
      _incomingMessageDebounce = Timer(const Duration(milliseconds: 100), _flushPendingMessages);
    });

    // Listen for edits and deletes
    _messageEditedSubscription?.cancel();
    _messageEditedSubscription = _socketService.onMessageEdited.listen((data) {
      if (!mounted) return;
      if (data['chatRoomId']?.toString() != widget.chatRoomId) return;
      final idx = _cachedMessages.indexWhere(
        (m) => m['messageId']?.toString() == data['messageId']?.toString(),
      );
      if (idx >= 0) {
        setState(() {
          _cachedMessages[idx] = {
            ..._cachedMessages[idx],
            'message':  data['newMessage'],
            'isEdited': true,
            'editedAt': data['editedAt'],
          };
          _messagesCacheVersion++;
        });
        _saveMessagesToLocalCache();
      }
    });

    _messageDeletedSubscription?.cancel();
    _messageDeletedSubscription = _socketService.onMessageDeleted.listen((data) {
      if (!mounted) return;
      if (data['chatRoomId']?.toString() != widget.chatRoomId) return;
      final msgId = data['messageId']?.toString();
      if (data['deleteForEveryone'] == true) {
        // Mark with a single flag – show "This message was deleted" placeholder for both parties
        final idx = _cachedMessages.indexWhere((m) => m['messageId']?.toString() == msgId);
        if (idx >= 0) {
          setState(() {
            _cachedMessages[idx] = {
              ..._cachedMessages[idx],
              'deletedForEveryone': true,
            };
            _messagesCacheVersion++;
          });
          _saveMessagesToLocalCache();
        }
      } else {
        final idx = _cachedMessages.indexWhere((m) => m['messageId']?.toString() == msgId);
        if (idx >= 0) {
          final isMine = data['userId']?.toString() == widget.currentUserId;
          setState(() {
            _cachedMessages[idx] = {
              ..._cachedMessages[idx],
              if (isMine) 'isDeletedForSender':   true,
              if (!isMine) 'isDeletedForReceiver': true,
            };
            _messagesCacheVersion++;
          });
          _saveMessagesToLocalCache();
        }
      }
    });

    _messageUnsentSubscription?.cancel();
    _messageUnsentSubscription = _socketService.onMessageUnsent.listen((data) {
      if (!mounted) return;
      if (data['chatRoomId']?.toString() != widget.chatRoomId) return;
      final msgId = data['messageId']?.toString();
      final idx = _cachedMessages.indexWhere((m) => m['messageId']?.toString() == msgId);
      if (idx >= 0) {
        setState(() {
          _cachedMessages[idx] = {
            ..._cachedMessages[idx],
            'isUnsent': true,
          };
          _messagesCacheVersion++;
        });
        _saveMessagesToLocalCache();
      }
    });

    _messageReactionSubscription?.cancel();
    _messageReactionSubscription = _socketService.onMessageReaction.listen((data) {
      if (!mounted) return;
      if (data['chatRoomId']?.toString() != widget.chatRoomId) return;
      final msgId = data['messageId']?.toString();
      final Map<String, dynamic> reactions =
          (data['reactions'] is Map) ? Map<String, dynamic>.from(data['reactions'] as Map) : {};
      final idx = _cachedMessages.indexWhere((m) => m['messageId']?.toString() == msgId);
      if (idx >= 0) {
        setState(() {
          _cachedMessages[idx] = {..._cachedMessages[idx], 'reactions': reactions};
          _messagesCacheVersion++;
        });
        _saveMessagesToLocalCache();
      }
    });
  }

  /// Flushes all buffered incoming messages in a single setState call.
  /// Called by [_incomingMessageDebounce] after a 100 ms quiet period.
  void _flushPendingMessages() {
    if (!mounted || _pendingIncomingMessages.isEmpty) return;

    // Determine scroll intent before setState so we don't read scroll position
    // inside the setState callback (which should only mutate state variables).
    bool shouldScroll = false;
    bool hasNewIncoming = false;
    for (final newMsg in _pendingIncomingMessages) {
      final existingIdx = _cachedMessages.indexWhere(
        (m) => m['messageId']?.toString() == newMsg['messageId']?.toString(),
      );
      if (existingIdx < 0) {
        if (_forceScrollToBottom || _isNearBottom()) {
          shouldScroll = true;
        }
        // Check if this is a new message from the other party
        if (newMsg['senderId']?.toString() != widget.currentUserId) {
          hasNewIncoming = true;
        }
      }
    }

    setState(() {
      for (final newMsg in _pendingIncomingMessages) {
        final existingIdx = _cachedMessages.indexWhere(
          (m) => m['messageId']?.toString() == newMsg['messageId']?.toString(),
        );
        if (existingIdx >= 0) {
          _cachedMessages[existingIdx] = newMsg;
        } else {
          _cachedMessages.add(newMsg);
        }
      }
      _pendingIncomingMessages.clear();
      _messagesCacheVersion++;
      if (_forceScrollToBottom) _forceScrollToBottom = false;
    });

    if (hasNewIncoming) _playReceiveSound();
    _syncVisibleIncomingMessagesAsRead(_cachedMessages);
    if (shouldScroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
    _saveMessagesToLocalCache();
  }

  void _loadCallHistory() {
    // Use a live stream so the section updates whenever a call is made/ended
    _callHistorySubscription =
        CallHistoryService.getCallHistory(widget.currentUserId).listen(
      (allCalls) {
        // Filter calls for this specific chat partner
        final filteredCalls = allCalls.where((call) {
          return (call.callerId == widget.currentUserId &&
                  call.recipientId == widget.receiverId) ||
              (call.recipientId == widget.currentUserId &&
                  call.callerId == widget.receiverId);
        }).toList();

        if (mounted) {
          setState(() {
            _callHistory = filteredCalls;
          });
        }
      },
      onError: (e) {
        print('Error loading call history: $e');
      },
    );
  }
  Future<void> _checkBlockStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final userDataString = prefs.getString('user_data');
    if (userDataString == null) {
      if (mounted) setState(() => _isLoadingBlock = false);
      return;
    }

    final userData = jsonDecode(userDataString);
    final myId = userData["id"].toString();

    final service = ProfileService();
    try {
      final status = await service.getBlockStatus(
        myId: myId,
        userId: widget.receiverId,
      );

      if (mounted) {
        setState(() {
          _isBlocked = status['is_blocked'] ?? false;
          _isBlockedByReceiver = status['is_blocked_by'] ?? false;
          _isLoadingBlock = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingBlock = false);
    }
  }

  Future<void> _fetchPhotoRequestStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataString = prefs.getString('user_data');
      if (userDataString == null) return;

      final userData = jsonDecode(userDataString);
      final myId = userData["id"].toString();

      final service = ProfileService();
      final profileResponse = await service.fetchProfile(
        myId: myId,
        userId: widget.receiverId,
      );

      if (mounted) {
        setState(() {
          _photoRequestStatus = profileResponse.data.personalDetail.photoRequest;
          _chatRequestStatus = profileResponse.data.personalDetail.chatRequest.isNotEmpty
              ? profileResponse.data.personalDetail.chatRequest
              : 'not_sent';
          _privacyStatus = profileResponse.data.personalDetail.privacy;
        });
      }
    } catch (e) {
      debugPrint('Error fetching photo request status: $e');
    }
  }

  // ───────── TYPING INDICATOR ─────────

  void _listenToTypingStatus() {
    _typingSubscription = _socketService.onTypingStart.listen((data) {
      if (!mounted) return;
      if (data['chatRoomId']?.toString() != widget.chatRoomId) return;
      if (data['userId']?.toString() != widget.receiverId) return;
      if (!_isReceiverTyping) {
        setState(() => _isReceiverTyping = true);
        _startTypingRepeat();
      }
      // Reset auto-clear timeout
      _typingDebounce?.cancel();
      _typingDebounce = Timer(Duration(seconds: _kTypingTimeoutSeconds), () {
        _stopTypingRepeat();
        if (mounted && _isReceiverTyping) setState(() => _isReceiverTyping = false);
      });
    });

    // Stop typing
    _typingStopSubscription?.cancel();
    _typingStopSubscription = _socketService.onTypingStop.listen((data) {
      if (!mounted) return;
      if (data['chatRoomId']?.toString() != widget.chatRoomId) return;
      if (data['userId']?.toString() != widget.receiverId) return;
      _typingDebounce?.cancel();
      _stopTypingRepeat();
      if (_isReceiverTyping) setState(() => _isReceiverTyping = false);
    });
  }

  // Start the repeating typewriter-click sound while the remote user is typing.
  void _startTypingRepeat() {
    _typingRepeatTimer?.cancel();
    _playTypingSound(); // Immediate first click
    _typingRepeatTimer = Timer.periodic(const Duration(milliseconds: 130), (_) {
      if (!_isReceiverTyping || !SoundSettingsService.instance.typingSoundEnabled) {
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

  // Play a short typing-indicator beep (Messenger-style)
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

  // Play a short message-received notification sound and vibrate
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

  void _applyReceiverStatus(Map<String, dynamic> data) {
    if (!mounted) return;
    final bool online = data['isOnline'] == true;
    final DateTime? lastSeen = SocketService.parseTimestamp(data['lastSeen']);
    setState(() {
      _isOtherUserOnline = online;
      _otherUserLastSeen  = lastSeen;
    });
  }

  void _startReceiverStatusListener() {
    _otherUserStatusSub?.cancel();
    _otherUserStatusSub = _socketService.onUserStatusChange.listen((data) {
      if (data['userId']?.toString() != widget.receiverId) return;
      _applyReceiverStatus(data);
    });

    // Fetch the current status immediately so the correct online/offline state
    // is shown when the chat screen first opens (before any status-change event).
    _socketService.getUserStatus(widget.receiverId).then(_applyReceiverStatus);
  }

  /// Format lastSeen timestamp into a human-readable "last active" string.
  String _formatLastSeen(DateTime lastSeen) => formatLastSeen(lastSeen);


  void _onTypingChanged() {
    _typingDebounce?.cancel();
    if (!_isTyping) {
      _isTyping = true;
      _socketService.startTyping(widget.chatRoomId, widget.currentUserId);
    }
    _typingDebounce = Timer(_kTypingDebounceDelay, _clearTyping);
  }

  void _clearTyping() {
    _typingDebounce?.cancel();
    if (!_isTyping) return;
    _isTyping = false;
    _socketService.stopTyping(widget.chatRoomId, widget.currentUserId);
  }

  // Backup incoming call listener so calls ring while the user is typing on
  // this screen.  The global CallOverlayWrapper is the primary handler; this
  // ensures the call UI still appears if its frame callback is delayed
  // (e.g. keyboard open with no frames being rendered).
  void _setupCallListener() {
    _callListenerSubscription?.cancel();
    _callListenerSubscription = NotificationService.incomingCalls.listen((data) {
      final isVideoCall =
          data['type'] == 'video_call' || data['isVideoCall'] == 'true';
      // Dismiss keyboard so it does not block the call screen.
      FocusManager.instance.primaryFocus?.unfocus();
      // Schedule a frame first so the postFrameCallback below fires immediately,
      // even when the app is idle (no frames being scheduled, e.g. keyboard open).
      WidgetsBinding.instance.scheduleFrame();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // isCallScreenShowing is set by whichever listener fires first (usually
        // CallOverlayWrapper).  Skip if the screen is already being shown.
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
          // Reset the flag if push fails so future calls are not blocked.
          CallManager().isCallScreenShowing = false;
        }
      });
    });
  }

  Future<void> _setActiveChatPresence({required bool isActive}) async {
    _socketService.setActiveChat(widget.currentUserId, widget.chatRoomId, isActive: isActive);
  }

  void _updateActiveChatPresence(bool isActive) {
    unawaited(
      _setActiveChatPresence(isActive: isActive).catchError((Object error) {
        debugPrint('Error updating active chat presence: $error');
      }),
    );
  }

  void _syncVisibleIncomingMessagesAsRead(List<Map<String, dynamic>> messages) {
    if (_isMarkingMessagesAsRead) return;
    final hasUnreadIncoming = messages.any((message) =>
        message['receiverId'] == widget.currentUserId &&
        message['isRead'] != true);
    if (!hasUnreadIncoming) return;
    _markMessagesAsRead();
  }

  // ───────── SCROLL TO REPLIED MESSAGE ─────────

  /// Scroll to the message with [messageId] and briefly highlight it.
  void _scrollToMessage(String messageId) {
    final key = _messageKeys[messageId];

    void _highlight() {
      setState(() => _highlightedMessageId = messageId);
      Future.delayed(_kHighlightDuration, () {
        if (mounted) setState(() => _highlightedMessageId = null);
      });
    }

    if (key?.currentContext != null) {
      Scrollable.ensureVisible(
        key!.currentContext!,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
        alignment: 0.3,
      );
      _highlight();
      return;
    }

    // Widget not rendered – scroll to approximate position by message index
    final idx = _cachedMessages.indexWhere(
      (m) => m['messageId']?.toString() == messageId,
    );
    if (idx < 0 || !_scrollController.hasClients) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Original message is not in view. Scroll up to find it.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final total = _cachedMessages.length;
    final fraction = idx / total;
    final targetPixels =
        _scrollController.position.maxScrollExtent * fraction;

    _scrollController.animateTo(
      targetPixels,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );

    // After scrolling completes, try ensureVisible then highlight
    Future.delayed(_kScrollToMessageDelay, () {
      if (!mounted) return;
      final k = _messageKeys[messageId];
      if (k?.currentContext != null) {
        Scrollable.ensureVisible(
          k!.currentContext!,
          duration: const Duration(milliseconds: 200),
          alignment: 0.3,
        );
      }
      _highlight();
    });
  }
  @override
  void dispose() {
    // Clear chat active state when screen closes
    ScreenStateManager().onChatScreenClosed();
    _updateActiveChatPresence(false);
    WidgetsBinding.instance.removeObserver(this);
    _messageController.removeListener(_onMessageTextChanged);
    _messageController.dispose();
    _editController.dispose();
    _scrollController.dispose();
    _messageFocusNode.dispose();
    _audioPlayerStateSubscription?.cancel();
    _audioPlayerPositionSubscription?.cancel();
    _audioPlayerDurationSubscription?.cancel();
    _audioStateNotifier.dispose();
    _audioPlayer.dispose();
    _recordTimer?.cancel();
    _amplitudeSubscription?.cancel();
    _recordDurationNotifier.dispose();
    _audioAmplitudeNotifier.dispose();
    _audioRecorder.dispose();
    _recordingAnimController?.dispose();
    _typingDebounce?.cancel();
    _typingRepeatTimer?.cancel();
    _typingSubscription?.cancel();
    _typingStopSubscription?.cancel();
    _typingAudioPlayer.dispose();
    _receiveAudioPlayer.dispose();
    _incomingMessageDebounce?.cancel();
    _messageEditedSubscription?.cancel();
    _messageDeletedSubscription?.cancel();
    _messageUnsentSubscription?.cancel();
    _messageReactionSubscription?.cancel();
    _otherUserStatusSub?.cancel();
    _callHistorySubscription?.cancel();
    _callListenerSubscription?.cancel();
    _messagesSubscription?.cancel();
    _socketService.leaveRoom(widget.chatRoomId);
    _clearTyping(); // Remove our typing entry on exit
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // Handle app lifecycle changes
    switch (state) {
      case AppLifecycleState.resumed:
      // App came back to foreground, set chat as active
        ScreenStateManager().onChatScreenOpened(
          widget.chatRoomId,
          widget.currentUserId,
          partnerUserId: widget.receiverId,
        );
        _updateActiveChatPresence(true);
        _markMessagesAsRead();
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      // App went to background, clear active state
        ScreenStateManager().onChatScreenClosed();
        _updateActiveChatPresence(false);
        break;
      case AppLifecycleState.detached:
      // App is closed
        ScreenStateManager().onChatScreenClosed();
        _updateActiveChatPresence(false);
        break;
      case AppLifecycleState.hidden:
      // App is hidden
        ScreenStateManager().onChatScreenClosed();
        _updateActiveChatPresence(false);
        break;
    }
  }

  // MARK MESSAGES AS READ
  Future<void> _markMessagesAsRead() async {
    if (_isMarkingMessagesAsRead) return;
    _isMarkingMessagesAsRead = true;
    try {
      await _markMessagesAsReadInternal();
    } finally {
      _isMarkingMessagesAsRead = false;
    }
  }

  Future<void> _markMessagesAsReadInternal() async {
    try {
      _socketService.markRead(widget.chatRoomId, widget.currentUserId);
    } catch (e) {
      print('Error marking messages as read: $e');
    }
  }

  // SEND MESSAGE (with reply support)
  Future<void> _sendMessage() async {
    if (_isEitherBlocked) return;
    if (_chatRequestStatus != 'unknown' && _chatRequestStatus != 'accepted') return;
    final messageText = _messageController.text.trim();
    if (messageText.isEmpty) return;

    // Clear input immediately to prevent duplicate sends
    _messageController.clear();
    if (mounted) setState(() { _isSending = true; });

    try {
      final timestamp = DateTime.now();
      final messageId = _uuid.v4();
      final bool receiverViewingThisChat = _isReceiverViewingThisChat;

      // Prepare message data
      final messageData = <String, dynamic>{
        'messageId': messageId,
        'senderId': widget.currentUserId,
        'receiverId': widget.receiverId,
        'message': messageText,
        'messageType': 'text',
        'timestamp': timestamp,
        'isRead': receiverViewingThisChat,
        'isDelivered': receiverViewingThisChat,
        'isDeletedForSender': false,
        'isDeletedForReceiver': false,
      };

      // Add reply data if replying to a message
      if (isReplying && repliedMessage != null) {
        messageData['repliedTo'] = {
          'messageId': repliedMessage!['messageId'],
          'message': repliedMessage!['message'],
          'senderId': repliedMessage!['senderId'],
          'senderName': repliedMessage!['senderId'] == widget.currentUserId
              ? widget.currentUserName
              : widget.receiverName,
          'messageType': repliedMessage!['messageType'] ?? 'text',
        };
      }

      // Clear reply/edit states
      _cancelReply();
      _cancelEdit();

      // Optimistic UI: add message immediately so the list grows exactly once.
      // The server echo will find this entry by messageId (existingIdx >= 0) and
      // update it in-place (read/delivered status) without appending a duplicate
      // or resetting the scroll position.
      setState(() {
        _cachedMessages.add(Map<String, dynamic>.from(messageData));
        _messagesCacheVersion++;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

      // Send via Socket.IO
      _socketService.sendMessage(
        chatRoomId:        widget.chatRoomId,
        senderId:          widget.currentUserId,
        receiverId:        widget.receiverId,
        message:           messageText,
        messageType:       'text',
        messageId:         messageId,
        repliedTo:         messageData['repliedTo'] as Map<String, dynamic>?,
        isReceiverViewing: receiverViewingThisChat,
        user1Name:         widget.currentUserName,
        user2Name:         widget.receiverName,
        user1Image:        widget.currentUserImage,
        user2Image:        widget.receiverImage,
      );

      if (!receiverViewingThisChat) {
        // Send notification after message is saved
        await NotificationService.sendChatNotification(
          recipientUserId: widget.receiverId.toString(),
          senderName: widget.currentUserName,
          senderId: widget.currentUserId.toString(),
          message: messageText,
        );
      }

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to send message: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() { _isSending = false; });
    }
  }

  bool _isSendingImage = false;

  Future<void> _pickAndSendImages() async {
    if (_isEitherBlocked || _isSendingImage) return;
    if (_chatRequestStatus != 'unknown' && _chatRequestStatus != 'accepted') return;
    final picker = ImagePicker();
    List<XFile> picked = [];
    try {
      picked = await picker.pickMultiImage(imageQuality: 80);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to access gallery. Please check permissions.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }
    if (picked.isEmpty || !mounted) return;

    setState(() => _isSendingImage = true);
    try {
      final bool receiverViewingThisChat = _isReceiverViewingThisChat;
      // Upload all images in parallel for speed
      final List<String?> urls = await Future.wait(
        picked.map((xfile) async {
          try {
            return await _socketService.uploadChatImage(
              bytes: await xfile.readAsBytes(),
              filename: xfile.name,
              userId:    widget.currentUserId,
              chatRoomId: widget.chatRoomId,
            );
          } catch (_) {
            return null;
          }
        }),
      );

      if (!mounted) return;

      final validUrls = urls.whereType<String>().toList();
      if (validUrls.isEmpty) return;

      final timestamp = DateTime.now();
      if (validUrls.length == 1) {
        // Single image — optimistic UI then send
        final messageId = _uuid.v4();
        setState(() {
          _cachedMessages.add({
            'messageId': messageId,
            'senderId': widget.currentUserId,
            'receiverId': widget.receiverId,
            'message': validUrls.first,
            'messageType': 'image',
            'timestamp': timestamp,
            'isRead': receiverViewingThisChat,
            'isDelivered': receiverViewingThisChat,
            'isDeletedForSender': false,
            'isDeletedForReceiver': false,
          });
          _messagesCacheVersion++;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
        _socketService.sendMessage(
          chatRoomId:        widget.chatRoomId,
          senderId:          widget.currentUserId,
          receiverId:        widget.receiverId,
          message:           validUrls.first,
          messageType:       'image',
          messageId:         messageId,
          isReceiverViewing: receiverViewingThisChat,
          user1Name:         widget.currentUserName,
          user2Name:         widget.receiverName,
          user1Image:        widget.currentUserImage,
          user2Image:        widget.receiverImage,
        );
      } else {
        // Multiple images — optimistic UI then send
        final messageId = _uuid.v4();
        setState(() {
          _cachedMessages.add({
            'messageId': messageId,
            'senderId': widget.currentUserId,
            'receiverId': widget.receiverId,
            'message': jsonEncode(validUrls),
            'messageType': 'image_gallery',
            'timestamp': timestamp,
            'isRead': receiverViewingThisChat,
            'isDelivered': receiverViewingThisChat,
            'isDeletedForSender': false,
            'isDeletedForReceiver': false,
          });
          _messagesCacheVersion++;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
        _socketService.sendMessage(
          chatRoomId:        widget.chatRoomId,
          senderId:          widget.currentUserId,
          receiverId:        widget.receiverId,
          message:           jsonEncode(validUrls),
          messageType:       'image_gallery',
          messageId:         messageId,
          isReceiverViewing: receiverViewingThisChat,
          user1Name:         widget.currentUserName,
          user2Name:         widget.receiverName,
          user1Image:        widget.currentUserImage,
          user2Image:        widget.receiverImage,
        );
      }

      if (!receiverViewingThisChat) {
        await NotificationService.sendChatNotification(
          recipientUserId: widget.receiverId.toString(),
          senderName: widget.currentUserName,
          senderId: widget.currentUserId.toString(),
          message: validUrls.length == 1 ? '📷 Photo' : '📷 ${validUrls.length} Photos',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send image: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSendingImage = false);
    }
  }

  // ── VOICE MESSAGE RECORDING ──────────────────────────────────────────────

  Future<void> _startRecording() async {
    if (_isEitherBlocked || _isRecording) return;
    if (_chatRequestStatus != 'unknown' && _chatRequestStatus != 'accepted') return;

    // Request microphone permission (native only; web uses browser prompt)
    if (!kIsWeb) {
      final status = await Permission.microphone.request();
      if (status != PermissionStatus.granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Microphone permission is required to record voice messages.'),
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

      // Monitor amplitude so the waveform shows flat bars when there is silence
      _amplitudeSubscription?.cancel();
      _amplitudeSubscription = _audioRecorder
          .onAmplitudeChanged(const Duration(milliseconds: 100))
          .listen((amp) {
        _audioAmplitudeNotifier.value = amp.current;
      });

      setState(() {
        _isRecording = true;
        _recordingPath = path;
      });
      _recordDurationNotifier.value = 0;

      _recordingAnimController?.repeat();
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        _recordDurationNotifier.value = _recordDurationNotifier.value + 1;
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
    _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;
    _audioAmplitudeNotifier.value = -160.0;
    _recordingAnimController?.stop();
    _recordingAnimController?.reset();
    if (mounted) setState(() => _isHoldRecording = false);

    try {
      final path = await _audioRecorder.stop();
      setState(() {
        _isRecording = false;
        _isSendingVoice = true;
      });

      if (path == null || path.isEmpty) return;

      final messageId = _uuid.v4();
      final bool receiverViewingThisChat = _isReceiverViewingThisChat;

      // Read file bytes cross-platform (works on web and native)
      Uint8List voiceBytes;
      if (kIsWeb) {
        // On web path is a blob URL; use XFile to read bytes
        final xfile = XFile(path);
        voiceBytes = await xfile.readAsBytes();
      } else {
        voiceBytes = await File(path).readAsBytes();
      }

      final voiceUrl = await _socketService.uploadVoiceMessage(
        bytes: voiceBytes,
        filename: 'voice_${DateTime.now().millisecondsSinceEpoch}.mp3',
        userId: widget.currentUserId,
        chatRoomId: widget.chatRoomId,
      );

      // Optimistic UI: add the voice message immediately so the list grows once.
      setState(() {
        _cachedMessages.add({
          'messageId': messageId,
          'senderId': widget.currentUserId,
          'receiverId': widget.receiverId,
          'message': voiceUrl,
          'messageType': 'voice',
          'timestamp': DateTime.now(),
          'isRead': receiverViewingThisChat,
          'isDelivered': receiverViewingThisChat,
          'isDeletedForSender': false,
          'isDeletedForReceiver': false,
          'duration': _recordDurationNotifier.value,
        });
        _messagesCacheVersion++;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

      _socketService.sendMessage(
        chatRoomId:        widget.chatRoomId,
        senderId:          widget.currentUserId,
        receiverId:        widget.receiverId,
        message:           voiceUrl,
        messageType:       'voice',
        messageId:         messageId,
        isReceiverViewing: receiverViewingThisChat,
        user1Name:         widget.currentUserName,
        user2Name:         widget.receiverName,
        user1Image:        widget.currentUserImage,
        user2Image:        widget.receiverImage,
      );

      if (!receiverViewingThisChat) {
        await NotificationService.sendChatNotification(
          recipientUserId: widget.receiverId.toString(),
          senderName: widget.currentUserName,
          senderId: widget.currentUserId.toString(),
          message: '🎤 Voice message',
        );
      }
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
    _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;
    _audioAmplitudeNotifier.value = -160.0;
    _recordDurationNotifier.value = 0;
    _recordingAnimController?.stop();
    _recordingAnimController?.reset();
    _audioRecorder.stop();
    setState(() {
      _isRecording = false;
      _isHoldRecording = false;
    });
  }

  String _formatRecordDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _editMessage() async {
    if (editingMessage == null || _editController.text.trim().isEmpty) return;

    try {
      final messageId = editingMessage!['messageId'];
      final newMessage = _editController.text.trim();

      _socketService.editMessage(widget.chatRoomId, messageId, newMessage);

      _cancelEdit();
      _scrollToBottom();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Message edited'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to edit message: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }


  // MESSAGE ACTIONS
  Future<void> _deleteMessage(bool deleteForEveryone) async {
    if (selectedMessage == null) return;

    try {
      final messageId = selectedMessage!['messageId'];

      _socketService.deleteMessage(
        chatRoomId:        widget.chatRoomId,
        messageId:         messageId,
        userId:            widget.currentUserId,
        deleteForEveryone: deleteForEveryone,
      );

      if (mounted) {
        setState(() {
          showDeletePopup = false;
          showActionOverlay = false;
          selectedMessage = null;
        });
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Message deleted'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      print('Error deleting message: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete message: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _copyMessage() {
    if (selectedMessage != null && selectedMessage!['messageType'] == 'text') {
      Clipboard.setData(ClipboardData(text: selectedMessage!['message']));
      if (mounted) {
        setState(() {
          showActionOverlay = false;
          selectedMessage = null;
        });
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Message copied to clipboard'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  // REPLY FUNCTIONALITY
  void _setReplyMessage(Map<String, dynamic> message) {
    if (mounted) {
      setState(() {
        repliedMessage = message;
        isReplying = true;
        showActionOverlay = false;
      });
    }

    _messageFocusNode.requestFocus();
  }

  void _cancelReply() {
    if (mounted) {
      setState(() {
        repliedMessage = null;
        isReplying = false;
      });
    }
  }

  // EDIT FUNCTIONALITY
  void _setEditMessage(Map<String, dynamic> message) {
    if (mounted) {
      setState(() {
        editingMessage = message;
        isEditing = true;
        _editController.text = message['message'];
        showActionOverlay = false;
      });
    }

    _messageFocusNode.requestFocus();
  }

  void _cancelEdit() {
    if (mounted) {
      setState(() {
        editingMessage = null;
        isEditing = false;
        _editController.clear();
      });
    }
  }

  // FORMATTING HELPERS
  String _formatTime(DateTime timestamp) {
    return DateFormat('hh:mm a').format(timestamp.toLocal());
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
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
        // Wait for layout to settle before unlocking
        WidgetsBinding.instance.addPostFrameCallback((_) {
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

  void _scrollToBottom({bool jump = false}) {
    // Don't auto-scroll if scroll is locked during initial load
    if (_scrollLocked) return;

    void doScroll() {
      if (!mounted || !_scrollController.hasClients) return;
      if (jump) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      } else {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    }

    // A single post-frame callback is sufficient. ListView (non-lazy) measures all
    // children in a single pass so the maxScrollExtent is correct by the first frame.
    // The previous double-callback caused visible double-jumping.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scrollController.hasClients) {
        doScroll();
      } else {
        // Controller not yet attached to a scroll view; retry after a short delay.
        Future.delayed(const Duration(milliseconds: 50), doScroll);
      }
    });
  }

  /// Returns a short preview string for a replied-to message.
  String _replySnippetText(Map<String, dynamic> repliedTo) {
    switch (repliedTo['messageType'] as String? ?? 'text') {
      case 'image':
        return '📷 Photo';
      case 'image_gallery':
        return '🖼️ Photos';
      case 'voice':
        return '🎤 Voice message';
      case 'call':
        return '📞 Voice call';
      case 'video_call':
        return '📹 Video call';
      case 'profile_card':
        return '👤 Profile card';
      case 'report':
        return '🚩 Profile reported';
      default:
        return repliedTo['message'] as String? ?? '';
    }
  }


  /// Returns true when the user is within 150px of the bottom of the list.
  bool _isNearBottom() {
    if (!_scrollController.hasClients) return true;
    final pos = _scrollController.position;
    return pos.pixels >= pos.maxScrollExtent - 150;
  }

  // VOICE PLAYBACK
  Future<void> _toggleVoicePlayback(String messageId, String audioUrl) async {
    final state = _audioStateNotifier.value;
    if (state.playingId == messageId && state.isPlaying) {
      await _audioPlayer.pause();
    } else if (state.playingId == messageId && !state.isPlaying) {
      await _audioPlayer.resume();
    } else {
      _audioStateNotifier.value = _AudioPlaybackState(playingId: messageId);
      await _audioPlayer.play(UrlSource(audioUrl));
    }
  }


  Widget _buildReplyPreview() {
    if (!isReplying || repliedMessage == null) return const SizedBox.shrink();

    final isMyMessage = repliedMessage!['senderId'] == widget.currentUserId;
    final senderName = isMyMessage ? 'You' : widget.receiverName;
    final messageType = repliedMessage!['messageType'] ?? 'text';
    final message = repliedMessage!['message'];

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: _secondaryGradient,
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(
            color: _accentColor,
            width: 4,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: _accentColor.withOpacity(0.10),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Replying to $senderName',
                  style: TextStyle(
                    fontSize: 12,
                    color: _accentColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                if (messageType == 'text')
                  Text(
                    message,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: _lightTextColor),
                  )
                else if (messageType == 'image')
                  Row(
                    children: [
                      Icon(Icons.image, size: 15, color: _accentColor),
                      const SizedBox(width: 4),
                      Text('Photo',
                          style: TextStyle(fontSize: 13, color: _lightTextColor)),
                    ],
                  )
                else if (messageType == 'image_gallery')
                  Row(
                    children: [
                      Icon(Icons.photo_library, size: 15, color: _accentColor),
                      const SizedBox(width: 4),
                      Text('Photos',
                          style: TextStyle(fontSize: 13, color: _lightTextColor)),
                    ],
                  )
                else if (messageType == 'voice')
                  Row(
                    children: [
                      Icon(Icons.mic, size: 15, color: _accentColor),
                      const SizedBox(width: 4),
                      Text('Voice message',
                          style: TextStyle(fontSize: 13, color: _lightTextColor)),
                    ],
                  )
                else if (messageType == 'call')
                  Row(
                    children: [
                      Icon(Icons.call, size: 15, color: _accentColor),
                      const SizedBox(width: 4),
                      Text('Voice call',
                          style: TextStyle(fontSize: 13, color: _lightTextColor)),
                    ],
                  )
                else if (messageType == 'video_call')
                  Row(
                    children: [
                      Icon(Icons.videocam, size: 15, color: _accentColor),
                      const SizedBox(width: 4),
                      Text('Video call',
                          style: TextStyle(fontSize: 13, color: _lightTextColor)),
                    ],
                  )
                else if (messageType == 'profile_card')
                  Row(
                    children: [
                      Icon(Icons.person, size: 15, color: _accentColor),
                      const SizedBox(width: 4),
                      Text('Profile card',
                          style: TextStyle(fontSize: 13, color: _lightTextColor)),
                    ],
                  )
                else
                  Text(
                    message ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: _lightTextColor),
                  ),
              ],
            ),
          ),
          GestureDetector(
            onTap: _cancelReply,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 16, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }

  // EDIT PREVIEW WIDGET
  Widget _buildEditPreview() {
    if (!isEditing || editingMessage == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: _secondaryGradient,
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(color: _accentColor, width: 4),
        ),
        boxShadow: [
          BoxShadow(
            color: _accentColor.withOpacity(0.08),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Editing message',
                  style: TextStyle(
                    fontSize: 12,
                    color: _accentColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  editingMessage!['message'],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: _lightTextColor),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: _cancelEdit,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 16, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }

  // SWIPEABLE MESSAGE WIDGET
  Widget _swipeableMessage({
    required Widget child,
    required Map<String, dynamic> messageData,
    required bool isMine,
  }) {
    return _SwipeToReplyWrapper(
      isMine: isMine,
      onReply: () => _setReplyMessage(messageData),
      onDragStart: () {
        if (mounted) setState(() => _isHorizontalDragging = true);
      },
      onDragEnd: () {
        if (mounted) setState(() => _isHorizontalDragging = false);
      },
      child: child,
    );
  }

  // Message bubble with swipe reply
  Widget _messageBubble({
    required bool isMine,
    required String text,
    required DateTime timestamp,
    required String messageType,
    required bool isRead,
    required bool isDelivered,
    required int? duration,
    required Map<String, dynamic> messageData,
    required Map<String, dynamic>? repliedTo,
    required bool isEdited,
    bool isDeleted = false,
  }) {
    // Show a WhatsApp-style "This message was deleted" placeholder
    if (isDeleted) {
      return Row(
        mainAxisAlignment: isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade300, width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.block, size: 14, color: Colors.grey.shade500),
                const SizedBox(width: 6),
                Text(
                  'This message was deleted',
                  style: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: 14,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }
    final msgId = messageData['messageId'] as String? ?? '';
    // Assign a stable GlobalKey so we can scroll to this message
    final key = _messageKeys.putIfAbsent(msgId, () => GlobalKey());

    final time = _formatTime(timestamp);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isHighlighted = _highlightedMessageId == msgId;

    // Build the reply snippet widget (tappable to scroll to source)
    Widget? replyWidget;
    if (repliedTo != null) {
      replyWidget = GestureDetector(
        onTap: () {
          final replyId = repliedTo['messageId'] as String?;
          if (replyId != null) _scrollToMessage(replyId);
        },
        child: Container(
          width: 260,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            gradient: _secondaryGradient,
            borderRadius: BorderRadius.circular(10),
            border: Border(
              left: BorderSide(color: _accentColor, width: 3.5),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                repliedTo['senderName'] ?? 'User',
                style: TextStyle(
                  fontSize: 12,
                  color: _accentColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _replySnippetText(repliedTo),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: _lightTextColor),
              ),
            ],
          ),
        ),
      );
    }

    // Choose tick icon based on delivery/read state
    Widget _buildTick() {
      if (isRead) {
        return Icon(Icons.done_all, size: 16, color: const Color(0xFF34B7F1));
      } else if (isDelivered) {
        return Icon(Icons.done_all, size: 16, color: Colors.grey.shade500);
      } else {
        return Icon(Icons.done, size: 16, color: Colors.grey.shade500);
      }
    }

    Widget messageContent = GestureDetector(
      onLongPressStart: (details) {
        if (mounted) {
          setState(() {
            selectedMessage = messageData;
            selectedMine = isMine;
            showActionOverlay = true;
            _selectedMessageOffset = details.globalPosition;
          });
        }
      },
      child: Container(
        key: key,
        margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 8),
        decoration: BoxDecoration(
          color: isHighlighted ? _accentColor.withOpacity(0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            Column(
              crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (replyWidget != null) replyWidget,

                Container(
                  padding: (messageType == 'image' || messageType == 'image_gallery' || messageType == 'profile_card' || messageType == 'report')
                      ? EdgeInsets.zero
                      : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  constraints: BoxConstraints(
                    maxWidth: screenWidth * 0.75,
                  ),
                  clipBehavior: (messageType == 'image' || messageType == 'image_gallery' || messageType == 'profile_card' || messageType == 'report') ? Clip.antiAlias : Clip.none,
                  decoration: messageType == 'report'
                      ? const BoxDecoration(color: Colors.transparent)
                      : messageType == 'profile_card'
                      ? BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: _accentColor.withOpacity(0.18),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        )
                      : BoxDecoration(
                          gradient: isMine ? _primaryGradient : null,
                          color: isMine ? null : _receivedBubbleColor,
                          border: isMine
                              ? null
                              : Border.all(
                                  color: _receivedBubbleBorder,
                                  width: 1,
                                ),
                          borderRadius: isMine
                              ? const BorderRadius.only(
                                  topLeft: Radius.circular(20),
                                  topRight: Radius.circular(20),
                                  bottomLeft: Radius.circular(20),
                                  bottomRight: Radius.circular(4),
                                )
                              : const BorderRadius.only(
                                  topLeft: Radius.circular(20),
                                  topRight: Radius.circular(20),
                                  bottomLeft: Radius.circular(4),
                                  bottomRight: Radius.circular(20),
                                ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.08),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildMessageContent(
                        text: text,
                        messageType: messageType,
                        isMine: isMine,
                        duration: duration,
                        messageId: messageData['messageId'] ?? '',
                      ),
                      if (isEdited)
                        Padding(
                          padding: EdgeInsets.only(top: 4),
                          child: Text(
                            'Edited',
                            style: TextStyle(
                              fontSize: 10,
                              color: isMine ? Colors.white70 : _lightTextColor,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      time,
                      style: TextStyle(
                        color: _lightTextColor,
                        fontSize: 12,
                      ),
                    ),
                    if (isMine) ...[
                      const SizedBox(width: 4),
                      _buildTick(),
                    ]
                  ],
                ),
                // Reaction badge below the bubble
                Builder(builder: (_) {
                  final raw = messageData['reactions'];
                  if (raw == null) return const SizedBox.shrink();
                  final Map<String, dynamic> rxns = (raw is Map)
                      ? Map<String, dynamic>.from(raw as Map)
                      : {};
                  if (rxns.isEmpty) return const SizedBox.shrink();
                  return _buildReactionBadge(rxns, isMine);
                }),
              ],
            ),
            if (isMine) ...[
              const SizedBox(width: 10),
            ],
          ],
        ),
      ),
    );

    // Wrap with MouseRegion on web for hover quick-actions
    if (kIsWeb) {
      messageContent = MouseRegion(
        onEnter: (_) => setState(() => _hoveredMessageId = msgId),
        onExit: (_) => setState(() {
          if (_hoveredMessageId == msgId) _hoveredMessageId = null;
        }),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            messageContent,
            if (_hoveredMessageId == msgId)
              Positioned(
                top: 0,
                right: isMine ? null : -80,
                left: isMine ? -80 : null,
                child: _buildHoverActions(messageData, isMine),
              ),
          ],
        ),
      );
    }

    return _swipeableMessage(
      child: messageContent,
      messageData: messageData,
      isMine: isMine,
    );
  }

  /// Small row of quick-action buttons shown on hover (web only).
  Widget _buildHoverActions(Map<String, dynamic> msg, bool isMine) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black26, blurRadius: 6, offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _hoverActionBtn(Icons.reply, () => _setReplyMessage(msg)),
          if (isMine && msg['messageType'] == 'text')
            _hoverActionBtn(Icons.edit, () => _setEditMessage(msg)),
          _hoverActionBtn(Icons.delete, () {
            setState(() {
              selectedMessage = msg;
              selectedMine = isMine;
              showDeletePopup = true;
            });
          }, color: Colors.red),
        ],
      ),
    );
  }

  Widget _hoverActionBtn(IconData icon, VoidCallback onTap, {Color? color}) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, size: 18, color: color ?? Colors.grey[700]),
      ),
    );
  }

  Widget _buildReactionBadge(Map<String, dynamic> reactions, bool isMine) {
    final Map<String, int> emojiCounts = {};
    for (final emoji in reactions.values) {
      final e = emoji.toString();
      emojiCounts[e] = (emojiCounts[e] ?? 0) + 1;
    }
    if (emojiCounts.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.only(
        top: 2,
        left: isMine ? 0 : 4,
        right: isMine ? 4 : 0,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
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
                      color: _lightTextColor,
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

  Widget _buildMessageContent({
    required String text,
    required String messageType,
    required bool isMine,
    required int? duration,
    required String messageId,
  }) {
    switch (messageType) {
      case 'image':
        final double imgWidth = MediaQuery.of(context).size.width * _kImageWidthFraction;
        // Only blur if not mine AND photo request is not accepted - ignore privacy
        final bool shouldBlur = !isMine &&
            _photoRequestStatus.toLowerCase() != 'accepted';

        if (shouldBlur) {
          return SizedBox(
            width: imgWidth,
            height: imgWidth * _kImageAspectRatio,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                  child: CachedNetworkImage(
                    imageUrl: text,
                    width: imgWidth,
                    height: imgWidth * _kImageAspectRatio,
                    fit: BoxFit.cover,
                    errorWidget: (context, url, error) => Container(
                      color: Colors.grey[300],
                    ),
                  ),
                ),
                Container(
                  color: Colors.black.withOpacity(0.4),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.grey.shade800.withOpacity(0.9),
                          ),
                          child: const Icon(
                            Icons.lock,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Photo Protected',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        return GestureDetector(
          onTap: () {
            showDialog(
              context: context,
              builder: (context) => Dialog(
                backgroundColor: Colors.black,
                insetPadding: const EdgeInsets.all(8),
                child: Stack(
                  children: [
                    InteractiveViewer(
                      child: CachedNetworkImage(
                        imageUrl: text,
                        fit: BoxFit.contain,
                        errorWidget: (context, url, error) => const Center(
                          child: Icon(Icons.broken_image, color: Colors.white54, size: 64),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 16,
                      right: 16,
                      child: IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: imgWidth,
              minWidth: _kImageMinWidth,
              maxHeight: _kImageMaxHeight,
            ),
            child: CachedNetworkImage(
              imageUrl: text,
              fit: BoxFit.cover,
              placeholder: (context, url) => SizedBox(
                width: imgWidth,
                height: imgWidth * _kImageAspectRatio,
                child: const Center(child: CircularProgressIndicator()),
              ),
              errorWidget: (context, url, error) => SizedBox(
                width: imgWidth,
                height: imgWidth * _kImageAspectRatio,
                child: Center(child: Icon(Icons.broken_image, color: Colors.grey.shade400)),
              ),
            ),
          ),
        );
      case 'image_gallery':
        return _buildImageGallery(text: text);
      case 'voice':
        final totalSecs = duration ?? 0;
        // A single ValueListenableBuilder on the combined audio state notifier
        // rebuilds only this bubble on each position/state tick; the message
        // list cache remains valid throughout playback.
        return RepaintBoundary(
          child: ValueListenableBuilder<_AudioPlaybackState>(
            valueListenable: _audioStateNotifier,
            builder: (context, audioState, _) {
              final isCurrentMessage = audioState.playingId == messageId;
              final isCurrentlyPlaying = isCurrentMessage && audioState.isPlaying;
              final progressValue = isCurrentMessage && audioState.duration.inSeconds > 0
                  ? (audioState.position.inMilliseconds / audioState.duration.inMilliseconds)
                      .clamp(0.0, 1.0)
                  : 0.0;
              final displayTime = isCurrentMessage && audioState.duration.inSeconds > 0
                  ? _formatDuration(audioState.position.inSeconds)
                  : _formatDuration(totalSecs);
              return GestureDetector(
                onTap: () => _toggleVoicePlayback(messageId, text),
                child: SizedBox(
                  width: 210,
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: isMine
                              ? Colors.white.withOpacity(0.20)
                              : _accentColor.withOpacity(0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isCurrentlyPlaying ? Icons.pause : Icons.play_arrow,
                          color: isMine ? Colors.white : _accentColor,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: LinearProgressIndicator(
                                value: progressValue,
                                minHeight: 4.5,
                                backgroundColor: isMine
                                    ? Colors.white.withOpacity(0.18)
                                    : Colors.black.withOpacity(0.08),
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  isMine ? Colors.white : _accentColor,
                                ),
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              displayTime,
                              style: TextStyle(
                                color: isMine ? Colors.white70 : _lightTextColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      case 'report':
        return _buildReportCardWidget(text, isMine);
      case 'profile_card':
        return _buildProfileCardWidget(text, isMine);
      default:
        return Text(
          text,
          style: TextStyle(
            color: isMine ? Colors.white : _textColor,
            fontSize: 16,
            height: 1.4,
          ),
        );
    }
  }

  /// Builds a report card widget from a JSON-encoded report payload string.
  Widget _buildReportCardWidget(String jsonText, bool isMine) {
    Map<String, dynamic>? reportData;
    try {
      final decoded = jsonDecode(jsonText);
      if (decoded is Map) reportData = Map<String, dynamic>.from(decoded);
    } catch (_) {}

    final reportReason = reportData?['reportReason']?.toString() ?? '';
    final reportedUserName = reportData?['reportedUserName']?.toString() ?? '';
    final reportedUserId = reportData?['reportedUserId']?.toString() ?? '';
    final initials = reportedUserName.isNotEmpty
        ? reportedUserName.trim().split(' ').map((w) => w.isEmpty ? '' : w[0].toUpperCase()).take(2).join()
        : '?';

    return Container(
      constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDE7),
        border: Border.all(color: const Color(0xFFF9A825), width: 1.2),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft:
              isMine ? const Radius.circular(16) : const Radius.circular(4),
          bottomRight:
              isMine ? const Radius.circular(4) : const Radius.circular(16),
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
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
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
        ],
      ),
    );
  }

  /// Builds a profile card widget from a JSON-encoded profile data string.
  /// Design matches the admin chat profile card for consistency.
  Widget _buildProfileCardWidget(String jsonText, bool isMine) {
    Map<String, dynamic>? profileData;
    try {
      final decoded = jsonDecode(jsonText);
      if (decoded is Map) profileData = Map<String, dynamic>.from(decoded);
    } catch (_) {}

    if (profileData == null) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text('👤 Profile Card',
            style: TextStyle(color: _textColor, fontSize: 15)),
      );
    }

    // Normalize field names (handle both admin-sent and user-sent formats)
    final String userId = (profileData['userId'] ?? profileData['id'] ?? '').toString();
    final String firstName = (profileData['firstName'] ?? profileData['first'] ?? '').toString();
    final String lastName = (profileData['lastName'] ?? profileData['last'] ?? '').toString();
    final String fullName = '$firstName $lastName'.trim();
    final String displayName =
        fullName.isNotEmpty ? fullName : (profileData['name']?.toString() ?? 'Unknown');
    final String? photoUrl = profileData['profileImage']?.toString();
    final bool hasPhoto = photoUrl != null && photoUrl.isNotEmpty;

    // Privacy: use shouldBlurPhoto from the shared data
    final bool shouldBlurPhoto = profileData['shouldBlurPhoto'] == true;
    // For user-to-user chat, respect photo privacy
    final bool shouldShowClear = !shouldBlurPhoto;

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Gradient header banner ──
          Container(
            height: 60,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFD81B60), Color(0xFFAD1457), Color(0xFF880E4F)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Icon(Icons.favorite, color: Colors.white.withOpacity(0.7), size: 16),
                const SizedBox(width: 6),
                const Text(
                  'Profile Card',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
                const Spacer(),
                if (userId.isNotEmpty)
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
                      // Profile photo
                      Container(
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
                                  imageFilter: ui.ImageFilter.blur(
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
                      const SizedBox(height: 12),
                      // Name + meta
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
                          if (_hasValue(profileData['location'] ?? profileData['country']))
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
                      if (_hasValue(profileData['religion']))
                        _buildProfileInfoChip(Icons.menu_book_outlined, profileData['religion']),
                      if (_hasValue(profileData['community']))
                        _buildProfileInfoChip(Icons.groups_outlined, profileData['community']),
                      if (_hasValue(profileData['occupation']))
                        _buildProfileInfoChip(Icons.work_outline, profileData['occupation']),
                      if (_hasValue(profileData['education']))
                        _buildProfileInfoChip(Icons.school_outlined, profileData['education']),
                      if (_hasValue(profileData['height']))
                        _buildProfileInfoChip(Icons.height, profileData['height']),
                    ],
                  ),
                ),

                // ── Bio ──
                if (_hasValue(profileData['bio']) &&
                    profileData['bio'] != 'No bio available')
                  Transform.translate(
                    offset: const Offset(0, -14),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD81B60).withOpacity(0.06),
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
                      if (userId.isNotEmpty && userId != widget.currentUserId) {
                        // Navigate to the profile page so chat request status is
                        // checked and the correct action button is shown.
                        // Direct messaging without the other user's permission is
                        // not allowed regardless of membership type.
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ProfileScreen(userId: userId),
                          ),
                        );
                      }
                    },
                    icon: Icon(Icons.chat_bubble_outline,
                        size: 16, color: const Color(0xFFD81B60)),
                    label: const Text(
                      'Chat',
                      style: TextStyle(
                        color: Color(0xFFD81B60),
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
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ProfileScreen(userId: userId),
                          ),
                        );
                      }
                    },
                    icon: Icon(Icons.person_outline,
                        size: 16, color: const Color(0xFFD81B60)),
                    label: const Text(
                      'View Profile',
                      style: TextStyle(
                        color: Color(0xFFD81B60),
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
    );
  }

  bool _hasValue(dynamic val) {
    if (val == null) return false;
    final s = val.toString().trim();
    return s.isNotEmpty && s != 'N/A' && s != 'null' && s != 'Location not specified';
  }

  Widget _buildProfileInfoChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFD81B60).withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD81B60).withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: const Color(0xFFD81B60)),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFFD81B60),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // WhatsApp-style image gallery widget
  Widget _buildImageGallery({required String text}) {
    List<String> urls;
    try {
      final decoded = jsonDecode(text);
      if (decoded is List) {
        urls = decoded.whereType<String>().toList();
      } else {
        urls = [text];
      }
    } on FormatException catch (e) {
      debugPrint('image_gallery: JSON parse error: $e');
      urls = [text];
    } catch (e) {
      debugPrint('image_gallery: unexpected error: $e');
      urls = [text];
    }
    if (urls.isEmpty) return const SizedBox.shrink();
    if (urls.length == 1) {
      // Fallback: single image display
      return _buildSingleGalleryImage(urls.first);
    }

    const int maxVisible = 6;
    final int displayCount = urls.length > maxVisible ? maxVisible : urls.length;
    final int extraCount = urls.length > maxVisible ? urls.length - maxVisible + 1 : 0;
    final double screenWidth = MediaQuery.of(context).size.width;
    final double gridWidth = screenWidth * 0.65;
    const double gap = 2;

    Widget buildThumb(int index, {bool showOverlay = false, int extra = 0}) {
      final url = urls[index];
      Widget img = CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        placeholder: (ctx, url) => Container(
          color: Colors.grey.shade200,
          child: const Center(
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
        errorWidget: (_, __, ___) => Container(
          color: Colors.grey.shade300,
          child: Icon(Icons.broken_image, color: Colors.grey.shade500),
        ),
      );

      Widget tile = GestureDetector(
        onTap: () => _openGalleryViewer(urls, index),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
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
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                )
              : img,
        ),
      );
      return tile;
    }

    // Build WhatsApp-like layouts
    if (urls.length == 2) {
      // 2 images side by side
      final double h = gridWidth / 2 - gap / 2;
      return SizedBox(
        width: gridWidth,
        child: Row(
          children: [
            Expanded(child: SizedBox(height: h, child: buildThumb(0))),
            SizedBox(width: gap),
            Expanded(child: SizedBox(height: h, child: buildThumb(1))),
          ],
        ),
      );
    }

    if (urls.length == 3) {
      // Large on left, 2 stacked on right
      final double h = gridWidth * 0.6;
      return SizedBox(
        width: gridWidth,
        height: h,
        child: Row(
          children: [
            Expanded(flex: 2, child: SizedBox(height: h, child: buildThumb(0))),
            SizedBox(width: gap),
            Expanded(
              flex: 1,
              child: Column(
                children: [
                  Expanded(child: buildThumb(1)),
                  SizedBox(height: gap),
                  Expanded(child: buildThumb(2)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (urls.length == 4) {
      // 2x2 grid
      final double cellW = (gridWidth - gap) / 2;
      final double h = cellW;
      return SizedBox(
        width: gridWidth,
        child: Column(
          children: [
            Row(children: [
              SizedBox(width: cellW, height: h, child: buildThumb(0)),
              SizedBox(width: gap),
              SizedBox(width: cellW, height: h, child: buildThumb(1)),
            ]),
            SizedBox(height: gap),
            Row(children: [
              SizedBox(width: cellW, height: h, child: buildThumb(2)),
              SizedBox(width: gap),
              SizedBox(width: cellW, height: h, child: buildThumb(3)),
            ]),
          ],
        ),
      );
    }

    // 5+ images: 2-column grid, last visible cell may show "+N"
    final double cellW = (gridWidth - gap) / 2;
    final double cellH = cellW;
    final List<Widget> cells = [];
    for (int i = 0; i < displayCount; i++) {
      final bool isLast = i == displayCount - 1 && extraCount > 0;
      cells.add(SizedBox(
        width: cellW,
        height: cellH,
        child: buildThumb(i, showOverlay: isLast, extra: extraCount),
      ));
    }

    final List<Widget> rows = [];
    for (int i = 0; i < cells.length; i += 2) {
      if (i > 0) rows.add(SizedBox(height: gap));
      rows.add(Row(
        children: [
          cells[i],
          SizedBox(width: gap),
          if (i + 1 < cells.length) cells[i + 1] else SizedBox(width: cellW),
        ],
      ));
    }

    return SizedBox(width: gridWidth, child: Column(children: rows));
  }

  Widget _buildSingleGalleryImage(String url) {
    final double imgWidth = MediaQuery.of(context).size.width * _kImageWidthFraction;
    return GestureDetector(
      onTap: () => _openGalleryViewer([url], 0),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: imgWidth,
          minWidth: _kImageMinWidth,
          maxHeight: _kImageMaxHeight,
        ),
        child: CachedNetworkImage(imageUrl: url, fit: BoxFit.cover),
      ),
    );
  }

  void _openGalleryViewer(List<String> urls, int initialIndex) {
    showDialog(
      context: context,
      builder: (ctx) => _GalleryViewerDialog(urls: urls, initialIndex: initialIndex),
    );
  }

  // FULLSCREEN OVERLAY MENU
  Widget _fullScreenActionOverlay() {
    const emojis = ['❤️', '😂', '😮', '😢', '👍', '😡'];
    final msgId = selectedMessage?['messageId']?.toString() ?? '';
    final existingReactions = selectedMessage?['reactions'];
    final Map<String, dynamic> reactions = (existingReactions is Map)
        ? Map<String, dynamic>.from(existingReactions as Map)
        : {};
    final myReaction = reactions[widget.currentUserId]?.toString() ?? '';

    final screenHeight = MediaQuery.of(context).size.height;
    final tapY = _selectedMessageOffset.dy;

    // Position emoji bar: show above message if there is room, else below
    const double emojiBarHeight = 56.0;
    const double gap = 10.0;
    double emojiTop;
    if (tapY - emojiBarHeight - gap < 80) {
      emojiTop = tapY + gap;
    } else {
      emojiTop = tapY - emojiBarHeight - gap;
    }
    emojiTop = emojiTop.clamp(60.0, screenHeight - emojiBarHeight - 220.0);

    return GestureDetector(
      onTap: () {
        if (mounted) {
          setState(() => showActionOverlay = false);
        }
      },
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: double.infinity,
        height: double.infinity,
        child: ColoredBox(
          color: Colors.black.withOpacity(0.45),
          child: Stack(
            children: [
              // Emoji bar positioned near the message
              Positioned(
                top: emojiTop,
                left: 0,
                right: 0,
                child: Center(
                  child: GestureDetector(
                    onTap: () {}, // absorb taps so background isn't dismissed
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
                              setState(() => showActionOverlay = false);
                              if (msgId.isNotEmpty) {
                                _socketService.addReaction(
                                    widget.chatRoomId, msgId, e);
                              }
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
                                style: TextStyle(
                                  fontSize: isSelected ? 28 : 24,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
              ),
              // Action panel anchored at the bottom, overlapping the input area
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: GestureDetector(
                  onTap: () {}, // absorb taps
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFF1E1E1E),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Drag handle
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        if (selectedMessage != null)
                          _menuItem(Icons.reply, "Reply", () {
                            _setReplyMessage(selectedMessage!);
                          }),
                        if (selectedMessage != null &&
                            selectedMessage!['messageType'] == 'text')
                          _menuItem(Icons.copy, "Copy", _copyMessage),
                        if (selectedMessage != null &&
                            selectedMine &&
                            selectedMessage!['messageType'] == 'text')
                          _menuItem(Icons.edit, "Edit", () {
                            _setEditMessage(selectedMessage!);
                          }),
                        _menuItem(Icons.delete, "Delete", () {
                          if (mounted) {
                            setState(() {
                              showActionOverlay = false;
                              showDeletePopup = true;
                            });
                          }
                        }, isDelete: true),
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

  Widget _deletePopupOverlay() {
    return GestureDetector(
      onTap: () {
        if (mounted) {
          setState(() => showDeletePopup = false);
        }
      },
      child: Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.black.withOpacity(0.55),
        child: Center(
          child: Container(
            width: 300,
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(22),
            ),
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _menuItem(Icons.delete_outline, "Delete only for you", () {
                  _deleteMessage(false);
                }, isDelete: true),
                if (selectedMine)
                  _menuItem(Icons.delete, "Delete for everyone", () {
                    _deleteMessage(true);
                  }, isDelete: true),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _menuItem(IconData icon, String text, VoidCallback onTap,
      {bool isDelete = false}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 18),
        child: Row(
          children: [
            Icon(icon, color: isDelete ? Colors.red : Colors.white, size: 20),
            const SizedBox(width: 14),
            Text(
              text,
              style: TextStyle(
                color: isDelete ? Colors.red : Colors.white,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bottomInputBar() {
    if (_isEitherBlocked) {
      return Container(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: MediaQuery.of(context).padding.bottom + 12,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(
            top: BorderSide(color: Colors.grey.shade200, width: 1),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.block, color: Colors.red.shade400, size: 18),
            const SizedBox(width: 8),
            Text(
              _isBlocked
                  ? 'You have blocked this user'
                  : 'This user has blocked you',
              style: TextStyle(
                color: Colors.red.shade400,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    // Chat request not yet accepted – block messaging and show a prompt.
    // 'unknown' means the status hasn't been fetched yet; allow input in that case
    // to avoid blocking users who legitimately opened a chat with an accepted request.
    final bool chatRequestNotAccepted =
        _chatRequestStatus != 'unknown' && _chatRequestStatus != 'accepted';
    if (chatRequestNotAccepted) {
      return Container(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: MediaQuery.of(context).padding.bottom + 12,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(
            top: BorderSide(color: Colors.grey.shade200, width: 1),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline, color: Colors.orange.shade600, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Send a chat request to start messaging',
                style: TextStyle(
                  color: Colors.orange.shade700,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProfileScreen(userId: widget.receiverId),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFE91E3E), Color(0xFFC2185B)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Send Request',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final hasText = isEditing
        ? _editController.text.trim().isNotEmpty
        : _hasText;

    return Listener(
      // Handles release-to-send for the hold-to-record gesture
      onPointerUp: (_) {
        if (_isHoldRecording && _isRecording) {
          _isHoldRecording = false;
          _stopAndSendRecording();
        }
      },
      onPointerCancel: (_) {
        if (_isHoldRecording && _isRecording) {
          _isHoldRecording = false;
          _cancelRecording();
        }
      },
      child: Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        border: Border(
          top: BorderSide(color: Colors.grey.shade200, width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isReplying) _buildReplyPreview(),
          if (isEditing) _buildEditPreview(),
          if (_isRecording) _buildRecordingBar() else Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isEditing)
                Padding(
                  padding: const EdgeInsets.only(right: 6, bottom: 4),
                  child: _isSendingImage
                      ? const SizedBox(
                          width: 40,
                          height: 40,
                          child: Padding(
                            padding: EdgeInsets.all(10),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(_accentColor),
                            ),
                          ),
                        )
                      : IconButton(
                          onPressed: _pickAndSendImages,
                          icon: const Icon(Icons.image_outlined, size: 24),
                          color: _accentColor,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                        ),
                ),
                Expanded(
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 48),
                    decoration: BoxDecoration(
                      color: _inputFieldBackground,
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(
                        color: Colors.grey.shade300,
                        width: 1,
                      ),
                    ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextField(
                          controller: isEditing
                              ? _editController
                              : _messageController,
                          focusNode: _messageFocusNode,
                          minLines: 1,
                          maxLines: 5,
                          keyboardType: TextInputType.multiline,
                          textInputAction: TextInputAction.newline,
                          style: const TextStyle(
                            fontSize: 15,
                            color: _textColor,
                            height: 1.4,
                          ),
                          decoration: InputDecoration(
                            hintText: isEditing
                                ? "Edit your message..."
                                : "Type a message...",
                            hintStyle: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 15,
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 0,
                              vertical: 12,
                            ),
                          ),
                          onChanged: (value) {
                            // Fire typing indicator only when composing (not editing)
                            if (!isEditing && value.isNotEmpty) {
                              _onTypingChanged();
                            } else if (!isEditing && value.isEmpty) {
                              _clearTyping();
                            }
                          },
                          onSubmitted: (_) => isEditing ? _editMessage() : _sendMessage(),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (!isEditing && !hasText)
                GestureDetector(
                  // Single tap: existing tap-to-record flow (shows recording bar)
                  onTap: _startRecording,
                  // Long press: WhatsApp-style hold-to-record (release to send)
                  onLongPressStart: (details) async {
                    HapticFeedback.lightImpact();
                    if (mounted) setState(() => _isHoldRecording = true);
                    await _startRecording();
                  },
                  child: Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      gradient: _primaryGradient,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: _accentColor.withOpacity(0.35),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.mic, color: Colors.white, size: 22),
                  ),
                )
              else
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    gradient: hasText ? _primaryGradient : null,
                    color: hasText ? null : _sendButtonDisabled,
                    shape: BoxShape.circle,
                    boxShadow: hasText
                        ? [
                            BoxShadow(
                              color: _accentColor.withOpacity(0.35),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ]
                        : [],
                  ),
                  child: IconButton(
                    onPressed: hasText ? (isEditing ? _editMessage : _sendMessage) : null,
                    icon: Icon(
                      isEditing ? Icons.check : Icons.send_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                    padding: const EdgeInsets.all(13),
                  ),
                ),
            ],
          ),
        ],
      ),
    ), // end Container
    ); // end Listener
  }

  Widget _bottomSection() => _bottomInputBar();

  Widget _buildRecordingBar() {
    if (_recordingAnimController == null) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_isHoldRecording)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.arrow_upward, size: 12, color: Colors.grey.shade500),
                const SizedBox(width: 4),
                Text(
                  'Slide up to cancel \u2022 Release to send',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade500,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        Row(
          children: [
            IconButton(
              onPressed: _cancelRecording,
              icon: const Icon(Icons.delete_outline, color: Colors.red, size: 24),
              tooltip: 'Cancel',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                height: 46,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: _accentColor.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: _accentColor.withOpacity(0.3), width: 1),
                ),
                child: Row(
                  children: [
                    // Pulsing red dot – opacity oscillates between 0.4 and 1.0
                    AnimatedBuilder(
                      animation: _recordingAnimController!,
                      builder: (context, _) {
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
                    // Timer text — rebuilds only on second tick via ValueNotifier
                    ValueListenableBuilder<int>(
                      valueListenable: _recordDurationNotifier,
                      builder: (context, secs, _) => Text(
                        _formatRecordDuration(secs),
                        style: const TextStyle(
                          color: _accentColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Animated waveform bars — AnimatedBuilder drives 60fps redraws
                    // and samples amplitude from the notifier on each frame. The
                    // notifier is read inside the builder so amplitude changes are
                    // picked up automatically without an extra ValueListenableBuilder
                    // wrapping (which would cause an extra 100ms rebuild on top of
                    // the 60fps animation ticks).
                    Expanded(
                      child: AnimatedBuilder(
                        animation: _recordingAnimController!,
                        builder: (context, _) {
                          final bool hasAudio = _audioAmplitudeNotifier.value > -40.0;
                          const barCount = 22;
                          const maxH = 20.0;
                          const minH = 4.0;
                          final t = _recordingAnimController!.value;
                          return Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: List.generate(barCount, (i) {
                              final phase = (i / barCount) * 2 * pi;
                              // Flat bars when no voice is detected, animated wave otherwise
                              final h = hasAudio
                                  ? minH + (maxH - minH) * (0.5 + 0.5 * sin(2 * pi * t + phase))
                                  : minH;
                              return Container(
                                width: 3,
                                height: h,
                                decoration: BoxDecoration(
                                  color: _accentColor.withOpacity(hasAudio ? 0.75 : 0.35),
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
            const SizedBox(width: 8),
            _isSendingVoice
                ? const SizedBox(
                    width: 46,
                    height: 46,
                    child: Padding(
                      padding: EdgeInsets.all(11),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(_accentColor),
                      ),
                    ),
                  )
                : GestureDetector(
                    onTap: _stopAndSendRecording,
                    child: Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        gradient: _primaryGradient,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: _accentColor.withOpacity(0.35),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.send_rounded, color: Colors.white, size: 22),
                    ),
                  ),
          ],
        ),
      ],
    );
  }

  Widget _buildMessagesList() {
    // Show skeleton on very first load before the stream delivers any data.
    if (_isFirstLoad) {
      return _buildSkeletonLoader();
    }

    if (_cachedMessages.isEmpty && _callHistory.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(Icons.chat_bubble_outline,
                  size: 42, color: _accentColor.withOpacity(0.7)),
            ),
            const SizedBox(height: 16),
            Text(
              'Start the conversation',
              style: TextStyle(
                color: _textColor,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Say hello and break the ice!',
              style: TextStyle(color: _lightTextColor, fontSize: 13),
            ),
          ],
        ),
      );
    }

    // Wrap the message list in Opacity so it stays invisible while the scroll
    // position is being set to the bottom on first load (like WhatsApp). The
    // ListView remains in the widget tree (scroll controller stays attached and
    // jumpTo works), but the user never sees the brief flash from top to bottom.
    return Opacity(
      opacity: _scrollLocked ? 0.0 : 1.0,
      child: _buildMessagesFromCache(),
    );
  }

  Future<void> _refreshMessages() async {
    try {
      final result = await _socketService.getMessages(
        widget.chatRoomId, page: 1, limit: _messagesPerPage,
      );
      if (!mounted) return;
      final messages = List<Map<String, dynamic>>.from(
        (result['messages'] as List? ?? []).map((m) => Map<String, dynamic>.from(m as Map)),
      );
      setState(() {
        _cachedMessages = messages;
        _hasMoreMessages = result['hasMore'] == true;
        _currentMessagePage = 1;
        _messagesCacheVersion++;
      });
      _scrollToBottom(jump: true);
      _saveMessagesToLocalCache();
    } catch (e) {
      debugPrint('Error refreshing messages: $e');
    }
  }

  Future<void> _loadMoreMessages() async {
    if (_isLoadingMore || !_hasMoreMessages) return;
    setState(() => _isLoadingMore = true);

    final double scrollExtentBefore = _scrollController.hasClients
        ? _scrollController.position.maxScrollExtent : 0.0;
    final double currentPixels = _scrollController.hasClients
        ? _scrollController.position.pixels : 0.0;

    try {
      final nextPage = _currentMessagePage + 1;
      final result = await _socketService.getMessages(
        widget.chatRoomId, page: nextPage, limit: _messagesPerPage,
      );
      if (!mounted) return;

      final newMessages = List<Map<String, dynamic>>.from(
        (result['messages'] as List? ?? []).map((m) => Map<String, dynamic>.from(m as Map)),
      );

      if (newMessages.isEmpty) {
        setState(() { _hasMoreMessages = false; _isLoadingMore = false; });
        return;
      }

      setState(() {
        _cachedMessages.insertAll(0, newMessages);
        _hasMoreMessages = result['hasMore'] == true;
        _currentMessagePage = nextPage;
        _isLoadingMore = false;
        _messagesCacheVersion++;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          final double scrollExtentAfter = _scrollController.position.maxScrollExtent;
          _scrollController.jumpTo(currentPixels + (scrollExtentAfter - scrollExtentBefore));
        }
      });
    } catch (e) {
      debugPrint('Error loading more messages: $e');
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  Widget _buildSkeletonLoader() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
      itemCount: 8,
      itemBuilder: (context, index) {
        final isLeft = index % 2 == 0;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Row(
            mainAxisAlignment:
                isLeft ? MainAxisAlignment.start : MainAxisAlignment.end,
            children: [
              Container(
                constraints: BoxConstraints(maxWidth: 280),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ShimmerBox(
                      width: 150 + (index * 20.0) % 80,
                      height: 12,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    const SizedBox(height: 6),
                    _ShimmerBox(
                      width: 100,
                      height: 12,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
  Widget _buildMessagesFromCache() {
    // Reuse cached widget list when nothing relevant has changed.
    // Audio playback state (position/duration/isPlaying) is handled via ValueNotifier
    // + ValueListenableBuilder inside each voice bubble, so position ticks no longer
    // invalidate the cache or trigger a full rebuild of the message list.
    final canUseCache = _cachedMessageWidgets != null &&
        _lastBuiltVersion == _messagesCacheVersion &&
        _lastBuiltHighlightId == _highlightedMessageId &&
        _lastBuiltIsLoadingMore == _isLoadingMore &&
        _lastBuiltIsBlockedByReceiver == _isBlockedByReceiver;

    // IMPORTANT: always return the SAME widget-type hierarchy (RefreshIndicator > ListView)
    // regardless of whether we use the cache or not. Changing the widget type at the same
    // tree position causes Flutter to unmount/remount the ListView, which resets the scroll
    // position and causes the visible "shaking" on every incoming/sent message.
    if (canUseCache) {
      return RefreshIndicator(
        onRefresh: _refreshMessages,
        child: ListView(
          controller: _scrollController,
          physics: _isHorizontalDragging
              ? const NeverScrollableScrollPhysics()
              : const ClampingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
          children: _cachedMessageWidgets!,
        ),
      );
    }

    final List<Widget> messageWidgets = [];

    // Add loading indicator at the top if loading more
    if (_isLoadingMore) {
      messageWidgets.add(
        Padding(
          padding: EdgeInsets.all(16.0),
          child: Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(_accentColor),
              ),
            ),
          ),
        ),
      );
    }

    // Show a prominent banner when the other user has blocked this user
    if (_isBlockedByReceiver) {
      messageWidgets.add(
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            border: Border.all(color: Colors.red.shade200),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(Icons.block, color: Colors.red.shade400, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${widget.receiverName} has blocked you. You cannot send messages or make calls.',
                  style: TextStyle(
                    color: Colors.red.shade700,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Group messages by date
    final Map<String, List<Map<String, dynamic>>> groupedMessages = {};

    for (final data in _cachedMessages) {
      final isDeletedForSender = data['isDeletedForSender'] ?? false;
      final isDeletedForReceiver = data['isDeletedForReceiver'] ?? false;
      final isDeletedForEveryone = data['deletedForEveryone'] == true;
      final isMine = data['senderId'] == widget.currentUserId;
      // "Delete for me only" — hide from the relevant user
      final isDeletedForMeOnly = !isDeletedForEveryone &&
          (isMine ? isDeletedForSender : isDeletedForReceiver);
      if (isDeletedForMeOnly) continue;

      final rawTs = data['timestamp'];
      if (rawTs == null) continue;
      final timestamp = rawTs is DateTime
          ? rawTs.toLocal()
          : rawTs is String
              ? DateTime.tryParse(rawTs)?.toLocal()
              : null;
      if (timestamp == null) continue;
      final dateKey = _formatDateForGrouping(timestamp);

      groupedMessages.putIfAbsent(dateKey, () => []);
      groupedMessages[dateKey]!.add(data);
    }

    // Sort date keys in chronological order (oldest first)
    final sortedDateKeys = _sortDateKeysChronologically(groupedMessages.keys.toList());

    // Build widgets for each date group
    for (final dateKey in sortedDateKeys) {
      final messagesForDate = groupedMessages[dateKey]!;

      // Sort messages within each date group by timestamp (oldest first)
      messagesForDate.sort((a, b) {
        final rawA = a['timestamp'];
        final rawB = b['timestamp'];
        if (rawA == null || rawB == null) return 0;
        final timeA = rawA is DateTime
            ? rawA.toLocal()
            : rawA is String
                ? (DateTime.tryParse(rawA)?.toLocal() ?? DateTime.now())
                : DateTime.now();
        final timeB = rawB is DateTime
            ? rawB.toLocal()
            : rawB is String
                ? (DateTime.tryParse(rawB)?.toLocal() ?? DateTime.now())
                : DateTime.now();
        return timeA.compareTo(timeB);
      });

      // Add date separator/label
      messageWidgets.add(_dateSeparator(dateKey));

      // Add all messages for this date
      for (final data in messagesForDate) {
        final rawTs = data['timestamp'];
        final timestamp = rawTs is DateTime
            ? rawTs.toLocal()
            : rawTs is String
                ? (DateTime.tryParse(rawTs)?.toLocal() ?? DateTime.now())
                : DateTime.now();

        if ((data['messageType'] ?? 'text') == 'call') {
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
          messageWidgets.add(_buildInlineCallBubble(
            callType: callPayload['callType']?.toString() ?? data['callType']?.toString() ?? 'audio',
            callStatus: callPayload['callStatus']?.toString() ?? data['callStatus']?.toString() ?? 'missed',
            duration: (callPayload['duration'] as num?)?.toInt() ?? data['duration']?.toInt() ?? 0,
            callerId: callPayload['callerId']?.toString() ?? data['callerId']?.toString() ?? data['senderId']?.toString() ?? '',
            timestamp: timestamp,
          ));
        } else {
          final isMine = data['senderId'] == widget.currentUserId;
          final isDeletedForEveryone = data['deletedForEveryone'] == true;
          final isUnsent = data['isUnsent'] == true;

          messageWidgets.add(_messageBubble(
            isMine: isMine,
            text: data['message'],
            timestamp: timestamp,
            messageType: data['messageType'] ?? 'text',
            isRead: data['isRead'] ?? false,
            isDelivered: data['isDelivered'] ?? false,
            duration: data['duration']?.toInt(),
            messageData: data,
            repliedTo: data['repliedTo'],
            isEdited: data['isEdited'] ?? false,
            isDeleted: isDeletedForEveryone || isUnsent,
          ));
        }
      }
    }

    // Cache for next rebuild
    _cachedMessageWidgets = messageWidgets;
    _lastBuiltVersion = _messagesCacheVersion;
    _lastBuiltHighlightId = _highlightedMessageId;
    _lastBuiltIsLoadingMore = _isLoadingMore;
    _lastBuiltIsBlockedByReceiver = _isBlockedByReceiver;

    return RefreshIndicator(
      onRefresh: _refreshMessages,
      child: ListView(
        controller: _scrollController,
        // Use ClampingScrollPhysics to prevent bounce effect that causes shaking
        physics: _isHorizontalDragging
            ? const NeverScrollableScrollPhysics()
            : const ClampingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
        children: messageWidgets,
      ),
    );
  }

  Widget _buildInlineCallBubble({
    required String callType,
    required String callStatus,
    required int duration,
    required String callerId,
    required DateTime timestamp,
  }) {
    final isVideo = callType == 'video';
    final isOutgoing = callerId == widget.currentUserId;
    final callLabel = isVideo ? 'Video' : 'Voice';

    // Resolve display properties per status + direction
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
          // Caller side: recipient never answered
          iconColor = Colors.amber[700]!;
          directionIcon = isVideo ? Icons.videocam_off : Icons.call_missed_outgoing;
          label = 'No Answer';
          subtitle = isVideo ? 'They didn\'t pick up the video call' : 'They didn\'t pick up';
          bubbleColor = Colors.amber.withOpacity(0.06);
          borderColor = Colors.amber.withOpacity(0.35);
        } else {
          // Receiver side: missed their call
          iconColor = Colors.red;
          directionIcon = isVideo ? Icons.videocam_off : Icons.call_missed;
          label = 'Missed $callLabel Call';
          bubbleColor = Colors.red.withOpacity(0.06);
          borderColor = Colors.red.withOpacity(0.3);
        }
        break;

      case 'declined':
        if (isOutgoing) {
          // Caller side: recipient rejected the call
          iconColor = Colors.red[600]!;
          directionIcon = isVideo ? Icons.videocam_off : Icons.call_end;
          label = '$callLabel Call Declined';
          subtitle = 'Declined by recipient';
          bubbleColor = Colors.red.withOpacity(0.06);
          borderColor = Colors.red.withOpacity(0.3);
        } else {
          // Receiver side: they chose to decline
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
          // Caller side: they cancelled before recipient answered
          iconColor = Colors.grey[600]!;
          directionIcon = isVideo ? Icons.videocam_off : Icons.call_end;
          label = 'Call Cancelled';
          subtitle = 'You cancelled before connecting';
          bubbleColor = Colors.grey.withOpacity(0.06);
          borderColor = Colors.grey.withOpacity(0.25);
        } else {
          // Receiver side: caller hung up before they could answer
          iconColor = Colors.orange[700]!;
          directionIcon = isVideo ? Icons.videocam_off : Icons.call_missed;
          label = 'Missed $callLabel Call';
          subtitle = 'Caller cancelled';
          bubbleColor = Colors.orange.withOpacity(0.06);
          borderColor = Colors.orange.withOpacity(0.3);
        }
        break;

      case 'busy':
        // Busy is always logged from the caller's perspective
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
        // Unknown status — safe fallback
        iconColor = Colors.grey[500]!;
        directionIcon = isVideo ? Icons.videocam_off : Icons.phone_missed;
        label = '$callLabel Call';
        bubbleColor = Colors.grey.withOpacity(0.05);
        borderColor = Colors.grey.withOpacity(0.2);
    }

    final timeStr = _formatTime(timestamp);

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

  Widget _buildCallHistorySection() {
    return Container(
      margin: const EdgeInsets.only(bottom: 20, top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with toggle button
          GestureDetector(
            onTap: () {
              setState(() {
                _showCallHistory = !_showCallHistory;
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                gradient: _primaryGradient,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: _accentColor.withOpacity(0.30),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Icon(Icons.history, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Call History',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.25),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_callHistory.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    _showCallHistory
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: Colors.white,
                  ),
                ],
              ),
            ),
          ),
          // Call history list
          if (_showCallHistory) ...[
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                gradient: _secondaryGradient,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: _callHistory.take(10).map((call) {
                  return _buildCallHistoryItem(call);
                }).toList(),
              ),
            ),
            if (_callHistory.length > 10)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Center(
                  child: Text(
                    '... and ${_callHistory.length - 10} more calls',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildCallHistoryItem(CallHistory call) {
    final isIncoming = call.isIncoming(widget.currentUserId);

    // Status icon based on call type and direction
    IconData statusIcon;
    Color statusColor;

    if (call.status == CallStatus.missed && isIncoming) {
      statusIcon = Icons.call_missed;
      statusColor = Colors.red;
    } else if (call.status == CallStatus.declined) {
      statusIcon = Icons.call_end;
      statusColor = Colors.red;
    } else if (call.status == CallStatus.cancelled) {
      statusIcon = Icons.call_missed_outgoing;
      statusColor = Colors.orange;
    } else if (isIncoming) {
      statusIcon = Icons.call_received;
      statusColor = Colors.green;
    } else {
      statusIcon = Icons.call_made;
      statusColor = Colors.green;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey[200]!, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          // Call type icon
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              call.callType == CallType.video ? Icons.videocam : Icons.call,
              color: statusColor,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          // Call details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(statusIcon, size: 14, color: statusColor),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        isIncoming ? 'Incoming Call' : 'Outgoing Call',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey[700],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  _formatCallDateTime(call.startTime),
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          // Duration or status
          if (call.status == CallStatus.completed)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                call.getFormattedDuration(),
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.green,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                call.getStatusText(widget.currentUserId),
                style: TextStyle(
                  fontSize: 11,
                  color: statusColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _formatCallDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays == 0) {
      return 'Today ${DateFormat('HH:mm').format(dateTime)}';
    } else if (difference.inDays == 1) {
      return 'Yesterday ${DateFormat('HH:mm').format(dateTime)}';
    } else if (difference.inDays < 7) {
      final dayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
      return '${dayNames[dateTime.weekday % 7]} ${DateFormat('HH:mm').format(dateTime)}';
    } else {
      return DateFormat('yyyy/MM/dd HH:mm').format(dateTime);
    }
  }

// Helper method to sort date keys chronologically with Today at the bottom
  List<String> _sortDateKeysChronologically(List<String> dateKeys) {
    final uniqueKeys = dateKeys.toSet().toList();

    uniqueKeys.sort((a, b) {
      // Convert date strings to DateTime for comparison
      DateTime? dateA, dateB;

      if (a == 'Today') {
        dateA = DateTime.now();
      } else if (a == 'Yesterday') {
        dateA = DateTime.now().subtract(const Duration(days: 1));
      } else {
        try {
          dateA = DateFormat('MMM dd, yyyy').parse(a);
        } catch (e) {
          dateA = DateTime.now();
        }
      }

      if (b == 'Today') {
        dateB = DateTime.now();
      } else if (b == 'Yesterday') {
        dateB = DateTime.now().subtract(const Duration(days: 1));
      } else {
        try {
          dateB = DateFormat('MMM dd, yyyy').parse(b);
        } catch (e) {
          dateB = DateTime.now();
        }
      }

      // Sort chronologically (oldest first)
      return dateA.compareTo(dateB);
    });

    return uniqueKeys;
  }

// Format date for grouping
  String _formatDateForGrouping(DateTime date) {
    final localDate = date.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    final messageDate = DateTime(localDate.year, localDate.month, localDate.day);

    if (messageDate == today) {
      return 'Today';
    } else if (messageDate == yesterday) {
      return 'Yesterday';
    } else {
      return DateFormat('MMM dd, yyyy').format(localDate);
    }
  }

// Helper method to sort date keys in correct order: Today → Yesterday → Older dates


// Format date for grouping

// Enhanced date separator widget
  Widget _dateSeparator(String date) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            date,
            style: const TextStyle(
              color: Colors.grey,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

// Update scrollToBottom method for correct scroll direction




  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemStatusBarContrastEnforced: false,
      ),
      child: Scaffold(
        backgroundColor: _backgroundColor,
        body: Stack(
          children: [
            Column(
              children: [
                _buildHeader(context),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [_backgroundColor, _backgroundColor.withOpacity(0.92)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                    child: _buildMessagesList(),
                  ),
                ),
                if (_isReceiverTyping)
                  Align(
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
                  ),
                _bottomSection(),
              ],
            ),

            if (showActionOverlay) _fullScreenActionOverlay(),
            if (showDeletePopup) _deletePopupOverlay(),
          ],
        ),
      ),
    );
  }

  /// Returns all image URLs exchanged in this chat (both sender and receiver).
  List<_SharedPhoto> _getSharedPhotos() {
    final List<_SharedPhoto> photos = [];
    for (final msg in _cachedMessages) {
      final type = msg['messageType']?.toString() ?? 'text';
      if (type != 'image' && type != 'image_gallery') continue;

      final text = msg['message']?.toString() ?? '';
      final senderId = msg['senderId']?.toString();
      final bool isFromReceiver = senderId != null && senderId != widget.currentUserId;

      if (type == 'image' && text.isNotEmpty) {
        photos.add(_SharedPhoto(
          url: resolveApiImageUrl(text),
          isFromReceiver: isFromReceiver,
        ));
      } else if (type == 'image_gallery') {
        try {
          final decoded = jsonDecode(text);
          if (decoded is List) {
            for (final u in decoded) {
              if (u is String && u.isNotEmpty) {
                photos.add(_SharedPhoto(
                  url: resolveApiImageUrl(u),
                  isFromReceiver: isFromReceiver,
                ));
              }
            }
          }
        } catch (_) {}
      }
    }
    return photos;
  }

  /// Shows a mini-profile bottom sheet for the person we are chatting with.
  void _showChatUserProfileSheet(BuildContext context) {
    final String resolvedImage = resolveApiImageUrl(widget.receiverImage);
    final List<_SharedPhoto> sharedPhotos = _getSharedPhotos();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ChatUserProfileSheet(
        receiverId: widget.receiverId,
        receiverName: widget.receiverName,
        receiverImage: resolvedImage,
        receiverPrivacy: widget.receiverPrivacy,
        receiverPhotoRequest: widget.receiverPhotoRequest,
        isOnline: _isOtherUserOnline,
        lastSeen: _otherUserLastSeen,
        sharedPhotos: sharedPhotos,
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final String resolvedReceiverImage =
        resolveApiImageUrl(widget.receiverImage);
    return Container(
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 8, left: 6, right: 6, bottom: 12),
      decoration: BoxDecoration(
        gradient: _primaryGradient,
        boxShadow: [
          BoxShadow(
            color: _accentColor.withOpacity(0.25),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 26),
          ),
          GestureDetector(
            onTap: () => _showChatUserProfileSheet(context),
            child: PrivacyUtils.buildPrivacyAwareAvatar(
              imageUrl: resolvedReceiverImage,
              privacy: widget.receiverPrivacy,
              photoRequest: widget.receiverPhotoRequest,
              radius: 22,
              backgroundColor: Colors.grey[600],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onTap: () => _showChatUserProfileSheet(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          widget.receiverName,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 17),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'MS-${widget.receiverId}',
                        style: const TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.w500,
                            fontSize: 13),
                      ),
                    ],
                  ),
                  Text(
                    _isBlockedByReceiver
                        ? '—'
                        : _isOtherUserOnline
                            ? 'online'
                            : (_otherUserLastSeen != null
                                ? _formatLastSeen(_otherUserLastSeen!)
                                : 'Offline'),
                    style: TextStyle(
                      color: _isOtherUserOnline && !_isBlockedByReceiver
                          ? Colors.white70
                          : Colors.white60,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!kIsWeb)
            IconButton(
              onPressed: (_isEitherBlocked) ? null : () async {
                // Enforce gated access for audio calls
                final canAccess = await AccessControl.canAccessFeature(
                  context,
                  FeatureType.audioCall,
                  hasAcceptedRequest: true, // Chat is already open, so chat request is accepted
                );

                if (!canAccess) {
                  // Dialog was already shown by AccessControl
                  return;
                }

                // Prevent starting a new call if one is already active
                if (CallOverlayManager().isCallActive) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('You are already in a call'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                  return;
                }
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    settings: const RouteSettings(name: activeCallRouteName),
                    builder: (context) => CallScreen(
                      currentUserId: widget.currentUserId,
                      currentUserName: widget.currentUserName,
                      currentUserImage: widget.currentUserImage,
                      otherUserId: widget.receiverId,
                      otherUserName: widget.receiverName,
                      otherUserImage: widget.receiverImage,
                      chatRoomId: widget.chatRoomId,
                    ),
                  ),
                );
              },
              icon: Icon(Icons.call,
                  color: (_isEitherBlocked) ? Colors.white38 : Colors.white),
            ),
          if (!kIsWeb)
            IconButton(
              onPressed: (_isEitherBlocked) ? null : () async {
                // Enforce gated access for video calls
                final canAccess = await AccessControl.canAccessFeature(
                  context,
                  FeatureType.videoCall,
                  hasAcceptedRequest: true, // Chat is already open, so chat request is accepted
                );

                if (!canAccess) {
                  // Dialog was already shown by AccessControl
                  return;
                }

                // Prevent starting a new call if one is already active
                if (CallOverlayManager().isCallActive) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('You are already in a call'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                  return;
                }
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    settings: const RouteSettings(name: activeCallRouteName),
                    builder: (context) => VideoCallScreen(
                      currentUserId: widget.currentUserId,
                      currentUserName: widget.currentUserName,
                      currentUserImage: widget.currentUserImage,
                      otherUserId: widget.receiverId,
                      otherUserName: widget.receiverName,
                      otherUserImage: widget.receiverImage,
                      chatRoomId: widget.chatRoomId,
                    ),
                  ),
                );
              },
              icon: Icon(Icons.videocam,
                  color: (_isEitherBlocked) ? Colors.white38 : Colors.white),
            ),
          PopupMenuButton<String>(
            onSelected: (String result) {
              if (result == 'block') {
                _showBlockProfileDialog(context);
              } else if (result == 'report') {
                _showReportDialog(context);
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'block',
                child: Row(
                  children: [
                    Icon(
                      _isBlocked ? Icons.check_circle : Icons.block,
                      color: _isBlocked ? Colors.green : Colors.red,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(_isBlocked ? 'Unblock Profile' : 'Block Profile'),
                  ],
                ),
              ),
              const PopupMenuItem<String>(
                value: 'report',
                child: Row(
                  children: [
                    Icon(Icons.flag, color: Colors.orange, size: 20),
                    SizedBox(width: 8),
                    Text('Report'),
                  ],
                ),
              ),
            ],
            icon: const Icon(Icons.more_vert, color: Colors.white),
          ),
        ],
      ),
    );
  }

  void _showReportDialog(BuildContext context) {
    String? selectedReason;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext sheetContext) {
        return StatefulBuilder(
          builder: (_, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Icon(Icons.flag, color: Colors.orange, size: 24),
                        SizedBox(width: 8),
                        Text(
                          'Report Profile',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      'Select reason for report:',
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...AppConstants.reportReasons.map((reason) => RadioListTile<String>(
                        value: reason,
                        groupValue: selectedReason,
                        onChanged: (value) =>
                            setSheetState(() => selectedReason = value),
                        title: Text(reason,
                            style: const TextStyle(fontSize: 14)),
                        activeColor: Colors.red,
                        dense: true,
                      )),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () =>
                                Navigator.of(sheetContext).pop(),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: selectedReason == null
                                ? null
                                : () async {
                                    Navigator.of(sheetContext).pop();
                                    await _submitReport(
                                        context, selectedReason!);
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                            ),
                            child: const Text(
                              'Report',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _submitReport(BuildContext context, String reason) async {
    try {
      final adminUserId = AppConstants.adminUserId;
      final reportMessage =
          'I have reported this profile.\n\nReason: $reason\n\nReported Profile ID: ${widget.receiverId}';
      final reportPayload = jsonEncode({
        'reportMessage': reportMessage,
        'reportedUserId': widget.receiverId,
        'reportedUserName': widget.receiverName,
        'reportReason': reason,
      });

      final List<String> ids = [widget.currentUserId, adminUserId]..sort();
      final adminChatRoomId = ids.join('_');
      _socketService.sendMessage(
        chatRoomId: adminChatRoomId,
        senderId: widget.currentUserId,
        receiverId: adminUserId,
        message: reportPayload,
        messageType: 'report',
        messageId: _uuid.v4(),
        user1Name: widget.currentUserName,
        user2Name: 'Admin',
        user1Image: widget.currentUserImage,
        user2Image: '',
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile reported successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to report: $e')),
        );
      }
    }
  }


  void _showBlockProfileDialog(BuildContext context) async {
    if (_isBlocked) {
      // Show unblock confirmation
      showDialog<void>(
        context: context,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            title: const Text('Unblock Profile'),
            content: const Text('Are you sure you want to unblock this profile? They will be able to contact you again.'),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('CANCEL'),
              ),
              TextButton(
                onPressed: () => _unblockUser(dialogContext),
                child: Text(
                  'UNBLOCK',
                  style: TextStyle(color: Theme.of(context).primaryColor),
                ),
              ),
            ],
          );
        },
      );
    } else {
      // Show block confirmation
      showDialog<void>(
        context: context,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            title: const Text('Block Profile'),
            content: const Text('Are you sure you want to block this profile? They will not be able to contact you or see your profile.'),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('CANCEL'),
              ),
              TextButton(
                onPressed: () => _blockUser(dialogContext),
                child: Text(
                  'BLOCK',
                  style: TextStyle(color: Theme.of(context).primaryColor),
                ),
              ),
            ],
          );
        },
      );
    }
  }

  Future<void> _blockUser(BuildContext dialogContext) async {
    setState(() {
      _isLoadingBlock = true;
    });

    Navigator.of(dialogContext).pop(); // Close dialog

    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataString = prefs.getString('user_data');
      final userData = jsonDecode(userDataString!);
      final myId = userData["id"].toString();

      final service = ProfileService();
      final result = await service.blockUser(
        myId: myId,
        userId: widget.receiverId,
      );

      if (mounted) {
        if (result['status'] == 'success') {
          setState(() {
            _isBlocked = true;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Profile blocked successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message'] ?? 'Failed to block user'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingBlock = false;
        });
      }
    }
  }

  Future<void> _unblockUser(BuildContext dialogContext) async {
    setState(() {
      _isLoadingBlock = true;
    });

    Navigator.of(dialogContext).pop(); // Close dialog

    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataString = prefs.getString('user_data');
      final userData = jsonDecode(userDataString!);
      final myId = userData["id"].toString();

      final service = ProfileService();
      final result = await service.unblockUser(
        myId: myId,
        userId: widget.receiverId,
      );

      if (mounted) {
        if (result['status'] == 'success') {
          setState(() {
            _isBlocked = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Profile unblocked successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message'] ?? 'Failed to unblock user'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingBlock = false;
        });
      }
    }
  }

}

// ---------------------------------------------------------------------------
// Swipe-to-reply wrapper
// Encapsulates all swipe state so that per-frame offset updates only rebuild
// this single widget, not the entire chat screen.
// ---------------------------------------------------------------------------
class _SwipeToReplyWrapper extends StatefulWidget {
  const _SwipeToReplyWrapper({
    required this.child,
    required this.isMine,
    required this.onReply,
    this.onDragStart,
    this.onDragEnd,
  });

  final Widget child;
  final bool isMine;
  final VoidCallback onReply;
  final VoidCallback? onDragStart;
  final VoidCallback? onDragEnd;

  @override
  State<_SwipeToReplyWrapper> createState() => _SwipeToReplyWrapperState();
}

class _SwipeToReplyWrapperState extends State<_SwipeToReplyWrapper>
    with SingleTickerProviderStateMixin {
  double _dragOffset = 0.0;
  bool _isDragging = false;
  late final AnimationController _animCtrl;
  late final Animation<double> _anim;

  static const double _kThreshold = 60.0;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _anim = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  void _onDragStart(DragStartDetails _) {
    _isDragging = true;
    _dragOffset = 0.0;
    _animCtrl.forward();
    widget.onDragStart?.call();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!_isDragging) return;
    final newOffset = _dragOffset + details.delta.dx;
    // Own messages swipe left; others' messages swipe right
    if (widget.isMine && newOffset > 0) return;
    if (!widget.isMine && newOffset < 0) return;
    setState(() {
      _dragOffset = newOffset.clamp(-100.0, 100.0);
    });
  }

  void _onDragEnd(DragEndDetails _) {
    if (!_isDragging) return;
    _isDragging = false;
    if (_dragOffset.abs() >= _kThreshold) {
      HapticFeedback.lightImpact();
      widget.onReply();
    }
    _animCtrl.reverse().then((_) {
      if (mounted) setState(() => _dragOffset = 0.0);
    });
    widget.onDragEnd?.call();
  }

  @override
  Widget build(BuildContext context) {
    final double offset = _dragOffset;
    return GestureDetector(
      onHorizontalDragStart: _onDragStart,
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      child: Stack(
        children: [
          AnimatedBuilder(
            animation: _anim,
            builder: (_, __) => Transform.translate(
              offset: Offset(offset * _anim.value, 0),
              child: widget.child,
            ),
          ),
          if (offset.abs() > 8)
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _anim,
                builder: (_, __) {
                  final opacity =
                      (offset.abs() / 100.0).clamp(0.0, 1.0) * _anim.value;
                  return Row(
                    mainAxisAlignment: widget.isMine
                        ? MainAxisAlignment.start
                        : MainAxisAlignment.end,
                    children: [
                      if (widget.isMine)
                        Padding(
                          padding: const EdgeInsets.only(left: 20),
                          child: Icon(Icons.reply,
                              color: Colors.grey.withOpacity(opacity)),
                        ),
                      if (!widget.isMine)
                        Padding(
                          padding: const EdgeInsets.only(right: 20),
                          child: Icon(Icons.reply,
                              color: Colors.grey.withOpacity(opacity)),
                        ),
                    ],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _ShimmerBox extends StatefulWidget {
  const _ShimmerBox({
    required this.width,
    required this.height,
    required this.borderRadius,
  });

  final double width;
  final double height;
  final BorderRadius borderRadius;

  @override
  State<_ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<_ShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (rect) {
            final slide = _controller.value;
            return LinearGradient(
              begin: Alignment(-1.0 - 2 * slide, 0),
              end: Alignment(1.0 + 2 * slide, 0),
              colors: const [
                Color(0xFFE5E7EB),
                Color(0xFFF8FAFC),
                Color(0xFFE5E7EB),
              ],
              stops: const [0.2, 0.5, 0.8],
            ).createShader(rect);
          },
          child: Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              color: const Color(0xFFE5E7EB),
              borderRadius: widget.borderRadius,
            ),
          ),
        );
      },
    );
  }
}

class _SharedPhoto {
  final String url;
  final bool isFromReceiver;

  const _SharedPhoto({
    required this.url,
    required this.isFromReceiver,
  });
}

// ─── Mini-profile bottom sheet shown when tapping avatar / name in chat ───────

class _ChatUserProfileSheet extends StatelessWidget {
  final String receiverId;
  final String receiverName;
  final String receiverImage;
  final String? receiverPrivacy;
  final String? receiverPhotoRequest;
  final bool isOnline;
  final DateTime? lastSeen;
  final List<_SharedPhoto> sharedPhotos;

  const _ChatUserProfileSheet({
    required this.receiverId,
    required this.receiverName,
    required this.receiverImage,
    this.receiverPrivacy,
    this.receiverPhotoRequest,
    required this.isOnline,
    this.lastSeen,
    required this.sharedPhotos,
  });

  void _openPhotoViewer(BuildContext context, int index) {
    if (sharedPhotos.isEmpty) return;
    showDialog(
      context: context,
      builder: (ctx) => _GalleryViewerDialog(
        urls: sharedPhotos.map((p) => p.url).toList(),
        initialIndex: index,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool canShowPhotos = PrivacyUtils.shouldShowClearImage(
      privacy: receiverPrivacy,
      photoRequest: receiverPhotoRequest,
    );

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Avatar + name + status
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  PrivacyUtils.buildPrivacyAwareAvatar(
                    imageUrl: receiverImage,
                    privacy: receiverPrivacy,
                    photoRequest: receiverPhotoRequest,
                    radius: 32,
                    backgroundColor: Colors.grey[300],
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          receiverName,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isOnline ? Colors.green : Colors.grey,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              isOnline
                                  ? 'Online'
                                  : (lastSeen != null
                                      ? 'Last seen ${_formatLastSeen(lastSeen!)}'
                                      : 'Offline'),
                              style: TextStyle(
                                fontSize: 13,
                                color: isOnline ? Colors.green : Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Shared photos section
            if (sharedPhotos.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Shared Photos',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    GestureDetector(
                      onTap: () => _openPhotoViewer(context, 0),
                      child: const Text(
                        'View All',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.red,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 90,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: sharedPhotos.length > 8
                      ? 8
                      : sharedPhotos.length,
                  itemBuilder: (ctx, i) {
                    final isLastVisible = i == 7 &&
                        sharedPhotos.length > 8;
                    final photo = sharedPhotos[i];
                    final shouldBlur = photo.isFromReceiver && !canShowPhotos;
                    return GestureDetector(
                      onTap: () => _openPhotoViewer(context, i),
                      child: Container(
                        width: 80,
                        height: 80,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          color: Colors.grey[200],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              shouldBlur
                                  ? Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        CachedNetworkImage(
                                          imageUrl: photo.url,
                                          fit: BoxFit.cover,
                                        ),
                                        BackdropFilter(
                                          filter: ui.ImageFilter.blur(
                                              sigmaX: 8, sigmaY: 8),
                                          child: Container(
                                            color:
                                                Colors.black.withOpacity(0.3),
                                          ),
                                        ),
                                        const Center(
                                          child: Icon(Icons.lock_outline,
                                              color: Colors.white, size: 24),
                                        ),
                                      ],
                                    )
                                  : CachedNetworkImage(
                                      imageUrl: photo.url,
                                      fit: BoxFit.cover,
                                      errorWidget: (_, __, ___) => const Icon(
                                        Icons.photo,
                                        color: Colors.grey,
                                        size: 30,
                                      ),
                                    ),
                              if (isLastVisible)
                                Container(
                                  color: Colors.black54,
                                  child: Center(
                                    child: Text(
                                      '+${sharedPhotos.length - 7}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              const Divider(height: 1),
            ],
            // View Profile button
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            ProfileScreen(userId: receiverId),
                      ),
                    );
                  },
                  icon: const Icon(Icons.person_outline),
                  label: const Text('View Profile'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatLastSeen(DateTime lastSeen) {
    final diff = DateTime.now().difference(lastSeen);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

/// Full-screen gallery viewer dialog (swipe through multiple images).
class _GalleryViewerDialog extends StatefulWidget {
  final List<String> urls;
  final int initialIndex;

  const _GalleryViewerDialog({required this.urls, required this.initialIndex});

  @override
  State<_GalleryViewerDialog> createState() => _GalleryViewerDialogState();
}

class _GalleryViewerDialogState extends State<_GalleryViewerDialog> {
  late final PageController _pageController;
  late int _current;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: EdgeInsets.zero,
      child: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: widget.urls.length,
            onPageChanged: (i) => setState(() => _current = i),
            itemBuilder: (ctx, i) => InteractiveViewer(
              child: Center(
                child: CachedNetworkImage(
                  imageUrl: widget.urls[i],
                  fit: BoxFit.contain,
                  errorWidget: (_, __, ___) => const Icon(
                    Icons.broken_image,
                    color: Colors.white54,
                    size: 64,
                  ),
                ),
              ),
            ),
          ),
          // Close button
          Positioned(
            top: 40,
            right: 16,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          // Page indicator
          if (widget.urls.length > 1)
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(widget.urls.length, (i) => Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: _current == i ? 10 : 6,
                  height: _current == i ? 10 : 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _current == i ? Colors.white : Colors.white38,
                  ),
                )),
              ),
            ),
        ],
      ),
    );
  }
}
