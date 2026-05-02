import 'package:flutter/foundation.dart' show kIsWeb;

// ---------------------------------------------------------------------------
// Auto-detects the server host from the browser URL when running as web.
// This means the app works on ANY IP/hostname without code changes — API calls
// are same-origin so CORS headers are never needed.
// For mobile/desktop the env var ADMIN_API_BASE_URL is used, or the fallback.
// ---------------------------------------------------------------------------

// Fallback IP used during `flutter run` dev server and mobile/desktop builds.
const String _kFallbackIp = '192.168.1.4';

/// Returns true when the page is being served by Flutter's own dev server
/// (e.g. flutter run -d chrome) which runs on localhost with a high port.
/// In that case the PHP backend is on Apache, not on localhost, so we must
/// use the real server IP instead of auto-detecting from Uri.base.
bool _isFlutterDevServer(Uri uri) =>
    uri.host == 'localhost' && uri.hasPort && uri.port > 1024;

String _deriveAdminApiBaseUrl() {
  if (kIsWeb) {
    final uri = Uri.base;
    // Flutter dev server → use localhost (same machine as XAMPP) for same-origin requests
    if (_isFlutterDevServer(uri)) {
      return 'http://localhost/uttamms/Backend';
    }
    // Production build served from Apache → same-origin, no CORS needed
    final scheme = uri.scheme.isNotEmpty ? uri.scheme : 'http';
    final host = uri.host.isNotEmpty ? uri.host : _kFallbackIp;
    final portStr = (uri.hasPort && uri.port != 80 && uri.port != 443)
        ? ':${uri.port}'
        : '';
    return '$scheme://$host$portStr/uttamms/Backend';
  }
  const envVal = String.fromEnvironment('ADMIN_API_BASE_URL', defaultValue: '');
  return envVal.isNotEmpty ? envVal : 'http://$_kFallbackIp/uttamms/Backend';
}

final String kAdminApiBaseUrl = _deriveAdminApiBaseUrl();

String _deriveAdminSocketBaseUrl() {
  if (kIsWeb) {
    final uri = Uri.base;
    if (_isFlutterDevServer(uri)) {
      return 'http://localhost:3001';
    }
    final scheme = uri.scheme == 'https' ? 'https' : 'http';
    final host = uri.host.isNotEmpty ? uri.host : _kFallbackIp;
    return '$scheme://$host:3001';
  }
  const envVal = String.fromEnvironment('ADMIN_SOCKET_URL', defaultValue: '');
  return envVal.isNotEmpty ? envVal : 'http://$_kFallbackIp:3001';
}

final String kAdminSocketBaseUrl = _deriveAdminSocketBaseUrl();

final String kAdminApi2BaseUrl = '$kAdminApiBaseUrl/Api2';
final String kAdminApi9BaseUrl = '$kAdminApiBaseUrl/api9';
