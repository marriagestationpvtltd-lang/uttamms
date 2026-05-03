class DeleteRequestItem {
  final int id;
  final int userId;
  final String userName;
  final String userEmail;
  final String? userPhoto;
  final String? userPhone;
  final String deleteReason;
  final String? feedback;
  final String status; // pending | approved | rejected
  final String createdAt;
  final String? reviewedAt;
  final String? adminNote;

  const DeleteRequestItem({
    required this.id,
    required this.userId,
    required this.userName,
    required this.userEmail,
    this.userPhoto,
    this.userPhone,
    required this.deleteReason,
    this.feedback,
    required this.status,
    required this.createdAt,
    this.reviewedAt,
    this.adminNote,
  });

  factory DeleteRequestItem.fromJson(Map<String, dynamic> j) {
    int _i(dynamic v) => v is int ? v : int.tryParse(v?.toString() ?? '0') ?? 0;
    return DeleteRequestItem(
      id: _i(j['id']),
      userId: _i(j['userid']),
      userName: j['user_name']?.toString() ?? '',
      userEmail: j['user_email']?.toString() ?? '',
      userPhoto: j['user_photo']?.toString(),
      userPhone: j['user_phone']?.toString(),
      deleteReason: j['delete_reason']?.toString() ?? '',
      feedback: j['feedback']?.toString(),
      status: j['status']?.toString() ?? 'pending',
      createdAt: j['created_at']?.toString() ?? '',
      reviewedAt: j['reviewed_at']?.toString(),
      adminNote: j['admin_note']?.toString(),
    );
  }
}

class DeleteRequestStats {
  final int pending;
  final int approved;
  final int rejected;
  final int total;

  const DeleteRequestStats({
    required this.pending,
    required this.approved,
    required this.rejected,
    required this.total,
  });

  factory DeleteRequestStats.fromJson(Map<String, dynamic> j) {
    int _i(dynamic v) => v is int ? v : int.tryParse(v?.toString() ?? '0') ?? 0;
    return DeleteRequestStats(
      pending: _i(j['pending']),
      approved: _i(j['approved']),
      rejected: _i(j['rejected']),
      total: _i(j['total']),
    );
  }
}
