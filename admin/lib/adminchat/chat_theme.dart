import 'package:flutter/material.dart';

/// Premium design tokens for the chat module, adapting to dark/light mode.
class ChatColors {
  final bool isDark;

  // ── Brand accent (unchanged in both modes) ──────────────────────────────
  final Color primary = const Color(0xFF7B61FF);
  final Color online  = const Color(0xFF22C55E);

  // ── Backgrounds ─────────────────────────────────────────────────────────
  final Color bg;          // main chat area background
  final Color sidebar;     // left/right panel background
  final Color header;      // top bar background
  final Color inputBg;     // message input bar background
  final Color cardBg;      // surface / card background
  final Color searchFill;  // search TextField fill

  // ── Bubbles ──────────────────────────────────────────────────────────────
  final Color sentBubble;      // admin-sent message bubble
  final Color sentBubbleText;
  final Color receivedBubble;  // user-received message bubble
  final Color receivedBubbleText;

  // ── Typography ───────────────────────────────────────────────────────────
  final Color text;    // primary text
  final Color muted;   // secondary / hint text

  // ── Borders / dividers ───────────────────────────────────────────────────
  final Color border;

  // ── Misc brand tints ────────────────────────────────────────────────────
  final Color primaryLight;  // soft pink chip / badge background
  final Color selectedRow;   // selected chat row highlight

  ChatColors._({
    required this.isDark,
    required this.bg,
    required this.sidebar,
    required this.header,
    required this.inputBg,
    required this.cardBg,
    required this.searchFill,
    required this.sentBubble,
    required this.sentBubbleText,
    required this.receivedBubble,
    required this.receivedBubbleText,
    required this.text,
    required this.muted,
    required this.border,
    required this.primaryLight,
    required this.selectedRow,
  });

  static final ChatColors _light = ChatColors._(
    isDark: false,
    bg:               const Color(0xFFF5F6FA),
    sidebar:          Colors.white,
    header:           Colors.white,
    inputBg:          Colors.white,
    cardBg:           Colors.white,
    searchFill:       const Color(0xFFF8FAFC),
    sentBubble:       const Color(0xFFDCF8C6),
    sentBubbleText:   const Color(0xFF1A3C2A),
    receivedBubble:   Colors.white,
    receivedBubbleText: const Color(0xFF1E293B),
    text:             const Color(0xFF1E293B),
    muted:            const Color(0xFF64748B),
    border:           const Color(0xFFE2E8F0),
    primaryLight:     const Color(0xFFEDE9FF),
    selectedRow:      const Color(0xFFF3F0FF),
  );

  static final ChatColors _dark = ChatColors._(
    isDark: true,
    bg:               const Color(0xFF1B2330),
    sidebar:          const Color(0xFF1F2B38),
    header:           const Color(0xFF253040),
    inputBg:          const Color(0xFF253040),
    cardBg:           const Color(0xFF243040),
    searchFill:       const Color(0xFF1E2B38),
    sentBubble:       const Color(0xFF1A4B3A),
    sentBubbleText:   const Color(0xFFE9EDEF),
    receivedBubble:   const Color(0xFF2E3A48),
    receivedBubbleText: const Color(0xFFE9EDEF),
    text:             const Color(0xFFE9EDEF),
    muted:            const Color(0xFF8696A0),
    border:           const Color(0xFF304050),
    primaryLight:     const Color(0xFF2D2554),
    selectedRow:      const Color(0xFF221E3F),
  );

  /// Resolve the correct [ChatColors] set for the current [BuildContext].
  static ChatColors of(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return brightness == Brightness.dark ? _dark : _light;
  }
}
