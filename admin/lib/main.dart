import 'package:adminmrz/core/app_theme.dart';
import 'package:adminmrz/payment/paymentprovider.dart';
import 'package:adminmrz/users/userprovider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:provider/provider.dart';
import 'adminchat/chatprovider.dart';
import 'adminchat/services/MatchedProfileService.dart';
import 'adminchat/services/callmanager.dart';
import 'adminchat/services/web_notification_service.dart';
import 'auth/dashboard.dart';
import 'requests/request_provider.dart';
import 'settings/call_settings_provider.dart';
import 'auth/login.dart';
import 'auth/service.dart';
import 'core/theme_provider.dart';
import 'document/docprovider/docservice.dart';
import 'firebase_options.dart';
import 'package/packageProvider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'dart:html' as html;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  setUrlStrategy(PathUrlStrategy());
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (error) {
    debugPrint('Firebase init skipped: $error');
  }

  WebNotificationService.ensurePermissionOnUserGesture();

  // Request browser notification permission so background notifications work.
  await WebNotificationService.requestPermission();

  runApp(const MyApp());
}



class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (context) => AuthProvider()),
        ChangeNotifierProvider(create: (context) => DocumentsProvider()),
        ChangeNotifierProvider(create: (context) => UserProvider()),
        ChangeNotifierProvider(create: (_) => PackageProvider()),
        ChangeNotifierProvider(create: (_) => PaymentProvider()),
        ChangeNotifierProvider(create: (context) => ChatProvider()),
        ChangeNotifierProvider(create: (context) => MatchedProfileProvider()),
        ChangeNotifierProvider(create: (_) => CallManager()),
        ChangeNotifierProvider(create: (_) => CallSettingsProvider()),
        ChangeNotifierProvider(create: (_) => RequestProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) => MaterialApp(
          title: 'Admin Panel',
          themeMode: themeProvider.themeMode,
          theme: buildLightTheme(),
          darkTheme: buildDarkTheme(),
          debugShowCheckedModeBanner: false,
          home: Consumer<AuthProvider>(
            builder: (context, authProvider, _) {
              return authProvider.isAuthenticated
                  ? const DashboardPage()
                  : const LoginPage();
            },
          ),
        ),
      ),
    );
  }
}

class ErrorApp extends StatelessWidget {
  final String error;

  const ErrorApp({Key? key, required this.error}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.error_outline,
                  color: Colors.red,
                  size: 64,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Firebase Initialization Failed',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  error,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    if (kIsWeb) {
                      html.window.location.reload();
                    }
                  },
                  child: const Text('Refresh Page'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
