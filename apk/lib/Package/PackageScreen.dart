import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import '../constant/app_colors.dart';
import '../constant/app_text_styles.dart';
import 'Paymentscreen.dart';
import 'historypage.dart';
import 'package:ms2026/config/app_endpoints.dart';

class SubscriptionPage extends StatefulWidget {
  const SubscriptionPage({super.key});

  @override
  State<SubscriptionPage> createState() => _SubscriptionPageState();
}

class _SubscriptionPageState extends State<SubscriptionPage>
    with SingleTickerProviderStateMixin {

  List<Package> packages = [];
  bool isLoading = true;
  String errorMessage = '';
  int _currentPage = 0;
  bool _swipeForward = true;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  // Current active package info
  String? _activePackageName;
  String? _activePackageExpiry;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
    fetchPackages();
    _fetchActivePackage();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _fetchActivePackage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataString = prefs.getString('user_data');
      if (userDataString == null) return;
      final userData = jsonDecode(userDataString);
      final userId = userData["id"].toString();

      final response = await http.get(
        Uri.parse('${kApiBaseUrl}/Api2/user_package.php?userid=$userId'),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true &&
            data['data'] != null &&
            (data['data'] as List).isNotEmpty) {
          final latest = (data['data'] as List).first;
          if (mounted) {
            setState(() {
              _activePackageName = latest['package_name'];
              final expiry = latest['expiredate']?.toString() ?? '';
              _activePackageExpiry = expiry.length >= 10 ? expiry.substring(0, 10) : expiry;
            });
          }
        }
      }
    } catch (_) {}
  }

  Future<void> fetchPackages() async {
    try {
      final response = await http.get(
        Uri.parse('${kApiBaseUrl}/Api2/packagelist.php'),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          setState(() {
            packages = (data['data'] as List)
                .map((item) => Package.fromJson(item))
                .toList();
            isLoading = false;
          });
          _animationController.forward();
        } else {
          setState(() {
            errorMessage = data['message'] ?? 'Failed to load packages';
            isLoading = false;
          });
        }
      } else {
        setState(() {
          errorMessage = 'Server error: ${response.statusCode}';
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = 'Network error: $e';
        isLoading = false;
      });
    }
  }

  // Tier config: color palette per card index
  static const List<_TierConfig> _tierConfigs = [
    _TierConfig(
      gradient: [Color(0xFF1C1C2E), Color(0xFF2D2D44)],
      accentColor: Color(0xFFB0BEC5),
      label: 'Basic',
      icon: Icons.star_border_rounded,
    ),
    _TierConfig(
      gradient: [Color(0xFFB71C1C), AppColors.primary],
      accentColor: AppColors.premium,
      label: 'Popular',
      icon: Icons.workspace_premium_rounded,
    ),
    _TierConfig(
      gradient: [Color(0xFF004D40), Color(0xFF00897B)],
      accentColor: Color(0xFFA5D6A7),
      label: 'Value',
      icon: Icons.diamond_rounded,
    ),
    _TierConfig(
      gradient: [Color(0xFF311B92), Color(0xFF6A1B9A)],
      accentColor: Color(0xFFCE93D8),
      label: 'Premium',
      icon: Icons.military_tech_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _buildAppBar(context),
      body: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeaderBanner(),
            if (_activePackageName != null) _buildActivePackageBanner(),
            const SizedBox(height: 24),
            _buildSectionTitle(),
            const SizedBox(height: 16),
            _buildPackageList(),
            const SizedBox(height: 32),
            _buildWhyPremiumSection(),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: AppColors.primary,
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.white,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemStatusBarContrastEnforced: false,
      ),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.white, size: 22),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: Text(
        'Subscription Plans',
        style: AppTextStyles.labelLarge.copyWith(
          color: AppColors.white,
          fontSize: 19,
          fontWeight: FontWeight.w600,
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () async {
            final prefs = await SharedPreferences.getInstance();
            final userDataString = prefs.getString('user_data');
            if (userDataString == null) return;
            final userData = jsonDecode(userDataString);
            final userId = userData["id"].toString();
            if (context.mounted) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => PackageHistoryPage(userid: userId),
                ),
              );
            }
          },
          icon: const Icon(Icons.history_rounded, color: AppColors.white, size: 22),
          label: Text(
            'History',
            style: AppTextStyles.labelMedium.copyWith(
              color: AppColors.white,
              fontSize: 15,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeaderBanner() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: AppColors.primaryGradient,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.white.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.workspace_premium_rounded,
              color: AppColors.white,
              size: 40,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Upgrade to Premium',
            style: AppTextStyles.whiteHeading.copyWith(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Unlock all features and find your perfect match',
              style: AppTextStyles.whiteBody.copyWith(
                fontSize: 15,
                color: AppColors.white.withOpacity(0.9),
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildActivePackageBanner() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.verified_rounded, color: AppColors.premium, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Active Plan: $_activePackageName',
                  style: AppTextStyles.labelMedium.copyWith(
                    color: AppColors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (_activePackageExpiry != null)
                  Text(
                    'Expires: $_activePackageExpiry',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.white.withOpacity(0.85),
                      fontSize: 14,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 22,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'Choose Your Plan',
            style: AppTextStyles.heading3.copyWith(
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPackageList() {
    if (isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 80),
        child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }
    if (errorMessage.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 56, color: AppColors.textHint),
            const SizedBox(height: 16),
            Text(errorMessage,
                style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  isLoading = true;
                  errorMessage = '';
                });
                fetchPackages();
              },
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.white,
              ),
            ),
          ],
        ),
      );
    }
    if (packages.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Text(
            'No subscription packages available',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
          ),
        ),
      );
    }

    return FadeTransition(
      opacity: _fadeAnimation,
      child: GestureDetector(
        onHorizontalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          const double minVelocity = 200;
          const double minDistance = 50;
          final bool fastSwipe = velocity.abs() > minVelocity;
          final bool farDrag = details.localPosition.dx.abs() > minDistance || fastSwipe;
          if (!farDrag) return;
          if (velocity < 0 && _currentPage < packages.length - 1) {
            setState(() {
              _swipeForward = true;
              _currentPage++;
            });
          } else if (velocity > 0 && _currentPage > 0) {
            setState(() {
              _swipeForward = false;
              _currentPage--;
            });
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (child, animation) {
              final offsetTween = Tween<Offset>(
                begin: Offset(_swipeForward ? 1.0 : -1.0, 0),
                end: Offset.zero,
              );
              return SlideTransition(
                position: offsetTween.animate(
                  CurvedAnimation(parent: animation, curve: Curves.easeOut),
                ),
                child: FadeTransition(opacity: animation, child: child),
              );
            },
            child: _PackagePlanCard(
              key: ValueKey(_currentPage),
              package: packages[_currentPage],
              config: _tierConfigs[_currentPage % _tierConfigs.length],
              isPopular: _currentPage == 1,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWhyPremiumSection() {
    const features = [
      _FeatureItem(Icons.favorite_rounded, 'Unlimited Proposals',
          'Send and receive unlimited marriage proposals'),
      _FeatureItem(Icons.chat_bubble_rounded, 'Unlimited Chats',
          'Chat with all matched profiles without limits'),
      _FeatureItem(Icons.visibility_rounded, 'Profile Boost',
          'Your profile gets more visibility to suitable matches'),
      _FeatureItem(Icons.support_agent_rounded, 'Priority Support',
          'Get dedicated customer support for your journey'),
    ];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowLight,
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.stars_rounded, color: AppColors.primary, size: 26),
              const SizedBox(width: 10),
              Text(
                'Why go Premium?',
                style: AppTextStyles.heading4.copyWith(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...features.map((f) => Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(f.icon, color: AppColors.primary, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        f.title,
                        style: AppTextStyles.labelMedium.copyWith(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        f.subtitle,
                        style: AppTextStyles.bodySmall.copyWith(
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }
}

// ============================
// Package data model
// ============================
class Package {
  final int id;
  final String name;
  final String duration;
  final String description;
  final dynamic price;

  Package({
    required this.id,
    required this.name,
    required this.duration,
    required this.description,
    required this.price,
  });

  factory Package.fromJson(Map<String, dynamic> json) {
    return Package(
      id: _parseInt(json['id']),
      name: _parseString(json['name']),
      duration: _parseString(json['duration']),
      description: _parseString(json['description']),
      price: json['price'] ?? 0,
    );
  }

  static int _parseInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.toInt();
    return int.tryParse(value.toString()) ?? 0;
  }

  static String _parseString(dynamic value) {
    if (value == null) return '';
    return value.toString();
  }

  String get priceString {
    if (price is int) return 'Rs. $price';
    if (price is double) return 'Rs. ${(price as double).toStringAsFixed(0)}';
    final parsed = double.tryParse(price.toString());
    return parsed != null ? 'Rs. ${parsed.toStringAsFixed(0)}' : 'Rs. ${price}';
  }

  double get priceDouble {
    if (price is int) return (price as int).toDouble();
    if (price is double) return price as double;
    return double.tryParse(price.toString()) ?? 0.0;
  }
}

// ============================
// Tier configuration
// ============================
class _TierConfig {
  final List<Color> gradient;
  final Color accentColor;
  final String label;
  final IconData icon;

  const _TierConfig({
    required this.gradient,
    required this.accentColor,
    required this.label,
    required this.icon,
  });
}

class _FeatureItem {
  final IconData icon;
  final String title;
  final String subtitle;

  const _FeatureItem(this.icon, this.title, this.subtitle);
}

// ============================
// Pro Package Plan Card
// ============================
class _PackagePlanCard extends StatelessWidget {
  final Package package;
  final _TierConfig config;
  final bool isPopular;

  const _PackagePlanCard({
    super.key,
    required this.package,
    required this.config,
    this.isPopular = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: config.gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: config.gradient.first.withOpacity(0.45),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          clipBehavior: Clip.hardEdge,
        children: [
          // Background decorative circles
          Positioned(
            top: -30,
            right: -30,
            child: Container(
              width: 130,
              height: 130,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.white.withOpacity(0.05),
              ),
            ),
          ),
          Positioned(
            bottom: 40,
            left: -40,
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.white.withOpacity(0.04),
              ),
            ),
          ),
          // Content
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top row: tier icon + popular badge
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(config.icon, color: config.accentColor, size: 28),
                    ),
                    if (isPopular)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: config.accentColor,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.bolt_rounded,
                                size: 16,
                                color: config.gradient.first),
                            const SizedBox(width: 5),
                            Text(
                              'Most Popular',
                              style: AppTextStyles.labelSmall.copyWith(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: config.gradient.first,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                // Package name
                Text(
                  package.name,
                  style: AppTextStyles.whiteHeading.copyWith(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                // Duration badge
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    package.duration,
                    style: AppTextStyles.labelSmall.copyWith(
                      color: config.accentColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 16),
                // Price display
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Flexible(
                      child: Text(
                        package.priceString,
                        style: AppTextStyles.whiteHeading.copyWith(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '/ plan',
                        style: AppTextStyles.whiteBody.copyWith(
                          color: AppColors.white.withOpacity(0.7),
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Divider(color: AppColors.white.withOpacity(0.25), height: 1, thickness: 1),
                const SizedBox(height: 14),
                // Description
                if (package.description.isNotEmpty)
                  Text(
                    package.description,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.white.withOpacity(0.8),
                      fontSize: 12,
                      height: 1.4,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                const SizedBox(height: 12),
                // Features
                _featureRow(config.accentColor, 'Unlimited Proposals'),
                _featureRow(config.accentColor, 'Unlimited Chats'),
                _featureRow(config.accentColor, 'Priority Support'),
                _featureRow(config.accentColor, package.duration),
                const SizedBox(height: 12),
                // Subscribe button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: config.accentColor,
                      foregroundColor: config.gradient.first,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      elevation: 0,
                    ),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => PaymentPage(
                            amount: package.priceDouble,
                            discount: 0,
                            packageName: package.name,
                            packageId: package.id,
                            packageDuration: package.duration,
                          ),
                        ),
                      );
                    },
                    child: Text(
                      'Subscribe Now',
                      style: AppTextStyles.labelLarge.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: config.gradient.first,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        ),
      ),
    );
  }

  Widget _featureRow(Color accentColor, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(Icons.check_circle_rounded, color: accentColor, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.whiteBody.copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
