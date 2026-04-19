// matched_profile_card.dart
// Reusable Flutter widgets for the horizontal matched-profiles UI.
// Usage:
// import 'matched_profile_card.dart';
//
// MatchedProfilesList(
//   profiles: yourListOfMaps,
//   onSendRequest: (profile) { /* handle send request */ },
// )

import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:ms2026/constant/app_colors.dart';
import 'package:ms2026/constant/app_dimensions.dart';
import 'package:ms2026/utils/privacy_utils.dart';

typedef SendRequestCallback = void Function(Map<String, dynamic> profile);

// ─── Matched Profiles Horizontal List ───────────────────────────────────────

class MatchedProfilesList extends StatelessWidget {
  final List<Map<String, dynamic>> profiles;
  final SendRequestCallback? onSendRequest;
  final EdgeInsetsGeometry padding;

  const MatchedProfilesList({
    Key? key,
    required this.profiles,
    this.onSendRequest,
    this.padding = const EdgeInsets.only(left: AppDimensions.spacingMD),
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Derive card width responsively: ~42% of screen, clamped between 140–190
    final double screenWidth = MediaQuery.of(context).size.width;
    final double cardWidth = (screenWidth * 0.42).clamp(140.0, 190.0);
    final double listHeight = cardWidth * 1.52; // ~3:2 portrait ratio

    return SizedBox(
      height: listHeight,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: profiles.length,
        padding: padding,
        itemBuilder: (context, index) {
          final profile = profiles[index];
          return Padding(
            padding: const EdgeInsets.only(right: AppDimensions.spacingSM),
            child: SizedBox(
              width: cardWidth,
              child: MatchedProfileCard(
                profile: profile,
                onSendRequest: () => onSendRequest?.call(profile),
                currentStatus: profile['request_status']?.toString(),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── Single Matched Profile Card ─────────────────────────────────────────────

class MatchedProfileCard extends StatelessWidget {
  final Map<String, dynamic> profile;
  final VoidCallback? onSendRequest;
  final String? currentStatus; // null | 'loading' | 'pending' | 'sent' | 'error'

  const MatchedProfileCard({
    Key? key,
    required this.profile,
    this.onSendRequest,
    this.currentStatus,
  }) : super(key: key);

  String _str(dynamic v) => (v ?? '').toString();

  @override
  Widget build(BuildContext context) {
    final name = _str(profile['firstName']).isNotEmpty
        ? _str(profile['firstName'])
        : (_str(profile['name']).isNotEmpty ? _str(profile['name']) : 'Name');
    final age = _str(profile['age']);
    final height = _str(profile['height_name'] ?? profile['height']);
    final profession =
        _str(profile['designation'] ?? profile['profession']);
    final location = _str(
      profile['city'] != null
          ? (profile['city'] as String) +
              (profile['country'] != null
                  ? ', ${profile['country']}'
                  : '')
          : (profile['location'] ?? ''),
    );
    final imageUrl = _str(profile['profile_picture'] ?? profile['image']);

    final privacy = _str(profile['privacy']);
    final photoRequest = _str(profile['photo_request']);
    final canViewPhoto = profile['can_view_photo'] as bool?;
    final shouldShowClear = PrivacyUtils.shouldShowClearImage(
      privacy: privacy,
      photoRequest: photoRequest,
      canViewPhoto: canViewPhoto,
    );

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppDimensions.radiusLG),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.10),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppDimensions.radiusLG),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── Background: profile image (or placeholder) ───────────
            _buildImage(imageUrl, shouldShowClear),

            // ── Gradient scrim (bottom 55%) ──────────────────────────
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.38, 0.65, 1.0],
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.40),
                      Colors.black.withOpacity(0.82),
                    ],
                  ),
                ),
              ),
            ),

            // ── Lock overlay for private photos ──────────────────────
            if (!shouldShowClear)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withOpacity(0.44),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.12),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: Colors.white.withOpacity(0.35)),
                        ),
                        child: const Icon(Icons.lock_outline_rounded,
                            size: 20, color: Colors.white),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        PrivacyUtils.getPhotoRequestStatusLabel(photoRequest),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),

            // ── Bottom info + button ─────────────────────────────────
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Name
                    Text(
                      name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.1,
                        shadows: [
                          Shadow(color: Colors.black54, blurRadius: 4),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),

                    if (shouldShowClear) ...[
                      const SizedBox(height: 2),
                      // Age / Height row
                      if (age.isNotEmpty || height.isNotEmpty)
                        Text(
                          [
                            if (age.isNotEmpty) '$age yrs',
                            if (height.isNotEmpty) height,
                          ].join(' · '),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),

                      if (profession.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(Icons.work_outline_rounded,
                                size: 10, color: Colors.white60),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                profession,
                                style: const TextStyle(
                                  color: Colors.white60,
                                  fontSize: 10,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],

                      if (location.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(Icons.location_on_outlined,
                                size: 10, color: Colors.white60),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                location,
                                style: const TextStyle(
                                  color: Colors.white60,
                                  fontSize: 10,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],

                    const SizedBox(height: 8),

                    // Send Request button
                    _buildStatusButton(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImage(String imageUrl, bool shouldShowClear) {
    Widget img;
    if (imageUrl.isNotEmpty) {
      final raw = Image.network(
        imageUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder(),
      );
      img = shouldShowClear
          ? raw
          : ImageFiltered(
              imageFilter: ui.ImageFilter.blur(
                sigmaX: PrivacyUtils.kStandardBlurSigmaX,
                sigmaY: PrivacyUtils.kStandardBlurSigmaY,
              ),
              child: raw,
            );
    } else {
      img = _placeholder();
    }
    return img;
  }

  Widget _placeholder() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFE5E5), Color(0xFFFFCDD2)],
        ),
      ),
      child: const Center(
        child: Icon(Icons.person_outline_rounded,
            size: 48, color: AppColors.primary),
      ),
    );
  }

  Widget _buildStatusButton() {
    final status = (currentStatus ?? '').toLowerCase();

    String label;
    bool enabled;
    IconData icon;

    switch (status) {
      case 'loading':
        label = 'Sending…';
        enabled = false;
        icon = Icons.send_rounded;
        break;
      case 'pending':
        label = 'Pending';
        enabled = false;
        icon = Icons.hourglass_top_rounded;
        break;
      case 'sent':
        label = 'Sent ✓';
        enabled = false;
        icon = Icons.check_circle_outline_rounded;
        break;
      case 'error':
        label = 'Retry';
        enabled = true;
        icon = Icons.refresh_rounded;
        break;
      default:
        label = 'Connect';
        enabled = true;
        icon = Icons.person_add_alt_1_rounded;
    }

    final Color bg = enabled ? AppColors.primary : Colors.white.withOpacity(0.20);
    final Color fg = Colors.white;

    return SizedBox(
      height: 30,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppDimensions.radiusRound),
          onTap: enabled ? onSendRequest : null,
          child: Ink(
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(AppDimensions.radiusRound),
              boxShadow: enabled
                  ? [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.4),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : null,
            ),
            child: Center(
              child: status == 'loading'
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            const AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icon, size: 12, color: fg),
                        const SizedBox(width: 5),
                        Text(
                          label,
                          style: TextStyle(
                            color: fg,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
