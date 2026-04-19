import 'dart:async';

import 'package:flutter/material.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import 'package:google_fonts/google_fonts.dart';

import '../Auth/Login/Email.dart';
import '../Auth/Login/LoginMain.dart';
import '../Auth/Screen/Signup.dart';
import '../constant/app_colors.dart';


class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pc = PageController();

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  Widget _buildGetStartedPill() {
    return GestureDetector(
      onTap: (){
        Navigator.push(context, MaterialPageRoute(builder: (context) =>
           // IntroduceYourselfPage(),
        PrefilledEmailScreen()
        ));
      },
      child: Container(
        height: 62,
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(40),
          boxShadow: [
            BoxShadow(
              color: AppColors.shadowLight,
              blurRadius: 8,
              offset: const Offset(0, 4),
            )
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Text(
              'Get Started',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            SizedBox(width: 10),
            CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.primary,
              child: Icon(Icons.arrow_forward, color: AppColors.white, size: 20),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Full gradient used on both pages
    return Scaffold(
      body: Stack(
        children: [
          // PageView
          PageView(
            controller: _pc,
            children: const [
              OnboardPageOne(),
              OnboardPageTwo(),
              OnboardPageThree(),
            ],
          ),

          // Skip button top-right
          Positioned(
            top: MediaQuery.of(context).padding.top + 14,
            right: 18,
            child: TextButton(
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => PrefilledEmailScreen(),));
              },
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 0),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Text(
                  'Skip',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),

          // Page indicator (above pill)
          Positioned(
            left: 0,
            right: 0,
            bottom: 120,
            child: Center(
              child: SmoothPageIndicator(
                controller: _pc,
                count: 3,
                effect: ExpandingDotsEffect(
                  dotHeight: 8,
                  dotWidth: 8,
                  spacing: 8,
                  activeDotColor: AppColors.white,
                  dotColor: AppColors.white.withOpacity(0.38),
                ),
              ),
            ),
          ),

          // Get started pill
          Positioned(
            left: 24,
            right: 24,
            bottom: 36,
            child: _buildGetStartedPill(),
          ),
        ],
      ),
    );
  }
}

/// ---------- Page 1 ----------
class OnboardPageOne extends StatelessWidget {
  const OnboardPageOne({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.primaryDark],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Stack(
        children: [
          // Subtle top-left arc background decoration
          const Positioned(
            left: -140,
            top: -220,
            child: ArcBigCircle(),
          ),

          // Subtle bottom-right arc for balance
          const Positioned(
            right: -160,
            bottom: 160,
            child: ArcBigCircle(),
          ),

          // Clean, centered couple illustration
          const Positioned(
            top: 72,
            left: 0,
            right: 0,
            child: _CoupleIllustration(),
          ),

          // Main textual content anchored at bottom
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                children: [
                  const Spacer(),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Real People, Real Story',
                      style: TextStyle(
                        color: AppColors.white,
                        fontSize: 30,
                        height: 1.02,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'A space where real people connect through genuine conversations and create stories that truly matter.',
                      style: TextStyle(
                        color: AppColors.white.withOpacity(0.9),
                        fontSize: 14,
                        height: 1.6,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 160),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Clean couple illustration: two profile cards with a connecting heart
class _CoupleIllustration extends StatelessWidget {
  const _CoupleIllustration();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Left profile card
          const _ProfileCard(icon: Icons.woman, label: 'Bride'),

          // Heart connector
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppColors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.shadowMedium,
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.favorite,
                color: AppColors.primary,
                size: 26,
              ),
            ),
          ),

          // Right profile card
          const _ProfileCard(icon: Icons.man, label: 'Groom'),
        ],
      ),
    );
  }
}

/// Individual frosted-glass profile card used in the couple illustration
class _ProfileCard extends StatelessWidget {
  final IconData icon;
  final String label;

  const _ProfileCard({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      height: 152,
      decoration: BoxDecoration(
        color: AppColors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: AppColors.white.withOpacity(0.45),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowMedium,
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.white.withOpacity(0.25),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppColors.white, size: 34),
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

/// ---------- Page 2 ----------
class OnboardPageTwo extends StatelessWidget {
  const OnboardPageTwo({super.key});

  static const ImageProvider leftImg =
      AssetImage('assets/images/partner.png');
  static const ImageProvider centerImg =
      AssetImage('assets/images/ms1.jpg');
  static const ImageProvider rightImg =
      AssetImage('assets/images/user1.png');
  static const ImageProvider small1 =
      AssetImage('assets/images/user1.png');
  static const ImageProvider small2 =
      AssetImage('assets/images/partner.png');

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.primaryDark],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Stack(
        children: [
          // top shadowed rounded cards row
          Positioned(
            top: 92,
            left: 24,
            right: 24,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // left small card
                Transform.translate(
                  offset: const Offset(-8, 20),
                  child: RoundedImageCard(
                    image: leftImg,
                    width: 110,
                    height: 170,
                    borderRadius: 18,
                  ),
                ),

                const SizedBox(width: 12),

                // center big card
                RoundedImageCard(
                  image: centerImg,
                  width: 170,
                  height: 260,
                  borderRadius: 18,
                ),

                const SizedBox(width: 12),

                // right small card
                Transform.translate(
                  offset: const Offset(8, 20),
                  child: RoundedImageCard(
                    image: rightImg,
                    width: 110,
                    height: 170,
                    borderRadius: 18,
                  ),
                ),
              ],
            ),
          ),

          // small floating avatars + send icon (center area)
          Positioned(
            left: 110,
            top: 350,
            child: CircleAvatarWithBorder(
              image: small1,
              size: 58,
            ),
          ),
          const Positioned(
            left: 185,
            top: 370,
            child: FloatingIcon(icon: Icons.send),
          ),
          Positioned(
            right: 110,
            top: 350,
            child: CircleAvatarWithBorder(
              image: small2,
              size: 58,
            ),
          ),

          // heart icon near right card
          const Positioned(
            right: 70,
            top: 220,
            child: FloatingIcon(icon: Icons.favorite_border),
          ),

          // Text area at bottom-left
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                children: [
                  const Spacer(flex: 2),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Find Your Kind Of Connection',
                      style: TextStyle(
                        color: AppColors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Find your kind of connection with people who share your vibe, match your energy, and make every conversation feel natural.',
                      style: TextStyle(
                        color: AppColors.white.withOpacity(0.95),
                        fontSize: 14,
                        height: 1.6,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 140),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ---------- Page 3 – Animated column-by-column feature guide ----------

/// Data model for a single feature column shown in the guide
class _FeatureData {
  final IconData icon;
  final String tag;
  final String title;
  final String description;
  final List<_MockField> mockFields;

  const _FeatureData({
    required this.icon,
    required this.tag,
    required this.title,
    required this.description,
    required this.mockFields,
  });
}

/// A single mock field displayed inside the animated preview card
class _MockField {
  final IconData icon;
  final String label;

  const _MockField(this.icon, this.label);
}

class OnboardPageThree extends StatefulWidget {
  const OnboardPageThree({super.key});

  @override
  State<OnboardPageThree> createState() => _OnboardPageThreeState();
}

class _OnboardPageThreeState extends State<OnboardPageThree>
    with TickerProviderStateMixin {
  // Feature columns: each represents a key section of the app
  static const List<_FeatureData> _features = [
    _FeatureData(
      icon: Icons.manage_accounts_rounded,
      tag: 'PROFILE',
      title: 'Complete Your Profile',
      description:
          'Fill in each section — name, age, religion, profession — so the right matches can discover you easily.',
      mockFields: [
        _MockField(Icons.person_outline, 'Full Name'),
        _MockField(Icons.cake_outlined, 'Date of Birth'),
        _MockField(Icons.temple_hindu_outlined, 'Religion'),
        _MockField(Icons.work_outline, 'Profession'),
      ],
    ),
    _FeatureData(
      icon: Icons.tune_rounded,
      tag: 'MATCHING',
      title: 'Smart Match Filters',
      description:
          'Set your preferences column by column — age range, location, caste — and our engine finds the best fits.',
      mockFields: [
        _MockField(Icons.height, 'Age Range'),
        _MockField(Icons.location_on_outlined, 'Location'),
        _MockField(Icons.school_outlined, 'Education'),
        _MockField(Icons.favorite_border, 'Interests'),
      ],
    ),
    _FeatureData(
      icon: Icons.chat_bubble_outline_rounded,
      tag: 'MESSAGING',
      title: 'Safe & Private Chat',
      description:
          'Send messages only to approved matches. Every field in your chat is encrypted and fully private.',
      mockFields: [
        _MockField(Icons.send_outlined, 'Send Message'),
        _MockField(Icons.photo_outlined, 'Share Photo'),
        _MockField(Icons.videocam_outlined, 'Video Call'),
        _MockField(Icons.block_outlined, 'Block / Report'),
      ],
    ),
    _FeatureData(
      icon: Icons.verified_outlined,
      tag: 'VERIFIED',
      title: 'Real Verified Members',
      description:
          'Each profile is verified with a government ID check so you always connect with genuine people.',
      mockFields: [
        _MockField(Icons.badge_outlined, 'ID Verified'),
        _MockField(Icons.photo_camera_outlined, 'Photo Check'),
        _MockField(Icons.workspace_premium_outlined, 'Premium Badge'),
        _MockField(Icons.circle_outlined, 'Active Status'),
      ],
    ),
  ];

  int _currentIndex = 0;

  late final AnimationController _slideCtrl;
  late final AnimationController _fadeCtrl;
  late final AnimationController _pulseCtrl;
  late final Animation<Offset> _slideAnim;
  late final Animation<double> _fadeAnim;
  late final Animation<double> _pulseAnim;

  Timer? _autoTimer;

  @override
  void initState() {
    super.initState();

    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _slideAnim = Tween<Offset>(
      begin: const Offset(0.22, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic));

    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeIn),
    );

    _pulseAnim = Tween<double>(begin: 0.82, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    _playEntrance();
    _startAutoTimer();
  }

  void _playEntrance() {
    _slideCtrl.forward(from: 0);
    _fadeCtrl.forward(from: 0);
  }

  void _startAutoTimer() {
    _autoTimer?.cancel();
    _autoTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;
      setState(() {
        _currentIndex = (_currentIndex + 1) % _features.length;
      });
      _playEntrance();
    });
  }

  void _goToIndex(int idx) {
    if (idx == _currentIndex) return;
    setState(() => _currentIndex = idx);
    _playEntrance();
    _startAutoTimer();
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _slideCtrl.dispose();
    _fadeCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final feature = _features[_currentIndex];

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.primaryDark],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Stack(
        children: [
          const Positioned(left: -140, top: -220, child: ArcBigCircle()),
          const Positioned(right: -160, bottom: 160, child: ArcBigCircle()),

          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Spacer(),

                  // Animated feature badge (tag pill with pulsing icon)
                  SlideTransition(
                    position: _slideAnim,
                    child: FadeTransition(
                      opacity: _fadeAnim,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.white.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ScaleTransition(
                              scale: _pulseAnim,
                              child: Icon(feature.icon,
                                  color: AppColors.white, size: 14),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              feature.tag,
                              style: const TextStyle(
                                color: AppColors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Animated title
                  SlideTransition(
                    position: _slideAnim,
                    child: FadeTransition(
                      opacity: _fadeAnim,
                      child: Text(
                        feature.title,
                        style: const TextStyle(
                          color: AppColors.white,
                          fontSize: 28,
                          height: 1.2,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Animated description
                  SlideTransition(
                    position: _slideAnim,
                    child: FadeTransition(
                      opacity: _fadeAnim,
                      child: Text(
                        feature.description,
                        style: TextStyle(
                          color: AppColors.white.withOpacity(0.9),
                          fontSize: 13.5,
                          height: 1.6,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Animated mock-fields preview card
                  SlideTransition(
                    position: _slideAnim,
                    child: FadeTransition(
                      opacity: _fadeAnim,
                      child: _AnimatedFieldsCard(
                        fields: feature.mockFields,
                        pulseAnim: _pulseAnim,
                      ),
                    ),
                  ),

                  const SizedBox(height: 22),

                  // Tappable column-indicator dots
                  Row(
                    children: List.generate(_features.length, (i) {
                      final isActive = i == _currentIndex;
                      return GestureDetector(
                        onTap: () => _goToIndex(i),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          margin: const EdgeInsets.only(right: 8),
                          width: isActive ? 28 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: isActive
                                ? AppColors.white
                                : AppColors.white.withOpacity(0.38),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      );
                    }),
                  ),

                  const SizedBox(height: 160),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Animated mock-fields preview card — shows how the feature column works
class _AnimatedFieldsCard extends StatelessWidget {
  final List<_MockField> fields;
  final Animation<double> pulseAnim;

  const _AnimatedFieldsCard({
    required this.fields,
    required this.pulseAnim,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.white.withOpacity(0.13),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.white.withOpacity(0.25),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Card header: "How it works" label + pulsing LIVE badge
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: AppColors.white,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'How it works',
                style: TextStyle(
                  color: AppColors.white.withOpacity(0.72),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                ),
              ),
              const Spacer(),
              ScaleTransition(
                scale: pulseAnim,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.white.withOpacity(0.22),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'LIVE',
                    style: TextStyle(
                      color: AppColors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Mock field chips — each represents a column/field in that feature
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: fields.map((f) => _MockFieldChip(field: f)).toList(),
          ),
        ],
      ),
    );
  }
}

/// Individual field chip shown in the animated preview card
class _MockFieldChip extends StatelessWidget {
  final _MockField field;

  const _MockFieldChip({required this.field});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.white.withOpacity(0.16),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.white.withOpacity(0.28),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(field.icon, color: AppColors.white, size: 13),
          const SizedBox(width: 5),
          Text(
            field.label,
            style: const TextStyle(
              color: AppColors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// ---------- small helper widgets ----------

class CircleAvatarWithBorder extends StatelessWidget {
  final ImageProvider image;
  final double size;
  const CircleAvatarWithBorder({
    super.key,
    required this.image,
    this.size = 60,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: [AppColors.white, AppColors.white.withOpacity(0.7)]),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowMedium,
            blurRadius: 6,
            offset: const Offset(0, 3),
          )
        ],
      ),
      child: CircleAvatar(
        radius: (size - 6) / 2,
        backgroundImage: image,
      ),
    );
  }
}

class FloatingIcon extends StatelessWidget {
  final IconData icon;
  const FloatingIcon({super.key, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: Colors.transparent,
        border: Border.all(color: AppColors.white, width: 1.6),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowMedium,
            blurRadius: 6,
            offset: const Offset(0, 3),
          )
        ],
      ),
      child: Icon(icon, color: AppColors.white, size: 18),
    );
  }
}

class RoundedImageCard extends StatelessWidget {
  final ImageProvider image;
  final double width;
  final double height;
  final double borderRadius;
  const RoundedImageCard({
    super.key,
    required this.image,
    required this.width,
    required this.height,
    required this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowDark,
            blurRadius: 18,
            offset: const Offset(0, 10),
          )
        ],
        image: DecorationImage(
          image: image,
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}

/// Big light arc circle used top-left (partially off-screen)
class ArcBigCircle extends StatelessWidget {
  const ArcBigCircle({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 420,
      height: 420,
      child: CustomPaint(
        painter: _ArcPainter(),
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = AppColors.white.withOpacity(0.24);
    canvas.drawCircle(Offset(size.width / 2, size.height / 2), size.width / 2, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}


