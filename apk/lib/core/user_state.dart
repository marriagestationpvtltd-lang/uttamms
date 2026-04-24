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

  /// Canonical value for an identity document that has never been submitted.
  static const String statusNotUploaded = 'not_uploaded';

  String _identityStatus = statusNotUploaded;
  String _usertype = 'free';
  bool _isVerified = false;

  /// Document-verification status.
  /// One of: `'not_uploaded'`, `'pending'`, `'approved'`, `'rejected'`.
  String get identityStatus => _identityStatus;

  /// `true` when the user has ALL required documents approved (identity + marital).
  /// This value comes from the backend and considers both identity and marital documents.
  bool get isVerified => _isVerified;

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
        _isVerified = data['is_verified'] as bool? ?? false;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('UserState.loadFromCache error: $e');
    }
  }

  // ── Update from already-fetched masterdata ───────────────────────────────

  /// Updates verification and subscription state from data that the caller has
  /// already retrieved from `masterdata.php`, avoiding an extra network round-trip.
  ///
  /// Screens that call `masterdata.php` for profile data (e.g. profile picture,
  /// page number) should call this method with the `docStatus`, `isVerified`, and `usertype`
  /// values from the same response so that [UserState] stays in sync without a
  /// second API call.
  void updateFromMasterData(String docStatus, bool isVerified, String usertype) {
    final changed = _identityStatus != docStatus || _isVerified != isVerified || _usertype != usertype;
    if (!changed) return;
    _identityStatus = docStatus;
    _isVerified = isVerified;
    _usertype = usertype;
    // Persist the updated values so they survive an app restart.
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString(
        _cacheKey,
        jsonEncode({
          'identity_status': _identityStatus,
          'is_verified': _isVerified,
          'usertype': _usertype,
        }),
      );
    }).catchError((e) {
      debugPrint('UserState.updateFromMasterData persist error: $e');
    });
    notifyListeners();
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
          // masterdata.php now returns `docstatus` for identity document status,
          // `is_verified` for overall verification status (identity + marital docs),
          // and `usertype` for the subscription type.
          final docStatus = data['docstatus'] as String? ?? 'not_uploaded';
          final isVerified = data['is_verified'] as bool? ?? false;
          final usertype = data['usertype'] as String? ?? 'free';

          _identityStatus = docStatus;
          _isVerified = isVerified;
          _usertype = usertype;

          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(
            _cacheKey,
            jsonEncode({
              'identity_status': _identityStatus,
              'is_verified': _isVerified,
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
    _identityStatus = statusNotUploaded;
    _isVerified = false;
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
