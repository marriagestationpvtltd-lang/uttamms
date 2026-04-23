import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../Auth/Screen/signupscreen10.dart';
import '../constant/app_colors.dart';
import '../config/app_endpoints.dart';
import '../core/user_state.dart';

/// Guard helper for verification-gated features.
///
/// The [instance] singleton is retained for backward compatibility with
/// code that cannot easily access a [BuildContext].  New code should prefer
/// reading from the [UserState] provider directly.
class VerificationService {
  VerificationService._();
  static final VerificationService instance = VerificationService._();

  static const String _cacheKey = 'verification_status_cache';

  // ── in-memory state ──────────────────────────────────────────────────────
  /// Status of the most recently uploaded identity document.
  /// One of: `'not_uploaded'`, `'pending'`, `'approved'`, `'rejected'`.
  String _identityStatus = 'not_uploaded';

  /// `true` when the user has at least one approved identity document.
  bool _isVerified = false;

  String get identityStatus => _identityStatus;
  bool get isVerified => _isVerified;

  // ── load from SharedPreferences (fast, zero network) ─────────────────────
  Future<void> loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_cacheKey);
      if (cached != null) {
        final data = jsonDecode(cached) as Map<String, dynamic>;
        _identityStatus =
            data['identity_status'] as String? ?? 'not_uploaded';
        _isVerified = data['is_verified'] == true;
      }
    } catch (e) {
      debugPrint('VerificationService.loadFromCache error: $e');
    }
  }

  // ── fetch from server and update cache ───────────────────────────────────
  Future<void> refresh(int userId) async {
    try {
      final response = await http
          .post(
            Uri.parse('${kApiBaseUrl}/Api2/check_document_status.php'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'user_id': userId}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final result =
            jsonDecode(response.body) as Map<String, dynamic>;
        if (result['success'] == true) {
          _identityStatus =
              result['identity_status'] as String? ?? 'not_uploaded';
          _isVerified = result['is_verified'] == true;

          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(
            _cacheKey,
            jsonEncode({
              'identity_status': _identityStatus,
              'is_verified': _isVerified,
            }),
          );
        }
      }
    } catch (e) {
      debugPrint('VerificationService.refresh error: $e');
    }
  }

  // ── clear on sign-out ────────────────────────────────────────────────────
  Future<void> clear() async {
    _identityStatus = 'not_uploaded';
    _isVerified = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey);
    } catch (e) {
      debugPrint('VerificationService.clear error: $e');
    }
  }

  // ── guard helper ─────────────────────────────────────────────────────────
  /// Returns `true` when the user is verified so the caller may proceed.
  ///
  /// Reads verification status from the global [UserState] provider so that
  /// the check always reflects the latest refreshed value.  Falls back to
  /// the local singleton state when no [UserState] is available in the tree.
  ///
  /// If not verified, shows an informational dialog (with a "Verify Now"
  /// button for unsubmitted/rejected documents) and returns `false`.
  static bool requireVerification(BuildContext context) {
    // Prefer the global provider so the check is always up-to-date.
    try {
      final userState = context.read<UserState>();
      if (userState.isVerified) return true;
      _showVerificationRequired(context, userState.identityStatus);
      return false;
    } catch (_) {
      // Fallback: provider not available (e.g. in tests or deep navigator routes).
      if (instance.isVerified) return true;
      _showVerificationRequired(context, instance.identityStatus);
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

