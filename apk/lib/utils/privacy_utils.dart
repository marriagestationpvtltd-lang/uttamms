import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Privacy utility functions for consistent profile photo privacy handling
/// across the entire application.
///
/// GATED INTERACTION RULES (ENFORCED):
/// - Photos are ONLY visible after photo request is accepted
/// - NO direct access even if privacy == 'free'
/// - User must be verified AND have active membership to send requests
/// - Access granted ONLY after request acceptance
class PrivacyUtils {
  /// Standard blur intensity for all private profile photos
  static const double kStandardBlurSigmaX = 15.0;
  static const double kStandardBlurSigmaY = 15.0;

  /// Computes can_view_photo from a raw profile JSON map.
  /// Uses the backend's pre-computed value if available; falls back to local logic.
  ///
  /// GATED INTERACTION: Only accepts 'accepted' photo requests.
  /// NO direct access based on privacy settings.
  static bool canViewPhotoFromJson(Map<String, dynamic> json) {
    final backendValue = json['can_view_photo'];
    if (backendValue != null) {
      return backendValue == true || backendValue == 1;
    }
    final photoRequest = json['photo_request']?.toString().toLowerCase().trim() ?? '';
    // ONLY allow access if photo request is accepted - NO direct access
    return photoRequest == 'accepted';
  }

  /// Checks if a profile photo should be shown clearly (not blurred)
  ///
  /// GATED INTERACTION: Returns true ONLY if:
  /// - canViewPhoto is provided and true (backend-computed authority), OR
  /// - photo_request == 'accepted'
  ///
  /// NO direct access based on privacy settings (removed 'free' check).
  /// Returns false otherwise (photo should be blurred)
  static bool shouldShowClearImage({
    required String? privacy,
    required String? photoRequest,
    bool? canViewPhoto,
  }) {
    // Trust backend's pre-computed result if provided
    if (canViewPhoto != null) return canViewPhoto;

    final photoRequestNormalized = photoRequest?.toString().toLowerCase().trim() ?? '';

    // ONLY show clear photo if photo request is accepted - NO direct access
    return photoRequestNormalized == 'accepted';
  }

  /// Gets the photo request status label for UI display
  static String getPhotoRequestStatusLabel(String? photoRequest) {
    final normalized = photoRequest?.toString().toLowerCase().trim() ?? '';

    switch (normalized) {
      case 'accepted':
        return 'Access Granted';
      case 'pending':
        return 'Request Pending';
      case 'rejected':
        return 'Request Rejected';
      default:
        return 'Photo Protected';
    }
  }

  /// Builds a privacy-aware profile image widget with consistent blur
  ///
  /// Parameters:
  /// - imageUrl: The URL of the profile photo
  /// - privacy: The user's privacy setting (no longer used for access control)
  /// - photoRequest: The photo request status ('accepted', 'pending', 'rejected', etc.)
  /// - width: Optional width of the image
  /// - height: Optional height of the image
  /// - fit: How the image should fit (default: BoxFit.cover)
  /// - placeholder: Optional placeholder widget while loading
  /// - errorWidget: Optional error widget if image fails to load
  static Widget buildPrivacyAwareImage({
    required String imageUrl,
    required String? privacy,
    required String? photoRequest,
    double? width,
    double? height,
    BoxFit fit = BoxFit.cover,
    Widget? placeholder,
    Widget? errorWidget,
  }) {
    final shouldShowClear = shouldShowClearImage(
      privacy: privacy,
      photoRequest: photoRequest,
    );

    if (shouldShowClear) {
      // Show clear image
      return CachedNetworkImage(
        imageUrl: imageUrl,
        width: width,
        height: height,
        fit: fit,
        placeholder: (context, url) => placeholder ??
          Container(
            width: width,
            height: height,
            color: Colors.grey[200],
            child: const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        errorWidget: (context, url, error) => errorWidget ??
          Container(
            width: width,
            height: height,
            color: Colors.grey[300],
            child: const Icon(Icons.person, color: Colors.grey),
          ),
      );
    } else {
      // Show blurred image with lock overlay
      return ImageFiltered(
        imageFilter: ui.ImageFilter.blur(
          sigmaX: kStandardBlurSigmaX,
          sigmaY: kStandardBlurSigmaY,
        ),
        child: CachedNetworkImage(
          imageUrl: imageUrl,
          width: width,
          height: height,
          fit: fit,
          placeholder: (context, url) => placeholder ??
            Container(
              width: width,
              height: height,
              color: Colors.grey[200],
              child: const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          errorWidget: (context, url, error) => errorWidget ??
            Container(
              width: width,
              height: height,
              color: Colors.grey[300],
              child: const Icon(Icons.person, color: Colors.grey),
            ),
        ),
      );
    }
  }

  /// Builds a privacy-aware CircleAvatar with consistent blur handling
  ///
  /// Use this for all avatar displays (chat lists, headers, etc.)
  static Widget buildPrivacyAwareAvatar({
    required String imageUrl,
    required String? privacy,
    required String? photoRequest,
    double radius = 20,
    Color? backgroundColor,
    Widget? child,
  }) {
    final shouldShowClear = shouldShowClearImage(
      privacy: privacy,
      photoRequest: photoRequest,
    );

    if (imageUrl.isEmpty) {
      // No image URL - show default avatar
      return CircleAvatar(
        radius: radius,
        backgroundColor: backgroundColor ?? Colors.grey[300],
        child: child ?? Icon(Icons.person, size: radius, color: Colors.grey[600]),
      );
    }

    if (shouldShowClear) {
      // Show clear avatar
      return CircleAvatar(
        radius: radius,
        backgroundColor: backgroundColor ?? Colors.grey[200],
        backgroundImage: NetworkImage(imageUrl),
        onBackgroundImageError: (_, __) {},
        child: null,
      );
    } else {
      // Show blurred avatar
      return ClipOval(
        child: ImageFiltered(
          imageFilter: ui.ImageFilter.blur(
            sigmaX: kStandardBlurSigmaX,
            sigmaY: kStandardBlurSigmaY,
          ),
          child: CircleAvatar(
            radius: radius,
            backgroundColor: backgroundColor ?? Colors.grey[200],
            backgroundImage: NetworkImage(imageUrl),
            onBackgroundImageError: (_, __) {},
            child: null,
          ),
        ),
      );
    }
  }

  /// Builds a lock icon overlay for blurred images
  static Widget buildLockOverlay({
    Color? backgroundColor,
    Color? iconColor,
    double? iconSize,
  }) {
    return Container(
      color: (backgroundColor ?? Colors.black).withOpacity(0.4),
      child: Center(
        child: Icon(
          Icons.lock_outline,
          color: iconColor ?? Colors.white,
          size: iconSize ?? 40,
        ),
      ),
    );
  }

  /// Creates a Stack with blurred image and lock overlay
  static Widget buildBlurredImageWithLock({
    required String imageUrl,
    double? width,
    double? height,
    BoxFit fit = BoxFit.cover,
    String statusLabel = 'Photo Protected',
  }) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ImageFiltered(
          imageFilter: ui.ImageFilter.blur(
            sigmaX: kStandardBlurSigmaX,
            sigmaY: kStandardBlurSigmaY,
          ),
          child: CachedNetworkImage(
            imageUrl: imageUrl,
            width: width,
            height: height,
            fit: fit,
            placeholder: (context, url) => Container(
              color: Colors.grey[200],
              child: const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            errorWidget: (context, url, error) => Container(
              color: Colors.grey[300],
              child: const Icon(Icons.person, color: Colors.grey, size: 50),
            ),
          ),
        ),
        Container(
          color: Colors.black.withOpacity(0.4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.lock_outline,
                color: Colors.white,
                size: 50,
              ),
              const SizedBox(height: 8),
              Text(
                statusLabel,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Builds a notification banner for privacy status
  /// Shows in Nepali and English to inform users about photo privacy
  static Widget buildPrivacyNotificationBanner({
    required String? privacy,
    required String? photoRequest,
  }) {
    final photoRequestNormalized = photoRequest?.toString().toLowerCase().trim() ?? '';

    // Don't show banner if photo request is accepted
    if (photoRequestNormalized == 'accepted') {
      return const SizedBox.shrink();
    }

    // Determine banner type based on status
    IconData icon;
    Color color;
    String titleNepali;
    String titleEnglish;
    String messageNepali;
    String messageEnglish;

    if (photoRequestNormalized == 'pending') {
      icon = Icons.hourglass_bottom;
      color = Colors.orange;
      titleNepali = 'तपाईंको अनुरोध पेन्डिङ छ';
      titleEnglish = 'Photo Request Pending';
      messageNepali = 'यो युजरले तपाईंको फोटो हेर्ने अनुरोध स्वीकार गर्न बाँकी छ।';
      messageEnglish = 'This user has not yet responded to your photo access request.';
    } else if (photoRequestNormalized == 'rejected') {
      icon = Icons.cancel;
      color = Colors.grey.shade600;
      titleNepali = 'तपाईंको अनुरोध अस्वीकार गरिएको छ';
      titleEnglish = 'Photo Request Rejected';
      messageNepali = 'यो युजरले तपाईंको फोटो हेर्ने अनुरोध अस्वीकार गरेको छ।';
      messageEnglish = 'This user has rejected your photo access request.';
    } else {
      // No request sent yet
      icon = Icons.lock;
      color = Colors.red.shade600;
      titleNepali = 'यो युजरले फोटो लक गरेको छ';
      titleEnglish = 'Photo is Locked';
      messageNepali = 'यो युजरको फोटो हेर्नको लागि तपाईंले रिक्वेस्ट पठाउनुपर्छ।';
      messageEnglish = 'You need to send a request to view this user\'s photo.';
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withOpacity(0.3),
          width: 1.5,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: color,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titleNepali,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                Text(
                  titleEnglish,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: color.withOpacity(0.8),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  messageNepali,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  messageEnglish,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
