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
  static const _accentDark = Color(0xFF880E4F);
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
            color: _accentColor.withOpacity(0.18),
            blurRadius: 24,
            spreadRadius: 0,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── TOP LABEL STRIP ───────────────────────────────────────────
            _buildTopStrip(userId, isPremiumProfile, isProfileVerified),
            // ── HERO PHOTO ────────────────────────────────────────────────
            _buildHeroPhoto(
              photoUrl: photoUrl,
              allImages: allImages,
              displayName: displayName,
              showClearPhoto: showClearPhoto,
              matchPercent: matchPercent,
              userId: userId,
              photoRequest: photoRequest,
              isVerified: isProfileVerified,
              isPremium: isPremiumProfile,
              profileData: profileData,
            ),
            // ── INFO SECTION ──────────────────────────────────────────────
            _buildInfoSection(profileData, userId, memberId, matchPercent),
            // ── GALLERY STRIP ─────────────────────────────────────────────
            if (allImages.length > 1) ...[
              _buildGalleryStrip(
                  allImages, showClearPhoto, userId, photoRequest),
              const SizedBox(height: 8),
            ],
            // ── ACTION BUTTONS ────────────────────────────────────────────
            _buildActions(userId, displayName),
            const SizedBox(height: 4),
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

    if (sharedBy == 'admin' || canViewPhotoInPayload) {
      return _AccessLevel.full;
    }
    return _AccessLevel.limited;
  }

  int _parseMatchPctFromBio(String bio) {
    final m = RegExp(r'(\d+(?:\.\d+)?)%').firstMatch(bio);
    return m != null ? (double.tryParse(m.group(1)!)?.round() ?? 0) : 0;
  }

  // ── TOP LABEL STRIP ────────────────────────────────────────────────────

  Widget _buildTopStrip(String userId, bool isPremium, bool isVerified) {
    return Container(
      height: 44,
      decoration: const BoxDecoration(gradient: _gradient),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.18),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.favorite_rounded,
                color: Colors.white, size: 13),
          ),
          const SizedBox(width: 8),
          const Text(
            'Profile Card',
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
          if (isPremium) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFFFFD54F), Color(0xFFFFA000)]),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.workspace_premium, size: 10, color: Colors.white),
                  SizedBox(width: 2),
                  Text('PRO',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5)),
                ],
              ),
            ),
          ],
          if (isVerified) ...[
            const SizedBox(width: 4),
            const Icon(Icons.verified_rounded,
                size: 15, color: Color(0xFF64B5F6)),
          ],
          const Spacer(),
          if (userId.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.22),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: Colors.white.withOpacity(0.3), width: 0.8),
              ),
              child: Text(
                'MS$userId',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3),
              ),
            ),
        ],
      ),
    );
  }

  // ── HERO PHOTO ─────────────────────────────────────────────────────────

  Widget _buildHeroPhoto({
    required String? photoUrl,
    required List<String> allImages,
    required String displayName,
    required bool showClearPhoto,
    required int matchPercent,
    required String userId,
    required String photoRequest,
    required bool isVerified,
    required bool isPremium,
    required Map<String, dynamic> profileData,
  }) {
    final bool hasPhoto = photoUrl != null && photoUrl.isNotEmpty;
    final String ageStr = profileData['age']?.toString() ?? '';
    final String location =
        (profileData['location'] ?? profileData['country'] ?? '').toString();
    final bool hasAge = _hasValue(ageStr) && ageStr != '0';
    final bool hasLocation = _hasValue(location);

    Widget photoWidget = Container(
      width: double.infinity,
      height: 210,
      color: const Color(0xFFF5E6EC),
      child: hasPhoto
          ? CachedNetworkImage(
              imageUrl: photoUrl,
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(
                color: const Color(0xFFF5E6EC),
                alignment: Alignment.center,
                child: const CircularProgressIndicator(
                    color: _accentColor, strokeWidth: 2),
              ),
              errorWidget: (_, __, ___) => Container(
                color: const Color(0xFFF5E6EC),
                alignment: Alignment.center,
                child: Icon(Icons.person_rounded,
                    size: 64, color: _accentColor.withOpacity(0.4)),
              ),
            )
          : Center(
              child: Icon(Icons.person_rounded,
                  size: 64, color: _accentColor.withOpacity(0.4)),
            ),
    );

    if (!showClearPhoto) {
      photoWidget = ImageFiltered(
        imageFilter: ImageFilter.blur(
          sigmaX: PrivacyUtils.kStandardBlurSigmaX,
          sigmaY: PrivacyUtils.kStandardBlurSigmaY,
        ),
        child: photoWidget,
      );
    }

    return GestureDetector(
      onTap: allImages.isNotEmpty
          ? () {
              if (!showClearPhoto) {
                onPrivatePhotoTap?.call(userId, photoRequest);
              } else {
                onOpenPhotoViewer?.call(allImages, 0);
              }
            }
          : null,
      child: Stack(
        children: [
          // Photo
          ClipRect(child: photoWidget),

          // Bottom gradient overlay
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 120,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.75),
                  ],
                ),
              ),
            ),
          ),

          // Name + meta on photo bottom
          Positioned(
            bottom: 12,
            left: 14,
            right: 14,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        displayName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.2,
                          shadows: [
                            Shadow(
                                color: Colors.black54,
                                blurRadius: 4,
                                offset: Offset(0, 1))
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isVerified) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.verified_rounded,
                          color: Color(0xFF64B5F6), size: 18),
                    ],
                  ],
                ),
                const SizedBox(height: 5),
              ],
            ),
          ),

          // Lock overlay when blurred
          if (!showClearPhoto)
            Positioned.fill(
              child: Container(
                alignment: Alignment.center,
                color: Colors.transparent,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.45),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.2)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock_rounded,
                          color: Colors.white.withOpacity(0.9), size: 26),
                      const SizedBox(height: 6),
                      Text(
                        'Photo Protected',
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.95),
                            fontSize: 13,
                            fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Tap to request access',
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.7), fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Photo count badge top-right
          if (allImages.length > 1)
            Positioned(
              top: 10,
              right: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.photo_library_outlined,
                        color: Colors.white, size: 12),
                    const SizedBox(width: 4),
                    Text(
                      '${allImages.length}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _photoBadge(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4.5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.25), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white, size: 12),
          const SizedBox(width: 5),
          Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  height: 1.2)),
        ],
      ),
    );
  }

  Widget _matchBadge(int pct) {
    Color color;
    if (pct >= 70) {
      color = const Color(0xFF43A047);
    } else if (pct >= 50) {
      color = const Color(0xFFFB8C00);
    } else {
      color = Colors.grey.shade500;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4.5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.85),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(Icons.favorite_rounded, size: 12, color: Colors.white),
          const SizedBox(width: 5),
          Text(
            '$pct% Match',
            style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                height: 1.2),
          ),
        ],
      ),
    );
  }

  // ── INFO SECTION ───────────────────────────────────────────────────────

  Widget _buildInfoSection(Map<String, dynamic> data, String userId,
      String memberId, int matchPercent) {
    final String pId = userId.isNotEmpty ? userId : memberId;
    final String location =
        (data['location'] ?? data['country'] ?? '').toString();
    final String marital =
        (data['maritalStatus'] ?? data['marit'] ?? '').toString();

    final infoItems = <_InfoItem>[
      if (pId.isNotEmpty) _InfoItem(Icons.badge_rounded, 'Member ID', 'MS$pId'),
      if (_hasValue(data['age']))
        _InfoItem(Icons.cake_rounded, 'Age', '${data['age']} years'),
      if (_hasValue(location))
        _InfoItem(Icons.location_on_rounded, 'Location', location),
      if (matchPercent > 0)
        _InfoItem(Icons.favorite_rounded, 'Match', '$matchPercent%'),
      if (_hasValue(data['gender']))
        _InfoItem(Icons.wc_rounded, 'Gender', data['gender'].toString()),
      if (_hasValue(data['occupation']))
        _InfoItem(
            Icons.work_rounded, 'Occupation', data['occupation'].toString()),
      if (_hasValue(data['education']))
        _InfoItem(
            Icons.school_rounded, 'Education', data['education'].toString()),
      if (_hasValue(marital))
        _InfoItem(Icons.favorite_border_rounded, 'Marital', marital),
      if (_hasValue(data['height']))
        _InfoItem(Icons.height_rounded, 'Height', data['height'].toString()),
      if (_hasValue(data['religion']))
        _InfoItem(
            Icons.menu_book_rounded, 'Religion', data['religion'].toString()),
      if (_hasValue(data['community']))
        _InfoItem(
            Icons.groups_rounded, 'Community', data['community'].toString()),
    ];

    if (infoItems.isEmpty) return const SizedBox(height: 12);

    // Show in a clean 2-column chip grid
    final leftItems = <_InfoItem>[];
    final rightItems = <_InfoItem>[];
    for (var i = 0; i < infoItems.length; i++) {
      if (i.isEven) {
        leftItems.add(infoItems[i]);
      } else {
        rightItems.add(infoItems[i]);
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section title
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 3,
                  height: 16,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [_accentColor, _accentDark],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Profile Details',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A2E),
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
          // Two-column info rows
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children:
                      leftItems.map((item) => _buildInfoChip(item)).toList(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children:
                      rightItems.map((item) => _buildInfoChip(item)).toList(),
                ),
              ),
            ],
          ),
          // Bio (if available)
          _buildBioRow(data),
        ],
      ),
    );
  }

  Widget _buildInfoChip(_InfoItem item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: _accentColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _accentColor.withOpacity(0.14), width: 0.8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(item.icon, size: 13, color: _accentColor),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.label,
                  style: const TextStyle(
                    fontSize: 8.5,
                    color: Color(0xFF90A4AE),
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.value,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFF1A2340),
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBioRow(Map<String, dynamic> data) {
    final bio = data['bio']?.toString() ?? '';
    final showBio = bio.isNotEmpty &&
        bio != 'No bio available' &&
        !RegExp(r'^\d+(\.\d+)?%').hasMatch(bio);
    if (!showBio) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF0F4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _accentColor.withOpacity(0.15), width: 0.8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1.5),
            child: Icon(Icons.format_quote_rounded,
                size: 16, color: _accentColor.withOpacity(0.4)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              bio,
              style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade700,
                  fontStyle: FontStyle.italic,
                  height: 1.5),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ── GALLERY STRIP ──────────────────────────────────────────────────────

  Widget _buildGalleryStrip(
    List<String> images,
    bool showClearPhoto,
    String userId,
    String photoRequest,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 3,
                  height: 16,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [_accentColor, _accentDark],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Gallery (${images.length} photos)',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A2E),
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 70,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: images.length,
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
                    width: 64,
                    height: 64,
                    margin: EdgeInsets.only(
                        right: index == images.length - 1 ? 0 : 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: _accentColor.withOpacity(0.25), width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.06),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child: showClearPhoto
                          ? CachedNetworkImage(
                              imageUrl: images[index],
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => Container(
                                color: const Color(0xFFF5E6EC),
                                alignment: Alignment.center,
                                child: Icon(Icons.image,
                                    size: 22,
                                    color: _accentColor.withOpacity(0.4)),
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
                                    Container(color: const Color(0xFFF5E6EC)),
                              ),
                            ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── ACTION BUTTONS ─────────────────────────────────────────────────────

  Widget _buildActions(String userId, String displayName) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: _buildActionButton(
              label: 'Chat',
              icon: Icons.chat_bubble_rounded,
              filled: true,
              onPressed: () => onChat?.call(userId, displayName),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildActionButton(
              label: 'View Profile',
              icon: Icons.person_rounded,
              filled: false,
              onPressed: () => onViewProfile?.call(userId),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required bool filled,
    required VoidCallback? onPressed,
  }) {
    if (filled) {
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFD81B60), Color(0xFF880E4F)],
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: _accentColor.withOpacity(0.35),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(icon, color: Colors.white, size: 16),
                  const SizedBox(width: 7),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                      letterSpacing: 0.2,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    } else {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _accentColor.withOpacity(0.4), width: 1.2),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(icon, color: _accentColor, size: 16),
                  const SizedBox(width: 7),
                  Text(
                    label,
                    style: const TextStyle(
                      color: _accentColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                      letterSpacing: 0.2,
                      height: 1.2,
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

  // ── Helpers ───────────────────────────────────────────────────────────

  String _truncate(String s, int max) =>
      s.length > max ? '${s.substring(0, max)}…' : s;

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

class _InfoItem {
  final IconData icon;
  final String label;
  final String value;
  const _InfoItem(this.icon, this.label, this.value);
}

enum _AccessLevel { full, limited, minimal }
