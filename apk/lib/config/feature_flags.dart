/// Feature Flags System for Safe Feature Rollout
///
/// This system allows you to enable/disable features without code changes.
/// Set flags to `false` during development, then enable for testing/production.
///
/// Usage:
/// ```dart
/// if (FeatureFlags.enableAdvancedSearch) {
///   // Show advanced search feature
/// }
/// ```

class FeatureFlags {
  // ==================== New Features ====================

  /// Advanced search with filters (age, location, education, etc.)
  static const bool enableAdvancedSearch = false;

  /// Video profile feature allowing users to add video introductions
  static const bool enableVideoProfiles = false;

  /// Premium subscription features
  static const bool enablePremiumFeatures = false;

  /// Chat reactions and message effects
  static const bool enableChatReactions = false;

  /// Story/Status feature like WhatsApp
  static const bool enableStories = false;

  /// Voice messages in chat
  static const bool enableVoiceMessages = true; // Already implemented

  /// Live video streaming
  static const bool enableLiveStreaming = false;

  /// Analytics dashboard for users
  static const bool enableAnalytics = false;

  /// In-app notifications center
  static const bool enableNotificationCenter = false;

  /// Profile verification system
  static const bool enableProfileVerification = false;

  // ==================== Experimental Features ====================

  /// AI-powered match suggestions
  static const bool enableAIMatching = false;

  /// Compatibility score calculation
  static const bool enableCompatibilityScore = false;

  /// Offline mode with local caching
  static const bool enableOfflineMode = false;

  /// Dark theme
  static const bool enableDarkTheme = false;

  // ==================== Beta Features ====================

  /// Group video calls
  static const bool enableGroupCalls = false;

  /// Screen sharing in video calls
  static const bool enableScreenSharing = false;

  /// Virtual gifts system
  static const bool enableVirtualGifts = false;

  /// Icebreaker questions
  static const bool enableIcebreakers = false;

  // ==================== Debug Features ====================

  /// Debug mode with additional logging
  static const bool enableDebugMode = false;

  /// Performance monitoring
  static const bool enablePerformanceMonitoring = false;

  /// Mock data for testing
  static const bool useMockData = false;

  // ==================== Helper Methods ====================

  /// Get all enabled features
  static List<String> getEnabledFeatures() {
    final enabled = <String>[];

    if (enableAdvancedSearch) enabled.add('Advanced Search');
    if (enableVideoProfiles) enabled.add('Video Profiles');
    if (enablePremiumFeatures) enabled.add('Premium Features');
    if (enableChatReactions) enabled.add('Chat Reactions');
    if (enableStories) enabled.add('Stories');
    if (enableVoiceMessages) enabled.add('Voice Messages');
    if (enableLiveStreaming) enabled.add('Live Streaming');
    if (enableAnalytics) enabled.add('Analytics');
    if (enableNotificationCenter) enabled.add('Notification Center');
    if (enableProfileVerification) enabled.add('Profile Verification');
    if (enableAIMatching) enabled.add('AI Matching');
    if (enableCompatibilityScore) enabled.add('Compatibility Score');
    if (enableOfflineMode) enabled.add('Offline Mode');
    if (enableDarkTheme) enabled.add('Dark Theme');
    if (enableGroupCalls) enabled.add('Group Calls');
    if (enableScreenSharing) enabled.add('Screen Sharing');
    if (enableVirtualGifts) enabled.add('Virtual Gifts');
    if (enableIcebreakers) enabled.add('Icebreakers');

    return enabled;
  }

  /// Check if any beta features are enabled
  static bool get hasBetaFeatures {
    return enableGroupCalls ||
        enableScreenSharing ||
        enableVirtualGifts ||
        enableIcebreakers;
  }

  /// Check if any experimental features are enabled
  static bool get hasExperimentalFeatures {
    return enableAIMatching ||
        enableCompatibilityScore ||
        enableOfflineMode ||
        enableDarkTheme;
  }
}
