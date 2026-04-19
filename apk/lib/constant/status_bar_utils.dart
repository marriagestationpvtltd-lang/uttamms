import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Returns a [SystemUiOverlayStyle] that sets the status bar [color] and
/// icon [brightness].  Wrap your screen's [Scaffold] (or the topmost widget)
/// with [AnnotatedRegion<SystemUiOverlayStyle>] and pass the result of this
/// function as the value to control the status bar per-screen.
///
/// Example:
/// ```dart
/// AnnotatedRegion<SystemUiOverlayStyle>(
///   value: setStatusBar(Colors.white, Brightness.dark),
///   child: Scaffold(...),
/// )
/// ```
SystemUiOverlayStyle setStatusBar(Color color, Brightness iconBrightness) {
  return SystemUiOverlayStyle(
    statusBarColor: color,
    statusBarIconBrightness: iconBrightness, // Android
    // iOS uses statusBarBrightness (opposite semantics to iconBrightness)
    statusBarBrightness: iconBrightness == Brightness.dark
        ? Brightness.light
        : Brightness.dark,
    systemStatusBarContrastEnforced: false,
  );
}

/// Calculates the relative luminance of a color using the WCAG formula.
/// Returns a value between 0 (darkest) and 1 (lightest).
///
/// This follows the WCAG 2.0 specification for relative luminance calculation:
/// https://www.w3.org/TR/WCAG20/#relativeluminancedef
double _calculateLuminance(Color color) {
  // Convert sRGB color components to linear RGB
  double toLinear(double component) {
    if (component <= 0.03928) {
      return component / 12.92;
    }
    return ((component + 0.055) / 1.055).toDouble() *
           ((component + 0.055) / 1.055).toDouble();
  }

  final r = toLinear(color.red / 255.0);
  final g = toLinear(color.green / 255.0);
  final b = toLinear(color.blue / 255.0);

  // Calculate relative luminance
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

/// Determines the appropriate status bar icon brightness based on background color.
///
/// Uses WCAG relative luminance calculation to determine if light or dark
/// icons should be used for optimal contrast.
///
/// - Returns [Brightness.light] for dark backgrounds (light icons)
/// - Returns [Brightness.dark] for light backgrounds (dark icons)
///
/// Example:
/// ```dart
/// final brightness = getStatusBarBrightness(Colors.red);
/// final style = setStatusBar(Colors.transparent, brightness);
/// ```
Brightness getStatusBarBrightness(Color backgroundColor) {
  final luminance = _calculateLuminance(backgroundColor);

  // If luminance is greater than 0.5, background is light, use dark icons
  // If luminance is less than or equal to 0.5, background is dark, use light icons
  return luminance > 0.5 ? Brightness.dark : Brightness.light;
}

/// Returns a [SystemUiOverlayStyle] with automatic icon brightness detection.
///
/// Automatically determines whether to use light or dark icons based on the
/// background color's luminance for optimal contrast.
///
/// Example:
/// ```dart
/// AnnotatedRegion<SystemUiOverlayStyle>(
///   value: setStatusBarAuto(AppColors.primary),
///   child: Scaffold(...),
/// )
/// ```
SystemUiOverlayStyle setStatusBarAuto(Color backgroundColor) {
  final iconBrightness = getStatusBarBrightness(backgroundColor);
  return setStatusBar(backgroundColor, iconBrightness);
}
