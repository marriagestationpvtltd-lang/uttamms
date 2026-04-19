import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../otherenew/othernew.dart';
import '../Chat/ChatdetailsScreen.dart';
import '../pushnotification/pushservice.dart';
import '../ReUsable/loading_widgets.dart';
import 'notification_inbox_service.dart';
import 'package:ms2026/config/app_endpoints.dart';

class MatrimonyNotificationPage extends StatefulWidget {
  const MatrimonyNotificationPage({Key? key}) : super(key: key);

  @override
  State<MatrimonyNotificationPage> createState() =>
      _MatrimonyNotificationPageState();
}

class _MatrimonyNotificationPageState
    extends State<MatrimonyNotificationPage> {
  bool _pushEnabled = true;
  bool _emailEnabled = true;
  bool _smsEnabled = false;
  bool _showSettings = false;

  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;
  bool _isRefreshing = false;
  final String _baseUrl = "${kApiBaseUrl}/Api2";
  final String _requestUrl = "${kApiBaseUrl}/request/request_list.php";

  @override
  void initState() {
    super.initState();
    _fetchNotifications();
  }

  Future<void> _fetchNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    final userDataString = prefs.getString('user_data');

    if (userDataString == null || userDataString.isEmpty) {
      if (!mounted) return;
      setState(() {
        _notifications = [];
        _isLoading = false;
      });
      return;
    }

    final safeUserDataString = userDataString!;
    final userData = jsonDecode(safeUserDataString);
    final userId = userData["id"].toString();

    try {
      final responses = await Future.wait([
        http.get(Uri.parse('$_requestUrl?receiver_id=$userId')),
        http.get(Uri.parse('$_baseUrl/get_notifications.php?user_id=$userId')),
        NotificationInboxService.loadNotifications(),
      ]);

      final requestResponse = responses[0] as http.Response;
      final settingsResponse = responses[1] as http.Response;
      final localNotifications = responses[2] as List<Map<String, dynamic>>;

      final requestData = requestResponse.statusCode == 200
          ? json.decode(requestResponse.body)
          : <String, dynamic>{};
      final settingsData = settingsResponse.statusCode == 200
          ? json.decode(settingsResponse.body)
          : <String, dynamic>{};

      final requestNotifications = _mapRequestNotifications(
        List<dynamic>.from(requestData['data'] ?? const []),
      );
      final backendNotifications = _mapBackendNotifications(settingsData);
      final merged = _mergeNotifications([
        ...requestNotifications,
        ...backendNotifications,
        ...localNotifications,
      ]);

      if (!mounted) return;
      setState(() {
        _notifications = merged;
        _pushEnabled = _toBool(settingsData['settings']?['push_enabled'], true);
        _emailEnabled = _toBool(settingsData['settings']?['email_enabled'], true);
        _smsEnabled = _toBool(settingsData['settings']?['sms_enabled'], false);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching notifications: $e');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> _mapRequestNotifications(List<dynamic> items) {
    return items
        .whereType<Map>()
        .map((rawItem) {
          final item = Map<String, dynamic>.from(rawItem);
          final requestType = NotificationInboxService.normalizeRequestType(
            item['request_type']?.toString() ?? item['type']?.toString(),
          );
          final rawType = (item['type']?.toString() ?? '').toLowerCase();
          final type = rawType == 'profile_view' ? 'profile_view' : 'request';
          final actorName = _actorNameFromItem(item);
          final content = NotificationInboxService.buildNotificationContent(
            type: type,
            actorName: actorName,
            requestType: requestType,
          );

          return {
            'id': item['id']?.toString() ??
                'request_${item['sender_id']}_${item['created_at'] ?? DateTime.now().toIso8601String()}',
            'type': type,
            'request_type': requestType,
            'title': content['title'],
            'message': content['body'],
            'time': item['created_at']?.toString() ?? 'Just now',
            'created_at': item['created_at']?.toString() ?? DateTime.now().toIso8601String(),
            'is_read': _toInt(item['is_read']),
            'sender_id': item['sender_id']?.toString(),
            'related_user_id': item['sender_id']?.toString(),
            'source': 'request_api',
          };
        })
        .toList();
  }

  List<Map<String, dynamic>> _mapBackendNotifications(Map<String, dynamic> data) {
    final rawList = data['notifications'] ?? data['data'] ?? const [];
    if (rawList is! List) {
      return [];
    }

    return rawList
        .whereType<Map>()
        .map((rawItem) {
          final item = Map<String, dynamic>.from(rawItem);
          final extraData = _parseEmbeddedData(item['data']);
          final type = (item['type']?.toString() ??
                  extraData['type']?.toString() ??
                  'notification')
              .trim()
              .toLowerCase();
          final requestType = NotificationInboxService.normalizeRequestType(
            item['request_type']?.toString() ??
                extraData['requestType']?.toString() ??
                extraData['request_type']?.toString(),
          );
          final actorName = _cleanName(
            item['sender_name']?.toString() ??
                extraData['senderName']?.toString() ??
                extraData['viewerName']?.toString(),
            fallbackId: item['sender_id']?.toString() ?? extraData['senderId']?.toString(),
          );
          final content = NotificationInboxService.buildNotificationContent(
            type: type,
            actorName: actorName,
            requestType: requestType,
            messagePreview: item['body']?.toString() ?? extraData['message']?.toString(),
          );

          return {
            'id': item['id']?.toString() ??
                'backend_${type}_${item['created_at'] ?? DateTime.now().toIso8601String()}',
            'type': type,
            'request_type': requestType,
            'title': item['title']?.toString().trim().isNotEmpty == true
                ? item['title'].toString()
                : content['title'],
            'message': item['body']?.toString().trim().isNotEmpty == true
                ? item['body'].toString()
                : content['body'],
            'time': item['created_at']?.toString() ?? 'Just now',
            'created_at': item['created_at']?.toString() ?? DateTime.now().toIso8601String(),
            'is_read': _toInt(item['is_read']),
            'sender_id': item['sender_id']?.toString() ??
                extraData['senderId']?.toString() ??
                extraData['viewerId']?.toString(),
            'related_user_id': item['sender_id']?.toString() ??
                extraData['senderId']?.toString() ??
                extraData['viewerId']?.toString(),
            'source': 'backend',
          };
        })
        .toList();
  }

  List<Map<String, dynamic>> _mergeNotifications(List<Map<String, dynamic>> items) {
    // Exclude call-started and call-ended notifications — they are handled
    // by the calling UI and should not appear in the notification inbox.
    const _excludedTypes = {'call', 'video_call', 'call_ended', 'video_call_ended'};

    final sorted = items
        .where((item) => !_excludedTypes.contains(item['type']?.toString()))
        .toList();
    sorted.sort((a, b) {
      final aDate = NotificationInboxService.parseDate(a['created_at']);
      final bDate = NotificationInboxService.parseDate(b['created_at']);
      if (aDate == null && bDate == null) return 0;
      if (aDate == null) return 1;
      if (bDate == null) return -1;
      return bDate.compareTo(aDate);
    });

    final deduped = <String, Map<String, dynamic>>{};
    for (final item in sorted) {
      final key = NotificationInboxService.dedupeKey(item);
      deduped.putIfAbsent(key, () => item);
    }
    return deduped.values.toList();
  }

  Future<void> _updateNotificationSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final userDataString = prefs.getString('user_data');
    final userData = jsonDecode(userDataString!);
    final userId = userData["id"].toString();
    try {
      await http.post(
        Uri.parse('$_baseUrl/update_notification_settings.php'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'user_id': userId,
          'push_enabled': _pushEnabled ? 1 : 0,
          'email_enabled': _emailEnabled ? 1 : 0,
          'sms_enabled': _smsEnabled ? 1 : 0,
        }),
      );
    } catch (e) {
      debugPrint('Error updating settings: $e');
    }
  }

  Future<void> _markAsRead(dynamic notificationId) async {
    final id = notificationId.toString();
    try {
      if (NotificationInboxService.isLocalNotificationId(id)) {
        await NotificationInboxService.markAsRead(id);
      } else {
        await http.post(
          Uri.parse('$_baseUrl/mark_as_read.php'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'notification_id': notificationId,
          }),
        );
      }

      if (!mounted) return;
      setState(() {
        _notifications = _notifications.map((notification) {
          if (notification['id'].toString() == id) {
            return {
              ...notification,
              'is_read': 1,
            };
          }
          return notification;
        }).toList();
      });
    } catch (e) {
      debugPrint('Error marking notification as read: $e');
    }
  }

  Future<void> _deleteNotification(dynamic notificationId) async {
    final id = notificationId.toString();
    try {
      if (NotificationInboxService.isLocalNotificationId(id)) {
        await NotificationInboxService.deleteNotification(id);
      } else {
        await http.delete(
          Uri.parse('$_baseUrl/delete_notification.php'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'notification_id': notificationId,
          }),
        );
      }

      if (!mounted) return;
      setState(() {
        _notifications.removeWhere((n) => n['id'].toString() == id);
      });
    } catch (e) {
      debugPrint('Error deleting notification: $e');
    }
  }

  Future<void> _sendReminder(Map<String, dynamic> notification) async {
    final requestRecipientId = _notificationUserId(notification);
    if (requestRecipientId == null || requestRecipientId.isEmpty) {
      return;
    }

    final currentUserId = await _currentUserId();
    if (currentUserId.isEmpty) {
      return;
    }

    final senderName = await NotificationInboxService.getCurrentUserDisplayName();
    final requestType = notification['request_type']?.toString() ?? 'Request';
    final success = await NotificationService.sendRequestNotification(
      recipientUserId: requestRecipientId,
      senderName: senderName,
      senderId: currentUserId,
      requestType: requestType,
      isReminder: true,
    );

    if (!success) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to send reminder right now.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    await NotificationInboxService.recordReminderSent(
      notificationId: notification['id'].toString(),
    );
    await _fetchNotifications();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${requestType.trim()} reminder sent successfully.'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<String> _currentUserId() async {
    final prefs = await SharedPreferences.getInstance();
    final userDataString = prefs.getString('user_data');
    if (userDataString == null || userDataString.isEmpty) {
      return '';
    }

    try {
      final userData = jsonDecode(userDataString);
      return userData['id']?.toString() ?? '';
    } catch (_) {
      return '';
    }
  }

  IconData _getIcon(String type, String? requestType) {
    switch (type) {
      case 'profile_view':
        return Icons.remove_red_eye;
      case 'request':
      case 'request_sent':
      case 'request_reminder':
      case 'request_reminder_sent':
        switch (NotificationInboxService.normalizeRequestType(requestType)) {
          case 'Photo':
            return Icons.photo_camera;
          case 'Chat':
            return Icons.chat_bubble_outline;
          case 'Profile':
            return Icons.person_search;
          default:
            return Icons.mark_email_unread_outlined;
        }
      case 'request_accepted':
        return Icons.check_circle;
      case 'request_rejected':
        return Icons.cancel;
      case 'chat':
      case 'chat_message':
        return Icons.chat;
      case 'missed_call':
      case 'call':
      case 'video_call':
        return Icons.call;
      default:
        return Icons.notifications;
    }
  }

  Color _getColor(String type) {
    switch (type) {
      case 'profile_view':
        return Colors.teal;
      case 'request':
      case 'request_sent':
      case 'request_reminder':
      case 'request_reminder_sent':
        return Colors.orange;
      case 'request_accepted':
        return Colors.green;
      case 'request_rejected':
        return Colors.red;
      case 'chat':
      case 'chat_message':
        return Colors.blue;
      case 'missed_call':
      case 'call':
      case 'video_call':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  String _formatTime(String? value) {
    final parsed = NotificationInboxService.parseDate(value);
    if (parsed == null) {
      return value?.toString() ?? '';
    }

    final now = DateTime.now();
    final difference = now.difference(parsed);

    if (difference.inMinutes < 1) return 'Just now';
    if (difference.inHours < 1) return '${difference.inMinutes} min ago';
    if (difference.inDays < 1) return '${difference.inHours} hr ago';
    return '${parsed.day}/${parsed.month}/${parsed.year}';
  }

  String _reminderAvailabilityText(Map<String, dynamic> notification) {
    final remaining = NotificationInboxService.reminderRemaining(notification);
    if (remaining == null || remaining == Duration.zero) {
      return 'Reminder available now';
    }

    final hours = remaining.inHours;
    final minutes = remaining.inMinutes.remainder(60);
    return 'Reminder available in ${hours}h ${minutes}m';
  }

  Map<String, dynamic> _parseEmbeddedData(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    if (value is String && value.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
      } catch (_) {
        return {};
      }
    }
    return {};
  }

  String _actorNameFromItem(Map<String, dynamic> item) {
    return NotificationInboxService.buildActorName(
      firstName: item['firstName']?.toString(),
      lastName: item['lastName']?.toString(),
      displayName: item['sender_name']?.toString(),
      fallbackId: item['sender_id']?.toString(),
    );
  }

  String? _notificationUserId(Map<String, dynamic> notification) {
    return notification['recipient_id']?.toString() ??
        notification['related_user_id']?.toString() ??
        notification['sender_id']?.toString();
  }

  Future<void> _navigateToChat(Map<String, dynamic> notif) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataString = prefs.getString('user_data');
      if (userDataString == null || !mounted) return;

      final userData = json.decode(userDataString) as Map<String, dynamic>;
      final currentUserId = userData['id']?.toString() ?? '';
      final firstName = userData['firstName']?.toString().trim() ?? '';
      final lastName = userData['lastName']?.toString().trim() ?? '';
      final currentUserName =
          [firstName, lastName].where((s) => s.isNotEmpty).join(' ').trim();

      final senderId = notif['sender_id']?.toString() ??
          notif['related_user_id']?.toString() ??
          '';
      if (senderId.isEmpty || currentUserId.isEmpty) return;

      final chatRoomId = currentUserId.compareTo(senderId) < 0
          ? '${currentUserId}_$senderId'
          : '${senderId}_$currentUserId';

      final senderName = notif['peer_name']?.toString() ?? 'User';

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatDetailScreen(
            chatRoomId: chatRoomId,
            receiverId: senderId,
            receiverName: senderName,
            receiverImage: '',
            currentUserId: currentUserId,
            currentUserName: currentUserName.isEmpty ? 'User' : currentUserName,
            currentUserImage: '',
          ),
        ),
      );
    } catch (e) {
      debugPrint('❌ Error navigating to chat from notification: $e');
    }
  }

  bool _shouldShowReminderAction(Map<String, dynamic> notification) {
    return notification['type'] == 'request_sent' &&
        (notification['request_status']?.toString().toLowerCase() ?? 'pending') ==
            'pending';
  }

  String _cleanName(String? value, {String? fallbackId}) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
    if (fallbackId != null && fallbackId.isNotEmpty) {
      return 'MS:$fallbackId';
    }
    return 'Someone';
  }

  bool _toBool(dynamic value, bool fallback) {
    if (value is bool) return value;
    if (value is int) return value == 1;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == '1' || normalized == 'true') return true;
      if (normalized == '0' || normalized == 'false') return false;
    }
    return fallback;
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Notifications', style: TextStyle(color: Colors.white)),
        centerTitle: true,
        backgroundColor: Colors.red,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.white,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
          systemStatusBarContrastEnforced: false,
        ),
        actions: [
          IconButton(
            icon: Icon(_showSettings ? Icons.settings : Icons.settings_outlined),
            onPressed: () {
              setState(() {
                _showSettings = !_showSettings;
              });
            },
            tooltip: 'Toggle Settings',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                setState(() => _isRefreshing = true);
                await _fetchNotifications();
                if (mounted) setState(() => _isRefreshing = false);
              },
              child: ShimmerLoading(
                isLoading: _isRefreshing,
                child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                      height: _showSettings ? 200 : 0,
                      child: _showSettings
                          ? Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  child: const Row(
                                    children: [
                                      Icon(Icons.settings, color: Colors.red, size: 20),
                                      SizedBox(width: 8),
                                      Text(
                                        'Notification Settings',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.red,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                _buildToggle('Push Notifications', _pushEnabled, (val) {
                                  setState(() => _pushEnabled = val);
                                  _updateNotificationSettings();
                                }),
                                const SizedBox(height: 8),
                                _buildToggle('Email Notifications', _emailEnabled, (val) {
                                  setState(() => _emailEnabled = val);
                                  _updateNotificationSettings();
                                }),
                                const SizedBox(height: 8),
                                _buildToggle('SMS Notifications', _smsEnabled, (val) {
                                  setState(() => _smsEnabled = val);
                                  _updateNotificationSettings();
                                }),
                                const SizedBox(height: 16),
                              ],
                            )
                          : const SizedBox.shrink(),
                    ),
                    Expanded(
                      child: _notifications.isEmpty
                          ? const Center(
                              child: Text(
                                'No notifications yet',
                                style: TextStyle(color: Colors.grey),
                              ),
                            )
                          : ListView.builder(
                              itemCount: _notifications.length,
                              itemBuilder: (context, index) {
                                final notif = _notifications[index];
                                final reminderAvailable =
                                    NotificationInboxService.canSendReminder(notif);
                                final showReminderAction =
                                    _shouldShowReminderAction(notif);

                                return Dismissible(
                                  key: Key(notif['id'].toString()),
                                  direction: DismissDirection.endToStart,
                                  background: Container(
                                    color: Colors.red,
                                    alignment: Alignment.centerRight,
                                    padding: const EdgeInsets.only(right: 20),
                                    child: const Icon(
                                      Icons.delete,
                                      color: Colors.white,
                                    ),
                                  ),
                                  confirmDismiss: (direction) async {
                                    return await showDialog(
                                      context: context,
                                      builder: (BuildContext context) {
                                        return AlertDialog(
                                          title: const Text("Delete Notification"),
                                          content: const Text(
                                            "Are you sure you want to delete this notification?",
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.of(context).pop(false),
                                              child: const Text("Cancel"),
                                            ),
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.of(context).pop(true),
                                              child: const Text("Delete"),
                                            ),
                                          ],
                                        );
                                      },
                                    );
                                  },
                                  onDismissed: (direction) {
                                    _deleteNotification(notif['id']);
                                  },
                                  child: Card(
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    margin: const EdgeInsets.symmetric(vertical: 8),
                                    elevation: 2,
                                    color: notif['is_read'] == 0
                                        ? Colors.grey[50]
                                        : Colors.white,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(12),
                                      onTap: () async {
                                        if (notif['is_read'] == 0) {
                                          await _markAsRead(notif['id']);
                                        }

                                        if (!mounted) return;

                                        final type = notif['type']?.toString() ?? '';
                                        if (type == 'chat_message' || type == 'chat') {
                                          await _navigateToChat(notif);
                                        } else {
                                          final userId = _notificationUserId(notif);
                                          if (userId == null || userId.isEmpty) {
                                            return;
                                          }
                                          if (!mounted) return;
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) =>
                                                  ProfileScreen(userId: userId),
                                            ),
                                          );
                                        }
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Container(
                                              width: 44,
                                              height: 44,
                                              decoration: BoxDecoration(
                                                color: _getColor(notif['type'].toString())
                                                    .withOpacity(0.12),
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                              child: Icon(
                                                _getIcon(
                                                  notif['type'].toString(),
                                                  notif['request_type']?.toString(),
                                                ),
                                                color: _getColor(notif['type'].toString()),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment.start,
                                                    children: [
                                                      Expanded(
                                                        child: Text(
                                                          notif['title']?.toString() ?? '',
                                                          style: TextStyle(
                                                            fontWeight: notif['is_read'] == 0
                                                                ? FontWeight.bold
                                                                : FontWeight.w600,
                                                            fontSize: 15,
                                                          ),
                                                          maxLines: 2,
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                      ),
                                                      if (notif['is_read'] == 0)
                                                        const Padding(
                                                          padding:
                                                              EdgeInsets.only(left: 8, top: 4),
                                                          child: CircleAvatar(
                                                            radius: 5,
                                                            backgroundColor: Colors.red,
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 6),
                                                  Text(
                                                    notif['message']?.toString() ?? '',
                                                    style: const TextStyle(fontSize: 14),
                                                    maxLines: 3,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                  const SizedBox(height: 8),
                                                  Text(
                                                    _formatTime(
                                                      notif['created_at']?.toString() ??
                                                          notif['time']?.toString(),
                                                    ),
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      color: Colors.grey,
                                                    ),
                                                  ),
                                                  if (showReminderAction) ...[
                                                    const SizedBox(height: 10),
                                                    Row(
                                                      children: [
                                                        Expanded(
                                                          child: Text(
                                                            _reminderAvailabilityText(notif),
                                                            style: TextStyle(
                                                              fontSize: 12,
                                                              color: reminderAvailable
                                                                  ? Colors.green
                                                                  : Colors.orange,
                                                              fontWeight: FontWeight.w500,
                                                            ),
                                                          ),
                                                        ),
                                                        TextButton.icon(
                                                          onPressed: reminderAvailable
                                                              ? () => _sendReminder(notif)
                                                              : null,
                                                          icon: const Icon(Icons.notifications_active),
                                                          label: const Text('Remind'),
                                                        ),
                                                      ],
                                                    ),
                                                  ],
                                                ],
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
                  ],
                ),
              ),
            ),
            ),
    );
  }

  Widget _buildToggle(
      String title, bool value, void Function(bool) onChanged) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: Colors.red,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }
}
