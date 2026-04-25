enum CallType { audio, video, group }

enum CallStatus { completed, missed, declined, cancelled, ended, rejected }

class CallHistory {
  final String callId;
  final String? roomId;
  final String callerId;
  final String callerName;
  final String callerImage;
  final String recipientId;
  final String recipientName;
  final String recipientImage;
  final CallType callType;
  final List<String> participants;
  final DateTime startTime;
  final DateTime? endTime;
  final int duration; // in seconds
  final CallStatus status;
  final String initiatedBy;
  final String? endedBy;

  CallHistory({
    required this.callId,
    this.roomId,
    required this.callerId,
    required this.callerName,
    required this.callerImage,
    required this.recipientId,
    required this.recipientName,
    required this.recipientImage,
    required this.callType,
    List<String>? participants,
    required this.startTime,
    this.endTime,
    required this.duration,
    required this.status,
    required this.initiatedBy,
    this.endedBy,
  }) : participants = participants ?? [];

  // Convert to map (JSON-serialisable, no Firestore types)
  Map<String, dynamic> toMap() {
    return {
      'callId': callId,
      'roomId': roomId,
      'callerId': callerId,
      'callerName': callerName,
      'callerImage': callerImage,
      'recipientId': recipientId,
      'recipientName': recipientName,
      'recipientImage': recipientImage,
      'callType': callType.toString().split('.').last,
      'participants': participants,
      'startTime': startTime.toIso8601String(),
      'endTime': endTime?.toIso8601String(),
      'duration': duration,
      'status': status.toString().split('.').last,
      'initiatedBy': initiatedBy,
      'endedBy': endedBy,
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

    List<String> _parseParticipants(dynamic v) {
      if (v == null) return [];
      if (v is List) return v.map((e) => e.toString()).toList();
      return [];
    }

    return CallHistory(
      callId: id ?? map['callId']?.toString() ?? '',
      roomId: map['roomId']?.toString(),
      callerId: map['callerId']?.toString() ?? '',
      callerName: map['callerName']?.toString() ?? '',
      callerImage: map['callerImage']?.toString() ?? '',
      recipientId: map['recipientId']?.toString() ?? '',
      recipientName: map['recipientName']?.toString() ?? '',
      recipientImage: map['recipientImage']?.toString() ?? '',
      callType: CallType.values.firstWhere(
        (e) => e.toString().split('.').last == map['callType']?.toString(),
        orElse: () => CallType.audio,
      ),
      participants: _parseParticipants(map['participants']),
      startTime: _parseDate(map['startTime']),
      endTime: map['endTime'] != null ? DateTime.tryParse(map['endTime'].toString())?.toLocal() : null,
      duration: (map['duration'] ?? 0) is int
          ? (map['duration'] ?? 0) as int
          : int.tryParse(map['duration']?.toString() ?? '0') ?? 0,
      status: CallStatus.values.firstWhere(
        (e) => e.toString().split('.').last == map['status']?.toString(),
        orElse: () => CallStatus.missed,
      ),
      initiatedBy: map['initiatedBy']?.toString() ?? '',
      endedBy: map['endedBy']?.toString(),
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
    } else if (status == CallStatus.declined || status == CallStatus.rejected) {
      return isIncoming(userId) ? 'Declined' : 'Rejected';
    } else if (status == CallStatus.cancelled) {
      return 'Cancelled';
    } else {
      return getFormattedDuration();
    }
  }

  // Get call type icon
  String getCallTypeIcon() {
    switch (callType) {
      case CallType.video:
        return '📹';
      case CallType.group:
        return '👥';
      case CallType.audio:
        return '📞';
    }
  }
}
