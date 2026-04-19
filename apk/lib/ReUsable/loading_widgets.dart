// Professional Loading and Error Widgets
import 'package:flutter/material.dart';
import '../constant/app_colors.dart';
import '../constant/app_dimensions.dart';
import '../constant/app_text_styles.dart';

// Loading Widget
class LoadingWidget extends StatelessWidget {
  final String? message;
  final double? size;

  const LoadingWidget({
    super.key,
    this.message,
    this.size,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: size ?? 40,
            height: size ?? 40,
            child: const CircularProgressIndicator(
              color: AppColors.primary,
              strokeWidth: 3,
            ),
          ),
          if (message != null) ...[
            AppSpacing.verticalMD,
            Text(
              message!,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// Circular Loading Indicator
class CircularLoading extends StatelessWidget {
  final Color? color;
  final double? size;

  const CircularLoading({
    super.key,
    this.color,
    this.size,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size ?? 24,
      height: size ?? 24,
      child: CircularProgressIndicator(
        color: color ?? AppColors.primary,
        strokeWidth: 2,
      ),
    );
  }
}

// Empty State Widget
class EmptyStateWidget extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? buttonText;
  final VoidCallback? onButtonPressed;

  const EmptyStateWidget({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.buttonText,
    this.onButtonPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: AppDimensions.paddingLG,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: AppDimensions.iconSizeXXL * 2,
              color: AppColors.textHint,
            ),
            AppSpacing.verticalLG,
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTextStyles.heading3,
            ),
            if (subtitle != null) ...[
              AppSpacing.verticalSM,
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
            if (buttonText != null && onButtonPressed != null) ...[
              AppSpacing.verticalLG,
              ElevatedButton(
                onPressed: onButtonPressed,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDimensions.spacingXL,
                    vertical: AppDimensions.spacingMD,
                  ),
                ),
                child: Text(buttonText!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// Error Widget
class ErrorStateWidget extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? errorMessage;
  final VoidCallback? onRetry;
  final String? retryButtonText;

  const ErrorStateWidget({
    super.key,
    required this.title,
    this.subtitle,
    this.errorMessage,
    this.onRetry,
    this.retryButtonText,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: AppDimensions.paddingLG,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: AppDimensions.iconSizeXXL * 2,
              color: AppColors.error,
            ),
            AppSpacing.verticalLG,
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTextStyles.heading3,
            ),
            if (subtitle != null) ...[
              AppSpacing.verticalSM,
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
            if (errorMessage != null) ...[
              AppSpacing.verticalSM,
              Container(
                padding: AppDimensions.paddingMD,
                decoration: BoxDecoration(
                  color: AppColors.error.withOpacity(0.1),
                  borderRadius: AppDimensions.borderRadiusMD,
                ),
                child: Text(
                  errorMessage!,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.error,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
            if (onRetry != null) ...[
              AppSpacing.verticalLG,
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(retryButtonText ?? 'Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDimensions.spacingXL,
                    vertical: AppDimensions.spacingMD,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// Success Message Widget
class SuccessMessageWidget extends StatelessWidget {
  final String message;
  final VoidCallback? onClose;

  const SuccessMessageWidget({
    super.key,
    required this.message,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: AppDimensions.paddingMD,
      padding: AppDimensions.paddingMD,
      decoration: BoxDecoration(
        color: AppColors.success,
        borderRadius: AppDimensions.borderRadiusMD,
        boxShadow: [
          BoxShadow(
            color: AppColors.success.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_rounded,
            color: AppColors.white,
            size: AppDimensions.iconSizeLG,
          ),
          AppSpacing.horizontalMD,
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.whiteBody.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (onClose != null) ...[
            AppSpacing.horizontalSM,
            IconButton(
              icon: const Icon(Icons.close, color: AppColors.white),
              onPressed: onClose,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ],
      ),
    );
  }
}

// Warning Message Widget
class WarningMessageWidget extends StatelessWidget {
  final String message;
  final VoidCallback? onClose;

  const WarningMessageWidget({
    super.key,
    required this.message,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: AppDimensions.paddingMD,
      padding: AppDimensions.paddingMD,
      decoration: BoxDecoration(
        color: AppColors.warning,
        borderRadius: AppDimensions.borderRadiusMD,
        boxShadow: [
          BoxShadow(
            color: AppColors.warning.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_rounded,
            color: AppColors.white,
            size: AppDimensions.iconSizeLG,
          ),
          AppSpacing.horizontalMD,
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.whiteBody.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (onClose != null) ...[
            AppSpacing.horizontalSM,
            IconButton(
              icon: const Icon(Icons.close, color: AppColors.white),
              onPressed: onClose,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Skeleton shape primitives ──────────────────────────────────────────────

/// A grey rounded rectangle placeholder used inside skeleton screens.
class _SkeletonBox extends StatelessWidget {
  final double width;
  final double height;
  final double radius;

  const _SkeletonBox({
    required this.width,
    required this.height,
    this.radius = 6,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.borderLight,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// A circular grey placeholder (for avatars / profile pictures).
class _SkeletonCircle extends StatelessWidget {
  final double size;

  const _SkeletonCircle({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: AppColors.borderLight,
        shape: BoxShape.circle,
      ),
    );
  }
}

// ── Section-specific skeleton screens ─────────────────────────────────────

/// Skeleton for a horizontal profile card (190 × 270).
/// Used in HomeScreen's Matched Profiles and Recent Members sections.
class ProfileCardSkeleton extends StatelessWidget {
  const ProfileCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerLoading(
      isLoading: true,
      child: Container(
        width: 190,
        margin: const EdgeInsets.only(right: 14),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
              child: const _SkeletonBox(width: 190, height: 155, radius: 0),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SkeletonBox(width: 120, height: 12),
                  const SizedBox(height: 6),
                  const _SkeletonBox(width: 80, height: 10),
                  const SizedBox(height: 6),
                  const _SkeletonBox(width: 100, height: 10),
                  const SizedBox(height: 10),
                  const _SkeletonBox(width: 160, height: 32, radius: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Horizontal list of [ProfileCardSkeleton] cards.
class ProfileCardListSkeleton extends StatelessWidget {
  final int count;
  final double height;

  const ProfileCardListSkeleton({
    super.key,
    this.count = 3,
    this.height = 270,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.only(left: 16, right: 8),
        itemCount: count,
        itemBuilder: (_, __) => const ProfileCardSkeleton(),
      ),
    );
  }
}

/// Skeleton for a horizontal shortlist card (140 × 180).
class ShortlistCardSkeleton extends StatelessWidget {
  const ShortlistCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerLoading(
      isLoading: true,
      child: Container(
        width: 140,
        height: 180,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: AppColors.borderLight,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  _SkeletonBox(width: 90, height: 11),
                  SizedBox(height: 5),
                  _SkeletonBox(width: 60, height: 9),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Horizontal list of [ShortlistCardSkeleton] cards.
class ShortlistCardListSkeleton extends StatelessWidget {
  final int count;

  const ShortlistCardListSkeleton({super.key, this.count = 3});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 180,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.only(left: 16, right: 8),
        itemCount: count,
        itemBuilder: (_, __) => const ShortlistCardSkeleton(),
      ),
    );
  }
}

/// Skeleton for a single chat list row.
class ChatListItemSkeleton extends StatelessWidget {
  const ChatListItemSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerLoading(
      isLoading: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            const _SkeletonCircle(size: 52),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  _SkeletonBox(width: 130, height: 13),
                  SizedBox(height: 6),
                  _SkeletonBox(width: 200, height: 11),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: const [
                _SkeletonBox(width: 36, height: 10),
                SizedBox(height: 6),
                _SkeletonCircle(size: 18),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Multiple [ChatListItemSkeleton] rows for a full chat list loading state.
class ChatListSkeleton extends StatelessWidget {
  final int count;

  const ChatListSkeleton({super.key, this.count = 7});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(count, (_) => const ChatListItemSkeleton()),
    );
  }
}

/// Skeleton for a 2-column profile grid card (Search recommended profiles).
class SearchProfileCardSkeleton extends StatelessWidget {
  const SearchProfileCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerLoading(
      isLoading: true,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(14),
                  topRight: Radius.circular(14),
                ),
                child: Container(
                  width: double.infinity,
                  color: AppColors.borderLight,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  _SkeletonBox(width: 90, height: 12),
                  SizedBox(height: 5),
                  _SkeletonBox(width: 60, height: 10),
                  SizedBox(height: 5),
                  _SkeletonBox(width: 100, height: 10),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A 2-column grid of [SearchProfileCardSkeleton] items.
class SearchProfileGridSkeleton extends StatelessWidget {
  final int count;

  const SearchProfileGridSkeleton({super.key, this.count = 4});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: count,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.65,
      ),
      itemBuilder: (_, __) => const SearchProfileCardSkeleton(),
    );
  }
}

/// Skeleton for a single service/offer card row.
class ServiceCardSkeleton extends StatelessWidget {
  const ServiceCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerLoading(
      isLoading: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            const _SkeletonBox(width: 56, height: 56, radius: 12),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  _SkeletonBox(width: 140, height: 13),
                  SizedBox(height: 6),
                  _SkeletonBox(width: 200, height: 11),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// List of [ServiceCardSkeleton] rows.
class ServiceListSkeleton extends StatelessWidget {
  final int count;

  const ServiceListSkeleton({super.key, this.count = 3});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(count, (_) => const ServiceCardSkeleton()),
    );
  }
}

// Shimmer Loading Effect (for skeleton screens)
class ShimmerLoading extends StatefulWidget {
  final Widget child;
  final bool isLoading;

  const ShimmerLoading({
    super.key,
    required this.child,
    required this.isLoading,
  });

  @override
  State<ShimmerLoading> createState() => _ShimmerLoadingState();
}

class _ShimmerLoadingState extends State<ShimmerLoading>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isLoading) {
      return widget.child;
    }

    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              colors: const [
                AppColors.borderLight,
                AppColors.white,
                AppColors.borderLight,
              ],
              stops: [
                _controller.value - 0.3,
                _controller.value,
                _controller.value + 0.3,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ).createShader(bounds);
          },
          child: child,
        );
      },
    );
  }
}
