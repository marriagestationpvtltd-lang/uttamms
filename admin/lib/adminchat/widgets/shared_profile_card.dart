import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Unified profile card widget for the admin panel chat.
///
/// Admin always has full access — shows clear photo, all info, gallery.
/// Design matches the user-app [SharedProfileCard] for visual consistency.
class AdminSharedProfileCard extends StatelessWidget {
  final Map<String, dynamic> profileData;

  /// Called when the Profile button is tapped.
  final void Function(String userId)? onViewProfile;

  /// Called when the Chat button is tapped (e.g. switch active chat).
  final void Function(int userId, String displayName)? onChat;

  const AdminSharedProfileCard({
    super.key,
    required this.profileData,
    this.onViewProfile,
    this.onChat,
  });

  static const _accentColor = Color(0xFFD81B60);
  static const _gradient = LinearGradient(
    colors: [Color(0xFFD81B60), Color(0xFFAD1457), Color(0xFF880E4F)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  @override
  Widget build(BuildContext context) {
    // ── Normalize field names ──────────────────────────────────────────────
    final String userId = (profileData['userId'] ?? profileData['id'] ?? '')
        .toString();
    final int? userIdInt = int.tryParse(userId);
    final String lastName =
        (profileData['lastName'] ?? profileData['last'] ?? '').toString();
    final String displayName = lastName.isNotEmpty
        ? lastName
        : (profileData['name']?.toString() ?? 'Unknown');
    final String memberId =
        (profileData['memberId'] ?? profileData['Member ID'] ?? '').toString();
    final String? photoUrl =
        (profileData['profileImage']?.toString() ?? '').isNotEmpty
        ? profileData['profileImage'].toString()
        : null;
    final bool isPremiumProfile =
        profileData['isPremium'] == true || profileData['is_paid'] == true;
    final bool isProfileVerified = profileData['isProfileVerified'] == true;

    int matchPercent = 0;
    final rawPct = profileData['matchPercent'];
    if (rawPct != null) {
      matchPercent = (rawPct is num) ? rawPct.round() : 0;
    } else {
      final bio = profileData['bio']?.toString() ?? '';
      final m = RegExp(r'(\d+(?:\.\d+)?)%').firstMatch(bio);
      if (m != null) matchPercent = double.tryParse(m.group(1)!)?.round() ?? 0;
    }

    // Gallery
    final List<String> galleryImages = [];
    final rawGallery = profileData['galleryImages'];
    if (rawGallery is List) {
      for (final item in rawGallery) {
        final url = item?.toString() ?? '';
        if (url.isNotEmpty) galleryImages.add(url);
      }
    }
    final List<String> allImages = [
      if (photoUrl != null) photoUrl,
      ...galleryImages.where((u) => u != photoUrl),
    ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _accentColor.withOpacity(0.12),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(userId, memberId, isPremiumProfile, isProfileVerified),
            _buildPhotoAndName(
              photoUrl: photoUrl,
              allImages: allImages,
              displayName: displayName,
              matchPercent: matchPercent,
              profileData: profileData,
            ),
            _buildInfoRows(profileData),
            Divider(height: 1, color: Colors.grey.shade200),
            _buildActions(userId, userIdInt, displayName),
          ],
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────

  Widget _buildHeader(
    String userId,
    String memberId,
    bool isPremiumProfile,
    bool isVerified,
  ) {
    return Container(
      height: 56,
      decoration: const BoxDecoration(gradient: _gradient),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Icon(
            Icons.person_pin_rounded,
            color: Colors.white.withOpacity(0.8),
            size: 14,
          ),
          const SizedBox(width: 5),
          const Text(
            'Profile Shared',
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
          if (isPremiumProfile) ...[
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFD54F), Color(0xFFFFA000)],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.workspace_premium, size: 8, color: Colors.white),
                  SizedBox(width: 2),
                  Text(
                    'Premium',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 7.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (isVerified) ...[
            const SizedBox(width: 4),
            const Icon(
              Icons.verified_rounded,
              size: 13,
              color: Color(0xFF64B5F6),
            ),
          ],
          const Spacer(),
          if (userId.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.25),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                memberId.isNotEmpty ? memberId : '#$userId',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Photo + name ──────────────────────────────────────────────────────

  Widget _buildPhotoAndName({
    required String? photoUrl,
    required List<String> allImages,
    required String displayName,
    required int matchPercent,
    required Map<String, dynamic> profileData,
  }) {
    final bool hasPhoto = photoUrl != null && photoUrl.isNotEmpty;

    Color matchColor;
    if (matchPercent >= 70) {
      matchColor = const Color(0xFF43A047);
    } else if (matchPercent >= 50) {
      matchColor = const Color(0xFFFB8C00);
    } else {
      matchColor = Colors.grey.shade500;
    }

    Widget photoWidget = Container(
      width: 54,
      height: 54,
      color: const Color(0xFFF8BBD9),
      child: hasPhoto
          ? CachedNetworkImage(
              imageUrl: photoUrl,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => const Icon(
                Icons.person_rounded,
                size: 28,
                color: _accentColor,
              ),
            )
          : const Icon(Icons.person_rounded, size: 28, color: _accentColor),
    );

    return Transform.translate(
      offset: const Offset(0, -28),
      child: Column(
        children: [
          Center(
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                if (matchPercent > 0)
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: matchColor, width: 2.5),
                    ),
                  ),
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.12),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: ClipOval(child: photoWidget),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            displayName,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A2340),
              letterSpacing: 0.1,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (matchPercent > 0) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: matchColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: matchColor.withOpacity(0.35),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.favorite_rounded, size: 9, color: matchColor),
                  const SizedBox(width: 3),
                  Text(
                    '$matchPercent% Match',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: matchColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Info rows ─────────────────────────────────────────────────────────

  Widget _buildInfoRows(Map<String, dynamic> data) {
    const kLabel = Color(0xFF78909C);
    const kValue = Color(0xFF1A2340);

    final String pId = (data['userId'] ?? data['id'] ?? '').toString();
    final String memberId = (data['memberId'] ?? data['Member ID'] ?? '')
        .toString();
    final String location = (data['location'] ?? data['country'] ?? '')
        .toString();
    final String marital = (data['maritalStatus'] ?? data['marit'] ?? '')
        .toString();

    return Transform.translate(
      offset: const Offset(0, -20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          children: [
            if (memberId.isNotEmpty)
              _row(Icons.badge_rounded, 'Member ID', memberId, kLabel, kValue)
            else if (pId.isNotEmpty)
              _row(Icons.badge_rounded, 'Member ID', '#$pId', kLabel, kValue),
            if (_v(data['gender']))
              _row(
                Icons.wc_rounded,
                'Gender',
                data['gender'].toString(),
                kLabel,
                kValue,
              ),
            if (_v(location))
              _row(
                Icons.location_on_rounded,
                'Location',
                location,
                kLabel,
                kValue,
              ),
            if (_v(data['age']))
              _row(
                Icons.cake_rounded,
                'Age',
                '${data['age']} years',
                kLabel,
                kValue,
              ),
            if (_v(data['occupation']))
              _row(
                Icons.work_rounded,
                'Occupation',
                data['occupation'].toString(),
                kLabel,
                kValue,
              ),
            if (_v(data['education']))
              _row(
                Icons.school_rounded,
                'Education',
                data['education'].toString(),
                kLabel,
                kValue,
              ),
            if (_v(marital))
              _row(
                Icons.favorite_border_rounded,
                'Marital',
                marital,
                kLabel,
                kValue,
              ),
            if (_v(data['height']))
              _row(
                Icons.height_rounded,
                'Height',
                data['height'].toString(),
                kLabel,
                kValue,
              ),
            if (_v(data['religion']))
              _row(
                Icons.menu_book_rounded,
                'Religion',
                data['religion'].toString(),
                kLabel,
                kValue,
              ),
            if (_v(data['community']))
              _row(
                Icons.groups_rounded,
                'Community',
                data['community'].toString(),
                kLabel,
                kValue,
              ),
          ],
        ),
      ),
    );
  }

  Widget _row(
    IconData icon,
    String label,
    String value,
    Color labelColor,
    Color valueColor,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 3),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _accentColor.withOpacity(0.04),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _accentColor.withOpacity(0.12), width: 0.8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 10, color: _accentColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 9.5,
              color: labelColor,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 9.5,
                color: valueColor,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ── Action buttons ────────────────────────────────────────────────────

  Widget _buildActions(String userId, int? userIdInt, String displayName) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => onViewProfile?.call(userId),
              child: Container(
                height: 30,
                decoration: BoxDecoration(
                  border: Border.all(color: _accentColor, width: 1.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.open_in_new_rounded,
                      size: 11,
                      color: _accentColor,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'Profile',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: _accentColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: GestureDetector(
              onTap: () {
                if (userIdInt != null) {
                  onChat?.call(userIdInt, displayName);
                }
              },
              child: Container(
                height: 30,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFD81B60), Color(0xFFAD1457)],
                  ),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: _accentColor.withOpacity(0.3),
                      blurRadius: 5,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.chat_bubble_rounded,
                      size: 11,
                      color: Colors.white,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'Chat',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _v(dynamic val) {
    if (val == null) return false;
    final s = val.toString().trim();
    return s.isNotEmpty &&
        s != 'N/A' &&
        s != 'null' &&
        s != 'Not specified' &&
        s != 'Location not specified' &&
        s != '0' &&
        s != 'false';
  }
}
