// ─── Centralized Design Tokens & ThemeData Builder ───────────────────────────
// Single source of truth for every colour, radius and shadow used in the app.
// Import this file instead of redefining tokens in every screen.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ─── Colour palette ───────────────────────────────────────────────────────────

const kPrimary      = Color(0xFF6366F1); // indigo-500
const kPrimaryDark  = Color(0xFF4F46E5); // indigo-600
const kViolet       = Color(0xFF8B5CF6); // violet-500
const kEmerald      = Color(0xFF10B981); // emerald-500
const kAmber        = Color(0xFFF59E0B); // amber-500
const kRose         = Color(0xFFEF4444); // rose-500
const kSky          = Color(0xFF0EA5E9); // sky-500
const kPink         = Color(0xFFEC4899); // pink-500

// Neutral / surface
const kSidebarBg    = Color(0xFF0F172A); // slate-900
const kContentBg    = Color(0xFFF1F5F9); // slate-100
const kSurface      = Colors.white;

// Text
const kTextPrimary   = Color(0xFF0F172A); // slate-900
const kTextSecondary = Color(0xFF475569); // slate-600
const kTextMuted     = Color(0xFF94A3B8); // slate-400
const kSlate700      = Color(0xFF334155);
const kSlate500      = Color(0xFF64748B);

// Border / outline
const kBorder        = Color(0xFFE2E8F0); // slate-200
const kBorderDark    = Color(0xFF1E293B); // slate-800

// ─── ThemeData builder ────────────────────────────────────────────────────────

ThemeData buildLightTheme() {
  final base = ThemeData(
    brightness: Brightness.light,
    primarySwatch: Colors.indigo,
    scaffoldBackgroundColor: kContentBg,
    colorScheme: const ColorScheme.light(
      primary: kPrimary,
      surface: kSurface,
      onSurface: kSlate700,
      outlineVariant: kBorder,
      error: kRose,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: kSurface,
      foregroundColor: kTextPrimary,
      elevation: 0,
      centerTitle: true,
    ),
  );
  return base.copyWith(
    textTheme: GoogleFonts.poppinsTextTheme(base.textTheme),
  );
}

ThemeData buildDarkTheme() {
  final base = ThemeData(
    brightness: Brightness.dark,
    primarySwatch: Colors.indigo,
    scaffoldBackgroundColor: const Color(0xFF0D1117),
    colorScheme: const ColorScheme.dark(
      primary: kPrimary,
      surface: kBorderDark,
      onSurface: Color(0xFFCBD5E1),
      outlineVariant: Color(0xFF334155),
      error: kRose,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: kBorderDark,
      foregroundColor: Color(0xFFCBD5E1),
      elevation: 0,
      centerTitle: true,
    ),
  );
  return base.copyWith(
    textTheme: GoogleFonts.poppinsTextTheme(base.textTheme),
  );
}

// ─── Shared card decoration ───────────────────────────────────────────────────
BoxDecoration kCardDecoration({
  Color? bg,
  Color? borderColor,
  double radius = 14,
  List<BoxShadow>? shadows,
}) {
  return BoxDecoration(
    color: bg ?? kSurface,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: borderColor ?? kBorder, width: 1),
    boxShadow: shadows ?? [
      const BoxShadow(color: Color(0x08000000), blurRadius: 12, offset: Offset(0, 4)),
    ],
  );
}

// ─── Gradient presets ─────────────────────────────────────────────────────────
const kGradientPrimary = LinearGradient(
  colors: [Color(0xFF4F46E5), Color(0xFF6366F1), Color(0xFF818CF8)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

const kGradientEmerald = LinearGradient(
  colors: [Color(0xFF059669), Color(0xFF10B981)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

const kGradientAmber = LinearGradient(
  colors: [Color(0xFFD97706), Color(0xFFF59E0B)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

const kGradientRose = LinearGradient(
  colors: [Color(0xFFDC2626), Color(0xFFEF4444)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

const kGradientSky = LinearGradient(
  colors: [Color(0xFF0284C7), Color(0xFF0EA5E9)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

const kGradientViolet = LinearGradient(
  colors: [Color(0xFF7C3AED), Color(0xFF8B5CF6)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);
