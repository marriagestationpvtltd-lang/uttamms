import 'package:flutter/foundation.dart';

/// Lightweight in-app signal for favorite/shortlist changes.
/// Any screen can listen and refresh its local data immediately.
class FavoriteSyncService {
  FavoriteSyncService._();

  static final ValueNotifier<int> _version = ValueNotifier<int>(0);

  static ValueListenable<int> get changes => _version;

  static void notifyChanged() {
    _version.value = _version.value + 1;
  }
}
