import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'call_history_model.dart';
import '../service/socket_service.dart';
import 'package:uuid/uuid.dart';

/// Base URL of the Node.js Socket.IO server (same as SocketService).
/// Kept in sync with [kSocketServerUrl] in socket_service.dart.
const String _kCallApiBase = kSocketServerUrl;

class CallHistoryService {
  // Log a new call – writes to MySQL via REST
  static Future<String> logCall({
    required String callerId,
    required String callerName,
    required String callerImage,
    required String recipientId,
    required String recipientName,
    required String recipientImage,
    required CallType callType,
    required String initiatedBy,
  }) async {
    try {
      final callId = const Uuid().v4();
      final response = await http.post(
        Uri.parse('$_kCallApiBase/api/calls'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'callId': callId,
          'callerId': callerId,
          'callerName': callerName,
          'callerImage': callerImage,
          'recipientId': recipientId,
          'recipientName': recipientName,
          'recipientImage': recipientImage,
          'callType': callType.toString().split('.').last,
          'initiatedBy': initiatedBy,
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        if (body['success'] == true) return callId;
      }
      print('⚠️ logCall failed: ${response.statusCode} ${response.body}');
      return callId; // Return generated ID even on server error so we can still update later
    } catch (e) {
      print('Error logging call: $e');
      return '';
    }
  }

  // Update call when it ends
  static Future<void> updateCallEnd({
    required String callId,
    required CallStatus status,
    int duration = 0,
  }) async {
    if (callId.isEmpty) return;
    try {
      await http.put(
        Uri.parse('$_kCallApiBase/api/calls/$callId'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'status': status.toString().split('.').last,
          'duration': duration,
        }),
      ).timeout(const Duration(seconds: 15));
    } catch (e) {
      print('Error updating call end: $e');
    }
  }

  // Get call history as a one-shot Stream (emits once with current data).
  // Used in ChatDetailsScreen to listen for updates via a StreamSubscription.
  static Stream<List<CallHistory>> getCallHistory(String userId, {int limit = 100}) {
    return Stream.fromFuture(getCallHistoryFuture(userId, limit: limit));
  }

  // Get call history with named parameters for use in admin chat (returns a Future).
  static Future<List<CallHistory>> getCallHistoryPaginated({
    required String userId,
    int limit = 50,
  }) {
    return getCallHistoryFuture(userId, limit: limit);
  }

  // Get call history for a specific user (returns a Future for use with FutureBuilder)
  static Future<List<CallHistory>> getCallHistoryFuture(String userId, {int limit = 100}) async {
    try {
      final response = await http.get(
        Uri.parse('$_kCallApiBase/api/calls?userId=$userId&limit=$limit'),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final calls = (body['calls'] as List? ?? [])
            .map((c) => CallHistory.fromMap(c as Map<String, dynamic>))
            .toList();
        return calls;
      }
      return [];
    } catch (e) {
      print('Error getting call history: $e');
      return [];
    }
  }

  // Delete a specific call from history
  static Future<void> deleteCall(String callId) async {
    try {
      await http.delete(
        Uri.parse('$_kCallApiBase/api/calls/$callId'),
      ).timeout(const Duration(seconds: 15));
    } catch (e) {
      print('Error deleting call: $e');
    }
  }

  // Clear all call history for a user
  static Future<void> clearCallHistory(String userId) async {
    try {
      await http.delete(
        Uri.parse('$_kCallApiBase/api/calls/user/$userId'),
      ).timeout(const Duration(seconds: 15));
    } catch (e) {
      print('Error clearing call history: $e');
    }
  }

  // Write an inline call event message into the chat message stream (WhatsApp-style).
  // Uses Socket.IO for both regular and admin chat rooms so the message appears
  // in ChatDetailScreen and AdminChatScreen which both read from the Socket.IO server.
  static Future<void> logCallMessageInChat({
    required String callerId,
    required String callType, // 'audio' or 'video'
    required String callStatus, // 'completed', 'missed', 'declined', 'cancelled'
    required int duration,
    String? chatRoomId,
    bool isAdminChat = false,
    String? adminChatSenderId,
    String? adminChatReceiverId,
    String? messageDocId,
  }) async {
    try {
      final payload = jsonEncode({
        'callType': callType,
        'callStatus': callStatus,
        'duration': duration,
        'callerId': callerId,
      });

      if (isAdminChat) {
        final senderId = adminChatSenderId ?? callerId;
        final receiverId = adminChatReceiverId ?? '';
        if (receiverId.isNotEmpty) {
          final List<String> ids = [senderId, receiverId]..sort();
          final adminChatRoomId = ids.join('_');
          SocketService().sendMessage(
            chatRoomId: adminChatRoomId,
            senderId: senderId,
            receiverId: receiverId,
            message: payload,
            messageType: 'call',
            messageId: messageDocId ?? const Uuid().v4(),
            user1Name: '',
            user2Name: '',
            user1Image: '',
            user2Image: '',
          );
        }
      } else if (chatRoomId != null && chatRoomId.isNotEmpty) {
        // Extract sender and receiver from the chatRoomId (format: "smallerId_largerId")
        final parts = chatRoomId.split('_');
        String senderId = callerId;
        String receiverId = '';
        if (parts.length >= 2) {
          // The receiver is the participant that is not the caller
          receiverId = parts[0] == callerId ? parts[1] : parts[0];
        }

        if (receiverId.isNotEmpty) {
          SocketService().sendMessage(
            chatRoomId: chatRoomId,
            senderId: senderId,
            receiverId: receiverId,
            message: payload,
            messageType: 'call',
            messageId: messageDocId ?? const Uuid().v4(),
            user1Name: '',
            user2Name: '',
            user1Image: '',
            user2Image: '',
          );
        }
      }
    } catch (e) {
      print('Error logging call message in chat (chatRoomId: $chatRoomId, isAdminChat: $isAdminChat): $e');
    }
  }

  // Get current user ID from SharedPreferences
  static Future<String> getCurrentUserId() async {
    final prefs = await SharedPreferences.getInstance();
    final userDataString = prefs.getString('user_data');
    if (userDataString != null) {
      try {
        final userData = jsonDecode(userDataString) as Map<String, dynamic>;
        return userData['id']?.toString() ?? '';
      } catch (_) {}
    }
    return '';
  }
}
