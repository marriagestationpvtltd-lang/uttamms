// ignore_for_file: unnecessary_library_name
// lib/screens/ChatDetailScreen.dart

library chatdetails_screen;

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ms2026/service/auth_http_client.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:ms2026/Chat/screen_state_manager.dart';
import 'package:ms2026/config/app_endpoints.dart';
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
import '../service/sound_settings_service.dart';
import '../service/audio_manager.dart';
import '../utils/access_control.dart';
import '../Calling/videocall.dart';
import '../Calling/OutgoingCall.dart';
import '../Calling/call_history_model.dart';
import '../Calling/call_history_service.dart';
import '../Calling/callmanager.dart';
import '../Calling/incommingcall.dart';
import '../Calling/incomingvideocall.dart';
import '../otherenew/othernew.dart';
import '../ReUsable/shared_profile_card.dart';
import '../otherenew/service.dart';
import '../pushnotification/pushservice.dart';
import 'call_overlay_manager.dart';
import '../constant/constant.dart';
import '../utils/time_utils.dart';
import '../utils/image_utils.dart';
import '../utils/image_compression.dart';
import '../utils/privacy_utils.dart';
import 'widgets/typing_indicator.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../core/user_state.dart';
import '../Package/PackageScreen.dart';
part 'ChatdetailsScreen_profile_actions.dart';
part 'chatdetailsscreen_format_helpers.dart';
part 'chatdetailsscreen_typing_audio_helpers.dart';
part 'chatdetailsscreen_presence_helpers.dart';
part 'chatdetailsscreen_typing_state_helpers.dart';
part 'chatdetailsscreen_scroll_helpers.dart';
part 'chatdetailsscreen_reply_scroll_helpers.dart';
part 'chatdetailsscreen_call_listener_helpers.dart';
part 'chatdetailsscreen_message_actions_helpers.dart';
part 'chatdetailsscreen_status_fetch_helpers.dart';
part 'chatdetailsscreen_message_stream_helpers.dart';
part 'chatdetailsscreen_recording_helpers.dart';
part 'chatdetailsscreen_profile_media_helpers.dart';
part 'chatdetailsscreen_message_list_helpers.dart';
part 'chatdetailsscreen_profile_moderation_helpers.dart';
part 'chatdetailsscreen_profile_shared_photos.dart';
part 'chatdetailsscreen_audio_playback_state.dart';
part 'chatdetailsscreen_profile_sheet_widgets.dart';
part 'chatdetailsscreen_interaction_widgets.dart';
part 'chatdetailsscreen_composer_overlay_widgets.dart';
part 'chatdetailsscreen_message_bubble_widgets.dart';
part 'chatdetailsscreen_compose_preview_widgets.dart';
part 'chatdetailsscreen_state_helpers.dart';
part 'chatdetailsscreen_send_media_helpers.dart';

/// Full chat screen  -  always operates in the "chat" view context.
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
  bool _isHoldRecording =
      false; // true when mic is being held (press-and-hold mode)
  bool _isRecordingLocked = false; // locked/hands-free after tap or slide-up
  double _recordSwipeDx = 0.0; // horizontal drag offset for swipe-to-cancel
  bool _isSendingVoice = false;
  bool _isSendingImage = false;
  // ValueNotifiers so the recording bar updates without rebuilding all messages.
  final ValueNotifier<int> _recordDurationNotifier = ValueNotifier(0);
  Timer? _recordTimer;
  AnimationController? _recordingAnimController;
  final ValueNotifier<double> _audioAmplitudeNotifier =
      ValueNotifier(-160.0); // dBFS
  StreamSubscription? _amplitudeSubscription;

  bool get _isAdminConversation =>
      widget.currentUserId.trim() == '1' || widget.receiverId.trim() == '1';

  // Scroll lock during swipe-to-reply
  bool _isHorizontalDragging = false;

  // Scroll lock during message loading to prevent screen shaking
  bool _scrollLocked = true;
  bool _initialScrollDone = false;

  // Track if user is actively scrolling to debounce message updates
  bool _isUserScrolling = false;
  Timer? _scrollIdleTimer;

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
  // Pagination cursor  -  only updated on first load and during loadMore (never on stream updates)
  int _currentMessagePage = 1;

  // Call history variables
  List<CallHistory> _callHistory = [];
  StreamSubscription? _callHistorySubscription;

  // Backup incoming call listener (mirrors AdminChatScreen logic)
  StreamSubscription<Map<String, dynamic>>? _callListenerSubscription;

  // Messages stream subscription (replaces StreamBuilder to prevent rebuild-on-setState)
  StreamSubscription? _messagesSubscription;
  StreamSubscription? _messageEditedSubscription;
  StreamSubscription? _messageDeletedSubscription;
  StreamSubscription? _messageUnsentSubscription;
  StreamSubscription? _messageBlockedSubscription;
  StreamSubscription? _messageReactionSubscription;

  // Incoming-message debounce: buffer rapid socket events and flush them in a
  // single setState to avoid one rebuild per message when multiple arrive together.
  final List<Map<String, dynamic>> _pendingIncomingMessages = [];
  Timer? _incomingMessageDebounce;

  // Typing indicator
  Timer? _typingDebounce;
  Timer? _typingRepeatTimer; // Repeating click while remote user is typing
  Timer? _voiceRecordingDebounce;
  bool _isTyping = false;
  bool _isReceiverTyping = false;
  bool _isReceiverVoiceRecording = false;
  StreamSubscription? _typingSubscription;
  StreamSubscription? _typingStopSubscription;
  StreamSubscription? _voiceRecordingStartSubscription;
  StreamSubscription? _voiceRecordingStopSubscription;
  bool _isMarkingMessagesAsRead = false;
  final bool _isReceiverViewingThisChat = false;

  // Receiver online status
  bool _isOtherUserOnline = false;
  DateTime? _otherUserLastSeen;
  StreamSubscription? _otherUserStatusSub;
  StreamSubscription? _audioPlayerStateSubscription;
  StreamSubscription? _audioPlayerPositionSubscription;
  StreamSubscription? _audioPlayerDurationSubscription;
  StreamSubscription<bool>? _socketConnectionSubscription;
  Timer? _socketHealthTimer;
  Timer? _socketBannerAutoHideTimer;
  Timer? _pendingOutgoingRetryTimer;
  bool _isSocketRealtimeHealthy = true;
  bool _showSocketReconnectBanner = false;
  bool _socketReconnectInFlight = false;
  bool _pendingOutgoingRetryInFlight = false;

  // Track whether the next scroll-to-bottom should be forced (own message sent)
  bool _forceScrollToBottom = false;

  // Chat session duration tracking
  DateTime? _chatStartTime;

  // Scroll-to-reply + highlight
  final Map<String, GlobalKey> _messageKeys = {};
  String? _highlightedMessageId;

  // Delivered status (hover for web)
  String? _hoveredMessageId;

  // Block / photo-privacy state
  bool _isBlocked = false; // I have blocked the other user
  bool _isBlockedByReceiver = false; // The other user has blocked me
  String _photoRequestStatus = 'not_sent';
  String _chatRequestStatus =
      'unknown'; // 'unknown' | 'accepted' | 'pending' | 'rejected' | 'not_sent'

  bool get _isEitherBlocked => _isBlocked || _isBlockedByReceiver;

  // Timing constants
  static const int _kTypingTimeoutSeconds = 5;
  static const int _kVoiceRecordingTimeoutSeconds = 8;
  static const Duration _kTypingDebounceDelay = Duration(seconds: 3);
  static const Duration _kHighlightDuration = Duration(milliseconds: 700);
  static const Duration _kScrollToMessageDelay = Duration(milliseconds: 400);

  // Image display constants
  // Static const removed - use getters instead

  // Accessors for static theme colors/gradients for use in part file extensions
  Color get accentColor => const Color(0xFFE91E3E);
  Color get receivedBubbleColor => const Color(0xFFFFFFFF);
  Color get receivedBubbleBorder => const Color(0xFFEEEEEE);
  Color get textColor => const Color(0xFF1A1A2E);
  Color get lightTextColor => const Color(0xFF757575);
  Color get backgroundColor => const Color(0xFFF0F2F5);
  LinearGradient get primaryGradient => const LinearGradient(
        colors: [Color(0xFFE91E3E), Color(0xFFC2185B)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
  LinearGradient get secondaryGradient => const LinearGradient(
        colors: [Color(0xFFFCE4EC), Color(0xFFFFF8F9)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      );
  double get kImageWidthFraction => 0.65;
  double get kImageAspectRatio => 0.75;
  double get kImageMinWidth => 120.0;
  double get kImageMaxHeight => 300.0;

  // Aliases for underscore-prefixed access from part files
  Color get _accentColor => accentColor;
  Color get _receivedBubbleColor => receivedBubbleColor;
  Color get _receivedBubbleBorder => receivedBubbleBorder;
  Color get _backgroundColor => backgroundColor;
  Color get _textColor => textColor;
  Color get _lightTextColor => lightTextColor;
  LinearGradient get _primaryGradient => primaryGradient;
  LinearGradient get _secondaryGradient => secondaryGradient;
  double get _kImageWidthFraction => kImageWidthFraction;
  double get _kImageAspectRatio => kImageAspectRatio;
  double get _kImageMinWidth => kImageMinWidth;
  double get _kImageMaxHeight => kImageMaxHeight;

  @override
  void initState() {
    super.initState();
    _chatStartTime = DateTime.now();
    myImage = widget.currentUserImage;
    otherUserImage = widget.receiverImage;

    _recordingAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    // Load cached messages synchronously from the pre-warmed singleton so the
    // screen shows content immediately on the first frame  -  no skeleton flash.
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

    // Audio player listeners  -  update the combined ValueNotifier directly to
    // avoid setState on every position tick, which would bypass the message-widget
    // cache and rebuild the entire message list hundreds of times per second.
    _audioPlayerStateSubscription =
        _audioPlayer.onPlayerStateChanged.listen((state) {
      final playing = state == PlayerState.playing;
      if (state == PlayerState.completed) {
        _audioStateNotifier.value = const _AudioPlaybackState();
      } else {
        _audioStateNotifier.value =
            _audioStateNotifier.value.copyWith(isPlaying: playing);
      }
    });
    _audioPlayerPositionSubscription =
        _audioPlayer.onPositionChanged.listen((pos) {
      _audioStateNotifier.value =
          _audioStateNotifier.value.copyWith(position: pos);
    });
    _audioPlayerDurationSubscription =
        _audioPlayer.onDurationChanged.listen((dur) {
      _audioStateNotifier.value =
          _audioStateNotifier.value.copyWith(duration: dur);
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
    _setupSocketHealthMonitoring();
    _startPendingOutgoingRetryLoop();
  }

  void _startPendingOutgoingRetryLoop() {
    _pendingOutgoingRetryTimer?.cancel();
    _pendingOutgoingRetryTimer =
        Timer.periodic(const Duration(seconds: 8), (_) {
      _retryPendingOutgoingMessages();
    });
  }

  Future<void> _retrySinglePendingOutgoingMessage(String messageId) async {
    if (_pendingOutgoingRetryInFlight || !mounted) return;

    final idx = _cachedMessages.indexWhere(
      (m) => m['messageId']?.toString() == messageId,
    );
    if (idx < 0) return;

    final msg = Map<String, dynamic>.from(_cachedMessages[idx]);
    final isMine = msg['senderId']?.toString() == widget.currentUserId;
    final isPending = msg['isPendingSend'] == true;
    if (!isMine || !isPending) return;

    _pendingOutgoingRetryInFlight = true;
    try {
      final type = (msg['messageType']?.toString() ?? 'text').toLowerCase();
      if (type != 'text' && mounted) {
        setState(() {
          _cachedMessages[idx] = {
            ..._cachedMessages[idx],
            'isUploading': true,
          };
          _messagesCacheVersion++;
        });
      }

      final payloadMessage = await _prepareRetryMessagePayload(msg);
      if (payloadMessage == null || payloadMessage.isEmpty) return;

      await _sendMessageViaHttp(
        chatRoomId: widget.chatRoomId,
        senderId: widget.currentUserId,
        receiverId: widget.receiverId,
        message: payloadMessage,
        messageType: msg['messageType']?.toString() ?? 'text',
        messageId: messageId,
        repliedTo: msg['repliedTo'] is Map
            ? Map<String, dynamic>.from(msg['repliedTo'] as Map)
            : null,
      );

      final freshIdx = _cachedMessages.indexWhere(
        (m) => m['messageId']?.toString() == messageId,
      );
      if (freshIdx >= 0 && mounted) {
        setState(() {
          _cachedMessages[freshIdx] = {
            ..._cachedMessages[freshIdx],
            'isPendingSend': false,
            'isUploading': false,
            'message': payloadMessage,
          };
          _messagesCacheVersion++;
        });
      }
      _saveMessagesToLocalCache();
    } catch (_) {
      final freshIdx = _cachedMessages.indexWhere(
        (m) => m['messageId']?.toString() == messageId,
      );
      if (freshIdx >= 0 && mounted) {
        setState(() {
          _cachedMessages[freshIdx] = {
            ..._cachedMessages[freshIdx],
            'isUploading': false,
          };
          _messagesCacheVersion++;
        });
      }
    } finally {
      _pendingOutgoingRetryInFlight = false;
    }
  }

  Future<void> _retryPendingOutgoingMessages() async {
    if (_pendingOutgoingRetryInFlight || !mounted) return;

    final pending = _cachedMessages.where((m) {
      final isMine = m['senderId']?.toString() == widget.currentUserId;
      final isPending = m['isPendingSend'] == true;
      final type = (m['messageType']?.toString() ?? 'text').toLowerCase();
      return isMine &&
          isPending &&
          (type == 'text' ||
              type == 'image' ||
              type == 'image_gallery' ||
              type == 'voice');
    }).toList();

    if (pending.isEmpty) return;

    _pendingOutgoingRetryInFlight = true;
    try {
      for (final msg in pending) {
        final messageId = msg['messageId']?.toString() ?? '';
        if (messageId.isEmpty) continue;

        try {
          final type = (msg['messageType']?.toString() ?? 'text').toLowerCase();
          if (type != 'text') {
            final idx = _cachedMessages.indexWhere(
              (m) => m['messageId']?.toString() == messageId,
            );
            if (idx >= 0 && mounted) {
              setState(() {
                _cachedMessages[idx] = {
                  ..._cachedMessages[idx],
                  'isUploading': true,
                };
                _messagesCacheVersion++;
              });
            }
          }

          final payloadMessage =
              await _prepareRetryMessagePayload(Map<String, dynamic>.from(msg));
          if (payloadMessage == null || payloadMessage.isEmpty) {
            continue;
          }

          await _sendMessageViaHttp(
            chatRoomId: widget.chatRoomId,
            senderId: widget.currentUserId,
            receiverId: widget.receiverId,
            message: payloadMessage,
            messageType: msg['messageType']?.toString() ?? 'text',
            messageId: messageId,
            repliedTo: msg['repliedTo'] is Map
                ? Map<String, dynamic>.from(msg['repliedTo'] as Map)
                : null,
          );

          if (!mounted) return;
          final idx = _cachedMessages.indexWhere(
            (m) => m['messageId']?.toString() == messageId,
          );
          if (idx >= 0) {
            setState(() {
              _cachedMessages[idx] = {
                ..._cachedMessages[idx],
                'isPendingSend': false,
                'isUploading': false,
                'message': payloadMessage,
              };
              _messagesCacheVersion++;
            });
          }
        } catch (_) {
          final idx = _cachedMessages.indexWhere(
            (m) => m['messageId']?.toString() == messageId,
          );
          if (idx >= 0 && mounted) {
            setState(() {
              _cachedMessages[idx] = {
                ..._cachedMessages[idx],
                'isUploading': false,
              };
              _messagesCacheVersion++;
            });
          }
          // Keep pending and retry in next cycle.
        }
      }
      _saveMessagesToLocalCache();
    } finally {
      _pendingOutgoingRetryInFlight = false;
    }
  }

  Future<String?> _prepareRetryMessagePayload(Map<String, dynamic> msg) async {
    final type = (msg['messageType']?.toString() ?? 'text').toLowerCase();
    final currentMessage = msg['message']?.toString() ?? '';

    if (type == 'text') {
      return currentMessage;
    }

    if (type == 'image') {
      if (currentMessage.startsWith('http://') ||
          currentMessage.startsWith('https://')) {
        return currentMessage;
      }

      final retryPaths = _extractRetryLocalPaths(msg);
      if (retryPaths.isEmpty) return null;

      final xfile = XFile(retryPaths.first);
      final compressed = await ImageCompressionUtils.compressImageForSending(
        xfile,
      );
      final uploadedUrl = await _socketService.uploadChatImage(
        bytes: compressed,
        filename: _extractRetryFileNames(msg).firstOrNull ?? xfile.name,
        userId: widget.currentUserId,
        chatRoomId: widget.chatRoomId,
      );
      return uploadedUrl;
    }

    if (type == 'image_gallery') {
      try {
        final decoded = jsonDecode(currentMessage);
        if (decoded is List &&
            decoded.isNotEmpty &&
            decoded.every((e) =>
                e is String &&
                (e.startsWith('http://') || e.startsWith('https://')))) {
          return currentMessage;
        }
      } catch (_) {
        // Keep trying with local retry paths below.
      }

      final retryPaths = _extractRetryLocalPaths(msg);
      if (retryPaths.isEmpty) return null;
      final retryNames = _extractRetryFileNames(msg);

      final uploaded = <String>[];
      for (var i = 0; i < retryPaths.length; i++) {
        final xfile = XFile(retryPaths[i]);
        final compressed = await ImageCompressionUtils.compressImageForSending(
          xfile,
        );
        final uploadedUrl = await _socketService.uploadChatImage(
          bytes: compressed,
          filename: i < retryNames.length ? retryNames[i] : xfile.name,
          userId: widget.currentUserId,
          chatRoomId: widget.chatRoomId,
        );
        uploaded.add(uploadedUrl);
      }

      if (uploaded.isEmpty) return null;
      return jsonEncode(uploaded);
    }

    if (type == 'voice') {
      if (currentMessage.startsWith('http://') ||
          currentMessage.startsWith('https://')) {
        return currentMessage;
      }
      final retryPath = msg['retryLocalPath']?.toString() ?? '';
      if (retryPath.isEmpty) return null;

      late Uint8List bytes;
      if (kIsWeb) {
        bytes = await XFile(retryPath).readAsBytes();
      } else {
        bytes = await File(retryPath).readAsBytes();
      }

      final uploadedUrl = await _socketService.uploadVoiceMessage(
        bytes: bytes,
        filename: 'voice_${DateTime.now().millisecondsSinceEpoch}.mp3',
        userId: widget.currentUserId,
        chatRoomId: widget.chatRoomId,
      );
      return uploadedUrl;
    }

    return currentMessage;
  }

  List<String> _extractRetryLocalPaths(Map<String, dynamic> msg) {
    final raw = msg['retryLocalPaths'];
    if (raw is List) {
      return raw
          .map((e) => e?.toString() ?? '')
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return const [];
  }

  List<String> _extractRetryFileNames(Map<String, dynamic> msg) {
    final raw = msg['retryFileNames'];
    if (raw is List) {
      return raw
          .map((e) => e?.toString() ?? '')
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return const [];
  }

  void _setupSocketHealthMonitoring() {
    // Reflect live socket connectivity in UI and trigger silent reconnects.
    _socketConnectionSubscription?.cancel();
    _socketConnectionSubscription =
        _socketService.onConnectionChange.listen((connected) {
      if (!mounted) return;
      if (connected) {
        _socketReconnectInFlight = false;
        _retryPendingOutgoingMessages();
        _socketBannerAutoHideTimer?.cancel();
        setState(() {
          _isSocketRealtimeHealthy = true;
          _showSocketReconnectBanner = true;
        });
        _socketBannerAutoHideTimer = Timer(const Duration(seconds: 2), () {
          if (!mounted) return;
          setState(() => _showSocketReconnectBanner = false);
        });
      } else {
        setState(() {
          _isSocketRealtimeHealthy = false;
          _showSocketReconnectBanner = true;
        });
        _triggerSocketReconnect();
      }
    });

    // Periodic health check in case disconnect events are missed.
    _socketHealthTimer?.cancel();
    _socketHealthTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      if (!mounted) return;
      if (!_socketService.isConnected) {
        if (_isSocketRealtimeHealthy || !_showSocketReconnectBanner) {
          setState(() {
            _isSocketRealtimeHealthy = false;
            _showSocketReconnectBanner = true;
          });
        }
        _triggerSocketReconnect();
      }
    });

    // Initialize banner state from current connectivity.
    _isSocketRealtimeHealthy = _socketService.isConnected;
    _showSocketReconnectBanner = !_isSocketRealtimeHealthy;
    if (!_isSocketRealtimeHealthy) {
      _triggerSocketReconnect();
    }
  }

  Future<void> _triggerSocketReconnect() async {
    if (_socketReconnectInFlight) return;
    _socketReconnectInFlight = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('bearer_token');
      _socketService.connect(widget.currentUserId, token: token);
      _socketService.joinRoom(widget.chatRoomId);
      _socketService.setActiveChat(widget.currentUserId, widget.chatRoomId);
    } catch (e) {
      debugPrint('Socket reconnect attempt failed: $e');
    } finally {
      // Allow another attempt after a short cooldown.
      Future.delayed(const Duration(seconds: 3), () {
        _socketReconnectInFlight = false;
      });
    }
  }

  void _listenToMessages() {
    _socketService.joinRoom(widget.chatRoomId);

    // Load initial page via Socket.IO request-response
    _socketService
        .getMessages(widget.chatRoomId, page: 1, limit: _messagesPerPage)
        .then((result) {
      if (!mounted) return;
      final serverMessages = List<Map<String, dynamic>>.from(
        (result['messages'] as List? ?? [])
            .map((m) => Map<String, dynamic>.from(m as Map)),
      );
      final pendingLocal = _collectLocallyPendingMessages(_cachedMessages);
      final messages = _mergeServerAndPendingMessages(
        serverMessages: serverMessages,
        pendingLocalMessages: pendingLocal,
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
            _scrollController
                .jumpTo(_scrollController.position.maxScrollExtent);
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

    // Real-time new messages  -  debounced to batch rapid consecutive socket events
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
      _incomingMessageDebounce =
          Timer(const Duration(milliseconds: 100), _flushPendingMessages);
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
            'message': data['newMessage'],
            'isEdited': true,
            'editedAt': data['editedAt'],
          };
          _messagesCacheVersion++;
        });
        _saveMessagesToLocalCache();
      }
    });

    _messageDeletedSubscription?.cancel();
    _messageDeletedSubscription =
        _socketService.onMessageDeleted.listen((data) {
      if (!mounted) return;
      if (data['chatRoomId']?.toString() != widget.chatRoomId) return;
      final msgId = data['messageId']?.toString();
      if (data['deleteForEveryone'] == true) {
        // Mark with a single flag  -  show "This message was deleted" placeholder for both parties
        final idx = _cachedMessages
            .indexWhere((m) => m['messageId']?.toString() == msgId);
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
        final idx = _cachedMessages
            .indexWhere((m) => m['messageId']?.toString() == msgId);
        if (idx >= 0) {
          final isMine = data['userId']?.toString() == widget.currentUserId;
          setState(() {
            _cachedMessages[idx] = {
              ..._cachedMessages[idx],
              if (isMine) 'isDeletedForSender': true,
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
      final idx = _cachedMessages
          .indexWhere((m) => m['messageId']?.toString() == msgId);
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

    _messageBlockedSubscription?.cancel();
    _messageBlockedSubscription =
        _socketService.onMessageBlocked.listen((data) {
      if (!mounted) return;
      if (data['chatRoomId']?.toString() != widget.chatRoomId) return;
      if (data['senderId']?.toString() != widget.currentUserId) return;

      final blockedMessageId = data['messageId']?.toString();
      if (blockedMessageId != null && blockedMessageId.isNotEmpty) {
        final idx = _cachedMessages.indexWhere(
          (m) => m['messageId']?.toString() == blockedMessageId,
        );
        if (idx >= 0) {
          setState(() {
            _cachedMessages.removeAt(idx);
            _messagesCacheVersion++;
          });
          _saveMessagesToLocalCache();
        }
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              (data['error'] ?? 'Messaging is blocked between these users')
                  .toString()),
          backgroundColor: Colors.red,
        ),
      );
    });

    _messageReactionSubscription?.cancel();
    _messageReactionSubscription =
        _socketService.onMessageReaction.listen((data) {
      if (!mounted) return;
      if (data['chatRoomId']?.toString() != widget.chatRoomId) return;
      final msgId = data['messageId']?.toString() ?? data['id']?.toString();
      final Map<String, dynamic> reactions = (data['reactions'] is Map)
          ? Map<String, dynamic>.from(data['reactions'] as Map)
          : {};
      final idx = _cachedMessages.indexWhere((m) {
        final localMessageId =
            m['messageId']?.toString() ?? m['id']?.toString();
        return localMessageId == msgId;
      });
      if (idx >= 0) {
        setState(() {
          _cachedMessages[idx] = {
            ..._cachedMessages[idx],
            'reactions': reactions
          };
          _messagesCacheVersion++;
        });
        _saveMessagesToLocalCache();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Keep global screen-state foreground/background flag accurate
    ScreenStateManager().updateAppLifecycleState(state);

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
        if (mounted) _markMessagesAsRead();
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

  // Mark all messages in this chat room as read and emit to socket server
  // so unread count is updated for the sender and all participants.
  Future<void> _markMessagesAsRead() async {
    if (_isMarkingMessagesAsRead) return;
    _isMarkingMessagesAsRead = true;
    try {
      // Emit mark_read event to socket server to update unread counts
      _socketService.markRead(widget.chatRoomId, widget.currentUserId);
    } finally {
      _isMarkingMessagesAsRead = false;
    }
  }

  @override
  void dispose() {
    _saveMessagesToLocalCache();

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
    _socketConnectionSubscription?.cancel();
    _socketHealthTimer?.cancel();
    _socketBannerAutoHideTimer?.cancel();
    _pendingOutgoingRetryTimer?.cancel();
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
    _voiceRecordingDebounce?.cancel();
    _typingSubscription?.cancel();
    _typingStopSubscription?.cancel();
    _voiceRecordingStartSubscription?.cancel();
    _voiceRecordingStopSubscription?.cancel();
    _scrollIdleTimer?.cancel();
    _incomingMessageDebounce?.cancel();
    _messageEditedSubscription?.cancel();
    _messageDeletedSubscription?.cancel();
    _messageUnsentSubscription?.cancel();
    _messageBlockedSubscription?.cancel();
    _messageReactionSubscription?.cancel();
    _otherUserStatusSub?.cancel();
    _callHistorySubscription?.cancel();
    _callListenerSubscription?.cancel();
    _messagesSubscription?.cancel();
    _socketService.leaveRoom(widget.chatRoomId);
    if (_isRecording) {
      _socketService.stopVoiceRecording(
          widget.chatRoomId, widget.currentUserId);
    }
    _clearTyping(); // Remove our typing entry on exit
    // Track chat session duration (fire-and-forget)
    final startTime = _chatStartTime;
    if (startTime != null) {
      final duration = DateTime.now().difference(startTime).inSeconds;
      if (duration > 0) {
        unawaited(http.post(
          Uri.parse('$kApiBaseUrl/Api2/track_behavior.php'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'userid': widget.currentUserId,
            'target_user_id': widget.receiverId,
            'action': 'chat_duration',
            'duration': duration,
          }),
        ));
      }
    }
    super.dispose();
  }
  // VOICE MESSAGE RECORDING moved to chatdetailsscreen_recording_helpers.dart

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
        body: _buildScreenBody(),
      ),
    );
  }

  void setBlockedFlag(bool value) {
    if (!mounted) return;
    setState(() {
      _isBlocked = value;
    });
  }
}
