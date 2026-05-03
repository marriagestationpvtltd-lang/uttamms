import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Unified profile card widget for the admin panel chat.
///
/// Design is intentionally kept in parity with the user app shared profile
/// card so profile-card messages look the same in both apps.
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
  static const _accentDark = Color(0xFF880E4F);
  static const _gradient = LinearGradient(
    colors: [Color(0xFFD81B60), Color(0xFFAD1457), Color(0xFF880E4F)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  @override
  Widget build(BuildContext context) {
    // ── Normalize field names ────────────────────────────────────────────
    final String userId = (profileData['userId'] ?? profileData['id'] ?? '')
        .toString();
    final int? userIdInt = int.tryParse(userId);
    final String memberId =
        (profileData['memberId'] ?? profileData['Member ID'] ?? '').toString();
    final String firstName =
        (profileData['firstName'] ?? profileData['first'] ?? '').toString();
    final String lastName =
        (profileData['lastName'] ?? profileData['last'] ?? '').toString();
    final String fullName = [
      firstName,
      lastName,
    ].where((s) => s.isNotEmpty).join(' ').trim();
    final String resolvedName = fullName.isNotEmpty
        ? fullName
        : (profileData['name']?.toString() ?? 'Unknown');
    final String msId = userId.isNotEmpty ? 'MS$userId' : '';
    final String displayName = msId.isNotEmpty
        ? '$resolvedName ($msId)'
        : resolvedName;
    final String? photoUrl =
        (profileData['profileImage']?.toString() ?? '').isNotEmpty
        ? profileData['profileImage'].toString()
        : null;
    final bool isPremiumProfile =
        profileData['isPremium'] == true || profileData['is_paid'] == true;
    final bool isProfileVerified = profileData['isProfileVerified'] == true;

    final int matchPercent =
        int.tryParse(profileData['matchPercent']?.toString() ?? '0') ??
        _parseMatchPctFromBio(profileData['bio']?.toString() ?? '');

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
            _buildTopStrip(userId, isPremiumProfile, isProfileVerified),
            _buildHeroPhoto(
              context: context,
              photoUrl: photoUrl,
              allImages: allImages,
              displayName: displayName,
              userId: userId,
              matchPercent: matchPercent,
              profileData: profileData,
            ),
            _buildInfoSection(profileData, userId, memberId),
            if (allImages.length > 1) ...[
              _buildGalleryStrip(allImages),
              const SizedBox(height: 8),
            ],
            _buildActions(userId, userIdInt, displayName),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  int _parseMatchPctFromBio(String bio) {
    final m = RegExp(r'(\d+(?:\.\d+)?)%').firstMatch(bio);
    return m != null ? (double.tryParse(m.group(1)!)?.round() ?? 0) : 0;
  }

  // ── TOP LABEL STRIP ──────────────────────────────────────────────────

  Widget _buildTopStrip(String userId, bool isPremiumProfile, bool isVerified) {
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
            child: const Icon(
              Icons.favorite_rounded,
              color: Colors.white,
              size: 13,
            ),
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
          if (isPremiumProfile) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFD54F), Color(0xFFFFA000)],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.workspace_premium, size: 10, color: Colors.white),
                  SizedBox(width: 2),
                  Text(
                    'PRO',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
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
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.22),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.white.withOpacity(0.3),
                  width: 0.8,
                ),
              ),
              child: Text(
                'MS$userId',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── HERO PHOTO ───────────────────────────────────────────────────────

  Widget _buildHeroPhoto({
    required BuildContext context,
    required String? photoUrl,
    required List<String> allImages,
    required String displayName,
    required String userId,
    required int matchPercent,
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
                  color: _accentColor,
                  strokeWidth: 2,
                ),
              ),
              errorWidget: (_, __, ___) => Container(
                color: const Color(0xFFF5E6EC),
                alignment: Alignment.center,
                child: Icon(
                  Icons.person_rounded,
                  size: 64,
                  color: _accentColor.withOpacity(0.4),
                ),
              ),
            )
          : Center(
              child: Icon(
                Icons.person_rounded,
                size: 64,
                color: _accentColor.withOpacity(0.4),
              ),
            ),
    );

    return GestureDetector(
      onTap: allImages.isNotEmpty
          ? () {
              _openPhotoViewerDialog(
                context: context,
                images: allImages,
                initialIndex: 0,
              );
            }
          : null,
      child: Stack(
        children: [
          ClipRect(child: photoWidget),
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
                  colors: [Colors.transparent, Colors.black.withOpacity(0.75)],
                ),
              ),
            ),
          ),
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
                              offset: Offset(0, 1),
                            ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (hasAge) _photoBadge(Icons.cake_outlined, '$ageStr yrs'),
                    if (hasLocation)
                      _photoBadge(
                        Icons.location_on_outlined,
                        _truncate(location, 18),
                      ),
                    if (matchPercent > 0) _matchBadge(matchPercent),
                  ],
                ),
              ],
            ),
          ),
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
                    const Icon(
                      Icons.photo_library_outlined,
                      color: Colors.white,
                      size: 12,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${allImages.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.25), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 11),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.85),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.favorite_rounded, size: 11, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            '$pct% Match',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  // ── INFO SECTION ─────────────────────────────────────────────────────

  Widget _buildInfoSection(
    Map<String, dynamic> data,
    String userId,
    String memberId,
  ) {
    final String pId = userId.isNotEmpty ? userId : memberId;
    final String location = (data['location'] ?? data['country'] ?? '')
        .toString();
    final String marital = (data['maritalStatus'] ?? data['marit'] ?? '')
        .toString();

    final infoItems = <_InfoItem>[
      if (pId.isNotEmpty) _InfoItem(Icons.badge_rounded, 'Member ID', 'MS$pId'),
      if (_hasValue(data['gender']))
        _InfoItem(Icons.wc_rounded, 'Gender', data['gender'].toString()),
      if (_hasValue(location))
        _InfoItem(Icons.location_on_rounded, 'Location', location),
      if (_hasValue(data['age']))
        _InfoItem(Icons.cake_rounded, 'Age', '${data['age']} yrs'),
      if (_hasValue(data['occupation']))
        _InfoItem(
          Icons.work_rounded,
          'Occupation',
          data['occupation'].toString(),
        ),
      if (_hasValue(data['education']))
        _InfoItem(
          Icons.school_rounded,
          'Education',
          data['education'].toString(),
        ),
      if (_hasValue(marital))
        _InfoItem(Icons.favorite_border_rounded, 'Marital', marital),
      if (_hasValue(data['height']))
        _InfoItem(Icons.height_rounded, 'Height', data['height'].toString()),
      if (_hasValue(data['religion']))
        _InfoItem(
          Icons.menu_book_rounded,
          'Religion',
          data['religion'].toString(),
        ),
      if (_hasValue(data['community']))
        _InfoItem(
          Icons.groups_rounded,
          'Community',
          data['community'].toString(),
        ),
    ];

    if (infoItems.isEmpty) return const SizedBox(height: 12);

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
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: 14,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [_accentColor, _accentDark],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  'Profile Details',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A2E),
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  children: leftItems
                      .map((item) => _buildInfoChip(item))
                      .toList(),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  children: rightItems
                      .map((item) => _buildInfoChip(item))
                      .toList(),
                ),
              ),
            ],
          ),
          _buildBioRow(data),
        ],
      ),
    );
  }

  Widget _buildInfoChip(_InfoItem item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 5),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: _accentColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _accentColor.withOpacity(0.14), width: 0.8),
      ),
      child: Row(
        children: [
          Icon(item.icon, size: 11, color: _accentColor),
          const SizedBox(width: 5),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.label,
                  style: const TextStyle(
                    fontSize: 9,
                    color: Color(0xFF90A4AE),
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
                Text(
                  item.value,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF1A2340),
                    fontWeight: FontWeight.w700,
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
    final showBio =
        bio.isNotEmpty &&
        bio != 'No bio available' &&
        !RegExp(r'^\d+(\.\d+)?%').hasMatch(bio);
    if (!showBio) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF0F4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _accentColor.withOpacity(0.15), width: 0.8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.format_quote_rounded,
            size: 14,
            color: _accentColor.withOpacity(0.5),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              bio,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade600,
                fontStyle: FontStyle.italic,
                height: 1.4,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ── GALLERY STRIP ───────────────────────────────────────────────────

  Widget _buildGalleryStrip(List<String> images) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: 14,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [_accentColor, _accentDark],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'Gallery (${images.length} photos)',
                  style: const TextStyle(
                    fontSize: 12,
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
                    _openPhotoViewerDialog(
                      context: context,
                      images: images,
                      initialIndex: index,
                    );
                  },
                  child: Container(
                    width: 64,
                    height: 64,
                    margin: EdgeInsets.only(
                      right: index == images.length - 1 ? 0 : 8,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _accentColor.withOpacity(0.25),
                        width: 1.5,
                      ),
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
                      child: CachedNetworkImage(
                        imageUrl: images[index],
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(
                          color: const Color(0xFFF5E6EC),
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.image,
                            size: 22,
                            color: _accentColor.withOpacity(0.4),
                          ),
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

  // ── ACTION BUTTONS ──────────────────────────────────────────────────

  Widget _buildActions(String userId, int? userIdInt, String displayName) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: _buildActionButton(
              label: 'Chat',
              icon: Icons.chat_bubble_rounded,
              filled: true,
              onPressed: () {
                if (userIdInt != null) {
                  onChat?.call(userIdInt, displayName);
                }
              },
            ),
          ),
          const SizedBox(width: 10),
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
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: Colors.white, size: 15),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

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
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: _accentColor, size: 15),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: const TextStyle(
                    color: _accentColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openPhotoViewerDialog({
    required BuildContext? context,
    required List<String> images,
    required int initialIndex,
  }) {
    if (context == null || images.isEmpty) return;
    showDialog(
      context: context,
      builder: (_) =>
          _AdminGalleryViewerDialog(urls: images, initialIndex: initialIndex),
    );
  }

  String _truncate(String s, int max) =>
      s.length > max ? '${s.substring(0, max)}…' : s;

  bool _hasValue(dynamic val) {
    if (val == null) return false;
    final s = val.toString().trim();
    return s.isNotEmpty &&
        s != 'N/A' &&
        s != 'null' &&
        s != 'Not specified' &&
        s != 'Location not specified' &&
        s != '0';
  }
}

class _InfoItem {
  final IconData icon;
  final String label;
  final String value;
  const _InfoItem(this.icon, this.label, this.value);
}

class _AdminGalleryViewerDialog extends StatefulWidget {
  final List<String> urls;
  final int initialIndex;

  const _AdminGalleryViewerDialog({required this.urls, this.initialIndex = 0});

  @override
  State<_AdminGalleryViewerDialog> createState() =>
      _AdminGalleryViewerDialogState();
}

class _AdminGalleryViewerDialogState extends State<_AdminGalleryViewerDialog> {
  late final PageController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.urls.length - 1);
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.all(18),
      child: SizedBox(
        width: 680,
        height: 560,
        child: Stack(
          children: [
            PageView.builder(
              controller: _controller,
              itemCount: widget.urls.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (_, i) => InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Center(
                  child: CachedNetworkImage(
                    imageUrl: widget.urls[i],
                    fit: BoxFit.contain,
                    errorWidget: (_, __, ___) => const Icon(
                      Icons.broken_image,
                      color: Colors.white54,
                      size: 44,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 10,
              left: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(
                  '${_index + 1}/${widget.urls.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
