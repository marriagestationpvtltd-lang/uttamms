// Professional Reusable Button Widgets
import 'package:flutter/material.dart';
import '../constant/app_colors.dart';
import '../constant/app_dimensions.dart';
import '../constant/app_text_styles.dart';

// Primary Button with gradient and elevation
class PrimaryButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;
  final double? width;
  final double? height;
  final double? fontSize;

  const PrimaryButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
    this.icon,
    this.width,
    this.height,
    this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width ?? double.infinity,
      height: height ?? AppDimensions.buttonHeightMD,
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: AppDimensions.borderRadiusMD,
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isLoading ? null : onPressed,
          borderRadius: AppDimensions.borderRadiusMD,
          child: Center(
            child: isLoading
                ? const SizedBox(
                    height: AppDimensions.iconSizeMD,
                    width: AppDimensions.iconSizeMD,
                    child: CircularProgressIndicator(
                      color: AppColors.white,
                      strokeWidth: 2,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icon != null) ...[
                        Icon(icon, color: AppColors.white, size: AppDimensions.iconSizeSM),
                        AppSpacing.horizontalSM,
                      ],
                      Text(
                        text,
                        style: AppTextStyles.whiteLabel.copyWith(fontSize: fontSize),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

// Secondary Button with outline
class SecondaryButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;
  final double? width;
  final double? height;
  final double? fontSize;

  const SecondaryButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
    this.icon,
    this.width,
    this.height,
    this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width ?? double.infinity,
      height: height ?? AppDimensions.buttonHeightMD,
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: AppDimensions.borderRadiusMD,
        border: Border.all(color: AppColors.primary, width: 1.5),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isLoading ? null : onPressed,
          borderRadius: AppDimensions.borderRadiusMD,
          child: Center(
            child: isLoading
                ? const SizedBox(
                    height: AppDimensions.iconSizeMD,
                    width: AppDimensions.iconSizeMD,
                    child: CircularProgressIndicator(
                      color: AppColors.primary,
                      strokeWidth: 2,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icon != null) ...[
                        Icon(icon, color: AppColors.primary, size: AppDimensions.iconSizeSM),
                        AppSpacing.horizontalSM,
                      ],
                      Text(
                        text,
                        style: AppTextStyles.labelLarge.copyWith(
                          color: AppColors.primary,
                          fontSize: fontSize,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

// Icon Button with circular design
class IconButtonPrimary extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final double? size;
  final Color? color;
  final Color? backgroundColor;

  const IconButtonPrimary({
    super.key,
    required this.icon,
    this.onPressed,
    this.size,
    this.color,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: Padding(
            padding: EdgeInsets.all(size != null ? size! / 3 : AppDimensions.spacingMD),
            child: Icon(
              icon,
              size: size ?? AppDimensions.iconSizeMD,
              color: color ?? AppColors.white,
            ),
          ),
        ),
      ),
    );
  }
}

// Small Button
class SmallButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isPrimary;
  final IconData? icon;

  const SmallButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isPrimary = true,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.spacingMD,
        vertical: AppDimensions.spacingSM,
      ),
      decoration: BoxDecoration(
        color: isPrimary ? AppColors.primary : AppColors.white,
        borderRadius: AppDimensions.borderRadiusSM,
        border: isPrimary ? null : Border.all(color: AppColors.primary, width: 1.5),
      ),
      child: InkWell(
        onTap: onPressed,
        borderRadius: AppDimensions.borderRadiusSM,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: AppDimensions.iconSizeXS,
                color: isPrimary ? AppColors.white : AppColors.primary,
              ),
              AppSpacing.horizontalSM,
            ],
            Text(
              text,
              style: AppTextStyles.labelMedium.copyWith(
                color: isPrimary ? AppColors.white : AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Social Button (for Google, Facebook, etc.)
class SocialButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final String? iconAsset;
  final IconData? icon;
  final Color? backgroundColor;
  final Color? textColor;

  const SocialButton({
    super.key,
    required this.text,
    this.onPressed,
    this.iconAsset,
    this.icon,
    this.backgroundColor,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: AppDimensions.buttonHeightMD,
      decoration: BoxDecoration(
        color: backgroundColor ?? AppColors.white,
        borderRadius: AppDimensions.borderRadiusMD,
        border: Border.all(color: AppColors.border, width: 1),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: AppDimensions.borderRadiusMD,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spacingMD),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (iconAsset != null)
                  Image.asset(iconAsset!, height: AppDimensions.iconSizeMD, width: AppDimensions.iconSizeMD)
                else if (icon != null)
                  Icon(icon, size: AppDimensions.iconSizeMD, color: textColor),
                AppSpacing.horizontalSM,
                Text(
                  text,
                  style: AppTextStyles.labelLarge.copyWith(
                    color: textColor ?? AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Floating Action Button
class FABPrimary extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final bool isExtended;
  final String? label;

  const FABPrimary({
    super.key,
    required this.icon,
    this.onPressed,
    this.isExtended = false,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    if (isExtended && label != null) {
      return FloatingActionButton.extended(
        onPressed: onPressed,
        backgroundColor: AppColors.primary,
        elevation: AppDimensions.elevationMD,
        icon: Icon(icon, color: AppColors.white),
        label: Text(
          label!,
          style: AppTextStyles.whiteLabel,
        ),
      );
    }

    return FloatingActionButton(
      onPressed: onPressed,
      backgroundColor: AppColors.primary,
      elevation: AppDimensions.elevationMD,
      child: Icon(icon, color: AppColors.white),
    );
  }
}
