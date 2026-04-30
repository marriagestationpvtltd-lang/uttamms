import 'package:adminmrz/adminchat/services/pushservice.dart';
import 'package:adminmrz/adminchat/services/admin_socket_service.dart';
import 'package:adminmrz/adminchat/services/callmanager.dart';
import 'package:adminmrz/adminchat/services/web_notification_service.dart';
import 'package:adminmrz/adminchat/video_call_page.dart';
import 'package:adminmrz/adminchat/group_call_screen.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'OutgoingCall.dart';
import 'audiocall.dart';
import 'chat_screen.dart';
import 'chatprovider.dart';
import 'chatscreen.dart';
import 'constant.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'dart:io';
import 'package:flutter/foundation.dart' show Uint8List, kIsWeb;
import 'chat_theme.dart';
import 'widgets/typing_indicator.dart';
import 'left.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:html' as html;
import 'dart:js' as js;
import 'dart:js_interop';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:adminmrz/config/app_endpoints.dart';
import 'package:adminmrz/users/userdetails/detailscreen.dart';
import 'package:adminmrz/users/userdetails/userdetailprovider.dart';
import 'package:adminmrz/users/userdetails/userdetailservice.dart';
import 'package:adminmrz/users/userprovider.dart';
import 'package:uuid/uuid.dart';
import 'package:adminmrz/utils/image_compression.dart';

class ChatWindow extends StatefulWidget {
  final String name;
  final bool isOnline;
  final dynamic receiverIdd;

  /// Called on mobile when the admin taps the back arrow to return to the list.
  final VoidCallback? onBack;

  const ChatWindow({
    super.key,
    required this.name,
    required this.isOnline,
    required this.receiverIdd,
    this.onBack,
  });

  @override
  State<ChatWindow> createState() => _ChatWindowState();
}

class _ChatWindowState extends State<ChatWindow> {
  final int senderId = 1;
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _messageFocusNode = FocusNode();

  // Socket.IO service for all chat messaging.
  final AdminSocketService _socketService = AdminSocketService();
  final CallManager _callManager = CallManager();
  StreamSubscription<Map<String, dynamic>>? _newMsgSub;
  StreamSubscription<Map<String, dynamic>>? _editedMsgSub;
  StreamSubscription<Map<String, dynamic>>? _deletedMsgSub;
  StreamSubscription<Map<String, dynamic>>? _unsentMsgSub;
  StreamSubscription<Map<String, dynamic>>? _likedMsgSub;
  StreamSubscription<Map<String, dynamic>>? _reactionMsgSub;
  StreamSubscription<Map<String, dynamic>>? _readMsgSub;
  StreamSubscription<Map<String, dynamic>>? _typingStartSub;
  StreamSubscription<Map<String, dynamic>>? _typingStopSub;
  StreamSubscription<Map<String, dynamic>>? _incomingCallSub;

  bool _isListening = false;
  bool _userStoppedListening = false;
  bool _isSearching = false;
  bool _showMatchInfo = false;
  bool _isHorizontalDragging = false;
  List<PlatformFile> _selectedImages = [];
  js.JsObject? _webSpeechRecognition;
  FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  final ScrollController _scrollController = ScrollController();
  String? _lastUploadedImageUrl;

  // Message list populated via Socket.IO.
  List<Map<String, dynamic>> _messages = [];
  List<Map<String, dynamic>> _filteredMessages = [];

  // Cached selected user — used to detect user switches.
  int? _cachedReceiverId;

  // Voice typing state
  String _selectedLanguage = 'en-US'; // 'en-US' or 'ne-NP'
  String _textBeforeVoice =
      ''; // text already in field before listening started

  // Pagination
  static const int _pageSize = 20;
  static const double _autoScrollThreshold = 120;
  static const int kIncomingCallTimeoutSeconds = 30;
  int _currentPage = 1;
  bool _isLoadingMore = false;
  bool _hasMoreMessages = true;
  bool _suppressNextAutoScroll = false;
  bool _isInitialLoad = true;
  int? _prevUserId;

  // Scroll lock during message loading to prevent screen shaking
  bool _scrollLocked = true;
  bool _initialScrollDone = false;

  // Cached ChatProvider reference — stored in initState so it can be
  // safely accessed from dispose() without risking a deactivated-ancestor error.
  ChatProvider? _chatProviderRef;

  // Floating date indicator (WhatsApp-style)
  final ValueNotifier<String?> _floatingDateNotifier = ValueNotifier(null);
  Timer? _floatingDateTimer;
  List<_ChatMessageDateGroup> _currentMessageGroups = [];

  // Match-related data
  Map<String, dynamic>? _matchDetails;
  bool _isLoadingMatchDetails = false;
  List<Map<String, dynamic>> _mutualMatches = [];

  // Active call overlay
  OverlayEntry? _callOverlayEntry;

  // Call-waiting banner overlay (shown when admin is already in a call)
  OverlayEntry? _callWaitingBannerEntry;

  // Typing indicator state
  Timer? _typingStopTimer;
  Timer? _typingTimer;
  bool _adminTypingActive = false;
  String? _activeTypingRoomId;
  bool _userIsTyping = false;
  DateTime? _lastTypingStart;

  // Inline reply / edit state
  Map<String, dynamic>?
  _replyingTo; // {messageId, message, senderid, senderName}
  String? _editingMessageId;
  String _editingOriginalText =
      ''; // original message text before user edits it

  // Voice message playback state
  final AudioPlayer _voiceAudioPlayer = AudioPlayer();
  final AudioPlayer _typingAudioPlayer = AudioPlayer();
  bool _typingSoundLoaded = false;
  String? _playingVoiceMessageId;
  bool _voiceIsPlaying = false;
  Duration _voicePlaybackPosition = Duration.zero;
  Duration _voicePlaybackDuration = Duration.zero;
  StreamSubscription? _voicePlayerStateSub;
  StreamSubscription? _voicePlayerPositionSub;
  StreamSubscription? _voicePlayerDurationSub;

  // Voice message recording state (web uses FlutterSoundRecorder)
  bool _isRecordingVoice = false;
  bool _isHoldRecordingVoice =
      false; // true when mic is held down (hold-to-record)
  bool _isSendingVoice = false;
  int _voiceRecordDuration = 0;
  Timer? _voiceRecordTimer;
  String? _voiceRecordingPath;

  static const int _kMaxQuoteLength =
      80; // max chars shown in reply/edit preview
  static const String _kDeletedMessageText = 'This message was deleted.';
  static const String _kUnsentMessageText = 'This message was unsent.';
  static const String _kDefaultMessageText = 'Message';
  static const String _kMaskedMessageText = '* * * * * * * * * *';
  // Approximate chat row height used for the initial jump before ensureVisible
  // performs the precise final alignment on the mounted target widget.
  static const double _kEstimatedMessageExtent = 112;
  static const double _kDateHeaderExtent = _ChatDateHeaderDelegate.kExtent;
  static const int _kMaxLoadAttempts = 20;
  static const int _kMaxContextFindAttempts = 6;
  static const Duration _kLoadRetryDelay = Duration(milliseconds: 250);
  static const Duration _kLoadMoreDelay = Duration(milliseconds: 450);
  static const Duration _kContextFindDelay = Duration(milliseconds: 80);
  static const Duration _kEnsureVisibleDuration = Duration(milliseconds: 420);
  static const Duration _kAdminTypingIdle = Duration(seconds: 3);
  static const int _kMinScrollDurationMs = 320;
  static const Duration _kTypingIdleDuration = Duration(seconds: 3);
  static const Duration _kTypingStartThrottle = Duration(milliseconds: 900);
  static const int _kMaxScrollDurationMs = 950;
  static const double _kScrollDurationMultiplier = 0.35;
  static const double _kMessageScrollAlignment = 0.45;
  static const double _kReplyPreviewSentBackgroundOpacity = 0.18;
  static const double _kReplyPreviewSentBorderOpacity = 0.78;
  static const double _kReplyPreviewSentTextOpacity = 0.85;
  static const double _kReplyPreviewSentIconOpacity = 0.88;

  final Map<String, GlobalKey> _messageKeys = <String, GlobalKey>{};
  final Map<String, int> _messageIndexMap = <String, int>{};
  Timer? _replyHighlightTimer;
  String? _highlightedMessageId;

  // Message long-press action overlay state (Facebook Messenger style)
  bool _showMsgActionOverlay = false;
  String? _overlayMessageId;
  Map<String, dynamic>? _overlayReplyPayload;
  bool _overlayIsSentByMe = false;
  bool _overlayCanEdit = false;
  bool _overlayCanMutate = false;
  Offset _overlayTapOffset = Offset.zero;

  @override
  void initState() {
    super.initState();
    _initializeWebSpeech();
    _initializeRecorder();
    // Cache provider reference before any async gap so dispose() can access it
    // safely without looking up a potentially deactivated widget ancestor.
    _chatProviderRef = Provider.of<ChatProvider>(context, listen: false);
    final chatProvider = _chatProviderRef!;
    if (chatProvider.id != null) {
      _fetchMatchDetails();
    }
    _scrollController.addListener(_onScrollForPagination);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusScope.of(context).requestFocus(_messageFocusNode);
      // Set up typing listener for the initially selected user.
      final cp = Provider.of<ChatProvider>(context, listen: false);
      if (cp.id != null) _setupTypingListener(cp.id!);
    });

    // Voice audio player listeners (just_audio)
    _voicePlayerStateSub = _voiceAudioPlayer.playerStateStream.listen((state) {
      if (mounted) {
        setState(() {
          _voiceIsPlaying = state.playing;
          if (state.processingState == ProcessingState.completed) {
            _playingVoiceMessageId = null;
            _voicePlaybackPosition = Duration.zero;
          }
        });
      }
    });
    _voicePlayerPositionSub = _voiceAudioPlayer.positionStream.listen((pos) {
      if (mounted) setState(() => _voicePlaybackPosition = pos);
    });
    _voicePlayerDurationSub = _voiceAudioPlayer.durationStream.listen((dur) {
      if (dur != null && mounted) setState(() => _voicePlaybackDuration = dur);
    });

    // Connect the Socket.IO service and start listening for events.
    _socketService.connect();
    _setupSocketListeners();

    // Handle any pending incoming call that was stored in CallManager before
    // this screen was mounted (e.g. the dashboard auto-navigated here because
    // a call arrived while the admin was on a different tab).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _callManager.hasActiveIncomingCall()) {
        final data = _callManager.currentCallData;
        if (data != null) _handleIncomingCallFromUser(data);
      }
    });

    // Load messages once the socket is ready (or immediately if already connected).
    if (_socketService.isConnected) {
      _loadMessages(reset: true);
    } else {
      StreamSubscription<bool>? connSub;
      connSub = _socketService.onConnectionChange.listen((connected) {
        if (connected && mounted) {
          connSub?.cancel();
          _loadMessages(reset: true);
        }
      });
    }
  }

  // ── SOCKET.IO HELPERS ────────────────────────────────────────────────────

  /// Convert a Socket.IO message map (camelCase fields from server) to the
  /// admin-panel-internal format (lowercase widget keys used by the
  /// rendering widgets).
  static Map<String, dynamic> _socketMsgToAdminData(Map<String, dynamic> msg) {
    final String msgType = msg['messageType']?.toString() ?? 'text';
    final String rawMessage = msg['message']?.toString() ?? '';
    // The API now provides a pre-decoded `images` array for image/image_gallery types.
    final List<dynamic>? apiImages = msg['images'] is List
        ? msg['images'] as List<dynamic>
        : null;

    // Decode optional structured payloads from the message field.
    String? imageUrl;
    Map<String, dynamic>? profileData;
    String? callType;
    String? callStatus;
    int callDuration = 0;
    String displayMessage = rawMessage;

    if (msgType == 'image') {
      // Use the URL from message, falling back to the first entry in images[].
      imageUrl = rawMessage.isNotEmpty
          ? rawMessage
          : (apiImages != null && apiImages.isNotEmpty
                ? apiImages.first?.toString()
                : null);
      displayMessage = 'Image';
    } else if (msgType == 'image_gallery') {
      // Prefer the `images` array from the API if available; otherwise keep
      // the raw JSON string so `_buildChatBubble` can decode it itself.
      if (apiImages != null && apiImages.isNotEmpty) {
        displayMessage = jsonEncode(apiImages.whereType<String>().toList());
      }
      // displayMessage stays as the raw JSON string if apiImages is absent.
    } else if (msgType == 'voice') {
      imageUrl = rawMessage; // reuse imageUrl field to carry voice URL
      displayMessage = '🎤 Voice message';
    } else if (msgType == 'profile_card') {
      try {
        profileData = jsonDecode(rawMessage) as Map<String, dynamic>;
        displayMessage = 'Match Profile';
      } catch (e) {
        debugPrint('Failed to parse profile_card JSON: $e');
        displayMessage = 'Match Profile';
      }
    } else if (msgType == 'call') {
      try {
        final decoded = jsonDecode(rawMessage) as Map<String, dynamic>;
        callType = decoded['callType']?.toString();
        callStatus = decoded['callStatus']?.toString();
        callDuration = (decoded['callDuration'] as num?)?.toInt() ?? 0;
        displayMessage = decoded['label']?.toString() ?? rawMessage;
      } catch (e) {
        debugPrint('Failed to parse call JSON: $e');
        displayMessage = 'Call';
      }
    }

    // Parse report payload
    Map<String, dynamic>? reportData;
    String effectiveMsgType = msgType;
    if (msgType == 'report') {
      try {
        final decoded = jsonDecode(rawMessage) as Map<String, dynamic>;
        reportData = decoded;
        displayMessage = '🚩 Profile Report';
      } catch (_) {
        displayMessage = '🚩 Profile Report';
      }
    } else if (msgType == 'text' || msgType.isEmpty) {
      // Fallback: detect report payloads that were stored with messageType='text'
      // (e.g. messages sent before 'report' was whitelisted on the server).
      try {
        final decoded = jsonDecode(rawMessage);
        if (decoded is Map &&
            (decoded.containsKey('reportedUserId') ||
                decoded.containsKey('reportReason') ||
                decoded.containsKey('reportMessage'))) {
          reportData = Map<String, dynamic>.from(decoded as Map);
          displayMessage = '🚩 Profile Report';
          effectiveMsgType = 'report';
        }
      } catch (_) {}
    }

    // Treat a message as deleted if it is deleted for both or either side
    // (admin sees all messages in the room).
    final bool deleted =
        msg['isDeletedForSender'] == true ||
        msg['isDeletedForReceiver'] == true;

    final repliedTo = _normalizeReplyPayload(msg['repliedTo']);

    return {
      'messageId': msg['messageId']?.toString() ?? '',
      'senderid': msg['senderId']?.toString() ?? '',
      'receiverid': msg['receiverId']?.toString() ?? '',
      'message': displayMessage,
      'type': effectiveMsgType,
      'liked': msg['liked'] == true,
      'reactions': (msg['reactions'] is Map)
          ? Map<String, dynamic>.from(msg['reactions'] as Map)
          : <String, dynamic>{},
      'seen': msg['isRead'] == true,
      'deleted': deleted,
      'unsent': msg['isUnsent'] == true,
      'edited': msg['isEdited'] == true,
      'replyto': repliedTo,
      'timestamp': msg['timestamp']?.toString(),
      if (imageUrl != null) 'imageUrl': imageUrl,
      if (callType != null) 'callType': callType,
      if (callStatus != null) 'callStatus': callStatus,
      'callDuration': callDuration,
      if (profileData != null) 'profileData': profileData,
      if (reportData != null) 'reportData': reportData,
    };
  }

  static Map<String, dynamic>? _normalizeReplyPayload(dynamic rawReplyTo) {
    if (rawReplyTo is! Map) return null;
    final replyTo = Map<String, dynamic>.from(rawReplyTo as Map);
    if (replyTo['messageId'] == null ||
        replyTo['messageId'].toString().isEmpty) {
      final legacyId = replyTo['docId']?.toString();
      if (legacyId != null && legacyId.isNotEmpty) {
        replyTo['messageId'] = legacyId;
      }
    }
    return replyTo;
  }

  String _replyTargetMessageId(Map<String, dynamic>? replyTo) {
    return _normalizeReplyPayload(replyTo)?['messageId']?.toString() ?? '';
  }

  /// Set up persistent Socket.IO event listeners.
  void _setupSocketListeners() {
    _newMsgSub?.cancel();
    _newMsgSub = _socketService.onNewMessage.listen((raw) {
      if (!mounted) return;
      final data = _socketMsgToAdminData(raw);
      final chatProvider = Provider.of<ChatProvider>(context, listen: false);
      final String expectedRoom = AdminSocketService.chatRoomId(
        chatProvider.id?.toString() ?? '',
      );
      if (raw['chatRoomId']?.toString() != expectedRoom) return;
      final msgId = data['messageId'] as String;
      if (msgId.isEmpty) return;
      setState(() {
        final idx = _messages.indexWhere((m) => m['messageId'] == msgId);
        if (idx >= 0) {
          _messages[idx] = data; // update optimistic message
        } else {
          _messages.add(data);
          if (_isSearching && _searchController.text.isNotEmpty) {
            if (data['message'].toString().toLowerCase().contains(
              _searchController.text.toLowerCase(),
            )) {
              _filteredMessages.add(data);
            }
          }
        }
      });
      _saveAdminMessagesToCache(expectedRoom);
      // Mark messages sent by user as seen by admin
      final bool isByUser = data['senderid'] != senderId.toString();
      if (isByUser)
        _socketService.markRead(raw['chatRoomId']?.toString() ?? expectedRoom);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_suppressNextAutoScroll && mounted) _scrollToBottom();
      });
    });

    _editedMsgSub?.cancel();
    _editedMsgSub = _socketService.onMessageEdited.listen((data) {
      if (!mounted) return;
      final String msgId = data['messageId']?.toString() ?? '';
      if (msgId.isEmpty) return;
      final chatProvider = Provider.of<ChatProvider>(context, listen: false);
      final String roomId = AdminSocketService.chatRoomId(
        chatProvider.id?.toString() ?? '',
      );
      setState(() {
        final idx = _messages.indexWhere((m) => m['messageId'] == msgId);
        if (idx >= 0) {
          _messages[idx] = {
            ..._messages[idx],
            'message':
                data['newMessage']?.toString() ?? _messages[idx]['message'],
            'edited': true,
          };
          _syncFilteredMessages();
        }
      });
      _saveAdminMessagesToCache(roomId);
    });

    _deletedMsgSub?.cancel();
    _deletedMsgSub = _socketService.onMessageDeleted.listen((data) {
      if (!mounted) return;
      final String msgId = data['messageId']?.toString() ?? '';
      if (msgId.isEmpty) return;
      final chatProvider = Provider.of<ChatProvider>(context, listen: false);
      final String roomId = AdminSocketService.chatRoomId(
        chatProvider.id?.toString() ?? '',
      );
      setState(() {
        final idx = _messages.indexWhere((m) => m['messageId'] == msgId);
        if (idx >= 0) {
          _messages[idx] = {
            ..._messages[idx],
            'message': _kDeletedMessageText,
            'deleted': true,
            'unsent': false,
            'edited': false,
          };
          _syncFilteredMessages();
        }
      });
      _saveAdminMessagesToCache(roomId);
    });

    _unsentMsgSub?.cancel();
    _unsentMsgSub = _socketService.onMessageUnsent.listen((data) {
      if (!mounted) return;
      final String msgId = data['messageId']?.toString() ?? '';
      if (msgId.isEmpty) return;
      final chatProvider = Provider.of<ChatProvider>(context, listen: false);
      final String roomId = AdminSocketService.chatRoomId(
        chatProvider.id?.toString() ?? '',
      );
      setState(() {
        final idx = _messages.indexWhere((m) => m['messageId'] == msgId);
        if (idx >= 0) {
          _messages[idx] = {
            ..._messages[idx],
            'message': _kUnsentMessageText,
            'unsent': true,
            'deleted': false,
            'edited': false,
          };
          _syncFilteredMessages();
        }
      });
      _saveAdminMessagesToCache(roomId);
    });

    _likedMsgSub?.cancel();
    _likedMsgSub = _socketService.onMessageLiked.listen((data) {
      if (!mounted) return;
      final String msgId = data['messageId']?.toString() ?? '';
      if (msgId.isEmpty) return;
      setState(() {
        final idx = _messages.indexWhere((m) => m['messageId'] == msgId);
        if (idx >= 0) {
          _messages[idx] = {..._messages[idx], 'liked': data['liked'] == true};
        }
      });
    });

    _reactionMsgSub?.cancel();
    _reactionMsgSub = _socketService.onMessageReaction.listen((data) {
      if (!mounted) return;
      final String msgId = data['messageId']?.toString() ?? '';
      if (msgId.isEmpty) return;
      final Map<String, dynamic> reactions = (data['reactions'] is Map)
          ? Map<String, dynamic>.from(data['reactions'] as Map)
          : {};
      setState(() {
        final idx = _messages.indexWhere((m) => m['messageId'] == msgId);
        if (idx >= 0) {
          _messages[idx] = {..._messages[idx], 'reactions': reactions};
        }
      });
    });

    _readMsgSub?.cancel();
    _readMsgSub = _socketService.onMessagesRead.listen((data) {
      if (!mounted) return;
      // When the user marks messages as read, update seen status on all admin-sent messages
      setState(() {
        for (int i = 0; i < _messages.length; i++) {
          if (_messages[i]['senderid'] == senderId.toString()) {
            _messages[i] = {..._messages[i], 'seen': true};
          }
        }
      });
    });

    _typingStartSub?.cancel();
    _typingStartSub = _socketService.onTypingStart.listen((data) {
      if (!mounted) return;
      final chatProvider = Provider.of<ChatProvider>(context, listen: false);
      final expectedRoom = AdminSocketService.chatRoomId(
        chatProvider.id?.toString() ?? '',
      );
      if (data['chatRoomId']?.toString() != expectedRoom) return;
      if (data['userId']?.toString() == senderId.toString()) return;
      if (_userIsTyping) return;
      _playTypingSound();
      setState(() => _userIsTyping = true);
    });

    _typingStopSub?.cancel();
    _typingStopSub = _socketService.onTypingStop.listen((data) {
      if (!mounted) return;
      final chatProvider = Provider.of<ChatProvider>(context, listen: false);
      final expectedRoom = AdminSocketService.chatRoomId(
        chatProvider.id?.toString() ?? '',
      );
      if (data['chatRoomId']?.toString() != expectedRoom) return;
      if (data['userId']?.toString() == senderId.toString()) return;
      if (!_userIsTyping) return;
      setState(() => _userIsTyping = false);
    });

    _incomingCallSub?.cancel();
    _incomingCallSub = _socketService.onIncomingCall.listen((data) {
      if (!mounted) return;
      _handleIncomingCallFromUser(data);
    });
  }

  /// Fetch basic caller details (usertype, package status, member ID) from
  /// cached UserProvider data and, in parallel, from the profile API.
  /// Returns a map with keys: usertype, paymentStatus, memberId.
  Future<Map<String, String?>> _fetchCallerDetails(String callerId) async {
    final callerIdInt = int.tryParse(callerId);
    String? usertype;
    String? paymentStatus;
    String? memberId;
    String? occupation;

    // 1. Quick lookup in already-loaded UserProvider cache (no API call).
    if (callerIdInt != null) {
      try {
        final userProvider = Provider.of<UserProvider>(context, listen: false);
        final cachedUser = userProvider.getUserById(callerIdInt);
        if (cachedUser != null) {
          usertype = cachedUser.usertype;
          paymentStatus = cachedUser.paymentStatus;
        }
      } catch (_) {}
    }

    // 2. Fetch full profile to get memberId, occupation (and confirm usertype if not cached).
    try {
      final svc = UserDetailsService();
      final response = await svc.getUserDetails(
        callerIdInt ?? 0,
        1 /* admin id */,
      );
      memberId = response.data.personalDetail.memberId;
      usertype ??= response.data.personalDetail.userType;
      final occ = response.data.personalDetail.occupationType;
      if (occ.isNotEmpty && occ != 'Not available') occupation = occ;
    } catch (_) {}

    return {
      'usertype': usertype,
      'paymentStatus': paymentStatus,
      'memberId': memberId,
      'occupation': occupation,
    };
  }

  /// Show an incoming call dialog when a user calls the admin.
  void _handleIncomingCallFromUser(Map<String, dynamic> data) {
    final callerId = data['callerId']?.toString() ?? '';
    final callerName = data['callerName']?.toString() ?? 'User';
    final channelName = data['channelName']?.toString() ?? '';
    final callType = data['callType']?.toString() ?? 'audio';
    final isVideo = callType == 'video';

    if (channelName.isEmpty || callerId.isEmpty) return;

    // If admin is already in a call, show a non-blocking banner notification
    // so the current call is not interrupted.  Another admin session can
    // still pick up the waiting call.
    if (_callOverlayEntry != null) {
      _showCallWaitingBanner(
        callerId: callerId,
        callerName: callerName,
        channelName: channelName,
        callType: callType,
        isVideo: isVideo,
      );
      return;
    }

    // Start looping ringtone for the incoming call.
    WebNotificationService.playCallRingtone();

    Timer? autoRejectTimer;
    StreamSubscription<Map<String, dynamic>>? cancelSub;
    StreamSubscription<Map<String, dynamic>>? endedSub;
    StreamSubscription<Map<String, dynamic>>? answeredElsewhereSub;
    BuildContext? incomingCallDialogContext;
    var dismissed = false;
    var remoteCallClosed = false;

    // Notifier so the dialog can rebuild once caller details arrive.
    final callerDetailsNotifier = ValueNotifier<Map<String, String?>>({
      'usertype': null,
      'paymentStatus': null,
      'memberId': null,
      'occupation': null,
    });

    // Kick off async fetch – dialog updates when data arrives.
    _fetchCallerDetails(callerId).then((details) {
      if (!dismissed) callerDetailsNotifier.value = details;
    });

    void dismissDialog(bool accepted) {
      if (dismissed) return;
      dismissed = true;
      WebNotificationService.stopCallRingtone();
      final ctx = incomingCallDialogContext;
      if (ctx != null && Navigator.of(ctx, rootNavigator: true).canPop()) {
        Navigator.of(ctx, rootNavigator: true).pop(accepted);
      }
    }

    cancelSub = _socketService.onCallCancelled.listen((event) {
      if (event['channelName']?.toString() != channelName) return;
      remoteCallClosed = true;
      dismissDialog(false);
    });

    endedSub = _socketService.onCallEnded.listen((event) {
      if (event['channelName']?.toString() != channelName) return;
      remoteCallClosed = true;
      dismissDialog(false);
    });

    answeredElsewhereSub = _socketService.onCallAnsweredElsewhere.listen((
      event,
    ) {
      if (event['channelName']?.toString() != channelName) return;
      remoteCallClosed = true;
      dismissDialog(false);
    });

    showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        incomingCallDialogContext = ctx;
        autoRejectTimer?.cancel();
        autoRejectTimer = Timer(
          const Duration(seconds: kIncomingCallTimeoutSeconds),
          () => dismissDialog(false),
        );
        final icon = isVideo ? Icons.videocam_rounded : Icons.call_rounded;
        final title = isVideo ? 'Incoming video call' : 'Incoming call';
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 380),
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            decoration: BoxDecoration(
              color: const Color(0xFF111827),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.28),
                  blurRadius: 24,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: ValueListenableBuilder<Map<String, String?>>(
              valueListenable: callerDetailsNotifier,
              builder: (_, details, __) {
                final usertype = details['usertype'];
                final paymentStatus = details['paymentStatus'];
                final memberId = details['memberId'];
                final occupation = details['occupation'];
                final isPaid = (usertype ?? '').toLowerCase() == 'paid';

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: isVideo
                              ? const [Color(0xFF8B5CF6), Color(0xFF6366F1)]
                              : const [Color(0xFF10B981), Color(0xFF059669)],
                        ),
                      ),
                      child: Icon(icon, color: Colors.white, size: 34),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      callerName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    // User type badge (FREE / PAID)
                    if (usertype != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: isPaid
                              ? const Color(0xFF1A3A2A)
                              : const Color(0xFF1A2A3A),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: isPaid
                                ? const Color(0xFF34D399)
                                : const Color(0xFF60A5FA),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isPaid
                                  ? Icons.workspace_premium_rounded
                                  : Icons.person_outline_rounded,
                              size: 13,
                              color: isPaid
                                  ? const Color(0xFF34D399)
                                  : const Color(0xFF60A5FA),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isPaid ? 'PREMIUM' : 'FREE',
                              style: TextStyle(
                                color: isPaid
                                    ? const Color(0xFF34D399)
                                    : const Color(0xFF60A5FA),
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                    ],
                    // Package status row
                    if (paymentStatus != null && paymentStatus.isNotEmpty) ...[
                      _buildCallerDetailRow(
                        icon: Icons.card_membership_rounded,
                        label: 'Package',
                        value: paymentStatus,
                        color: const Color(0xFFFBBF24),
                      ),
                      const SizedBox(height: 4),
                    ],
                    // Member ID / registration number row
                    if (memberId != null &&
                        memberId.isNotEmpty &&
                        memberId != 'Not available') ...[
                      _buildCallerDetailRow(
                        icon: Icons.badge_outlined,
                        label: 'Member ID',
                        value: memberId,
                        color: const Color(0xFFA78BFA),
                      ),
                      const SizedBox(height: 4),
                    ] else if (usertype != null && memberId == null) ...[
                      // Still loading member ID
                      _buildCallerDetailRow(
                        icon: Icons.badge_outlined,
                        label: 'Member ID',
                        value: '…',
                        color: Colors.white38,
                      ),
                      const SizedBox(height: 4),
                    ],
                    // Profession / occupation row
                    if (occupation != null && occupation.isNotEmpty) ...[
                      _buildCallerDetailRow(
                        icon: Icons.work_outline_rounded,
                        label: 'Profession',
                        value: occupation,
                        color: const Color(0xFF67E8F9),
                      ),
                      const SizedBox(height: 4),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.72),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'Respond within $kIncomingCallTimeoutSeconds seconds',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.62),
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        Expanded(
                          child: _buildIncomingCallActionButton(
                            label: 'Reject',
                            icon: Icons.call_end_rounded,
                            backgroundColor: const Color(0xFF3F1D24),
                            foregroundColor: const Color(0xFFF87171),
                            onTap: () => dismissDialog(false),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildIncomingCallActionButton(
                            label: 'Accept',
                            icon: isVideo
                                ? Icons.videocam_rounded
                                : Icons.call_rounded,
                            backgroundColor: const Color(0xFF123F34),
                            foregroundColor: const Color(0xFF34D399),
                            onTap: () => dismissDialog(true),
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    ).then((accepted) {
      callerDetailsNotifier.dispose();
      autoRejectTimer?.cancel();
      cancelSub?.cancel();
      endedSub?.cancel();
      answeredElsewhereSub?.cancel();
      _callManager.clearCallData();
      if (accepted == true) {
        _socketService.emitCallAccept(
          callerId: callerId,
          recipientId: kAdminUserId,
          recipientName: 'Admin',
          recipientUid: '',
          channelName: channelName,
          callType: callType,
        );
        // Launch call overlay with the caller's channel
        _launchIncomingCall(
          userId: callerId,
          userName: callerName,
          channelName: channelName,
          isVideo: isVideo,
        );
      } else if (!remoteCallClosed) {
        _socketService.emitCallReject(
          callerId: callerId,
          recipientId: kAdminUserId,
          recipientName: 'Admin',
          channelName: channelName,
          callType: callType,
        );
      }
    });
  }

  /// Small info row used inside the incoming call dialog.
  Widget _buildCallerDetailRow({
    required IconData icon,
    required String label,
    required String value,
    Color color = Colors.white70,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Text(
          '$label: ',
          style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 12),
        ),
        Flexible(
          child: Text(
            value,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  /// Shows a compact banner at the top when admin is already in a call and
  /// another user is calling.  The ongoing call is NOT interrupted.
  void _showCallWaitingBanner({
    required String callerId,
    required String callerName,
    required String channelName,
    required String callType,
    required bool isVideo,
  }) {
    // Dismiss any previous waiting banner before showing the new one.
    _removeCallWaitingBanner();

    Timer? autoRejectTimer;
    StreamSubscription<Map<String, dynamic>>? cancelSub;
    StreamSubscription<Map<String, dynamic>>? endedSub;
    StreamSubscription<Map<String, dynamic>>? answeredElsewhereSub;
    var dismissed = false;
    var remoteCallClosed = false;
    final bannerDetailsNotifier = ValueNotifier<Map<String, String?>>({
      'usertype': null,
      'memberId': null,
      'occupation': null,
    });
    _fetchCallerDetails(callerId).then((details) {
      if (!dismissed) bannerDetailsNotifier.value = details;
    });

    void dismiss(bool accepted) {
      if (dismissed) return;
      dismissed = true;
      autoRejectTimer?.cancel();
      cancelSub?.cancel();
      endedSub?.cancel();
      answeredElsewhereSub?.cancel();
      _removeCallWaitingBanner();
      // Dispose the notifier after the overlay entry has been removed from the
      // widget tree so that any in-flight ValueListenableBuilder rebuild during
      // the removal does not access a disposed notifier.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        bannerDetailsNotifier.dispose();
      });
      if (accepted) {
        _socketService.emitCallAccept(
          callerId: callerId,
          recipientId: kAdminUserId,
          recipientName: 'Admin',
          recipientUid: '',
          channelName: channelName,
          callType: callType,
        );
        // End current call and start the new one.
        _removeCallOverlay();
        _launchIncomingCall(
          userId: callerId,
          userName: callerName,
          channelName: channelName,
          isVideo: isVideo,
        );
      } else if (!remoteCallClosed) {
        _socketService.emitCallReject(
          callerId: callerId,
          recipientId: kAdminUserId,
          recipientName: 'Admin',
          channelName: channelName,
          callType: callType,
        );
      }
    }

    cancelSub = _socketService.onCallCancelled.listen((event) {
      if (event['channelName']?.toString() != channelName) return;
      remoteCallClosed = true;
      dismiss(false);
    });
    endedSub = _socketService.onCallEnded.listen((event) {
      if (event['channelName']?.toString() != channelName) return;
      remoteCallClosed = true;
      dismiss(false);
    });
    answeredElsewhereSub = _socketService.onCallAnsweredElsewhere.listen((
      event,
    ) {
      if (event['channelName']?.toString() != channelName) return;
      remoteCallClosed = true;
      dismiss(false);
    });

    autoRejectTimer = Timer(
      const Duration(seconds: kIncomingCallTimeoutSeconds),
      () => dismiss(false),
    );

    _callWaitingBannerEntry = OverlayEntry(
      builder: (ctx) => Positioned(
        top: MediaQuery.of(ctx).padding.top + 8,
        left: 16,
        right: 16,
        child: Material(
          color: Colors.transparent,
          child: ValueListenableBuilder<Map<String, String?>>(
            valueListenable: bannerDetailsNotifier,
            builder: (_, details, __) {
              final usertype = details['usertype'];
              final memberId = details['memberId'];
              final occupation = details['occupation'];
              final isPaid = (usertype ?? '').toLowerCase() == 'paid';
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF1F2937),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFF374151)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.4),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: isVideo
                              ? const [Color(0xFF8B5CF6), Color(0xFF6366F1)]
                              : const [Color(0xFF10B981), Color(0xFF059669)],
                        ),
                      ),
                      child: Icon(
                        isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  callerName,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              if (usertype != null) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isPaid
                                        ? const Color(0xFF1A3A2A)
                                        : const Color(0xFF1A2A3A),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: isPaid
                                          ? const Color(0xFF34D399)
                                          : const Color(0xFF60A5FA),
                                      width: 1,
                                    ),
                                  ),
                                  child: Text(
                                    isPaid ? 'PREMIUM' : 'FREE',
                                    style: TextStyle(
                                      color: isPaid
                                          ? const Color(0xFF34D399)
                                          : const Color(0xFF60A5FA),
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isVideo
                                ? 'Incoming video call (call waiting)'
                                : 'Incoming call (call waiting)',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.6),
                              fontSize: 12,
                            ),
                          ),
                          if (memberId != null &&
                              memberId.isNotEmpty &&
                              memberId != 'Not available') ...[
                            const SizedBox(height: 2),
                            Text(
                              'ID: $memberId',
                              style: TextStyle(
                                color: const Color(0xFFA78BFA).withOpacity(0.9),
                                fontSize: 11,
                              ),
                            ),
                          ],
                          if (occupation != null && occupation.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              occupation,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: const Color(0xFF67E8F9).withOpacity(0.9),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Accept button
                        GestureDetector(
                          onTap: () => dismiss(true),
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0xFF123F34),
                            ),
                            child: const Icon(
                              Icons.call_rounded,
                              color: Color(0xFF34D399),
                              size: 18,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        // Dismiss button
                        GestureDetector(
                          onTap: () => dismiss(false),
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0xFF3F1D24),
                            ),
                            child: const Icon(
                              Icons.call_end_rounded,
                              color: Color(0xFFF87171),
                              size: 18,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_callWaitingBannerEntry!);
  }

  Widget _buildIncomingCallActionButton({
    required String label,
    required IconData icon,
    required Color backgroundColor,
    required Color foregroundColor,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      height: 54,
      child: Material(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: foregroundColor, size: 22),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: foregroundColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Launch the call overlay for an INCOMING call from a user.
  void _launchIncomingCall({
    required String userId,
    required String userName,
    required String channelName,
    required bool isVideo,
  }) {
    if (_callOverlayEntry != null) return;

    final isMinimizedNotifier = ValueNotifier<bool>(false);

    void onCallEnded(String callType, String status, int durationSeconds) {
      _removeCallOverlay();
      _saveCallHistory(userId, callType, status, durationSeconds);
    }

    _callOverlayEntry = OverlayEntry(
      builder: (ctx) => ValueListenableBuilder<bool>(
        valueListenable: isMinimizedNotifier,
        builder: (_, isMin, __) {
          final callWidget = isVideo
              ? VideoCallScreen(
                  currentUserId: kAdminUserId,
                  currentUserName: 'Admin',
                  otherUserId: userId,
                  otherUserName: userName,
                  isOutgoingCall: false,
                  incomingChannelName: channelName,
                  onMinimize: () => isMinimizedNotifier.value = true,
                  onEnd: _removeCallOverlay,
                  onCallEnded: onCallEnded,
                )
              : CallScreen(
                  currentUserId: kAdminUserId,
                  currentUserName: 'Admin',
                  otherUserId: userId,
                  otherUserName: userName,
                  isOutgoingCall: false,
                  incomingChannelName: channelName,
                  onMinimize: () => isMinimizedNotifier.value = true,
                  onEnd: _removeCallOverlay,
                  onCallEnded: onCallEnded,
                );

          return Stack(
            children: [
              Offstage(offstage: isMin, child: callWidget),
              if (isMin)
                _buildMiniCallBar(
                  userName: userName,
                  isVideo: isVideo,
                  onMaximize: () => isMinimizedNotifier.value = false,
                  onEnd: _removeCallOverlay,
                ),
            ],
          );
        },
      ),
    );
    Overlay.of(context).insert(_callOverlayEntry!);
  }

  // ── Local message cache helpers ───────────────────────────────────────────

  /// Maximum number of messages to persist in the local cache per room.
  static const int _maxCachedAdminMessages = 30;

  /// Returns the SharedPreferences key for the given room's message cache.
  static String _adminCacheKey(String roomId) => 'admin_chat_msgs_$roomId';

  /// Saves the most recent [_maxCachedAdminMessages] messages to SharedPreferences.
  Future<void> _saveAdminMessagesToCache(String roomId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final toSave = _messages.length > _maxCachedAdminMessages
          ? _messages.sublist(_messages.length - _maxCachedAdminMessages)
          : _messages;
      final encoded = jsonEncode(toSave);
      await prefs.setString(_adminCacheKey(roomId), encoded);
    } catch (e) {
      debugPrint('Failed to save admin messages to local cache: $e');
    }
  }

  /// Loads previously cached messages from SharedPreferences.
  /// Returns an empty list when no cache exists or on error.
  Future<List<Map<String, dynamic>>> _loadAdminMessagesFromCache(
    String roomId,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_adminCacheKey(roomId));
      if (raw == null) return [];
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
    } catch (e) {
      debugPrint('Failed to load admin messages from local cache: $e');
      return [];
    }
  }

  // ── Message loading ───────────────────────────────────────────────────────

  /// Load a page of messages from the server.
  Future<void> _loadMessages({bool reset = false}) async {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    if (chatProvider.id == null) return;
    final String roomId = AdminSocketService.chatRoomId(
      chatProvider.id.toString(),
    );

    if (reset) {
      setState(() {
        _messages = [];
        _filteredMessages = [];
        _currentPage = 1;
        _hasMoreMessages = true;
        _isInitialLoad = true;
        _scrollLocked = true;
        _initialScrollDone = false;
      });
      _socketService.joinRoom(roomId);
      _socketService.setActiveChat(roomId);

      // Show cached messages immediately so the chat is usable at once.
      final cached = await _loadAdminMessagesFromCache(roomId);
      if (!mounted) return;
      if (cached.isNotEmpty && _messages.isEmpty) {
        setState(() {
          _messages = cached;
          _isInitialLoad = false;
        });
        _performInitialScroll();
      }
    }

    setState(() => _isLoadingMore = !reset);

    try {
      final result = await _socketService.getMessages(
        roomId,
        page: _currentPage,
        limit: _pageSize,
      );
      if (!mounted) return;
      final msgs = (result['messages'] as List? ?? []).map((m) {
        try {
          return _socketMsgToAdminData(Map<String, dynamic>.from(m as Map));
        } catch (e) {
          debugPrint('Failed to convert message: $e');
          // Return a safe fallback message
          return <String, dynamic>{
            'messageId': m['messageId']?.toString() ?? 'unknown',
            'senderid': m['senderId']?.toString() ?? '',
            'receiverid': m['receiverId']?.toString() ?? '',
            'message': 'Error loading message',
            'type': 'text',
            'liked': false,
            'seen': false,
            'deleted': false,
            'unsent': false,
            'edited': false,
            'replyto': null,
            'timestamp':
                m['timestamp']?.toString() ?? DateTime.now().toIso8601String(),
          };
        }
      }).toList();
      final hasMore = result['hasMore'] == true;

      setState(() {
        if (reset) {
          _messages = msgs;
        } else {
          final existingIds = _messages.map((m) => m['messageId']).toSet();
          final newMsgs = msgs
              .where((m) => !existingIds.contains(m['messageId']))
              .toList();
          _messages = [...newMsgs, ..._messages];
        }
        _hasMoreMessages = hasMore;
        _isLoadingMore = false;
        _isInitialLoad = false;
      });

      if (reset) {
        _performInitialScroll();
        _saveAdminMessagesToCache(roomId);
      }
      _socketService.markRead(roomId);
    } catch (e) {
      debugPrint('Error loading messages: $e');
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
          _isInitialLoad = false;
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
        // Wait for layout to settle before unlocking
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _scrollLocked = false);
        });
      } else {
        // Controller not yet attached; retry after layout
        Future.delayed(const Duration(milliseconds: 50), () {
          if (mounted && _scrollController.hasClients) {
            _scrollController.jumpTo(
              _scrollController.position.maxScrollExtent,
            );
          }
          if (mounted) setState(() => _scrollLocked = false);
        });
      }
    });
  }

  /// Keep [_filteredMessages] in sync with [_messages] after an in-place update.
  void _syncFilteredMessages() {
    if (!_isSearching || _searchController.text.isEmpty) return;
    final query = _searchController.text.toLowerCase();
    _filteredMessages = _messages
        .where((m) => m['message'].toString().toLowerCase().contains(query))
        .toList();
  }

  Future<void> _fetchMatchDetails() async {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);

    if (chatProvider.id == null) {
      setState(() {
        _isLoadingMatchDetails = false;
        _matchDetails = null;
        _mutualMatches = [];
      });
      return;
    }

    setState(() {
      _isLoadingMatchDetails = true;
      _matchDetails = null;
      _mutualMatches = [];
    });

    try {
      final response = await http.get(
        Uri.parse(
          '${kAdminApiBaseUrl}/get_match_details.php?user_id=${chatProvider.id}',
        ),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success') {
          setState(() {
            _matchDetails = data['match_details'];
            _mutualMatches = List<Map<String, dynamic>>.from(
              data['mutual_matches'] ?? [],
            );
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching match details: $e');
    } finally {
      setState(() {
        _isLoadingMatchDetails = false;
      });
    }
  }

  // ── TYPING INDICATOR ────────────────────────────────────────────────────

  void _setupTypingListener(int userId) {
    _typingTimer?.cancel();
    _adminTypingActive = false;
    final roomId = AdminSocketService.chatRoomId(userId.toString());
    _socketService.joinRoom(roomId);
    _typingStopTimer?.cancel();
    _adminTypingActive = false;
    _activeTypingRoomId = null;
    setState(() => _userIsTyping = false);
  }

  void _updateAdminTypingStatus(String text, String receiverId) {
    final trimmed = text.trim();
    if (receiverId.isEmpty) return;
    _typingTimer?.cancel();
    final roomId = AdminSocketService.chatRoomId(receiverId);
    final isTyping = trimmed.isNotEmpty;
    if (isTyping) {
      final now = DateTime.now();
      final bool shouldEmitStart =
          !_adminTypingActive ||
          _lastTypingStart == null ||
          now.difference(_lastTypingStart!) >= _kTypingStartThrottle;
      if (shouldEmitStart) {
        _socketService.sendTypingStart(roomId);
        _adminTypingActive = true;
        _lastTypingStart = now;
      }
      _typingTimer = Timer(_kTypingIdleDuration, () {
        _emitTypingStop(roomId);
      });
    } else {
      _emitTypingStop(roomId);
    }
    _activeTypingRoomId = roomId;
    _adminTypingActive = true;
    _socketService.sendTypingStart(roomId);
  }

  void _emitTypingStop(String roomId) {
    _typingTimer?.cancel();
    if (!_adminTypingActive) return;
    _adminTypingActive = false;
    _socketService.sendTypingStop(roomId);
  }

  void _clearAdminTypingStatus() {
    _typingTimer?.cancel();
    // Use the cached provider reference — safe to call even from dispose()
    // because it does NOT look up the widget tree via context.
    final chatProvider = _chatProviderRef;
    final receiverId = chatProvider?.id?.toString();
    final roomId = receiverId != null && receiverId.isNotEmpty
        ? AdminSocketService.chatRoomId(receiverId)
        : null;
    final wasTyping = _adminTypingActive;
    _adminTypingActive = false;
    if (roomId != null && wasTyping) {
      _socketService.sendTypingStop(roomId);
    }
  }

  // Ensure the typing sound asset is loaded into [_typingAudioPlayer].
  Future<void> _ensureTypingSoundLoaded() async {
    if (_typingSoundLoaded) return;
    try {
      await _typingAudioPlayer.setAsset('assets/audio/outcall.mp3');
      _typingSoundLoaded = true;
    } catch (e) {
      debugPrint('Failed to load typing sound: $e');
    }
  }

  // Play typing sound — short, soft, Messenger-style
  void _playTypingSound() async {
    try {
      await _ensureTypingSoundLoaded();
      if (!_typingSoundLoaded) return;
      await _typingAudioPlayer.setVolume(0.2);
      await _typingAudioPlayer.seek(Duration.zero);
      _typingAudioPlayer.play();
      Future.delayed(const Duration(milliseconds: 250), () {
        _typingAudioPlayer.stop();
      });
    } catch (e) {
      print('Error playing typing sound: $e');
    }
  }

  // ── SEEN STATUS ─────────────────────────────────────────────────────────

  /// Mark incoming messages in the current room as read via Socket.IO.
  void _markIncomingMessagesAsSeen() {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    if (chatProvider.id == null) return;
    final String roomId = AdminSocketService.chatRoomId(
      chatProvider.id.toString(),
    );
    _socketService.markRead(roomId);
  }

  // ── CALL HISTORY ─────────────────────────────────────────────────────────

  /// Send a call history message via Socket.IO.
  Future<void> _saveCallHistory(
    String receiverId,
    String callType,
    String status,
    int durationSeconds,
  ) async {
    try {
      final String label = _callLabel(callType, status, durationSeconds);
      final String roomId = AdminSocketService.chatRoomId(receiverId);
      final String msgId =
          'call_${DateTime.now().millisecondsSinceEpoch}_${senderId}';
      _socketService.sendMessage(
        chatRoomId: roomId,
        receiverId: receiverId,
        message: jsonEncode({
          'label': label,
          'callType': callType,
          'callStatus': status,
          'callDuration': durationSeconds,
        }),
        messageType: 'call',
        messageId: msgId,
      );
    } catch (_) {}
  }

  String _callLabel(String callType, String status, int seconds) {
    final bool isVideo = callType == 'video';
    if (status == 'missed') {
      return isVideo ? '📹 Missed Video Call' : '📞 Missed Call';
    }
    final String dur = _formatCallDuration(seconds);
    return isVideo ? '📹 Video Call • $dur' : '📞 Audio Call • $dur';
  }

  String _messagePreviewText(Map<String, dynamic> data) {
    if (data['deleted'] == true) return _kDeletedMessageText;
    if (data['unsent'] == true) return _kUnsentMessageText;

    switch (data['type']?.toString()) {
      case 'image':
        return '📷 Image';
      case 'voice':
        return '🎤 Voice message';
      case 'profile_card':
        return '👤 Profile shared';
      case 'report':
        return '🚩 Profile Report';
      case 'call':
        return _callLabel(
          data['callType']?.toString() ?? 'audio',
          data['callStatus']?.toString() ?? 'missed',
          (data['callDuration'] as num?)?.toInt() ?? 0,
        );
      case 'text':
      case null:
        final text = data['message']?.toString().trim() ?? '';
        return text.isEmpty ? _kDefaultMessageText : text;
      default:
        return data['message']?.toString() ?? _kDefaultMessageText;
    }
  }

  Map<String, dynamic> _buildReplyPayload({
    required String messageId,
    required Map<String, dynamic> data,
    required String senderId,
    required String senderName,
  }) {
    return {
      'messageId': messageId,
      'message': _messagePreviewText(data),
      'senderid': senderId,
      'senderName': senderName,
      'type': data['type']?.toString() ?? 'text',
      if (data['type'] == 'image' && data['imageUrl'] != null)
        'imageUrl': data['imageUrl'],
      'edited': data['edited'] == true,
      'deleted': data['deleted'] == true,
      'unsent': data['unsent'] == true,
    };
  }

  Map<String, dynamic> _buildFallbackReplyPayload({
    required String messageId,
    required String message,
    required String senderId,
    required String senderName,
  }) {
    return _buildReplyPayload(
      messageId: messageId,
      data: {
        'message': message,
        'type': 'text',
        'edited': false,
        'deleted': false,
        'unsent': false,
      },
      senderId: senderId,
      senderName: senderName,
    );
  }

  bool _canEditMessage(Map<String, dynamic> data, bool isSentByMe) {
    if (!isSentByMe) return false;
    if (data['deleted'] == true || data['unsent'] == true) return false;
    final type = data['type']?.toString();
    return type == null || type == 'text';
  }

  bool _canMutateMessage(Map<String, dynamic> data, bool isSentByMe) {
    // Admin can delete/unsend any message (not just their own).
    return data['deleted'] != true && data['unsent'] != true;
  }

  Future<void> _syncReplySnapshots(
    String sourceMessageId,
    Map<String, dynamic> replyData,
  ) async {
    // Update reply previews locally in the in-memory message list.
    setState(() {
      for (int i = 0; i < _messages.length; i++) {
        final replyto = _messages[i]['replyto'];
        if (replyto is Map &&
            _replyTargetMessageId(Map<String, dynamic>.from(replyto)) ==
                sourceMessageId) {
          _messages[i] = {..._messages[i], 'replyto': replyData};
        }
      }
    });
  }

  Future<void> _applyMessageMutation({
    required String messageId,
    required Map<String, dynamic> updates,
  }) async {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    final receiverId = chatProvider.id?.toString();
    if (receiverId == null) return;

    final String roomId = AdminSocketService.chatRoomId(receiverId);

    // Determine mutation type and emit the appropriate Socket.IO event.
    if (updates['unsent'] == true) {
      _socketService.unsendMessage(chatRoomId: roomId, messageId: messageId);
    } else if (updates['deleted'] == true) {
      _socketService.deleteMessage(chatRoomId: roomId, messageId: messageId);
    } else if (updates.containsKey('message') && updates['edited'] == true) {
      _socketService.editMessage(
        chatRoomId: roomId,
        messageId: messageId,
        newMessage: updates['message'] as String,
      );
    }

    // Optimistically update the local list immediately.
    setState(() {
      final idx = _messages.indexWhere((m) => m['messageId'] == messageId);
      if (idx >= 0) {
        _messages[idx] = {..._messages[idx], ...updates};
        _syncFilteredMessages();
      }
    });

    // Update reply-preview snapshots locally.
    final idx = _messages.indexWhere((m) => m['messageId'] == messageId);
    if (idx >= 0) {
      final latestData = _messages[idx];
      final replyData = {
        'messageId': messageId,
        'message': _messagePreviewText(latestData),
        'senderid': latestData['senderid']?.toString() ?? senderId.toString(),
        'senderName': latestData['senderid']?.toString() == senderId.toString()
            ? 'You'
            : (chatProvider.namee ?? 'User'),
        'type': latestData['type']?.toString() ?? 'text',
        'edited': latestData['edited'] == true,
        'deleted': latestData['deleted'] == true,
        'unsent': latestData['unsent'] == true,
      };
      await _syncReplySnapshots(messageId, replyData);
    }
  }

  String _formatCallDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _initializeWebSpeech() {
    // Prefer the unprefixed SpeechRecognition (Firefox/Edge) with a fallback to
    // the webkit-prefixed version used by Chrome.
    final dynamic speechClass = js.context.hasProperty('SpeechRecognition')
        ? js.context['SpeechRecognition']
        : js.context.hasProperty('webkitSpeechRecognition')
        ? js.context['webkitSpeechRecognition']
        : null;

    if (speechClass == null) return;

    _webSpeechRecognition = js.JsObject(speechClass as js.JsFunction);
    _webSpeechRecognition!['continuous'] = true;
    _webSpeechRecognition!['interimResults'] = true;
    _webSpeechRecognition!['lang'] = _selectedLanguage;

    _webSpeechRecognition!['onresult'] = ((JSAny? event) {
      final eventObj = js.JsObject.fromBrowserObject(event!);
      final results = eventObj['results'];
      if (results == null) return;

      final resultList = js.JsObject.fromBrowserObject(results);
      // Use safe num→int cast; JS numbers come through as num, not int.
      final int length = (resultList['length'] as num).toInt();
      // Only process new results starting at resultIndex to avoid double-counting
      // previous finals every time onresult fires.
      final int resultIndex = (eventObj['resultIndex'] as num).toInt();

      String interimTranscript = '';
      String finalTranscript = '';

      for (int i = resultIndex; i < length; i++) {
        final result = js.JsObject.fromBrowserObject(
          resultList.callMethod('item', [i]),
        );
        final transcript =
            js.JsObject.fromBrowserObject(
                  result.callMethod('item', [0]),
                )['transcript']
                as String;
        // Use == true instead of `as bool` — JS booleans may not cast to Dart bool directly.
        final isFinal = result['isFinal'] == true;
        if (isFinal) {
          finalTranscript += transcript;
        } else {
          interimTranscript += transcript;
        }
      }

      if (finalTranscript.isNotEmpty) {
        _textBeforeVoice = _textBeforeVoice + finalTranscript;
      }

      final displayText = interimTranscript.isNotEmpty
          ? _textBeforeVoice + interimTranscript
          : _textBeforeVoice;

      setState(() {
        _messageController.text = displayText;
        _messageController.selection = TextSelection.fromPosition(
          TextPosition(offset: displayText.length),
        );
      });
    }).toJS;

    _webSpeechRecognition!['onend'] = ((JSAny? _) {
      // With continuous=true the browser may still fire onend after silence.
      // Restart automatically unless the user explicitly stopped listening.
      if (!_userStoppedListening && _isListening && mounted) {
        try {
          _webSpeechRecognition!.callMethod('start');
        } catch (e) {
          setState(() => _isListening = false);
        }
      } else {
        if (mounted) setState(() => _isListening = false);
      }
    }).toJS;

    _webSpeechRecognition!['onerror'] = ((JSAny? event) {
      if (!mounted) return;
      final error =
          js.JsObject.fromBrowserObject(event!)['error'] as String? ?? '';
      if (error == 'aborted')
        return; // user-initiated stop, onend handles state

      // Prevent auto-restart only for unrecoverable errors (permission denied).
      if (error == 'not-allowed' || error == 'service-not-allowed') {
        _userStoppedListening = true;
      }

      final resetText = _textBeforeVoice.trimRight();
      setState(() {
        _isListening = false;
        _messageController.text = resetText;
        _messageController.selection = TextSelection.fromPosition(
          TextPosition(offset: resetText.length),
        );
      });

      String errorMsg;
      switch (error) {
        case 'not-allowed':
        case 'service-not-allowed':
          errorMsg =
              'Microphone access denied. Please allow microphone permission in your browser settings.';
          break;
        case 'no-speech':
          errorMsg = 'No speech detected. Please try again.';
          break;
        default:
          errorMsg = 'Speech error: $error';
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(errorMsg)));
    }).toJS;
  }

  Future<void> _initializeRecorder() async {
    try {
      await _recorder.openRecorder();
    } catch (e) {}
  }

  void _startListening() {
    if (_webSpeechRecognition != null && !_isListening) {
      _textBeforeVoice = _messageController.text;
      if (_textBeforeVoice.isNotEmpty && !_textBeforeVoice.endsWith(' ')) {
        _textBeforeVoice += ' ';
      }
      _webSpeechRecognition!['lang'] = _selectedLanguage;
      _userStoppedListening = false;
      _webSpeechRecognition!.callMethod('start');
      setState(() => _isListening = true);
    }
  }

  void _stopListening() {
    if (_isListening && _webSpeechRecognition != null) {
      _userStoppedListening = true;
      _webSpeechRecognition!.callMethod('stop');
      setState(() => _isListening = false);
    }
  }

  void _scrollToBottom() {
    // Don't auto-scroll if scroll is locked during initial load
    if (_scrollLocked) return;
    if (!mounted) return;
    if (_scrollController.hasClients) {
      // jumpTo(0) is a no-op when content fits on screen, so no need to guard
      // against maxScrollExtent == 0 — just jump unconditionally.
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    } else {
      // Controller not yet attached; retry once after layout.
      Future.delayed(const Duration(milliseconds: 50), () {
        if (mounted && _scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    }
  }

  void _onScrollForPagination() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels <= 200 && !_isLoadingMore && _hasMoreMessages) {
      _loadMoreMessages();
    }
  }

  void _loadMoreMessages() {
    if (_isLoadingMore || !_hasMoreMessages) return;
    setState(() {
      _isLoadingMore = true;
      _suppressNextAutoScroll = true;
    });
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    if (chatProvider.id == null) {
      setState(() => _isLoadingMore = false);
      return;
    }
    final String roomId = AdminSocketService.chatRoomId(
      chatProvider.id.toString(),
    );
    final double savedOffset = _scrollController.hasClients
        ? _scrollController.offset
        : 0;
    // Capture old max extent so we can shift the position by exactly the
    // height of the newly prepended messages, keeping the visible content
    // stable instead of jumping.
    final double oldMaxExtent = _scrollController.hasClients
        ? _scrollController.position.maxScrollExtent
        : 0;
    _currentPage++;
    _socketService
        .getMessages(roomId, page: _currentPage, limit: _pageSize)
        .then((result) {
          if (!mounted) return;
          final msgs = (result['messages'] as List? ?? [])
              .map(
                (m) =>
                    _socketMsgToAdminData(Map<String, dynamic>.from(m as Map)),
              )
              .toList();
          final hasMore = result['hasMore'] == true;
          final existingIds = _messages.map((m) => m['messageId']).toSet();
          final newMsgs = msgs
              .where((m) => !existingIds.contains(m['messageId']))
              .toList();
          setState(() {
            _messages = [...newMsgs, ..._messages];
            _hasMoreMessages = hasMore;
            _isLoadingMore = false;
            _suppressNextAutoScroll = false;
          });
          // Restore scroll position so the user stays at the same message.
          // Shift by the height added at the top (newMaxExtent - oldMaxExtent).
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollController.hasClients) {
              final double newMaxExtent =
                  _scrollController.position.maxScrollExtent;
              _scrollController.jumpTo(
                savedOffset + (newMaxExtent - oldMaxExtent),
              );
            }
          });
        })
        .catchError((e) {
          _currentPage--;
          if (mounted)
            setState(() {
              _isLoadingMore = false;
              _suppressNextAutoScroll = false;
            });
        });
  }

  GlobalKey _messageKeyFor(String messageId) {
    return _messageKeys.putIfAbsent(
      messageId,
      () => GlobalKey(debugLabel: 'message-$messageId'),
    );
  }

  void _highlightMessage(String messageId) {
    _replyHighlightTimer?.cancel();
    if (!mounted) return;

    setState(() {
      _highlightedMessageId = messageId;
    });

    _replyHighlightTimer = Timer(const Duration(milliseconds: 1600), () {
      if (!mounted || _highlightedMessageId != messageId) return;
      setState(() {
        _highlightedMessageId = null;
      });
    });
  }

  Future<bool> _ensureMessageLoaded(String messageId) async {
    for (int attempt = 0; attempt < _kMaxLoadAttempts; attempt++) {
      final bool found = _messages.any((m) => m['messageId'] == messageId);
      if (found) return true;
      if (!_hasMoreMessages || _isLoadingMore) {
        await Future.delayed(_kLoadRetryDelay);
        continue;
      }
      _loadMoreMessages();
      await Future.delayed(_kLoadMoreDelay);
    }
    return _messages.any((m) => m['messageId'] == messageId);
  }

  Duration _navigationDurationForDistance(double distance) {
    final int millis =
        (_kMinScrollDurationMs + (distance * _kScrollDurationMultiplier))
            .round()
            .clamp(_kMinScrollDurationMs, _kMaxScrollDurationMs);
    return Duration(milliseconds: millis);
  }

  Future<void> _scrollToMessage(String messageId) async {
    if (messageId.isEmpty) return;

    final bool isLoaded = await _ensureMessageLoaded(messageId);
    if (!mounted) return;

    if (!isLoaded) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Original message could not be found.')),
      );
      return;
    }

    if (_scrollController.hasClients) {
      final int? targetIndex = _messageIndexMap[messageId];
      if (targetIndex != null) {
        final position = _scrollController.position;
        final double estimatedOffset = (targetIndex * _kEstimatedMessageExtent)
            .clamp(0.0, position.maxScrollExtent);
        final double distance = (position.pixels - estimatedOffset).abs();
        await _scrollController.animateTo(
          estimatedOffset,
          duration: _navigationDurationForDistance(distance),
          curve: Curves.easeInOutCubic,
        );
      }
    }

    for (int attempt = 0; attempt < _kMaxContextFindAttempts; attempt++) {
      // Wait for the post-scroll frame so the lazily built target row can mount.
      await SchedulerBinding.instance.endOfFrame;
      final BuildContext? targetContext =
          _messageKeys[messageId]?.currentContext;
      if (targetContext == null) {
        await Future.delayed(_kContextFindDelay);
        continue;
      }

      await Scrollable.ensureVisible(
        targetContext,
        duration: _kEnsureVisibleDuration,
        curve: Curves.easeInOutCubic,
        alignment: _kMessageScrollAlignment,
      );
      _highlightMessage(messageId);
      return;
    }

    _highlightMessage(messageId);
  }

  Future<void> _handleReplyPreviewTap(Map<String, dynamic>? replyTo) async {
    final String messageId = _replyTargetMessageId(replyTo);
    if (messageId.isEmpty) return;
    await _scrollToMessage(messageId);
  }

  Future<void> _sendMatchProfile(Map<String, dynamic> profileData) async {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    final receiverId = chatProvider.id?.toString();
    if (receiverId == null || receiverId.isEmpty) return;

    try {
      final connected = await _socketService.ensureConnected();
      if (!connected) throw Exception('Socket not connected');
      _socketService.sendMessage(
        chatRoomId: AdminSocketService.chatRoomId(receiverId),
        receiverId: receiverId,
        message: jsonEncode(profileData),
        messageType: 'profile_card',
        messageId: 'profile_${DateTime.now().millisecondsSinceEpoch}_$senderId',
        receiverName: chatProvider.namee,
        receiverImage: chatProvider.profilePicture,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Failed to send match profile")));
    }
  }

  // ── CALL OVERLAY HELPERS ─────────────────────────────────────────────────

  /// Remove the active call overlay and clean up.
  void _removeCallOverlay() {
    _callOverlayEntry?.remove();
    _callOverlayEntry = null;
  }

  void _removeCallWaitingBanner() {
    _callWaitingBannerEntry?.remove();
    _callWaitingBannerEntry = null;
  }

  /// Show a dialog to select a user to add to the ongoing call.
  /// Returns the selected user ID or null if cancelled.
  /// Shows a searchable dialog to pick a user to add to the ongoing call.
  /// Returns `{'id': userId, 'name': userName}` on selection, or null on cancel.
  /// Fetches all users from the API, sorted online-first.
  /// Excludes [excludeId] from the list (usually the current participant).
  /// Returns the list and any error string.
  Future<(List<Map<String, dynamic>>, String?)>
  _fetchAllUsersSortedOnlineFirst({String? excludeId}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? '';
      final response = await http.get(
        Uri.parse('$kAdminApi9BaseUrl/get_users.php'),
        headers: {
          'Content-Type': 'application/json',
          if (token.isNotEmpty) 'Authorization': 'Bearer $token',
        },
      );
      if (response.statusCode != 200) {
        return (
          const <Map<String, dynamic>>[],
          'Failed to load users (${response.statusCode})',
        );
      }
      final data = jsonDecode(response.body);
      List<Map<String, dynamic>>
      users = ((data['data'] as List<dynamic>?) ?? [])
          .where((u) => excludeId == null || u['id']?.toString() != excludeId)
          .map((u) {
            final raw = Map<String, dynamic>.from(u as Map);
            // Prefer the real-time isOnline returned by the updated API.
            raw['_isOnline'] =
                raw['isOnline'] == 1 ||
                raw['isOnline'] == '1' ||
                raw['isOnline'] == true;
            // Parse lastSeen from the API's lastSeen field (ISO-8601 string or null).
            final lastSeenRaw = raw['lastSeen']?.toString();
            raw['_lastSeen'] = (lastSeenRaw != null && lastSeenRaw.isNotEmpty)
                ? DateTime.tryParse(lastSeenRaw)
                : null;
            // Build a combined display name with both first and full names.
            final firstName = (raw['firstName'] ?? '').toString().trim();
            final lastName = (raw['lastName'] ?? '').toString().trim();
            raw['_firstName'] = firstName;
            raw['_fullName'] = [
              firstName,
              lastName,
            ].where((s) => s.isNotEmpty).join(' ');
            return raw;
          })
          .toList();

      // Sort: online users first, then by lastSeen DESC, then alphabetically.
      users.sort((a, b) {
        final aOnline = a['_isOnline'] as bool;
        final bOnline = b['_isOnline'] as bool;
        if (aOnline && !bOnline) return -1;
        if (!aOnline && bOnline) return 1;
        // Among users with the same online state, most-recently-seen first.
        final aLastSeen = a['_lastSeen'] as DateTime?;
        final bLastSeen = b['_lastSeen'] as DateTime?;
        if (aLastSeen != null && bLastSeen != null) {
          final cmp = bLastSeen.compareTo(aLastSeen);
          if (cmp != 0) return cmp;
        } else if (aLastSeen != null) {
          return -1;
        } else if (bLastSeen != null) {
          return 1;
        }
        return (a['_firstName'] as String).compareTo(b['_firstName'] as String);
      });

      return (users, null);
    } catch (_) {
      return (const <Map<String, dynamic>>[], 'Error loading users');
    }
  }

  Future<Map<String, String>?> _showAddParticipantDialog(
    String currentParticipantId,
  ) async {
    final (allUsers, fetchError) = await _fetchAllUsersSortedOnlineFirst(
      excludeId: currentParticipantId,
    );

    if (!mounted) return null;

    if (fetchError != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(fetchError)));
      return null;
    }

    return await showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _AddParticipantDialog(allUsers: allUsers),
    );
  }

  /// Shows a multi-select participant picker for starting a group call.
  /// Returns a list of selected users [{id, name (first name only)}].
  Future<List<Map<String, String>>?> _showGroupCallParticipantPicker() async {
    final (allUsers, fetchError) = await _fetchAllUsersSortedOnlineFirst();

    if (!mounted) return null;

    if (fetchError != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(fetchError)));
      return null;
    }

    if (allUsers.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No users available')));
      return null;
    }

    return await showDialog<List<Map<String, String>>>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _GroupCallParticipantPicker(allUsers: allUsers),
    );
  }

  /// Start a group call: opens participant picker, then launches the dedicated
  /// [GroupCallScreen] which handles all participants natively.
  void _launchGroupCall(ChatProvider chatProvider, {required bool isVideo}) {
    if (_callOverlayEntry != null) return; // call already active
    _showGroupCallParticipantPicker().then((selected) {
      if (selected == null || selected.isEmpty) return;
      if (!mounted) return;

      final isMinimizedNotifier = ValueNotifier<bool>(false);

      void onCallEnded(String callType, String status, int durationSeconds) {
        _removeCallOverlay();
        // Save history for the first selected user as the primary contact.
        if (selected.isNotEmpty) {
          _saveCallHistory(
            selected.first['id']!,
            callType,
            status,
            durationSeconds,
          );
        }
      }

      _callOverlayEntry = OverlayEntry(
        builder: (ctx) => ValueListenableBuilder<bool>(
          valueListenable: isMinimizedNotifier,
          builder: (_, isMin, __) {
            final groupCallWidget = GroupCallScreen(
              adminId: kAdminUserId,
              adminName: 'Admin',
              initialParticipants: selected,
              isVideo: isVideo,
              onMinimize: () => isMinimizedNotifier.value = true,
              onEnd: _removeCallOverlay,
              onCallEnded: onCallEnded,
            );

            return Stack(
              children: [
                Offstage(offstage: isMin, child: groupCallWidget),
                if (isMin)
                  _buildMiniCallBar(
                    userName: selected.length == 1
                        ? (selected.first['name'] ?? '')
                        : '${selected.first['name'] ?? ''} +${selected.length - 1}',
                    isVideo: isVideo,
                    onMaximize: () => isMinimizedNotifier.value = false,
                    onEnd: _removeCallOverlay,
                  ),
              ],
            );
          },
        ),
      );
      Overlay.of(context).insert(_callOverlayEntry!);
    });
  }

  /// Launch a call (video or audio) in a floating overlay so the admin can
  /// minimize it and continue browsing other conversations without ending it.
  void _launchCall(ChatProvider chatProvider, {required bool isVideo}) {
    if (_callOverlayEntry != null) return; // call already active

    final userId = chatProvider.id.toString();
    final userName = chatProvider.namee.toString();
    final isMinimizedNotifier = ValueNotifier<bool>(false);

    void onCallEnded(String callType, String status, int durationSeconds) {
      _removeCallOverlay();
      _saveCallHistory(userId, callType, status, durationSeconds);
    }

    _callOverlayEntry = OverlayEntry(
      builder: (ctx) => ValueListenableBuilder<bool>(
        valueListenable: isMinimizedNotifier,
        builder: (_, isMin, __) {
          final callWidget = isVideo
              ? VideoCallScreen(
                  currentUserId: '1',
                  currentUserName: 'Admin',
                  otherUserId: userId,
                  otherUserName: userName,
                  onMinimize: () => isMinimizedNotifier.value = true,
                  onEnd: _removeCallOverlay,
                  onCallEnded: onCallEnded,
                  onAddParticipant: () => _showAddParticipantDialog(userId),
                )
              : CallScreen(
                  currentUserId: '1',
                  currentUserName: 'Admin',
                  otherUserId: userId,
                  otherUserName: userName,
                  onMinimize: () => isMinimizedNotifier.value = true,
                  onEnd: _removeCallOverlay,
                  onCallEnded: onCallEnded,
                  onAddParticipant: () => _showAddParticipantDialog(userId),
                );

          return Stack(
            children: [
              // Full-screen call – kept alive via Offstage while minimized
              Offstage(offstage: isMin, child: callWidget),
              // Floating mini-bar shown when minimized
              if (isMin)
                _buildMiniCallBar(
                  userName: userName,
                  isVideo: isVideo,
                  onMaximize: () => isMinimizedNotifier.value = false,
                  onEnd: _removeCallOverlay,
                ),
            ],
          );
        },
      ),
    );
    Overlay.of(context).insert(_callOverlayEntry!);
  }

  void _launchVideoCall(ChatProvider chatProvider) =>
      _launchCall(chatProvider, isVideo: true);

  void _launchAudioCall(ChatProvider chatProvider) =>
      _launchCall(chatProvider, isVideo: false);

  /// A compact floating bar shown at the bottom-right when the call is
  /// minimized.  The admin can tap it to expand back or end the call.
  Widget _buildMiniCallBar({
    required String userName,
    required bool isVideo,
    required VoidCallback onMaximize,
    required VoidCallback onEnd,
  }) {
    return Positioned(
      bottom: 24,
      right: 24,
      child: Material(
        color: Colors.transparent,
        child: GestureDetector(
          onTap: onMaximize,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(40),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: const BoxDecoration(
                    color: Color(0xFF22C55E),
                    shape: BoxShape.circle,
                  ),
                ),
                Icon(
                  isVideo ? Icons.videocam : Icons.call,
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  userName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: onEnd,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.call_end,
                      color: Colors.white,
                      size: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: onMaximize,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.open_in_full,
                      color: Colors.white,
                      size: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── PROFILE SHEET HELPERS ────────────────────────────────────────────

  /// Returns shared photos from messages sent by the user (not admin) in this chat.
  List<_AdminSharedPhoto> _getAdminSharedPhotos() {
    final List<_AdminSharedPhoto> photos = [];
    for (final msg in _messages) {
      if (msg['senderid'] == senderId.toString()) continue;
      final String messageId = msg['messageid']?.toString() ?? '';
      final type = msg['type']?.toString() ?? 'text';
      if (type == 'image') {
        final imageUrl = msg['imageUrl']?.toString() ?? '';
        if (imageUrl.isNotEmpty) {
          photos.add(_AdminSharedPhoto(url: imageUrl, messageId: messageId));
        }
      } else if (type == 'image_gallery') {
        final raw = msg['message']?.toString() ?? '';
        try {
          final decoded = jsonDecode(raw);
          if (decoded is List) {
            for (final u in decoded) {
              if (u is String && u.isNotEmpty) {
                photos.add(_AdminSharedPhoto(url: u, messageId: messageId));
              }
            }
          }
        } catch (_) {}
      }
    }
    return photos;
  }

  /// Shows a mini-profile bottom sheet for the selected user.
  void _showUserProfileSheet(BuildContext context, ChatProvider chatProvider) {
    final int? userId = chatProvider.id;
    if (userId == null) return;
    final List<_AdminSharedPhoto> sharedPhotos = _getAdminSharedPhotos();
    final String name = chatProvider.namee ?? 'User';
    final String? avatarUrl = chatProvider.profilePicture;
    final bool isOnline = chatProvider.online;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AdminUserProfileSheet(
        userId: userId,
        name: name,
        avatarUrl: avatarUrl,
        isOnline: isOnline,
        isPaid: chatProvider.ispaid,
        sharedPhotos: sharedPhotos,
        onViewProfile: _openProfileInNewTab,
        onDeleteMessage: _deleteMessage,
      ),
    );
  }

  // ── ICON BUTTON HELPER ────────────────────────────────────────────
  Widget _iconBtn({
    required IconData icon,
    required VoidCallback onTap,
    bool active = false,
    Color? iconColor,
  }) {
    final c = ChatColors.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: active ? c.primaryLight : c.searchFill,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          size: 18,
          color: iconColor ?? (active ? c.primary : c.muted),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = ChatColors.of(context);

    final chatProvider = Provider.of<ChatProvider>(context);

    // Reset the room-backed message state only when the selected user changes
    // so the chat view swaps conversations without stale pagination state.
    final bool userChanged = chatProvider.id != _cachedReceiverId;
    if (userChanged) {
      _cachedReceiverId = chatProvider.id;
      _hasMoreMessages = true;
      _suppressNextAutoScroll = false;
      _messageKeys.clear();
      _messageIndexMap.clear();
      _replyHighlightTimer?.cancel();
      _highlightedMessageId = null;
      // Clear any active reply / edit state so the input bar starts fresh.
      _replyingTo = null;
      _editingMessageId = null;
      _editingOriginalText = '';
      _messageController.clear();
      // Re-fetch match details for the newly selected user
      if (chatProvider.id != null) Future.microtask(_fetchMatchDetails);
      // Reset user-typing state and subscribe to new user's typing status.
      _userIsTyping = false;
      if (chatProvider.id != null)
        Future.microtask(() => _setupTypingListener(chatProvider.id!));
      // Clear admin typing status for the previous user.
      Future.microtask(_clearAdminTypingStatus);
      // Auto-focus the message input so the admin can type immediately.
      Future.microtask(() {
        if (mounted) FocusScope.of(context).requestFocus(_messageFocusNode);
      });
      // Leave previous room and join new one, then reload messages.
      if (chatProvider.id != null) {
        Future.microtask(() => _loadMessages(reset: true));
      }
    }

    return Scaffold(
      backgroundColor: c.bg,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: Container(
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: c.header,
            border: Border(bottom: BorderSide(color: c.border, width: 1)),
          ),
          child: Row(
            children: [
              // Back button (mobile only — shown when onBack callback is provided)
              if (widget.onBack != null) ...[
                SizedBox(
                  width: 32,
                  height: 32,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: widget.onBack,
                      borderRadius: BorderRadius.circular(8),
                      child: Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 18,
                        color: c.muted,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              // Avatar + paid badge (tappable to open mini-profile sheet)
              GestureDetector(
                onTap: () => _showUserProfileSheet(context, chatProvider),
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: const Color(0xFFF1F5F9),
                      backgroundImage:
                          chatProvider.profilePicture != null &&
                              chatProvider.profilePicture!.isNotEmpty
                          ? NetworkImage(chatProvider.profilePicture!)
                          : null,
                      child:
                          chatProvider.profilePicture == null ||
                              chatProvider.profilePicture!.isEmpty
                          ? Icon(
                              Icons.person,
                              size: 18,
                              color: Colors.grey[400],
                            )
                          : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),

              // Name + status (tappable to open mini-profile sheet)
              Expanded(
                child: GestureDetector(
                  onTap: () => _showUserProfileSheet(context, chatProvider),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              chatProvider.namee.toString(),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: chatProvider.ispaid ? c.primary : c.text,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (chatProvider.matchesCount != null &&
                              chatProvider.matchesCount! > 0)
                            Container(
                              margin: const EdgeInsets.only(left: 6),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: c.primaryLight,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.favorite,
                                    color: c.primary,
                                    size: 10,
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    '${chatProvider.matchesCount}',
                                    style: TextStyle(
                                      color: c.primary,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            margin: const EdgeInsets.only(right: 4),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: chatProvider.online ? c.online : c.muted,
                            ),
                          ),
                          Text(
                            chatProvider.online ? "Online" : "Offline",
                            style: TextStyle(
                              fontSize: 11,
                              color: chatProvider.online ? c.online : c.muted,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // Action buttons
              _iconBtn(
                icon: _showMatchInfo ? Icons.favorite : Icons.favorite_border,
                active: _showMatchInfo,
                iconColor: _showMatchInfo ? c.primary : c.muted,
                onTap: () => setState(() => _showMatchInfo = !_showMatchInfo),
              ),
              const SizedBox(width: 6),
              _iconBtn(
                icon: Icons.video_call_outlined,
                iconColor: c.primary,
                onTap: () => _launchVideoCall(chatProvider),
              ),
              const SizedBox(width: 6),
              _iconBtn(
                icon: Icons.call_outlined,
                iconColor: const Color(0xFF334155),
                onTap: () => _launchAudioCall(chatProvider),
              ),
              const SizedBox(width: 6),
              // Group Call button — opens multi-select picker and starts a
              // group audio/video call with all selected participants.
              Tooltip(
                message: 'Start Group Call',
                child: InkWell(
                  onTap: () => _launchGroupCall(chatProvider, isVideo: false),
                  onLongPress: () =>
                      _launchGroupCall(chatProvider, isVideo: true),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF7B61FF).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.groups_outlined, size: 18, color: c.primary),
                        const SizedBox(width: 2),
                        Icon(Icons.call_outlined, size: 12, color: c.primary),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              _iconBtn(
                icon: _isSearching ? Icons.close : Icons.search,
                active: _isSearching,
                onTap: () {
                  setState(() {
                    _isSearching = !_isSearching;
                    if (!_isSearching) {
                      _searchController.clear();
                      _filteredMessages.clear();
                    }
                  });
                },
              ),
              const SizedBox(width: 6),
              _iconBtn(
                icon: Icons.notifications_outlined,
                iconColor: c.muted,
                onTap: () {},
              ),
            ],
          ),
        ),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              if (_isSearching)
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: SizedBox(
                    height: 38,
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: "Search messages...",
                        hintStyle: TextStyle(fontSize: 12, color: c.muted),
                        prefixIcon: Icon(
                          Icons.search,
                          size: 16,
                          color: c.muted,
                        ),
                        filled: true,
                        fillColor: c.searchFill,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide(color: c.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide(color: c.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide(color: c.primary),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 0,
                          horizontal: 12,
                        ),
                        isDense: true,
                      ),
                      onChanged: _searchMessages,
                    ),
                  ),
                ),

              // Match info panel
              if (_showMatchInfo) _buildMatchInfoPanel(chatProvider),

              Expanded(
                child: Stack(
                  children: [
                    Builder(
                      builder: (context) {
                        final isActiveSearch =
                            _isSearching && _searchController.text.isNotEmpty;
                        final messages = isActiveSearch
                            ? _filteredMessages
                            : _messages;

                        if (_isInitialLoad) {
                          return Center(
                            child: CircularProgressIndicator(color: c.primary),
                          );
                        }

                        if (messages.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.chat_bubble_outline,
                                  size: 40,
                                  color: Colors.grey[300],
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  isActiveSearch
                                      ? "No matching messages"
                                      : "No messages yet",
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: c.muted,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  isActiveSearch
                                      ? "Try a different keyword"
                                      : "Start a conversation!",
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: c.muted,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        final itemCount = messages.length;
                        final activeMessageIds = messages
                            .map((m) => m['messageId'] as String)
                            .toSet();
                        for (final messageId in _messageKeys.keys.toList()) {
                          if (!activeMessageIds.contains(messageId)) {
                            _messageKeys.remove(messageId);
                          }
                        }
                        _messageIndexMap
                          ..clear()
                          ..addEntries(
                            List.generate(
                              itemCount,
                              (i) => MapEntry(
                                messages[i]['messageId'] as String,
                                i,
                              ),
                            ),
                          );
                        final messageGroups = _groupMessagesByDate(messages);
                        _currentMessageGroups = messageGroups;

                        return Opacity(
                          // Hide the list while the scroll position is being set to
                          // the bottom on first load (WhatsApp-style instant positioning).
                          // The CustomScrollView stays in the tree so the controller
                          // remains attached and jumpTo works correctly.
                          opacity: _scrollLocked ? 0.0 : 1.0,
                          child: NotificationListener<ScrollUpdateNotification>(
                            onNotification: (notification) {
                              final offset = _scrollController.hasClients
                                  ? _scrollController.offset
                                  : 0.0;
                              final label = _dateGroupAtScrollOffset(
                                offset,
                                _currentMessageGroups,
                              );
                              if (label != null) _showFloatingDateLabel(label);
                              return false;
                            },
                            child: CustomScrollView(
                              controller: _scrollController,
                              // Use ClampingScrollPhysics to prevent bounce effect that causes shaking
                              physics: _isHorizontalDragging
                                  ? const NeverScrollableScrollPhysics()
                                  : const ClampingScrollPhysics(),
                              slivers: [
                                if (_hasMoreMessages || _isLoadingMore)
                                  SliverToBoxAdapter(
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        12,
                                        12,
                                        12,
                                        4,
                                      ),
                                      child: Center(
                                        child: _isLoadingMore
                                            ? SizedBox(
                                                width: 20,
                                                height: 20,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      color: c.primary,
                                                    ),
                                              )
                                            : TextButton.icon(
                                                onPressed: _loadMoreMessages,
                                                icon: Icon(
                                                  Icons.history,
                                                  size: 14,
                                                  color: c.primary,
                                                ),
                                                label: Text(
                                                  'Load older messages',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: c.primary,
                                                  ),
                                                ),
                                              ),
                                      ),
                                    ),
                                  ),
                                for (final group in messageGroups) ...[
                                  SliverPersistentHeader(
                                    pinned: false,
                                    delegate: _ChatDateHeaderDelegate(
                                      label: group.headerLabel,
                                      backgroundColor: c.bg,
                                      chipColor: c.primaryLight,
                                      textColor: c.text,
                                      borderColor: c.border,
                                    ),
                                  ),
                                  SliverPadding(
                                    padding: const EdgeInsets.fromLTRB(
                                      12,
                                      0,
                                      12,
                                      14,
                                    ),
                                    sliver: SliverList(
                                      delegate: SliverChildBuilderDelegate((
                                        context,
                                        index,
                                      ) {
                                        final data = group.messages[index];
                                        final String msgId =
                                            data['messageId'] as String;
                                        final isSentByAdmin =
                                            data['senderid'] ==
                                            senderId.toString();
                                        final isSentByUser = !isSentByAdmin;
                                        final timestamp =
                                            _messageTimestampFromData(data);
                                        final replyPayload = _buildReplyPayload(
                                          messageId: msgId,
                                          data: data,
                                          senderId: isSentByAdmin
                                              ? senderId.toString()
                                              : (chatProvider.id?.toString() ??
                                                    ''),
                                          senderName: isSentByAdmin
                                              ? 'You'
                                              : (chatProvider.namee ?? 'User'),
                                        );
                                        final canEdit = _canEditMessage(
                                          data,
                                          isSentByAdmin,
                                        );
                                        final canMutate = _canMutateMessage(
                                          data,
                                          isSentByAdmin,
                                        );

                                        return _AdminSwipeToReplyWrapper(
                                          key: ValueKey(msgId),
                                          isMine: isSentByAdmin,
                                          onReply: () => _startReply(
                                            msgId,
                                            replyPayload['message']
                                                    ?.toString() ??
                                                '',
                                            replyPayload['senderid']
                                                    ?.toString() ??
                                                '',
                                            replyPayload['senderName']
                                                    ?.toString() ??
                                                'User',
                                            replyPayload,
                                          ),
                                          onDragStart: () {
                                            if (mounted) {
                                              setState(
                                                () => _isHorizontalDragging =
                                                    true,
                                              );
                                            }
                                          },
                                          onDragEnd: () {
                                            if (mounted) {
                                              setState(
                                                () => _isHorizontalDragging =
                                                    false,
                                              );
                                            }
                                          },
                                          child: GestureDetector(
                                            onLongPressStart: (details) {
                                              if (mounted) {
                                                setState(() {
                                                  _overlayMessageId = msgId;
                                                  _overlayReplyPayload =
                                                      replyPayload;
                                                  _overlayIsSentByMe =
                                                      isSentByAdmin;
                                                  _overlayCanEdit = canEdit;
                                                  _overlayCanMutate = canMutate;
                                                  _overlayTapOffset =
                                                      details.globalPosition;
                                                  _showMsgActionOverlay = true;
                                                });
                                              }
                                            },
                                            child: Builder(
                                              builder: (_) {
                                                final Map<String, dynamic>
                                                reactions =
                                                    (data['reactions'] is Map)
                                                    ? Map<String, dynamic>.from(
                                                        data['reactions']
                                                            as Map,
                                                      )
                                                    : {};

                                                // The admin (paid member) always sees all messages in full.
                                                // Message masking for free users is applied in the
                                                // user-facing app, not here in the admin panel.
                                                const bool isMasked = false;
                                                final String bubbleMessage =
                                                    isMasked
                                                    ? _kMaskedMessageText
                                                    : data['message'];
                                                final String? bubbleType =
                                                    isMasked
                                                    ? 'text'
                                                    : data['type'];
                                                final Map<String, dynamic>?
                                                bubbleProfileData = isMasked
                                                    ? null
                                                    : (data.containsKey(
                                                            'profileData',
                                                          )
                                                          ? data['profileData']
                                                          : null);
                                                final String? bubbleImageUrl =
                                                    isMasked
                                                    ? null
                                                    : (data.containsKey(
                                                            'imageUrl',
                                                          )
                                                          ? data['imageUrl']
                                                          : null);
                                                final Map<String, dynamic>?
                                                bubbleReportData = isMasked
                                                    ? null
                                                    : (data.containsKey(
                                                            'reportData',
                                                          )
                                                          ? data['reportData']
                                                                as Map<
                                                                  String,
                                                                  dynamic
                                                                >
                                                          : null);

                                                return Column(
                                                  crossAxisAlignment:
                                                      isSentByAdmin
                                                      ? CrossAxisAlignment.end
                                                      : CrossAxisAlignment
                                                            .start,
                                                  children: [
                                                    _HighlightableMessageContainer(
                                                      key: _messageKeyFor(
                                                        msgId,
                                                      ),
                                                      isHighlighted:
                                                          _highlightedMessageId ==
                                                          msgId,
                                                      child: _buildChatBubble(
                                                        bubbleMessage,
                                                        isSentByAdmin,
                                                        timestamp,
                                                        bubbleType,
                                                        bubbleProfileData,
                                                        bubbleImageUrl,
                                                        data['seen'] == true,
                                                        data['callType']
                                                            ?.toString(),
                                                        data['callStatus']
                                                            ?.toString(),
                                                        (data['callDuration']
                                                                    as num?)
                                                                ?.toInt() ??
                                                            0,
                                                        msgId,
                                                        data['replyto']
                                                                is Map<
                                                                  String,
                                                                  dynamic
                                                                >
                                                            ? data['replyto']
                                                                  as Map<
                                                                    String,
                                                                    dynamic
                                                                  >
                                                            : null,
                                                        data['edited'] == true,
                                                        data['deleted'] == true,
                                                        data['unsent'] == true,
                                                        canEdit,
                                                        canMutate,
                                                        replyPayload,
                                                        bubbleReportData,
                                                      ),
                                                    ),
                                                    if (reactions.isNotEmpty)
                                                      _buildAdminReactionBadge(
                                                        reactions,
                                                        isSentByAdmin,
                                                      ),
                                                  ],
                                                );
                                              },
                                            ),
                                          ),
                                        );
                                      }, childCount: group.messages.length),
                                    ),
                                  ),
                                ],
                                const SliverToBoxAdapter(
                                  child: SizedBox(height: 12),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    // WhatsApp-style floating date indicator
                    Positioned(
                      top: 8,
                      left: 0,
                      right: 0,
                      child: ValueListenableBuilder<String?>(
                        valueListenable: _floatingDateNotifier,
                        builder: (context, label, _) {
                          if (label == null) return const SizedBox.shrink();
                          return Center(
                            child: IgnorePointer(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: c.primaryLight,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: c.border,
                                    width: 0.5,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.08),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Text(
                                  label,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: c.text,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              if (_userIsTyping)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(left: 12, bottom: 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: c.selectedRow,
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
              _buildMessageInput(chatProvider),
            ],
          ),
          if (_showMsgActionOverlay) _buildMsgActionOverlay(context),
        ],
      ),
    );
  }

  Widget _buildMatchInfoPanel(ChatProvider chatProvider) {
    final c = ChatColors.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.selectedRow,
        border: Border(bottom: BorderSide(color: c.primaryLight, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.favorite, color: c.primary, size: 16),
              const SizedBox(width: 6),
              Text(
                'Match Information',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: c.primary,
                ),
              ),
              const Spacer(),
              if (_isLoadingMatchDetails)
                SizedBox(
                  height: 14,
                  width: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: c.primary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),

          if (_matchDetails != null && _matchDetails!['percentage'] != null)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: c.cardBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Match Score: ',
                    style: TextStyle(fontSize: 12, color: c.muted),
                  ),
                  Text(
                    '${_matchDetails!['percentage']}%',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: c.primary,
                    ),
                  ),
                ],
              ),
            ),

          if (_matchDetails != null &&
              _matchDetails!['commonInterests'] != null)
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: (_matchDetails!['commonInterests'] as List).map((
                interest,
              ) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: c.primaryLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    interest,
                    style: TextStyle(fontSize: 10, color: c.primary),
                  ),
                );
              }).toList(),
            ),

          if (_mutualMatches.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Mutual Matches:',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: c.muted,
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 50,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _mutualMatches.length,
                itemBuilder: (context, index) {
                  final match = _mutualMatches[index];
                  return Container(
                    margin: const EdgeInsets.only(right: 8),
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: const Color(0xFFF1F5F9),
                          backgroundImage:
                              match['profile_picture'] != null &&
                                  match['profile_picture'].toString().isNotEmpty
                              ? NetworkImage(match['profile_picture'])
                              : null,
                          child:
                              match['profile_picture'] == null ||
                                  match['profile_picture'].toString().isEmpty
                              ? Icon(
                                  Icons.person,
                                  size: 16,
                                  color: Colors.grey[400],
                                )
                              : null,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          match['name'] ?? '',
                          style: TextStyle(fontSize: 8, color: c.muted),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],

          if (chatProvider.matchesCount != null &&
              chatProvider.matchesCount! > 0)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _showMatchSelectionDialog(chatProvider),
                icon: const Icon(Icons.send, size: 12),
                label: const Text(
                  'Send Match Profile',
                  style: TextStyle(fontSize: 11),
                ),
                style: TextButton.styleFrom(
                  backgroundColor: c.primaryLight,
                  foregroundColor: c.primary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  minimumSize: const Size(0, 28),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showMatchSelectionDialog(ChatProvider chatProvider) {
    chatProvider.fetchUserMatches(chatProvider.id ?? 0);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Select Match Profile', style: TextStyle(fontSize: 16)),
          content: Container(
            width: double.maxFinite,
            height: 300,
            child: Consumer<ChatProvider>(
              builder: (context, provider, _) {
                if (provider.isLoadingMatches) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (provider.matchError != null) {
                  return Center(child: Text(provider.matchError!));
                }

                final matches = provider.matchedProfiles;
                if (matches.isEmpty) {
                  return const Center(child: Text('No matches found'));
                }

                return ListView.builder(
                  itemCount: matches.length,
                  itemBuilder: (context, index) {
                    final match = matches[index];
                    return ListTile(
                      leading: CircleAvatar(
                        radius: 20,
                        backgroundColor: Colors.grey[300],
                        backgroundImage:
                            match['profile_picture'] != null &&
                                match['profile_picture'].toString().isNotEmpty
                            ? NetworkImage(match['profile_picture'])
                            : null,
                        child:
                            match['profile_picture'] == null ||
                                match['profile_picture'].toString().isEmpty
                            ? Icon(Icons.person, color: Colors.grey[700])
                            : null,
                      ),
                      title: Text(match['name']?.toString() ?? 'Unknown'),
                      subtitle: Text('Match: ${match['percentage'] ?? 'N/A'}%'),
                      onTap: () {
                        Navigator.pop(context);
                        _sendMatchProfile(match);
                      },
                    );
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  void openUrl(String url) {
    html.window.open(url, '_blank');
  }

  void _openProfileInNewTab(BuildContext context, int userId) {
    try {
      // Store userId in session storage for the new tab to read
      html.window.sessionStorage['pendingProfileView'] = userId.toString();

      // Open current URL in new tab - the app will check session storage on load
      final currentUrl = html.window.location.href.split('#')[0];
      final newWindow = html.window.open(
        '$currentUrl#profile/$userId',
        '_blank',
      );

      if (newWindow == null) {
        // Popup was blocked, fall back to same window navigation
        html.window.sessionStorage.remove('pendingProfileView');
        _navigateToProfile(context, userId);
      } else {
        // Successfully opened in new tab
        // Also show a brief message that profile opened in new tab
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile opened in new tab'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      // If there's any error, fall back to same window navigation
      _navigateToProfile(context, userId);
    }
  }

  void _navigateToProfile(BuildContext context, int userId) {
    // Navigate to the user profile screen with proper provider setup
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider(
          create: (_) => UserDetailsProvider(),
          child: UserDetailsScreen(userId: userId, myId: 1),
        ),
      ),
    );
  }

  DateTime _dateOnly(DateTime dateTime) =>
      DateTime(dateTime.year, dateTime.month, dateTime.day);

  DateTime _messageTimestampFromData(
    Map<String, dynamic> data, {
    DateTime? fallback,
  }) {
    return AdminSocketService.parseTimestamp(data['timestamp']) ??
        fallback ??
        DateTime.now();
  }

  bool _isToday(DateTime dateTime, [DateTime? reference]) {
    final now = reference ?? DateTime.now();
    return _dateOnly(dateTime) == _dateOnly(now);
  }

  bool _isYesterday(DateTime dateTime, [DateTime? reference]) {
    final yesterday = _dateOnly(
      reference ?? DateTime.now(),
    ).subtract(const Duration(days: 1));
    return _dateOnly(dateTime) == yesterday;
  }

  String _formatDateHeader(DateTime dateTime, [DateTime? reference]) {
    final now = reference ?? DateTime.now();
    if (_isToday(dateTime, now)) return 'Today';
    if (_isYesterday(dateTime, now)) return 'Yesterday';
    return DateFormat('MMM d, y').format(dateTime);
  }

  List<Map<String, dynamic>> _sortMessagesChronologically(
    List<Map<String, dynamic>> messages,
  ) {
    final sorted = List<Map<String, dynamic>>.from(messages);
    final fallbackTimestamp = DateTime.now();
    sorted.sort((a, b) {
      final aTimestamp = _messageTimestampFromData(
        a,
        fallback: fallbackTimestamp,
      );
      final bTimestamp = _messageTimestampFromData(
        b,
        fallback: fallbackTimestamp,
      );
      return aTimestamp.compareTo(bTimestamp);
    });
    return sorted;
  }

  List<_ChatMessageDateGroup> _groupMessagesByDate(
    List<Map<String, dynamic>> messages,
  ) {
    final groups = <_ChatMessageDateGroup>[];
    final fallbackTimestamp = DateTime.now();
    final referenceNow = DateTime.now();

    for (final data in _sortMessagesChronologically(messages)) {
      final timestamp = _messageTimestampFromData(
        data,
        fallback: fallbackTimestamp,
      );
      final date = _dateOnly(timestamp);

      if (groups.isEmpty || groups.last.date != date) {
        groups.add(
          _ChatMessageDateGroup(
            date: date,
            headerLabel: _formatDateHeader(timestamp, referenceNow),
            messages: [data],
          ),
        );
      } else {
        groups.last.messages.add(data);
      }
    }

    return groups;
  }

  /// Returns the headerLabel of the date group that is visible near the top of
  /// the viewport given the current [offset] and the rendered [groups].
  String? _dateGroupAtScrollOffset(
    double offset,
    List<_ChatMessageDateGroup> groups,
  ) {
    if (groups.isEmpty) return null;
    const double msgH = _kEstimatedMessageExtent;
    double pos = 0;
    for (final group in groups) {
      final groupH = _kDateHeaderExtent + group.messages.length * msgH;
      if (offset < pos + groupH) return group.headerLabel;
      pos += groupH;
    }
    return groups.last.headerLabel;
  }

  void _showFloatingDateLabel(String label) {
    _floatingDateTimer?.cancel();
    _floatingDateNotifier.value = label;
    _floatingDateTimer = Timer(const Duration(seconds: 2), () {
      _floatingDateNotifier.value = null;
    });
  }

  bool _shouldAutoScrollToBottom({
    required bool hasSnapshotData,
    required bool isSearching,
    required int previousCount,
    required int currentCount,
  }) {
    if (isSearching || _isLoadingMore || !hasSnapshotData) {
      return false;
    }

    if (_suppressNextAutoScroll) {
      return false;
    }

    if (!_scrollController.hasClients) {
      // The first layout pass has not attached the controller yet; schedule a
      // deferred scroll so the view still lands on the latest messages.
      return true;
    }

    if (previousCount != currentCount) {
      return true;
    }

    final distanceFromBottom =
        _scrollController.position.maxScrollExtent - _scrollController.offset;
    return distanceFromBottom <= _autoScrollThreshold;
  }

  Widget _buildChatBubble(
    String message,
    bool isSentByMe,
    DateTime timestamp, [
    String? type,
    Map<String, dynamic>? profileData,
    String? imageUrl,
    bool seen = false,
    String? callType,
    String? callStatus,
    int callDuration = 0,
    String? messageId,
    Map<String, dynamic>? replyTo,
    bool edited = false,
    bool deleted = false,
    bool unsent = false,
    bool canEdit = false,
    bool canMutate = false,
    Map<String, dynamic>? replyPayload,
    Map<String, dynamic>? reportData,
  ]) {
    const kPrimary = Color(0xFF7B61FF);
    const kText = Color(0xFF1E293B);
    const kMuted = Color(0xFF64748B);
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    final replyPreview = _buildReplyPreview(
      replyTo: replyTo,
      isSentByMe: isSentByMe,
      mutedColor: kMuted,
      primaryColor: kPrimary,
    );

    final statusMessage = deleted
        ? _kDeletedMessageText
        : (unsent ? _kUnsentMessageText : null);
    final displayedMessage = statusMessage ?? message;
    final showEditedLabel = edited && statusMessage == null;

    Widget footer({bool includeSeen = true}) {
      return Padding(
        padding: const EdgeInsets.only(right: 8, left: 8, bottom: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showEditedLabel) ...[
              const Text(
                'Edited',
                style: TextStyle(
                  fontSize: 10,
                  color: kMuted,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(width: 4),
            ],
            Text(
              DateFormat('hh:mm a').format(timestamp),
              style: const TextStyle(fontSize: 10, color: kMuted),
            ),
            if (includeSeen && isSentByMe) ...[
              const SizedBox(width: 3),
              _buildSeenTick(seen),
            ],
          ],
        ),
      );
    }

    if (type == 'call') {
      final callBubble = statusMessage != null
          ? Column(
              crossAxisAlignment: isSentByMe
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (replyPreview != null) replyPreview,
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  margin: const EdgeInsets.symmetric(
                    vertical: 3,
                    horizontal: 6,
                  ),
                  decoration: BoxDecoration(
                    color: isSentByMe ? kPrimary : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    displayedMessage,
                    style: TextStyle(
                      color: isSentByMe ? Colors.white : kText,
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
                footer(),
              ],
            )
          : _buildCallBubble(
              callType ?? 'audio',
              callStatus ?? 'missed',
              callDuration,
              isSentByMe,
              timestamp,
              replyPreview: replyPreview,
            );
      return _buildMessageWithActions(
        bubble: callBubble,
        isSentByMe: isSentByMe,
        canEdit: false,
        canMutate: canMutate,
        messageId: messageId,
        replyPayload: replyPayload,
      );
    }

    if (type == 'image' && imageUrl != null) {
      final bubble = Column(
        crossAxisAlignment: isSentByMe
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (replyPreview != null) replyPreview,
          if (statusMessage != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 6),
              decoration: BoxDecoration(
                color: isSentByMe ? kPrimary : Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                displayedMessage,
                style: TextStyle(
                  color: isSentByMe ? Colors.white : kText,
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                ),
              ),
            )
          else
            GestureDetector(
              onTap: () => _openAdminGalleryViewer([imageUrl], 0),
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CachedNetworkImage(
                    imageUrl: imageUrl,
                    width: MediaQuery.of(context).size.width * 0.24,
                    height: MediaQuery.of(context).size.width * 0.24,
                    memCacheWidth: (MediaQuery.of(context).size.width * 0.24)
                        .toInt(),
                    memCacheHeight: (MediaQuery.of(context).size.width * 0.24)
                        .toInt(),
                    fit: BoxFit.cover,
                    fadeInDuration: const Duration(milliseconds: 150),
                    placeholder: (context, url) => Container(
                      color: Colors.grey.shade200,
                      child: const Center(
                        child: CircularProgressIndicator(
                          color: kPrimary,
                          strokeWidth: 2,
                        ),
                      ),
                    ),
                    errorWidget: (context, url, error) => Container(
                      color: Colors.grey.shade200,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.image_not_supported_outlined,
                            color: Colors.grey.shade500,
                            size: 32,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'File not found',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          footer(),
        ],
      );

      return _buildMessageWithActions(
        bubble: bubble,
        isSentByMe: isSentByMe,
        canEdit: false,
        canMutate: canMutate,
        messageId: messageId,
        replyPayload: replyPayload,
        onForward: () => _forwardImage(imageUrl, 'image'),
        onCopy: () => _copyToClipboard(imageUrl),
      );
    }

    if (type == 'image_gallery') {
      List<String> galleryUrls;
      try {
        final decoded = jsonDecode(message);
        if (decoded is List) {
          galleryUrls = decoded.whereType<String>().toList();
        } else {
          galleryUrls = [message];
        }
      } on FormatException catch (e) {
        debugPrint('image_gallery: JSON parse error: $e');
        galleryUrls = [message];
      } catch (e) {
        debugPrint('image_gallery: unexpected error: $e');
        galleryUrls = [message];
      }

      Widget galleryWidget = _buildAdminGalleryGrid(galleryUrls);

      final bubble = Column(
        crossAxisAlignment: isSentByMe
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (replyPreview != null) replyPreview,
          Container(
            margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: galleryWidget,
            ),
          ),
          footer(),
        ],
      );

      return _buildMessageWithActions(
        bubble: bubble,
        isSentByMe: isSentByMe,
        canEdit: false,
        canMutate: canMutate,
        messageId: messageId,
        replyPayload: replyPayload,
        onForward: () => _forwardImage(message, 'image_gallery'),
        onCopy: () => _copyToClipboard(galleryUrls.join('\n')),
      );
    }

    if (type == 'voice' && imageUrl != null) {
      // imageUrl field holds the voice URL for voice messages in this schema
      final voiceUrl = imageUrl;
      final isCurrentlyPlaying =
          _playingVoiceMessageId == messageId && _voiceIsPlaying;
      final isCurrentMessage = _playingVoiceMessageId == messageId;
      final progressValue =
          isCurrentMessage && _voicePlaybackDuration.inSeconds > 0
          ? (_voicePlaybackPosition.inMilliseconds /
                    _voicePlaybackDuration.inMilliseconds)
                .clamp(0.0, 1.0)
          : 0.0;
      final displaySecs =
          isCurrentMessage && _voicePlaybackDuration.inSeconds > 0
          ? _voicePlaybackPosition.inSeconds
          : 0;
      final displayTime =
          '${(displaySecs ~/ 60).toString().padLeft(2, '0')}:${(displaySecs % 60).toString().padLeft(2, '0')}';

      final bubble = Column(
        crossAxisAlignment: isSentByMe
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (replyPreview != null) replyPreview,
          if (statusMessage != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 6),
              decoration: BoxDecoration(
                color: isSentByMe ? kPrimary : Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                displayedMessage,
                style: TextStyle(
                  color: isSentByMe ? Colors.white : kText,
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                ),
              ),
            )
          else
            GestureDetector(
              onTap: () => _toggleVoicePlayback(messageId!, voiceUrl),
              child: Container(
                width: 200,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 6),
                decoration: BoxDecoration(
                  color: isSentByMe ? kPrimary : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.07),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: isSentByMe
                            ? Colors.white.withOpacity(0.22)
                            : kPrimary.withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isCurrentlyPlaying ? Icons.pause : Icons.play_arrow,
                        color: isSentByMe ? Colors.white : kPrimary,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 8),
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
                              backgroundColor: Colors.grey.withOpacity(0.25),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                isSentByMe ? Colors.white : kPrimary,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            displayTime,
                            style: TextStyle(
                              color: isSentByMe ? Colors.white70 : kMuted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          footer(),
        ],
      );

      return _buildMessageWithActions(
        bubble: bubble,
        isSentByMe: isSentByMe,
        canEdit: false,
        canMutate: canMutate,
        messageId: messageId,
        replyPayload: replyPayload,
      );
    }

    if (type == 'profile_card' && profileData != null) {
      const kCardPrimary = Color(0xFF7B61FF);
      const kCardSurface = Color(0xFFFCFCFE);
      const kCardBorder = Color(0xFFEDE7F6);
      const kInfoLabel = Color(0xFF78909C);
      const kInfoValue = Color(0xFF1A2340);

      // Normalize field names: handle both admin-sent and user-sent formats
      final String? pId =
          profileData['id']?.toString() ?? profileData['userId']?.toString();
      final int? pIdValue = int.tryParse(pId ?? '');
      final String pFirst =
          profileData['first']?.toString() ??
          profileData['firstName']?.toString() ??
          '';
      final String pLast =
          profileData['last']?.toString() ??
          profileData['lastName']?.toString() ??
          '';
      final String pCountry =
          profileData['country']?.toString() ??
          profileData['location']?.toString() ??
          '';
      final String pName =
          profileData['name']?.toString() ?? '$pFirst $pLast'.trim();

      final bool isPaid = profileData['is_paid'] == true;
      final String bioText = profileData['bio'] ?? '';
      final matchRegex = RegExp(r'(\d+(?:\.\d+)?)%');
      final matchMatch = matchRegex.firstMatch(bioText);
      final double matchPct = matchMatch != null
          ? double.tryParse(matchMatch.group(1)!) ?? 0
          : 0;

      Color matchColor;
      if (matchPct >= 70) {
        matchColor = const Color(0xFF43A047);
      } else if (matchPct >= 50) {
        matchColor = const Color(0xFFFB8C00);
      } else {
        matchColor = const Color(0xFF78909C);
      }

      final bubble = Column(
        crossAxisAlignment: isSentByMe
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (replyPreview != null) replyPreview,
          if (statusMessage != null)
            Container(
              width: MediaQuery.of(context).size.width * 0.22,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
              decoration: BoxDecoration(
                color: isSentByMe ? kPrimary : Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                displayedMessage,
                style: TextStyle(
                  color: isSentByMe ? Colors.white : kText,
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                ),
              ),
            )
          else
            Container(
              width: MediaQuery.of(context).size.width * 0.22,
              margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
              decoration: BoxDecoration(
                color: kCardSurface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kCardBorder, width: 1),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF7B61FF).withOpacity(0.08),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(15),
                      topRight: Radius.circular(15),
                    ),
                    child: Container(
                      height: 72,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Color(0xFF7B61FF),
                            Color(0xFF5B41CF),
                            Color(0xFF4A32B8),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Stack(
                        children: [
                          Positioned(
                            top: -10,
                            right: -10,
                            child: Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withOpacity(0.06),
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: -8,
                            left: -8,
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withOpacity(0.06),
                              ),
                            ),
                          ),
                          Positioned(
                            top: 8,
                            left: 10,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.18),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Icon(
                                    Icons.person_pin_rounded,
                                    size: 9,
                                    color: Colors.white,
                                  ),
                                  SizedBox(width: 3),
                                  Text(
                                    'Profile Shared',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 8.5,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (isPaid)
                            Positioned(
                              top: 8,
                              right: 10,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFFFFD54F),
                                      Color(0xFFFFA000),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.workspace_premium,
                                      size: 8,
                                      color: Colors.white,
                                    ),
                                    SizedBox(width: 2),
                                    Text(
                                      'Premium',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 7.5,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.2,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  Transform.translate(
                    offset: const Offset(0, -28),
                    child: Column(
                      children: [
                        Center(
                          child: Stack(
                            alignment: Alignment.center,
                            clipBehavior: Clip.none,
                            children: [
                              if (matchPct > 0)
                                Container(
                                  width: 60,
                                  height: 60,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: matchColor,
                                      width: 2.5,
                                    ),
                                  ),
                                ),
                              Container(
                                width: 54,
                                height: 54,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 2.5,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.12),
                                      blurRadius: 8,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: ClipOval(
                                  child:
                                      profileData['profileImage'] != null &&
                                          profileData['profileImage']
                                              .toString()
                                              .isNotEmpty
                                      ? CachedNetworkImage(
                                          imageUrl: profileData['profileImage'],
                                          fit: BoxFit.cover,
                                          errorWidget: (_, __, ___) =>
                                              Container(
                                                color: const Color(0xFFF8BBD9),
                                                child: const Icon(
                                                  Icons.person_rounded,
                                                  size: 28,
                                                  color: Color(0xFF7B61FF),
                                                ),
                                              ),
                                        )
                                      : Container(
                                          color: const Color(0xFFF8BBD9),
                                          child: const Icon(
                                            Icons.person_rounded,
                                            size: 28,
                                            color: Color(0xFF7B61FF),
                                          ),
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Text(
                            pName.isNotEmpty ? pName : 'Unknown',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: kInfoValue,
                              letterSpacing: 0.1,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (matchPct > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: matchColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: matchColor.withOpacity(0.35),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.favorite_rounded,
                                  size: 9,
                                  color: matchColor,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  '${matchPct.toStringAsFixed(0)}% Match',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: matchColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  Transform.translate(
                    offset: const Offset(0, -18),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Column(
                        children: [
                          Container(
                            margin: const EdgeInsets.only(bottom: 4),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: kCardPrimary.withOpacity(0.07),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: kCardPrimary.withOpacity(0.25),
                                width: 0.8,
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.tag_rounded,
                                  size: 10,
                                  color: kCardPrimary,
                                ),
                                const SizedBox(width: 4),
                                const Text(
                                  'User ID',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    color: kCardPrimary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  '#${pId ?? ''}',
                                  style: const TextStyle(
                                    fontSize: 9.5,
                                    color: kCardPrimary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _buildInfoRow(
                            Icons.badge_rounded,
                            'Member ID',
                            profileData['Member ID'],
                            kInfoLabel,
                            kInfoValue,
                          ),
                          _buildInfoRow(
                            Icons.wc_rounded,
                            'Gender',
                            profileData['gender'],
                            kInfoLabel,
                            kInfoValue,
                          ),
                          _buildInfoRow(
                            Icons.location_on_rounded,
                            'Location',
                            pCountry,
                            kInfoLabel,
                            kInfoValue,
                          ),
                          _buildInfoRow(
                            Icons.work_rounded,
                            'Occupation',
                            profileData['occupation'],
                            kInfoLabel,
                            kInfoValue,
                          ),
                          _buildInfoRow(
                            Icons.school_rounded,
                            'Education',
                            profileData['education'],
                            kInfoLabel,
                            kInfoValue,
                          ),
                          _buildInfoRow(
                            Icons.favorite_border_rounded,
                            'Marital',
                            profileData['marit'],
                            kInfoLabel,
                            kInfoValue,
                          ),
                          _buildInfoRow(
                            Icons.cake_rounded,
                            'Age',
                            profileData['age']?.toString(),
                            kInfoLabel,
                            kInfoValue,
                          ),
                          _buildInfoRow(
                            Icons.height_rounded,
                            'Height',
                            profileData['height']?.toString(),
                            kInfoLabel,
                            kInfoValue,
                          ),
                          _buildInfoRow(
                            Icons.menu_book_rounded,
                            'Religion',
                            profileData['religion']?.toString(),
                            kInfoLabel,
                            kInfoValue,
                          ),
                          _buildInfoRow(
                            Icons.groups_rounded,
                            'Community',
                            profileData['community']?.toString(),
                            kInfoLabel,
                            kInfoValue,
                          ),
                        ],
                      ),
                    ),
                  ),
                  Transform.translate(
                    offset: const Offset(0, -12),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => openUrl(
                                "${kAdminApiBaseUrl}/profile.php?id=${pId ?? ''}",
                              ),
                              child: Container(
                                height: 32,
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: kCardPrimary,
                                    width: 1.2,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.open_in_new_rounded,
                                      size: 12,
                                      color: kCardPrimary,
                                    ),
                                    SizedBox(width: 4),
                                    Text(
                                      'Profile',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: kCardPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  Provider.of<ChatProvider>(
                                    context,
                                    listen: false,
                                  ).updateName("${pLast}  ${pFirst}");
                                  if (pIdValue != null) {
                                    Provider.of<ChatProvider>(
                                      context,
                                      listen: false,
                                    ).updateidd(pIdValue);
                                  }
                                });
                              },
                              child: Container(
                                height: 32,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFF7B61FF),
                                      Color(0xFF5B41CF),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(
                                        0xFF7B61FF,
                                      ).withOpacity(0.3),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.chat_bubble_rounded,
                                      size: 12,
                                      color: Colors.white,
                                    ),
                                    SizedBox(width: 4),
                                    Text(
                                      'Chat',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          footer(),
        ],
      );

      return _buildMessageWithActions(
        bubble: bubble,
        isSentByMe: isSentByMe,
        canEdit: false,
        canMutate: canMutate,
        messageId: messageId,
        replyPayload: replyPayload,
      );
    }

    if (type == 'report') {
      final rd = reportData ?? {};
      final reportReason = rd['reportReason']?.toString() ?? '';
      final reportedUserName = rd['reportedUserName']?.toString() ?? '';
      final reportedUserId = rd['reportedUserId']?.toString() ?? '';
      final reporterName = rd['reporterName']?.toString().isNotEmpty == true
          ? rd['reporterName']!.toString()
          : (chatProvider.namee ?? 'Unknown');
      final reporterId = rd['reporterId']?.toString().isNotEmpty == true
          ? rd['reporterId']!.toString()
          : (chatProvider.id?.toString() ?? '');
      final reporterImage = rd['reporterImage']?.toString() ?? '';
      final customMessage = rd['reportMessage']?.toString() ?? '';

      String _initials(String name) => name.isNotEmpty
          ? name
                .trim()
                .split(' ')
                .map((w) => w.isEmpty ? '' : w[0].toUpperCase())
                .take(2)
                .join()
          : '?';

      Widget _userRow({
        required String name,
        required String userId,
        String imageUrl = '',
        required Color avatarColor,
        required Color nameColor,
        required Color idColor,
      }) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: avatarColor,
              backgroundImage: imageUrl.isNotEmpty
                  ? NetworkImage(imageUrl)
                  : null,
              child: imageUrl.isEmpty
                  ? Text(
                      _initials(name),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (name.isNotEmpty)
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: nameColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (userId.isNotEmpty)
                    Text(
                      'ID: $userId',
                      style: TextStyle(fontSize: 10, color: idColor),
                    ),
                ],
              ),
            ),
          ],
        );
      }

      final formattedTs = DateFormat('MMM d, yyyy • h:mm a').format(timestamp);

      final reportBubble = Column(
        crossAxisAlignment: isSentByMe
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (replyPreview != null) replyPreview,
          if (statusMessage != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 6),
              decoration: BoxDecoration(
                color: isSentByMe ? kPrimary : Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                displayedMessage,
                style: TextStyle(
                  color: isSentByMe ? Colors.white : kText,
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                ),
              ),
            )
          else
            Container(
              width: MediaQuery.of(context).size.width * 0.75,
              margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFFFCDD2), width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.red.withOpacity(0.10),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Red header ──────────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFFD32F2F), Color(0xFFB71C1C)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(13),
                        topRight: Radius.circular(13),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.warning_rounded,
                          color: Colors.white,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        const Expanded(
                          child: Text(
                            'USER REPORTED',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                        // Status badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.25),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.circle,
                                color: Color(0xFFFFEB3B),
                                size: 7,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Pending',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── Reporter section ─────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.person_outline,
                              size: 11,
                              color: Color(0xFF757575),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'REPORTED BY',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: Colors.grey.shade600,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        _userRow(
                          name: reporterName,
                          userId: reporterId,
                          imageUrl: reporterImage,
                          avatarColor: const Color(0xFF1565C0),
                          nameColor: const Color(0xFF0D47A1),
                          idColor: Colors.grey.shade500,
                        ),
                      ],
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Divider(color: Colors.grey.shade200, height: 12),
                  ),

                  // ── Reported user section ────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.flag_outlined,
                              size: 11,
                              color: Color(0xFFD32F2F),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'REPORTED USER',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: Colors.red.shade700,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        _userRow(
                          name: reportedUserName.isNotEmpty
                              ? reportedUserName
                              : 'Unknown',
                          userId: reportedUserId,
                          avatarColor: const Color(0xFFD32F2F),
                          nameColor: const Color(0xFF7F0000),
                          idColor: Colors.grey.shade500,
                        ),
                      ],
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Divider(color: Colors.grey.shade200, height: 12),
                  ),

                  // ── Report reason ────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.report_gmailerrorred_outlined,
                              size: 11,
                              color: Color(0xFFE65100),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'REASON',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: Colors.orange.shade800,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF3E0),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            reportReason.isNotEmpty
                                ? reportReason
                                : 'No reason provided',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF4E342E),
                            ),
                          ),
                        ),
                        if (customMessage.isNotEmpty &&
                            !customMessage.startsWith('I have reported')) ...[
                          const SizedBox(height: 6),
                          Text(
                            customMessage,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // ── Timestamp ────────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 6),
                    child: Row(
                      children: [
                        Icon(
                          Icons.access_time_rounded,
                          size: 11,
                          color: Colors.grey.shade500,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          formattedTs,
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Divider(color: Colors.grey.shade200, height: 8),
                  ),

                  // ── Action buttons ───────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        // View Profile
                        if (reportedUserId.isNotEmpty)
                          SizedBox(
                            height: 30,
                            child: OutlinedButton.icon(
                              onPressed: () {
                                final uid = int.tryParse(reportedUserId);
                                if (uid != null) {
                                  kIsWeb
                                      ? _openProfileInNewTab(context, uid)
                                      : _navigateToProfile(context, uid);
                                }
                              },
                              icon: const Icon(
                                Icons.person_search_rounded,
                                size: 13,
                              ),
                              label: const Text(
                                'View Profile',
                                style: TextStyle(fontSize: 11),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF1565C0),
                                side: const BorderSide(
                                  color: Color(0xFF1565C0),
                                  width: 1,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                              ),
                            ),
                          ),
                        // Take Action
                        SizedBox(
                          height: 30,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              showModalBottomSheet<void>(
                                context: context,
                                shape: const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.vertical(
                                    top: Radius.circular(20),
                                  ),
                                ),
                                builder: (_) => Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    20,
                                    16,
                                    20,
                                    24,
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Take Action',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      if (reportedUserName.isNotEmpty)
                                        Text(
                                          'Against: $reportedUserName',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                      const SizedBox(height: 12),
                                      _ActionTile(
                                        icon: Icons.notifications_off_outlined,
                                        color: Colors.orange,
                                        label: 'Warn User',
                                        onTap: () {
                                          Navigator.pop(context);
                                          _sendReportWarning(
                                            reportedUserId: reportedUserId,
                                            reportedUserName: reportedUserName,
                                            reportReason: reportReason,
                                          );
                                        },
                                      ),
                                      _ActionTile(
                                        icon: Icons.block_rounded,
                                        color: Colors.red,
                                        label: 'Ban User',
                                        onTap: () {
                                          Navigator.pop(context);
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                '$reportedUserName has been banned',
                                              ),
                                              backgroundColor: Colors.red,
                                            ),
                                          );
                                        },
                                      ),
                                      _ActionTile(
                                        icon:
                                            Icons.pause_circle_outline_rounded,
                                        color: Colors.deepOrange,
                                        label: 'Suspend User',
                                        onTap: () {
                                          Navigator.pop(context);
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                '$reportedUserName has been suspended',
                                              ),
                                              backgroundColor:
                                                  Colors.deepOrange,
                                            ),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.gavel_rounded, size: 13),
                            label: const Text(
                              'Take Action',
                              style: TextStyle(fontSize: 11),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFD32F2F),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              elevation: 0,
                            ),
                          ),
                        ),
                        // Ignore
                        SizedBox(
                          height: 30,
                          child: TextButton.icon(
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Report marked as ignored'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            },
                            icon: Icon(
                              Icons.close_rounded,
                              size: 13,
                              color: Colors.grey.shade600,
                            ),
                            label: Text(
                              'Ignore',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
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
        ],
      );

      return _buildMessageWithActions(
        bubble: reportBubble,
        isSentByMe: isSentByMe,
        canEdit: false,
        canMutate: canMutate,
        messageId: messageId,
        replyPayload: replyPayload,
      );
    }

    final bubble = ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.24,
      ),
      child: Column(
        crossAxisAlignment: isSentByMe
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 6),
            decoration: BoxDecoration(
              color: isSentByMe ? kPrimary : Colors.white,
              borderRadius: isSentByMe
                  ? const BorderRadius.only(
                      topLeft: Radius.circular(18),
                      topRight: Radius.circular(18),
                      bottomLeft: Radius.circular(18),
                      bottomRight: Radius.circular(4),
                    )
                  : const BorderRadius.only(
                      topLeft: Radius.circular(4),
                      topRight: Radius.circular(18),
                      bottomLeft: Radius.circular(18),
                      bottomRight: Radius.circular(18),
                    ),
              boxShadow: isSentByMe
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (replyPreview != null) replyPreview,
                Text(
                  displayedMessage,
                  style: TextStyle(
                    color: isSentByMe ? Colors.white : kText,
                    fontSize: 13,
                    fontStyle: statusMessage != null
                        ? FontStyle.italic
                        : FontStyle.normal,
                  ),
                ),
              ],
            ),
          ),
          footer(),
        ],
      ),
    );

    return _buildMessageWithActions(
      bubble: bubble,
      isSentByMe: isSentByMe,
      canEdit: canEdit,
      canMutate: canMutate,
      messageId: messageId,
      replyPayload: replyPayload,
      onCopy: (deleted || unsent) ? null : () => _copyToClipboard(message),
    );
  }

  Widget _buildMessageWithActions({
    required Widget bubble,
    required bool isSentByMe,
    required bool canEdit,
    required bool canMutate,
    required String? messageId,
    required Map<String, dynamic>? replyPayload,
    VoidCallback? onForward,
    VoidCallback? onCopy,
  }) {
    if (messageId == null || replyPayload == null) {
      return Align(
        alignment: isSentByMe ? Alignment.centerRight : Alignment.centerLeft,
        child: bubble,
      );
    }

    return _HoverableMessageBubble(
      bubble: bubble,
      isSentByMe: isSentByMe,
      canEdit: canEdit,
      canDelete: canMutate,
      canUnsend: canMutate,
      onReply: () => _startReply(
        messageId,
        replyPayload['message']?.toString() ?? '',
        replyPayload['senderid']?.toString() ?? '',
        replyPayload['senderName']?.toString() ?? 'User',
        replyPayload,
      ),
      onEdit: canEdit
          ? () =>
                _startEdit(messageId, replyPayload['message']?.toString() ?? '')
          : null,
      onDelete: canMutate ? () => _deleteMessage(messageId) : null,
      onUnsend: canMutate ? () => _unsendMessage(messageId) : null,
      onForward: onForward,
      onCopy: onCopy,
    );
  }

  Widget? _buildReplyPreview({
    required Map<String, dynamic>? replyTo,
    required bool isSentByMe,
    required Color mutedColor,
    required Color primaryColor,
  }) {
    if (replyTo == null || replyTo['message'] == null) return null;

    final String replyMsgType = replyTo['messageType']?.toString() ?? 'text';
    final String rawQuotedMsg = replyTo['message'] as String;
    final String quotedMsg = replyMsgType == 'image_gallery'
        ? '🖼️ Photos'
        : rawQuotedMsg;
    final String quotedSender = replyTo['senderName'] as String? ?? 'User';
    final bool canNavigate = _replyTargetMessageId(replyTo).isNotEmpty;
    // For image_gallery, show first image as thumbnail
    String? imageUrl = replyTo['imageUrl']?.toString();
    if ((imageUrl == null || imageUrl.isEmpty) &&
        replyMsgType == 'image_gallery') {
      try {
        final decoded = jsonDecode(rawQuotedMsg);
        if (decoded is List && decoded.isNotEmpty) {
          imageUrl = decoded.first?.toString();
        }
      } on FormatException catch (_) {
        // Malformed gallery JSON — leave imageUrl null
      }
    }
    final bool hasImage = imageUrl != null && imageUrl.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4, left: 6, right: 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: canNavigate ? () => _handleReplyPreviewTap(replyTo) : null,
          splashColor: canNavigate ? null : Colors.transparent,
          highlightColor: canNavigate ? null : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: Ink(
            decoration: BoxDecoration(
              color: isSentByMe
                  ? Colors.white.withOpacity(
                      _kReplyPreviewSentBackgroundOpacity,
                    )
                  : primaryColor.withOpacity(0.07),
              borderRadius: BorderRadius.circular(10),
              border: Border(
                left: BorderSide(
                  color: isSentByMe
                      ? Colors.white.withOpacity(
                          _kReplyPreviewSentBorderOpacity,
                        )
                      : primaryColor,
                  width: 3,
                ),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          quotedSender,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isSentByMe ? Colors.white : primaryColor,
                          ),
                        ),
                        if (replyTo['edited'] == true &&
                            replyTo['deleted'] != true &&
                            replyTo['unsent'] != true) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Edited',
                            style: TextStyle(
                              fontSize: 10,
                              fontStyle: FontStyle.italic,
                              color: isSentByMe
                                  ? Colors.white.withOpacity(
                                      _kReplyPreviewSentTextOpacity,
                                    )
                                  : mutedColor,
                            ),
                          ),
                        ],
                        const SizedBox(height: 2),
                        Text(
                          quotedMsg.length > _kMaxQuoteLength
                              ? '${quotedMsg.substring(0, _kMaxQuoteLength)}…'
                              : quotedMsg,
                          style: TextStyle(
                            fontSize: 11,
                            color: isSentByMe
                                ? Colors.white.withOpacity(
                                    _kReplyPreviewSentTextOpacity,
                                  )
                                : mutedColor,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
                // Image thumbnail (WhatsApp-style)
                if (hasImage)
                  ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(10),
                      bottomRight: Radius.circular(10),
                    ),
                    child: CachedNetworkImage(
                      imageUrl: imageUrl!,
                      width: 50,
                      height: 54,
                      memCacheWidth: 50,
                      memCacheHeight: 54,
                      fit: BoxFit.cover,
                      fadeInDuration: const Duration(milliseconds: 150),
                      placeholder: (_, __) => Container(
                        width: 50,
                        height: 54,
                        color: Colors.grey.shade200,
                        child: const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        width: 50,
                        height: 54,
                        color: Colors.grey.shade200,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.image_not_supported_outlined,
                              color: Colors.grey.shade500,
                              size: 18,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Not found',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 8,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else if (canNavigate) ...[
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(
                      Icons.subdirectory_arrow_left_rounded,
                      size: 16,
                      color: isSentByMe
                          ? Colors.white.withOpacity(
                              _kReplyPreviewSentIconOpacity,
                            )
                          : primaryColor,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// WhatsApp-style gallery grid for image_gallery message type.
  Widget _buildAdminGalleryGrid(List<String> urls) {
    if (urls.isEmpty) return const SizedBox.shrink();
    const Color adminPrimary = Color(0xFF7B61FF);
    final double gridWidth = MediaQuery.of(context).size.width * 0.24;
    const double gap = 2;

    Widget thumb(int index, {bool showOverlay = false, int extra = 0}) {
      final url = urls[index];
      Widget img = CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        memCacheWidth: gridWidth.toInt(),
        memCacheHeight: gridWidth.toInt(),
        fadeInDuration: const Duration(milliseconds: 150),
        placeholder: (ctx, url) => Container(
          color: Colors.grey.shade200,
          child: const Center(
            child: CircularProgressIndicator(
              color: adminPrimary,
              strokeWidth: 2,
            ),
          ),
        ),
        errorWidget: (_, __, ___) => Container(
          color: Colors.grey.shade200,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.image_not_supported_outlined,
                color: Colors.grey.shade500,
                size: 28,
              ),
              const SizedBox(height: 4),
              Text(
                'File not found',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 10),
              ),
            ],
          ),
        ),
      );
      return GestureDetector(
        onTap: () => _openAdminGalleryViewer(urls, index),
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
      return SizedBox(width: gridWidth, height: gridWidth, child: thumb(0));
    }
    if (urls.length == 2) {
      final h = gridWidth / 2 - gap / 2;
      return SizedBox(
        width: gridWidth,
        child: Row(
          children: [
            Expanded(
              child: SizedBox(height: h, child: thumb(0)),
            ),
            SizedBox(width: gap),
            Expanded(
              child: SizedBox(height: h, child: thumb(1)),
            ),
          ],
        ),
      );
    }
    if (urls.length == 3) {
      final h = gridWidth * 0.6;
      return SizedBox(
        width: gridWidth,
        height: h,
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: SizedBox(height: h, child: thumb(0)),
            ),
            SizedBox(width: gap),
            Expanded(
              flex: 1,
              child: Column(
                children: [
                  Expanded(child: thumb(1)),
                  SizedBox(height: gap),
                  Expanded(child: thumb(2)),
                ],
              ),
            ),
          ],
        ),
      );
    }
    if (urls.length == 4) {
      final cellW = (gridWidth - gap) / 2;
      return SizedBox(
        width: gridWidth,
        child: Column(
          children: [
            Row(
              children: [
                SizedBox(width: cellW, height: cellW, child: thumb(0)),
                SizedBox(width: gap),
                SizedBox(width: cellW, height: cellW, child: thumb(1)),
              ],
            ),
            SizedBox(height: gap),
            Row(
              children: [
                SizedBox(width: cellW, height: cellW, child: thumb(2)),
                SizedBox(width: gap),
                SizedBox(width: cellW, height: cellW, child: thumb(3)),
              ],
            ),
          ],
        ),
      );
    }

    // 5+ images: 2-column grid, last cell may show "+N"
    const int maxVisible = 6;
    final int displayCount = urls.length > maxVisible
        ? maxVisible
        : urls.length;
    final int extraCount = urls.length > maxVisible
        ? urls.length - maxVisible + 1
        : 0;
    final double cellW = (gridWidth - gap) / 2;
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
      rows.add(
        Row(
          children: [
            cells[i],
            SizedBox(width: gap),
            if (i + 1 < cells.length) cells[i + 1] else SizedBox(width: cellW),
          ],
        ),
      );
    }
    return SizedBox(
      width: gridWidth,
      child: Column(children: rows),
    );
  }

  void _openAdminGalleryViewer(List<String> urls, int initialIndex) {
    if (urls.isEmpty) return;
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    final String userName = chatProvider.namee ?? 'User';
    final int userId = chatProvider.id ?? 0;

    // Start with all shared photos from this chat so navigation mirrors the profile sheet.
    final List<_AdminSharedPhoto> sharedPhotos = _getAdminSharedPhotos();
    final List<_AdminSharedPhoto> viewerPhotos = List<_AdminSharedPhoto>.from(
      sharedPhotos,
    );
    final Set<String> seenUrls = viewerPhotos.map((p) => p.url).toSet();

    // Ensure tapped message photos are included even if not part of sharedPhotos (e.g., admin-sent).
    for (final url in urls) {
      if (url.isEmpty || seenUrls.contains(url)) continue;
      viewerPhotos.add(_AdminSharedPhoto(url: url));
      seenUrls.add(url);
    }

    if (viewerPhotos.isEmpty) return;

    final int safeIndex = initialIndex.clamp(0, urls.length - 1).toInt();
    final String targetUrl = urls[safeIndex];
    int startIndex = viewerPhotos.indexWhere((p) => p.url == targetUrl);
    if (startIndex == -1) startIndex = 0;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _AdminPhotoViewerPage(
          photos: viewerPhotos,
          initialIndex: startIndex,
          userName: userName,
          userId: userId,
          onDeleteMessage: _deleteMessage,
        ),
      ),
    );
  }

  /// WhatsApp-style read receipt tick for admin-sent messages.
  /// Reaction badge displayed below a message bubble.
  Widget _buildAdminReactionBadge(
    Map<String, dynamic> reactions,
    bool isSentByMe,
  ) {
    const kPrimary = Color(0xFF7B61FF);
    final Map<String, int> emojiCounts = {};
    for (final emoji in reactions.values) {
      final e = emoji.toString();
      emojiCounts[e] = (emojiCounts[e] ?? 0) + 1;
    }
    if (emojiCounts.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.only(
        top: 2,
        left: isSentByMe ? 0 : 8,
        right: isSentByMe ? 8 : 0,
        bottom: 2,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: isSentByMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: emojiCounts.entries.map((entry) {
          final count = entry.value;
          return Container(
            margin: const EdgeInsets.only(right: 4),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kPrimary.withOpacity(0.3), width: 1),
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
                    style: const TextStyle(
                      fontSize: 11,
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

  /// Double grey ticks = delivered (not yet read by user).
  /// Double blue ticks = read by user.
  Widget _buildSeenTick(bool seen) {
    // WhatsApp blue (#34B7F1) for read, slate-grey for delivered-not-read.
    const kReadBlue = Color(0xFF34B7F1);
    const kDelivered = Color(0xFF94A3B8);
    return Icon(Icons.done_all, size: 14, color: seen ? kReadBlue : kDelivered);
  }

  /// Call history message bubble.
  Widget _buildCallBubble(
    String callType,
    String status,
    int durationSeconds,
    bool isSentByMe,
    DateTime timestamp, {
    Widget? replyPreview,
  }) {
    const kPrimary = Color(0xFF7B61FF);
    const kMuted = Color(0xFF64748B);
    final bool isBusy = status == 'busy';
    final bool isMissed = isBusy || status == 'missed';
    final bool isVideo = callType == 'video';
    final Color color = isBusy
        ? Colors.orange
        : (isMissed ? Colors.red : kPrimary);
    final String label = isBusy
        ? 'User is busy'
        : isMissed
        ? (isVideo ? 'Missed Video Call' : 'Missed Call')
        : (isVideo ? 'Video Call' : 'Audio Call');
    final IconData icon = isBusy
        ? Icons.phone_locked
        : isMissed
        ? (isVideo ? Icons.videocam_off_outlined : Icons.phone_missed)
        : (isVideo ? Icons.videocam_outlined : Icons.phone_outlined);
    final String dur = durationSeconds > 0
        ? ' • ${_formatCallDuration(durationSeconds)}'
        : '';

    return Column(
      crossAxisAlignment: isSentByMe
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (replyPreview != null) replyPreview,
        Container(
          margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isBusy
                ? Colors.orange.shade50
                : (isMissed ? Colors.red.shade50 : const Color(0xFFFCE4EC)),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isBusy
                  ? Colors.orange.shade200
                  : (isMissed ? Colors.red.shade200 : const Color(0xFFFFCDD2)),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$label$dur',
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    DateFormat('hh:mm a').format(timestamp),
                    style: const TextStyle(fontSize: 10, color: kMuted),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(
    IconData icon,
    String label,
    String? value,
    Color labelColor,
    Color valueColor,
  ) {
    if (value == null || value.isEmpty || value == 'null')
      return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 11, color: labelColor),
          const SizedBox(width: 5),
          SizedBox(
            width: 58,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 9.5,
                color: labelColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 9.5,
                color: valueColor,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(String text, Color color, VoidCallback onPressed) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      onPressed: onPressed,
      child: Text(
        text,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }

  void _playAudio(String url) async {
    final AudioPlayer _audioPlayer = AudioPlayer();
    try {
      await _audioPlayer.setUrl(url);
      await _audioPlayer.play();
    } catch (e) {}
  }

  Future<void> _toggleVoicePlayback(String messageId, String voiceUrl) async {
    if (_playingVoiceMessageId == messageId && _voiceIsPlaying) {
      await _voiceAudioPlayer.pause();
      return;
    }

    if (_playingVoiceMessageId == messageId && !_voiceIsPlaying) {
      await _voiceAudioPlayer.play();
      return;
    }

    _voicePlaybackPosition = Duration.zero;
    _voicePlaybackDuration = Duration.zero;

    try {
      await _voiceAudioPlayer.stop();
      await _voiceAudioPlayer.setUrl(voiceUrl);
      if (mounted) setState(() => _playingVoiceMessageId = messageId);
      await _voiceAudioPlayer.play();
    } catch (e) {
      debugPrint('Voice playback failed: $e');
      await _voiceAudioPlayer.stop();
      if (mounted) {
        setState(() {
          _playingVoiceMessageId = null;
          _voicePlaybackPosition = Duration.zero;
          _voicePlaybackDuration = Duration.zero;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to play voice message')),
        );
      }
    }
  }

  // ── VOICE MESSAGE RECORDING (web: flutter_sound) ─────────────────────────

  Future<void> _startVoiceRecording() async {
    if (_isRecordingVoice) return;
    try {
      await _recorder.openRecorder();
      final tempPath = 'voice_${DateTime.now().millisecondsSinceEpoch}.webm';
      await _recorder.startRecorder(toFile: tempPath, codec: Codec.opusWebM);
      setState(() {
        _isRecordingVoice = true;
        _voiceRecordDuration = 0;
        _voiceRecordingPath = tempPath;
      });
      _voiceRecordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _voiceRecordDuration++);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start recording: $e')),
        );
      }
    }
  }

  Future<void> _stopAndSendVoiceRecording() async {
    if (!_isRecordingVoice) return;
    _voiceRecordTimer?.cancel();
    _voiceRecordTimer = null;
    if (mounted) setState(() => _isHoldRecordingVoice = false);

    try {
      final path = await _recorder.stopRecorder();
      setState(() {
        _isRecordingVoice = false;
        _isSendingVoice = true;
      });
      if (path == null || path.isEmpty) return;
      final chatProvider = Provider.of<ChatProvider>(context, listen: false);
      final receiverId = chatProvider.id?.toString();
      if (receiverId == null) return;

      final voiceUrl = await _uploadVoiceMessage(path);
      final String messageId = const Uuid().v4();
      final String roomId = AdminSocketService.chatRoomId(receiverId);

      if (_socketService.isConnected) {
        _socketService.sendMessage(
          chatRoomId: roomId,
          receiverId: receiverId,
          message: voiceUrl,
          messageType: 'voice',
          messageId: messageId,
          receiverName: chatProvider.namee,
          receiverImage: chatProvider.profilePicture,
        );
      } else {
        await _sendMessageViaHttp(
          roomId: roomId,
          receiverId: receiverId,
          message: voiceUrl,
          messageType: 'voice',
          messageId: messageId,
          chatProvider: chatProvider,
        );
      }

      await NotificationService.sendChatNotification(
        recipientUserId: receiverId,
        senderName: "Admin",
        senderId: '1',
        message: '🎤 Voice message',
        extraData: {'chatId': receiverId, 'screen': 'chat'},
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send voice message: $e')),
        );
      }
    } finally {
      if (mounted)
        setState(() {
          _isRecordingVoice = false;
          _isSendingVoice = false;
        });
    }
  }

  void _cancelVoiceRecording() {
    if (!_isRecordingVoice) return;
    _voiceRecordTimer?.cancel();
    _voiceRecordTimer = null;
    _recorder.stopRecorder();
    setState(() {
      _isRecordingVoice = false;
      _isHoldRecordingVoice = false;
      _voiceRecordDuration = 0;
    });
  }

  Future<String> _uploadVoiceMessage(String filePath) async {
    // For web, flutter_sound returns a blob URL; use XHR to fetch then upload
    if (kIsWeb) {
      // Resolve relative paths returned by the recorder to an absolute URL so
      // the browser can fetch the blob bytes.
      String resolvedUrl = filePath;
      final uri = Uri.parse(filePath);
      if (!uri.hasScheme) {
        final origin = html.window.location.origin;
        final normalizedPath = filePath.startsWith('/')
            ? filePath
            : '/$filePath';
        resolvedUrl = '$origin$normalizedPath';
      }

      final xhr = await html.HttpRequest.request(
        resolvedUrl,
        responseType: 'arraybuffer',
      );
      final resp = xhr.response;
      if (xhr.status != 200 || resp == null) {
        throw Exception('Failed to read recorded audio data');
      }

      late final Uint8List bytes;
      if (resp is ByteBuffer) {
        bytes = Uint8List.view(resp);
      } else if (resp is Uint8List) {
        bytes = resp;
      } else {
        throw Exception('Failed to read recorded audio data');
      }
      final req = http.MultipartRequest(
        'POST',
        Uri.parse(
          kAdminSocketUrl,
        ).replace(path: '/upload', queryParameters: {'type': 'voice'}),
      );
      req.files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: 'voice_${DateTime.now().millisecondsSinceEpoch}.webm',
          contentType: MediaType('audio', 'webm'),
        ),
      );
      final streamed = await req.send();
      final body = await streamed.stream.bytesToString();
      if (streamed.statusCode != 200) {
        throw Exception('Upload failed: ${streamed.statusCode} $body');
      }
      final json = jsonDecode(body) as Map<String, dynamic>;
      final url = json['url']?.toString();
      if (url == null || url.isEmpty) {
        throw Exception(json['error']?.toString() ?? 'Upload returned no URL');
      }
      return _normalizeUploadUrl(url);
    } else {
      final req = http.MultipartRequest(
        'POST',
        Uri.parse(
          kAdminSocketUrl,
        ).replace(path: '/upload', queryParameters: {'type': 'voice'}),
      );
      req.files.add(await http.MultipartFile.fromPath('file', filePath));
      final streamed = await req.send();
      final body = await streamed.stream.bytesToString();
      if (streamed.statusCode != 200) {
        throw Exception('Upload failed: ${streamed.statusCode} $body');
      }
      final json = jsonDecode(body) as Map<String, dynamic>;
      final url = json['url']?.toString();
      if (url == null || url.isEmpty) {
        throw Exception(json['error']?.toString() ?? 'Upload returned no URL');
      }
      return _normalizeUploadUrl(url);
    }
  }

  String _formatVoiceRecordDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Widget _buildActionBanner(ChatColors colors) {
    const kPrimary = Color(0xFF7B61FF);
    final bool isEditing = _editingMessageId != null;
    final bool replyingToEdited =
        _replyingTo?['edited'] == true &&
        _replyingTo?['deleted'] != true &&
        _replyingTo?['unsent'] != true;
    final String label = isEditing
        ? 'Editing'
        : 'Replying to ${_replyingTo?['senderName'] ?? 'User'}${replyingToEdited ? ' • edited' : ''}';
    final String preview = isEditing
        ? (_editingOriginalText.length > _kMaxQuoteLength
              ? '${_editingOriginalText.substring(0, _kMaxQuoteLength)}…'
              : _editingOriginalText)
        : (() {
            final String msg = (_replyingTo?['message'] as String?) ?? '';
            return msg.length > _kMaxQuoteLength
                ? '${msg.substring(0, _kMaxQuoteLength)}…'
                : msg;
          }());
    final IconData leadIcon = isEditing
        ? Icons.edit_outlined
        : Icons.reply_rounded;
    final String? replyImageUrl = !isEditing
        ? (_replyingTo?['imageUrl']?.toString())
        : null;
    final bool hasReplyImage =
        replyImageUrl != null && replyImageUrl.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: kPrimary.withOpacity(0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kPrimary.withOpacity(0.25), width: 1),
      ),
      child: Row(
        children: [
          // Left accent bar
          Container(
            width: 3,
            height: hasReplyImage ? 56 : 46,
            margin: const EdgeInsets.only(right: 0),
            decoration: BoxDecoration(
              color: kPrimary,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(10),
                bottomLeft: Radius.circular(10),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Icon(leadIcon, size: 15, color: kPrimary),
          const SizedBox(width: 6),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: kPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: colors.muted),
                  ),
                ],
              ),
            ),
          ),
          // Image thumbnail for image replies
          if (hasReplyImage) ...[
            const SizedBox(width: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: CachedNetworkImage(
                imageUrl: replyImageUrl!,
                width: 44,
                height: 44,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) =>
                    Icon(Icons.image, size: 44, color: Colors.grey.shade400),
              ),
            ),
            const SizedBox(width: 4),
          ],
          GestureDetector(
            onTap: _cancelAction,
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Icon(Icons.close, size: 16, color: colors.muted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdminRecordingBar(ChatColors colors, Color kPrimary) {
    return Row(
      children: [
        IconButton(
          onPressed: _cancelVoiceRecording,
          icon: const Icon(Icons.delete_outline, color: Colors.red, size: 22),
          tooltip: 'Cancel',
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          padding: EdgeInsets.zero,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: kPrimary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: kPrimary.withOpacity(0.3), width: 1),
            ),
            child: Row(
              children: [
                // Pulsing red dot
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.4, end: 1.0),
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeInOut,
                  onEnd: () => setState(() {}),
                  builder: (_, opacity, __) => Opacity(
                    opacity: opacity,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _formatVoiceRecordDuration(_voiceRecordDuration),
                  style: TextStyle(
                    color: kPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: _AdminVoiceWaveform(color: kPrimary)),
              ],
            ),
          ),
        ),
        const SizedBox(width: 6),
        _isSendingVoice
            ? const SizedBox(
                width: 38,
                height: 38,
                child: Padding(
                  padding: EdgeInsets.all(9),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF7B61FF),
                  ),
                ),
              )
            : GestureDetector(
                onTap: _stopAndSendVoiceRecording,
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: kPrimary,
                    borderRadius: BorderRadius.circular(19),
                  ),
                  child: const Icon(
                    Icons.send_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
      ],
    );
  }

  Widget _buildMessageInput(ChatProvider chatProvider) {
    const kPrimary = Color(0xFF7B61FF);
    // Dark-mode tints for the language-selector chip
    const kLangNepaliDarkBg = Color(0xFF4A1A1A);
    const kLangEnglishDarkBg = Color(0xFF1A2A40);
    const kLangNepaliDarkBorder = Color(0xFFCC4444);
    const kLangEnglishDarkBorder = Color(0xFF4488CC);
    const kLangNepaliDarkText = Color(0xFFFF6B6B);
    const kLangEnglishDarkText = Color(0xFF64B5F6);
    final colors = ChatColors.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.inputBg,
        border: Border(top: BorderSide(color: colors.border, width: 1)),
      ),
      child: Column(
        children: [
          // ── Inline reply / edit banner ──────────────────────────────────
          if (_replyingTo != null || _editingMessageId != null)
            _buildActionBanner(colors),
          if (_selectedImages.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 88,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _selectedImages.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 6),
                      itemBuilder: (context, index) {
                        final file = _selectedImages[index];
                        ImageProvider? imgProvider;
                        if (kIsWeb && file.bytes != null) {
                          imgProvider = MemoryImage(file.bytes!);
                        } else if (!kIsWeb && file.path != null) {
                          imgProvider = FileImage(File(file.path!));
                        }
                        return Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              height: 80,
                              width: 80,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                color: colors.border,
                                image: imgProvider != null
                                    ? DecorationImage(
                                        image: imgProvider,
                                        fit: BoxFit.cover,
                                      )
                                    : null,
                              ),
                              child: imgProvider == null
                                  ? Icon(
                                      Icons.image,
                                      color: colors.muted,
                                      size: 32,
                                    )
                                  : null,
                            ),
                            Positioned(
                              top: -4,
                              right: -4,
                              child: GestureDetector(
                                onTap: () => setState(() {
                                  _selectedImages.removeAt(index);
                                }),
                                child: Container(
                                  width: 20,
                                  height: 20,
                                  decoration: const BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.close,
                                    color: Colors.white,
                                    size: 14,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      ElevatedButton(
                        onPressed: _sendImageMessage,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kPrimary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                        ),
                        child: Text(
                          _selectedImages.length == 1
                              ? 'Send Photo'
                              : 'Send ${_selectedImages.length} Photos',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: Icon(Icons.close, color: colors.muted, size: 18),
                        onPressed: () => setState(() => _selectedImages = []),
                        constraints: const BoxConstraints(
                          minWidth: 28,
                          minHeight: 28,
                        ),
                        padding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          if (_isRecordingVoice)
            _buildAdminRecordingBar(colors, kPrimary)
          else
            Row(
              children: [
                IconButton(
                  icon: Icon(
                    Icons.emoji_emotions,
                    color: colors.muted,
                    size: 20,
                  ),
                  onPressed: _showEmojiPicker,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  padding: EdgeInsets.zero,
                ),
                const SizedBox(width: 2),
                IconButton(
                  icon: Icon(Icons.attach_file, color: colors.muted, size: 20),
                  onPressed: _pickImage,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  padding: EdgeInsets.zero,
                ),
                // Language selector button
                Tooltip(
                  message: _selectedLanguage == 'en-US'
                      ? 'Switch to Nepali'
                      : 'Switch to English',
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedLanguage = _selectedLanguage == 'en-US'
                            ? 'ne-NP'
                            : 'en-US';
                        if (_webSpeechRecognition != null) {
                          _webSpeechRecognition!['lang'] = _selectedLanguage;
                        }
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 4,
                      ),
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: _isListening
                            ? (_selectedLanguage == 'ne-NP'
                                  ? (colors.isDark
                                        ? kLangNepaliDarkBg
                                        : Colors.red.shade50)
                                  : (colors.isDark
                                        ? kLangEnglishDarkBg
                                        : Colors.blue.shade50))
                            : colors.cardBg,
                        border: Border.all(
                          color: _selectedLanguage == 'ne-NP'
                              ? (colors.isDark
                                    ? kLangNepaliDarkBorder
                                    : Colors.red.shade300)
                              : (colors.isDark
                                    ? kLangEnglishDarkBorder
                                    : Colors.blue.shade300),
                          width: 1,
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _selectedLanguage == 'en-US' ? 'EN' : 'ने',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _selectedLanguage == 'ne-NP'
                              ? (colors.isDark
                                    ? kLangNepaliDarkText
                                    : Colors.red.shade700)
                              : (colors.isDark
                                    ? kLangEnglishDarkText
                                    : Colors.blue.shade700),
                        ),
                      ),
                    ),
                  ),
                ),
                // Mic button
                IconButton(
                  tooltip: _isListening
                      ? 'Stop voice typing'
                      : 'Start voice typing',
                  icon: Icon(
                    _isListening ? Icons.mic_off : Icons.mic,
                    color: _isListening ? kPrimary : colors.muted,
                    size: 20,
                  ),
                  onPressed: _isListening ? _stopListening : _startListening,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  padding: EdgeInsets.zero,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: CallbackShortcuts(
                    bindings: <ShortcutActivator, VoidCallback>{
                      const SingleActivator(LogicalKeyboardKey.enter): () {
                        final keys =
                            HardwareKeyboard.instance.logicalKeysPressed;
                        final bool hasModifier =
                            keys.contains(LogicalKeyboardKey.shiftLeft) ||
                            keys.contains(LogicalKeyboardKey.shiftRight) ||
                            keys.contains(LogicalKeyboardKey.controlLeft) ||
                            keys.contains(LogicalKeyboardKey.controlRight) ||
                            keys.contains(LogicalKeyboardKey.altLeft) ||
                            keys.contains(LogicalKeyboardKey.altRight) ||
                            keys.contains(LogicalKeyboardKey.metaLeft) ||
                            keys.contains(LogicalKeyboardKey.metaRight);

                        final int lineCount = _estimateLineCount(
                          _messageController.text,
                        );
                        final String trimmed = _messageController.text.trim();

                        if (!hasModifier &&
                            lineCount <= 2 &&
                            trimmed.isNotEmpty) {
                          _sendMessage();
                          return;
                        }

                        final selection = _messageController.selection;
                        final start = selection.start >= 0
                            ? selection.start
                            : _messageController.text.length;
                        final end = selection.end >= 0
                            ? selection.end
                            : _messageController.text.length;
                        final String newText = _messageController.text
                            .replaceRange(start, end, '\n');
                        _messageController.value = TextEditingValue(
                          text: newText,
                          selection: TextSelection.collapsed(offset: start + 1),
                        );
                      },
                    },
                    child: TextField(
                      controller: _messageController,
                      focusNode: _messageFocusNode,
                      textInputAction: TextInputAction.newline,
                      minLines: 1,
                      maxLines: 6,
                      onChanged: (text) {
                        if (chatProvider.id != null) {
                          _updateAdminTypingStatus(
                            text,
                            chatProvider.id.toString(),
                          );
                        }
                      },
                      style: TextStyle(color: colors.text, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: _selectedLanguage == 'ne-NP'
                            ? "सन्देश टाइप गर्नुहोस्"
                            : "Type a message",
                        hintStyle: TextStyle(color: colors.muted, fontSize: 14),
                        filled: true,
                        fillColor: colors.searchFill,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 12,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(
                            color: colors.border,
                            width: 1,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: kPrimary, width: 1.5),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(
                            color: colors.border,
                            width: 1,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _messageController,
                  builder: (context, value, child) {
                    final hasText = value.text.trim().isNotEmpty;
                    if (!hasText) {
                      return Listener(
                        // Release-to-send for hold-to-record on the admin mic button
                        onPointerUp: (_) {
                          if (_isHoldRecordingVoice && _isRecordingVoice) {
                            _isHoldRecordingVoice = false;
                            _stopAndSendVoiceRecording();
                          }
                        },
                        onPointerCancel: (_) {
                          if (_isHoldRecordingVoice && _isRecordingVoice) {
                            _isHoldRecordingVoice = false;
                            _cancelVoiceRecording();
                          }
                        },
                        child: GestureDetector(
                          onTap: _startVoiceRecording,
                          onLongPressStart: (details) async {
                            if (mounted)
                              setState(() => _isHoldRecordingVoice = true);
                            await _startVoiceRecording();
                          },
                          child: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: kPrimary,
                              borderRadius: BorderRadius.circular(19),
                            ),
                            child: const Icon(
                              Icons.mic,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ),
                      );
                    }
                    return GestureDetector(
                      onTap: _sendMessage,
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: hasText ? kPrimary : colors.border,
                          borderRadius: BorderRadius.circular(19),
                        ),
                        child: Icon(
                          Icons.send_rounded,
                          color: hasText ? Colors.white : colors.muted,
                          size: 18,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _pickImage() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: true,
        withData: kIsWeb,
      );
      if (result != null && result.files.isNotEmpty) {
        setState(() {
          _selectedImages = result.files;
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error picking image: $e")));
    }
  }

  void _sendImageMessage() {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);

    if (_selectedImages.isEmpty) return;

    // Capture and clear immediately so UI resets right away
    final List<PlatformFile> imagesToSend = List<PlatformFile>.from(
      _selectedImages,
    );
    final String receiverId = chatProvider.id.toString();

    setState(() {
      _selectedImages = [];
    });

    // Upload and send in background without blocking the UI
    _uploadImagesInBackground(imagesToSend, receiverId);
  }

  Future<void> _uploadImagesInBackground(
    List<PlatformFile> images,
    String receiverId,
  ) async {
    try {
      // Compress and upload all images in parallel for speed
      final List<String> urls = [];
      for (final file in images) {
        // Compress image before uploading
        final compressedBytes =
            await AdminImageCompression.compressImageForSending(file);

        final url = await _uploadChatImage(
          image: null, // Always use bytes after compression
          imageBytes: compressedBytes,
          fileName: file.name,
        );
        urls.add(url);
      }

      if (!mounted) return;
      final chatProvider = Provider.of<ChatProvider>(context, listen: false);
      final String roomId = AdminSocketService.chatRoomId(receiverId);
      final bool connected = _socketService.isConnected;

      if (urls.length == 1) {
        final msgId =
            'image_${DateTime.now().millisecondsSinceEpoch}_$senderId';
        if (connected) {
          _socketService.sendMessage(
            chatRoomId: roomId,
            receiverId: receiverId,
            message: urls.first,
            messageType: 'image',
            messageId: msgId,
            receiverName: chatProvider.namee,
            receiverImage: chatProvider.profilePicture,
          );
        } else {
          await _sendMessageViaHttp(
            roomId: roomId,
            receiverId: receiverId,
            message: urls.first,
            messageType: 'image',
            messageId: msgId,
            chatProvider: chatProvider,
          );
        }

        await NotificationService.sendChatNotification(
          recipientUserId: receiverId,
          senderName: "Admin",
          senderId: '1',
          message: '📷 Photo',
          extraData: {'chatId': receiverId, 'screen': 'chat'},
        );
      } else {
        final msgId =
            'gallery_${DateTime.now().millisecondsSinceEpoch}_$senderId';
        if (connected) {
          _socketService.sendMessage(
            chatRoomId: roomId,
            receiverId: receiverId,
            message: jsonEncode(urls),
            messageType: 'image_gallery',
            messageId: msgId,
            receiverName: chatProvider.namee,
            receiverImage: chatProvider.profilePicture,
          );
        } else {
          await _sendMessageViaHttp(
            roomId: roomId,
            receiverId: receiverId,
            message: jsonEncode(urls),
            messageType: 'image_gallery',
            messageId: msgId,
            chatProvider: chatProvider,
          );
        }

        await NotificationService.sendChatNotification(
          recipientUserId: receiverId,
          senderName: "Admin",
          senderId: '1',
          message: '📷 ${urls.length} Photos',
          extraData: {'chatId': receiverId, 'screen': 'chat'},
        );
      }
    } catch (e) {
      debugPrint('Failed to send image(s): $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Failed to send images. Please try again."),
          ),
        );
      }
    }
  }

  Future<String> _uploadChatImage({
    File? image,
    Uint8List? imageBytes,
    String? fileName,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse(
        kAdminSocketUrl,
      ).replace(path: '/upload', queryParameters: {'type': 'image'}),
    );

    if (kIsWeb) {
      if (imageBytes == null) {
        throw Exception('Missing image bytes');
      }
      final effectiveName =
          fileName ?? 'chat_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final mimeString = fileName != null
          ? _mimeTypeFromFilename(effectiveName)
          : 'image/jpeg';
      final mimeParts = mimeString.split('/');
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          imageBytes,
          filename: effectiveName,
          contentType: MediaType(mimeParts[0], mimeParts[1]),
        ),
      );
    } else {
      if (image == null) {
        throw Exception('Missing image file');
      }
      request.files.add(await http.MultipartFile.fromPath('file', image.path));
    }

    final response = await request.send();
    final body = await response.stream.bytesToString();
    if (response.statusCode != 200) {
      throw Exception('Upload failed: ${response.statusCode} $body');
    }

    final json = jsonDecode(body) as Map<String, dynamic>;
    final url = json['url']?.toString();
    if (url == null || url.isEmpty) {
      throw Exception(json['error']?.toString() ?? 'Upload returned no URL');
    }
    // Normalize to always use the known socket server base URL.
    // If PUBLIC_URL is not configured on the server the returned URL may be an
    // internal address (e.g. http://127.0.0.1:3001/...) that is unreachable
    // from clients.  Re-anchoring to kAdminSocketUrl makes images loadable
    // regardless of the server's proxy configuration.
    return _normalizeUploadUrl(url);
  }

  /// Ensures [url] uses [kAdminSocketUrl] as its base when the path starts
  /// with `/uploads/`.  The scheme and host are replaced with the known server
  /// while the path, query parameters, and fragment are preserved.
  /// Returns [url] unchanged for any other URL shape.
  static String _normalizeUploadUrl(String url) {
    try {
      final parsed = Uri.parse(url);
      if (parsed.path.startsWith('/uploads/')) {
        final base = Uri.parse(kAdminSocketUrl);
        return Uri(
          scheme: base.scheme,
          host: base.host,
          port: base.hasPort ? base.port : null,
          path: parsed.path,
          queryParameters: parsed.hasQuery ? parsed.queryParameters : null,
          fragment: parsed.hasFragment ? parsed.fragment : null,
        ).toString();
      }
    } catch (_) {}
    return url;
  }

  int _estimateLineCount(String text) {
    if (text.isEmpty) return 1;
    return text.split('\n').length;
  }

  /// Returns a MIME type string for the given filename based on its extension.
  /// Falls back to 'image/jpeg' for unknown or missing extensions.
  static String _mimeTypeFromFilename(String filename) {
    final ext = filename.contains('.')
        ? filename.split('.').last.toLowerCase()
        : '';
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'bmp':
        return 'image/bmp';
      case 'svg':
        return 'image/svg+xml';
      case 'heic':
        return 'image/heic';
      case 'heif':
        return 'image/heif';
      default:
        return 'image/jpeg';
    }
  }

  Future<void> _sendMessage() async {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    final receiverId = chatProvider.id?.toString();

    if (_messageController.text.trim().isEmpty || receiverId == null) return;

    final String messageText = _messageController.text.trim();

    // --- Inline Edit Mode ---
    if (_editingMessageId != null) {
      final messageId = _editingMessageId!;
      _messageController.clear();
      _textBeforeVoice = '';
      setState(() {
        _editingMessageId = null;
        _editingOriginalText = '';
      });
      FocusScope.of(context).requestFocus(_messageFocusNode);
      _clearAdminTypingStatus();
      try {
        await _applyMessageMutation(
          messageId: messageId,
          updates: {
            'message': messageText,
            'edited': true,
            'deleted': false,
            'unsent': false,
          },
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text("Failed to edit message: $e")));
        }
      }
      return;
    }

    // Clear immediately so the UI feels instant
    _messageController.clear();
    _textBeforeVoice = '';
    final replySnapshot = _replyingTo;
    setState(() => _replyingTo = null);
    FocusScope.of(context).requestFocus(_messageFocusNode);

    // Clear typing indicator immediately on send.
    _clearAdminTypingStatus();

    final String msgId =
        'msg_${DateTime.now().millisecondsSinceEpoch}_$senderId';
    final String roomId = AdminSocketService.chatRoomId(receiverId);

    try {
      if (_socketService.isConnected) {
        _socketService.sendMessage(
          chatRoomId: roomId,
          receiverId: receiverId,
          message: messageText,
          messageType: 'text',
          messageId: msgId,
          repliedTo: replySnapshot,
          receiverName: chatProvider.namee,
          receiverImage: chatProvider.profilePicture,
        );
      } else {
        // Socket unavailable — fall back to HTTP so the message is never lost
        await _sendMessageViaHttp(
          roomId: roomId,
          receiverId: receiverId,
          message: messageText,
          messageType: 'text',
          messageId: msgId,
          repliedTo: replySnapshot,
          chatProvider: chatProvider,
        );
      }

      await NotificationService.sendChatNotification(
        recipientUserId: receiverId,
        senderName: "Admin",
        senderId: '1',
        message: messageText,
        extraData: {'chatId': receiverId, 'screen': 'chat'},
      );
    } catch (e) {
      // Restore message text so user doesn't lose their content
      if (!mounted) return;
      if (_messageController.text.isEmpty) {
        _messageController.text = messageText;
        _messageController.selection = TextSelection.fromPosition(
          TextPosition(offset: messageText.length),
        );
        _textBeforeVoice = messageText;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Failed to send message. Please try again."),
        ),
      );
    }
  }

  /// Sends a message via the HTTP fallback endpoint when the socket is unavailable.
  Future<void> _sendMessageViaHttp({
    required String roomId,
    required String receiverId,
    required String message,
    required String messageType,
    required String messageId,
    Map<String, dynamic>? repliedTo,
    required ChatProvider chatProvider,
  }) async {
    final response = await http.post(
      Uri.parse(kAdminSocketUrl).replace(path: '/api/send-message'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'chatRoomId': roomId,
        'senderId': senderId.toString(),
        'receiverId': receiverId,
        'message': message,
        'messageType': messageType,
        'messageId': messageId,
        if (repliedTo != null) 'repliedTo': repliedTo,
        'user1Name': 'Admin',
        'user2Name': chatProvider.namee ?? '',
        'user1Image': '',
        'user2Image': chatProvider.profilePicture ?? '',
      }),
    );
    if (response.statusCode != 200) {
      throw Exception('HTTP fallback failed: ${response.statusCode}');
    }
  }

  // Facebook Messenger-style action overlay: emoji near message, actions at bottom
  Widget _buildMsgActionOverlay(BuildContext context) {
    const emojis = ['❤️', '😂', '😮', '😢', '👍', '😡'];
    final messageId = _overlayMessageId ?? '';
    final replyPayload = _overlayReplyPayload ?? {};
    final String? msgType = replyPayload['type']?.toString();
    final bool isImageMsg = msgType == 'image' || msgType == 'image_gallery';
    final String? imagePayload = msgType == 'image'
        ? replyPayload['imageUrl']?.toString()
        : (msgType == 'image_gallery'
              ? replyPayload['message']?.toString()
              : null);
    final bool canForward =
        isImageMsg && imagePayload != null && imagePayload.isNotEmpty;
    final copyInfo = _resolveCopyInfo(replyPayload);
    final String? copyText = copyInfo.copyText;
    final bool canCopy = copyInfo.canCopy;

    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    final String currentRoomId = AdminSocketService.chatRoomId(
      chatProvider.id?.toString() ?? '',
    );

    final msgData = _messages.firstWhere(
      (m) => m['messageId'] == messageId,
      orElse: () => <String, dynamic>{},
    );
    final Map<String, dynamic> reactions = (msgData['reactions'] is Map)
        ? Map<String, dynamic>.from(msgData['reactions'] as Map)
        : {};
    final String myReaction = reactions[kAdminUserId]?.toString() ?? '';

    final screenHeight = MediaQuery.of(context).size.height;
    final tapY = _overlayTapOffset.dy;

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
        if (mounted) setState(() => _showMsgActionOverlay = false);
      },
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: double.infinity,
        height: double.infinity,
        child: ColoredBox(
          color: Colors.black.withOpacity(0.45),
          child: Stack(
            children: [
              // Emoji bar near the message
              Positioned(
                top: emojiTop,
                left: 0,
                right: 0,
                child: Center(
                  child: GestureDetector(
                    onTap: () {},
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
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
                              if (mounted)
                                setState(() => _showMsgActionOverlay = false);
                              if (messageId.isNotEmpty) {
                                _socketService.addReaction(
                                  chatRoomId: currentRoomId,
                                  messageId: messageId,
                                  emoji: e,
                                );
                              }
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? const Color(0xFF7B61FF).withOpacity(0.15)
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
                  onTap: () {},
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFF1E1E1E),
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(20),
                      ),
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
                        _adminOverlayMenuItem(
                          Icons.reply_rounded,
                          "Reply",
                          const Color(0xFF7B61FF),
                          () {
                            if (mounted)
                              setState(() => _showMsgActionOverlay = false);
                            _startReply(
                              messageId,
                              replyPayload['message']?.toString() ?? '',
                              replyPayload['senderid']?.toString() ?? '',
                              replyPayload['senderName']?.toString() ?? 'User',
                              replyPayload,
                            );
                          },
                        ),
                        if (canForward)
                          _adminOverlayMenuItem(
                            Icons.forward_rounded,
                            "Forward",
                            const Color(0xFF10B981),
                            () {
                              if (mounted)
                                setState(() => _showMsgActionOverlay = false);
                              _forwardImage(imagePayload!, msgType ?? 'image');
                            },
                          ),
                        if (canCopy)
                          _adminOverlayMenuItem(
                            Icons.copy_rounded,
                            "Copy",
                            const Color(0xFF475569),
                            () {
                              if (mounted)
                                setState(() => _showMsgActionOverlay = false);
                              _copyToClipboard(copyText!);
                            },
                          ),
                        if (_overlayIsSentByMe && _overlayCanEdit)
                          _adminOverlayMenuItem(
                            Icons.edit,
                            "Edit",
                            const Color(0xFF0EA5E9),
                            () {
                              if (mounted)
                                setState(() => _showMsgActionOverlay = false);
                              _startEdit(
                                messageId,
                                replyPayload['message']?.toString() ?? '',
                              );
                            },
                          ),
                        if (_overlayCanMutate) ...[
                          _adminOverlayMenuItem(
                            Icons.delete,
                            "Delete",
                            const Color(0xFFEF4444),
                            () {
                              if (mounted)
                                setState(() => _showMsgActionOverlay = false);
                              _deleteMessage(messageId);
                            },
                          ),
                          _adminOverlayMenuItem(
                            Icons.remove_circle_outline_rounded,
                            "Unsend",
                            const Color(0xFFF59E0B),
                            () {
                              _unsendMessage(messageId);
                              if (mounted)
                                setState(() => _showMsgActionOverlay = false);
                            },
                          ),
                        ],
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

  Widget _adminOverlayMenuItem(
    IconData icon,
    String label,
    Color iconColor,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 18),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 20),
            const SizedBox(width: 14),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  void _showMessageOptions(
    BuildContext context,
    String messageId,
    Map<String, dynamic> replyPayload,
    bool isSentByMe, {
    required bool canEdit,
    required bool canMutate,
  }) {
    final String? msgType = replyPayload['type']?.toString();
    final bool isImageMsg = msgType == 'image' || msgType == 'image_gallery';
    final String? imagePayload = msgType == 'image'
        ? replyPayload['imageUrl']?.toString()
        : (msgType == 'image_gallery'
              ? replyPayload['message']?.toString()
              : null);
    final bool canForward =
        isImageMsg && imagePayload != null && imagePayload.isNotEmpty;
    final copyInfo = _resolveCopyInfo(replyPayload);
    final String? copyText = copyInfo.copyText;
    final bool canCopy = copyInfo.canCopy;
    final bool copyIsImage = copyInfo.isImage;

    // Get the current chat room ID
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    final String currentRoomId = AdminSocketService.chatRoomId(
      chatProvider.id?.toString() ?? '',
    );

    // Get current reactions for this message
    final msgData = _messages.firstWhere(
      (m) => m['messageId'] == messageId,
      orElse: () => <String, dynamic>{},
    );
    final Map<String, dynamic> reactions = (msgData['reactions'] is Map)
        ? Map<String, dynamic>.from(msgData['reactions'] as Map)
        : {};
    final String myReaction = reactions[kAdminUserId]?.toString() ?? '';
    const emojis = ['❤️', '😂', '😮', '😢', '👍', '😡'];

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Wrap(
          children: [
            // Emoji reaction row
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: emojis.map((e) {
                  final isSelected = myReaction == e;
                  return GestureDetector(
                    onTap: () {
                      Navigator.pop(ctx);
                      _socketService.addReaction(
                        chatRoomId: currentRoomId,
                        messageId: messageId,
                        emoji: e,
                      );
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFF7B61FF).withOpacity(0.15)
                            : Colors.transparent,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        e,
                        style: TextStyle(fontSize: isSelected ? 30 : 26),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(
                Icons.reply_rounded,
                size: 20,
                color: Color(0xFF7B61FF),
              ),
              title: const Text("Reply", style: TextStyle(fontSize: 14)),
              onTap: () {
                Navigator.pop(ctx);
                _startReply(
                  messageId,
                  replyPayload['message']?.toString() ?? '',
                  replyPayload['senderid']?.toString() ?? '',
                  replyPayload['senderName']?.toString() ?? 'User',
                  replyPayload,
                );
              },
            ),
            if (canForward)
              ListTile(
                leading: const Icon(
                  Icons.forward_rounded,
                  size: 20,
                  color: Color(0xFF10B981),
                ),
                title: const Text("Forward", style: TextStyle(fontSize: 14)),
                onTap: () {
                  Navigator.pop(ctx);
                  _forwardImage(imagePayload!, msgType ?? 'image');
                },
              ),
            if (canCopy)
              ListTile(
                leading: const Icon(
                  Icons.copy_rounded,
                  size: 20,
                  color: Color(0xFF475569),
                ),
                title: Text(
                  copyIsImage ? "Copy Link" : "Copy",
                  style: const TextStyle(fontSize: 14),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _copyToClipboard(copyText!);
                },
              ),
            if (isSentByMe && canEdit) ...[
              ListTile(
                leading: const Icon(
                  Icons.edit,
                  size: 20,
                  color: Color(0xFF0EA5E9),
                ),
                title: const Text("Edit", style: TextStyle(fontSize: 14)),
                onTap: () {
                  Navigator.pop(ctx);
                  _startEdit(
                    messageId,
                    replyPayload['message']?.toString() ?? '',
                  );
                },
              ),
            ],
            if (canMutate) ...[
              ListTile(
                leading: const Icon(
                  Icons.delete,
                  size: 20,
                  color: Color(0xFFEF4444),
                ),
                title: const Text("Delete", style: TextStyle(fontSize: 14)),
                onTap: () {
                  Navigator.pop(ctx);
                  _deleteMessage(messageId);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.remove_circle_outline_rounded,
                  size: 20,
                  color: Color(0xFFF59E0B),
                ),
                title: const Text("Unsend", style: TextStyle(fontSize: 14)),
                onTap: () {
                  _unsendMessage(messageId);
                  Navigator.pop(ctx);
                },
              ),
            ],
          ],
        );
      },
    );
  }

  void _editMessage(String messageId, String currentMessage) {
    _startEdit(messageId, currentMessage);
  }

  void _replyToMessage(
    String originalMessage,
    String messageId,
    String senderid,
    String senderName,
  ) {
    _startReply(messageId, originalMessage, senderid, senderName);
  }

  Future<void> _copyToClipboard(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Copied to clipboard'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  /// Returns the copyable text and whether the copy action is available for a
  /// given message payload. Used by both the overlay and the bottom sheet.
  ({String? copyText, bool canCopy, bool isImage}) _resolveCopyInfo(
    Map<String, dynamic> replyPayload,
  ) {
    final String? msgType = replyPayload['type']?.toString();
    final bool isImageMsg = msgType == 'image' || msgType == 'image_gallery';
    final String? imagePayload = msgType == 'image'
        ? replyPayload['imageUrl']?.toString()
        : (msgType == 'image_gallery'
              ? replyPayload['message']?.toString()
              : null);
    final String? copyText = isImageMsg
        ? imagePayload
        : ((msgType == null || msgType == 'text')
              ? replyPayload['message']?.toString()
              : null);
    final bool canCopy =
        copyText != null &&
        copyText.isNotEmpty &&
        replyPayload['deleted'] != true &&
        replyPayload['unsent'] != true;
    return (copyText: copyText, canCopy: canCopy, isImage: isImageMsg);
  }

  void _deleteMessage(String messageId) {
    _applyMessageMutation(
      messageId: messageId,
      updates: {
        'message': _kDeletedMessageText,
        'deleted': true,
        'unsent': false,
        'edited': false,
      },
    ).catchError((error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete message: $error')),
        );
      }
    });
  }

  void _unsendMessage(String messageId) {
    _applyMessageMutation(
      messageId: messageId,
      updates: {
        'message': _kUnsentMessageText,
        'unsent': true,
        'deleted': false,
        'edited': false,
      },
    ).catchError((error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to unsend message: $error')),
        );
      }
    });
  }

  // ── SEND REPORT WARNING ──────────────────────────────────────────────────

  /// Sends a warning message to the reported user (identified by [reportedUserId])
  /// WITHOUT revealing who filed the report. Shows a dialog so the admin can
  /// review / edit the message before sending.
  Future<void> _sendReportWarning({
    required String reportedUserId,
    required String reportedUserName,
    required String reportReason,
  }) async {
    if (reportedUserId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reported user information not found')),
        );
      }
      return;
    }

    final String defaultMessage = reportReason.isNotEmpty
        ? '⚠️ Your profile has been reported. Reason: $reportReason. Please review our community guidelines to ensure your profile complies with our policies.'
        : '⚠️ Your profile has been reported. Please review our community guidelines to ensure your profile complies with our policies.';

    final TextEditingController msgController = TextEditingController(
      text: defaultMessage,
    );

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Send Warning to User'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (reportedUserName.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'To: $reportedUserName',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ),
            TextField(
              controller: msgController,
              maxLines: 5,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Enter warning message...',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Send Warning'),
          ),
        ],
      ),
    );

    final String finalMessage = msgController.text.trim().isEmpty
        ? defaultMessage
        : msgController.text.trim();
    msgController.dispose();

    if (confirmed != true || !mounted) return;

    try {
      final connected = await _socketService.ensureConnected();
      if (!connected) throw Exception('Socket not connected');

      _socketService.sendMessage(
        chatRoomId: AdminSocketService.chatRoomId(reportedUserId),
        receiverId: reportedUserId,
        message: finalMessage,
        messageType: 'text',
        messageId: 'warn_${DateTime.now().millisecondsSinceEpoch}_$senderId',
        receiverName: reportedUserName,
      );

      await NotificationService.sendChatNotification(
        recipientUserId: reportedUserId,
        senderName: 'Admin',
        senderId: '1',
        message: '⚠️ Warning from Admin',
        extraData: {'chatId': reportedUserId, 'screen': 'chat'},
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Warning sent to $reportedUserName'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send warning: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ── FORWARD IMAGE ────────────────────────────────────────────────────────

  /// Shows a user-picker dialog and forwards [imagePayload] (a URL for single
  /// images or a JSON array for galleries) to the selected user's chat room
  /// without re-uploading the image bytes.
  Future<void> _forwardImage(String imagePayload, String messageType) async {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    final List<Map<String, String>> users = List<Map<String, String>>.from(
      chatProvider.chatList,
    );
    if (users.isEmpty) return;

    final selectedUser = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => _ForwardUserPickerDialog(users: users),
    );

    if (selectedUser == null) return;

    final String targetId = selectedUser['id'] ?? '';
    final String targetName = selectedUser['namee'] ?? 'User';
    final String targetAvatar = selectedUser['profile_picture'] ?? '';
    if (targetId.isEmpty) return;

    try {
      final connected = await _socketService.ensureConnected();
      if (!connected) throw Exception('Socket not connected');

      _socketService.sendMessage(
        chatRoomId: AdminSocketService.chatRoomId(targetId),
        receiverId: targetId,
        message: imagePayload,
        messageType: messageType,
        messageId: 'fwd_${DateTime.now().millisecondsSinceEpoch}_$senderId',
        receiverName: targetName,
        receiverImage: targetAvatar,
      );

      await NotificationService.sendChatNotification(
        recipientUserId: targetId,
        senderName: "Admin",
        senderId: '1',
        message: '📷 Photo',
        extraData: {'chatId': targetId, 'screen': 'chat'},
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Photo forwarded to $targetName')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to forward photo: $e')));
      }
    }
  }

  // ── INLINE REPLY / EDIT ─────────────────────────────────────────────────

  void _startReply(
    String messageId,
    String message,
    String senderid,
    String senderName, [
    Map<String, dynamic>? payload,
  ]) {
    setState(() {
      _replyingTo =
          payload ??
          _buildFallbackReplyPayload(
            messageId: messageId,
            message: message,
            senderId: senderid,
            senderName: senderName,
          );
      _editingMessageId = null;
    });
    FocusScope.of(context).requestFocus(_messageFocusNode);
  }

  void _startEdit(String messageId, String message) {
    setState(() {
      _editingMessageId = messageId;
      _editingOriginalText = message;
      _replyingTo = null;
      _messageController.text = message;
      _messageController.selection = TextSelection.fromPosition(
        TextPosition(offset: message.length),
      );
    });
    FocusScope.of(context).requestFocus(_messageFocusNode);
  }

  void _cancelAction() {
    setState(() {
      _replyingTo = null;
      if (_editingMessageId != null) {
        _editingMessageId = null;
        _editingOriginalText = '';
        _messageController.clear();
      }
    });
    FocusScope.of(context).requestFocus(_messageFocusNode);
  }

  void _showEmojiPicker() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          content: SizedBox(
            height: 240,
            width: 240,
            child: EmojiPicker(
              onEmojiSelected: (category, emoji) {
                setState(() {
                  _messageController.text += emoji.emoji;
                });
              },
              config: Config(),
            ),
          ),
        );
      },
    );
  }

  void _searchMessages(String query) {
    final lowerQuery = query.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredMessages.clear();
      } else {
        _filteredMessages = _messages.where((message) {
          final text = message['message']?.toString().toLowerCase() ?? '';
          return text.contains(lowerQuery);
        }).toList();
      }
    });
  }

  @override
  void dispose() {
    _removeCallOverlay();
    _typingTimer?.cancel();
    _typingStopTimer?.cancel();
    _replyHighlightTimer?.cancel();
    _floatingDateTimer?.cancel();
    _floatingDateNotifier.dispose();
    _newMsgSub?.cancel();
    _editedMsgSub?.cancel();
    _deletedMsgSub?.cancel();
    _unsentMsgSub?.cancel();
    _likedMsgSub?.cancel();
    _reactionMsgSub?.cancel();
    _readMsgSub?.cancel();
    _typingStartSub?.cancel();
    _typingStopSub?.cancel();
    _incomingCallSub?.cancel();
    _clearAdminTypingStatus();
    _scrollController.dispose();
    _messageFocusNode.dispose();
    _messageController.dispose();
    _searchController.dispose();
    _recorder.closeRecorder();
    _voiceRecordTimer?.cancel();
    _voicePlayerStateSub?.cancel();
    _voicePlayerPositionSub?.cancel();
    _voicePlayerDurationSub?.cancel();
    _voiceAudioPlayer.dispose();
    _typingAudioPlayer.dispose();
    super.dispose();
  }
}

class _HighlightableMessageContainer extends StatelessWidget {
  static const double _kHighlightOpacity = 0.9;

  const _HighlightableMessageContainer({
    super.key,
    required this.child,
    required this.isHighlighted,
  });

  final Widget child;
  final bool isHighlighted;

  @override
  Widget build(BuildContext context) {
    final colors = ChatColors.of(context);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
      decoration: BoxDecoration(
        color: isHighlighted
            ? colors.primaryLight.withOpacity(_kHighlightOpacity)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }
}

class _HoverableMessageBubble extends StatefulWidget {
  const _HoverableMessageBubble({
    required this.bubble,
    required this.isSentByMe,
    required this.onReply,
    this.onEdit,
    this.onDelete,
    this.onUnsend,
    this.onForward,
    this.onCopy,
    this.canEdit = false,
    this.canDelete = false,
    this.canUnsend = false,
  });

  final Widget bubble;
  final bool isSentByMe;
  final VoidCallback onReply;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onUnsend;
  final VoidCallback? onForward;
  final VoidCallback? onCopy;
  final bool canEdit;
  final bool canDelete;
  final bool canUnsend;

  @override
  State<_HoverableMessageBubble> createState() =>
      _HoverableMessageBubbleState();
}

class _HoverableMessageBubbleState extends State<_HoverableMessageBubble>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeIn,
    );
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  void _onEnter(_) {
    setState(() => _isHovered = true);
    _fadeController.forward();
  }

  void _onExit(_) {
    setState(() => _isHovered = false);
    _fadeController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final actionMenu = _MessageActionMenu(
      onReply: widget.onReply,
      onEdit: widget.onEdit,
      onDelete: widget.onDelete,
      onUnsend: widget.onUnsend,
      onForward: widget.onForward,
      onCopy: widget.onCopy,
      canEdit: widget.canEdit,
      canDelete: widget.canDelete,
      canUnsend: widget.canUnsend,
    );

    return MouseRegion(
      onEnter: _onEnter,
      onExit: _onExit,
      child: Row(
        mainAxisAlignment: widget.isSentByMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (widget.isSentByMe)
            FadeTransition(
              opacity: _fadeAnimation,
              child: IgnorePointer(ignoring: !_isHovered, child: actionMenu),
            ),
          Flexible(child: widget.bubble),
          if (!widget.isSentByMe)
            FadeTransition(
              opacity: _fadeAnimation,
              child: IgnorePointer(ignoring: !_isHovered, child: actionMenu),
            ),
        ],
      ),
    );
  }
}

/// Small dropdown icon button that opens the WhatsApp-style popup menu.
class _MessageActionMenu extends StatelessWidget {
  const _MessageActionMenu({
    required this.onReply,
    this.onEdit,
    this.onDelete,
    this.onUnsend,
    this.onForward,
    this.onCopy,
    this.canEdit = false,
    this.canDelete = false,
    this.canUnsend = false,
  });

  final VoidCallback onReply;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onUnsend;
  final VoidCallback? onForward;
  final VoidCallback? onCopy;
  final bool canEdit;
  final bool canDelete;
  final bool canUnsend;

  @override
  Widget build(BuildContext context) {
    const kPrimary = Color(0xFF7B61FF);

    return PopupMenuButton<_MsgAction>(
      padding: EdgeInsets.zero,
      icon: const Icon(
        Icons.keyboard_arrow_down_rounded,
        size: 17,
        color: Color(0xFF94A3B8),
      ),
      iconSize: 17,
      splashRadius: 14,
      tooltip: '',
      offset: const Offset(0, 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      elevation: 6,
      color: Colors.white,
      onSelected: (action) {
        switch (action) {
          case _MsgAction.reply:
            onReply();
            break;
          case _MsgAction.edit:
            onEdit?.call();
            break;
          case _MsgAction.delete:
            onDelete?.call();
            break;
          case _MsgAction.unsend:
            onUnsend?.call();
            break;
          case _MsgAction.forward:
            onForward?.call();
            break;
          case _MsgAction.copy:
            onCopy?.call();
            break;
        }
      },
      itemBuilder: (context) => [
        _menuItem(_MsgAction.reply, Icons.reply_rounded, 'Reply', kPrimary),
        if (onCopy != null)
          _menuItem(
            _MsgAction.copy,
            Icons.copy_rounded,
            'Copy',
            const Color(0xFF475569),
          ),
        if (onForward != null)
          _menuItem(
            _MsgAction.forward,
            Icons.forward_rounded,
            'Forward',
            const Color(0xFF10B981),
          ),
        if (canEdit)
          _menuItem(
            _MsgAction.edit,
            Icons.edit_outlined,
            'Edit',
            const Color(0xFF0EA5E9),
          ),
        if (canDelete)
          _menuItem(
            _MsgAction.delete,
            Icons.delete_outline_rounded,
            'Delete',
            const Color(0xFFEF4444),
          ),
        if (canUnsend)
          _menuItem(
            _MsgAction.unsend,
            Icons.remove_circle_outline_rounded,
            'Unsend',
            const Color(0xFFF59E0B),
          ),
      ],
    );
  }

  PopupMenuItem<_MsgAction> _menuItem(
    _MsgAction value,
    IconData icon,
    String label,
    Color color,
  ) {
    return PopupMenuItem<_MsgAction>(
      value: value,
      height: 38,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

enum _MsgAction { reply, edit, delete, unsend, forward, copy }

// ---------------------------------------------------------------------------
// Data class grouping chat messages by calendar date.
// ---------------------------------------------------------------------------
class _ChatMessageDateGroup {
  final DateTime date;
  final String headerLabel;
  final List<Map<String, dynamic>> messages;

  _ChatMessageDateGroup({
    required this.date,
    required this.headerLabel,
    required List<Map<String, dynamic>> messages,
  }) : messages = List<Map<String, dynamic>>.from(messages);
}

// ---------------------------------------------------------------------------
// Inline (non-pinned) sliver header that shows the date chip between message groups.
// ---------------------------------------------------------------------------
class _ChatDateHeaderDelegate extends SliverPersistentHeaderDelegate {
  static const double kExtent = 36.0;

  final String label;
  final Color backgroundColor;
  final Color chipColor;
  final Color textColor;
  final Color borderColor;

  const _ChatDateHeaderDelegate({
    required this.label,
    required this.backgroundColor,
    required this.chipColor,
    required this.textColor,
    required this.borderColor,
  });

  @override
  double get minExtent => kExtent;

  @override
  double get maxExtent => kExtent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      color: backgroundColor,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: chipColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: 0.5),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: textColor,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(_ChatDateHeaderDelegate oldDelegate) {
    return oldDelegate.label != label ||
        oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.chipColor != chipColor ||
        oldDelegate.textColor != textColor ||
        oldDelegate.borderColor != borderColor;
  }
}

/// Animated voice waveform widget used in the admin recording bar.
/// Uses its own [AnimationController] so [_ChatWindowState] does not need
/// to mix in [TickerProviderStateMixin].
class _AdminVoiceWaveform extends StatefulWidget {
  final Color color;
  const _AdminVoiceWaveform({required this.color});

  @override
  State<_AdminVoiceWaveform> createState() => _AdminVoiceWaveformState();
}

class _AdminVoiceWaveformState extends State<_AdminVoiceWaveform>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
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
        const barCount = 16;
        const maxH = 16.0;
        const minH = 3.0;
        final t = _controller.value;
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List.generate(barCount, (i) {
            final phase = (i / barCount) * 2 * math.pi;
            final h =
                minH +
                (maxH - minH) * (0.5 + 0.5 * math.sin(2 * math.pi * t + phase));
            return Container(
              width: 2.5,
              height: h,
              decoration: BoxDecoration(
                color: widget.color.withOpacity(0.75),
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Admin swipe-to-reply wrapper
// Encapsulates swipe state so that per-frame offset updates rebuild only this
// widget instead of the full chat screen.
// ---------------------------------------------------------------------------
class _AdminSwipeToReplyWrapper extends StatefulWidget {
  const _AdminSwipeToReplyWrapper({
    super.key,
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
  State<_AdminSwipeToReplyWrapper> createState() =>
      _AdminSwipeToReplyWrapperState();
}

class _AdminSwipeToReplyWrapperState extends State<_AdminSwipeToReplyWrapper>
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
    _anim = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut));
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
                          child: Icon(
                            Icons.reply,
                            color: Colors.grey.withOpacity(opacity),
                          ),
                        ),
                      if (!widget.isMine)
                        Padding(
                          padding: const EdgeInsets.only(right: 20),
                          child: Icon(
                            Icons.reply,
                            color: Colors.grey.withOpacity(opacity),
                          ),
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

/// Full-screen gallery viewer dialog for admin chat.
class _AdminGalleryViewerDialog extends StatefulWidget {
  final List<String> urls;
  final int initialIndex;

  const _AdminGalleryViewerDialog({
    required this.urls,
    required this.initialIndex,
  });

  @override
  State<_AdminGalleryViewerDialog> createState() =>
      _AdminGalleryViewerDialogState();
}

class _AdminGalleryViewerDialogState extends State<_AdminGalleryViewerDialog> {
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

  void _prev() {
    if (_current > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _next() {
    if (_current < widget.urls.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
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
            itemBuilder: (ctx, i) => _ZoomablePageImage(url: widget.urls[i]),
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
          // Image counter (e.g. "2 / 5")
          if (widget.urls.length > 1)
            Positioned(
              top: 44,
              left: 0,
              right: 52,
              child: Center(
                child: Text(
                  '${_current + 1} / ${widget.urls.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
                  ),
                ),
              ),
            ),
          // Prev arrow
          if (widget.urls.length > 1 && _current > 0)
            Positioned(
              left: 4,
              top: 0,
              bottom: 0,
              child: Center(
                child: Material(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(24),
                  child: IconButton(
                    icon: const Icon(
                      Icons.chevron_left,
                      color: Colors.white,
                      size: 36,
                    ),
                    onPressed: _prev,
                  ),
                ),
              ),
            ),
          // Next arrow
          if (widget.urls.length > 1 && _current < widget.urls.length - 1)
            Positioned(
              right: 4,
              top: 0,
              bottom: 0,
              child: Center(
                child: Material(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(24),
                  child: IconButton(
                    icon: const Icon(
                      Icons.chevron_right,
                      color: Colors.white,
                      size: 36,
                    ),
                    onPressed: _next,
                  ),
                ),
              ),
            ),
          // Page indicator dots
          if (widget.urls.length > 1)
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  widget.urls.length,
                  (i) => Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: _current == i ? 10 : 6,
                    height: _current == i ? 10 : 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _current == i ? Colors.white : Colors.white38,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A zoomable image page that passes horizontal swipes to the parent [PageView]
/// when the image is at 1× zoom, and enables panning only when zoomed in.
class _ZoomablePageImage extends StatefulWidget {
  final String url;
  const _ZoomablePageImage({required this.url});

  @override
  State<_ZoomablePageImage> createState() => _ZoomablePageImageState();
}

class _ZoomablePageImageState extends State<_ZoomablePageImage> {
  final TransformationController _ctrl = TransformationController();
  bool _zoomed = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onInteractionUpdate(ScaleUpdateDetails details) {
    final scale = _ctrl.value.getMaxScaleOnAxis();
    final isZoomed = scale > 1.01;
    if (isZoomed != _zoomed) setState(() => _zoomed = isZoomed);
  }

  void _onInteractionEnd(ScaleEndDetails details) {
    final scale = _ctrl.value.getMaxScaleOnAxis();
    if (scale <= 1.01) {
      _ctrl.value = Matrix4.identity();
      if (_zoomed) setState(() => _zoomed = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      transformationController: _ctrl,
      panEnabled: _zoomed,
      onInteractionUpdate: _onInteractionUpdate,
      onInteractionEnd: _onInteractionEnd,
      child: Center(
        child: CachedNetworkImage(
          imageUrl: widget.url,
          fit: BoxFit.contain,
          fadeInDuration: const Duration(milliseconds: 150),
          placeholder: (_, __) => const Center(
            child: CircularProgressIndicator(
              color: Colors.white54,
              strokeWidth: 2,
            ),
          ),
          errorWidget: (_, __, ___) => Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.image_not_supported_outlined,
                color: Colors.white54,
                size: 64,
              ),
              const SizedBox(height: 8),
              const Text(
                'File not found',
                style: TextStyle(color: Colors.white54, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Mini-profile bottom sheet for Admin Chat ────────────────────────────────

class _AdminSharedPhoto {
  final String url;
  final String? messageId;

  const _AdminSharedPhoto({required this.url, this.messageId});
}

class _AdminUserProfileSheet extends StatelessWidget {
  final int userId;
  final String name;
  final String? avatarUrl;
  final bool isOnline;
  final bool isPaid;
  final List<_AdminSharedPhoto> sharedPhotos;
  final void Function(BuildContext context, int userId) onViewProfile;
  final ValueChanged<String> onDeleteMessage;

  const _AdminUserProfileSheet({
    required this.userId,
    required this.name,
    this.avatarUrl,
    required this.isOnline,
    required this.isPaid,
    required this.sharedPhotos,
    required this.onViewProfile,
    required this.onDeleteMessage,
  });

  void _openPhotoViewer(BuildContext context, int index) {
    if (sharedPhotos.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _AdminPhotoViewerPage(
          photos: sharedPhotos,
          initialIndex: index,
          userName: name,
          userId: userId,
          onDeleteMessage: onDeleteMessage,
        ),
      ),
    );
  }

  void _openGalleryGrid(BuildContext context) {
    if (sharedPhotos.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _AdminGalleryGridPage(
          photos: sharedPhotos,
          userName: name,
          userId: userId,
          onDeleteMessage: onDeleteMessage,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: const Color(0xFFF1F5F9),
                    backgroundImage:
                        (avatarUrl != null && avatarUrl!.isNotEmpty)
                        ? NetworkImage(avatarUrl!)
                        : null,
                    child: (avatarUrl == null || avatarUrl!.isEmpty)
                        ? const Icon(Icons.person, size: 30, color: Colors.grey)
                        : null,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                name,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                          ],
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
                              isOnline ? 'Online' : 'Offline',
                              style: TextStyle(
                                fontSize: 13,
                                color: isOnline
                                    ? Colors.green
                                    : Colors.grey[600],
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
                      onTap: () => _openGalleryGrid(context),
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
                  itemCount: sharedPhotos.length > 8 ? 8 : sharedPhotos.length,
                  itemBuilder: (ctx, i) {
                    final isLastVisible = i == 7 && sharedPhotos.length > 8;
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
                              CachedNetworkImage(
                                imageUrl: sharedPhotos[i].url,
                                fit: BoxFit.cover,
                                memCacheWidth: 80,
                                memCacheHeight: 80,
                                fadeInDuration: const Duration(
                                  milliseconds: 150,
                                ),
                                placeholder: (_, __) => Container(
                                  color: Colors.grey.shade200,
                                  child: const Center(
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                ),
                                errorWidget: (_, __, ___) => Container(
                                  color: Colors.grey.shade200,
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.image_not_supported_outlined,
                                        color: Colors.grey.shade500,
                                        size: 22,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Not found',
                                        style: TextStyle(
                                          color: Colors.grey.shade600,
                                          fontSize: 9,
                                        ),
                                      ),
                                    ],
                                  ),
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
                    // Open profile in new tab
                    onViewProfile(context, userId);
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
}

// ─── Full-screen photo viewer for Admin Chat ──────────────────────────────────

class _AdminPhotoViewerPage extends StatefulWidget {
  final List<_AdminSharedPhoto> photos;
  final int initialIndex;
  final String userName;
  final int userId;
  final ValueChanged<String> onDeleteMessage;

  const _AdminPhotoViewerPage({
    required this.photos,
    required this.initialIndex,
    required this.userName,
    required this.userId,
    required this.onDeleteMessage,
  });

  @override
  State<_AdminPhotoViewerPage> createState() => _AdminPhotoViewerPageState();
}

class _AdminPhotoViewerPageState extends State<_AdminPhotoViewerPage> {
  late final PageController _pageController;
  late final ScrollController _thumbScrollController;
  late int _current;
  late List<_AdminSharedPhoto> _photos;
  final Map<int, TransformationController> _transformControllers = {};
  TapDownDetails? _lastTapDownDetails;

  static const double _thumbSize = 60.0;
  static const double _thumbSpacing = 6.0;
  static const double _viewerHeaderHeight = 76.0;
  static const double _thumbStripHeight = _thumbSize + 20.0;
  static const double _tapZoomScale = 2.4;

  @override
  void initState() {
    super.initState();
    _photos = List<_AdminSharedPhoto>.from(widget.photos);
    _current = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    _thumbScrollController = ScrollController();
    // Pre-initialize transformation controllers for better performance
    for (int i = 0; i < _photos.length; i++) {
      _transformControllers[i] = TransformationController();
    }
  }

  void _scrollThumbToVisible(int index) {
    if (!_thumbScrollController.hasClients) return;
    final double offset = index * (_thumbSize + _thumbSpacing);
    final double viewportWidth =
        _thumbScrollController.position.viewportDimension;
    final double maxExtent = _thumbScrollController.position.maxScrollExtent;
    final double target = (offset - (viewportWidth / 2) + (_thumbSize / 2))
        .clamp(0.0, maxExtent);
    // Only animate if the thumbnail is not already fully visible
    final double current = _thumbScrollController.offset;
    final bool alreadyVisible =
        target >= current && target + _thumbSize <= current + viewportWidth;
    if (alreadyVisible) return;
    _thumbScrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    _thumbScrollController.dispose();
    for (final controller in _transformControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _copyCurrentPhoto() async {
    if (_photos.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _photos[_current].url));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Photo link copied')));
  }

  Future<void> _photoCopyCurrent() async {
    if (_photos.isEmpty) return;
    final url = _photos[_current].url;
    if (kIsWeb) {
      final uri = Uri.tryParse(url);
      final lastSegment = (uri != null && uri.pathSegments.isNotEmpty)
          ? uri.pathSegments.last
          : '';
      final hasKnownExt = RegExp(
        r'\.(png|jpe?g|webp|gif|bmp|heic|heif)$',
        caseSensitive: false,
      ).hasMatch(lastSegment);
      final ext = hasKnownExt ? lastSegment.split('.').last : 'img';
      final anchor = html.AnchorElement(href: url)
        ..setAttribute(
          'download',
          'photo_${DateTime.now().millisecondsSinceEpoch}.$ext',
        )
        ..target = '_blank';
      anchor.click();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Photo copy/download started')),
      );
      return;
    }
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Future<void> _deleteCurrentPhoto() async {
    if (_photos.isEmpty) return;
    final photo = _photos[_current];
    final messageId = photo.messageId;
    if (messageId == null || messageId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Delete unavailable for this photo')),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Photo Message'),
        content: const Text(
          'This will delete the related chat photo message. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    widget.onDeleteMessage(messageId);
    for (final controller in _transformControllers.values) {
      controller.dispose();
    }
    _transformControllers.clear();
    final updated = List<_AdminSharedPhoto>.from(_photos)..removeAt(_current);
    if (updated.isEmpty) {
      if (!mounted) return;
      Navigator.pop(context);
      return;
    }
    final int nextIndex = _current.clamp(0, updated.length - 1);
    for (int i = 0; i < updated.length; i++) {
      _transformControllers[i] = TransformationController();
    }
    setState(() {
      _photos = updated;
      _current = nextIndex;
    });
    _pageController.jumpToPage(_current);
  }

  @override
  Widget build(BuildContext context) {
    final c = ChatColors.of(context);
    final media = MediaQuery.of(context);
    final double topInset = media.padding.top + _viewerHeaderHeight;
    if (_photos.isEmpty) {
      return Scaffold(
        backgroundColor: c.bg,
        body: const Center(child: Text('No photos')),
      );
    }
    return Scaffold(
      backgroundColor: c.bg,
      body: Stack(
        children: [
          Positioned.fill(
            top: topInset,
            bottom: _thumbStripHeight, // leave space for thumbnail strip
            child: PageView.builder(
              controller: _pageController,
              itemCount: _photos.length,
              onPageChanged: (i) {
                setState(() => _current = i);
                // Reset zoom on any non-current images when switching pages
                for (final entry in _transformControllers.entries) {
                  if (entry.key != i) {
                    entry.value.value = Matrix4.identity();
                  }
                }
                // Keep the selected thumbnail visible
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _scrollThumbToVisible(i);
                });
              },
              itemBuilder: (ctx, i) {
                final transformController = _transformControllers[i]!;
                return GestureDetector(
                  onTapDown: (details) => _lastTapDownDetails = details,
                  onTap: () {
                    final double currentScale = transformController.value
                        .getMaxScaleOnAxis();
                    if (currentScale > 1.05) {
                      setState(
                        () => transformController.value = Matrix4.identity(),
                      );
                      return;
                    }
                    final Offset? pos = _lastTapDownDetails?.localPosition;
                    final Matrix4 next = Matrix4.identity();
                    if (pos != null) {
                      next.translate(
                        -pos.dx * (_tapZoomScale - 1),
                        -pos.dy * (_tapZoomScale - 1),
                      );
                    }
                    next.scale(_tapZoomScale);
                    setState(() => transformController.value = next);
                  },
                  child: InteractiveViewer(
                    transformationController: transformController,
                    minScale: 1.0,
                    maxScale: 4.0,
                    panEnabled: true,
                    scaleEnabled: true,
                    boundaryMargin: const EdgeInsets.all(double.infinity),
                    child: Center(
                      child: CachedNetworkImage(
                        imageUrl: _photos[i].url,
                        fit: BoxFit.contain,
                        fadeInDuration: const Duration(milliseconds: 150),
                        placeholder: (_, __) => const Center(
                          child: CircularProgressIndicator(
                            color: Colors.white54,
                            strokeWidth: 2,
                          ),
                        ),
                        errorWidget: (_, __, ___) => Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.image_not_supported_outlined,
                              color: Colors.white54,
                              size: 64,
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'File not found',
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Container(
                margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: c.header.withOpacity(0.95),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: c.border),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back, color: c.text),
                      onPressed: () => Navigator.pop(context),
                      tooltip: 'Close',
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.userName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: c.text,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'ID: ${widget.userId}',
                            style: TextStyle(color: c.muted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.copy_rounded, color: c.text),
                      onPressed: _copyCurrentPhoto,
                      tooltip: 'Copy',
                    ),
                    IconButton(
                      icon: Icon(Icons.file_copy_outlined, color: c.text),
                      onPressed: _photoCopyCurrent,
                      tooltip: 'Photo copy',
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        color: Color(0xFFEF4444),
                      ),
                      onPressed: _deleteCurrentPhoto,
                      tooltip: 'Delete',
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Page counter
          Positioned(
            top: topInset + 6,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                '${_current + 1} / ${_photos.length}',
                style: TextStyle(color: c.muted, fontSize: 14),
              ),
            ),
          ),
          // Thumbnail strip footer
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              color: Colors.black.withOpacity(0.75),
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: SizedBox(
                height: _thumbSize,
                child: ListView.builder(
                  controller: _thumbScrollController,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _photos.length,
                  itemBuilder: (ctx, i) {
                    final isSelected = i == _current;
                    return GestureDetector(
                      onTap: () {
                        _pageController.animateToPage(
                          i,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        );
                      },
                      child: Container(
                        width: _thumbSize,
                        height: _thumbSize,
                        margin: EdgeInsets.only(right: _thumbSpacing),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isSelected ? Colors.red : Colors.white30,
                            width: isSelected ? 2.5 : 1,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: CachedNetworkImage(
                            imageUrl: _photos[i].url,
                            fit: BoxFit.cover,
                            memCacheWidth: _thumbSize.toInt(),
                            memCacheHeight: _thumbSize.toInt(),
                            fadeInDuration: const Duration(milliseconds: 150),
                            placeholder: (_, __) => Container(
                              color: Colors.white10,
                              child: const Center(
                                child: CircularProgressIndicator(
                                  color: Colors.white54,
                                  strokeWidth: 1.5,
                                ),
                              ),
                            ),
                            errorWidget: (_, __, ___) => Container(
                              color: Colors.white10,
                              child: const Icon(
                                Icons.image_not_supported_outlined,
                                color: Colors.white38,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Grid gallery view page for Admin Chat ───────────────────────────────────

class _AdminGalleryGridPage extends StatefulWidget {
  final List<_AdminSharedPhoto> photos;
  final String userName;
  final int userId;
  final ValueChanged<String> onDeleteMessage;

  const _AdminGalleryGridPage({
    required this.photos,
    required this.userName,
    required this.userId,
    required this.onDeleteMessage,
  });

  @override
  State<_AdminGalleryGridPage> createState() => _AdminGalleryGridPageState();
}

class _AdminGalleryGridPageState extends State<_AdminGalleryGridPage> {
  void _openFullScreenViewer(int index) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _AdminPhotoViewerPage(
          photos: widget.photos,
          initialIndex: index,
          userName: widget.userName,
          userId: widget.userId,
          onDeleteMessage: widget.onDeleteMessage,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = ChatColors.of(context);

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.header,
        elevation: 1,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: c.text),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.userName,
              style: TextStyle(
                color: c.text,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              '${widget.photos.length} photos',
              style: TextStyle(color: c.muted, fontSize: 12),
            ),
          ],
        ),
      ),
      body: widget.photos.isEmpty
          ? Center(
              child: Text('No photos', style: TextStyle(color: c.muted)),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(4),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
              ),
              itemCount: widget.photos.length,
              itemBuilder: (ctx, i) {
                return GestureDetector(
                  onTap: () => _openFullScreenViewer(i),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: CachedNetworkImage(
                        imageUrl: widget.photos[i].url,
                        fit: BoxFit.cover,
                        memCacheWidth: 200,
                        memCacheHeight: 200,
                        fadeInDuration: const Duration(milliseconds: 150),
                        placeholder: (_, __) => Container(
                          color: Colors.grey.shade200,
                          child: const Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                        errorWidget: (_, __, ___) => Container(
                          color: Colors.grey.shade200,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.image_not_supported_outlined,
                                color: Colors.grey.shade500,
                                size: 32,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'File not found',
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Forward image user-picker dialog
// ---------------------------------------------------------------------------
class _ForwardUserPickerDialog extends StatefulWidget {
  const _ForwardUserPickerDialog({required this.users});

  final List<Map<String, String>> users;

  @override
  State<_ForwardUserPickerDialog> createState() =>
      _ForwardUserPickerDialogState();
}

class _ForwardUserPickerDialogState extends State<_ForwardUserPickerDialog> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    const kPrimary = Color(0xFF7B61FF);
    final filtered = _search.isEmpty
        ? widget.users
        : widget.users
              .where(
                (u) => (u['namee'] ?? '').toLowerCase().contains(
                  _search.toLowerCase(),
                ),
              )
              .toList();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: SizedBox(
        width: 340,
        height: 480,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  const Icon(Icons.forward_rounded, color: kPrimary, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Forward Photo To',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                  ),
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: const Icon(
                      Icons.close,
                      size: 18,
                      color: Color(0xFF94A3B8),
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: TextField(
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Search users…',
                  hintStyle: const TextStyle(fontSize: 13),
                  prefixIcon: const Icon(Icons.search, size: 18),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                ),
                onChanged: (v) => setState(() => _search = v),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(
                      child: Text(
                        'No users found',
                        style: TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 13,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (ctx, i) {
                        final user = filtered[i];
                        final name = user['namee'] ?? 'User';
                        final avatar = user['profile_picture'] ?? '';
                        return ListTile(
                          dense: true,
                          leading: CircleAvatar(
                            radius: 18,
                            backgroundColor: const Color(0xFFF1F5F9),
                            backgroundImage: avatar.isNotEmpty
                                ? NetworkImage(avatar)
                                : null,
                            child: avatar.isEmpty
                                ? Text(
                                    name.isNotEmpty
                                        ? name[0].toUpperCase()
                                        : '?',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Color(0xFF64748B),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  )
                                : null,
                          ),
                          title: Text(
                            name,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          onTap: () => Navigator.pop(ctx, user),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A compact action tile used in the "Take Action" bottom sheet of report cards.
class _ActionTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: color.withOpacity(0.12),
        child: Icon(icon, color: color, size: 18),
      ),
      title: Text(
        label,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
      onTap: onTap,
    );
  }
}

// ── Add Participant Dialog ────────────────────────────────────────────────────
/// Searchable, photo-enabled dialog to pick a user for a conference call.
/// Returns `{'id': userId, 'name': userName}` on selection.
class _AddParticipantDialog extends StatefulWidget {
  final List<Map<String, dynamic>> allUsers;
  const _AddParticipantDialog({required this.allUsers});

  @override
  State<_AddParticipantDialog> createState() => _AddParticipantDialogState();
}

class _AddParticipantDialogState extends State<_AddParticipantDialog> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Returns the first name for display (privacy: only first name shown in calls).
  String _displayName(Map<String, dynamic> u) {
    // Prefer pre-computed _firstName added by _fetchAllUsersSortedOnlineFirst.
    final fn = (u['_firstName'] ?? u['firstName'] ?? '').toString().trim();
    if (fn.isNotEmpty) return fn;
    // Fallback: take first word of full name or name field.
    final full = (u['_fullName'] ?? u['name'] ?? '').toString().trim();
    return full.split(' ').first.isNotEmpty ? full.split(' ').first : 'User';
  }

  bool _isUserOnline(Map<String, dynamic> u) =>
      u['_isOnline'] == true ||
      u['isOnline'] == 1 ||
      u['isOnline'] == '1' ||
      u['isOnline'] == true;

  List<Map<String, dynamic>> get _filtered {
    if (_query.isEmpty) return widget.allUsers;
    final q = _query.toLowerCase();
    return widget.allUsers
        .where((u) => _displayName(u).toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 8, 16),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.group_add, color: Colors.white, size: 26),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Add to Call',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Online users first',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // ── Search bar ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _searchCtrl,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Search by name…',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 16,
                  ),
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _query = '');
                          },
                        )
                      : null,
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),

            // ── User list ───────────────────────────────────────────────────
            Flexible(
              child: filtered.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.search_off,
                            size: 52,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _query.isEmpty
                                ? 'No users available'
                                : 'No users match "$_query"',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, indent: 72),
                      itemBuilder: (ctx, idx) {
                        final user = filtered[idx];
                        final userId = user['id']?.toString() ?? '';
                        // Show only first name in the participant list (privacy).
                        final displayName = _displayName(user);
                        final photoUrl = user['profile_picture']?.toString();
                        final isOnline = _isUserOnline(user);
                        final initial = displayName.isNotEmpty
                            ? displayName[0].toUpperCase()
                            : '?';

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          leading: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              CircleAvatar(
                                radius: 24,
                                backgroundColor: const Color(
                                  0xFF6366F1,
                                ).withOpacity(0.15),
                                backgroundImage:
                                    (photoUrl != null && photoUrl.isNotEmpty)
                                    ? NetworkImage(photoUrl)
                                    : null,
                                child: (photoUrl == null || photoUrl.isEmpty)
                                    ? Text(
                                        initial,
                                        style: const TextStyle(
                                          color: Color(0xFF6366F1),
                                          fontWeight: FontWeight.w700,
                                          fontSize: 16,
                                        ),
                                      )
                                    : null,
                              ),
                              if (isOnline)
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: Container(
                                    width: 11,
                                    height: 11,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF22C55E),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          title: Text(
                            displayName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          subtitle: Text(
                            isOnline ? 'Online' : 'Offline',
                            style: TextStyle(
                              color: isOnline
                                  ? const Color(0xFF22C55E)
                                  : Colors.grey.shade400,
                              fontSize: 12,
                            ),
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF6366F1).withOpacity(0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'Add',
                              style: TextStyle(
                                color: Color(0xFF6366F1),
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          onTap: () => Navigator.pop(ctx, {
                            'id': userId,
                            'name': displayName,
                          }),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Group Call Participant Picker
//  Multi-select dialog: allows admin to select multiple users to invite to a
//  group call.  Online users appear at the top.  Shows first name only.
// ─────────────────────────────────────────────────────────────────────────────
class _GroupCallParticipantPicker extends StatefulWidget {
  final List<Map<String, dynamic>> allUsers;
  const _GroupCallParticipantPicker({required this.allUsers});

  @override
  State<_GroupCallParticipantPicker> createState() =>
      _GroupCallParticipantPickerState();
}

class _GroupCallParticipantPickerState
    extends State<_GroupCallParticipantPicker> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';
  final Set<String> _selectedIds = {};

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String _displayName(Map<String, dynamic> u) {
    final fn = (u['_firstName'] ?? u['firstName'] ?? '').toString().trim();
    if (fn.isNotEmpty) return fn;
    final full = (u['_fullName'] ?? u['name'] ?? '').toString().trim();
    final parts = full.split(' ');
    return parts.first.isNotEmpty ? parts.first : 'User';
  }

  bool _isOnline(Map<String, dynamic> u) =>
      u['_isOnline'] == true ||
      u['isOnline'] == 1 ||
      u['isOnline'] == '1' ||
      u['isOnline'] == true;

  /// Returns a human-readable last-seen label (e.g. "Last seen 5 min ago").
  String _lastSeenLabel(Map<String, dynamic> u) {
    final lastSeen = u['_lastSeen'] as DateTime?;
    if (lastSeen == null) return '';
    final now = DateTime.now().toUtc();
    final diff = now.difference(lastSeen.toUtc());
    if (diff.inSeconds < 60) return 'Last seen just now';
    if (diff.inMinutes < 60) return 'Last seen ${diff.inMinutes} min ago';
    if (diff.inHours < 24) return 'Last seen ${diff.inHours} hr ago';
    return 'Last seen ${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
  }

  List<Map<String, dynamic>> get _filtered {
    final base = _query.isEmpty
        ? List<Map<String, dynamic>>.from(widget.allUsers)
        : widget.allUsers
              .where(
                (u) =>
                    _displayName(
                      u,
                    ).toLowerCase().contains(_query.toLowerCase()) ||
                    (u['id']?.toString() ?? '').contains(_query),
              )
              .toList();
    base.sort((a, b) {
      final aOnline = _isOnline(a) ? 0 : 1;
      final bOnline = _isOnline(b) ? 0 : 1;
      if (aOnline != bOnline) return aOnline - bOnline;
      return _displayName(a).compareTo(_displayName(b));
    });
    return base;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final hasSelection = _selectedIds.isNotEmpty;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ────────────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 8, 16),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF7B61FF), Color(0xFF6366F1)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.groups, color: Colors.white, size: 26),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Start Group Call',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Select participants (online users first)',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // ── Search bar ────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: TextField(
                controller: _searchCtrl,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Search by name…',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 16,
                  ),
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _query = '');
                          },
                        )
                      : null,
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),

            // ── Selection count chip ─────────────────────────────────────────
            if (_selectedIds.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF7B61FF).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: const Color(0xFF7B61FF).withOpacity(0.3),
                        ),
                      ),
                      child: Text(
                        '${_selectedIds.length} selected',
                        style: const TextStyle(
                          color: Color(0xFF7B61FF),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => setState(() => _selectedIds.clear()),
                      child: const Text(
                        'Clear',
                        style: TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),

            // ── User list ─────────────────────────────────────────────────────
            Flexible(
              child: filtered.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.search_off,
                            size: 52,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _query.isEmpty
                                ? 'No users available'
                                : 'No users match "$_query"',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, indent: 72),
                      itemBuilder: (ctx, idx) {
                        final user = filtered[idx];
                        final userId = user['id']?.toString() ?? '';
                        final name = _displayName(user);
                        final photoUrl = user['profile_picture']?.toString();
                        final isOnline = _isOnline(user);
                        final lastSeenLabel = isOnline
                            ? ''
                            : _lastSeenLabel(user);
                        final isSelected = _selectedIds.contains(userId);
                        final initial = name.isNotEmpty
                            ? name[0].toUpperCase()
                            : '?';

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 2,
                          ),
                          leading: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              CircleAvatar(
                                radius: 22,
                                backgroundColor: const Color(
                                  0xFF7B61FF,
                                ).withOpacity(0.15),
                                backgroundImage:
                                    (photoUrl != null && photoUrl.isNotEmpty)
                                    ? NetworkImage(photoUrl)
                                    : null,
                                child: (photoUrl == null || photoUrl.isEmpty)
                                    ? Text(
                                        initial,
                                        style: const TextStyle(
                                          color: Color(0xFF7B61FF),
                                          fontWeight: FontWeight.w700,
                                          fontSize: 15,
                                        ),
                                      )
                                    : null,
                              ),
                              if (isOnline)
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF22C55E),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          title: Text(
                            // Show first name only (privacy requirement).
                            name,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: isSelected
                                  ? const Color(0xFF7B61FF)
                                  : null,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                isOnline ? 'Online' : 'Offline',
                                style: TextStyle(
                                  color: isOnline
                                      ? const Color(0xFF22C55E)
                                      : Colors.grey.shade400,
                                  fontSize: 12,
                                ),
                              ),
                              if (!isOnline && lastSeenLabel.isNotEmpty)
                                Text(
                                  lastSeenLabel,
                                  style: TextStyle(
                                    color: Colors.grey.shade500,
                                    fontSize: 11,
                                  ),
                                ),
                            ],
                          ),
                          trailing: isSelected
                              ? const Icon(
                                  Icons.check_circle,
                                  color: Color(0xFF7B61FF),
                                  size: 22,
                                )
                              : Icon(
                                  Icons.circle_outlined,
                                  color: Colors.grey.shade400,
                                  size: 22,
                                ),
                          onTap: () {
                            setState(() {
                              if (isSelected) {
                                _selectedIds.remove(userId);
                              } else {
                                _selectedIds.add(userId);
                              }
                            });
                          },
                        );
                      },
                    ),
            ),

            // ── Action footer ─────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: hasSelection
                      ? () {
                          final selected = widget.allUsers
                              .where(
                                (u) => _selectedIds.contains(
                                  u['id']?.toString() ?? '',
                                ),
                              )
                              .map(
                                (u) => {
                                  'id': u['id']?.toString() ?? '',
                                  'name': _displayName(u),
                                },
                              )
                              .toList();
                          Navigator.pop(context, selected);
                        }
                      : null,
                  icon: const Icon(Icons.call),
                  label: Text(
                    hasSelection
                        ? 'Start Call with ${_selectedIds.length} participant${_selectedIds.length == 1 ? '' : 's'}'
                        : 'Select at least one participant',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7B61FF),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    disabledBackgroundColor: Colors.grey.shade200,
                    disabledForegroundColor: Colors.grey.shade500,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
