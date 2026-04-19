import 'package:flutter/material.dart';

import 'HomeScreenPage.dart';

class AppRestartHelper {
  static void restartApp(BuildContext context) {
    // For Android/iOS
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (context) => PopScope(
            canPop: false, // Prevent going back
            child: MatrimonyHomeScreen(), // Your home screen
          ),
        ),
            (route) => false,
      );
    });
  }
}