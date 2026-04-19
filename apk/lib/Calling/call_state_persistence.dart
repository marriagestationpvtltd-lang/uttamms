import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Persistent call state storage service
/// Saves and restores call state across app restarts
class CallStatePersistence {
  static const String _keyCallState = 'active_call_state';
  static const String _keyCallHistory = 'pending_call_history';

  /// Save active call state
  static Future<void> saveCallState(CallStateData data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyCallState, json.encode(data.toJson()));
      print('[CallStatePersistence] Saved call state: ${data.callId}');
    } catch (e) {
      print('[CallStatePersistence] Error saving call state: $e');
    }
  }

  /// Load active call state
  static Future<CallStateData?> loadCallState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? stateJson = prefs.getString(_keyCallState);
      if (stateJson != null && stateJson.isNotEmpty) {
        final data = CallStateData.fromJson(json.decode(stateJson));
        print('[CallStatePersistence] Loaded call state: ${data.callId}');
        return data;
      }
    } catch (e) {
      print('[CallStatePersistence] Error loading call state: $e');
    }
    return null;
  }

  /// Clear active call state
  static Future<void> clearCallState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyCallState);
      print('[CallStatePersistence] Cleared call state');
    } catch (e) {
      print('[CallStatePersistence] Error clearing call state: $e');
    }
  }

  /// Check if there's an active call state
  static Future<bool> hasActiveCallState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.containsKey(_keyCallState);
    } catch (e) {
      return false;
    }
  }

  /// Save pending call history update (for retry)
  static Future<void> savePendingCallHistory(
      String callHistoryId, Map<String, dynamic> updateData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pending = <String, dynamic>{
        'callHistoryId': callHistoryId,
        'updateData': updateData,
        'timestamp': DateTime.now().toIso8601String(),
      };
      await prefs.setString(_keyCallHistory, json.encode(pending));
      print('[CallStatePersistence] Saved pending call history update');
    } catch (e) {
      print('[CallStatePersistence] Error saving pending history: $e');
    }
  }

  /// Load pending call history update
  static Future<Map<String, dynamic>?> loadPendingCallHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? historyJson = prefs.getString(_keyCallHistory);
      if (historyJson != null && historyJson.isNotEmpty) {
        return json.decode(historyJson) as Map<String, dynamic>;
      }
    } catch (e) {
      print('[CallStatePersistence] Error loading pending history: $e');
    }
    return null;
  }

  /// Clear pending call history update
  static Future<void> clearPendingCallHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyCallHistory);
      print('[CallStatePersistence] Cleared pending call history');
    } catch (e) {
      print('[CallStatePersistence] Error clearing pending history: $e');
    }
  }
}

/// Call status enum
enum CallStatus {
  ringing,
  connecting,
  active,
  ending,
  ended,
  missed,
  declined,
  cancelled,
  failed,
  dropped
}

/// Call state data model
class CallStateData {
  final String callId;
  final String? callHistoryId; // Firestore document ID
  final String channelName;
  final String callerId;
  final String callerName;
  final String callerImage;
  final String receiverId;
  final String receiverName;
  final String receiverImage;
  final String callType; // 'audio' or 'video'
  final CallStatus status;
  final DateTime startTime;
  final DateTime? connectTime;
  final int? duration; // seconds
  final bool isMinimized;
  final bool isIncoming;
  final Map<String, dynamic>? extraData;

  CallStateData({
    required this.callId,
    this.callHistoryId,
    required this.channelName,
    required this.callerId,
    required this.callerName,
    required this.callerImage,
    required this.receiverId,
    required this.receiverName,
    required this.receiverImage,
    required this.callType,
    required this.status,
    required this.startTime,
    this.connectTime,
    this.duration,
    this.isMinimized = false,
    this.isIncoming = true,
    this.extraData,
  });

  Map<String, dynamic> toJson() {
    return {
      'callId': callId,
      'callHistoryId': callHistoryId,
      'channelName': channelName,
      'callerId': callerId,
      'callerName': callerName,
      'callerImage': callerImage,
      'receiverId': receiverId,
      'receiverName': receiverName,
      'receiverImage': receiverImage,
      'callType': callType,
      'status': status.name,
      'startTime': startTime.toIso8601String(),
      'connectTime': connectTime?.toIso8601String(),
      'duration': duration,
      'isMinimized': isMinimized,
      'isIncoming': isIncoming,
      'extraData': extraData,
    };
  }

  factory CallStateData.fromJson(Map<String, dynamic> json) {
    return CallStateData(
      callId: json['callId'] as String,
      callHistoryId: json['callHistoryId'] as String?,
      channelName: json['channelName'] as String,
      callerId: json['callerId'] as String,
      callerName: json['callerName'] as String,
      callerImage: json['callerImage'] as String,
      receiverId: json['receiverId'] as String,
      receiverName: json['receiverName'] as String,
      receiverImage: json['receiverImage'] as String,
      callType: json['callType'] as String,
      status: CallStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => CallStatus.ringing,
      ),
      startTime: DateTime.parse(json['startTime'] as String),
      connectTime: json['connectTime'] != null
          ? DateTime.parse(json['connectTime'] as String)
          : null,
      duration: json['duration'] as int?,
      isMinimized: json['isMinimized'] as bool? ?? false,
      isIncoming: json['isIncoming'] as bool? ?? true,
      extraData: json['extraData'] as Map<String, dynamic>?,
    );
  }

  CallStateData copyWith({
    String? callId,
    String? callHistoryId,
    String? channelName,
    String? callerId,
    String? callerName,
    String? callerImage,
    String? receiverId,
    String? receiverName,
    String? receiverImage,
    String? callType,
    CallStatus? status,
    DateTime? startTime,
    DateTime? connectTime,
    int? duration,
    bool? isMinimized,
    bool? isIncoming,
    Map<String, dynamic>? extraData,
  }) {
    return CallStateData(
      callId: callId ?? this.callId,
      callHistoryId: callHistoryId ?? this.callHistoryId,
      channelName: channelName ?? this.channelName,
      callerId: callerId ?? this.callerId,
      callerName: callerName ?? this.callerName,
      callerImage: callerImage ?? this.callerImage,
      receiverId: receiverId ?? this.receiverId,
      receiverName: receiverName ?? this.receiverName,
      receiverImage: receiverImage ?? this.receiverImage,
      callType: callType ?? this.callType,
      status: status ?? this.status,
      startTime: startTime ?? this.startTime,
      connectTime: connectTime ?? this.connectTime,
      duration: duration ?? this.duration,
      isMinimized: isMinimized ?? this.isMinimized,
      isIncoming: isIncoming ?? this.isIncoming,
      extraData: extraData ?? this.extraData,
    );
  }

  /// Check if call is still active
  bool get isActive {
    return status == CallStatus.ringing ||
        status == CallStatus.connecting ||
        status == CallStatus.active;
  }

  /// Check if call should time out
  bool shouldTimeout(Duration timeout) {
    if (status != CallStatus.ringing) return false;
    return DateTime.now().difference(startTime) > timeout;
  }

  @override
  String toString() {
    return 'CallStateData(callId: $callId, status: ${status.name}, type: $callType, incoming: $isIncoming)';
  }
}
