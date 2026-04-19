import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ConnectivityService extends ChangeNotifier {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _delayedRecheckTimer;

  /// Periodic timer that polls every [_autoRecoveryInterval] seconds while we
  /// believe we are offline but a network interface (WiFi / mobile) is still
  /// present.  connectivity_plus only fires events when the interface changes,
  /// so without this timer the app would stay "no internet" even after the
  /// actual internet access is restored on the same interface.
  Timer? _autoRecoveryTimer;
  static const Duration _autoRecoveryInterval = Duration(seconds: 5);

  List<ConnectivityResult> _connectionStatus = [];
  bool _hasInternet = true;
  bool _isChecking = false;

  /// Set to true when a connectivity change arrives while a probe is already
  /// running.  After the probe finishes the service schedules an immediate
  /// re-check so the missed event is not silently dropped.
  bool _pendingCheck = false;

  /// Guard that prevents the auto-recovery timer callback from spawning
  /// overlapping probe runs if a single probe takes longer than the polling
  /// interval.
  bool _autoRecoveryRunning = false;

  int _consecutiveProbeFailures = 0;
  DateTime? _startupGraceUntil;

  List<ConnectivityResult> get connectionStatus => _connectionStatus;
  bool get hasInternet => _hasInternet;
  bool get isWifiConnected => _connectionStatus.contains(ConnectivityResult.wifi);
  bool get isMobileConnected => _connectionStatus.contains(ConnectivityResult.mobile);

  /// Returns true when connected.  Before [initialize] completes we treat the
  /// state as "undetermined" and optimistically report connected so that the
  /// connectivity banner never flickers offline→online on a normal launch.
  bool get isConnected {
    if (_connectionStatus.isEmpty) return true; // not yet initialised
    return _hasInternet && !_connectionStatus.contains(ConnectivityResult.none);
  }

  /// Whether a network interface (WiFi or mobile) is present but we currently
  /// believe actual internet access is absent.  This is the condition under
  /// which we should keep polling so we can auto-recover.
  bool get _shouldAutoRecover =>
      !_hasInternet && !_connectionStatus.contains(ConnectivityResult.none);

  /// Initialize connectivity monitoring
  Future<void> initialize() async {
    try {
      _startupGraceUntil = DateTime.now().add(const Duration(seconds: 15));
      // Get initial status
      _connectionStatus = await _connectivity.checkConnectivity();
      await _checkActualInternetConnection();

      // Listen to connectivity changes
      _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
        (List<ConnectivityResult> result) async {
          _connectionStatus = result;
          await _checkActualInternetConnection();
          notifyListeners();

          if (kDebugMode) {
            print('📡 Connectivity changed: $_connectionStatus, Internet: $_hasInternet');
          }
        },
      );
    } catch (e) {
      if (kDebugMode) {
        print('❌ Connectivity service initialization error: $e');
      }
      // Populate the status list so isConnected no longer returns the
      // optimistic "not yet initialised" value.
      if (_connectionStatus.isEmpty) {
        _connectionStatus = [ConnectivityResult.none];
      }
      _hasInternet = false;
      notifyListeners();
    }
  }

  /// Check actual internet connection by trying to reach a reliable server
  Future<bool> _checkActualInternetConnection() async {
    if (_isChecking) {
      // Queue a re-check so that a connectivity change arriving while a probe
      // is already running is never silently dropped.
      _pendingCheck = true;
      return _hasInternet;
    }

    if (_connectionStatus.contains(ConnectivityResult.none)) {
      _consecutiveProbeFailures = 0;
      _hasInternet = false;
      _stopAutoRecoveryTimer();
      notifyListeners();
      return _hasInternet;
    }

    _isChecking = true;
    try {
      // Try multiple reliable endpoints in parallel.  We use lightweight
      // generate_204 / HEAD-style probes that return quickly on success.
      // Cloudflare 1.1.1.1 and Google DNS are reachable even in regions where
      // other Google services may be throttled.
      final results = await Future.wait([
        _checkHost(Uri.https('connectivitycheck.gstatic.com', '/generate_204')),
        _checkHost(Uri.https('www.gstatic.com', '/generate_204')),
        _checkHost(Uri.https('one.one.one.one', '/')),
        _checkHost(Uri.https('dns.google', '/')),
      ]);

      final hasInternetNow = results.any((result) => result);

      if (hasInternetNow) {
        _consecutiveProbeFailures = 0;
        _hasInternet = true;
        _stopAutoRecoveryTimer();
      } else {
        _consecutiveProbeFailures += 1;
        final inStartupGrace = _startupGraceUntil != null &&
            DateTime.now().isBefore(_startupGraceUntil!);
        // Require 3 consecutive failures (was 2) before declaring offline to
        // reduce transient false positives.
        final shouldKeepPreviousOnlineState = _hasInternet &&
            (_consecutiveProbeFailures < 3 || inStartupGrace);

        if (shouldKeepPreviousOnlineState) {
          _scheduleDelayedRecheck();
        } else {
          _hasInternet = false;
          _startAutoRecoveryTimer();
        }
      }
    } catch (e) {
      _consecutiveProbeFailures += 1;
      if (!_hasInternet || _consecutiveProbeFailures >= 3) {
        _hasInternet = false;
        _startAutoRecoveryTimer();
      } else {
        _scheduleDelayedRecheck();
      }
      if (kDebugMode) {
        print('❌ Internet check error: $e');
      }
    } finally {
      _isChecking = false;

      // If a new connectivity event arrived while we were probing, re-run
      // immediately so the missed event takes effect.
      if (_pendingCheck) {
        _pendingCheck = false;
        // Defer with scheduleMicrotask to avoid re-entrancy while still inside
        // the finally block.
        scheduleMicrotask(_checkActualInternetConnection);
      }
    }

    notifyListeners();
    return _hasInternet;
  }

  /// Check if a specific endpoint is reachable.
  /// Uses HTTP GET on all platforms (avoids dart:io dependency on web).
  Future<bool> _checkHost(Uri uri) async {
    try {
      if (kIsWeb) {
        // On web, trust connectivity_plus; InternetAddress.lookup is unavailable.
        return !_connectionStatus.contains(ConnectivityResult.none);
      }
      final response = await http.get(uri).timeout(const Duration(seconds: 3));
      return response.statusCode >= 200 && response.statusCode < 500;
    } catch (_) {
      return false;
    }
  }

  void _scheduleDelayedRecheck() {
    _delayedRecheckTimer?.cancel();
    _delayedRecheckTimer = Timer(const Duration(seconds: 2), () {
      _checkActualInternetConnection();
    });
  }

  /// Start the periodic auto-recovery timer.  While the app is offline but a
  /// network interface is present, we poll every [_autoRecoveryInterval] so
  /// that we detect internet restoration without relying on connectivity_plus
  /// firing another event.
  void _startAutoRecoveryTimer() {
    if (_autoRecoveryTimer?.isActive ?? false) return;
    _autoRecoveryTimer = Timer.periodic(_autoRecoveryInterval, (_) async {
      if (!_shouldAutoRecover) {
        _stopAutoRecoveryTimer();
        return;
      }
      // Guard against overlapping runs when a probe takes longer than the
      // polling interval.
      if (_autoRecoveryRunning) return;
      _autoRecoveryRunning = true;
      try {
        _connectionStatus = await _connectivity.checkConnectivity();
        await _checkActualInternetConnection();
      } finally {
        _autoRecoveryRunning = false;
      }
    });
  }

  void _stopAutoRecoveryTimer() {
    _autoRecoveryTimer?.cancel();
    _autoRecoveryTimer = null;
    _autoRecoveryRunning = false;
  }

  /// Manual check for internet connectivity (use before important API calls)
  Future<bool> checkConnectivity() async {
    _connectionStatus = await _connectivity.checkConnectivity();
    return await _checkActualInternetConnection();
  }

  /// Get connection type as string (for display)
  String getConnectionType() {
    if (!_hasInternet) return 'No Internet';
    if (_connectionStatus.contains(ConnectivityResult.wifi)) return 'WiFi';
    if (_connectionStatus.contains(ConnectivityResult.mobile)) return 'Mobile Data';
    if (_connectionStatus.contains(ConnectivityResult.ethernet)) return 'Ethernet';
    if (_connectionStatus.contains(ConnectivityResult.vpn)) return 'VPN';
    return 'Unknown';
  }

  /// Dispose subscription when not needed
  void dispose() {
    _connectivitySubscription?.cancel();
    _delayedRecheckTimer?.cancel();
    _stopAutoRecoveryTimer();
    super.dispose();
  }
}
