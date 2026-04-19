/// Responsive layout utilities for Marriage Station web + mobile.
///
/// Usage:
///   ```dart
///   if (ResponsiveLayout.isMobile(context)) { ... }
///
///   ResponsiveLayout(
///     mobile: MobileView(),
///     tablet: TabletView(),      // optional – falls back to mobile
///     desktop: DesktopView(),    // optional – falls back to tablet → mobile
///   )
///   ```
library responsive_layout;

import 'package:flutter/material.dart';

/// Breakpoints (logical pixels).
class Breakpoints {
  Breakpoints._();
  static const double mobile = 600;
  static const double tablet = 1024;
}

/// Utility methods for querying the current layout size.
class ResponsiveLayout extends StatelessWidget {
  const ResponsiveLayout({
    super.key,
    required this.mobile,
    this.tablet,
    this.desktop,
  });

  final Widget mobile;
  final Widget? tablet;
  final Widget? desktop;

  // ── Helpers ──────────────────────────────────────────────────────────────

  static bool isMobile(BuildContext context) =>
      MediaQuery.sizeOf(context).width < Breakpoints.mobile;

  static bool isTablet(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return w >= Breakpoints.mobile && w < Breakpoints.tablet;
  }

  static bool isDesktop(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= Breakpoints.tablet;

  static bool isWideLayout(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= Breakpoints.mobile;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= Breakpoints.tablet) {
      return desktop ?? tablet ?? mobile;
    }
    if (width >= Breakpoints.mobile) {
      return tablet ?? mobile;
    }
    return mobile;
  }
}

/// A simple centered-container wrapper that constrains the content to
/// [maxWidth] on wide screens (web/desktop), while filling the screen on
/// mobile.
class ResponsiveContainer extends StatelessWidget {
  const ResponsiveContainer({
    super.key,
    required this.child,
    this.maxWidth = 960,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

/// Two-panel layout (like WhatsApp Web): a fixed-width [sidebar] on the left
/// and an [expandable] panel that fills the remaining space.
/// Falls back to showing only [expandable] (or [sidebar] if [expandable] is
/// null) on narrow screens.
class TwoPanelLayout extends StatelessWidget {
  const TwoPanelLayout({
    super.key,
    required this.sidebar,
    required this.body,
    this.sidebarWidth = 380,
    this.showSidebarOnly = false,
  });

  final Widget sidebar;
  final Widget body;
  final double sidebarWidth;

  /// When true the sidebar is shown full-width (used on mobile when no chat
  /// is selected).
  final bool showSidebarOnly;

  @override
  Widget build(BuildContext context) {
    if (!ResponsiveLayout.isWideLayout(context)) {
      // Mobile: show only one panel at a time
      return showSidebarOnly ? sidebar : body;
    }

    // Wide layout: side-by-side
    return Row(
      children: [
        SizedBox(width: sidebarWidth, child: sidebar),
        const VerticalDivider(width: 1, thickness: 1),
        Expanded(child: body),
      ],
    );
  }
}
