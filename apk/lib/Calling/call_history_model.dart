enum CallType { audio, video }

enum CallStatus { completed, missed, declined, cancelled }

class CallHistory {
  final String callId;
  final String callerId;
  final String callerName;
  final String callerImage;
  final String recipientId;
  final String recipientName;
  final String recipientImage;
  final CallType callType;
  final DateTime startTime;
  final DateTime? endTime;
  final int duration; // in seconds
  final CallStatus status;
  final String initiatedBy;

  CallHistory({
    required this.callId,
    required this.callerId,
    required this.callerName,
    required this.callerImage,
    required this.recipientId,
    required this.recipientName,
    required this.recipientImage,
    required this.callType,
    required this.startTime,
    this.endTime,
    required this.duration,
    required this.status,
    required this.initiatedBy,
  });

  // Convert to map (JSON-serialisable, no Firestore types)
  Map<String, dynamic> toMap() {
    return {
      'callId': callId,
      'callerId': callerId,
      'callerName': callerName,
      'callerImage': callerImage,
      'recipientId': recipientId,
      'recipientName': recipientName,
      'recipientImage': recipientImage,
      'callType': callType.toString().split('.').last,
      'startTime': startTime.toIso8601String(),
      'endTime': endTime?.toIso8601String(),
      'duration': duration,
      'status': status.toString().split('.').last,
      'initiatedBy': initiatedBy,
    };
  }

  // Create from map (works with REST JSON or Socket.IO data)
  factory CallHistory.fromMap(Map<String, dynamic> map, [String? id]) {
    DateTime _parseDate(dynamic v) {
      if (v == null) return DateTime.now();
      if (v is DateTime) return v.isUtc ? v.toLocal() : v;
      final dt = DateTime.tryParse(v.toString());
      return dt != null ? dt.toLocal() : DateTime.now();
    }

    return CallHistory(
      callId: id ?? map['callId'] ?? '',
      callerId: map['callerId'] ?? '',
      callerName: map['callerName'] ?? '',
      callerImage: map['callerImage'] ?? '',
      recipientId: map['recipientId'] ?? '',
      recipientName: map['recipientName'] ?? '',
      recipientImage: map['recipientImage'] ?? '',
      callType: CallType.values.firstWhere(
        (e) => e.toString().split('.').last == map['callType'],
        orElse: () => CallType.audio,
      ),
      startTime: _parseDate(map['startTime']),
      endTime: map['endTime'] != null ? DateTime.tryParse(map['endTime'].toString())?.toLocal() : null,
      duration: (map['duration'] ?? 0) is int
          ? (map['duration'] ?? 0)
          : int.tryParse(map['duration'].toString()) ?? 0,
      status: CallStatus.values.firstWhere(
        (e) => e.toString().split('.').last == map['status'],
        orElse: () => CallStatus.missed,
      ),
      initiatedBy: map['initiatedBy'] ?? '',
    );
  }

  // Check if call is incoming for a specific user
  bool isIncoming(String userId) {
    return recipientId == userId;
  }

  // Check if call is outgoing for a specific user
  bool isOutgoing(String userId) {
    return callerId == userId;
  }

  // Get the other person's ID for a specific user
  String getOtherPersonId(String userId) {
    return callerId == userId ? recipientId : callerId;
  }

  // Get the other person's name for a specific user
  String getOtherPersonName(String userId) {
    return callerId == userId ? recipientName : callerName;
  }

  // Get the other person's image for a specific user
  String getOtherPersonImage(String userId) {
    return callerId == userId ? recipientImage : callerImage;
  }

  // Format duration as MM:SS
  String getFormattedDuration() {
    final minutes = duration ~/ 60;
    final seconds = duration % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  // Get call status text
  String getStatusText(String userId) {
    if (status == CallStatus.missed) {
      return isIncoming(userId) ? 'Missed' : 'No Answer';
    } else if (status == CallStatus.declined) {
      return isIncoming(userId) ? 'Declined' : 'Rejected';
    } else if (status == CallStatus.cancelled) {
      return 'Cancelled';
    } else {
      return getFormattedDuration();
    }
  }

  // Get call type icon
  String getCallTypeIcon() {
    return callType == CallType.video ? '📹' : '📞';
  }
}
