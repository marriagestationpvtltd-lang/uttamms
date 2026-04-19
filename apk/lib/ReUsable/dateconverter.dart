// utils/nepali_date_converter.dart
import 'dart:math';

class NepaliDateConverter {
  // Nepali calendar data (BS 2000-2090)
  static final Map<int, List<int>> _nepaliCalendar = {
    2061: [31, 31, 32, 31, 31, 31, 30, 29, 30, 29, 30, 30],
    2060: [31, 32, 31, 32, 31, 30, 30, 30, 29, 29, 30, 30],
    2059: [31, 32, 31, 32, 31, 30, 30, 30, 29, 30, 29, 31],
    2058: [31, 31, 31, 32, 31, 31, 30, 29, 30, 29, 30, 30],
    2057: [31, 31, 32, 31, 31, 31, 30, 29, 30, 29, 30, 30],
    2056: [31, 32, 31, 32, 31, 30, 30, 30, 29, 29, 30, 30],
    2055: [31, 32, 31, 32, 31, 30, 30, 30, 29, 30, 29, 31],
    2054: [31, 31, 31, 32, 31, 31, 30, 29, 30, 29, 30, 30],
    2053: [31, 31, 32, 31, 31, 31, 30, 29, 30, 29, 30, 30],
    2052: [31, 32, 31, 32, 31, 30, 30, 30, 29, 29, 30, 30],
    2051: [31, 32, 31, 32, 31, 30, 30, 30, 29, 30, 29, 31],
    2050: [31, 31, 31, 32, 31, 31, 30, 29, 30, 29, 30, 30],
    2049: [31, 31, 32, 31, 31, 31, 30, 29, 30, 29, 30, 30],
    2048: [31, 32, 31, 32, 31, 30, 30, 30, 29, 29, 30, 30],
    2047: [31, 32, 31, 32, 31, 30, 30, 30, 29, 30, 29, 31],
    2046: [31, 31, 31, 32, 31, 31, 30, 29, 30, 29, 30, 30],
    2045: [31, 31, 32, 31, 31, 31, 30, 29, 30, 29, 30, 30],
    2044: [31, 32, 31, 32, 31, 30, 30, 30, 29, 29, 30, 30],
    2043: [31, 32, 31, 32, 31, 30, 30, 30, 29, 30, 29, 31],
    2042: [31, 31, 31, 32, 31, 31, 30, 29, 30, 29, 30, 30],
    2041: [31, 31, 32, 31, 31, 31, 30, 29, 30, 29, 30, 30],
    2040: [31, 32, 31, 32, 31, 30, 30, 30, 29, 29, 30, 30],
    2039: [31, 32, 31, 32, 31, 30, 30, 30, 29, 30, 29, 31],
    2038: [31, 31, 31, 32, 31, 31, 30, 29, 30, 29, 30, 30],
    2037: [31, 31, 32, 31, 31, 31, 30, 29, 30, 29, 30, 30],
    2036: [31, 32, 31, 32, 31, 30, 30, 30, 29, 29, 30, 30],
    2035: [31, 32, 31, 32, 31, 30, 30, 30, 29, 30, 29, 31],
    2034: [31, 31, 31, 32, 31, 31, 30, 29, 30, 29, 30, 30],
    2033: [31, 31, 32, 31, 31, 31, 30, 29, 30, 29, 30, 30],
    2032: [31, 32, 31, 32, 31, 30, 30, 30, 29, 29, 30, 30],
  };

  // Nepali month names in Bikram Sambat (BS) transliteration
  static final List<String> nepaliMonthsNepali = [
    'Baisakh',
    'Jestha',
    'Ashadh',
    'Shrawan',
    'Bhadra',
    'Ashwin',
    'Kartik',
    'Mangsir',
    'Poush',
    'Magh',
    'Falgun',
    'Chaitra'
  ];

  static final List<String> nepaliMonthsEnglish = [
    'Baisakh',
    'Jestha',
    'Ashad',
    'Shrawan',
    'Bhadra',
    'Ashwin',
    'Kartik',
    'Mangsir',
    'Poush',
    'Magh',
    'Falgun',
    'Chaitra'
  ];

  // Convert BS to AD
  static DateTime? bsToAd(int year, int month, int day) {
    try {
      if (!_nepaliCalendar.containsKey(year)) {
        return null;
      }

      final monthDays = _nepaliCalendar[year]!;
      if (month < 1 || month > 12 || day < 1 || day > monthDays[month - 1]) {
        return null;
      }

      // Reference date: 2000-01-01 BS = 1943-04-14 AD
      final referenceBsYear = 2000;
      final referenceBsMonth = 1;
      final referenceBsDay = 1;
      final referenceAd = DateTime(1943, 4, 14);

      // Calculate total days from reference BS date
      int totalDays = 0;

      // Add days from reference year to target year-1
      for (int y = referenceBsYear; y < year; y++) {
        if (_nepaliCalendar.containsKey(y)) {
          totalDays += _nepaliCalendar[y]!.reduce((a, b) => a + b);
        }
      }

      // Add days from completed months in target year
      for (int m = 0; m < month - 1; m++) {
        totalDays += _nepaliCalendar[year]![m];
      }

      // Add days
      totalDays += (day - 1);

      // Calculate AD date
      final resultDate = referenceAd.add(Duration(days: totalDays));
      return resultDate;
    } catch (e) {
      print('Error converting BS to AD: $e');
      return null;
    }
  }

  // Convert AD to BS (optional, if you need two-way conversion)
  static Map<String, int>? adToBs(DateTime adDate) {
    try {
      // Reference date: 1943-04-14 AD = 2000-01-01 BS
      final referenceAd = DateTime(1943, 4, 14);
      final referenceBsYear = 2000;
      final referenceBsMonth = 1;
      final referenceBsDay = 1;

      // Calculate days difference
      final difference = adDate.difference(referenceAd).inDays;
      if (difference < 0) {
        return null;
      }

      int remainingDays = difference;
      int bsYear = referenceBsYear;
      int bsMonth = referenceBsMonth;
      int bsDay = referenceBsDay;

      // Find year
      while (true) {
        if (!_nepaliCalendar.containsKey(bsYear)) {
          return null;
        }

        final yearDays = _nepaliCalendar[bsYear]!.reduce((a, b) => a + b);

        if (remainingDays < yearDays) {
          break;
        }

        remainingDays -= yearDays;
        bsYear++;
      }

      // Find month
      final yearMonthDays = _nepaliCalendar[bsYear]!;
      for (bsMonth = 0; bsMonth < 12; bsMonth++) {
        if (remainingDays < yearMonthDays[bsMonth]) {
          break;
        }
        remainingDays -= yearMonthDays[bsMonth];
      }
      bsMonth++; // Convert from 0-based to 1-based

      // Calculate day
      bsDay = remainingDays + 1;

      return {
        'year': bsYear,
        'month': bsMonth,
        'day': bsDay,
      };
    } catch (e) {
      print('Error converting AD to BS: $e');
      return null;
    }
  }

  // Get valid days for a given BS month and year
  static List<String> getBsDaysList(int year, int month) {
    final days = <String>[];
    if (_nepaliCalendar.containsKey(year) && month >= 1 && month <= 12) {
      final maxDays = _nepaliCalendar[year]![month - 1];
      for (int i = 1; i <= maxDays; i++) {
        days.add(i.toString().padLeft(2, '0'));
      }
    }
    return days;
  }

  // Get valid BS years (filtered for age range: 21 to 80 years from today)
  static List<String> getBsYearsList() {
    final now = DateTime.now();
    final currentBsDate = adToBs(now);

    if (currentBsDate == null) {
      return _nepaliCalendar.keys.map((e) => e.toString()).toList();
    }

    final currentBsYear = currentBsDate['year']!;
    final minYear = currentBsYear - 80; // 80 years ago
    final maxYear = currentBsYear - 21; // 21 years ago

    return _nepaliCalendar.keys
        .where((year) => year >= minYear && year <= maxYear)
        .map((e) => e.toString())
        .toList()
        .reversed
        .toList();
  }
}