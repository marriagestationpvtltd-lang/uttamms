import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../Auth/Screen/signupscreen10.dart';
import '../Auth/Screen/signupscreen2.dart';
import '../Auth/Screen/signupscreen3.dart';
import '../Auth/Screen/signupscreen4.dart';
import '../Auth/Screen/signupscreen5.dart';
import '../Auth/Screen/signupscreen6.dart';
import '../Auth/Screen/signupscreen7.dart';
import '../Auth/Screen/signupscreen8.dart';
import '../Auth/Screen/signupscreen9.dart';
import '../Auth/SuignupModel/signup_model.dart';
import '../Chat/ChatlistScreen.dart';
import '../Home/Screen/HomeScreenPage.dart';
import '../ReUsable/Navbar.dart';
import '../core/user_state.dart';
import '../online/onlineservice.dart';
import '../profile/myprofile.dart';
import '../purposal/purposalScreen.dart';
import '../pushnotification/pushservice.dart';
import '../service/pagenocheck.dart';
import '../webrtc/webrtc.dart';
import '../constant/app_colors.dart';
import '../constant/app_dimensions.dart';
import '../navigation/app_navigation.dart';
import 'MainControllere.dart';
import 'onboarding.dart';

import 'dart:convert';
import 'dart:async';
import 'package:ms2026/config/app_endpoints.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  // ── Fast-start support ──────────────────────────────────────────────────────
  // Set by main() before runApp() so _setupAnimations() can choose the right
  // duration synchronously in initState (no async SharedPreferences read needed
  // before the first frame).
  static bool _isSubsequentLaunch = false;

  /// Called from main() after reading SharedPreferences and pre-warming the
  /// GIF asset bytes. Stores the launch-count flag and marks the app as ready
  /// for the fast-start animation path on second-and-later launches.
  static void preloadForFastStart(bool hasLaunchedBefore) {
    _isSubsequentLaunch = hasLaunchedBefore;
  }

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  Map<String, dynamic>? _versionData;
  bool _isCheckingVersion = true;
  String? _errorMessage;
  bool _isFirstLaunch = true; // Track if this is the first app launch

  // Prevents double-navigation when the background version check completes
  // after the splash screen has already navigated away.
  bool _navigationStarted = false;

  // Completes when the entrance animation finishes.
  // Guaranteed to be set in initState before any async callback can use it.
  late Future<void> _animationCompleted;

  // Completes when navigation data (prefs + optional pageNo API) is preloaded.
  // Runs concurrently with the entrance animation so navigation can start the
  // instant the animation finishes rather than after an extra round-trip.
  // Initialised to a completed future so that any unexpected early call to
  // _proceedWithNavigation never hits a LateInitializationError.
  Future<void> _navDataFuture = Future.value();

  // Animation durations:
  //   First launch    → 2000 ms so the full GIF cycle plays.
  //   Subsequent      → 600 ms for an instant branded flash before navigation.
  // First launch: 4200 ms — long enough for the full networking animation to
  // play, then the logo crossfades in on top.
  // Subsequent: 600 ms — instant branded flash before navigation.
  static const int _firstLaunchDurationMs = 4200;
  static const int _returnLaunchDurationMs = 600;

  int get _entranceDurationMs =>
      SplashScreen._isSubsequentLaunch ? _returnLaunchDurationMs : _firstLaunchDurationMs;

  // Current app versions - Update these with your actual current versions
  final String currentAndroidVersion = '24.0.0'; // Your current Android version
  final String currentIOSVersion = '1.0.0';     // Your current iOS version

  // Animation controllers - simplified
  AnimationController? _entranceController;
  AnimationController? _dotsController;

  // Entrance animations - simplified
  Animation<double>? _logoOpacity;
  Animation<double>? _textOpacity;

  @override
  void initState() {
    super.initState();

    // Set up simplified animations
    _setupAnimations();
    _animationCompleted = _entranceController!.forward().orCancel
        .catchError((Object e) {
          if (e is! TickerCanceled) debugPrint('Splash entrance animation failed: $e');
        });

    // Kick off background work: first-launch tracking, navigation, and the
    // optional version check. None of these block the animation or the UI.
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    // Record first-launch flag. This is fire-and-forget w.r.t. the animation;
    // the entrance animations are already playing by the time we get here.
    await _checkFirstLaunch();

    // Pre-load navigation data (prefs reads + optional pageNo API call) in
    // parallel with the entrance animation. This way navigation is instant
    // once the animation finishes — no sequential server round-trip after the
    // splash screen has already played.
    _navDataFuture = _preloadNavData();

    // Proceed to navigation — waits for both the animation AND the preloaded
    // data (via Future.wait) so they race concurrently.
    _proceedWithNavigation();

    // Check for app updates in background. The result never delays navigation;
    // if an update is available a dialog is shown on top of the current screen.
    _checkAppVersionInBackground();
  }

  /// Pre-loads everything needed by [_navigateBasedOnUserState] so that the
  /// actual navigation call after the animation is effectively instantaneous.
  ///
  /// On first launch (no cached pageNo) this triggers the API call to
  /// [PageService.getPageNo] and caches the result, eliminating the sequential
  /// network round-trip that previously followed the 3-second entrance
  /// animation.
  Future<void> _preloadNavData() async {
    try {
      if (!mounted) return;
      // Load user model data from storage (fast, local read).
      await context.read<SignupModel>().loadUserData();

      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('bearer_token');
      final userDataString = prefs.getString('user_data');

      if (token == null || userDataString == null) return;

      final userData = jsonDecode(userDataString);
      final userId = int.tryParse(userData["id"].toString());
      if (userId == null) return;

      // Load cached UserState first (instant local read) then fetch fresh
      // state from the server.  We await the refresh so that the pageno=8
      // navigation decision (isVerified gate) always uses accurate data
      // rather than a potentially-stale cache value.
      if (mounted) {
        final userState = context.read<UserState>();
        await userState.loadFromCache();
        await userState.refresh(userId);
      }

      // Only fetch pageNo from the server when there is no cached value.
      // Subsequent launches already have a cached pageNo and will navigate
      // instantly once the animation ends.
      final cachedPageNo = prefs.getInt('cached_page_no');
      if (cachedPageNo == null) {
        final pageNo = await PageService.getPageNo(userId);
        if (pageNo != null && mounted) {
          await prefs.setInt('cached_page_no', pageNo);
        }
      }
    } catch (e) {
      // Preload errors are non-fatal — _navigateBasedOnUserState will retry
      // any failed reads/calls itself when it runs after the animation.
      debugPrint('Splash nav preload error (non-fatal): $e');
    }
  }

  Future<void> _checkFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    final hasLaunchedBefore = prefs.getBool('has_launched_before') ?? false;

    if (mounted) {
      setState(() {
        _isFirstLaunch = !hasLaunchedBefore;
      });
    }

    // Mark that the app has been launched
    if (!hasLaunchedBefore) {
      await prefs.setBool('has_launched_before', true);
    }
  }

  void _setupAnimations() {
    // Simplified animation setup - just entrance duration
    final entranceMs = _entranceDurationMs;

    _entranceController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: entranceMs),
    );

    // 3-dot wave loop
    _dotsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750),
    )..repeat();

    // Logo fades in smoothly
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController!,
        curve: const Interval(0.0, 0.4, curve: Curves.easeOut),
      ),
    );

    // Text fades in after logo
    _textOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController!,
        curve: const Interval(0.4, 0.8, curve: Curves.easeOut),
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Pre-decode the splash GIF so there is no blank white frame between the
    // native splash and the first Flutter frame that contains the logo.
    precacheImage(const AssetImage('assets/images/ms.gif'), context);
  }

  @override
  void dispose() {
    _entranceController?.dispose();
    _dotsController?.dispose();
    super.dispose();
  }

  /// Performs an app version check. When [isBackground] is true, the call
  /// respects the cached timestamp to avoid hammering the server and never
  /// surfaces user-facing errors.
  Future<void> _checkAppVersion({bool isBackground = false}) async {
    const sixHoursMs = 6 * 60 * 60 * 1000;
    const thirtyMinutesMs = 30 * 60 * 1000;
    SharedPreferences? prefs;

    if (!isBackground && mounted) {
      setState(() {
        _isCheckingVersion = true;
        _errorMessage = null;
      });
    }

    try {
      prefs = await SharedPreferences.getInstance();
      // 0 means "never checked" → always proceeds on fresh install.
      if (isBackground) {
        final lastCheck = prefs.getInt('last_version_check_ok') ?? 0;
        final msElapsed = DateTime.now().millisecondsSinceEpoch - lastCheck;
        if (msElapsed < sixHoursMs) {
          if (mounted) setState(() => _isCheckingVersion = false);
          return; // Checked recently — nothing to do.
        }
      }

      final response = await http
          .get(Uri.parse('${kApiBaseUrl}/app.php'))
          .timeout(const Duration(seconds: 5));

      // Always update the cache after a real HTTP attempt so that a server
      // returning non-success or an update-not-needed result doesn't trigger
      // a repeat check on the very next launch.
      await prefs.setInt(
          'last_version_check_ok', DateTime.now().millisecondsSinceEpoch);

      if (response.statusCode != 200) {
        throw Exception('Non-200 response');
      }

      final data = jsonDecode(response.body);
      if (data['success'] != true) {
        throw Exception('Invalid response');
      }

      _versionData = data['data'];
      if (mounted) {
        setState(() {
          _isCheckingVersion = false;
          _errorMessage = null;
        });
      }

      _showUpdateDialogIfNeeded();
    } catch (_) {
      if (isBackground) {
        // Network unavailable or timeout.  Save a shortened cache timestamp so
        // that we retry in ~30 min rather than on every single launch.
        try {
          prefs ??= await SharedPreferences.getInstance();
          // Back-date the timestamp by (sixHours - thirtyMinutes) so the next
          // cache check fires after ~30 minutes instead of another 6 hours.
          final retryAfter30Min = DateTime.now().millisecondsSinceEpoch -
              (sixHoursMs - thirtyMinutesMs);
          await prefs.setInt('last_version_check_ok', retryAfter30Min);
          if (mounted) setState(() => _isCheckingVersion = false);
        } catch (_) {}
      } else if (mounted) {
        setState(() {
          _isCheckingVersion = false;
          _errorMessage =
              'Unable to check for updates. Please check your connection and try again.';
        });
      }
    }
  }

  /// Background version check — runs after navigation has already started so
  /// it never blocks the user from reaching the app.
  ///
  /// • Within 6 h of the last check  → skipped entirely.
  /// • HTTP success with new version  → shows update dialog on the current screen.
  /// • HTTP error / timeout           → saves a shortened cache time (30 min) so
  ///   we retry later but don't hammer the server on every launch.
  Future<void> _checkAppVersionInBackground() async {
    await _checkAppVersion(isBackground: true);
  }

  /// Shows an update dialog on whichever screen is currently active.
  /// Safe to call after the splash screen has already navigated away because it
  /// uses the global [navigatorKey] context instead of the widget's own context.
  void _showUpdateDialogIfNeeded() {
    if (_versionData == null) return;

    final String serverAndroidVersion =
        _versionData!['android_version']?.toString() ?? '';
    final String serverIOSVersion =
        _versionData!['ios_version']?.toString() ?? '';
    final bool forceUpdate = _versionData!['force_update'] == true;
    final String description =
        _versionData!['description']?.toString() ?? '';
    final String appLink = _versionData!['app_link']?.toString() ?? '';

    if (kIsWeb) return;

    bool updateNeeded = false;
    String? platformVersion;
    final isAndroid = defaultTargetPlatform == TargetPlatform.android;
    final isIOS = defaultTargetPlatform == TargetPlatform.iOS;

    if (isAndroid && serverAndroidVersion.isNotEmpty) {
      updateNeeded =
          _compareVersions(currentAndroidVersion, serverAndroidVersion);
      platformVersion = serverAndroidVersion;
    } else if (isIOS && serverIOSVersion.isNotEmpty) {
      updateNeeded = _compareVersions(currentIOSVersion, serverIOSVersion);
      platformVersion = serverIOSVersion;
    }

    if (!updateNeeded) return;

    // Prefer the global navigator's context (always points to the currently
    // active screen) over the splash screen's own context, which becomes
    // invalid once pushReplacement has disposed the widget.
    final ctx = navigatorKey.currentContext ?? (mounted ? context : null);
    if (ctx == null) return;

    _showUpdateDialog(
      forceUpdate, description, appLink, platformVersion!,
      dialogContext: ctx,
    );
  }

  bool _compareVersions(String current, String server) {
    // Simple version comparison (can be enhanced for more complex versioning)
    List<int> currentParts = current.split('.').map(int.parse).toList();
    List<int> serverParts = server.split('.').map(int.parse).toList();

    for (int i = 0; i < currentParts.length; i++) {
      if (i >= serverParts.length) return false;
      if (serverParts[i] > currentParts[i]) return true;
      if (serverParts[i] < currentParts[i]) return false;
    }
    return serverParts.length > currentParts.length;
  }

  void _showUpdateDialog(bool forceUpdate, String description, String appLink,
      String newVersion, {BuildContext? dialogContext}) {
    // Use the supplied context (e.g. navigatorKey.currentContext when called
    // from the background check) or fall back to the widget's own context.
    final ctx = dialogContext ?? context;
    showDialog(
      context: ctx,
      barrierDismissible: !forceUpdate,
      builder: (BuildContext dialogCtx) {
        return PopScope(
          canPop: !forceUpdate,
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: forceUpdate ? AppColors.error.withOpacity(0.1) : AppColors.info.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    forceUpdate ? Icons.system_update_alt : Icons.update,
                    color: forceUpdate ? AppColors.error : AppColors.info,
                    size: 24,
                  ),
                ),
                AppSpacing.horizontalMD,
                Expanded(
                  child: Text(
                    forceUpdate ? 'Update Required' : 'New Update Available',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Version $newVersion',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                      fontSize: 14,
                    ),
                  ),
                ),
                AppSpacing.verticalMD,
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (forceUpdate) ...[
                  AppSpacing.verticalMD,
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.error.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.error.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.warning_rounded,
                          color: AppColors.error,
                          size: 20,
                        ),
                        AppSpacing.horizontalSM,
                        const Expanded(
                          child: Text(
                            'You must update to continue using the app.',
                            style: TextStyle(
                              color: AppColors.error,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              if (!forceUpdate)
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogCtx).pop();
                    // _proceedWithNavigation() is a no-op once navigation has
                    // started, so it's safe to call here for the rare case
                    // where the background dialog fires before navigation.
                    _proceedWithNavigation();
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                  ),
                  child: const Text('Later'),
                ),
              ElevatedButton(
                onPressed: () async {
                  final Uri url = Uri.parse(appLink);
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                    if (forceUpdate) {
                      // If force update, keep dialog open
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'Update Now',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        );
      },
    ).then((_) {
      if (!forceUpdate) {
        _proceedWithNavigation();
      }
    });
  }

  Future<void> _proceedWithNavigation() async {
    // Prevent duplicate navigation (e.g. from the background version-check
    // callback firing after we have already navigated away).
    if (_navigationStarted) return;
    _navigationStarted = true;

    if (!mounted) return;

    // Wait for the logo entrance animation to finish AND for nav data to be
    // ready. Both run concurrently (started in initState / _initializeApp),
    // so navigation fires as soon as the later of the two completes — the
    // full logo GIF animation always plays and navigation is instant once it
    // ends (no extra round-trip after the animation).
    await Future.wait([_animationCompleted, _navDataFuture]);

    if (!mounted) return;

    await _navigateBasedOnUserState();
  }

  Future<void> _navigateBasedOnUserState() async {
    await context.read<SignupModel>().loadUserData();

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('bearer_token');
    final userDataString = prefs.getString('user_data');

    // NO TOKEN → GO TO ONBOARDING
    if (token == null || userDataString == null) {
      _goTo(const OnboardingScreen());
      return;
    }

    // Decode stored signup response
    final userData = jsonDecode(userDataString);
    final userId = int.tryParse(userData["id"].toString());

    if (userId == null) {
      _goTo(const OnboardingScreen());
      return;
    }

    _initFCM();

    // Use cached pageNo for instant navigation (skip API call on subsequent launches)
    final cachedPageNo = prefs.getInt('cached_page_no');
    if (cachedPageNo != null) {
      if (!mounted) return;
      _navigateToPage(cachedPageNo);
      // Validate in background and re-navigate only if pageNo changed
      PageService.getPageNo(userId).then((freshPageNo) {
        if (freshPageNo != null) {
          prefs.setInt('cached_page_no', freshPageNo);
          if (freshPageNo != cachedPageNo && mounted) {
            _navigateToPage(freshPageNo);
          }
        }
      }).catchError((e) {
        debugPrint('Background pageNo validation failed: $e');
      });
      return;
    }

    // No cached pageNo → call API (first launch or cache cleared after logout)
    final pageNo = await PageService.getPageNo(userId);

    if (!mounted) return;

    if (pageNo == null) {
      _goTo(const OnboardingScreen());
      return;
    }

    await prefs.setInt('cached_page_no', pageNo);
    _navigateToPage(pageNo);
  }

  void _navigateToPage(int pageNo) {
    switch (pageNo) {
      case 0:
        _goTo(const PersonalDetailsPage());
        break;
      case 1:
        _goTo(const CommunityDetailsPage());
        break;
      case 2:
        _goTo(const LivingStatusPage());
        break;
      case 3:
        _goTo(FamilyDetailsPage());
        break;
      case 4:
        _goTo(EducationCareerPage());
        break;
      case 5:
        _goTo(AstrologicDetailsPage());
        break;
      case 6:
        _goTo(LifestylePage());
        break;
      case 7:
        _goTo(PartnerPreferencesPage());
        break;
      case 8:
        // Navigate to home if the user has submitted documents (pending or
        // approved) or is fully verified. Only show IDVerificationScreen when
        // no documents have ever been uploaded so the user can complete the
        // initial submission step. Rejected documents also redirect to home –
        // the user can re-upload from their profile without being blocked here.
        final userState = mounted ? context.read<UserState>() : null;
        final identityStatus = userState?.identityStatus ?? 'not_uploaded';
        _goTo(identityStatus != UserState.statusNotUploaded
            ? const MainControllerScreen(initialIndex: 0)
            : const IDVerificationScreen());
        break;
      case 9:
      case 10:
        _goTo(const MainControllerScreen(initialIndex: 0));
        break;
      default:
        _goTo(const OnboardingScreen());
    }
  }

  Future<void> _initFCM() async {
    final prefs = await SharedPreferences.getInstance();

    final userDataString = prefs.getString('user_data');
    if (userDataString == null) return;

    final userData = jsonDecode(userDataString);
    final String userId = userData["id"].toString();

    try {
      // Request notification permission. The result only affects whether the
      // OS displays notification banners — the FCM token must always be
      // registered with the backend so the server can reach this device.
      NotificationSettings settings =
          await FirebaseMessaging.instance.requestPermission();

      final authorized =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
      print(authorized
          ? "Push permission granted"
          : "Push permission not granted - banners won't show, but token will still be registered");

      await Future.delayed(const Duration(milliseconds: 300));

      String? fcmToken = await FirebaseMessaging.instance.getToken();

      if (fcmToken == null) {
        await Future.delayed(const Duration(milliseconds: 500));
        fcmToken = await FirebaseMessaging.instance.getToken();
      }

      if (fcmToken == null) {
        print("FCM token still null after retry");
        return;
      }

      print("FCM TOKEN => $fcmToken");

      // Always update the token on the server. This ensures the backend stays
      // in sync after a Firebase project key change, a DB reset, or a token
      // that was previously blocked from reaching the server.
      await prefs.setString('fcm_token', fcmToken);
      await updateFcmToken(userId, fcmToken);
      print("FCM TOKEN synced with server");

      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
        await prefs.setString('fcm_token', newToken);
        await updateFcmToken(userId, newToken);
        print("FCM TOKEN refreshed => $newToken");
      });
    } catch (e) {
      print("FCM ERROR => $e");
    }
    OnlineStatusService().start();
  }

  Future<void> updateFcmToken(String userId, String token) async {
    final response = await http.post(
      Uri.parse("${kApiBaseUrl}/Api2/update_token.php"),
      body: {
        "user_id": userId,
        "fcm_token": token,
      },
    );
    print(response.body);
  }

  void _goTo(Widget screen) {
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => screen,
        transitionDuration: const Duration(milliseconds: 600),
        reverseTransitionDuration: const Duration(milliseconds: 300),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  // ─── Single decorative ring with gradient glow ────────────────────────────
  Widget _buildRing(
      Animation<double>? scale, Animation<double>? opacity, double baseSize,
      {Color ringColor = const Color(0xFFFF4466)}) {
    if (scale == null || opacity == null) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: Listenable.merge([scale, opacity]),
      builder: (context, child) => Opacity(
        opacity: opacity.value.clamp(0.0, 1.0),
        child: Transform.scale(
          scale: scale.value,
          child: child,
        ),
      ),
      child: Container(
        width: baseSize,
        height: baseSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: ringColor,
            width: 1.8,
          ),
          boxShadow: [
            BoxShadow(
              color: ringColor.withOpacity(0.50),
              blurRadius: 12,
              spreadRadius: 1,
            ),
          ],
        ),
      ),
    );
  }

  // ─── Logo with pure luminous glow — NO opaque white circle ──────────────
  // The glow is achieved entirely through radial gradients and box-shadows on
  // nearly-transparent containers, creating a "lit from within" look that
  // blends naturally into the dark red background.
  Widget _buildBrightLogo(double size) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer diffuse warm aura (largest layer, most transparent)
          Container(
            width: size * 1.05,
            height: size * 1.05,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  const Color(0xFFFF1A3A).withOpacity(0.22),
                  const Color(0xFFCC0020).withOpacity(0.08),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.55, 1.0],
              ),
            ),
          ),
          // Inner luminous core — soft warm-white glow (NOT a solid disc)
          Container(
            width: size * 0.74,
            height: size * 0.74,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              // Very subtle semi-transparent fill so the box-shadows render
              // correctly, while still appearing nearly see-through.
              gradient: RadialGradient(
                colors: [
                  Colors.white.withOpacity(0.14),
                  const Color(0xFFFFE0EA).withOpacity(0.07),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.42, 1.0],
              ),
              boxShadow: [
                // Tight white luminous halo
                BoxShadow(
                  color: Colors.white.withOpacity(0.60),
                  blurRadius: 52,
                  spreadRadius: 6,
                ),
                // Red mid-glow bloom
                BoxShadow(
                  color: const Color(0xFFFF2244).withOpacity(0.70),
                  blurRadius: 88,
                  spreadRadius: 16,
                ),
                // Wide diffuse crimson aura
                BoxShadow(
                  color: const Color(0xFFCC001A).withOpacity(0.38),
                  blurRadius: 140,
                  spreadRadius: 30,
                ),
              ],
            ),
          ),
          // GIF logo — rendered on top of the glow layers
          Image(
            image: const AssetImage('assets/images/ms.gif'),
            height: size,
            width: size,
            fit: BoxFit.contain,
            gaplessPlayback: true,
          ),
        ],
      ),
    );
  }

  // ─── Premium glowing wave dots ────────────────────────────────────────────
  Widget _buildLoadingDots() {
    // Each dot has its own color and glow to create a gradient wave effect.
    const dotColors = [
      Color(0xFFFFFFFF),  // white
      Color(0xFFFF8899),  // pink
      Color(0xFFFF3355),  // red
    ];
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (index) {
        final delay = index * 0.30;
        return AnimatedBuilder(
          animation: _dotsController!,
          builder: (context, child) {
            final raw = (_dotsController!.value - delay) % 1.0;
            final wave = Curves.easeInOutSine.transform(
              raw < 0.5 ? raw * 2.0 : (1.0 - raw) * 2.0,
            );
            final dotSize = 7.0 + 5.0 * wave;
            final color = dotColors[index];
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 5),
              width: dotSize,
              height: dotSize,
              transform: Matrix4.translationValues(0, -11 * wave, 0),
              decoration: BoxDecoration(
                color: color.withOpacity(0.55 + 0.45 * wave),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.75 * wave),
                    blurRadius: 14 * wave,
                    spreadRadius: 2 * wave,
                  ),
                ],
              ),
            );
          },
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final logoSize = screenSize.width * 0.6; // 60% of screen width

    return Scaffold(
      backgroundColor: const Color(0xFF8B0000), // dark red background
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF7B0000), // deep dark red
              Color(0xFF8B0000), // dark red
              Color(0xFFB00010), // rich red
            ],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Logo with simple fade-in animation
              FadeTransition(
                opacity: _logoOpacity ?? const AlwaysStoppedAnimation(1.0),
                child: Image.asset(
                  'assets/images/ms.gif',
                  height: logoSize,
                  width: logoSize,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                ),
              ),

              const SizedBox(height: 20),

              // App name with simple fade
              FadeTransition(
                opacity: _textOpacity ?? const AlwaysStoppedAnimation(1.0),
                child: const Text(
                  'Marriage Station',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 0.8,
                  ),
                ),
              ),

              const SizedBox(height: 6),

              // Tagline
              FadeTransition(
                opacity: _textOpacity ?? const AlwaysStoppedAnimation(1.0),
                child: const Text(
                  'Connecting Hearts',
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFFFFCCCC),
                    fontWeight: FontWeight.w400,
                    letterSpacing: 3.0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
