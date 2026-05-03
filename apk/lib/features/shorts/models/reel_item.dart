class ReelItem {
  final int id;
  final int userId;
  final String userName;
  final String profilePicture;
  final String videoUrl;
  final String thumbnailUrl;
  final String soundUrl;
  final String soundTitle;
  final String caption;
  final String privacy;
  final bool allowComments;
  final bool allowDuet;
  final bool allowDownload;
  final int viewCount;
  final int likeCount;
  final int commentCount;
  final int shareCount;
  final bool myLike;
  final String createdAt;

  const ReelItem({
    required this.id,
    required this.userId,
    required this.userName,
    required this.profilePicture,
    required this.videoUrl,
    required this.thumbnailUrl,
    this.soundUrl = '',
    this.soundTitle = '',
    required this.caption,
    required this.privacy,
    required this.allowComments,
    required this.allowDuet,
    required this.allowDownload,
    required this.viewCount,
    required this.likeCount,
    required this.commentCount,
    required this.shareCount,
    required this.myLike,
    required this.createdAt,
  });

  factory ReelItem.fromJson(Map<String, dynamic> json) {
    bool toBool(dynamic v) => v == true || v == 1 || v?.toString() == '1';

    int toInt(dynamic v) => int.tryParse(v?.toString() ?? '') ?? 0;

    return ReelItem(
      id: toInt(json['id']),
      userId: toInt(json['user_id']),
      userName: json['user_name']?.toString() ?? '',
      profilePicture: json['profile_picture']?.toString() ?? '',
      videoUrl: json['video_url']?.toString() ?? '',
      thumbnailUrl: json['thumbnail_url']?.toString() ?? '',
      soundUrl: json['sound_url']?.toString() ?? '',
      soundTitle: json['sound_title']?.toString() ?? '',
      caption: json['caption']?.toString() ?? '',
      privacy: json['privacy']?.toString() ?? 'public',
      allowComments: toBool(json['allow_comments']),
      allowDuet: toBool(json['allow_duet']),
      allowDownload: toBool(json['allow_download']),
      likeCount: toInt(json['like_count']),
      commentCount: toInt(json['comment_count']),
      viewCount: toInt(json['view_count']),
      shareCount: toInt(json['share_count']),
      myLike: toBool(json['my_like']),
      createdAt: json['created_at']?.toString() ?? '',
    );
  }

  ReelItem copyWith({
    int? viewCount,
    int? likeCount,
    int? commentCount,
    int? shareCount,
    bool? myLike,
  }) {
    return ReelItem(
      id: id,
      userId: userId,
      userName: userName,
      profilePicture: profilePicture,
      videoUrl: videoUrl,
      thumbnailUrl: thumbnailUrl,
      soundUrl: soundUrl,
      soundTitle: soundTitle,
      caption: caption,
      privacy: privacy,
      allowComments: allowComments,
      allowDuet: allowDuet,
      allowDownload: allowDownload,
      viewCount: viewCount ?? this.viewCount,
      likeCount: likeCount ?? this.likeCount,
      commentCount: commentCount ?? this.commentCount,
      shareCount: shareCount ?? this.shareCount,
      myLike: myLike ?? this.myLike,
      createdAt: createdAt,
    );
  }
}
