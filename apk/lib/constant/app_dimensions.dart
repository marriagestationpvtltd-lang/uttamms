// Responsive Design Utilities
import 'package:flutter/material.dart';

class AppDimensions {
  // Screen dimensions
  static late double screenWidth;
  static late double screenHeight;
  static late double statusBarHeight;
  static late double bottomBarHeight;

  // Safe area dimensions
  static late double safeWidth;
  static late double safeHeight;

  // Initialize dimensions
  static void init(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    screenWidth = mediaQuery.size.width;
    screenHeight = mediaQuery.size.height;
    statusBarHeight = mediaQuery.padding.top;
    bottomBarHeight = mediaQuery.padding.bottom;
    safeWidth = screenWidth;
    safeHeight = screenHeight - statusBarHeight - bottomBarHeight;
  }

  // Responsive width
  static double width(double percentage) {
    return screenWidth * (percentage / 100);
  }

  // Responsive height
  static double height(double percentage) {
    return screenHeight * (percentage / 100);
  }

  // Responsive font size
  static double fontSize(double size) {
    return size * (screenWidth / 375); // Based on iPhone X width
  }

  // Spacing
  static const double spacingXS = 4;
  static const double spacingSM = 8;
  static const double spacingMD = 16;
  static const double spacingLG = 24;
  static const double spacingXL = 32;
  static const double spacingXXL = 48;

  // Padding
  static const EdgeInsets paddingXS = EdgeInsets.all(spacingXS);
  static const EdgeInsets paddingSM = EdgeInsets.all(spacingSM);
  static const EdgeInsets paddingMD = EdgeInsets.all(spacingMD);
  static const EdgeInsets paddingLG = EdgeInsets.all(spacingLG);
  static const EdgeInsets paddingXL = EdgeInsets.all(spacingXL);

  // Horizontal Padding
  static const EdgeInsets paddingHorizontalXS = EdgeInsets.symmetric(horizontal: spacingXS);
  static const EdgeInsets paddingHorizontalSM = EdgeInsets.symmetric(horizontal: spacingSM);
  static const EdgeInsets paddingHorizontalMD = EdgeInsets.symmetric(horizontal: spacingMD);
  static const EdgeInsets paddingHorizontalLG = EdgeInsets.symmetric(horizontal: spacingLG);
  static const EdgeInsets paddingHorizontalXL = EdgeInsets.symmetric(horizontal: spacingXL);

  // Vertical Padding
  static const EdgeInsets paddingVerticalXS = EdgeInsets.symmetric(vertical: spacingXS);
  static const EdgeInsets paddingVerticalSM = EdgeInsets.symmetric(vertical: spacingSM);
  static const EdgeInsets paddingVerticalMD = EdgeInsets.symmetric(vertical: spacingMD);
  static const EdgeInsets paddingVerticalLG = EdgeInsets.symmetric(vertical: spacingLG);
  static const EdgeInsets paddingVerticalXL = EdgeInsets.symmetric(vertical: spacingXL);

  // Border Radius
  static const double radiusXS = 4;
  static const double radiusSM = 8;
  static const double radiusMD = 12;
  static const double radiusLG = 16;
  static const double radiusXL = 20;
  static const double radiusRound = 999;

  // Border Radius Circular
  static const BorderRadius borderRadiusXS = BorderRadius.all(Radius.circular(radiusXS));
  static const BorderRadius borderRadiusSM = BorderRadius.all(Radius.circular(radiusSM));
  static const BorderRadius borderRadiusMD = BorderRadius.all(Radius.circular(radiusMD));
  static const BorderRadius borderRadiusLG = BorderRadius.all(Radius.circular(radiusLG));
  static const BorderRadius borderRadiusXL = BorderRadius.all(Radius.circular(radiusXL));
  static const BorderRadius borderRadiusRound = BorderRadius.all(Radius.circular(radiusRound));

  // Icon Sizes
  static const double iconSizeXS = 16;
  static const double iconSizeSM = 20;
  static const double iconSizeMD = 24;
  static const double iconSizeLG = 32;
  static const double iconSizeXL = 40;
  static const double iconSizeXXL = 48;

  // Button Sizes
  static const double buttonHeightSM = 40;
  static const double buttonHeightMD = 48;
  static const double buttonHeightLG = 52;
  static const double buttonHeightXL = 56;

  // Elevation
  static const double elevationXS = 1;
  static const double elevationSM = 2;
  static const double elevationMD = 4;
  static const double elevationLG = 8;
  static const double elevationXL = 16;
}

// SizedBox helpers
class AppSpacing {
  static const SizedBox verticalXS = SizedBox(height: AppDimensions.spacingXS);
  static const SizedBox verticalSM = SizedBox(height: AppDimensions.spacingSM);
  static const SizedBox verticalMD = SizedBox(height: AppDimensions.spacingMD);
  static const SizedBox verticalLG = SizedBox(height: AppDimensions.spacingLG);
  static const SizedBox verticalXL = SizedBox(height: AppDimensions.spacingXL);
  static const SizedBox verticalXXL = SizedBox(height: AppDimensions.spacingXXL);

  static const SizedBox horizontalXS = SizedBox(width: AppDimensions.spacingXS);
  static const SizedBox horizontalSM = SizedBox(width: AppDimensions.spacingSM);
  static const SizedBox horizontalMD = SizedBox(width: AppDimensions.spacingMD);
  static const SizedBox horizontalLG = SizedBox(width: AppDimensions.spacingLG);
  static const SizedBox horizontalXL = SizedBox(width: AppDimensions.spacingXL);
  static const SizedBox horizontalXXL = SizedBox(width: AppDimensions.spacingXXL);
}

// Screen Size Breakpoints
class ScreenSize {
  static bool isSmallScreen(BuildContext context) {
    return MediaQuery.of(context).size.width < 600;
  }

  static bool isMediumScreen(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return width >= 600 && width < 1024;
  }

  static bool isLargeScreen(BuildContext context) {
    return MediaQuery.of(context).size.width >= 1024;
  }

  static bool isPortrait(BuildContext context) {
    return MediaQuery.of(context).orientation == Orientation.portrait;
  }

  static bool isLandscape(BuildContext context) {
    return MediaQuery.of(context).orientation == Orientation.landscape;
  }
}

// Responsive Widget
class ResponsiveWidget extends StatelessWidget {
  final Widget mobile;
  final Widget? tablet;
  final Widget? desktop;

  const ResponsiveWidget({
    super.key,
    required this.mobile,
    this.tablet,
    this.desktop,
  });

  @override
  Widget build(BuildContext context) {
    if (ScreenSize.isLargeScreen(context)) {
      return desktop ?? tablet ?? mobile;
    } else if (ScreenSize.isMediumScreen(context)) {
      return tablet ?? mobile;
    } else {
      return mobile;
    }
  }
}
