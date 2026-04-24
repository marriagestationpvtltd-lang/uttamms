import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/user_state.dart';
import '../service/verification_service.dart';
import '../Package/PackageScreen.dart' show SubscriptionPage;

/// Centralized access control utility for gated interaction system.
///
/// Enforces that users must be verified AND have active membership before:
/// - Sending requests (chat, photo, audio, video)
/// - Accessing protected features after request acceptance
///
/// Usage:
/// ```dart
/// if (await AccessControl.canSendRequest(context)) {
///   // Send the request
/// }
///
/// if (await AccessControl.canAccessFeature(context, FeatureType.chat)) {
///   // Navigate to chat
/// }
/// ```
class AccessControl {
  /// Checks if user can send any type of request.
  ///
  /// Requirements:
  /// - User must be verified (identity document approved)
  /// - User must have active membership (paid package)
  ///
  /// Returns `true` if both conditions are met, `false` otherwise.
  /// Shows appropriate dialogs to guide user if requirements not met.
  static Future<bool> canSendRequest(
    BuildContext context, {
    bool showDialogs = true,
  }) async {
    final userState = Provider.of<UserState>(context, listen: false);

    // Check verification first
    if (!userState.isVerified) {
      if (showDialogs) {
        final verified = await VerificationService.requireVerification(context);
        if (!verified) {
          return false;
        }
      } else {
        return false;
      }
    }

    // Check membership
    if (!userState.hasPackage) {
      if (showDialogs) {
        await _showMembershipRequiredDialog(context);
      }
      return false;
    }

    return true;
  }

  /// Checks if user can access a specific feature.
  ///
  /// Requirements:
  /// - User must be verified (identity document approved)
  /// - User must have active membership (paid package)
  /// - For chat/audio/video: Must have accepted request between users
  ///
  /// [featureType] specifies what feature to check access for
  /// [hasAcceptedRequest] indicates if there's an accepted request (for chat/calls)
  ///
  /// Returns `true` if all conditions are met, `false` otherwise.
  /// Shows appropriate dialogs to guide user if requirements not met.
  static Future<bool> canAccessFeature(
    BuildContext context,
    FeatureType featureType, {
    bool hasAcceptedRequest = false,
    bool showDialogs = true,
  }) async {
    final userState = Provider.of<UserState>(context, listen: false);

    // Check verification first
    if (!userState.isVerified) {
      if (showDialogs) {
        final verified = await VerificationService.requireVerification(context);
        if (!verified) {
          return false;
        }
      } else {
        return false;
      }
    }

    // Check membership
    if (!userState.hasPackage) {
      if (showDialogs) {
        await _showMembershipRequiredDialog(context);
      }
      return false;
    }

    // For features requiring accepted request
    if (_requiresAcceptedRequest(featureType)) {
      if (!hasAcceptedRequest) {
        if (showDialogs) {
          await _showRequestRequiredDialog(context, featureType);
        }
        return false;
      }
    }

    return true;
  }

  /// Determines if a feature requires an accepted request between users
  static bool _requiresAcceptedRequest(FeatureType featureType) {
    return featureType == FeatureType.chat ||
        featureType == FeatureType.audioCall ||
        featureType == FeatureType.videoCall;
  }

  /// Shows dialog informing user they need active membership
  static Future<void> _showMembershipRequiredDialog(BuildContext context) async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('सदस्यता आवश्यक / Membership Required'),
        content: const Text(
          'यो सुविधा प्रयोग गर्नको लागि तपाईंलाई सक्रिय सदस्यता चाहिन्छ।\n\n'
          'You need an active membership to use this feature.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('रद्द गर्नुहोस् / Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const SubscriptionPage(),
                ),
              );
            },
            child: const Text('प्याकेजहरू हेर्नुहोस् / View Packages'),
          ),
        ],
      ),
    );
  }

  /// Shows dialog informing user they need an accepted request
  static Future<void> _showRequestRequiredDialog(
    BuildContext context,
    FeatureType featureType,
  ) async {
    final featureName = _getFeatureName(featureType);
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('अनुरोध आवश्यक / Request Required'),
        content: Text(
          'यो $featureName सुविधा प्रयोग गर्नको लागि तपाईंको अनुरोध स्वीकृत हुनुपर्छ।\n\n'
          'Your request must be accepted to use this $featureName feature.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('ठीक छ / OK'),
          ),
        ],
      ),
    );
  }

  /// Gets the localized feature name for display
  static String _getFeatureName(FeatureType featureType) {
    switch (featureType) {
      case FeatureType.chat:
        return 'च्याट / chat';
      case FeatureType.photo:
        return 'फोटो / photo';
      case FeatureType.audioCall:
        return 'अडियो कल / audio call';
      case FeatureType.videoCall:
        return 'भिडियो कल / video call';
    }
  }
}

/// Types of features that can be gated
enum FeatureType {
  chat,
  photo,
  audioCall,
  videoCall,
}
