class PartnerAgePreferenceBounds {
  static const int minimumAllowedAge = 21;
  static const int defaultMaximumAge = 60;
  static const int maximumAgeOffsetFromUserAge = 20;
  static const int absoluteMaximumAge = 120;

  final int minAge;
  final int maxAge;

  const PartnerAgePreferenceBounds({
    required this.minAge,
    required this.maxAge,
  });

  List<String> buildAgeOptions() {
    return List.generate(
      (maxAge - minAge) + 1,
      (index) => (minAge + index).toString(),
    );
  }
}

PartnerAgePreferenceBounds resolvePartnerAgePreferenceBounds({
  Map<String, dynamic>? userData,
  int fallbackMaxAge = PartnerAgePreferenceBounds.defaultMaximumAge,
}) {
  final parsedBirthDate = _parseBirthDate(
    userData?['dateofbirth'] ??
        userData?['birthdate'] ??
        userData?['dob'],
  );

  final minAge = PartnerAgePreferenceBounds.minimumAllowedAge;
  final maxAge = parsedBirthDate == null
      ? (fallbackMaxAge < minAge ? minAge : fallbackMaxAge)
      : ((_calculateAge(parsedBirthDate) +
                  PartnerAgePreferenceBounds.maximumAgeOffsetFromUserAge)
              .clamp(minAge, PartnerAgePreferenceBounds.absoluteMaximumAge));

  return PartnerAgePreferenceBounds(
    minAge: minAge,
    maxAge: maxAge,
  );
}

DateTime? _parseBirthDate(dynamic rawValue) {
  if (rawValue == null) {
    return null;
  }

  final value = rawValue.toString().trim();
  if (value.isEmpty) {
    return null;
  }

  final normalized = value.contains('T')
      ? value.split('T').first
      : value.split(' ').first;

  final parsed = DateTime.tryParse(normalized);
  if (parsed != null) {
    return parsed;
  }

  final sanitized = normalized.replaceAll('/', '-');
  return DateTime.tryParse(sanitized);
}

int _calculateAge(DateTime birthDate) {
  final today = DateTime.now();
  var calculatedAge = today.year - birthDate.year;

  final hasHadBirthdayThisYear = today.month > birthDate.month ||
      (today.month == birthDate.month && today.day >= birthDate.day);

  if (!hasHadBirthdayThisYear) {
    calculatedAge -= 1;
  }

  return calculatedAge;
}
