import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart'
    if (dart.library.html) 'package:ms2026/utils/web_permission_stub.dart';

import '../constant/app_colors.dart';
import '../constant/app_dimensions.dart';
import '../service/connectivity_service.dart';

class NoInternetScreen extends StatefulWidget {
  final FutureOr<void> Function()? onRetry;

  const NoInternetScreen({super.key, this.onRetry});

  @override
  State<NoInternetScreen> createState() => _NoInternetScreenState();
}

class _NoInternetScreenState extends State<NoInternetScreen>
    with SingleTickerProviderStateMixin {
  final ConnectivityService _connectivityService = ConnectivityService();
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  bool _isChecking = false;
  bool _isRecovering = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );
    _animationController.forward();
    _connectivityService.addListener(_onConnectivityChange);
  }

  void _onConnectivityChange() {
    if (_connectivityService.isConnected && mounted) {
      _triggerRecovery();
    }
  }

  @override
  void dispose() {
    _connectivityService.removeListener(_onConnectivityChange);
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _handleRetry() async {
    if (_isChecking || _isRecovering) {
      return;
    }

    setState(() {
      _isChecking = true;
    });

    final hasInternet = await _connectivityService.checkConnectivity();

    if (!mounted) {
      return;
    }

    setState(() {
      _isChecking = false;
    });

    if (hasInternet) {
      await _completeRetry();
      return;
    }

    _showNoConnectionSnackBar();
  }

  Future<void> _completeRetry() async {
    if (_isRecovering || !mounted) {
      return;
    }

    _isRecovering = true;

    try {
      if (widget.onRetry != null) {
        await widget.onRetry!();
      } else if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    } finally {
      _isRecovering = false;
    }
  }

  Future<void> _triggerRecovery() async {
    try {
      await _completeRetry();
    } catch (error) {
      debugPrint('NoInternetScreen recovery failed: $error');
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to reload after reconnecting. Please try the retry button.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _showNoConnectionSnackBar() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _connectivityService.isWifiConnected
              ? 'Wi-Fi is connected, but internet access is unavailable.'
              : _connectivityService.isMobileConnected
                  ? 'Mobile data is connected, but internet access is unavailable.'
                  : 'Still no internet connection.',
        ),
        backgroundColor: AppColors.error,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _openWifiSettings() async {
    try {
      await openAppSettings();
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to open settings.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _openMobileDataSettings() async {
    try {
      await openAppSettings();
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to open settings.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDisconnected = !_connectivityService.isWifiConnected &&
        !_connectivityService.isMobileConnected;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemStatusBarContrastEnforced: false,
      ),
      child: Scaffold(
        backgroundColor: AppColors.white,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
            onPressed: () {
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
            },
          ),
        ),
        body: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TweenAnimationBuilder(
                    tween: Tween<double>(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 800),
                    builder: (context, double value, child) {
                      return Transform.scale(
                        scale: value,
                        child: Container(
                          padding: const EdgeInsets.all(32),
                          decoration: BoxDecoration(
                            color: AppColors.error.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.wifi_off_rounded,
                            size: 100,
                            color: AppColors.error,
                          ),
                        ),
                      );
                    },
                  ),
                  AppSpacing.verticalXL,
                  const Text(
                    'No internet connection',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  AppSpacing.verticalMD,
                  Text(
                    isDisconnected
                        ? 'No network connection was detected. Please turn on Wi-Fi or mobile data.'
                        : _connectivityService.isWifiConnected
                            ? 'Wi-Fi is connected, but internet access is unavailable. Please check your Wi-Fi network.'
                            : _connectivityService.isMobileConnected
                                ? 'Mobile data is connected, but internet access is unavailable. Please check your data connection.'
                                : 'Please check your internet connection and try again.',
                    style: const TextStyle(
                      fontSize: 16,
                      color: AppColors.textSecondary,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  AppSpacing.verticalXL,
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppColors.borderLight,
                        width: 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        _buildConnectionRow(
                          'Wi-Fi',
                          _connectivityService.isWifiConnected,
                          Icons.wifi_rounded,
                          _openWifiSettings,
                        ),
                        AppSpacing.verticalMD,
                        _buildConnectionRow(
                          'Mobile Data',
                          _connectivityService.isMobileConnected,
                          Icons.signal_cellular_alt_rounded,
                          _openMobileDataSettings,
                        ),
                      ],
                    ),
                  ),
                  AppSpacing.verticalXL,
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isChecking ? null : _handleRetry,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      icon: _isChecking
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation(AppColors.white),
                              ),
                            )
                          : const Icon(Icons.refresh_rounded),
                      label: Text(
                        _isChecking ? 'Checking...' : 'Retry',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  AppSpacing.verticalMD,
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _openWifiSettings,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        side: const BorderSide(
                          color: AppColors.primary,
                          width: 1.5,
                        ),
                      ),
                      icon: const Icon(Icons.settings_rounded),
                      label: const Text(
                        'Open Settings',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
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

  Widget _buildConnectionRow(
    String title,
    bool isConnected,
    IconData icon,
    VoidCallback onTap,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isConnected
                  ? AppColors.success.withOpacity(0.1)
                  : AppColors.error.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              color: isConnected ? AppColors.success : AppColors.error,
              size: 24,
            ),
          ),
          AppSpacing.horizontalMD,
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isConnected
                  ? AppColors.success.withOpacity(0.1)
                  : AppColors.error.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              isConnected ? 'Connected' : 'Disconnected',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isConnected ? AppColors.success : AppColors.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
