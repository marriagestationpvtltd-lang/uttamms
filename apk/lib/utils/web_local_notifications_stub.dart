/// Web stub for flutter_local_notifications.
///
/// flutter_local_notifications does not support the web platform.
/// This stub provides no-op implementations of every type/class used in
/// main.dart and elsewhere so the code compiles on web without modification.
/// All methods silently do nothing.
library web_local_notifications_stub;

import 'dart:typed_data';
import 'package:flutter/material.dart' show Color;

// ── Core plugin ──────────────────────────────────────────────────────────────

class FlutterLocalNotificationsPlugin {
  Future<bool?> initialize(
    InitializationSettings initializationSettings, {
    void Function(NotificationResponse)? onDidReceiveNotificationResponse,
    void Function(NotificationResponse)? onDidReceiveBackgroundNotificationResponse,
  }) async => true;

  Future<void> show(
    int id,
    String? title,
    String? body,
    NotificationDetails? notificationDetails, {
    String? payload,
  }) async {}

  Future<void> cancel(int id, {String? tag}) async {}

  T? resolvePlatformSpecificImplementation<T extends Object>() => null;

  Future<List<PendingNotificationRequest>> pendingNotificationRequests() async => [];
}

// ── Initialization ────────────────────────────────────────────────────────────

class InitializationSettings {
  const InitializationSettings({
    this.android,
    this.iOS,
    this.macOS,
    this.linux,
  });
  final AndroidInitializationSettings? android;
  final DarwinInitializationSettings? iOS;
  final DarwinInitializationSettings? macOS;
  final LinuxInitializationSettings? linux;
}

class AndroidInitializationSettings {
  const AndroidInitializationSettings(this.defaultIcon);
  final String defaultIcon;
}

class DarwinInitializationSettings {
  const DarwinInitializationSettings({
    this.requestAlertPermission = true,
    this.requestBadgePermission = true,
    this.requestSoundPermission = true,
    this.requestCriticalPermission = false,
    this.requestProvisionalPermission = false,
    this.notificationCategories = const [],
    this.defaultPresentAlert = true,
    this.defaultPresentBadge = true,
    this.defaultPresentSound = true,
    this.defaultPresentBanner = true,
    this.defaultPresentList = true,
  });
  final bool requestAlertPermission;
  final bool requestBadgePermission;
  final bool requestSoundPermission;
  final bool requestCriticalPermission;
  final bool requestProvisionalPermission;
  final List<DarwinNotificationCategory> notificationCategories;
  final bool defaultPresentAlert;
  final bool defaultPresentBadge;
  final bool defaultPresentSound;
  final bool defaultPresentBanner;
  final bool defaultPresentList;
}

class LinuxInitializationSettings {
  const LinuxInitializationSettings({required this.defaultActionName});
  final String defaultActionName;
}

// ── Notification details ──────────────────────────────────────────────────────

class NotificationDetails {
  const NotificationDetails({this.android, this.iOS, this.macOS, this.linux});
  final AndroidNotificationDetails? android;
  final DarwinNotificationDetails? iOS;
  final DarwinNotificationDetails? macOS;
  final LinuxNotificationDetails? linux;
}

class AndroidNotificationDetails {
  const AndroidNotificationDetails(
    this.channelId,
    this.channelName, {
    this.channelDescription,
    this.importance = Importance.defaultImportance,
    this.priority = Priority.defaultPriority,
    this.ticker,
    this.playSound = true,
    this.enableVibration = true,
    this.vibrationPattern,
    this.enableLights = false,
    this.ledColor,
    this.ledOnMs,
    this.ledOffMs,
    this.fullScreenIntent = false,
    this.category,
    this.visibility,
    this.color,
    this.colorized = false,
    this.actions = const [],
    this.styleInformation,
    this.tag,
    this.groupKey,
    this.setAsGroupSummary = false,
    this.onlyAlertOnce = false,
    this.channelShowBadge = true,
    this.autoCancel = true,
    this.ongoing = false,
    this.timeoutAfter,
    this.showWhen = true,
    this.usesChronometer = false,
    this.when,
    this.subText,
    this.largeIcon,
  });
  final String channelId;
  final String channelName;
  final String? channelDescription;
  final Importance importance;
  final Priority priority;
  final String? ticker;
  final bool playSound;
  final bool enableVibration;
  final Int64List? vibrationPattern;
  final bool enableLights;
  final Color? ledColor;
  final int? ledOnMs;
  final int? ledOffMs;
  final bool fullScreenIntent;
  final AndroidNotificationCategory? category;
  final NotificationVisibility? visibility;
  final Color? color;
  final bool colorized;
  final List<AndroidNotificationAction> actions;
  final StyleInformation? styleInformation;
  final String? tag;
  final String? groupKey;
  final bool setAsGroupSummary;
  final bool onlyAlertOnce;
  final bool channelShowBadge;
  final bool autoCancel;
  final bool ongoing;
  final int? timeoutAfter;
  final bool showWhen;
  final bool usesChronometer;
  final int? when;
  final String? subText;
  final Object? largeIcon;
}

class DarwinNotificationDetails {
  const DarwinNotificationDetails({
    this.presentAlert = true,
    this.presentBadge = true,
    this.presentSound = true,
    this.presentBanner = true,
    this.presentList = true,
    this.categoryIdentifier,
    this.interruptionLevel,
    this.threadIdentifier,
  });
  final bool presentAlert;
  final bool presentBadge;
  final bool presentSound;
  final bool presentBanner;
  final bool presentList;
  final String? categoryIdentifier;
  final InterruptionLevel? interruptionLevel;
  final String? threadIdentifier;
}

class LinuxNotificationDetails {
  const LinuxNotificationDetails();
}

// ── Enums ─────────────────────────────────────────────────────────────────────

enum Importance { min, low, defaultImportance, high, max }

enum Priority { min, low, defaultPriority, high, max }

enum NotificationVisibility { secret, private, public }

enum InterruptionLevel { passive, active, timeSensitive, critical }

// ── Supporting types ──────────────────────────────────────────────────────────

class AndroidNotificationAction {
  const AndroidNotificationAction(
    this.id,
    this.title, {
    this.icon,
    this.showsUserInterface = false,
    this.cancelNotification = true,
  });
  final String id;
  final String title;
  final Object? icon;
  final bool showsUserInterface;
  final bool cancelNotification;
}

class AndroidNotificationCategory {
  const AndroidNotificationCategory(this.name);
  final String name;
  static const AndroidNotificationCategory call = AndroidNotificationCategory('call');
  static const AndroidNotificationCategory message = AndroidNotificationCategory('msg');
}

class DrawableResourceAndroidBitmap {
  const DrawableResourceAndroidBitmap(this.name);
  final String name;
}

class FilePathAndroidBitmap {
  const FilePathAndroidBitmap(this.filePath);
  final String filePath;
}

abstract class StyleInformation {}

class BigTextStyleInformation extends StyleInformation {
  BigTextStyleInformation(
    this.bigText, {
    this.contentTitle,
    this.summaryText,
    this.htmlFormatContent = false,
    this.htmlFormatTitle = false,
  });
  final String bigText;
  final String? contentTitle;
  final String? summaryText;
  final bool htmlFormatContent;
  final bool htmlFormatTitle;
}

class BigPictureStyleInformation extends StyleInformation {
  BigPictureStyleInformation(this.bigPicture);
  final Object bigPicture;
}

class DarwinNotificationCategory {
  const DarwinNotificationCategory(
    this.identifier, {
    this.actions = const [],
    this.options = const {},
  });
  final String identifier;
  final List<DarwinNotificationAction> actions;
  final Set<DarwinNotificationCategoryOption> options;
}

class DarwinNotificationAction {
  const DarwinNotificationAction.plain(
    this.identifier,
    this.title, {
    this.options = const {},
  });
  final String identifier;
  final String title;
  final Set<DarwinNotificationActionOption> options;
}

enum DarwinNotificationActionOption {
  foreground,
  destructive,
  authenticationRequired,
}

enum DarwinNotificationCategoryOption {
  customDismissAction,
  allowInCarPlay,
  hiddenPreviewShowTitle,
  hiddenPreviewShowSubtitle,
}

class IOSFlutterLocalNotificationsPlugin
    extends ResolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin> {}


class NotificationResponse {
  const NotificationResponse({
    this.id,
    this.actionId,
    this.input,
    this.payload,
    this.notificationResponseType = NotificationResponseType.selectedNotification,
  });
  final int? id;
  final String? actionId;
  final String? input;
  final String? payload;
  final NotificationResponseType notificationResponseType;
}

enum NotificationResponseType {
  selectedNotification,
  selectedNotificationAction,
}

class PendingNotificationRequest {
  const PendingNotificationRequest(this.id, this.title, this.body, this.payload);
  final int id;
  final String? title;
  final String? body;
  final String? payload;
}

class ResolvePlatformSpecificImplementation<T extends Object> {
  Future<bool?> requestNotificationsPermission() async => true;
  Future<bool?> requestExactAlarmsPermission() async => true;
}

// ── Android-specific plugin ───────────────────────────────────────────────────

class AndroidFlutterLocalNotificationsPlugin
    extends ResolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin> {
  Future<void> createNotificationChannel(AndroidNotificationChannel channel) async {}
  Future<void> deleteNotificationChannel(String channelId) async {}
}

class AndroidNotificationChannel {
  const AndroidNotificationChannel(
    this.id,
    this.name, {
    this.description,
    this.importance = Importance.defaultImportance,
    this.playSound = true,
    this.enableVibration = true,
    this.enableLights = false,
    this.ledColor,
    this.showBadge = true,
    this.vibrationPattern,
  });
  final String id;
  final String name;
  final String? description;
  final Importance importance;
  final bool playSound;
  final bool enableVibration;
  final bool enableLights;
  final Color? ledColor;
  final bool showBadge;
  final Int64List? vibrationPattern;
}
