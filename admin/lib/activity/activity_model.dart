class UserActivity {
  final int id;
  final int userId;
  final String userName;
  final int? targetId;
  final String? targetName;
  final String activityType;
  final String description;
  final DateTime createdAt;

  const UserActivity({
    required this.id,
    required this.userId,
    required this.userName,
    this.targetId,
    this.targetName,
    required this.activityType,
    required this.description,
    required this.createdAt,
  });

  factory UserActivity.fromJson(Map<String, dynamic> json) {
    return UserActivity(
      id:           json['id'] is int ? json['id'] : int.tryParse(json['id'].toString()) ?? 0,
      userId:       json['user_id'] is int ? json['user_id'] : int.tryParse(json['user_id'].toString()) ?? 0,
      userName:     json['user_name']?.toString() ?? '',
      targetId:     json['target_id'] != null
                      ? (json['target_id'] is int ? json['target_id'] : int.tryParse(json['target_id'].toString()))
                      : null,
      targetName:   json['target_name']?.toString(),
      activityType: json['activity_type']?.toString() ?? '',
      description:  json['description']?.toString() ?? '',
      createdAt:    json['created_at'] != null
                      ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
                      : DateTime.now(),
    );
  }
}

class ActivityFeedResponse {
  final bool success;
  final List<UserActivity> activities;
  final int total;
  final int page;
  final int limit;
  final int totalPages;

  const ActivityFeedResponse({
    required this.success,
    required this.activities,
    required this.total,
    required this.page,
    required this.limit,
    required this.totalPages,
  });

  factory ActivityFeedResponse.fromJson(Map<String, dynamic> json) {
    final list = (json['activities'] as List<dynamic>? ?? [])
        .map((e) => UserActivity.fromJson(e as Map<String, dynamic>))
        .toList();
    return ActivityFeedResponse(
      success:    json['success'] == true || json['status'] == 'success',
      activities: list,
      total:      json['total'] is int ? json['total'] : int.tryParse(json['total'].toString()) ?? 0,
      page:       json['page']  is int ? json['page']  : int.tryParse(json['page'].toString())  ?? 1,
      limit:      json['limit'] is int ? json['limit'] : int.tryParse(json['limit'].toString()) ?? 50,
      totalPages: json['total_pages'] is int
                    ? json['total_pages']
                    : int.tryParse(json['total_pages'].toString()) ?? 1,
    );
  }
}
