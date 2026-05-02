import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/user_state.dart';
import '../utils/privacy_utils.dart';

/// Unified profile card widget for chat messages.
///
/// Access tiers (for user viewers):
///   - Admin viewer (`isAdminViewer=true`): always full
///   - Premium + Verified: full (clear photo + all info + gallery)
///   - Premium + Not Verified: limited (blurred photo + basic info)
///   - Free member: minimal (blurred photo + name + upgrade prompt)
class SharedProfileCard extends StatelessWidget {
  final Map<String, dynamic> profileData;

  /// True when the current viewer is an admin (always full access).
  final bool isAdminViewer;

  /// Called to open a fullscreen photo viewer.
  final void Function(List<String> images, int index)? onOpenPhotoViewer;

  /// Called when the viewer taps a private/blurred photo.
  final void Function(String userId, String photoRequest)? onPrivatePhotoTap;

  /// Called when the Chat button is tapped.
  final void Function(String userId, String displayName)? onChat;

  /// Called when the View Profile button is tapped.
  final void Function(String userId)? onViewProfile;

  const SharedProfileCard({
    super.key,
    required this.profileData,
    this.isAdminViewer = false,
    this.onOpenPhotoViewer,
    this.onPrivatePhotoTap,
    this.onChat,
    this.onViewProfile,
  });

  static const _accentColor = Color(0xFFD81B60);
  static const _gradient = LinearGradient(
    colors: [Color(0xFFD81B60), Color(0xFFAD1457), Color(0xFF880E4F)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  @override
  Widget build(BuildContext context) {
    // ── Normalize field names (admin-sent and user-sent formats) ─────────
    final String userId =
        (profileData['userId'] ?? profileData['id'] ?? '').toString();
    final String memberId =
        (profileData['memberId'] ?? profileData['Member ID'] ?? '').toString();
    final String firstName =
        (profileData['firstName'] ?? profileData['first'] ?? '').toString();
    final String lastName =
        (profileData['lastName'] ?? profileData['last'] ?? '').toString();
    final String fullName =
        [firstName, lastName].where((s) => s.isNotEmpty).join(' ').trim();
    final String resolvedName = fullName.isNotEmpty
        ? fullName
        : (profileData['name']?.toString() ?? 'Unknown');
    // Admin sees full name + MS ID; user-side sees only MS ID + last name.
    final String adminId = userId.isNotEmpty ? 'MS$userId' : '';
    final String adminDisplayName =
        adminId.isNotEmpty ? '$resolvedName ($adminId)' : resolvedName;
    final String displayName = isAdminViewer
        ? adminDisplayName
        : _publicIdentity(userId, lastName: lastName);
    final String? photoUrl =
        (profileData['profileImage']?.toString() ?? '').isNotEmpty
            ? profileData['profileImage'].toString()
            : null;
    final bool isPremiumProfile =
        profileData['isPremium'] == true || profileData['is_paid'] == true;
    final bool isProfileVerified = profileData['isProfileVerified'] == true;
    final int matchPercent = int.tryParse(
          profileData['matchPercent']?.toString() ?? '0',
        ) ??
        _parseMatchPctFromBio(profileData['bio']?.toString() ?? '');
    final String sharedBy = profileData['sharedBy']?.toString() ?? 'user';
    final String photoRequest = profileData['photoRequest']?.toString() ?? '';

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

    // ── Viewer access level ───────────────────────────────────────────────
    final _AccessLevel access = _computeAccess(
      context,
      sharedBy: sharedBy,
      canViewPhotoInPayload: profileData['canViewPhoto'] == true ||
          profileData['shouldBlurPhoto'] == false,
    );
    final bool showClearPhoto = access == _AccessLevel.full;

    return Container(
      width: 300,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _accentColor.withOpacity(0.15),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(userId, memberId, isPremiumProfile, isProfileVerified),
            _buildPhotoAndName(
              photoUrl: photoUrl,
              allImages: allImages,
              displayName: displayName,
              profileData: profileData,
              showClearPhoto: showClearPhoto,
              matchPercent: matchPercent,
              userId: userId,
              photoRequest: photoRequest,
            ),
            _buildInfoRows(profileData),
            _buildBioAndGallery(
                profileData, allImages, showClearPhoto, userId, photoRequest),
            Divider(height: 1, color: Colors.grey.shade200),
            _buildActions(userId, displayName),
          ],
        ),
      ),
    );
  }

  String _publicIdentity(String userId, {String? lastName}) {
    final String u = userId.trim();
    final String idPart = u.isEmpty ? 'MS ID' : 'MS$u';
    final String ln = (lastName ?? '').trim();
    if (ln.isEmpty) return idPart;
    return '$idPart $ln';
  }

  // ── Access level computation ──────────────────────────────────────────

  _AccessLevel _computeAccess(
    BuildContext context, {
    required String sharedBy,
    required bool canViewPhotoInPayload,
  }) {
    if (isAdminViewer) return _AccessLevel.full;

    final userState = context.read<UserState>();
    final bool isPremium = userState.hasPackage;
    final bool isVerified = userState.isVerified;

    if (!isPremium) return _AccessLevel.minimal;
    if (!isVerified) return _AccessLevel.limited;

    // Premium + verified: full if admin shared OR backend says can view
    if (sharedBy == 'admin' || canViewPhotoInPayload) {
      return _AccessLevel.full;
    }
    return _AccessLevel.limited;
  }

  int _parseMatchPctFromBio(String bio) {
    final m = RegExp(r'(\d+(?:\.\d+)?)%').firstMatch(bio);
    return m != null ? (double.tryParse(m.group(1)!)?.round() ?? 0) : 0;
  }

  // ── Header ────────────────────────────────────────────────────────────

  Widget _buildHeader(
    String userId,
    String memberId,
    bool isPremiumProfile,
    bool isVerified,
  ) {
    return Container(
      height: 60,
      decoration: const BoxDecoration(gradient: _gradient),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Icon(Icons.favorite, color: Colors.white.withOpacity(0.7), size: 16),
          const SizedBox(width: 6),
          const Text(
            'Profile Card',
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
          if (isPremiumProfile) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFFFFD54F), Color(0xFFFFA000)]),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.workspace_premium, size: 9, color: Colors.white),
                  SizedBox(width: 2),
                  Text('Premium',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ],
          if (isVerified) ...[
            const SizedBox(width: 4),
            const Icon(Icons.verified_rounded,
                size: 14, color: Color(0xFF64B5F6)),
          ],
          const Spacer(),
          if (userId.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.25),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'MS$userId',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    );
  }

  // ── Profile photo + name ──────────────────────────────────────────────

  Widget _buildPhotoAndName({
    required String? photoUrl,
    required List<String> allImages,
    required String displayName,
    required Map<String, dynamic> profileData,
    required bool showClearPhoto,
    required int matchPercent,
    required String userId,
    required String photoRequest,
  }) {
    final bool hasPhoto = photoUrl != null && photoUrl.isNotEmpty;

    Widget photoInner = Container(
      width: 80,
      height: 80,
      color: Colors.grey.shade200,
      child: hasPhoto
          ? CachedNetworkImage(
              imageUrl: photoUrl,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) =>
                  Icon(Icons.person, size: 40, color: Colors.grey.shade400),
            )
          : Icon(Icons.person, size: 40, color: Colors.grey.shade400),
    );

    if (!showClearPhoto) {
      photoInner = ImageFiltered(
        imageFilter: ImageFilter.blur(
          sigmaX: PrivacyUtils.kStandardBlurSigmaX,
          sigmaY: PrivacyUtils.kStandardBlurSigmaY,
        ),
        child: photoInner,
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
      child: Column(
        children: [
          Transform.translate(
            offset: const Offset(0, -30),
            child: Column(
              children: [
                GestureDetector(
                  onTap: allImages.isNotEmpty
                      ? () {
                          if (!showClearPhoto) {
                            onPrivatePhotoTap?.call(userId, photoRequest);
                          } else {
                            onOpenPhotoViewer?.call(allImages, 0);
                          }
                        }
                      : null,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.15),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: ClipOval(child: photoInner),
                  ),
                ),
                const SizedBox(height: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            displayName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Color(0xFF1A1A2E),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: showClearPhoto
                                ? Colors.green.shade100
                                : Colors.orange.shade100,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            showClearPhoto
                                ? Icons.lock_open_outlined
                                : Icons.lock_outline,
                            size: 12,
                            color: showClearPhoto
                                ? Colors.green.shade700
                                : Colors.orange.shade700,
                          ),
                        ),
                      ],
                    ),
                    if (matchPercent > 0) ...[
                      const SizedBox(height: 4),
                      _buildMatchBadge(matchPercent),
                    ],
                    if (_hasValue(profileData['age'])) ...[
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.cake_outlined,
                              size: 13, color: Colors.grey.shade500),
                          const SizedBox(width: 4),
                          Text(
                            '${profileData['age']} years',
                            style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ],
                    if (_hasValue(
                        profileData['location'] ?? profileData['country'])) ...[
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.location_on_outlined,
                              size: 13, color: Colors.grey.shade500),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              (profileData['location'] ??
                                      profileData['country'])
                                  .toString(),
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey.shade500),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMatchBadge(int matchPercent) {
    Color color;
    if (matchPercent >= 70) {
      color = const Color(0xFF43A047);
    } else if (matchPercent >= 50) {
      color = const Color(0xFFFB8C00);
    } else {
      color = Colors.grey.shade500;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.favorite_rounded, size: 10, color: color),
          const SizedBox(width: 3),
          Text(
            '$matchPercent% Match',
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }

  // ── Info rows ─────────────────────────────────────────────────────────

  Widget _buildInfoRows(Map<String, dynamic> data) {
    const kLabel = Color(0xFF78909C);
    const kValue = Color(0xFF1A2340);

    final String pId = (data['userId'] ?? data['id'] ?? '').toString();
    final String memberId =
        (data['memberId'] ?? data['Member ID'] ?? '').toString();
    final String location =
        (data['location'] ?? data['country'] ?? '').toString();
    final String marital =
        (data['maritalStatus'] ?? data['marit'] ?? '').toString();

    final rows = <Widget>[
      if (pId.isNotEmpty)
        _infoRow(Icons.badge_rounded, 'Member ID', 'MS$pId', kLabel, kValue)
      else if (memberId.isNotEmpty)
        _infoRow(Icons.badge_rounded, 'Member ID', memberId, kLabel, kValue),
      if (_hasValue(data['gender']))
        _infoRow(Icons.wc_rounded, 'Gender', data['gender'].toString(), kLabel,
            kValue),
      if (_hasValue(location))
        _infoRow(
            Icons.location_on_rounded, 'Location', location, kLabel, kValue),
      if (_hasValue(data['age']))
        _infoRow(
            Icons.cake_rounded, 'Age', '${data['age']} years', kLabel, kValue),
      if (_hasValue(data['occupation']))
        _infoRow(Icons.work_rounded, 'Occupation',
            data['occupation'].toString(), kLabel, kValue),
      if (_hasValue(data['education']))
        _infoRow(Icons.school_rounded, 'Education',
            data['education'].toString(), kLabel, kValue),
      if (_hasValue(marital))
        _infoRow(
            Icons.favorite_border_rounded, 'Marital', marital, kLabel, kValue),
      if (_hasValue(data['height']))
        _infoRow(Icons.height_rounded, 'Height', data['height'].toString(),
            kLabel, kValue),
      if (_hasValue(data['religion']))
        _infoRow(Icons.menu_book_rounded, 'Religion',
            data['religion'].toString(), kLabel, kValue),
      if (_hasValue(data['community']))
        _infoRow(Icons.groups_rounded, 'Community',
            data['community'].toString(), kLabel, kValue),
    ];

    if (rows.isEmpty) return const SizedBox.shrink();

    return Transform.translate(
      offset: const Offset(0, -22),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Column(children: rows),
      ),
    );
  }

  Widget _infoRow(
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

  // ── Bio + gallery ─────────────────────────────────────────────────────

  Widget _buildBioAndGallery(
    Map<String, dynamic> profileData,
    List<String> allImages,
    bool showClearPhoto,
    String userId,
    String photoRequest,
  ) {
    final bio = profileData['bio']?.toString() ?? '';
    // Don't show "X% Matched" as bio
    final showBio = bio.isNotEmpty &&
        bio != 'No bio available' &&
        !RegExp(r'^\d+(\.\d+)?%').hasMatch(bio);

    return Column(
      children: [
        if (showBio)
          Transform.translate(
            offset: const Offset(0, -14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: _accentColor.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '"$bio"',
                  style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                      fontStyle: FontStyle.italic),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        if (allImages.length > 1)
          Transform.translate(
            offset: Offset(0, showBio ? -10.0 : -14.0),
            child: _buildGalleryStrip(
                allImages, showClearPhoto, userId, photoRequest),
          ),
      ],
    );
  }

  Widget _buildGalleryStrip(
    List<String> images,
    bool showClearPhoto,
    String userId,
    String photoRequest,
  ) {
    return SizedBox(
      height: 56,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: images.length,
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
        itemBuilder: (context, index) {
          return GestureDetector(
            onTap: () {
              if (!showClearPhoto) {
                onPrivatePhotoTap?.call(userId, photoRequest);
              } else {
                onOpenPhotoViewer?.call(images, index);
              }
            },
            child: Container(
              width: 50,
              height: 50,
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: _accentColor.withOpacity(0.3), width: 1.5),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: showClearPhoto
                    ? CachedNetworkImage(
                        imageUrl: images[index],
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(
                          color: Colors.grey.shade200,
                          child: Icon(Icons.image,
                              size: 20, color: Colors.grey.shade400),
                        ),
                      )
                    : ImageFiltered(
                        imageFilter: ImageFilter.blur(
                          sigmaX: PrivacyUtils.kStandardBlurSigmaX,
                          sigmaY: PrivacyUtils.kStandardBlurSigmaY,
                        ),
                        child: CachedNetworkImage(
                          imageUrl: images[index],
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) =>
                              Container(color: Colors.grey.shade200),
                        ),
                      ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Action buttons ────────────────────────────────────────────────────

  Widget _buildActions(String userId, String displayName) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: TextButton.icon(
              onPressed: () => onChat?.call(userId, displayName),
              icon: const Icon(Icons.chat_bubble_outline,
                  size: 16, color: _accentColor),
              label: const Text('Chat',
                  style: TextStyle(
                      color: _accentColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 13)),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 6),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
          Container(width: 1, height: 28, color: Colors.grey.shade200),
          Expanded(
            child: TextButton.icon(
              onPressed: () => onViewProfile?.call(userId),
              icon: const Icon(Icons.person_outline,
                  size: 16, color: _accentColor),
              label: const Text('View Profile',
                  style: TextStyle(
                      color: _accentColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 13)),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 6),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────

  bool _hasValue(dynamic val) {
    if (val == null) return false;
    final s = val.toString().trim();
    return s.isNotEmpty &&
        s != 'N/A' &&
        s != 'null' &&
        s != 'Not specified' &&
        s != 'Location not specified';
  }
}

enum _AccessLevel { full, limited, minimal }
