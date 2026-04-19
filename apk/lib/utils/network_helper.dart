import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../navigation/app_navigation.dart';
import '../service/connectivity_service.dart';
import '../screens/no_internet_screen.dart';
import '../constant/app_colors.dart';

/// Helper class for network-related operations
class NetworkHelper {
  /// Check internet connectivity before making API calls
  /// Returns true if internet is available, false otherwise
  /// Optionally shows a SnackBar if no internet and showMessage is true
  static Future<bool> checkConnectivity(
    BuildContext context, {
    bool showMessage = true,
    bool navigateToNoInternet = false,
  }) async {
    final connectivityService =
        Provider.of<ConnectivityService>(context, listen: false);
    final hasInternet = await connectivityService.checkConnectivity();

    if (!hasInternet && context.mounted) {
      if (navigateToNoInternet) {
        Navigator.of(context).push(
          MaterialPageRoute(
            settings: const RouteSettings(name: noInternetRouteName),
            builder: (_) => const NoInternetScreen(),
          ),
        );
      } else if (showMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.wifi_off, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    connectivityService.isWifiConnected
                        ? 'Wi-Fi is connected, but internet access is unavailable.'
                        : connectivityService.isMobileConnected
                            ? 'Mobile data is connected, but internet access is unavailable.'
                            : 'No internet connection. Please check your network and try again.',
                  ),
                ),
              ],
            ),
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    }

    return hasInternet;
  }

  /// Execute an API call with automatic internet checking
  /// If no internet, shows error message and returns null
  /// Otherwise, executes the apiCall and returns its result
  static Future<T?> executeWithConnectivityCheck<T>(
    BuildContext context, {
    required Future<T> Function() apiCall,
    bool showMessage = true,
    bool navigateToNoInternet = false,
  }) async {
    final hasInternet = await checkConnectivity(
      context,
      showMessage: showMessage,
      navigateToNoInternet: navigateToNoInternet,
    );

    if (!hasInternet) {
      return null;
    }

    try {
      return await apiCall();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return null;
    }
  }

  /// Show a loading dialog with connectivity status
  static void showLoadingDialog(BuildContext context, {String? message}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation(AppColors.primary),
                ),
                const SizedBox(height: 16),
                Text(
                  message ?? 'Please wait...',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Consumer<ConnectivityService>(
                  builder: (context, connectivity, _) {
                    return Text(
                      connectivity.getConnectionType(),
                      style: TextStyle(
                        fontSize: 12,
                        color: connectivity.isConnected
                            ? AppColors.success
                            : AppColors.error,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Dismiss loading dialog
  static void dismissLoadingDialog(BuildContext context) {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }
}
