import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ms2026/service/auth_http_client.dart' as http;
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    if (dart.library.html) 'package:ms2026/utils/web_local_notifications_stub.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ms2026/Notification/notification_inbox_service.dart';
import 'package:ms2026/pushnotification/pushservice.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';

import 'Calling/callmanager.dart';
import 'Calling/incomingvideocall.dart';
import 'Calling/incommingcall.dart';
import 'Calling/call_state_recovery_manager.dart';
import 'Calling/unified_call_manager.dart';
import 'Calling/call_foreground_service.dart';
import 'Chat/call_overlay_manager.dart';
import 'Chat/ChatdetailsScreen.dart';
import 'Chat/adminchat.dart';
import 'Chat/screen_state_manager.dart';
import 'Startup/SplashScreen.dart';
import 'Auth/SuignupModel/signup_model.dart';
import 'Startup/onboarding.dart';
import 'constant/app_colors.dart';
import 'otherenew/modelfile.dart';
import 'otherenew/othernew.dart';
import 'otherenew/service.dart';
import 'utils/access_control.dart' as app_access;
import 'constant/app_theme.dart';
import 'core/current_user_info.dart';
import 'core/user_state.dart';
import 'navigation/app_navigation.dart';
import 'online/onlineservice.dart';
import 'config/app_endpoints.dart';
import 'service/socket_service.dart';
import 'service/connectivity_service.dart';
import 'service/chat_message_cache.dart';
import 'service/sound_settings_service.dart';
import 'service/message_tone_service.dart';
import 'service/app_sound_tone_service.dart';
import 'service/audio_manager.dart';
import 'service/verification_service.dart';
import 'widgets/global_connectivity_handler.dart';

part 'main_notification_routing.dart';
part 'main_notification_helpers.dart';
part 'main_notification_actions.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

// Notification channel IDs
const String callChannelId = 'calls_channel_v3';
const String callChannelName = 'Calls';
const String callChannelDescription =
    'Channel for WhatsApp-like call notifications';
const String messagesChannelId = 'messages_channel_v2';
const String messagesChannelName = 'Messages';
const String messagesChannelDescription = 'Channel for chat messages';
const String generalChannelId = 'general_notifications';
const String generalChannelName = 'General Notifications';
const String generalChannelDescription =
    'Channel for general app notifications';

/// Idempotently registers an Android notification channel for the custom
/// admin-uploaded incoming-call ringtone. Safe to call from any isolate as
/// many times as needed — Android ignores re-creation if a channel with the
/// same ID already exists (channel settings are immutable after creation,
/// so a URL-hash based channel ID is used to force a fresh channel whenever
/// the admin uploads a new tone).
///
/// Returns true when the channel exists (created or already existed), false
/// when the platform is web, the file is missing, or registration failed.
Future<bool> ensureCustomCallChannel(String channelId, String localPath) async {
  if (kIsWeb) return false;
  try {
    if (!File(localPath).existsSync()) return false;
    final android =
        flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return false;
    final channel = AndroidNotificationChannel(
      channelId,
      callChannelName,
      description: callChannelDescription,
      importance: Importance.max,
      playSound: true,
      sound: UriAndroidNotificationSound('file://$localPath'),
      audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
      enableVibration: true,
      enableLights: true,
      ledColor: Colors.blue,
      showBadge: true,
      vibrationPattern: Int64List.fromList([0, 1000, 500, 1000]),
    );
    await android.createNotificationChannel(channel);
    return true;
  } catch (e) {
    debugPrint('ensureCustomCallChannel failed: $e');
    return false;
  }
}

Future<void> _configureSystemUi() async {
  await SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.manual,
    overlays: SystemUiOverlay.values,
  );
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: AppColors.white,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemStatusBarContrastEnforced: false,
    systemNavigationBarColor: AppColors.white,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));
}

/// Background notification response handler — required by flutter_local_notifications
/// when the app is in the background and a notification action button is tapped
/// (action with showsUserInterface: false / side-effect only). For our call
/// notifications all actions have showsUserInterface: true, so the app is always
/// brought to the foreground first and the main-isolate
/// onDidReceiveNotificationResponse fires instead. This stub is still required
/// to be registered so the plugin does not crash looking for the handler.
@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse notificationResponse) {
  // No-op: foreground handler onDidReceiveNotificationResponse takes over
  // once the app is brought to foreground by showsUserInterface: true.
  debugPrint(
      '📱 [background] notification action: ${notificationResponse.actionId}');
}

@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Initialize local notifications plugin so we can show custom notifications
  // (e.g. full-screen call intent) from this background isolate.
  try {
    await initLocalNotifications(requestPermission: false);
  } catch (e) {
    debugPrint('⚠️ Background local notification init failed: $e');
  }

  final data = message.data;
  final type = _extractNotificationType(data);
  final normalizedData = {
    ...data,
    'type': type,
  };

  // Trigger call response for response notifications.
  // NOTE: This runs in a background Dart isolate – the stream event will NOT
  // reach the main isolate's listeners. We persist the event to SharedPreferences
  // so that the main isolate can process it when the app resumes.
  NotificationService.triggerCallResponse(normalizedData);

  // Trigger incoming call for new call notifications (stream call for same reason)
  if (type == 'call' || type == 'video_call') {
    NotificationService.triggerIncomingCall(normalizedData);
  }

  // Persist events that the main isolate must process on resume
  try {
    final prefs = await SharedPreferences.getInstance();
    final ts = DateTime.now().millisecondsSinceEpoch;

    if (type == 'call' || type == 'video_call') {
      // Save incoming call so CallOverlayWrapper can show the screen on resume
      await prefs.setString(
        'pending_incoming_call',
        json.encode({...normalizedData, '_receivedAt': ts}),
      );
    } else if (type == 'call_response' ||
        type == 'video_call_response' ||
        type == 'call_ended' ||
        type == 'video_call_ended' ||
        type == 'call_cancelled' ||
        type == 'video_call_cancelled') {
      // Save call termination event so OutgoingCall/VideoCall screens can close on resume
      await prefs.setString(
        'pending_call_event',
        json.encode({...normalizedData, '_receivedAt': ts}),
      );
    }
  } catch (_) {}

  // Real-time interactive notifications (Type 1): Incoming calls.
  // Hoisted ABOVE the inbox DB write so the full-screen-intent fires as
  // fast as possible when the app is killed — every millisecond saved
  // here reduces the time-to-ring for the user. Inbox recording follows.
  if (defaultTargetPlatform == TargetPlatform.android &&
      (type == 'call' || type == 'video_call')) {
    await _displayWhatsAppCallNotification(
        normalizedData, message.notification);
    // Fire-and-forget inbox record so we don't delay the ringing UI.
    unawaited(NotificationInboxService.recordIncomingRemoteNotification(
      data: normalizedData,
      fallbackTitle: message.notification?.title,
      fallbackBody: message.notification?.body,
    ));
    return;
  }

  // Always record notification in inbox (non-call types)
  await NotificationInboxService.recordIncomingRemoteNotification(
    data: normalizedData,
    fallbackTitle: message.notification?.title,
    fallbackBody: message.notification?.body,
  );

  // Silent notifications (Type 2): No user alert, only update app state
  const silentTypes = {
    'call_response',
    'video_call_response',
    'call_ended',
    'video_call_ended',
    'call_cancelled',
    'video_call_cancelled',
    'missed_call',
    'missed_video_call',
  };

  if (silentTypes.contains(type)) {
    // Silent notification - no visual alert needed
    debugPrint('🔕 Silent notification received: $type');
    return;
  }

  // Standard notifications (Type 3 & 4): chat, requests, profile views, etc.
  // Show them only while the app is backgrounded.
  //
  // IMPORTANT: When the FCM payload contains a `notification` block (chat
  // pushes from the PHP backend now do), the Android system itself already
  // displays the banner with the channel sound. Creating another local
  // notification here would cause duplicates. Skip in that case — the data
  // payload is still recorded in the inbox above.
  if (message.notification == null &&
      _shouldDisplayStandardNotification(normalizedData)) {
    await _displayStandardNotification(message);
  }
}

// WhatsApp-like call notification display
Future<void> _displayWhatsAppCallNotification(
  Map<String, dynamic> data,
  RemoteNotification? notification, {
  FlutterLocalNotificationsPlugin? localPlugin,
}) async {
  final plugin = localPlugin ?? flutterLocalNotificationsPlugin;

  final isVideoCall =
      data['type'] == 'video_call' || data['isVideoCall'] == 'true';
  final callerName = data['callerName'] ?? 'Unknown';
  // Use the call's channelName as the notification tag so this local
  // notification REPLACES the OS-displayed FCM banner (which the PHP
  // backend posts with the same tag = channelName). Without a matching
  // tag the OS banner would stack on top of our full-screen UI.
  final channelTag = (data['channelName']?.toString().isNotEmpty ?? false)
      ? data['channelName'].toString()
      : 'incoming_call';

  // Create notification ID based on call type
  final notificationId = isVideoCall ? 1002 : 1001;

  // WhatsApp-like action buttons. Uses dedicated phone/hangup vector
  // drawables (res/drawable/ic_call_accept.xml and ic_call_decline.xml)
  // so the lock-screen heads-up banner shows the universally-recognised
  // call icons instead of the app launcher icon.
  final acceptAction = AndroidNotificationAction(
    'accept_call',
    'Accept',
    icon: const DrawableResourceAndroidBitmap('ic_call_accept'),
    showsUserInterface: true,
    cancelNotification: false,
  );

  final declineAction = AndroidNotificationAction(
    'decline_call',
    'Decline',
    icon: const DrawableResourceAndroidBitmap('ic_call_decline'),
    showsUserInterface: true,
    cancelNotification: true,
  );

  // Resolve which notification channel to use: prefer the admin-uploaded
  // custom-ringtone channel (backed by a local file), fall back to the
  // device-default-ringtone channel (calls_channel_v3) when unavailable.
  String _activeCallChannelId = callChannelId;
  if (!kIsWeb) {
    try {
      final _p = await SharedPreferences.getInstance();
      final _path = _p.getString(AppSoundToneService.kLocalRingtonePathKey);
      final _cid = _p.getString(AppSoundToneService.kActiveCallChannelIdKey);
      if (_path != null && _cid != null && File(_path).existsSync()) {
        // Guarantee the custom-ringtone channel exists in THIS isolate before
        // posting the notification. Without this, a fresh background isolate
        // that booted before AppSoundToneService.preload() finished downloading
        // the admin ringtone would fall back silently to the default-sound
        // channel even though the path/id are now in prefs.
        final ok = await ensureCustomCallChannel(_cid, _path);
        if (ok) {
          _activeCallChannelId = _cid;
        }
      }
    } catch (_) {}
  }

  // Use simpler notification style without custom icons
  final androidDetails = AndroidNotificationDetails(
    _activeCallChannelId,
    callChannelName,
    channelDescription: callChannelDescription,
    importance: Importance.max,
    priority: Priority.max,
    ticker: 'Incoming ${isVideoCall ? 'video' : 'voice'} call',
    playSound: true,
    enableVibration: true,
    vibrationPattern: Int64List.fromList([0, 1000, 500, 1000]),
    enableLights: true,
    ledColor: const Color(0xFF25D366), // REQUIRED if lights enabled

    //isVideoCall ? 0xFF25D366 : 0xFF34B7F1,
    ledOnMs: 1000,
    ledOffMs: 500,
    fullScreenIntent: true,
    category: AndroidNotificationCategory.call,
    visibility: NotificationVisibility.public,
    color: isVideoCall ? const Color(0xFF25D366) : const Color(0xFF34B7F1),
    colorized: true,
    actions: [acceptAction, declineAction],
    styleInformation: BigTextStyleInformation(
      'Incoming ${isVideoCall ? 'video' : 'voice'} call from $callerName',
      contentTitle: isVideoCall ? '📹 Video Call' : '📞 Voice Call',
      summaryText: callerName,
      htmlFormatContent: true,
      htmlFormatTitle: true,
    ),
    tag: channelTag,
    groupKey: 'calls',
    setAsGroupSummary: false,
    onlyAlertOnce: false,
    channelShowBadge: true,
    autoCancel: false,
    ongoing: true,
    timeoutAfter: 60000,
    showWhen: true,
    usesChronometer: true,
    when: DateTime.now().millisecondsSinceEpoch,
    subText: isVideoCall ? 'Video calling...' : 'Calling...',
  );

  final iosDetails = DarwinNotificationDetails(
    presentAlert: true,
    presentBadge: true,
    presentSound: true,
    presentBanner: true,
    presentList: true,
    categoryIdentifier: 'incoming_call',
    interruptionLevel: InterruptionLevel.critical,
    threadIdentifier: 'calls',
  );

  final details = NotificationDetails(
    android: androidDetails,
    iOS: iosDetails,
  );

  debugPrint('📞 Showing WhatsApp-like call notification for: $callerName');

  // Before posting our own full-screen-intent notification, remove the
  // OS banner that Firebase's FCM SDK already displayed from the FCM
  // `notification` block. FCM picks an opaque internal id for that
  // banner so we cannot cancel it via the plain plugin.cancel(id) API;
  // we cancel by tag via the native NotificationManager so both the
  // small heads-up and the full-screen UI never coexist.
  try {
    await CallForegroundServiceManager.cancelNotificationsByTag(channelTag);
  } catch (_) {}

  await plugin.show(
    notificationId,
    isVideoCall ? '📹 Video Call' : '📞 Voice Call',
    callerName,
    details,
    payload: json.encode(data),
  );
}

// Display standard notification for messages, requests, etc.
Future<void> _displayStandardNotification(
  RemoteMessage message, {
  bool forceSilent = false,
}) async {
  final data = message.data;
  final type = _extractNotificationType(data);
  final isMessage = _isChatNotificationType(type) || _isLikelyChatPayload(data);
  final content = NotificationInboxService.buildNotificationContent(
    type: type,
    actorName: data['senderName']?.toString() ??
        data['viewerName']?.toString() ??
        data['callerName']?.toString(),
    requestType:
        data['requestType']?.toString() ?? data['request_type']?.toString(),
    messagePreview: data['message']?.toString() ?? message.notification?.body,
  );

  final dataTitle = data['title']?.toString().trim();
  final dataBody = data['body']?.toString().trim();
  final remoteTitle = message.notification?.title?.trim();
  final remoteBody = message.notification?.body?.trim();

  final resolvedTitle = isMessage
      ? (content['title'] ?? 'New chat message')
      : (dataTitle != null && dataTitle.isNotEmpty
          ? dataTitle
          : (remoteTitle != null && remoteTitle.isNotEmpty
              ? remoteTitle
              : (content['title'] ?? 'New notification')));

  final resolvedBody = isMessage
      ? (content['body'] ?? 'You have a new chat message.')
      : (dataBody != null && dataBody.isNotEmpty
          ? dataBody
          : (remoteBody != null && remoteBody.isNotEmpty
              ? remoteBody
              : (content['body'] ?? 'You have a new update.')));

  // Use different channel based on notification type
  final channelId = isMessage ? messagesChannelId : generalChannelId;
  final channelName = isMessage ? messagesChannelName : generalChannelName;
  final channelDescription =
      isMessage ? messagesChannelDescription : generalChannelDescription;

  // Category label shown as subText on notification banner
  final typeLabel = _notificationTypeLabel(type);

  final androidDetails = AndroidNotificationDetails(
    channelId,
    channelName,
    channelDescription: channelDescription,
    importance: isMessage ? Importance.high : Importance.defaultImportance,
    priority: isMessage ? Priority.high : Priority.defaultPriority,
    playSound: !forceSilent,
    silent: forceSilent,
    audioAttributesUsage: AudioAttributesUsage.notification,
    enableVibration: true,
    showWhen: true,
    subText: typeLabel,
    category: _notificationCategory(type),
  );

  final iosDetails = DarwinNotificationDetails(
    presentAlert: true,
    presentBadge: true,
    presentSound: !forceSilent,
    // sound: null → use device default notification sound. The previous
    // hardcoded 'ms_notification.wav' was removed per the centralized-sound
    // policy: admin-uploaded custom sounds are handled at playback time;
    // otherwise the OS plays its own default.
    sound: null,
    presentBanner: true,
    presentList: true,
  );

  final details = NotificationDetails(
    android: androidDetails,
    iOS: iosDetails,
  );

  /// Use conversation-based notification ID to update same chat thread
  /// instead of creating multiple notifications
  final senderId =
      data['senderId']?.toString() ?? data['sender_id']?.toString() ?? '';
  final notificationId = isMessage && senderId.isNotEmpty
      ? senderId.hashCode.abs() % 100000
      : DateTime.now().millisecondsSinceEpoch ~/ 1000;

  /// Cancel previous notification from same sender before showing new one
  /// This prevents notification pile-up and keeps only latest message visible
  if (isMessage && senderId.isNotEmpty) {
    await flutterLocalNotificationsPlugin.cancel(notificationId);
  }

  await flutterLocalNotificationsPlugin.show(
    notificationId,
    resolvedTitle,
    resolvedBody,
    details,
    payload: json.encode(data),
  );
}

String _extractNotificationType(Map<String, dynamic> data) {
  return (data['type']?.toString() ??
          data['notificationType']?.toString() ??
          data['notification_type']?.toString() ??
          data['eventType']?.toString() ??
          data['event_type']?.toString() ??
          '')
      .trim()
      .toLowerCase();
}

/// Public accessor for app foreground state - usable from other files
bool get isAppInForeground => _MyAppState.isAppInForeground;

bool _isLikelyChatPayload(Map<String, dynamic> data) {
  final hasChatRoom = (data['chatRoomId']?.toString().isNotEmpty ?? false) ||
      (data['chat_room_id']?.toString().isNotEmpty ?? false);
  final hasMessage = (data['message']?.toString().isNotEmpty ?? false) ||
      (data['body']?.toString().isNotEmpty ?? false);
  final hasSender = (data['senderId']?.toString().isNotEmpty ?? false) ||
      (data['sender_id']?.toString().isNotEmpty ?? false) ||
      (data['fromId']?.toString().isNotEmpty ?? false) ||
      (data['from_id']?.toString().isNotEmpty ?? false);
  return (hasChatRoom || hasMessage) && hasSender;
}

bool _isSilentNotificationType(String type) {
  return type == 'call_response' ||
      type == 'video_call_response' ||
      type == 'call_ended' ||
      type == 'video_call_ended' ||
      type == 'call_cancelled' ||
      type == 'video_call_cancelled' ||
      type == 'missed_call' ||
      type == 'missed_video_call';
}

bool _shouldDisplayStandardNotification(Map<String, dynamic> data) {
  final type = _extractNotificationType(data);
  if (_isSilentNotificationType(type)) return false;
  if (type == 'call' || type == 'video_call') return false;

  final hasVisibleContent =
      (data['title']?.toString().trim().isNotEmpty ?? false) ||
          (data['body']?.toString().trim().isNotEmpty ?? false) ||
          (data['message']?.toString().trim().isNotEmpty ?? false);

  return _isChatNotificationType(type) ||
      _isLikelyChatPayload(data) ||
      _isRequestNotificationType(type) ||
      type == 'profile_view' ||
      type == 'profile_like' ||
      type == 'shortlist' ||
      type == 'reel_like' ||
      type == 'reel_comment' ||
      type == 'reel_share' ||
      type == 'story_like' ||
      type == 'story_comment' ||
      (type.isEmpty && hasVisibleContent);
}

/// Returns a human-readable label shown as subText on the notification banner.
/// Users can see at a glance: "Message", "Profile Like", "Reel", etc.
String _notificationTypeLabel(String type) {
  switch (type) {
    case 'chat':
    case 'chat_message':
      return '💬 Message';
    case 'call':
      return '📞 Voice Call';
    case 'video_call':
      return '🎥 Video Call';
    case 'missed_call':
    case 'missed_video_call':
      return '📵 Missed Call';
    case 'request':
      return '🤝 Request';
    case 'request_accepted':
      return '✅ Request Accepted';
    case 'request_rejected':
      return '❌ Request Rejected';
    case 'request_reminder':
      return '🔔 Reminder';
    case 'profile_view':
      return '👁 Profile View';
    case 'profile_like':
      return '❤️ Profile Like';
    case 'shortlist':
      return '⭐ Shortlisted';
    case 'reel_like':
      return '🎬 Reel Like';
    case 'reel_comment':
      return '🎬 Reel Comment';
    case 'reel_share':
      return '🔗 Reel Share';
    case 'story_like':
      return '📸 Story Like';
    case 'story_comment':
      return '📸 Story Comment';
    default:
      return '🔔 Notification';
  }
}

/// Returns the appropriate Android notification category for system handling.
AndroidNotificationCategory _notificationCategory(String type) {
  switch (type) {
    case 'chat':
    case 'chat_message':
      return AndroidNotificationCategory.message;
    case 'call':
    case 'video_call':
    case 'missed_call':
    case 'missed_video_call':
      return AndroidNotificationCategory.missedCall;
    case 'request':
    case 'request_accepted':
    case 'request_rejected':
    case 'request_reminder':
    case 'profile_like':
    case 'shortlist':
    case 'profile_view':
      return AndroidNotificationCategory.social;
    case 'reel_like':
    case 'reel_comment':
    case 'reel_share':
    case 'story_like':
    case 'story_comment':
      return AndroidNotificationCategory.event;
    default:
      return AndroidNotificationCategory.status;
  }
}

// Create notification channels and configure actions
Future<void> initLocalNotifications({bool requestPermission = true}) async {
  // Local notifications are not supported on web
  if (kIsWeb) return;
  // Determine the ringtone sound for the call notification channel.
  // Priority: (1) admin-uploaded custom tone downloaded to local storage,
  //           (2) device default ringtone via the well-known Android URI.
  // Android notification-channel sounds are immutable after creation, so a
  // URL-derived channel ID is used for the custom-tone channel, and
  // calls_channel_v3 is used for the system-ringtone fallback.
  String? _customRingtonePath;
  String? _customChannelId;
  try {
    final _ringtonePrefs = await SharedPreferences.getInstance();
    _customRingtonePath =
        _ringtonePrefs.getString(AppSoundToneService.kLocalRingtonePathKey);
    _customChannelId =
        _ringtonePrefs.getString(AppSoundToneService.kActiveCallChannelIdKey);
  } catch (_) {}
  final bool _hasCustomRingtone = !kIsWeb &&
      _customRingtonePath != null &&
      _customChannelId != null &&
      File(_customRingtonePath).existsSync();

  // Primary call channel — device default ringtone.
  final callChannel = AndroidNotificationChannel(
    callChannelId, // 'calls_channel_v3'
    callChannelName,
    description: callChannelDescription,
    importance: Importance.max,
    playSound: true,
    sound:
        const UriAndroidNotificationSound('content://settings/system/ringtone'),
    audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
    enableVibration: true,
    enableLights: true,
    ledColor: Colors.blue,
    showBadge: true,
    vibrationPattern: Int64List.fromList([0, 1000, 500, 1000]),
  );

  // Custom-ringtone call channel — backed by the admin-uploaded local file.
  final AndroidNotificationChannel? callChannelCustom = _hasCustomRingtone
      ? AndroidNotificationChannel(
          _customChannelId,
          callChannelName,
          description: callChannelDescription,
          importance: Importance.max,
          playSound: true,
          sound: UriAndroidNotificationSound('file://$_customRingtonePath'),
          audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
          enableVibration: true,
          enableLights: true,
          ledColor: Colors.blue,
          showBadge: true,
          vibrationPattern: Int64List.fromList([0, 1000, 500, 1000]),
        )
      : null;

  // Use the device default notification sound. The previous hardcoded
  // RawResourceAndroidNotificationSound('ms_notification') was removed per
  // the centralized-sound policy: if the admin uploads a custom notification
  // tone the apk plays it at notification time; otherwise the OS picks its
  // own default.

  final messagesChannel = AndroidNotificationChannel(
    messagesChannelId,
    messagesChannelName,
    description: messagesChannelDescription,
    importance: Importance.high,
    playSound: true,
    audioAttributesUsage: AudioAttributesUsage.notification,
    enableVibration: true,
    showBadge: true,
    ledColor: Colors.green,
  );

  // Create Android notification channel for general notifications
  final generalChannel = AndroidNotificationChannel(
    generalChannelId,
    generalChannelName,
    description: generalChannelDescription,
    importance: Importance.defaultImportance,
    playSound: true,
    audioAttributesUsage: AudioAttributesUsage.notification,
    showBadge: true,
    ledColor: Colors.blue,
    enableVibration: true,
  );

  final androidPlugin =
      flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  await androidPlugin?.createNotificationChannel(callChannel);
  if (callChannelCustom != null) {
    await androidPlugin?.createNotificationChannel(callChannelCustom);
  }
  await androidPlugin?.createNotificationChannel(messagesChannel);
  await androidPlugin?.createNotificationChannel(generalChannel);

  // Remove legacy call channels — channel sounds are immutable so each
  // ringtone change requires a new channel ID; old IDs are cleaned up here.
  try {
    await androidPlugin?.deleteNotificationChannel('calls_channel');
  } catch (_) {}
  try {
    await androidPlugin?.deleteNotificationChannel('calls_channel_v2');
  } catch (_) {}

  const android = AndroidInitializationSettings('@mipmap/ic_launcher');
  const ios = DarwinInitializationSettings(
    requestAlertPermission: true,
    requestBadgePermission: true,
    requestSoundPermission: true,
    requestCriticalPermission: true,
    defaultPresentAlert: true,
    defaultPresentBadge: true,
    defaultPresentSound: true,
    defaultPresentBanner: true,
    defaultPresentList: true,
  );

  await flutterLocalNotificationsPlugin.initialize(
    const InitializationSettings(android: android, iOS: ios),
    onDidReceiveNotificationResponse: (NotificationResponse response) {
      _handleNotificationAction(response);
    },
    onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
  );

  // Handle cold-start: app was killed when user tapped a notification action.
  // In this case onDidReceiveNotificationResponse does NOT fire automatically;
  // we must call getNotificationAppLaunchDetails() to retrieve the response.
  try {
    final launchDetails =
        await flutterLocalNotificationsPlugin.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp == true) {
      final response = launchDetails!.notificationResponse;
      if (response != null) {
        // 800 ms: enough for SplashScreen minimum (300 ms) + async navigation,
        // fast enough that a ringing call is still alive when the UI opens.
        Future.delayed(const Duration(milliseconds: 800), () {
          _handleNotificationAction(response);
        });
      }
    }
  } catch (e) {
    debugPrint('📱 getNotificationAppLaunchDetails error: $e');
  }

  if (requestPermission && defaultTargetPlatform == TargetPlatform.android) {
    final granted = await androidPlugin?.requestNotificationsPermission();
    debugPrint(
        '🔔 Android notification permission: ${granted == true ? 'granted' : 'denied'}');

    // Android 14+ (API 34) requires the user to explicitly grant the
    // "Allow full-screen notifications" permission for the WhatsApp-style
    // incoming call screen to actually pop over the lockscreen. The
    // permission is auto-granted on Android < 14 (since it's a normal
    // permission there) so this call is a no-op on those versions.
    // We do not block app startup on the result — if the user denies, the
    // call still arrives as a heads-up banner, just without the full-screen
    // takeover.
    try {
      final fsiGranted =
          await androidPlugin?.requestFullScreenIntentPermission();
      debugPrint(
          '📞 Full-screen intent permission: ${fsiGranted == true ? 'granted' : 'denied/not-required'}');
    } catch (e) {
      debugPrint('📞 requestFullScreenIntentPermission failed: $e');
    }
  }

  // Configure iOS notification categories - using the correct method
  if (requestPermission && defaultTargetPlatform == TargetPlatform.iOS) {
    await _configureIOSNotifications();
  }
}

// Configure iOS notification categories with actions
Future<void> _configureIOSNotifications() async {
  // For newer versions of flutter_local_notifications, use this method
  final iosPlugin =
      flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();

  if (iosPlugin != null) {
    // await iosPlugin.noSuchMethod([callCategory]);
  }
}

Future<String> _resolveCurrentUserName() async {
  final prefs = await SharedPreferences.getInstance();
  final cachedFirstName = prefs.getString('user_firstName')?.trim();
  if (cachedFirstName != null && cachedFirstName.isNotEmpty) {
    return cachedFirstName;
  }
  final info = await CurrentUserInfo.fromPrefs();
  return info.fullName.trim().isEmpty ? 'User' : info.fullName.trim();
}

Future<String> _resolveCurrentUserId() async {
  final info = await CurrentUserInfo.fromPrefs();
  return info.userId > 0 ? info.userId.toString() : '';
}

Future<void> _syncFcmTokenToBackend(String token) async {
  if (token.trim().isEmpty) return;

  try {
    final prefs = await SharedPreferences.getInstance();
    final userDataRaw = prefs.getString('user_data');
    if (userDataRaw == null || userDataRaw.isEmpty) {
      return;
    }

    final decoded = json.decode(userDataRaw);
    if (decoded is! Map<String, dynamic>) {
      return;
    }

    final userId = decoded['id']?.toString() ?? '';
    if (userId.isEmpty) {
      return;
    }

    await prefs.setString('fcm_token', token);

    final response = await http.post(
      Uri.parse('$kApiBaseUrl/Api2/update_token.php'),
      body: {
        'user_id': userId,
        'fcm_token': token,
      },
    );

    debugPrint(
        '🔄 FCM token sync response(${response.statusCode}) for user $userId');
  } catch (e) {
    debugPrint('⚠️ FCM token sync failed: $e');
  }
}

Future<void> setupFirebaseMessaging() async {
  // Set up iOS foreground notification presentation.
  // Keep foreground push alerts disabled so chat/request notifications only
  // surface while the app is backgrounded. Incoming calls still open their UI
  // directly from onMessage.
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
      alert: false,
      badge: true,
      sound: false,
    );
  }

  await FirebaseMessaging.instance.requestPermission(
    alert: true,
    badge: true,
    sound: true,
    criticalAlert: true,
    provisional: false,
    announcement: true,
    carPlay: true,
  );

  try {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await FirebaseMessaging.instance.getAPNSToken();
    }
    final token = await FirebaseMessaging.instance.getToken();
    debugPrint("🎯 FCM TOKEN: $token");

    if (token != null && token.trim().isNotEmpty) {
      await _syncFcmTokenToBackend(token);
    }

    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      debugPrint('🔁 FCM token refreshed: $newToken');
      await _syncFcmTokenToBackend(newToken);
    });
  } catch (e) {
    debugPrint("⚠️ FCM token not ready yet: $e");
  }

  // Set up foreground message handlers
  FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
    final data = message.data;
    final type = _extractNotificationType(data);
    final normalizedData = {
      ...data,
      'type': type,
    };
    debugPrint(
        '📱 Foreground message received: ${message.notification?.title}');
    debugPrint('📱 Message data: $data');
    debugPrint('📱 Message type: $type');

    // Always record notification in inbox first
    await NotificationInboxService.recordIncomingRemoteNotification(
      data: normalizedData,
      fallbackTitle: message.notification?.title,
      fallbackBody: message.notification?.body,
    );

    // Trigger call response for response notifications
    NotificationService.triggerCallResponse(normalizedData);

    // Type 1: Real-time Interactive Notifications (Incoming Calls)
    if (type == 'call' || type == 'video_call') {
      final currentUserId = await _resolveCurrentUserId();
      final callerId = normalizedData['callerId']?.toString() ??
          normalizedData['senderId']?.toString() ??
          '';
      if (currentUserId.isNotEmpty &&
          callerId.isNotEmpty &&
          callerId == currentUserId) {
        debugPrint('⚠️ Ignored self-originated call notification');
        return;
      }
      NotificationService.triggerIncomingCall(normalizedData);
      // When app is in foreground, the calling UI opens directly via CallOverlayWrapper.
      // Do NOT show a notification banner — it would appear alongside the call screen.
      debugPrint(
          '📞 Incoming call notification - UI handled by CallOverlayWrapper');
      return;
    }

    // Type 2: Silent Data Messages (No visual notification)
    const silentTypes = {
      'call_response',
      'video_call_response',
      'call_ended',
      'video_call_ended',
      'call_cancelled',
      'video_call_cancelled',
      'missed_call',
      'missed_video_call',
    };

    if (silentTypes.contains(type)) {
      // Silent notification - handled programmatically by call screen UI
      // No notification banner needed, just recorded in inbox above
      debugPrint('🔕 Silent notification - no banner shown: $type');
      return;
    }

    // Type 3: Context-Aware Messages (Chat)
    if (_isChatNotificationType(type)) {
      // Suppress chat notifications when the recipient is actively viewing that chat
      if (!shouldShowChatNotification(normalizedData)) {
        debugPrint('💬 Chat notification suppressed - user viewing this chat');
        return;
      }
      // Foreground chat: only play the in-app tone via the unified
      // AudioManager. We DO NOT show a local notification banner here
      // because (a) the app is visible to the user, (b) the chat list /
      // unread badge updates in real time over the socket, and (c) showing
      // the banner additionally would produce a "double notification"
      // (channel-level sound on Android 8+ ignores the per-notification
      // silent flag, so the system tone would play on top of the in-app
      // tone). The background isolate handler is responsible for showing
      // the banner when the app is not in the foreground.
      MessageToneService.instance.playToneForIncomingFcmData(normalizedData);
      return;
    }

    // Show notification banner for non-chat standard types
    // (request, profile_like, reel interactions, etc.).
    if (_shouldDisplayStandardNotification(normalizedData)) {
      await _displayStandardNotification(message);
    }
  });

  // Handle messages when app is in background but opened via notification
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) async {
    final data = message.data;
    final type = _extractNotificationType(data);
    final normalizedData = {
      ...data,
      'type': type,
    };
    debugPrint('📱 App opened from background via notification');
    debugPrint('📱 Message data: $normalizedData');
    await NotificationInboxService.recordIncomingRemoteNotification(
      data: normalizedData,
      fallbackTitle: message.notification?.title,
      fallbackBody: message.notification?.body,
    );

    // Handle call termination events – trigger the stream so active call screens close
    const callTerminationTypes = {
      'call_response',
      'video_call_response',
      'call_ended',
      'video_call_ended',
      'call_cancelled',
      'video_call_cancelled',
    };
    if (callTerminationTypes.contains(type)) {
      NotificationService.triggerCallResponse(normalizedData);
      return;
    }

    // Navigate based on notification type
    if (type == 'call' || type == 'video_call') {
      // Check if the call is still within the answerable window (60 s).
      // The background isolate writes _receivedAt into pending_incoming_call
      // when the FCM push arrives. If more than 60 seconds have passed, or
      // the key is absent (already claimed by the overlay dismiss handler),
      // the call has expired — open the chat conversation instead so the
      // user is not dropped into a stale call screen.
      bool callStillActive = false;
      try {
        final prefs = await SharedPreferences.getInstance();
        final pendingStr = prefs.getString('pending_incoming_call');
        await prefs.remove('pending_incoming_call');
        if (pendingStr != null) {
          final pendingData = json.decode(pendingStr) as Map<String, dynamic>;
          final receivedAt = pendingData['_receivedAt'] as int?;
          final now = DateTime.now().millisecondsSinceEpoch;
          callStillActive = receivedAt != null && now - receivedAt <= 60000;
        }
      } catch (_) {}

      if (callStillActive) {
        _navigateToCallPage(normalizedData);
      } else {
        // Race-condition guard: _checkPendingIncomingCall (which fires from
        // AppLifecycleState.resumed) may have consumed pending_incoming_call
        // and already pushed the call screen. Wait briefly so that flag is set.
        Future.delayed(const Duration(milliseconds: 300), () {
          if (!CallManager().isCallScreenShowing &&
              !IncomingCallOverlayManager().isVisible) {
            _navigateToChatFromCallNotification(normalizedData);
          }
        });
      }
    } else if (_isChatNotificationType(type) ||
        _isLikelyChatPayload(normalizedData)) {
      if (_isAdminMessage(normalizedData)) {
        _navigateToAdminChatFromNotification(normalizedData);
      } else {
        _navigateToChatFromMessageNotification(normalizedData);
      }
    } else {
      _navigateToUserProfileFromNotification(normalizedData);
    }
  });

  // Handle initial message if app was opened from terminated state
  FirebaseMessaging.instance
      .getInitialMessage()
      .then((RemoteMessage? message) async {
    if (message != null) {
      final data = message.data;
      final type = _extractNotificationType(data);
      final normalizedData = {
        ...data,
        'type': type,
      };
      debugPrint('📱 App opened from terminated state via notification');
      debugPrint('📱 Message data: $normalizedData');
      await NotificationInboxService.recordIncomingRemoteNotification(
        data: normalizedData,
        fallbackTitle: message.notification?.title,
        fallbackBody: message.notification?.body,
      );

      WidgetsBinding.instance.addPostFrameCallback((_) async {
        // Navigate based on notification type
        if (type == 'call' || type == 'video_call') {
          // Terminated-state call: use the same direct 60-second window check
          // as onMessageOpenedApp instead of going through CallStateRecoveryManager
          // (which adds latency that can cause the call to expire before the UI opens).
          bool callStillActive = false;
          try {
            final prefs = await SharedPreferences.getInstance();
            final pendingStr = prefs.getString('pending_incoming_call');
            await prefs.remove('pending_incoming_call');
            if (pendingStr != null) {
              final pendingData =
                  json.decode(pendingStr) as Map<String, dynamic>;
              final receivedAt = pendingData['_receivedAt'] as int?;
              final now = DateTime.now().millisecondsSinceEpoch;
              callStillActive = receivedAt != null && now - receivedAt <= 60000;
            }
          } catch (_) {}
          if (callStillActive) {
            _navigateToCallPage(normalizedData);
          } else if (!CallManager().isCallScreenShowing &&
              !IncomingCallOverlayManager().isVisible) {
            _navigateToChatFromCallNotification(normalizedData);
          }
        } else if (_isChatNotificationType(type) ||
            _isLikelyChatPayload(normalizedData)) {
          if (_isAdminMessage(normalizedData)) {
            _navigateToAdminChatFromNotification(normalizedData);
          } else {
            _navigateToChatFromMessageNotification(normalizedData);
          }
        } else if (type == 'reel_like' ||
            type == 'reel_comment' ||
            type == 'reel_share' ||
            type == 'story_like' ||
            type == 'story_comment') {
          // For reel/story notifications, navigate to the user's profile
          // where their reels/stories are visible
          _navigateToUserProfileFromNotification(normalizedData);
        } else {
          _navigateToUserProfileFromNotification(normalizedData);
        }
      });
    }
  });

  FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);
}

/// Initialises Firebase without blocking [runApp]. The returned [Future] is
/// awaited in [addPostFrameCallback] before any Firebase-dependent setup runs.
Future<void> _initFirebase() async {
  try {
    if (Firebase.apps.isNotEmpty) {
      return;
    }
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);
  } catch (e) {
    if (e.toString().contains('duplicate-app')) {
      // Another isolate/engine already initialized Firebase.
      return;
    }
    debugPrint('⚠️ Firebase initialization failed: $e');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _configureSystemUi();

  // Start Firebase initialisation in the background so it does not delay
  // the first rendered frame. All Firebase-dependent setup (FCM, Auth, local
  // notifications) runs in addPostFrameCallback and explicitly awaits this
  // future before proceeding.
  final firebaseInitFuture = _initFirebase();

  // Pre-warm the chat message cache so chat screens can read cached messages
  // synchronously in initState, eliminating the white-screen flash.
  await ChatMessageCache.instance.init();

  // ── Splash asset pre-warm ───────────────────────────────────────────────
  // Pre-warm the logo GIF bytes into the rootBundle cache. Flutter's
  //    AssetImage resolver uses rootBundle.load() internally, so warming it
  //    here means the 3.3 MB GIF bytes are already in memory when the splash
  //    widget builds — the decoder starts immediately on the first frame.
  // Pre-load GIF bytes; fire-and-forget — we don't need to await the result
  // because rootBundle caches the ByteData Future itself, so any concurrent
  // AssetImage.resolve() call will wait on the same cached Future.
  unawaited(() async {
    try {
      await rootBundle.load('assets/images/ms.gif');
    } catch (e) {
      debugPrint('Splash GIF pre-warm failed (non-fatal): $e');
    }
  }());

  // Connectivity service: create now, but start the background HTTP reachability
  // checks (to google.com / cloudflare.com) after the first frame — they can
  // each take up to 5 s and must not block runApp().
  final connectivityService = ConnectivityService();

  // Initialize call state recovery manager
  final callRecoveryManager = CallStateRecoveryManager();

  // Render the first frame as fast as possible.
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SignupModel()),
        ChangeNotifierProvider<UserProfile>(
          create: (_) => UserProfile.empty(),
        ),
        ChangeNotifierProvider(create: (_) => UserState()),
        ChangeNotifierProvider.value(value: connectivityService),
        ChangeNotifierProvider.value(value: UnifiedCallManager()),
      ],
      child: const MyApp(),
    ),
  );

  WidgetsBinding.instance.addPostFrameCallback((_) async {
    // Initialise connectivity monitoring after the first frame — this fires
    // two HTTP HEAD requests (google.com + cloudflare.com) with 5 s timeouts
    // each and must not run before the UI is shown.
    // ConnectivityService defaults to _hasInternet = true so downstream code
    // works correctly before initialize() completes; the service updates its
    // state and notifies listeners once the HTTP checks finish.
    connectivityService.initialize();

    // Pre-warm centralized sound settings cache so the first call /
    // message / typing tone plays without a server round-trip.
    AppSoundToneService.instance.preload();

    // Pre-load user sound/vibration preferences so chat screens can read
    // them synchronously without an async hop.
    SoundSettingsService.instance.load();

    // Initialize the unified audio manager for all sound playback
    // (messages, calls, typing, voice recordings).
    AudioManager.instance.init();

    // Wait for Firebase before any Firebase-dependent setup so that
    // FCM token requests and local notification channel creation succeed.
    await firebaseInitFuture;

    if (Firebase.apps.isEmpty) {
      debugPrint('⚠️ Firebase not available; skipping FCM/Auth bootstrap');
      return;
    }

    // Initialise local notifications after the first frame so channel creation
    // and plugin setup don't add to the cold-start time.
    await initLocalNotifications();

    // Recover active call state BEFORE registering FCM handlers so that
    // _hasRecovered = true when getInitialMessage().then() fires — this
    // prevents the navigation from being queued and delayed unnecessarily.
    await callRecoveryManager.initialize();

    setupFirebaseMessaging();
    // Start online presence tracking if the user is already logged in
    // (handles app restarts without going through SplashScreen login)
    SharedPreferences.getInstance().then((prefs) {
      final userData = prefs.getString('user_data');
      if (userData != null && userData.isNotEmpty) {
        try {
          final parsed = json.decode(userData) as Map<String, dynamic>;
          final uid = parsed['id']?.toString() ?? '';
          if (uid.isNotEmpty) {
            MessageToneService.instance.init(uid);
          }
        } catch (_) {}
        OnlineStatusService().start();
      }
    });
  });
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  static AppLifecycleState _appLifecycleState = AppLifecycleState.detached;

  StreamSubscription<Map<String, dynamic>>? _newProposalNotificationSub;
  StreamSubscription<Map<String, dynamic>>? _proposalAcceptedNotificationSub;

  /// Check if app is currently in foreground (user actively viewing app)
  static bool get isAppInForeground =>
      _appLifecycleState == AppLifecycleState.resumed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _attachLiveRequestSocketNotifications();
    http.sessionExpiredTick.addListener(_onSessionExpired);
  }

  @override
  void dispose() {
    _newProposalNotificationSub?.cancel();
    _proposalAcceptedNotificationSub?.cancel();
    http.sessionExpiredTick.removeListener(_onSessionExpired);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Triggered when [auth_http_client.sessionExpiredTick] fires because a
  /// wrapped HTTP call returned 401. Clears stored credentials and pushes
  /// the user back to the login screen with a snackbar explaining why.
  bool _sessionRedirectInFlight = false;
  void _onSessionExpired() async {
    if (_sessionRedirectInFlight) return;
    _sessionRedirectInFlight = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('user_data');
      // bearer_token already cleared inside the wrapper.
      final navState = navigatorKey.currentState;
      if (navState != null) {
        navState.pushNamedAndRemoveUntil('/login', (_) => false);
      }
      final ctx = navigatorKey.currentContext;
      if (ctx != null) {
        final reason = http.lastSessionExpiredReason;
        ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(
          SnackBar(
            content: Text(
              (reason != null && reason.isNotEmpty)
                  ? 'Session expired: $reason. Please sign in again.'
                  : 'Your session has expired. Please sign in again.',
            ),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('Session expiry redirect error: $e');
    } finally {
      _sessionRedirectInFlight = false;
    }
  }

  void _attachLiveRequestSocketNotifications() {
    final socket = SocketService();

    _newProposalNotificationSub = socket.onNewProposal.listen((data) {
      unawaited(_showLiveRequestNotification(
        title: _incomingRequestTitle(data),
        body: _incomingRequestBody(data),
        payload: {
          'type': 'request',
          'requestType': data['requestType']?.toString() ?? 'Request',
          'senderId': data['senderId']?.toString() ?? '',
          'senderName': data['senderName']?.toString() ?? '',
          'proposalId': data['proposalId']?.toString() ?? '',
        },
      ));
    });

    _proposalAcceptedNotificationSub = socket.onProposalAccepted.listen((data) {
      unawaited(_showLiveRequestNotification(
        title: 'Request Accepted',
        body: _acceptedRequestBody(data),
        payload: {
          'type': 'request_accepted',
          'requestType': data['requestType']?.toString() ?? 'Request',
          'acceptorId': data['acceptorId']?.toString() ?? '',
          'acceptorName': data['acceptorName']?.toString() ?? '',
          'proposalId': data['proposalId']?.toString() ?? '',
        },
      ));
    });
  }

  String _incomingRequestTitle(Map<String, dynamic> data) {
    final requestType = (data['requestType']?.toString() ?? 'Request').trim();
    return requestType.toLowerCase() == 'photo'
        ? 'Photo View Request'
        : '$requestType Request';
  }

  String _incomingRequestBody(Map<String, dynamic> data) {
    final senderName = (data['senderName']?.toString() ?? '').trim();
    final requestType = (data['requestType']?.toString() ?? 'Request').trim();
    if (senderName.isEmpty) {
      return 'You received a $requestType request';
    }
    return '$senderName sent you a $requestType request';
  }

  String _acceptedRequestBody(Map<String, dynamic> data) {
    final acceptorName = (data['acceptorName']?.toString() ?? '').trim();
    final requestType = (data['requestType']?.toString() ?? 'Request').trim();
    if (acceptorName.isEmpty) {
      return 'Your $requestType request was accepted';
    }
    return '$acceptorName accepted your $requestType request';
  }

  Future<void> _showLiveRequestNotification({
    required String title,
    required String body,
    required Map<String, dynamic> payload,
  }) async {
    if (kIsWeb) return;

    const androidDetails = AndroidNotificationDetails(
      generalChannelId,
      generalChannelName,
      channelDescription: generalChannelDescription,
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      audioAttributesUsage: AudioAttributesUsage.notification,
      enableVibration: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      // sound: null → device default notification sound.
      sound: null,
      presentBanner: true,
      presentList: true,
    );

    await flutterLocalNotificationsPlugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      const NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: json.encode(payload),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appLifecycleState = state;
    ScreenStateManager().updateAppLifecycleState(state);

    if (state == AppLifecycleState.resumed) {
      OnlineStatusService().start();
      // Refresh UserState so that a document approved by the admin while the
      // app was backgrounded is reflected immediately without requiring a
      // full restart.
      _refreshUserStateOnResume();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      OnlineStatusService().setOffline();
    }
  }

  /// Reads the stored userId and asks [UserState] to fetch fresh verification
  /// and subscription data from the server.  Fire-and-forget; failures are
  /// silently swallowed because stale state is still correct for the current
  /// session.
  Future<void> _refreshUserStateOnResume() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userData = prefs.getString('user_data');
      if (userData == null || userData.isEmpty) return;
      final data = jsonDecode(userData) as Map<String, dynamic>;
      final userId = int.tryParse(data['id']?.toString() ?? '');
      if (userId == null || !mounted) return;
      unawaited(context.read<UserState>().refresh(userId));
    } catch (e) {
      debugPrint('MyApp: UserState resume refresh error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'Marriage Station',
      theme: AppTheme.lightTheme,
      navigatorObservers: [appRouteTracker],
      builder: (context, child) {
        return CallOverlayWrapper(
          child: GlobalConnectivityHandler(
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
      home: const SplashScreen(),
      routes: {
        '/login': (context) => const OnboardingScreen(),
        '/onboarding': (context) => const OnboardingScreen(),
      },
    );
  }
}

class ProfileLoader extends StatefulWidget {
  final String myId;
  final String userId;

  const ProfileLoader({
    super.key,
    required this.myId,
    required this.userId,
  });

  @override
  State<ProfileLoader> createState() => _ProfileLoaderState();
}

class _ProfileLoaderState extends State<ProfileLoader> {
  bool _isLoading = true;
  String? _error;
  final ProfileService _profileService = ProfileService();

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await _profileService.fetchProfile(
        myId: widget.myId,
        userId: widget.userId,
      );

      if (mounted) {
        Provider.of<UserProfile>(context, listen: false)
            .updateFromResponse(response);
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceAll('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                'Loading profile...',
                style: TextStyle(color: Colors.grey.shade700),
              ),
            ],
          ),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 64,
                  color: Colors.red.shade300,
                ),
                const SizedBox(height: 16),
                Text(
                  'Error Loading Profile',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _loadProfile,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                      },
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Go Back'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.grey.shade700,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    return ProfileScreen(userId: widget.userId.toString());
  }
}
