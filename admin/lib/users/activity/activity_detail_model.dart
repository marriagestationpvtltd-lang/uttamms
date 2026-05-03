/// Data models for per-section member activity detail.

class ActivityDetailItem {
  final int id;
  final int? otherUserId;
  final String? otherUserName;
  final String? requestType; // requests_* section
  final String? status; // requests_* section
  final String? callType; // calls section: call_made | call_received
  final String? likeAction; // likes section: like_sent | like_removed
  final String description;
  final DateTime date;

  const ActivityDetailItem({
    required this.id,
    this.otherUserId,
    this.otherUserName,
    this.requestType,
    this.status,
    this.callType,
    this.likeAction,
    required this.description,
    required this.date,
  });

  factory ActivityDetailItem.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic v) {
      if (v == null) return DateTime(0);
      return DateTime.tryParse(v.toString()) ?? DateTime(0);
    }

    return ActivityDetailItem(
      id: json['id'] is int
          ? json['id']
          : int.tryParse(json['id'].toString()) ?? 0,
      otherUserId: json['other_user_id'] != null
          ? (json['other_user_id'] is int
                ? json['other_user_id']
                : int.tryParse(json['other_user_id'].toString()))
          : null,
      otherUserName: json['other_user_name']?.toString(),
      requestType: json['request_type']?.toString(),
      status: json['status']?.toString(),
      callType: json['call_type']?.toString(),
      likeAction: json['like_action']?.toString(),
      description: json['description']?.toString() ?? '',
      date: parseDate(json['date']),
    );
  }
}

class ActivityDetailPage {
  final String section;
  final int total;
  final int page;
  final int totalPages;
  final List<ActivityDetailItem> items;

  const ActivityDetailPage({
    required this.section,
    required this.total,
    required this.page,
    required this.totalPages,
    required this.items,
  });

  factory ActivityDetailPage.fromJson(Map<String, dynamic> json) {
    final raw = json['items'];
    final items = raw is List
        ? raw
              .map(
                (e) => ActivityDetailItem.fromJson(e as Map<String, dynamic>),
              )
              .toList()
        : <ActivityDetailItem>[];
    return ActivityDetailPage(
      section: json['section']?.toString() ?? '',
      total: json['total'] is int
          ? json['total']
          : int.tryParse(json['total'].toString()) ?? 0,
      page: json['page'] is int
          ? json['page']
          : int.tryParse(json['page'].toString()) ?? 1,
      totalPages: json['total_pages'] is int
          ? json['total_pages']
          : int.tryParse(json['total_pages'].toString()) ?? 1,
      items: items,
    );
  }

  bool get hasMore => page < totalPages;
}

/// Sections shown in the bottom sheet tabs.
enum ActivitySection {
  requestsSent,
  requestsReceived,
  chats,
  calls,
  likes,
  profileViews,
  logins,
}

extension ActivitySectionX on ActivitySection {
  String get key {
    switch (this) {
      case ActivitySection.requestsSent:
        return 'requests_sent';
      case ActivitySection.requestsReceived:
        return 'requests_received';
      case ActivitySection.chats:
        return 'chats';
      case ActivitySection.calls:
        return 'calls';
      case ActivitySection.likes:
        return 'likes';
      case ActivitySection.profileViews:
        return 'profile_views';
      case ActivitySection.logins:
        return 'logins';
    }
  }

  String get label {
    switch (this) {
      case ActivitySection.requestsSent:
        return 'Req Sent';
      case ActivitySection.requestsReceived:
        return 'Req Received';
      case ActivitySection.chats:
        return 'Chats';
      case ActivitySection.calls:
        return 'Calls';
      case ActivitySection.likes:
        return 'Likes';
      case ActivitySection.profileViews:
        return 'Profile Views';
      case ActivitySection.logins:
        return 'Logins';
    }
  }
}
