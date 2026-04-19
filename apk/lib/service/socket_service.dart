import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../Calling/callmanager.dart';
import 'package:ms2026/config/app_endpoints.dart';

/// URL of the Node.js Socket.IO server.
/// ⚠️  IMPORTANT: Replace this with your actual deployed server URL before
/// building for production. Example: 'https://socket.yourserver.com:3001'
const String kSocketServerUrl = kSocketServerBaseUrl;

/// ---------------------------------------------------------------------------
/// SocketService — singleton that manages the Socket.IO connection and
/// exposes streams for all real-time chat events.
/// ---------------------------------------------------------------------------
class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  IO.Socket? _socket;
  String? _connectedUserId;

  /// Default timeout for Socket.IO request-response (ack) calls.
  static const Duration kRequestTimeout = Duration(seconds: 15);

  // ── Stream controllers ────────────────────────────────────────────────────

  final _newMessageCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _messageEditedCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _messageDeletedCtrl =
      StreamController<Map<String, dynamic>>.broadcast();
  final _messageLikedCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _messageReactionCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _typingStartCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _typingStopCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _messagesReadCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _userStatusCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _chatRoomsUpdateCtrl = StreamController<List<dynamic>>.broadcast();
  final _connectionCtrl = StreamController<bool>.broadcast();

  // ── Call signaling streams ────────────────────────────────────────────────

  final _incomingCallCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _callAcceptedCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _callRejectedCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _callCancelledCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _callEndedCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _callRingingCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _callUserOfflineCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _callBusyCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _callBlockedCtrl = StreamController<Map<String, dynamic>>.broadcast();

  // ── Audio-to-video switch streams ─────────────────────────────────────────

  final _switchToVideoRequestCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _switchToVideoResponseCtrl = StreamController<Map<String, dynamic>>.broadcast();

  // ── Conference call streams ───────────────────────────────────────────────

  final _addedToCallCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _participantAddedToCallCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _participantAcceptedCallCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _participantRejectedCallCtrl = StreamController<Map<String, dynamic>>.broadcast();

  // ── Public streams ────────────────────────────────────────────────────────

  Stream<Map<String, dynamic>> get onNewMessage => _newMessageCtrl.stream;
  Stream<Map<String, dynamic>> get onMessageEdited => _messageEditedCtrl.stream;
  Stream<Map<String, dynamic>> get onMessageDeleted =>
      _messageDeletedCtrl.stream;
  Stream<Map<String, dynamic>> get onMessageLiked => _messageLikedCtrl.stream;
  Stream<Map<String, dynamic>> get onMessageReaction => _messageReactionCtrl.stream;
  Stream<Map<String, dynamic>> get onTypingStart => _typingStartCtrl.stream;
  Stream<Map<String, dynamic>> get onTypingStop => _typingStopCtrl.stream;
  Stream<Map<String, dynamic>> get onMessagesRead => _messagesReadCtrl.stream;
  Stream<Map<String, dynamic>> get onUserStatusChange => _userStatusCtrl.stream;
  Stream<List<dynamic>> get onChatRoomsUpdate => _chatRoomsUpdateCtrl.stream;
  Stream<bool> get onConnectionChange => _connectionCtrl.stream;

  // Call signaling streams
  Stream<Map<String, dynamic>> get onIncomingCall => _incomingCallCtrl.stream;
  Stream<Map<String, dynamic>> get onCallAccepted => _callAcceptedCtrl.stream;
  Stream<Map<String, dynamic>> get onCallRejected => _callRejectedCtrl.stream;
  Stream<Map<String, dynamic>> get onCallCancelled => _callCancelledCtrl.stream;
  Stream<Map<String, dynamic>> get onCallEnded => _callEndedCtrl.stream;

  /// Emitted when the recipient's device starts ringing (Calling → Ringing).
  Stream<Map<String, dynamic>> get onCallRinging => _callRingingCtrl.stream;

  /// Emitted when the recipient is offline at the time of the call_invite.
  Stream<Map<String, dynamic>> get onCallUserOffline => _callUserOfflineCtrl.stream;

  /// Emitted when the recipient is already in another active call.
  Stream<Map<String, dynamic>> get onCallBusy => _callBusyCtrl.stream;

  /// Emitted when the call is rejected because either party has blocked the other.
  Stream<Map<String, dynamic>> get onCallBlocked => _callBlockedCtrl.stream;

  // Audio-to-video switch streams
  /// Emitted when the other party requests to upgrade the call to video.
  Stream<Map<String, dynamic>> get onSwitchToVideoRequest => _switchToVideoRequestCtrl.stream;

  /// Emitted when the other party responds to a switch-to-video request.
  Stream<Map<String, dynamic>> get onSwitchToVideoResponse => _switchToVideoResponseCtrl.stream;

  // Conference call streams
  Stream<Map<String, dynamic>> get onAddedToCall => _addedToCallCtrl.stream;
  Stream<Map<String, dynamic>> get onParticipantAddedToCall => _participantAddedToCallCtrl.stream;
  Stream<Map<String, dynamic>> get onParticipantAcceptedCall => _participantAcceptedCallCtrl.stream;
  Stream<Map<String, dynamic>> get onParticipantRejectedCall => _participantRejectedCallCtrl.stream;

  bool get isConnected => _socket?.connected == true;

  // ── Connect / Disconnect ──────────────────────────────────────────────────

  void connect(String userId) {
    if (_socket != null) {
      // If already connected with the same user, nothing to do.
      if (_socket!.connected && _connectedUserId == userId) return;
      // Always disconnect the old socket (even if it is currently reconnecting)
      // to avoid having two simultaneous connections that would duplicate events.
      _socket!.disconnect();
      _socket = null;
    }

    _connectedUserId = userId;

    _socket = IO.io(
      kSocketServerUrl,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .enableAutoConnect()
          .enableReconnection()
          .setReconnectionAttempts(20)
          .setReconnectionDelay(2000)
          .build(),
    );

    _socket!.onConnect((_) {
      print('✅ Socket connected');
      _connectionCtrl.add(true);
      // Authenticate immediately after connect / reconnect
      _socket!.emit('authenticate', {'userId': userId});
    });

    _socket!.onDisconnect((_) {
      print('⚡ Socket disconnected');
      _connectionCtrl.add(false);
    });

    _socket!.onConnectError((err) => print('❌ Socket connect error: $err'));

    // ── Register event listeners ────────────────────────────────────────────

    _socket!.on('new_message', (data) {
      _newMessageCtrl.add(_toMap(data));
    });

    _socket!.on('message_edited', (data) {
      _messageEditedCtrl.add(_toMap(data));
    });

    _socket!.on('message_deleted', (data) {
      _messageDeletedCtrl.add(_toMap(data));
    });

    _socket!.on('message_liked', (data) {
      _messageLikedCtrl.add(_toMap(data));
    });

    _socket!.on('message_reaction', (data) {
      _messageReactionCtrl.add(_toMap(data));
    });

    _socket!.on('typing_start', (data) {
      _typingStartCtrl.add(_toMap(data));
    });

    _socket!.on('typing_stop', (data) {
      _typingStopCtrl.add(_toMap(data));
    });

    _socket!.on('messages_read', (data) {
      _messagesReadCtrl.add(_toMap(data));
    });

    _socket!.on('user_status_change', (data) {
      _userStatusCtrl.add(_toMap(data));
    });

    _socket!.on('chat_rooms_update', (data) {
      final map = _toMap(data);
      final rooms = map['chatRooms'];
      if (rooms is List) _chatRoomsUpdateCtrl.add(rooms);
    });

    // ── Call signaling events ────────────────────────────────────────────────
    _socket!.on('incoming_call', (data) {
      final map = _toMap(data);
      _incomingCallCtrl.add(map);
      // Bridge to CallManager so CallOverlayWrapper can show the call screen
      // for users who are online (socket path, not FCM path).
      CallManager().triggerIncomingCall(map);
    });

    _socket!.on('call_accepted', (data) {
      _callAcceptedCtrl.add(_toMap(data));
    });

    _socket!.on('call_rejected', (data) {
      _callRejectedCtrl.add(_toMap(data));
    });

    _socket!.on('call_cancelled', (data) {
      _callCancelledCtrl.add(_toMap(data));
    });

    _socket!.on('call_ended', (data) {
      _callEndedCtrl.add(_toMap(data));
    });

    _socket!.on('call_ringing', (data) {
      _callRingingCtrl.add(_toMap(data));
    });

    _socket!.on('call_user_offline', (data) {
      _callUserOfflineCtrl.add(_toMap(data));
    });

    _socket!.on('call_busy', (data) {
      _callBusyCtrl.add(_toMap(data));
    });

    _socket!.on('call_blocked', (data) {
      _callBlockedCtrl.add(_toMap(data));
    });

    // ── Audio-to-video switch events ─────────────────────────────────────────
    _socket!.on('switch_to_video_request', (data) {
      _switchToVideoRequestCtrl.add(_toMap(data));
    });

    _socket!.on('switch_to_video_response', (data) {
      _switchToVideoResponseCtrl.add(_toMap(data));
    });

    // ── Conference call events ────────────────────────────────────────────────
    _socket!.on('added_to_call', (data) {
      final map = _toMap(data);
      _addedToCallCtrl.add(map);

      // Normalize admin fields to caller fields for incoming call screen compatibility
      final bool isVideo = map['callType']?.toString() == 'video';
      final normalizedMap = {
        ...map,
        'callerId': map['adminId'] ?? '',
        'callerName': map['adminName'] ?? 'Admin',
        'callerImage': map['adminImage'] ?? '',
        // Allow _blockIfFreeUser() to bypass the paid-plan check for admin calls
        'callerRole': 'admin',
        // Set type fields so call_overlay_manager correctly opens the video call
        // screen when the admin invites this user to a video conference call
        if (isVideo) 'type': 'video_call',
        if (isVideo) 'isVideoCall': 'true',
        // Keep the original adminId/adminName for conference call handling
        'isConferenceCall': true,
      };

      // Bridge to CallManager so CallOverlayWrapper can show the call screen
      // when admin adds this user to a conference call.
      CallManager().triggerIncomingCall(normalizedMap);
    });

    _socket!.on('participant_added_to_call', (data) {
      _participantAddedToCallCtrl.add(_toMap(data));
    });

    _socket!.on('participant_accepted_call', (data) {
      _participantAcceptedCallCtrl.add(_toMap(data));
    });

    _socket!.on('participant_rejected_call', (data) {
      _participantRejectedCallCtrl.add(_toMap(data));
    });

    _socket!.on('error', (data) {
      print('🔴 Socket error event: $data');
    });

    _socket!.connect();
  }

  void disconnect() {
    _socket?.disconnect();
    _socket = null;
    _connectedUserId = null;
  }

  // ── Emit helpers ──────────────────────────────────────────────────────────

  /// Join a chat room socket channel.
  void joinRoom(String chatRoomId) {
    _socket?.emit('join_room', {'chatRoomId': chatRoomId});
  }

  /// Leave a chat room socket channel.
  void leaveRoom(String chatRoomId) {
    _socket?.emit('leave_room', {'chatRoomId': chatRoomId});
  }

  /// Tell the server which chat room is currently active (for read-receipt logic).
  void setActiveChat(String userId, String chatRoomId, {bool isActive = true}) {
    _socket?.emit('set_active_chat', {
      'userId': userId,
      'chatRoomId': chatRoomId,
      'isActive': isActive,
    });
  }

  /// Send a text or media message.
  void sendMessage({
    required String chatRoomId,
    required String senderId,
    required String receiverId,
    required String message,
    required String messageType,
    required String messageId,
    Map<String, dynamic>? repliedTo,
    bool isReceiverViewing = false,
    String user1Name = '',
    String user2Name = '',
    String user1Image = '',
    String user2Image = '',
  }) {
    _socket?.emit('send_message', {
      'chatRoomId': chatRoomId,
      'senderId': senderId,
      'receiverId': receiverId,
      'message': message,
      'messageType': messageType,
      'messageId': messageId,
      'repliedTo': repliedTo,
      'isReceiverViewing': isReceiverViewing,
      'user1Name': user1Name,
      'user2Name': user2Name,
      'user1Image': user1Image,
      'user2Image': user2Image,
    });
  }

  void startTyping(String chatRoomId, String userId) {
    _socket?.emit('typing_start', {'chatRoomId': chatRoomId, 'userId': userId});
  }

  void stopTyping(String chatRoomId, String userId) {
    _socket?.emit('typing_stop', {'chatRoomId': chatRoomId, 'userId': userId});
  }

  void markRead(String chatRoomId, String userId) {
    _socket?.emit('mark_read', {'chatRoomId': chatRoomId, 'userId': userId});
  }

  void toggleLike(String chatRoomId, String messageId) {
    _socket?.emit(
        'toggle_like', {'chatRoomId': chatRoomId, 'messageId': messageId});
  }

  void addReaction(String chatRoomId, String messageId, String emoji) {
    _socket?.emit('add_reaction', {
      'chatRoomId': chatRoomId,
      'messageId': messageId,
      'emoji': emoji,
    });
  }

  void editMessage(String chatRoomId, String messageId, String newMessage) {
    _socket?.emit('edit_message', {
      'chatRoomId': chatRoomId,
      'messageId': messageId,
      'newMessage': newMessage,
    });
  }

  void deleteMessage({
    required String chatRoomId,
    required String messageId,
    required String userId,
    required bool deleteForEveryone,
  }) {
    _socket?.emit('delete_message', {
      'chatRoomId': chatRoomId,
      'messageId': messageId,
      'userId': userId,
      'deleteForEveryone': deleteForEveryone,
    });
  }

  // ── Call signaling emit methods ───────────────────────────────────────────

  /// Notify the recipient of an incoming call (real-time, for online users).
  /// Also send a FCM push via [NotificationService] as fallback for offline users.
  void emitCallInvite({
    required String recipientId,
    required String callerId,
    required String callerName,
    required String callerImage,
    required String channelName,
    required String callerUid,
    String callType = 'audio',
    String? chatRoomId,
  }) {
    _socket?.emit('call_invite', {
      'recipientId': recipientId,
      'callerId': callerId,
      'callerName': callerName,
      'callerImage': callerImage,
      'channelName': channelName,
      'callerUid': callerUid,
      'callType': callType,
      if (chatRoomId != null) 'chatRoomId': chatRoomId,
      'type': callType == 'video' ? 'video_call' : 'call',
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Notify the caller that the call was accepted.
  void emitCallAccept({
    required String callerId,
    required String recipientId,
    required String recipientName,
    required String recipientUid,
    required String channelName,
    String callType = 'audio',
  }) {
    _socket?.emit('call_accept', {
      'callerId': callerId,
      'recipientId': recipientId,
      'recipientName': recipientName,
      'recipientUid': recipientUid,
      'channelName': channelName,
      'callType': callType,
      'accepted': 'true',
      'type': callType == 'video' ? 'video_call_response' : 'call_response',
    });
  }

  /// Notify the caller that the call was rejected.
  void emitCallReject({
    required String callerId,
    required String recipientId,
    required String recipientName,
    required String channelName,
    String callType = 'audio',
  }) {
    _socket?.emit('call_reject', {
      'callerId': callerId,
      'recipientId': recipientId,
      'recipientName': recipientName,
      'channelName': channelName,
      'callType': callType,
      'accepted': 'false',
      'type': callType == 'video' ? 'video_call_response' : 'call_response',
    });
  }

  /// Notify the recipient that the caller cancelled before they answered.
  void emitCallCancel({
    required String recipientId,
    required String callerId,
    required String callerName,
    required String channelName,
    String callType = 'audio',
  }) {
    _socket?.emit('call_cancel', {
      'recipientId': recipientId,
      'callerId': callerId,
      'callerName': callerName,
      'channelName': channelName,
      'callType': callType,
      'type': callType == 'video' ? 'video_call_cancelled' : 'call_cancelled',
    });
  }

  /// Notify the caller that the recipient's device is actively ringing.
  /// Called by the recipient when IncomingCallScreen becomes visible.
  void emitCallRinging({
    required String callerId,
    required String recipientId,
    required String channelName,
    String callType = 'audio',
  }) {
    _socket?.emit('call_ringing', {
      'callerId': callerId,
      'recipientId': recipientId,
      'channelName': channelName,
      'callType': callType,
    });
  }

  /// Notify both parties that the call has ended.
  void emitCallEnd({
    required String callerId,
    required String recipientId,
    required String channelName,
    String callType = 'audio',
    int duration = 0,
  }) {
    _socket?.emit('call_end', {
      'callerId': callerId,
      'recipientId': recipientId,
      'channelName': channelName,
      'callType': callType,
      'duration': duration,
      'type': callType == 'video' ? 'video_call_ended' : 'call_ended',
    });
  }

  // ── Conference call emit methods ──────────────────────────────────────────

  /// Request to upgrade the current audio call to a video call.
  void emitSwitchToVideoRequest({
    required String recipientId,
    required String requesterId,
    required String channelName,
  }) {
    _socket?.emit('switch_to_video_request', {
      'recipientId': recipientId,
      'requesterId': requesterId,
      'channelName': channelName,
    });
  }

  /// Respond to a switch-to-video request (accept or decline).
  void emitSwitchToVideoResponse({
    required String requesterId,
    required String responderId,
    required String channelName,
    required bool accepted,
  }) {
    _socket?.emit('switch_to_video_response', {
      'requesterId': requesterId,
      'responderId': responderId,
      'channelName': channelName,
      'accepted': accepted,
    });
  }

  /// User accepts a conference call invitation (when added by admin).
  void emitParticipantCallAccept({
    required String adminId,
    required String channelName,
    required String acceptedById,
    String? existingParticipantId,
  }) {
    _socket?.emit('participant_call_accept', {
      'adminId': adminId,
      'channelName': channelName,
      'acceptedById': acceptedById,
      if (existingParticipantId != null) 'existingParticipantId': existingParticipantId,
    });
  }

  /// User rejects a conference call invitation (when added by admin).
  void emitParticipantCallReject({
    required String adminId,
    required String channelName,
    required String rejectedById,
    String? existingParticipantId,
  }) {
    _socket?.emit('participant_call_reject', {
      'adminId': adminId,
      'channelName': channelName,
      'rejectedById': rejectedById,
      if (existingParticipantId != null) 'existingParticipantId': existingParticipantId,
    });
  }

  // ── Request-response helpers ──────────────────────────────────────────────

  /// Fetch a page of messages (request-response via Socket.IO ack).
  Future<Map<String, dynamic>> getMessages(String chatRoomId,
      {int page = 1, int limit = 20}) {
    final completer = Completer<Map<String, dynamic>>();
    _socket?.emitWithAck(
      'get_messages',
      {'chatRoomId': chatRoomId, 'page': page, 'limit': limit},
      ack: (response) {
        final map = _toMap(response);
        if (!completer.isCompleted) completer.complete(map);
      },
    );
    // Timeout fallback
    Future.delayed(kRequestTimeout, () {
      if (!completer.isCompleted) {
        completer.completeError(TimeoutException('get_messages timed out'));
      }
    });
    return completer.future;
  }

  /// Fetch the current online status of a specific user (request-response via Socket.IO ack).
  Future<Map<String, dynamic>> getUserStatus(String userId) {
    final completer = Completer<Map<String, dynamic>>();
    if (_socket == null || !_socket!.connected) {
      completer
          .complete({'userId': userId, 'isOnline': false, 'lastSeen': null});
      return completer.future;
    }
    _socket!.emitWithAck(
      'get_user_status',
      {'userId': userId},
      ack: (response) {
        final map = _toMap(response);
        if (!completer.isCompleted) completer.complete(map);
      },
    );
    Future.delayed(kRequestTimeout, () {
      if (!completer.isCompleted) {
        completer
            .complete({'userId': userId, 'isOnline': false, 'lastSeen': null});
      }
    });
    return completer.future;
  }

  /// Fetch the user's chat room list (request-response via Socket.IO ack).
  Future<List<dynamic>> getChatRooms(String userId) async {
    final completer = Completer<List<dynamic>>();
    _socket?.emitWithAck(
      'get_chat_rooms',
      {'userId': userId},
      ack: (response) {
        final map = _toMap(response);
        final rooms = map['chatRooms'];
        if (!completer.isCompleted) {
          completer.complete(rooms is List ? rooms : []);
        }
      },
    );
    Future.delayed(kRequestTimeout, () {
      if (!completer.isCompleted) completer.complete([]);
    });
    return completer.future;
  }

  // ── Media upload ──────────────────────────────────────────────────────────

  /// Upload a chat image via PHP REST API and return the public URL.
  /// [bytes] is the raw file data (use XFile.readAsBytes() to get it).
  /// [filename] is used to set a sensible filename in the multipart request.
  Future<String> uploadChatImage({
    required Uint8List bytes,
    required String filename,
    required String userId,
    required String chatRoomId,
  }) async {
    return _uploadBytes(
      bytes: bytes,
      filename: filename,
      userId: userId,
      type: 'image',
      mimeType: MediaType('image', 'jpeg'),
    );
  }

  /// Upload a voice message via PHP REST API and return the public URL.
  Future<String> uploadVoiceMessage({
    required Uint8List bytes,
    required String filename,
    required String userId,
    required String chatRoomId,
  }) async {
    return _uploadBytes(
      bytes: bytes,
      filename: filename,
      userId: userId,
      type: 'voice',
      mimeType: MediaType('audio', 'mpeg'),
    );
  }

  Future<String> _uploadBytes({
    required Uint8List bytes,
    required String filename,
    required String userId,
    required String type,
    required MediaType mimeType,
  }) async {
    // Validate type against allowlist to prevent URL injection
    final safeType = (type == 'voice') ? 'voice' : 'image';
    final uri = Uri.parse(kSocketServerUrl).replace(
      path: '/upload',
      queryParameters: {'type': safeType},
    );
    final request = http.MultipartRequest('POST', uri)
      ..files.add(http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: filename,
        contentType: mimeType,
      ));

    final streamed = await request.send();
    final body = await streamed.stream.bytesToString();

    if (streamed.statusCode != 200) {
      throw Exception('Upload failed: ${streamed.statusCode} $body');
    }

    final json = jsonDecode(body) as Map<String, dynamic>;
    final url = json['url']?.toString();
    if (url == null || url.isEmpty) {
      throw Exception(json['error']?.toString() ?? 'Upload returned no URL');
    }
    return url;
  }

  // ── Utility ───────────────────────────────────────────────────────────────

  /// Normalize data coming from socket events to Map<String, dynamic>.
  static Map<String, dynamic> _toMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is String) {
      try {
        return jsonDecode(data) as Map<String, dynamic>;
      } catch (_) {}
    }
    return {};
  }

  /// Parse a timestamp value (String ISO8601 or DateTime) to a local DateTime.
  /// UTC timestamps from the server are converted to the device's local timezone.
  static DateTime? parseTimestamp(dynamic ts) {
    if (ts == null) return null;
    if (ts is DateTime) return ts.isUtc ? ts.toLocal() : ts;
    if (ts is String) {
      final dt = DateTime.tryParse(ts);
      return dt?.toLocal();
    }
    return null;
  }

  void dispose() {
    disconnect();
    _newMessageCtrl.close();
    _messageEditedCtrl.close();
    _messageDeletedCtrl.close();
    _messageLikedCtrl.close();
    _messageReactionCtrl.close();
    _typingStartCtrl.close();
    _typingStopCtrl.close();
    _messagesReadCtrl.close();
    _userStatusCtrl.close();
    _chatRoomsUpdateCtrl.close();
    _connectionCtrl.close();
    _incomingCallCtrl.close();
    _callAcceptedCtrl.close();
    _callRejectedCtrl.close();
    _callCancelledCtrl.close();
    _callEndedCtrl.close();
    _callRingingCtrl.close();
    _callUserOfflineCtrl.close();
    _callBusyCtrl.close();
    _callBlockedCtrl.close();
    _switchToVideoRequestCtrl.close();
    _switchToVideoResponseCtrl.close();
    _addedToCallCtrl.close();
    _participantAddedToCallCtrl.close();
    _participantAcceptedCallCtrl.close();
    _participantRejectedCallCtrl.close();
  }
}
