import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../constant/app_colors.dart';
import '../constant/app_dimensions.dart';
import '../constant/app_text_styles.dart';
import '../utils/privacy_utils.dart';

/// Reusable privacy-aware profile card widget
/// This card ensures consistent privacy enforcement across all sections of the app
///
/// Privacy Rules:
/// - If privacy == 'free': Photo is always visible (clear)
/// - If privacy != 'free' AND photo_request == 'accepted': Photo is visible (clear)
/// - Otherwise: Photo is BLURRED with lock overlay
class PrivacyAwareProfileCard extends StatelessWidget {
  final String imageUrl;
  final String name;
  final String? age;
  final String? location;
  final String? profession;
  final String? height;
  final String? privacy;
  final String? photoRequest;
  final bool? isPremium;
  final bool? isVerified;
  final bool? isOnline;
  final bool showNewBadge;
  final VoidCallback? onTap;
  final VoidCallback? onLike;
  final VoidCallback? onMessage;
  final VoidCallback? onSendRequest;
  final Widget? customActionButton;
  final List<String>? interests;
  final CardLayout layout;

  const PrivacyAwareProfileCard({
    super.key,
    required this.imageUrl,
    required this.name,
    required this.privacy,
    required this.photoRequest,
    this.age,
    this.location,
    this.profession,
    this.height,
    this.isPremium,
    this.isVerified,
    this.isOnline,
    this.showNewBadge = false,
    this.onTap,
    this.onLike,
    this.onMessage,
    this.onSendRequest,
    this.customActionButton,
    this.interests,
    this.layout = CardLayout.vertical,
  });

  @override
  Widget build(BuildContext context) {
    final shouldShowClear = PrivacyUtils.shouldShowClearImage(
      privacy: privacy,
      photoRequest: photoRequest,
    );

    switch (layout) {
      case CardLayout.vertical:
        return _buildVerticalCard(shouldShowClear);
      case CardLayout.grid:
        return _buildGridCard(shouldShowClear);
      case CardLayout.horizontal:
        return _buildHorizontalCard(shouldShowClear);
    }
  }

  /// Vertical card layout (default) - used in profile lists
  Widget _buildVerticalCard(bool shouldShowClear) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: AppDimensions.borderRadiusMD,
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowLight.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: AppDimensions.borderRadiusMD,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppDimensions.borderRadiusMD,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image Section with Privacy
              _buildImageSection(shouldShowClear),
              // Details Section
              _buildDetailsSection(shouldShowClear),
            ],
          ),
        ),
      ),
    );
  }

  /// Grid card layout - used in premium members, recent members
  Widget _buildGridCard(bool shouldShowClear) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppDimensions.radiusMD),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppDimensions.radiusMD),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppDimensions.radiusMD),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image with overlay info
              _buildGridImageSection(shouldShowClear),
              // Bottom info section
              if (shouldShowClear && interests != null && interests!.isNotEmpty)
                _buildInterestsSection(),
              // Action button
              if (customActionButton != null)
                Padding(
                  padding: const EdgeInsets.all(AppDimensions.spacingSM),
                  child: customActionButton,
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Horizontal card layout - used in matched profiles carousel
  Widget _buildHorizontalCard(bool shouldShowClear) {
    return Container(
      width: 200,
      decoration: BoxDecoration(
        color: AppColors.white,
        border: Border.all(color: AppColors.primary),
        borderRadius: BorderRadius.circular(AppDimensions.radiusSM),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppDimensions.radiusSM),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppDimensions.radiusSM),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Image with name overlay
              _buildHorizontalImageSection(shouldShowClear),
              // Info section
              _buildHorizontalInfoSection(shouldShowClear),
            ],
          ),
        ),
      ),
    );
  }

  /// Image section for vertical card
  Widget _buildImageSection(bool shouldShowClear) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppDimensions.radiusMD),
          ),
          child: SizedBox(
            height: 200,
            width: double.infinity,
            child: _buildPrivacyAwareImage(shouldShowClear),
          ),
        ),
        // Badges - only show if image is clear
        if (shouldShowClear)
          Positioned(
            top: 12,
            left: 12,
            child: Row(
              children: [
                if (showNewBadge)
                  _buildBadge(
                    icon: Icons.new_releases,
                    color: AppColors.success,
                    label: 'New',
                  ),
                if (showNewBadge && (isPremium == true || isVerified == true))
                  const SizedBox(width: 8),
                if (isPremium == true)
                  _buildBadge(
                    icon: Icons.workspace_premium,
                    color: AppColors.premium,
                    label: 'Premium',
                  ),
                if (isPremium == true && isVerified == true)
                  const SizedBox(width: 8),
                if (isVerified == true)
                  _buildBadge(
                    icon: Icons.verified,
                    color: AppColors.verified,
                    label: 'Verified',
                  ),
              ],
            ),
          ),
        // Lock overlay if image is blurred
        if (!shouldShowClear) _buildLockOverlay(),
        // Online status - only show if image is clear
        if (shouldShowClear && isOnline == true)
          Positioned(
            top: 12,
            right: 12,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: AppColors.online,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.white, width: 2),
              ),
            ),
          ),
      ],
    );
  }

  /// Image section for grid card
  Widget _buildGridImageSection(bool shouldShowClear) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppDimensions.radiusMD),
          ),
          child: SizedBox(
            height: 180,
            width: double.infinity,
            child: _buildPrivacyAwareImage(shouldShowClear),
          ),
        ),
        // Gradient overlay for text readability
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            height: 80,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withOpacity(0.7),
                ],
              ),
            ),
          ),
        ),
        // User info overlay - only show if image is clear
        if (shouldShowClear)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  age != null ? '$name, $age' : name,
                  style: AppTextStyles.labelLarge.copyWith(
                    color: AppColors.white,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (location != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        size: 14,
                        color: AppColors.white,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          location!,
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        // Badges - only show if image is clear
        if (shouldShowClear)
          Positioned(
            top: 12,
            right: 12,
            child: Row(
              children: [
                if (isPremium == true)
                  _buildBadge(
                    icon: Icons.workspace_premium,
                    color: AppColors.premium,
                    label: '',
                  ),
                if (isVerified == true) ...[
                  if (isPremium == true) const SizedBox(width: 8),
                  _buildBadge(
                    icon: Icons.verified,
                    color: AppColors.verified,
                    label: '',
                  ),
                ],
              ],
            ),
          ),
        // Lock overlay if image is blurred
        if (!shouldShowClear) _buildLockOverlay(),
      ],
    );
  }

  /// Image section for horizontal card
  Widget _buildHorizontalImageSection(bool shouldShowClear) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppDimensions.radiusSM),
          ),
          child: SizedBox(
            height: 140,
            width: double.infinity,
            child: _buildPrivacyAwareImage(shouldShowClear),
          ),
        ),
        // Name overlay at bottom - only show if clear
        if (shouldShowClear)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              color: Colors.black.withOpacity(0.55),
              child: Text(
                name,
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.white,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        // Lock overlay if image is blurred
        if (!shouldShowClear) _buildLockOverlay(compact: true),
      ],
    );
  }

  /// Privacy-aware image widget
  Widget _buildPrivacyAwareImage(bool shouldShowClear) {
    if (shouldShowClear) {
      // Clear image
      return CachedNetworkImage(
        imageUrl: imageUrl,
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(
          color: AppColors.borderLight,
          child: const Center(
            child: CircularProgressIndicator(
              color: AppColors.primary,
              strokeWidth: 2,
            ),
          ),
        ),
        errorWidget: (context, url, error) => Container(
          color: AppColors.borderLight,
          child: const Icon(
            Icons.person,
            size: 64,
            color: AppColors.textHint,
          ),
        ),
      );
    } else {
      // Blurred image
      return ImageFiltered(
        imageFilter: ui.ImageFilter.blur(
          sigmaX: PrivacyUtils.kStandardBlurSigmaX,
          sigmaY: PrivacyUtils.kStandardBlurSigmaY,
        ),
        child: CachedNetworkImage(
          imageUrl: imageUrl,
          fit: BoxFit.cover,
          placeholder: (context, url) => Container(
            color: AppColors.borderLight,
            child: const Center(
              child: CircularProgressIndicator(
                color: AppColors.primary,
                strokeWidth: 2,
              ),
            ),
          ),
          errorWidget: (context, url, error) => Container(
            color: AppColors.borderLight,
            child: const Icon(
              Icons.person,
              size: 64,
              color: AppColors.textHint,
            ),
          ),
        ),
      );
    }
  }

  /// Lock overlay for blurred images
  Widget _buildLockOverlay({bool compact = false}) {
    return Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withOpacity(0.3),
              Colors.black.withOpacity(0.5),
            ],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.lock_outline,
              color: AppColors.white,
              size: compact ? 32 : 50,
            ),
            const SizedBox(height: 8),
            Text(
              PrivacyUtils.getPhotoRequestStatusLabel(photoRequest),
              style: TextStyle(
                color: AppColors.white,
                fontSize: compact ? 12 : 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Details section for vertical card
  Widget _buildDetailsSection(bool shouldShowClear) {
    return Padding(
      padding: AppDimensions.paddingMD,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Name and Age
          Text(
            age != null ? '$name, $age' : name,
            style: AppTextStyles.heading4,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          // Only show details if image is clear
          if (shouldShowClear) ...[
            if (profession != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(
                    Icons.work_outline,
                    size: AppDimensions.iconSizeXS,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      profession!,
                      style: AppTextStyles.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
            if (location != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(
                    Icons.location_on_outlined,
                    size: AppDimensions.iconSizeXS,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      location!,
                      style: AppTextStyles.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
            if (height != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(
                    Icons.height,
                    size: AppDimensions.iconSizeXS,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    height!,
                    style: AppTextStyles.bodySmall,
                  ),
                ],
              ),
            ],
          ],
          // Action Buttons - always visible
          if (onLike != null || onMessage != null || customActionButton != null) ...[
            const SizedBox(height: 16),
            if (customActionButton != null)
              customActionButton!
            else
              Row(
                children: [
                  if (onLike != null)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onLike,
                        icon: const Icon(Icons.favorite_border, size: AppDimensions.iconSizeSM),
                        label: const Text('Like'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            vertical: AppDimensions.spacingSM,
                          ),
                        ),
                      ),
                    ),
                  if (onLike != null && onMessage != null)
                    const SizedBox(width: 12),
                  if (onMessage != null)
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: onMessage,
                        icon: const Icon(Icons.message, size: AppDimensions.iconSizeSM),
                        label: const Text('Message'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            vertical: AppDimensions.spacingSM,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ],
      ),
    );
  }

  /// Interests section for grid card - only shown when image is clear
  Widget _buildInterestsSection() {
    if (interests == null || interests!.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.spacingSM,
        vertical: AppDimensions.spacingXS,
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: interests!.take(3).map((interest) {
          return Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 4,
            ),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              interest,
              style: AppTextStyles.caption.copyWith(
                color: AppColors.primary,
                fontSize: 11,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// Info section for horizontal card
  Widget _buildHorizontalInfoSection(bool shouldShowClear) {
    return Padding(
      padding: const EdgeInsets.all(AppDimensions.spacingSM),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Only show details if image is clear
          if (shouldShowClear) ...[
            Text(
              'Age ${age ?? '-'} yrs, ${height ?? '-'} cm',
              style: AppTextStyles.captionSmall.copyWith(
                color: AppColors.textSecondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            if (profession != null)
              Row(
                children: [
                  const Icon(Icons.work_outline, size: 13, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      profession!,
                      style: AppTextStyles.captionSmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            if (profession != null) const SizedBox(height: 4),
            if (location != null)
              Row(
                children: [
                  const Icon(Icons.location_on_outlined, size: 13, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      location!,
                      style: AppTextStyles.captionSmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 8),
          ] else ...[
            // When blurred, show minimal info
            const Text(
              'Photo Protected',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
          ],
          // Action button - always visible
          if (customActionButton != null)
            SizedBox(
              height: AppDimensions.buttonHeightSM,
              child: customActionButton,
            ),
        ],
      ),
    );
  }

  /// Badge widget
  Widget _buildBadge({
    required IconData icon,
    required Color color,
    required String label,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: label.isEmpty ? 6 : 8,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppDimensions.radiusSM),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.white),
          if (label.isNotEmpty) ...[
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.white,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Card layout options
enum CardLayout {
  vertical,   // Default vertical card
  grid,       // Grid card with overlay text
  horizontal, // Horizontal carousel card
}
