import 'package:ms2026/config/app_endpoints.dart';
const String _apiBaseUrl = '${kApiBaseUrl}/Api2';

/// Resolves a raw image path returned by the PHP API into a full URL.
///
/// The API often returns relative paths such as `uploads/profile/123.jpg`.
/// This helper normalises them to an absolute URL so widgets like
/// [NetworkImage] / [CachedNetworkImage] can load them correctly.
///
/// If [rawImage] is already an absolute URL it is returned unchanged.
/// If [rawImage] is empty, an empty string is returned.
String resolveApiImageUrl(String rawImage) {
  if (rawImage.isEmpty) return '';
  if (rawImage.startsWith('http')) return rawImage;
  final normalizedPath =
      rawImage.startsWith('/') ? rawImage.substring(1) : rawImage;
  return '$_apiBaseUrl/$normalizedPath';
}
