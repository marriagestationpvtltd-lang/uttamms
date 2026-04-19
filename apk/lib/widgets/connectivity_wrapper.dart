import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../navigation/app_navigation.dart';
import '../service/connectivity_service.dart';
import '../screens/no_internet_screen.dart';

/// A wrapper widget that monitors internet connectivity and shows NoInternetScreen
/// when there's no connection. Automatically restores the wrapped screen when
/// connection is back.
class ConnectivityWrapper extends StatefulWidget {
  final Widget child;
  final bool enableAutoCheck;

  const ConnectivityWrapper({
    super.key,
    required this.child,
    this.enableAutoCheck = true,
  });

  @override
  State<ConnectivityWrapper> createState() => _ConnectivityWrapperState();
}

class _ConnectivityWrapperState extends State<ConnectivityWrapper> {
  bool _showingNoInternet = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.enableAutoCheck) {
      return widget.child;
    }

    return Consumer<ConnectivityService>(
      builder: (context, connectivityService, child) {
        final isConnected = connectivityService.isConnected;

        // Show no internet screen if not connected
        if (!isConnected && !_showingNoInternet) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _showingNoInternet = true;
              });
            }
          });
        }

        // Hide no internet screen if connected
        if (isConnected && _showingNoInternet) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _showingNoInternet = false;
              });
            }
          });
        }

        // Show no internet screen or the actual content
        if (_showingNoInternet) {
          return NoInternetScreen(
            onRetry: () async {
              final hasInternet = await connectivityService.checkConnectivity();
              if (hasInternet && mounted) {
                setState(() {
                  _showingNoInternet = false;
                });
              }
            },
          );
        }

        return widget.child;
      },
    );
  }
}

/// Extension to easily check connectivity before making API calls
extension ConnectivityCheck on BuildContext {
  /// Check if device has internet connection
  Future<bool> hasInternet() async {
    final connectivityService = Provider.of<ConnectivityService>(this, listen: false);
    return await connectivityService.checkConnectivity();
  }

  /// Show no internet screen if no connection, return true if has internet
  Future<bool> requireInternet() async {
    final connectivityService = Provider.of<ConnectivityService>(this, listen: false);
    final hasInternet = await connectivityService.checkConnectivity();

    if (!hasInternet && mounted) {
      Navigator.of(this).push(
        MaterialPageRoute(
          settings: const RouteSettings(name: noInternetRouteName),
          builder: (_) => const NoInternetScreen(),
        ),
      );
    }

    return hasInternet;
  }
}
