// lib/constants/agora_constants.dart
class AgoraConstants {
  // Agora App ID — used client-side to join channels.
  // The Agora Certificate must NEVER be stored on the client; token
  // generation happens server-side in Api2/test_token.php.
  static const String appId = '7750d283e6794eebba06e7d021e8a01c';

  // Token expiration time (1 hour)
  static const int tokenExpirationTime = 3600;
}

class AppConstants {
  /// Firestore user ID for the admin account.
  static const String adminUserId = '1';

  /// Returns a deterministic conversation document ID for two participants.
  static String conversationId(String a, String b) =>
      (a.compareTo(b) < 0) ? '${a}_$b' : '${b}_$a';

  /// Matrimonial profile report reasons shown in the report bottom sheet.
  static const List<String> reportReasons = [
    'Fake Profile',
    'Inappropriate/Obscene Content',
    'Married but claiming to be Single',
    'Financial Fraud or Deception',
    'False Age or Personal Details',
    'Harassment or Abuse',
    'Inappropriate Contact Behavior',
  ];
}
