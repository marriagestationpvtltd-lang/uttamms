// lib/services/profile_service.dart

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../Notification/notification_inbox_service.dart';
import '../pushnotification/pushservice.dart';
import '../otherenew/modelfile.dart';
import 'package:ms2026/config/app_endpoints.dart';

class ProfileService {
  static const String baseUrl = '${kApiBaseUrl}/Api2';

  /// Fetch profile data from API
  Future<ProfileResponse> fetchProfile({
    required dynamic myId,
    required dynamic userId
  }) async {
    // Ensure both are converted to strings explicitly
    final String myIdStr = myId.toString();
    final String userIdStr = userId.toString();

    final url = Uri.parse('$baseUrl/other_profile_new.php?myid=$myIdStr&userid=$userIdStr');

    try {
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final jsonResponse = json.decode(response.body);

        if (jsonResponse['status'] == 'success') {
          return ProfileResponse.fromJson(jsonResponse);
        } else {
          throw Exception('API returned error status: ${jsonResponse['status']}');
        }
      } else {
        throw Exception('Failed to load profile. Status code: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching profile: $e');
    }
  }


  // In ProfileService class
  Future<Map<String, dynamic>> blockUser({
    required String myId,
    required String userId,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/block_user.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'my_id': myId,
          'user_id': userId,
        }),
      );

      return jsonDecode(response.body);
    } catch (e) {
      return {'status': 'error', 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> unblockUser({
    required String myId,
    required String userId,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/unblock_user.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'my_id': myId,
          'user_id': userId,
        }),
      );

      return jsonDecode(response.body);
    } catch (e) {
      return {'status': 'error', 'message': e.toString()};
    }
  }

  Future<bool> isUserBlocked({
    required String myId,
    required String userId,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/check_block_status.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'my_id': myId,
          'user_id': userId,
        }),
      );

      final data = jsonDecode(response.body);
      return data['is_blocked'] ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Returns a map with keys:
  ///   `is_blocked`    – current user has blocked the other
  ///   `is_blocked_by` – the other user has blocked the current user
  ///   `either_blocked`– either party has blocked the other
  Future<Map<String, bool>> getBlockStatus({
    required String myId,
    required String userId,
  }) async {
    const _empty = {
      'is_blocked': false,
      'is_blocked_by': false,
      'either_blocked': false,
    };
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/check_block_status.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'my_id': myId,
          'user_id': userId,
        }),
      );

      final data = jsonDecode(response.body);
      return {
        'is_blocked':    data['is_blocked']    == true,
        'is_blocked_by': data['is_blocked_by'] == true,
        'either_blocked': data['either_blocked'] == true,
      };
    } catch (e) {
      return _empty;
    }
  }

  Future<List<Map<String, dynamic>>> getBlockedUsers({
    required String myId,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/get_blocked_users.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'my_id': myId,
        }),
      );

      final data = jsonDecode(response.body);
      if (data['status'] == 'success') {
        return List<Map<String, dynamic>>.from(data['users'] ?? []);
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  /// Fetch matched profiles
  Future<List<MatchedProfile>> fetchMatchedProfiles({
    required dynamic userId,
  }) async {
    // Ensure userId is converted to string explicitly
    final String userIdStr = userId.toString();
    final url = Uri.parse('$baseUrl/match.php?userid=$userIdStr');

    try {
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final jsonResponse = json.decode(response.body);

        if (jsonResponse['success'] == true) {
          final List<dynamic> matchedUsersJson = jsonResponse['matched_users'] ?? [];
          final matchedProfiles = matchedUsersJson
              .map((json) => MatchedProfile.fromJson(json))
              .toList();
          matchedProfiles.sort((a, b) {
            final matchCompare = b.matchPercent.compareTo(a.matchPercent);
            if (matchCompare != 0) return matchCompare;
            return b.userid.compareTo(a.userid);
          });
          return matchedProfiles;
        } else {
          return [];
        }
      } else {
        return [];
      }
    } catch (e) {
      return [];
    }
  }

  /// Send photo request
  Future<Map<String, dynamic>> sendPhotoRequest({
    required String myId,
    required String userId,
  }) async {
    try {
      final url = Uri.parse('$baseUrl/send_request.php');

      final response = await http.post(
        url,
        body: {
          'myid': myId,
          'userid': userId,
          'request_type': 'Photo'
        },
      );

      if (response.statusCode == 200) {
        final result = Map<String, dynamic>.from(json.decode(response.body));
        if (result['status'] == 'success') {
          try {
            final senderName = await NotificationInboxService.getCurrentUserDisplayName();
            await NotificationService.sendRequestNotification(
              recipientUserId: userId,
              senderName: senderName,
              senderId: myId,
              requestType: 'Photo',
            );
            await NotificationInboxService.recordOutgoingRequest(
              recipientUserId: userId,
              requestType: 'Photo',
              recipientName: 'MS:$userId',
            );
          } catch (notifError, stackTrace) {
            debugPrint('⚠️ Photo request sent but notification failed: $notifError\n$stackTrace');
          }
        }
        return result;
      }

      return {
        'status': 'error',
        'message': 'Failed to send photo request',
      };
    } catch (e) {
      debugPrint('❌ Error sending photo request: $e');
      return {
        'status': 'error',
        'message': e.toString(),
      };
    }
  }

  /// Send chat request
  Future<Map<String, dynamic>> sendChatRequest({
    required String myId,
    required String userId,
  }) async {
    try {
      final url = Uri.parse('$baseUrl/send_request.php');

      final response = await http.post(
        url,
        body: {
          'myid': myId,
          'userid': userId,
          'request_type': "Chat"
        },
      );

      if (response.statusCode == 200) {
        final result = Map<String, dynamic>.from(json.decode(response.body));
        if (result['status'] == 'success') {
          try {
            final senderName = await NotificationInboxService.getCurrentUserDisplayName();
            await NotificationService.sendRequestNotification(
              recipientUserId: userId,
              senderName: senderName,
              senderId: myId,
              requestType: 'Chat',
            );
            await NotificationInboxService.recordOutgoingRequest(
              recipientUserId: userId,
              requestType: 'Chat',
              recipientName: 'MS:$userId',
            );
          } catch (notifError, stackTrace) {
            debugPrint('⚠️ Chat request sent but notification failed: $notifError\n$stackTrace');
          }
        }
        return result;
      }

      return {
        'status': 'error',
        'message': 'Failed to send chat request',
      };
    } catch (e) {
      debugPrint('❌ Error sending chat request: $e');
      return {
        'status': 'error',
        'message': e.toString(),
      };
    }
  }

  /// Send like/unlike
  Future<Map<String, dynamic>> sendLike({
    required String myId,
    required String userId,
    required bool like,
  }) async {
    try {
      final url = Uri.parse('$baseUrl/like.php');

      final response = await http.post(
        url,
        body: {
          'myid': myId,
          'userid': userId,
          'like': like ? '1' : '0',
        },
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        return {'status': 'error', 'message': 'Failed to send like'};
      }
    } catch (e) {
      return {'status': 'error', 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> acceptRequest({
    required String myId,
    required String senderId,
    required String type,
  }) async {
    final url = Uri.parse('$baseUrl/accept_request.php');

    final response = await http.post(url, body: {
      'myid': myId,
      'sender_id': senderId,
      'request_type': type,
    });

    final result = Map<String, dynamic>.from(json.decode(response.body));
    if (result['status'] == 'success') {
      final senderName = await NotificationInboxService.getCurrentUserDisplayName();
      await NotificationService.sendRequestAccepted(
        recipientUserId: senderId,
        senderName: senderName,
        senderId: myId,
        requestType: type,
      );
      await NotificationInboxService.markRequestResolved(
        peerUserId: senderId,
        requestType: type,
        status: 'accepted',
      );
    }

    return result;
  }

  Future<Map<String, dynamic>> rejectRequest({
    required String myId,
    required String senderId,
    required String type,
  }) async {
    final url = Uri.parse('$baseUrl/reject_request.php');

    final response = await http.post(url, body: {
      'myid': myId,
      'sender_id': senderId,
      'request_type': type,
    });

    final result = Map<String, dynamic>.from(json.decode(response.body));
    if (result['status'] == 'success') {
      final senderName = await NotificationInboxService.getCurrentUserDisplayName();
      await NotificationService.sendRequestRejected(
        recipientUserId: senderId,
        senderName: senderName,
        senderId: myId,
        requestType: type,
      );
      await NotificationInboxService.markRequestResolved(
        peerUserId: senderId,
        requestType: type,
        status: 'rejected',
      );
    }

    return result;
  }
}
