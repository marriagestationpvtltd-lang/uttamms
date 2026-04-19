/// Web stub for the geocoding package.
///
/// The geocoding package does NOT support Flutter Web.
/// On web, reverse geocoding would need a separate web-compatible API call.
/// This stub provides no-op implementations that return empty results.
library web_geocoding_stub;

class Placemark {
  const Placemark({
    this.name,
    this.street,
    this.locality,
    this.subLocality,
    this.administrativeArea,
    this.subAdministrativeArea,
    this.postalCode,
    this.country,
    this.isoCountryCode,
  });
  final String? name;
  final String? street;
  final String? locality;
  final String? subLocality;
  final String? administrativeArea;
  final String? subAdministrativeArea;
  final String? postalCode;
  final String? country;
  final String? isoCountryCode;
}

/// Always returns an empty list on web.
Future<List<Placemark>> placemarkFromCoordinates(
  double latitude,
  double longitude, {
  String? localeIdentifier,
}) async =>
    const [];
