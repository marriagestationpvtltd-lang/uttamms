// Professional Registration Progress Indicator
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../constant/app_colors.dart';
import '../Startup/onboarding.dart';
import '../Auth/SuignupModel/signup_model.dart';

// ---------------------------------------------------------------------------
// Shared back-navigation helpers used by both RegistrationStepHeader and
// RegistrationStepContainer.
// ---------------------------------------------------------------------------

/// Navigates to [OnboardingScreen], clearing the entire navigation stack.
void _navigateToOnboarding(BuildContext context) {
  Navigator.pushAndRemoveUntil(
    context,
    MaterialPageRoute(builder: (_) => const OnboardingScreen()),
    (route) => false,
  );
}

/// Shows a logout-confirmation dialog when the user has a partially registered
/// account.  Returns `true` if the user confirmed logout, `false` to stay.
Future<bool> _showLogoutConfirmation(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        'Registration Incomplete',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: AppColors.textPrimary,
        ),
      ),
      content: const Text(
        'Your registration process is not complete. '
        'Do you want to logout of your account?',
        style: TextStyle(
          fontSize: 14,
          color: AppColors.textSecondary,
          height: 1.5,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text(
            'Stay',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          style: TextButton.styleFrom(foregroundColor: AppColors.primary),
          child: const Text(
            'Logout',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
  return result == true;
}

/// Handles the back-navigation logic shared across all registration screens.
///
/// - If [onStepBack] is provided AND there is a previous route on the stack,
///   navigates to the previous step.
/// - Otherwise (first step, or app restarted mid-registration with no back
///   stack), shows a confirmation dialog before logging out (if bearerToken
///   exists) or navigates to onboarding directly.
Future<void> _handleRegistrationBack(
  BuildContext context,
  SignupModel model, {
  VoidCallback? onStepBack,
}) async {
  // Only use step-back if there is actually a previous route to go back to.
  // When the app is restarted mid-registration the navigation stack only has
  // one entry, so canPop() returns false and we fall through to the logout
  // confirmation instead of popping to a black/empty screen.
  if (onStepBack != null && Navigator.canPop(context)) {
    onStepBack();
    return;
  }

  // No step-back available (or no previous route) – user is trying to exit.
  if (model.bearerToken?.isNotEmpty == true) {
    final shouldLogout = await _showLogoutConfirmation(context);
    if (!shouldLogout) return; // User chose to stay — do nothing.
    await model.logout();
    if (context.mounted) _navigateToOnboarding(context);
  } else {
    _navigateToOnboarding(context);
  }
}

class RegistrationProgress extends StatelessWidget {
  final int currentStep;
  final int totalSteps;

  const RegistrationProgress({
    Key? key,
    required this.currentStep,
    this.totalSteps = 11,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final progress = currentStep / totalSteps;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  height: 8,
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: AppColors.borderLight,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      AppColors.primary,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                '$currentStep/$totalSteps',
                style: const TextStyle(
                  color: AppColors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Step $currentStep of $totalSteps',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              '${(progress * 100).toInt()}% Complete',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// Step Header Component
class RegistrationStepHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final int currentStep;
  final int totalSteps;
  final VoidCallback? onBack;
  final VoidCallback? onStepBack;

  const RegistrationStepHeader({
    Key? key,
    required this.title,
    required this.subtitle,
    required this.currentStep,
    this.totalSteps = 11,
    this.onBack,
    this.onStepBack,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Back button and progress
        Row(
          children: [
            if (onBack != null)
              Container(
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.shadowLight,
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: Consumer<SignupModel>(
                    builder: (context, model, _) {
                      return InkWell(
                        // Use the shared back-navigation helper with onStepBack
                        // to allow step-by-step navigation if provided
                        onTap: () => _handleRegistrationBack(
                          context,
                          model,
                          onStepBack: onStepBack,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        child: const Padding(
                          padding: EdgeInsets.all(12),
                          child: Icon(
                            Icons.arrow_back_ios_new,
                            size: 20,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            if (onBack != null) const SizedBox(width: 16),
            Expanded(
              child: RegistrationProgress(
                currentStep: currentStep,
                totalSteps: totalSteps,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        // Title
        Text(
          title,
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
            height: 1.2,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 6),
        // Subtitle
        Text(
          subtitle,
          style: const TextStyle(
            fontSize: 14,
            color: AppColors.textSecondary,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 20),
        // Decorative divider
        Container(
          width: 48,
          height: 4,
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ],
    );
  }
}

// Step Container - wraps entire step content
class RegistrationStepContainer extends StatelessWidget {
  final Widget child;
  final VoidCallback? onContinue;
  final VoidCallback? onBack;
  final VoidCallback? onStepBack;
  final String continueText;
  final bool isLoading;
  final bool canContinue;
  final ScrollController? scrollController;
  final ScrollPhysics? scrollPhysics;

  const RegistrationStepContainer({
    Key? key,
    required this.child,
    this.onContinue,
    this.onBack,
    this.onStepBack,
    this.continueText = 'Continue',
    this.isLoading = false,
    this.canContinue = true,
    this.scrollController,
    this.scrollPhysics,
  }) : super(key: key);

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Consumer<SignupModel>(
      builder: (context, model, _) {
        return PopScope(
          canPop: false,
          onPopInvoked: (bool didPop) async {
            if (didPop) return;
            await _handleRegistrationBack(
              context,
              model,
              onStepBack: onStepBack,
            );
          },
          child: GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            behavior: HitTestBehavior.translucent,
            child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
              controller: scrollController,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
              physics: scrollPhysics ?? const ClampingScrollPhysics(),
              // Scrollable content only — no keyboard spacer or buttons here.
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                child: child,
              ),
            ),
          ),

            // -----------------------------------------------------------
            // Sticky action-button footer.
            // Lives OUTSIDE the scroll area so it is always visible.
            // When the software keyboard is open, viewInsets.bottom > 0 and
            // the extra bottom padding lifts the footer above the keyboard
            // (Scaffold has resizeToAvoidBottomInset: false on every step).
            // -----------------------------------------------------------
              Container(
                padding: EdgeInsets.fromLTRB(
                  20,
                  20,
                  20,
                  20 + MediaQuery.viewInsetsOf(context).bottom,
                ),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.shadowLight,
                      blurRadius: 12,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: SafeArea(
                  top: false,
                  child: Row(
                    children: [
                      // Back button (only rendered when [onBack] is provided)
                      if (onBack != null) ...[
                        Expanded(
                          flex: 1,
                          child: OutlinedButton(
                            onPressed: isLoading
                                ? null
                                : () {
                                    FocusScope.of(context).unfocus();
                                    _handleRegistrationBack(
                                      context,
                                      model,
                                      onStepBack: onStepBack,
                                    );
                                  },
                            style: OutlinedButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 18),
                              side: const BorderSide(
                                color: AppColors.border,
                                width: 1.5,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: const Text(
                              'Back',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],

                      // Continue button
                      Expanded(
                        flex: 2,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: canContinue
                                ? AppColors.primaryGradient
                                : const LinearGradient(
                                    colors: [
                                      AppColors.borderLight,
                                      AppColors.border,
                                    ],
                                  ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: canContinue
                                ? [
                                    BoxShadow(
                                      color: AppColors.primary
                                          .withOpacity(0.3),
                                      blurRadius: 16,
                                      offset: const Offset(0, 6),
                                    ),
                                  ]
                                : [],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: isLoading
                                  ? null
                                  : () {
                                      FocusScope.of(context).unfocus();
                                      onContinue?.call();
                                    },
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 18),
                                child: Center(
                                  child: isLoading
                                      ? const SizedBox(
                                          height: 24,
                                          width: 24,
                                          child: CircularProgressIndicator(
                                            color: AppColors.white,
                                            strokeWidth: 2.5,
                                          ),
                                        )
                                      : Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              continueText,
                                              style: TextStyle(
                                                color: canContinue
                                                    ? AppColors.white
                                                    : AppColors
                                                        .textSecondary,
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                                letterSpacing: 0.3,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Icon(
                                              Icons.arrow_forward_ios,
                                              size: 16,
                                              color: canContinue
                                                  ? AppColors.white
                                                  : AppColors.textSecondary,
                                            ),
                                          ],
                                        ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          ),
        );
      },
    );
  }
}
