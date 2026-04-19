import 'package:flutter/material.dart';
import 'package:ms2026/Auth/Login/LoginMain.dart';
import 'package:ms2026/Auth/Screen/Signup.dart';
import 'package:ms2026/constant/app_colors.dart';
import 'package:ms2026/constant/app_dimensions.dart';
import 'package:ms2026/constant/app_text_styles.dart';
import '../../ReUsable/terms_dialog.dart';

class MobileLoginScreen extends StatelessWidget {
  const MobileLoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Login And Find A Partner For Yourself.',
              style: AppTextStyles.heading2.copyWith(
                color: AppColors.primary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppDimensions.spacingXXL),

            // Mobile Number Field
            TextFormField(
              keyboardType: TextInputType.phone,
              style: AppTextStyles.bodyLarge,
              decoration: InputDecoration(
                labelText: 'Mobile Number',
                labelStyle: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
                floatingLabelStyle: AppTextStyles.labelMedium.copyWith(color: AppColors.primary),
                border: OutlineInputBorder(
                  borderRadius: AppDimensions.borderRadiusMD,
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: AppDimensions.borderRadiusMD,
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: AppDimensions.borderRadiusMD,
                  borderSide: const BorderSide(color: AppColors.primary, width: 2),
                ),
                prefixIcon: const Icon(Icons.phone, color: AppColors.textSecondary, size: AppDimensions.iconSizeSM),
              ),
            ),
            const SizedBox(height: AppDimensions.spacingMD),

            // OTP Field
            TextFormField(
              keyboardType: TextInputType.number,
              style: AppTextStyles.bodyLarge,
              decoration: InputDecoration(
                labelText: 'OTP',
                labelStyle: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
                floatingLabelStyle: AppTextStyles.labelMedium.copyWith(color: AppColors.primary),
                border: OutlineInputBorder(
                  borderRadius: AppDimensions.borderRadiusMD,
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: AppDimensions.borderRadiusMD,
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: AppDimensions.borderRadiusMD,
                  borderSide: const BorderSide(color: AppColors.primary, width: 2),
                ),
                prefixIcon: const Icon(Icons.sms, color: AppColors.textSecondary, size: AppDimensions.iconSizeSM),
              ),
            ),
            const SizedBox(height: AppDimensions.spacingSM),

            // Send OTP Button
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {},
                style: TextButton.styleFrom(foregroundColor: AppColors.primary),
                child: Text('Send OTP', style: AppTextStyles.primaryLabel),
              ),
            ),
            const SizedBox(height: AppDimensions.spacingMD),

            // Login Button
            SizedBox(
              width: double.infinity,
              height: AppDimensions.buttonHeightMD,
              child: Container(
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: AppDimensions.borderRadiusMD,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: AppDimensions.borderRadiusMD,
                    onTap: () {
                      // Your login logic here
                    },
                    child: Center(
                      child: Text('Login', style: AppTextStyles.whiteLabel),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppDimensions.spacingMD),

            // Divider with "or"
            Row(
              children: [
                const Expanded(child: Divider(color: AppColors.border)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spacingMD),
                  child: Text('or', style: AppTextStyles.caption),
                ),
                const Expanded(child: Divider(color: AppColors.border)),
              ],
            ),
            const SizedBox(height: AppDimensions.spacingMD),

            // Login With Email
            SizedBox(
              width: double.infinity,
              height: AppDimensions.buttonHeightMD,
              child: OutlinedButton(
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (context) => LoginScreens()));
                },
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.border),
                  shape: RoundedRectangleBorder(borderRadius: AppDimensions.borderRadiusMD),
                  foregroundColor: AppColors.textPrimary,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.email, size: AppDimensions.iconSizeSM),
                    const SizedBox(width: AppDimensions.spacingSM),
                    Text('Login With Email', style: AppTextStyles.labelMedium),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppDimensions.spacingXXL),

            // Register Link
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text("Don't have an account?", style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
                TextButton(
                  onPressed: () async {
                    final accepted = await TermsConditionsBottomSheet.show(context);
                    if (!context.mounted) return;
                    if (accepted) {
                      Navigator.push(context, MaterialPageRoute(builder: (context) => const IntroduceYourselfPage()));
                    }
                  },
                  style: TextButton.styleFrom(foregroundColor: AppColors.primary),
                  child: Text('Register', style: AppTextStyles.primaryLabel),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}