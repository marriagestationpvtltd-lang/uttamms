import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../Auth/Screen/signupscreen10.dart';
import '../constant/app_colors.dart';
import '../core/user_state.dart';

/// Guard helper for verification-gated features.
///
/// Verification state is managed exclusively by [UserState], which is loaded
/// once after login (via [UserState.loadFromCache] + [UserState.refresh]) and
/// acts as the single source of truth across all screens.  Screens must NOT
/// make their own calls to `check_document_status.php` for gate checks; they
/// should read [UserState.isVerified] directly or call
/// [VerificationService.requireVerification].
class VerificationService {
  VerificationService._();

  // ── guard helper ─────────────────────────────────────────────────────────
  /// Returns `true` when the user is verified so the caller may proceed.
  ///
  /// Reads verification status from the global [UserState] provider so that
  /// the check always reflects the latest refreshed value.
  ///
  /// If not verified, shows an informational dialog (with a "Verify Now"
  /// button for unsubmitted/rejected documents) and returns `false`.
  static bool requireVerification(BuildContext context) {
    try {
      final userState = context.read<UserState>();
      if (userState.isVerified) return true;
      _showVerificationRequired(context, userState.identityStatus);
      return false;
    } catch (e) {
      // UserState is not in the widget tree (e.g. tests or detached routes).
      // Fail closed: treat the user as unverified.
      debugPrint('VerificationService.requireVerification: UserState not found – $e');
      return false;
    }
  }

  static void _showVerificationRequired(
      BuildContext context, String status) {
    final isPending = status == 'pending';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              isPending
                  ? Icons.hourglass_top_rounded
                  : Icons.verified_user_rounded,
              color: isPending
                  ? const Color(0xFFF57C00)
                  : AppColors.primary,
              size: 22,
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Verification Required',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Text(
          isPending
              ? 'Your identity document is under review. '
                  'This feature will be available once your document '
                  'is verified.'
              : 'Please verify your identity document to use this '
                  'feature.',
          style: const TextStyle(fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          if (!isPending)
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => IDVerificationScreen()),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Verify Now'),
            ),
        ],
      ),
    );
  }
}

