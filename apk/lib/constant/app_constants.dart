class AppConstants {
  static const String adminUserId = '1';

  static const List<String> reportReasons = [
    'Fake profile',
    'Inappropriate content',
    'Harassment or abuse',
    'Spam',
    'Scam or fraud',
    'Offensive language',
    'Other',
  ];

  static String conversationId(String userId1, String userId2) {
    return (userId1.compareTo(userId2) < 0)
        ? '${userId1}_$userId2'
        : '${userId2}_$userId1';
  }
}
