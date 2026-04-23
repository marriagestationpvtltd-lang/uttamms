import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_endpoints.dart';

/// Centralized user state that is the single source of truth for the current
/// user's document-verification status and package/subscription type.
///
/// Register as a [ChangeNotifierProvider] in [main.dart] and refresh it:
///   * after login / splash screen (call [loadFromCache] then [refresh])
///   * whenever a screen that gates features becomes visible (call [refresh])
///   * on logout (call [clear])
///
/// Screens read [isVerified] and [hasPackage] instead of making their own
/// API calls, eliminating duplicate network requests and stale local state.
class UserState extends ChangeNotifier {
  static const String _cacheKey = 'user_state_cache';

  String _identityStatus = 'not_uploaded';
  String _usertype = 'free';

  /// Document-verification status.
  /// One of: `'not_uploaded'`, `'pending'`, `'approved'`, `'rejected'`.
  String get identityStatus => _identityStatus;

  /// `true` when the user has an approved identity document.
  bool get isVerified => _identityStatus == 'approved';

  /// Subscription type – `'free'` or `'paid'`.
  String get usertype => _usertype;

  /// `true` when the user has an active paid package.
  bool get hasPackage => _usertype == 'paid';

  // ── Load from SharedPreferences (fast, zero network) ─────────────────────

  Future<void> loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_cacheKey);
      if (cached != null) {
        final data = jsonDecode(cached) as Map<String, dynamic>;
        _identityStatus =
            data['identity_status'] as String? ?? 'not_uploaded';
        _usertype = data['usertype'] as String? ?? 'free';
        notifyListeners();
      }
    } catch (e) {
      debugPrint('UserState.loadFromCache error: $e');
    }
  }

  // ── Fetch from server and update cache ───────────────────────────────────

  /// Fetches fresh state from `masterdata.php` for [userId] and persists it.
  Future<void> refresh(int userId) async {
    try {
      final response = await http
          .get(
            Uri.parse('${kApiBaseUrl}/Api2/masterdata.php?userid=$userId'),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body) as Map<String, dynamic>;
        if (result['success'] == true) {
          final data = result['data'] as Map<String, dynamic>;
          // masterdata.php returns `docstatus` for the document status and
          // `usertype` for the subscription type.
          final docStatus = data['docstatus'] as String? ?? 'not_uploaded';
          final usertype = data['usertype'] as String? ?? 'free';

          _identityStatus = docStatus;
          _usertype = usertype;

          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(
            _cacheKey,
            jsonEncode({
              'identity_status': _identityStatus,
              'usertype': _usertype,
            }),
          );

          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('UserState.refresh error: $e');
    }
  }

  // ── Clear on sign-out ────────────────────────────────────────────────────

  Future<void> clear() async {
    _identityStatus = 'not_uploaded';
    _usertype = 'free';
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey);
    } catch (e) {
      debugPrint('UserState.clear error: $e');
    }
    notifyListeners();
  }
}
