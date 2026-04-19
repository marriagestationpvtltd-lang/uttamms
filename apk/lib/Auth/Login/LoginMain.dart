import 'package:flutter/material.dart';
import '../../constant/app_colors.dart';
import '../../constant/app_dimensions.dart';
import '../../constant/app_text_styles.dart';
import 'Email.dart';
import 'ohonelogin.dart';

class LoginScreens extends StatefulWidget {
  const LoginScreens({super.key});

  @override
  State<LoginScreens> createState() => _LoginScreensState();
}

class _LoginScreensState extends State<LoginScreens> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: const [
          PrefilledEmailScreen(),
          MobileLoginScreen(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textSecondary,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.email),
            label: 'Email Login',
          ),

          BottomNavigationBarItem(
            icon: Icon(Icons.phone),
            label: 'Mobile Login',
          ),
        ],
      ),
    );
  }
}