import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  /// Uses a two-stage check to avoid false failures caused by stale cached
  /// state (e.g. the admin approved documents while the app was running):
  ///
  /// 1. Fast path — if [UserState.isVerified] is already `true`, return
  ///    immediately without a network round-trip.
  /// 2. Slow path — if the cached state says unverified, fetch fresh data
  ///    from the server before deciding.  Only shows the "Verification
  ///    Required" dialog when the server also reports the user as unverified.
  ///
  /// If not verified, shows an informational dialog (with a "Verify Now"
  /// button for unsubmitted/rejected documents) and returns `false`.
  static Future<bool> requireVerification(BuildContext context) async {
    try {
      final userState = context.read<UserState>();

      // Fast path: already verified in cache — no network call needed.
      if (userState.isVerified) return true;

      // Slow path: refresh from the server before showing the popup, in case
      // the admin approved documents since the cached state was last written.
      try {
        final prefs = await SharedPreferences.getInstance();
        final userDataString = prefs.getString('user_data');
        if (userDataString != null) {
          final data = jsonDecode(userDataString) as Map<String, dynamic>;
          final userId = int.tryParse(data['id']?.toString() ?? '');
          if (userId != null) {
            await userState.refresh(userId);
          }
        }
      } catch (e) {
        debugPrint('VerificationService.requireVerification: refresh error – $e');
      }

      if (!context.mounted) return false;
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
            Expanded(
              child: Text(
                isPending
                    ? 'Waiting for account approval'
                    : 'Verification Required',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Text(
          isPending
              ? 'Your account is under review. You will be notified '
                  'once your account is approved.'
              : 'Please verify your identity document to use this '
                  'feature.',
          style: const TextStyle(fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
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

