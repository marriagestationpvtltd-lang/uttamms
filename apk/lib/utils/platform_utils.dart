/// Platform utility helpers for cross-platform (mobile + web) support.
///
/// Import this file wherever you need to conditionally execute
/// platform-specific code.  It provides zero-cost compile-time constants and
/// a small set of helper guards so that the calling code stays readable.
library platform_utils;

import 'package:flutter/foundation.dart' show kIsWeb;

/// True when the app is running inside a browser (Flutter Web).
const bool isWeb = kIsWeb;

/// True when the app is running on a native mobile / desktop platform.
bool get isNative => !kIsWeb;

/// Runs [fn] only on native platforms (Android / iOS / desktop).
/// On web it is a no-op.
void runOnNative(void Function() fn) {
  if (!kIsWeb) fn();
}

/// Returns [value] on native, or [webFallback] on web.
T platformValue<T>(T value, T webFallback) => kIsWeb ? webFallback : value;
