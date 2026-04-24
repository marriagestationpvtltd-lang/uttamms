class RequestItem {
  final int id;
  final int senderId;
  final String senderName;
  final String senderEmail;
  final String? senderPhoto;
  final int receiverId;
  final String receiverName;
  final String receiverEmail;
  final String? receiverPhoto;
  final String requestType;
  final String status;
  final String createdAt;
  final String updatedAt;

  const RequestItem({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.senderEmail,
    this.senderPhoto,
    required this.receiverId,
    required this.receiverName,
    required this.receiverEmail,
    this.receiverPhoto,
    required this.requestType,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  factory RequestItem.fromJson(Map<String, dynamic> json) {
    int _parse(dynamic v) =>
        v is int ? v : int.tryParse(v?.toString() ?? '0') ?? 0;
    return RequestItem(
      id: _parse(json['id']),
      senderId: _parse(json['sender_id']),
      senderName: json['sender_name']?.toString() ?? '',
      senderEmail: json['sender_email']?.toString() ?? '',
      senderPhoto: json['sender_photo']?.toString(),
      receiverId: _parse(json['receiver_id']),
      receiverName: json['receiver_name']?.toString() ?? '',
      receiverEmail: json['receiver_email']?.toString() ?? '',
      receiverPhoto: json['receiver_photo']?.toString(),
      requestType: json['request_type']?.toString() ?? 'match',
      status: json['status']?.toString() ?? 'pending',
      createdAt: json['created_at']?.toString() ?? '',
      updatedAt: json['updated_at']?.toString() ?? '',
    );
  }

  RequestItem copyWith({String? status}) {
    return RequestItem(
      id: id,
      senderId: senderId,
      senderName: senderName,
      senderEmail: senderEmail,
      senderPhoto: senderPhoto,
      receiverId: receiverId,
      receiverName: receiverName,
      receiverEmail: receiverEmail,
      receiverPhoto: receiverPhoto,
      requestType: requestType,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  String get senderInitials {
    final parts = senderName.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    if (senderName.isNotEmpty) return senderName[0].toUpperCase();
    return '?';
  }

  String get receiverInitials {
    final parts = receiverName.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    if (receiverName.isNotEmpty) return receiverName[0].toUpperCase();
    return '?';
  }

  String get formattedDate {
    try {
      final dt = DateTime.parse(createdAt);
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return createdAt;
    }
  }
}

class RequestStats {
  final int total;
  final int pending;
  final int accepted;
  final int rejected;
  final int cancelled;

  const RequestStats({
    required this.total,
    required this.pending,
    required this.accepted,
    required this.rejected,
    required this.cancelled,
  });

  factory RequestStats.fromJson(Map<String, dynamic> json) {
    int _parse(dynamic v) =>
        v is int ? v : int.tryParse(v?.toString() ?? '0') ?? 0;
    return RequestStats(
      total: _parse(json['total']),
      pending: _parse(json['pending']),
      accepted: _parse(json['accepted']),
      rejected: _parse(json['rejected']),
      cancelled: _parse(json['cancelled']),
    );
  }
}

class RequestPagination {
  final int total;
  final int page;
  final int perPage;
  final int totalPages;

  const RequestPagination({
    required this.total,
    required this.page,
    required this.perPage,
    required this.totalPages,
  });

  factory RequestPagination.fromJson(Map<String, dynamic> json) {
    int _parse(dynamic v) =>
        v is int ? v : int.tryParse(v?.toString() ?? '0') ?? 0;
    return RequestPagination(
      total: _parse(json['total']),
      page: _parse(json['page']),
      perPage: _parse(json['per_page']),
      totalPages: _parse(json['total_pages']),
    );
  }

  bool get hasMore => page < totalPages;
}

class RequestsResponse {
  final bool success;
  final List<RequestItem> data;
  final RequestPagination pagination;
  final RequestStats stats;

  const RequestsResponse({
    required this.success,
    required this.data,
    required this.pagination,
    required this.stats,
  });

  factory RequestsResponse.fromJson(Map<String, dynamic> json) {
    return RequestsResponse(
      success: json['success'] ?? false,
      data: List<RequestItem>.from(
          (json['data'] ?? []).map((x) => RequestItem.fromJson(x))),
      pagination: RequestPagination.fromJson(json['pagination'] ?? {}),
      stats: RequestStats.fromJson(json['stats'] ?? {}),
    );
  }
}
