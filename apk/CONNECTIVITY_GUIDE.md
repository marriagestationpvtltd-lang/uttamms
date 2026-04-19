# Network Connectivity Integration Guide

This document explains how to use the new connectivity features throughout the app.

## Overview

The following components have been added:
1. **ConnectivityService** - Real-time internet monitoring
2. **NoInternetScreen** - User-friendly no internet page with WiFi/Data status
3. **ConnectivityWrapper** - Widget for automatic no-internet handling
4. **NetworkHelper** - Utility functions for checking connectivity

## Usage Examples

### 1. Check connectivity before API calls

```dart
import 'package:ms2026/utils/network_helper.dart';

Future<void> fetchData() async {
  // Check connectivity first
  final hasInternet = await NetworkHelper.checkConnectivity(context);

  if (!hasInternet) {
    return; // NetworkHelper already shows error message
  }

  // Make API call
  final response = await http.get(url);
  // ... process response
}
```

### 2. Execute API call with automatic connectivity check

```dart
import 'package:ms2026/utils/network_helper.dart';

Future<void> fetchMatchedProfiles() async {
  final result = await NetworkHelper.executeWithConnectivityCheck(
    context,
    apiCall: () async {
      final url = Uri.parse('https://digitallami.com/Api2/match.php?userid=$userId');
      final response = await http.get(url);
      return jsonDecode(response.body);
    },
  );

  if (result != null) {
    // Process successful result
    setState(() {
      _matchedProfiles = result['matched_users'];
    });
  }
}
```

### 3. Wrap screens with ConnectivityWrapper

```dart
import 'package:ms2026/widgets/connectivity_wrapper.dart';

class HomeScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ConnectivityWrapper(
      child: Scaffold(
        // Your screen content
      ),
    );
  }
}
```

### 4. Show loading with connectivity status

```dart
import 'package:ms2026/utils/network_helper.dart';

Future<void> saveData() async {
  NetworkHelper.showLoadingDialog(context, message: 'Saving...');

  await Future.delayed(Duration(seconds: 2)); // Your API call

  NetworkHelper.dismissLoadingDialog(context);
}
```

### 5. Manual navigation to No Internet screen

```dart
import 'package:ms2026/screens/no_internet_screen.dart';

void showNoInternet() {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => NoInternetScreen(
        onRetry: () {
          // Custom retry logic
          Navigator.pop(context);
          fetchData();
        },
      ),
    ),
  );
}
```

## Updating Existing Screens

### Example: Update HomeScreenPage

**Before:**
```dart
Future<void> fetchMatchedProfiles() async {
  try {
    setState(() {
      _isLoading = true;
    });

    final response = await http.get(url);
    // Process response
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Error: $e')),
    );
  }
}
```

**After:**
```dart
import 'package:ms2026/utils/network_helper.dart';

Future<void> fetchMatchedProfiles() async {
  // Check connectivity first
  final hasInternet = await NetworkHelper.checkConnectivity(context);
  if (!hasInternet) return;

  try {
    setState(() {
      _isLoading = true;
    });

    final response = await http.get(url);
    // Process response
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('त्रुटि: $e')),
      );
    }
  }
}
```

## Features

### NoInternetScreen
- Shows WiFi and Mobile Data status
- Nepali language support
- Auto-retry when connection is restored
- Direct link to system settings
- Professional UI with animations

### ConnectivityService
- Real-time connectivity monitoring
- Actual internet check (not just WiFi/Data connection)
- Provides connection type (WiFi, Mobile Data, etc.)
- Notifies listeners on connectivity change

### NetworkHelper
- Convenient utility functions
- Automatic error handling
- Customizable messages
- Loading dialogs with connectivity status

## Integration Checklist

For each screen that makes API calls:

- [ ] Import NetworkHelper: `import 'package:ms2026/utils/network_helper.dart';`
- [ ] Add connectivity check before API calls
- [ ] Use Nepali error messages
- [ ] Test offline scenario
- [ ] Test WiFi-connected-but-no-internet scenario
- [ ] Test mobile-data-connected-but-no-internet scenario

## Common Issues

### Issue: Settings button not opening settings
**Solution:** The app uses `permission_handler` package which provides `openAppSettings()`. This opens the app settings page where users can manually enable WiFi/Data.

### Issue: Connectivity check takes too long
**Solution:** The connectivity check has a 5-second timeout per host. It checks multiple hosts (google.com, cloudflare.com) in parallel.

### Issue: Screen doesn't update when internet comes back
**Solution:** Make sure you're using `Consumer<ConnectivityService>` or listening to the ConnectivityService provider.
