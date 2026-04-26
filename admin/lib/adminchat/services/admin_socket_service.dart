import 'dart:async';
import 'dart:convert';

import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'callmanager.dart';
import 'package:adminmrz/config/app_endpoints.dart';

/// URL of the Node.js Socket.IO server.
/// ⚠️  Replace this with your actual deployed server URL before building.
/// Example: 'https://socket.yourserver.com:3001'
const String kAdminSocketUrl = kAdminSocketBaseUrl;

/// Admin user ID — always '1'.
const String kAdminUserId = '1';
const int kAdminSocketReconnectAttempts = 20;

/// Default timeout for acknowledgement-based Socket.IO calls.
const Duration kAdminSocketTimeout = Duration(seconds: 15);

/// ---------------------------------------------------------------------------
/// AdminSocketService — singleton that manages the Socket.IO connection for
/// the admin panel (connects as userId = '1') and exposes streams for all
/// real-time chat events.
/// ---------------------------------------------------------------------------
class AdminSocketService {
  static final AdminSocketService _instance = AdminSocketService._internal();
  factory AdminSocketService() => _instance;
  AdminSocketService._internal();

  IO.Socket? _socket;

  // ── Stream controllers ────────────────────────────────────────────────────

  final _newMessageCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _messageEditedCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _messageDeletedCtrl =
      StreamController<Map<String, dynamic>>.broadcast();
  final _messageUnsentCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _messageLikedCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _messageReactionCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _messagesReadCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _typingStartCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _typingStopCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _userStatusCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _chatRoomsUpdateCtrl = StreamController<List<dynamic>>.broadcast();
  final _incomingCallCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _callAcceptedCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _callRejectedCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _callCancelledCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _callAnsweredElsewhereCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _callEndedCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _callBusyCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _addedToCallCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _participantAddedToCallCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _participantAcceptedCallCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _participantRejectedCallCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _connectionCtrl = StreamController<bool>.broadcast();
  final _userActivityCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _adminActivityCtrl = StreamController<Map<String, dynamic>>.broadcast();
  // Receives the server-side send_message event emitted to admin_room so the
  // message monitor screen can display every message in real-time.
  final _sendMessageMonitorCtrl = StreamController<Map<String, dynamic>>.broadcast();
  // Emitted by the server when a user's payment/subscription status changes.
  // Payload: { userId, usertype, is_paid, timestamp }
  final _paymentUpdatedCtrl = StreamController<Map<String, dynamic>>.broadcast();
  // Emitted by the server after mark_read to reset the unread count for a room
  // without requiring a full chat_rooms_update reload.
  // Payload: { chatRoomId, userId, unreadCount }
  final _unreadResetCtrl = StreamController<Map<String, dynamic>>.broadcast();

  // ── Public streams ────────────────────────────────────────────────────────

  Stream<Map<String, dynamic>> get onNewMessage => _newMessageCtrl.stream;
  Stream<Map<String, dynamic>> get onMessageEdited => _messageEditedCtrl.stream;
  Stream<Map<String, dynamic>> get onMessageDeleted =>
      _messageDeletedCtrl.stream;
  Stream<Map<String, dynamic>> get onMessageUnsent => _messageUnsentCtrl.stream;
  Stream<Map<String, dynamic>> get onMessageLiked => _messageLikedCtrl.stream;
  Stream<Map<String, dynamic>> get onMessageReaction => _messageReactionCtrl.stream;
  Stream<Map<String, dynamic>> get onMessagesRead => _messagesReadCtrl.stream;
  Stream<Map<String, dynamic>> get onTypingStart => _typingStartCtrl.stream;
  Stream<Map<String, dynamic>> get onTypingStop => _typingStopCtrl.stream;
  Stream<Map<String, dynamic>> get onUserStatusChange => _userStatusCtrl.stream;
  Stream<List<dynamic>> get onChatRoomsUpdate => _chatRoomsUpdateCtrl.stream;
  Stream<Map<String, dynamic>> get onIncomingCall => _incomingCallCtrl.stream;
  Stream<Map<String, dynamic>> get onCallAccepted => _callAcceptedCtrl.stream;
  Stream<Map<String, dynamic>> get onCallRejected => _callRejectedCtrl.stream;
  Stream<Map<String, dynamic>> get onCallCancelled => _callCancelledCtrl.stream;
  Stream<Map<String, dynamic>> get onCallAnsweredElsewhere => _callAnsweredElsewhereCtrl.stream;
  Stream<Map<String, dynamic>> get onCallEnded => _callEndedCtrl.stream;
  Stream<Map<String, dynamic>> get onCallBusy => _callBusyCtrl.stream;
  Stream<Map<String, dynamic>> get onAddedToCall => _addedToCallCtrl.stream;
  Stream<Map<String, dynamic>> get onParticipantAddedToCall => _participantAddedToCallCtrl.stream;
  Stream<Map<String, dynamic>> get onParticipantAcceptedCall => _participantAcceptedCallCtrl.stream;
  Stream<Map<String, dynamic>> get onParticipantRejectedCall => _participantRejectedCallCtrl.stream;
  Stream<bool> get onConnectionChange => _connectionCtrl.stream;
  /// Emitted by the server whenever a user activity is logged. Admin panel
  /// uses this for real-time activity feed updates.
  Stream<Map<String, dynamic>> get onUserActivity => _userActivityCtrl.stream;
  /// Emitted by the server immediately when a user sends a text message.
  /// Payload: { sender_id, receiver_id, sender_name, receiver_name, message, timestamp }
  Stream<Map<String, dynamic>> get onAdminActivity => _adminActivityCtrl.stream;
  /// Emitted by the server for every sent message (all types) — used by the
  /// admin message monitor screen to show live messages with sender/receiver info.
  /// Payload: { messageId, chatRoomId, senderId, receiverId, senderName,
  ///            receiverName, message, messageType, timestamp }
  Stream<Map<String, dynamic>> get onMessageMonitor => _sendMessageMonitorCtrl.stream;
  /// Emitted by the server when a user's payment/subscription status changes.
  /// Payload: { userId, usertype, is_paid, timestamp }
  Stream<Map<String, dynamic>> get onPaymentUpdated => _paymentUpdatedCtrl.stream;
  /// Emitted by the server after mark_read — resets the unread count for a
  /// specific chat room without requiring a full chat_rooms_update reload.
  /// Payload: { chatRoomId, userId, unreadCount }
  Stream<Map<String, dynamic>> get onUnreadReset => _unreadResetCtrl.stream;

  // ── State ─────────────────────────────────────────────────────────────────

  bool get isConnected => _socket?.connected ?? false;

  // ── Connect / Disconnect ──────────────────────────────────────────────────

  void connect() {
    if (_socket != null && _socket!.connected) return;

    _socket?.dispose();
    _socket = IO.io(
      kAdminSocketUrl,
      IO.OptionBuilder()
          .setTransports(['websocket', 'polling'])
          .setReconnectionDelay(2000)
          .setReconnectionDelayMax(10000)
          .setReconnectionAttempts(kAdminSocketReconnectAttempts)
          .enableReconnection()
          .disableAutoConnect()
          .build(),
    );

    _socket!.onConnect((_) {
      _connectionCtrl.add(true);
      // Authenticate as admin
      _socket!.emit('authenticate', {'userId': kAdminUserId});
      // Join the admin_activity room to receive real-time activity events
      _socket!.emit('admin_join');
    });

    _socket!.onDisconnect((_) {
      _connectionCtrl.add(false);
    });

    _socket!.onConnectError((err) {
      _connectionCtrl.add(false);
      print('❌ Admin socket connect error: $err');
    });

    _socket!.on('new_message', (data) {
      if (data is Map) _newMessageCtrl.add(Map<String, dynamic>.from(data));
    });

    _socket!.on('message_edited', (data) {
      if (data is Map) _messageEditedCtrl.add(Map<String, dynamic>.from(data));
    });

    _socket!.on('message_deleted', (data) {
      if (data is Map) _messageDeletedCtrl.add(Map<String, dynamic>.from(data));
    });

    _socket!.on('message_unsent', (data) {
      if (data is Map) _messageUnsentCtrl.add(Map<String, dynamic>.from(data));
    });

    _socket!.on('message_liked', (data) {
      if (data is Map) _messageLikedCtrl.add(Map<String, dynamic>.from(data));
    });

    _socket!.on('message_reaction', (data) {
      if (data is Map) _messageReactionCtrl.add(Map<String, dynamic>.from(data));
    });

    _socket!.on('messages_read', (data) {
      if (data is Map) _messagesReadCtrl.add(Map<String, dynamic>.from(data));
    });

    _socket!.on('typing_start', (data) {
      if (data is Map) _typingStartCtrl.add(Map<String, dynamic>.from(data));
    });

    _socket!.on('typing_stop', (data) {
      if (data is Map) _typingStopCtrl.add(Map<String, dynamic>.from(data));
    });

    _socket!.on('user_status_change', (data) {
      if (data is Map) _userStatusCtrl.add(Map<String, dynamic>.from(data));
    });

    _socket!.on('chat_rooms_update', (data) {
      final map = _toMap(data);
      final rooms = map['chatRooms'];
      if (rooms is List) _chatRoomsUpdateCtrl.add(rooms);
    });

    _socket!.on('incoming_call', (data) {
      final map = _toMap(data);
      _incomingCallCtrl.add(map);
      // Bridge to CallManager so the incoming call UI can be shown.
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

    _socket!.on('call_answered_elsewhere', (data) {
      _callAnsweredElsewhereCtrl.add(_toMap(data));
    });

    _socket!.on('call_ended', (data) {
      _callEndedCtrl.add(_toMap(data));
    });

    _socket!.on('call_busy', (data) {
      _callBusyCtrl.add(_toMap(data));
    });

    _socket!.on('added_to_call', (data) {
      _addedToCallCtrl.add(_toMap(data));
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

    _socket!.on('user_activity', (data) {
      if (data is Map) _userActivityCtrl.add(Map<String, dynamic>.from(data));
    });

    _socket!.on('admin_activity', (data) {
      if (data is Map) _adminActivityCtrl.add(Map<String, dynamic>.from(data));
    });

    // Server emits 'send_message' to admin_room for every sent message so the
    // admin monitor sees it in real-time regardless of which chat room it is in.
    _socket!.on('send_message', (data) {
      if (data is Map) _sendMessageMonitorCtrl.add(Map<String, dynamic>.from(data));
    });

    // Server emits 'payment_updated' to admin_room when a user's payment status changes.
    _socket!.on('payment_updated', (data) {
      if (data is Map) _paymentUpdatedCtrl.add(Map<String, dynamic>.from(data));
    });

    // Lightweight unread reset emitted after mark_read — lets the sidebar
    // update the badge without a full chat_rooms_update reload.
    _socket!.on('unread_reset', (data) {
      if (data is Map) _unreadResetCtrl.add(Map<String, dynamic>.from(data));
    });

    _socket!.connect();
  }

  void disconnect() {
    _socket?.disconnect();
  }

  void dispose() {
    disconnect();
    _socket?.dispose();
    _socket = null;
    _newMessageCtrl.close();
    _messageEditedCtrl.close();
    _messageDeletedCtrl.close();
    _messageUnsentCtrl.close();
    _messageLikedCtrl.close();
    _messageReactionCtrl.close();
    _messagesReadCtrl.close();
    _typingStartCtrl.close();
    _typingStopCtrl.close();
    _userStatusCtrl.close();
    _chatRoomsUpdateCtrl.close();
    _incomingCallCtrl.close();
    _callAcceptedCtrl.close();
    _callRejectedCtrl.close();
    _callCancelledCtrl.close();
    _callAnsweredElsewhereCtrl.close();
    _callEndedCtrl.close();
    _callBusyCtrl.close();
    _addedToCallCtrl.close();
    _participantAddedToCallCtrl.close();
    _participantAcceptedCallCtrl.close();
    _participantRejectedCallCtrl.close();
    _connectionCtrl.close();
    _userActivityCtrl.close();
    _adminActivityCtrl.close();
    _sendMessageMonitorCtrl.close();
    _paymentUpdatedCtrl.close();
    _unreadResetCtrl.close();
  }

  Future<bool> ensureConnected() async {
    if (isConnected) return true;
    connect();

    final completer = Completer<bool>();
    late StreamSubscription<bool> sub;
    final timer = Timer(kAdminSocketTimeout, () {
      if (!completer.isCompleted) completer.complete(false);
    });

    sub = onConnectionChange.listen((connected) {
      if (connected && !completer.isCompleted) {
        completer.complete(true);
      }
    });

    final result = await completer.future;
    await sub.cancel();
    timer.cancel();
    return result;
  }

  // ── Room management ───────────────────────────────────────────────────────

  void joinRoom(String chatRoomId) {
    _socket?.emit('join_room', {'chatRoomId': chatRoomId});
  }

  void leaveRoom(String chatRoomId) {
    _socket?.emit('leave_room', {'chatRoomId': chatRoomId});
  }

  void setActiveChat(String chatRoomId, {bool isActive = true}) {
    _socket?.emit('set_active_chat', {
      'userId': kAdminUserId,
      'chatRoomId': isActive ? chatRoomId : null,
      'isActive': isActive,
    });
  }

  // ── Messaging ─────────────────────────────────────────────────────────────

  /// Send a message from admin to [receiverId].
  void sendMessage({
    required String chatRoomId,
    required String receiverId,
    required String message,
    required String messageType,
    required String messageId,
    Map<String, dynamic>? repliedTo,
    String? receiverName,
    String? receiverImage,
  }) {
    _socket?.emit('send_message', {
      'chatRoomId': chatRoomId,
      'senderId': kAdminUserId,
      'receiverId': receiverId,
      'message': message,
      'messageType': messageType,
      'messageId': messageId,
      if (repliedTo != null) 'repliedTo': repliedTo,
      'user1Name': 'Admin',
      'user2Name': receiverName ?? '',
      'user1Image': '',
      'user2Image': receiverImage ?? '',
    });
  }

  void editMessage({
    required String chatRoomId,
    required String messageId,
    required String newMessage,
  }) {
    _socket?.emit('edit_message', {
      'chatRoomId': chatRoomId,
      'messageId': messageId,
      'newMessage': newMessage,
    });
  }

  void deleteMessage({required String chatRoomId, required String messageId}) {
    _socket?.emit('delete_message', {
      'chatRoomId': chatRoomId,
      'messageId': messageId,
      'userId': kAdminUserId,
      'deleteForEveryone': true,
    });
  }

  void unsendMessage({required String chatRoomId, required String messageId}) {
    _socket?.emit('unsend_message', {
      'chatRoomId': chatRoomId,
      'messageId': messageId,
      'userId': kAdminUserId,
    });
  }

  void toggleLike({required String chatRoomId, required String messageId}) {
    _socket?.emit('toggle_like', {
      'chatRoomId': chatRoomId,
      'messageId': messageId,
    });
  }

  void addReaction({required String chatRoomId, required String messageId, required String emoji}) {
    _socket?.emit('add_reaction', {
      'chatRoomId': chatRoomId,
      'messageId': messageId,
      'emoji': emoji,
    });
  }

  void markRead(String chatRoomId) {
    _socket?.emit('mark_read', {
      'chatRoomId': chatRoomId,
      'userId': kAdminUserId,
    });
  }

  void sendTypingStart(String chatRoomId) {
    _socket?.emit('typing_start', {
      'chatRoomId': chatRoomId,
      'userId': kAdminUserId,
    });
  }

  void sendTypingStop(String chatRoomId) {
    _socket?.emit('typing_stop', {
      'chatRoomId': chatRoomId,
      'userId': kAdminUserId,
    });
  }

  // ── Request/Response (with ack) ───────────────────────────────────────────

  /// Load a page of messages for [chatRoomId].
  Future<Map<String, dynamic>> getMessages(
    String chatRoomId, {
    int page = 1,
    int limit = 30,
  }) {
    final completer = Completer<Map<String, dynamic>>();
    // Fail fast when socket is not available so callers receive an immediate
    // error instead of hanging until kAdminSocketTimeout fires.
    if (_socket == null || !_socket!.connected) {
      Future.microtask(() {
        if (!completer.isCompleted) {
          completer.completeError(Exception('Socket not connected'));
        }
      });
      return completer.future;
    }
    final timer = Timer(kAdminSocketTimeout, () {
      if (!completer.isCompleted) {
        completer.completeError(
          TimeoutException('getMessages timed out', kAdminSocketTimeout),
        );
      }
    });

    _socket!.emitWithAck(
      'get_messages',
      {'chatRoomId': chatRoomId, 'page': page, 'limit': limit},
      ack: (data) {
        timer.cancel();
        if (!completer.isCompleted) {
          completer.complete(Map<String, dynamic>.from(data as Map? ?? {}));
        }
      },
    );

    return completer.future;
  }

  /// Cursor-based load-more for [chatRoomId].
  /// Fetches up to [limit] messages older than [beforeTimestamp].
  /// Returns the same structure as [getMessages], plus a [nextCursor] field.
  Future<Map<String, dynamic>> getMessagesWithCursor(
    String chatRoomId, {
    required String beforeTimestamp,
    int limit = 20,
  }) {
    final completer = Completer<Map<String, dynamic>>();
    final timer = Timer(kAdminSocketTimeout, () {
      if (!completer.isCompleted) {
        completer.completeError(
          TimeoutException('getMessagesWithCursor timed out', kAdminSocketTimeout),
        );
      }
    });

    _socket?.emitWithAck(
      'get_messages',
      {
        'chatRoomId':       chatRoomId,
        'beforeTimestamp':  beforeTimestamp,
        'limit':            limit,
      },
      ack: (data) {
        timer.cancel();
        if (!completer.isCompleted) {
          completer.complete(Map<String, dynamic>.from(data as Map? ?? {}));
        }
      },
    );

    return completer.future;
  }

  Future<List<dynamic>> getChatRooms() async {
    // Return empty list immediately when socket is not connected.
    if (_socket == null || !_socket!.connected) return const [];
    final completer = Completer<List<dynamic>>();
    final timer = Timer(kAdminSocketTimeout, () {
      if (!completer.isCompleted) {
        completer.completeError(
          TimeoutException('getChatRooms timed out', kAdminSocketTimeout),
        );
      }
    });

    _socket!.emitWithAck(
      'get_chat_rooms',
      {'userId': kAdminUserId},
      ack: (data) {
        timer.cancel();
        final map = _toMap(data);
        final rooms = map['chatRooms'];
        if (!completer.isCompleted) {
          completer.complete(rooms is List ? rooms : const []);
        }
      },
    );

    return completer.future;
  }

  Future<Map<String, dynamic>> getUserStatus(String userId) async {
    final completer = Completer<Map<String, dynamic>>();
    final timer = Timer(kAdminSocketTimeout, () {
      if (!completer.isCompleted) {
        completer.complete({
          'userId': userId,
          'isOnline': false,
          'lastSeen': null,
        });
      }
    });

    _socket?.emitWithAck(
      'get_user_status',
      {'userId': userId},
      ack: (data) {
        timer.cancel();
        if (!completer.isCompleted) {
          completer.complete(_toMap(data));
        }
      },
    );

    return completer.future;
  }

  void emitCallInvite({
    required String recipientId,
    required String callerId,
    required String callerName,
    required String callerImage,
    required String channelName,
    required String callerUid,
    required String callType,
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
      'callerRole': 'admin',
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  void emitCallCancel({
    required String recipientId,
    required String callerId,
    required String callerName,
    required String channelName,
    required String callType,
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

  void emitCallAccept({
    required String callerId,
    required String recipientId,
    required String recipientName,
    required String recipientUid,
    required String channelName,
    required String callType,
  }) {
    _socket?.emit('call_accept', {
      'callerId': callerId,
      'recipientId': recipientId,
      'recipientName': recipientName,
      'recipientUid': recipientUid,
      'channelName': channelName,
      'callType': callType,
      'type': callType == 'video' ? 'video_call_accepted' : 'call_accepted',
    });
  }

  void emitCallReject({
    required String callerId,
    required String recipientId,
    required String recipientName,
    required String channelName,
    required String callType,
  }) {
    _socket?.emit('call_reject', {
      'callerId': callerId,
      'recipientId': recipientId,
      'recipientName': recipientName,
      'channelName': channelName,
      'callType': callType,
      'type': callType == 'video' ? 'video_call_rejected' : 'call_rejected',
    });
  }

  void emitCallEnd({
    required String callerId,
    required String recipientId,
    required String channelName,
    required String callType,
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

  /// Admin emits this to add a new participant to an ongoing call (conference call)
  void emitAddParticipantToCall({
    required String newParticipantId,
    required String channelName,
    required String callType,
    required String adminId,
    required String adminName,
    String? existingParticipantId,
    String? newParticipantName,
    String? agoraAppId,
    String? callerUid,
  }) {
    _socket?.emit('add_participant_to_call', {
      'newParticipantId': newParticipantId,
      'channelName': channelName,
      'callType': callType,
      'adminId': adminId,
      'adminName': adminName,
      if (existingParticipantId != null) 'existingParticipantId': existingParticipantId,
      if (newParticipantName != null) 'newParticipantName': newParticipantName,
      if (agoraAppId != null) 'agoraAppId': agoraAppId,
      if (callerUid != null) 'callerUid': callerUid,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// New participant accepts the conference call invitation
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

  /// New participant rejects the conference call invitation
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

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Compute the chat room ID shared between admin and [userId].
  static String chatRoomId(String userId) {
    final ids = [kAdminUserId, userId]..sort();
    return ids.join('_');
  }

  /// Parse a nullable timestamp string to [DateTime].
  static DateTime? parseTimestamp(dynamic ts) {
    if (ts == null) return null;
    if (ts is DateTime) return ts.isUtc ? ts.toLocal() : ts;
    if (ts is String) {
      final dt = DateTime.tryParse(ts);
      return dt?.toLocal();
    }
    return null;
  }

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
}
