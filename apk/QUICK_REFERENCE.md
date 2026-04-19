# Quick Reference: Internet Connectivity Integration

## तुरुन्त प्रयोग गर्न (Quick Start)

### 1. API Call गर्नु अघि Internet Check
```dart
import 'package:ms2026/utils/network_helper.dart';

// Method 1: Simple check
final hasInternet = await NetworkHelper.checkConnectivity(context);
if (!hasInternet) return; // Auto-shows error message

// Method 2: With navigation to no-internet screen
final hasInternet = await NetworkHelper.checkConnectivity(
  context,
  navigateToNoInternet: true,
);

// Method 3: Silent check (no message)
final hasInternet = await NetworkHelper.checkConnectivity(
  context,
  showMessage: false,
);
```

### 2. API Call लाई Automatic Wrap गर्नुहोस्
```dart
final result = await NetworkHelper.executeWithConnectivityCheck(
  context,
  apiCall: () async {
    final response = await http.get(url);
    return jsonDecode(response.body);
  },
);

if (result != null) {
  // Success - process result
} else {
  // No internet or API failed
}
```

### 3. Screen लाई Protect गर्नुहोस्
```dart
import 'package:ms2026/widgets/connectivity_wrapper.dart';

@override
Widget build(BuildContext context) {
  return ConnectivityWrapper(
    child: Scaffold(
      appBar: AppBar(title: Text('My Screen')),
      body: YourContent(),
    ),
  );
}
```

### 4. Loading Dialog with Connectivity Status
```dart
// Show
NetworkHelper.showLoadingDialog(context, message: 'Saving...');

// Your work
await Future.delayed(Duration(seconds: 2));

// Dismiss
NetworkHelper.dismissLoadingDialog(context);
```

### 5. Manual Navigation to No Internet Screen
```dart
import 'package:ms2026/screens/no_internet_screen.dart';

Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => NoInternetScreen(
      onRetry: () {
        Navigator.pop(context);
        fetchData(); // Your retry logic
      },
    ),
  ),
);
```

## Common Patterns

### Pattern A: Simple API Call
```dart
Future<void> fetchData() async {
  final hasInternet = await NetworkHelper.checkConnectivity(context);
  if (!hasInternet) return;

  setState(() => _isLoading = true);

  try {
    final response = await http.get(url);
    final data = jsonDecode(response.body);
    setState(() {
      _data = data;
      _isLoading = false;
    });
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('त्रुटि: $e')),
      );
    }
    setState(() => _isLoading = false);
  }
}
```

### Pattern B: With Loading Dialog
```dart
Future<void> saveData() async {
  final hasInternet = await NetworkHelper.checkConnectivity(context);
  if (!hasInternet) return;

  NetworkHelper.showLoadingDialog(context, message: 'Saving...');

  try {
    await http.post(url, body: data);
    NetworkHelper.dismissLoadingDialog(context);
    // Show success message
  } catch (e) {
    NetworkHelper.dismissLoadingDialog(context);
    // Show error message
  }
}
```

### Pattern C: Automatic Handling
```dart
Future<void> loadProfile() async {
  final profile = await NetworkHelper.executeWithConnectivityCheck(
    context,
    apiCall: () async {
      final response = await http.get(profileUrl);
      return Profile.fromJson(jsonDecode(response.body));
    },
  );

  if (profile != null) {
    setState(() => _profile = profile);
  }
}
```

## ConnectivityService Direct Access

```dart
import 'package:provider/provider.dart';
import 'package:ms2026/service/connectivity_service.dart';

// In your widget
final connectivity = Provider.of<ConnectivityService>(context, listen: false);

// Check status
if (connectivity.isConnected) {
  // Has internet
}

if (connectivity.isWifiConnected) {
  // WiFi is on
}

if (connectivity.isMobileConnected) {
  // Mobile data is on
}

// Get connection type
String type = connectivity.getConnectionType(); // "WiFi", "Mobile Data", etc.

// Manual check
bool hasInternet = await connectivity.checkConnectivity();
```

## Listen to Connectivity Changes

```dart
@override
Widget build(BuildContext context) {
  return Consumer<ConnectivityService>(
    builder: (context, connectivity, child) {
      if (!connectivity.isConnected) {
        return NoInternetWidget();
      }
      return YourNormalWidget();
    },
  );
}
```

## File Locations

```
lib/
├── service/
│   └── connectivity_service.dart     # Core service
├── screens/
│   └── no_internet_screen.dart       # No internet UI
├── widgets/
│   └── connectivity_wrapper.dart     # Wrapper widget
└── utils/
    └── network_helper.dart            # Helper functions
```

## Import Statements

```dart
// For NetworkHelper
import 'package:ms2026/utils/network_helper.dart';

// For NoInternetScreen
import 'package:ms2026/screens/no_internet_screen.dart';

// For ConnectivityWrapper
import 'package:ms2026/widgets/connectivity_wrapper.dart';

// For ConnectivityService (usually not needed, use NetworkHelper instead)
import 'package:ms2026/service/connectivity_service.dart';
import 'package:provider/provider.dart';
```

## Error Messages (Nepali)

```dart
'इन्टरनेट जडान छैन'                          // No internet connection
'WiFi जडान भएको छ तर इन्टरनेट छैन'           // WiFi connected but no internet
'मोबाइल डाटा जडान भएको छ तर इन्टरनेट छैन'   // Mobile data connected but no internet
'पुन: प्रयास गर्नुहोस्'                    // Retry
'सेटिङ्ग खोल्नुहोस्'                        // Open settings
'कृपया पर्खनुहोस्...'                      // Please wait...
'त्रुटि'                                   // Error
```

## Testing Checklist

- [ ] WiFi connected, internet working
- [ ] WiFi connected, no internet (disable router internet)
- [ ] Mobile data connected, internet working
- [ ] Mobile data connected, no internet (disable mobile data from network)
- [ ] Airplane mode
- [ ] Switch from WiFi to Mobile Data
- [ ] Switch from Mobile Data to WiFi
- [ ] Internet lost during API call
- [ ] Internet restored during no-internet screen
- [ ] Settings button navigation
- [ ] Retry button functionality

## Performance Notes

- Internet check timeout: 5 seconds per host
- Two hosts checked in parallel: google.com, cloudflare.com
- Connectivity service runs in background
- Updates every connectivity change
- Minimal battery impact

## Support

For issues or questions, refer to:
- `CONNECTIVITY_GUIDE.md` - Detailed integration guide
- `SOLUTION_SUMMARY_NP.md` - Complete solution documentation
