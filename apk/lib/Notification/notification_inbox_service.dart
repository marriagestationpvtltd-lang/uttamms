import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

class NotificationInboxService {
  static const String _storageKey = 'notification_inbox_records_v2';
  static const Duration reminderCooldown = Duration(hours: 6);
  static const int _maxRandomSuffix = 1048576;
  static final Random _random = Random();

  static Future<List<Map<String, dynamic>>> loadNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);

    if (raw == null || raw.isEmpty) {
      return [];
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return [];
      }

      final notifications = decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();

      notifications.sort((a, b) {
        final aDate = parseDate(a['created_at']);
        final bDate = parseDate(b['created_at']);
        if (aDate == null && bDate == null) return 0;
        if (aDate == null) return 1;
        if (bDate == null) return -1;
        return bDate.compareTo(aDate);
      });

      return notifications;
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveNotifications(List<Map<String, dynamic>> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(items));
  }

  static Future<void> upsertNotification(Map<String, dynamic> notification) async {
    final items = await loadNotifications();
    final id = notification['id']?.toString();
    final externalId = notification['external_id']?.toString();

    if (externalId != null && externalId.isNotEmpty) {
      final existingIndex = items.indexWhere(
        (item) => item['external_id']?.toString() == externalId,
      );
      if (existingIndex != -1) {
        items[existingIndex] = {
          ...items[existingIndex],
          ...notification,
        };
        await saveNotifications(items);
        return;
      }
    }

    if (id != null && id.isNotEmpty) {
      items.removeWhere((item) => item['id']?.toString() == id);
    }

    items.add(notification);
    await saveNotifications(items);
  }

  static Future<void> deleteNotification(String notificationId) async {
    final items = await loadNotifications();
    items.removeWhere((item) => item['id']?.toString() == notificationId);
    await saveNotifications(items);
  }

  static Future<void> markAsRead(String notificationId) async {
    final items = await loadNotifications();
    final index = items.indexWhere((item) => item['id']?.toString() == notificationId);
    if (index == -1) return;

    items[index] = {
      ...items[index],
      'is_read': 1,
    };
    await saveNotifications(items);
  }

  static Future<void> recordOutgoingRequest({
    required String recipientUserId,
    required String requestType,
    String? recipientName,
  }) async {
    final createdAt = DateTime.now();
    final cleanRequestType = normalizeRequestType(requestType);
    final peerName = _cleanName(recipientName, fallbackId: recipientUserId);
    final content = buildNotificationContent(
      type: 'request_sent',
      actorName: peerName,
      requestType: cleanRequestType,
    );

    await upsertNotification({
      'id': _localId('request_sent'),
      'type': 'request_sent',
      'request_type': cleanRequestType,
      'title': content['title'],
      'message': content['body'],
      'created_at': createdAt.toIso8601String(),
      'time': createdAt.toIso8601String(),
      'is_read': 0,
      'source': 'local',
      'request_status': 'pending',
      'recipient_id': recipientUserId,
      'related_user_id': recipientUserId,
      'peer_name': peerName,
      'external_id':
          'local_request_sent|${cleanRequestType.toLowerCase()}|$recipientUserId|${createdAt.millisecondsSinceEpoch}',
    });
  }

  static Future<void> recordReminderSent({
    required String notificationId,
  }) async {
    final items = await loadNotifications();
    final index = items.indexWhere((item) => item['id']?.toString() == notificationId);
    if (index == -1) return;

    final source = Map<String, dynamic>.from(items[index]);
    final reminderAt = DateTime.now();
    final peerName = _cleanName(
      source['peer_name']?.toString(),
      fallbackId: source['recipient_id']?.toString() ?? source['related_user_id']?.toString(),
    );
    final requestType = normalizeRequestType(source['request_type']?.toString());
    final content = buildNotificationContent(
      type: 'request_reminder_sent',
      actorName: peerName,
      requestType: requestType,
    );

    items[index] = {
      ...source,
      'last_reminder_sent_at': reminderAt.toIso8601String(),
      'is_read': 1,
    };

    items.add({
      'id': _localId('request_reminder_sent'),
      'type': 'request_reminder_sent',
      'request_type': requestType,
      'title': content['title'],
      'message': content['body'],
      'created_at': reminderAt.toIso8601String(),
      'time': reminderAt.toIso8601String(),
      'is_read': 0,
      'source': 'local',
      'recipient_id': source['recipient_id'],
      'related_user_id': source['related_user_id'],
      'peer_name': peerName,
      'external_id':
          'local_request_reminder|${requestType.toLowerCase()}|${source['recipient_id']}|${reminderAt.millisecondsSinceEpoch}',
    });

    await saveNotifications(items);
  }

  static Future<void> markRequestResolved({
    required String peerUserId,
    required String requestType,
    required String status,
  }) async {
    final items = await loadNotifications();
    final normalizedType = normalizeRequestType(requestType);

    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      if (item['type']?.toString() != 'request_sent') continue;
      if (normalizeRequestType(item['request_type']?.toString()) != normalizedType) continue;

      final recipientId = item['recipient_id']?.toString() ?? item['related_user_id']?.toString();
      if (recipientId != peerUserId) continue;

      items[i] = {
        ...item,
        'request_status': status.toLowerCase(),
      };
    }

    await saveNotifications(items);
  }

  static Future<void> recordIncomingRemoteNotification({
    required Map<String, dynamic> data,
    String? fallbackTitle,
    String? fallbackBody,
  }) async {
    final type = data['type']?.toString().trim();
    if (type == null || type.isEmpty) {
      return;
    }

    // Call-started and call-ended notifications are handled by the calling UI
    // and should not appear in the notification inbox.
    const _skipTypes = {'call', 'video_call', 'call_ended', 'video_call_ended'};
    if (_skipTypes.contains(type)) {
      return;
    }

    final requestType = normalizeRequestType(
      data['requestType']?.toString() ?? data['request_type']?.toString(),
    );
    final actorName = _cleanName(
      data['senderName']?.toString() ??
          data['callerName']?.toString() ??
          data['viewerName']?.toString() ??
          data['recipientName']?.toString(),
      fallbackId: data['senderId']?.toString() ??
          data['callerId']?.toString() ??
          data['viewerId']?.toString() ??
          data['recipientId']?.toString(),
    );

    final content = buildNotificationContent(
      type: type,
      actorName: actorName,
      requestType: requestType,
      messagePreview: data['message']?.toString(),
    );

    final createdAt = _parseRemoteTimestamp(data['timestamp']?.toString()) ?? DateTime.now();
    final relatedUserId = data['senderId']?.toString() ??
        data['callerId']?.toString() ??
        data['viewerId']?.toString() ??
        data['recipientId']?.toString();

    if ((type == 'request_accepted' || type == 'request_rejected') &&
        relatedUserId != null &&
        relatedUserId.isNotEmpty) {
      await markRequestResolved(
        peerUserId: relatedUserId,
        requestType: requestType,
        status: type == 'request_accepted' ? 'accepted' : 'rejected',
      );
    }

    await upsertNotification({
      'id': _localId(type),
      'type': type,
      'request_type': requestType,
      'title': (fallbackTitle != null && fallbackTitle.isNotEmpty)
          ? fallbackTitle
          : content['title'],
      'message': (fallbackBody != null && fallbackBody.isNotEmpty)
          ? fallbackBody
          : content['body'],
      'created_at': createdAt.toIso8601String(),
      'time': createdAt.toIso8601String(),
      'is_read': 0,
      'source': 'push',
      'sender_id': data['senderId']?.toString() ??
          data['callerId']?.toString() ??
          data['viewerId']?.toString(),
      'related_user_id': relatedUserId,
      'peer_name': actorName,
      'external_id': _remoteExternalId(
        type: type,
        requestType: requestType,
        actorId: relatedUserId,
        timestamp: createdAt.toIso8601String(),
        message: data['message']?.toString(),
      ),
    });
  }

  static bool isLocalNotificationId(dynamic value) {
    return value?.toString().startsWith('local_') ?? false;
  }

  static String get reminderCooldownLabel {
    final totalHours = reminderCooldown.inHours;
    if (totalHours > 0) {
      return '$totalHours hours';
    }

    final totalMinutes = reminderCooldown.inMinutes;
    return '$totalMinutes minutes';
  }

  static bool canSendReminder(Map<String, dynamic> notification) {
    if (notification['type']?.toString() != 'request_sent') {
      return false;
    }

    if ((notification['request_status']?.toString().toLowerCase() ?? 'pending') != 'pending') {
      return false;
    }

    final baseTime = parseDate(
      notification['last_reminder_sent_at']?.toString() ?? notification['created_at']?.toString(),
    );
    if (baseTime == null) {
      return false;
    }

    return DateTime.now().difference(baseTime) >= reminderCooldown;
  }

  static Duration? reminderRemaining(Map<String, dynamic> notification) {
    if (notification['type']?.toString() != 'request_sent') {
      return null;
    }

    if ((notification['request_status']?.toString().toLowerCase() ?? 'pending') != 'pending') {
      return null;
    }

    final baseTime = parseDate(
      notification['last_reminder_sent_at']?.toString() ?? notification['created_at']?.toString(),
    );
    if (baseTime == null) {
      return null;
    }

    final remaining = reminderCooldown - DateTime.now().difference(baseTime);
    if (remaining.isNegative) {
      return Duration.zero;
    }
    return remaining;
  }

  static String normalizeRequestType(String? value) {
    final normalized = (value ?? '').trim().toLowerCase();
    switch (normalized) {
      case 'photo':
      case 'photo_request':
        return 'Photo';
      case 'chat':
      case 'chat_request':
        return 'Chat';
      case 'profile':
      case 'profile_request':
        return 'Profile';
      case 'contact':
      case 'contact_request':
        return 'Contact';
      default:
        return normalized.isEmpty ? 'Request' : _toSentenceCase(normalized);
    }
  }

  static Map<String, String> buildNotificationContent({
    required String type,
    String? actorName,
    String? requestType,
    String? messagePreview,
  }) {
    final cleanType = type.trim().toLowerCase();
    final cleanActor = actorName?.trim().isNotEmpty == true ? actorName!.trim() : 'Someone';
    final cleanRequestType = normalizeRequestType(requestType);
    final requestLabel = cleanRequestType.toLowerCase();
    final requestPhrase =
        cleanRequestType == 'Request' ? 'request' : '$requestLabel request';

    switch (cleanType) {
      case 'request':
        return {
          'title': cleanRequestType == 'Request'
              ? 'New request received'
              : '$cleanRequestType request received',
          'body': '$cleanActor sent you a $requestPhrase. Please review and respond.',
        };
      case 'request_sent':
        return {
          'title': cleanRequestType == 'Request'
              ? 'Request sent'
              : '$cleanRequestType request sent',
          'body':
              'Your $requestPhrase was sent to $cleanActor. If there is no reply within $reminderCooldownLabel, you can send a reminder.',
        };
      case 'request_reminder':
        return {
          'title': cleanRequestType == 'Request'
              ? 'Reminder: request pending'
              : 'Reminder: $cleanRequestType request pending',
          'body': '$cleanActor is still waiting for your reply to the $requestPhrase.',
        };
      case 'request_reminder_sent':
        return {
          'title': cleanRequestType == 'Request'
              ? 'Request reminder sent'
              : '$cleanRequestType reminder sent',
          'body': 'We reminded $cleanActor about your pending $requestPhrase.',
        };
      case 'request_accepted':
        return {
          'title': cleanRequestType == 'Request'
              ? 'Request accepted'
              : '$cleanRequestType request accepted',
          'body': '$cleanActor accepted your $requestPhrase.',
        };
      case 'request_rejected':
        return {
          'title': cleanRequestType == 'Request'
              ? 'Request rejected'
              : '$cleanRequestType request rejected',
          'body': '$cleanActor rejected your $requestPhrase.',
        };
      case 'chat':
      case 'chat_message':
        return {
          'title': 'New chat message',
          'body': messagePreview?.trim().isNotEmpty == true
              ? '$cleanActor: ${messagePreview!.trim()}'
              : '$cleanActor sent you a new chat message.',
        };
      case 'profile_view':
        return {
          'title': 'Profile viewed',
          'body': '$cleanActor viewed your profile.',
        };
      case 'call':
      case 'video_call':
        return {
          'title': 'Incoming call',
          'body': '$cleanActor is calling you.',
        };
      case 'missed_call':
        return {
          'title': 'Missed call',
          'body': '$cleanActor tried to call you.',
        };
      case 'call_ended':
        return {
          'title': 'Call update',
          'body': messagePreview?.trim().isNotEmpty == true
              ? messagePreview!.trim()
              : 'Your call activity was updated.',
        };
      default:
        return {
          'title': _toSentenceCase(cleanType.replaceAll('_', ' ')),
          'body': messagePreview?.trim().isNotEmpty == true
              ? messagePreview!.trim()
              : '$cleanActor sent you a notification.',
        };
    }
  }

  static DateTime? parseDate(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is DateTime) {
      return value;
    }

    final text = value.toString().trim();
    if (text.isEmpty) {
      return null;
    }

    return DateTime.tryParse(text.replaceFirst(' ', 'T'));
  }

  static String dedupeKey(Map<String, dynamic> notification) {
    final createdAt = parseDate(notification['created_at']) ?? parseDate(notification['time']);
    final minuteBucket = createdAt == null
        ? ''
        : '${createdAt.year}-${createdAt.month}-${createdAt.day}-${createdAt.hour}-${createdAt.minute}';

    return [
      notification['type']?.toString() ?? '',
      normalizeRequestType(notification['request_type']?.toString()),
      notification['sender_id']?.toString() ?? notification['related_user_id']?.toString() ?? '',
      minuteBucket,
      notification['title']?.toString() ?? '',
    ].join('|');
  }

  static Future<String> getCurrentUserDisplayName() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('user_data');
    if (raw == null || raw.isEmpty) {
      return 'Someone';
    }

    try {
      final userData = jsonDecode(raw);
      final id = userData['id']?.toString() ?? '';
      final firstName = userData['firstName']?.toString() ?? '';
      final lastName = userData['lastName']?.toString() ?? '';
      final fullName = [firstName, lastName].where((item) => item.trim().isNotEmpty).join(' ').trim();

      if (id.isNotEmpty && fullName.isNotEmpty) {
        return 'MS:$id $fullName';
      }
      if (id.isNotEmpty) {
        return 'MS:$id';
      }
      if (fullName.isNotEmpty) {
        return fullName;
      }
    } catch (_) {
      return 'Someone';
    }

    return 'Someone';
  }

  static String _remoteExternalId({
    required String type,
    required String requestType,
    String? actorId,
    String? timestamp,
    String? message,
  }) {
    return [
      type,
      requestType,
      actorId ?? '',
      timestamp ?? '',
      message ?? '',
    ].join('|');
  }

  static DateTime? _parseRemoteTimestamp(String? value) {
    return parseDate(value);
  }

  static String _localId(String type) {
    return 'local_${type}_${DateTime.now().microsecondsSinceEpoch}_${_random.nextInt(_maxRandomSuffix)}';
  }

  static String _toSentenceCase(String value) {
    final cleaned = value.replaceAll('_', ' ').trim();
    if (cleaned.isEmpty) {
      return 'Notification';
    }
    return '${cleaned[0].toUpperCase()}${cleaned.substring(1)}';
  }

  static String _cleanName(String? value, {String? fallbackId}) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
    if (fallbackId != null && fallbackId.isNotEmpty) {
      return 'MS:$fallbackId';
    }
    return 'Someone';
  }

  static String buildActorName({
    String? firstName,
    String? lastName,
    String? displayName,
    String? fallbackId,
  }) {
    final parts = [
      firstName?.trim(),
      lastName?.trim(),
    ].where((value) => value?.isNotEmpty == true).cast<String>().toList();

    if (parts.isNotEmpty) {
      return _cleanName(parts.join(' '), fallbackId: fallbackId);
    }

    return _cleanName(displayName, fallbackId: fallbackId);
  }
}
