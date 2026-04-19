import 'dart:io' show File;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart'
    if (dart.library.html) 'package:ms2026/utils/web_mlkit_stub.dart';

/// Service for extracting text from document images using Google ML Kit
class OCRService {
  final TextRecognizer _textRecognizer = TextRecognizer();

  // Mapping of Nepali (Devanagari) numerals to English numerals
  static const Map<String, String> _nepaliToEnglishDigits = {
    '०': '0',
    '१': '1',
    '२': '2',
    '३': '3',
    '४': '4',
    '५': '5',
    '६': '6',
    '७': '7',
    '८': '8',
    '९': '9',
  };

  /// Converts Nepali (Devanagari) numerals to English numerals
  /// Example: "१२३४" -> "1234"
  String _convertNepaliToEnglish(String text) {
    String result = text;
    _nepaliToEnglishDigits.forEach((nepali, english) {
      result = result.replaceAll(nepali, english);
    });
    return result;
  }

  /// Checks if a string contains Nepali numerals
  bool _containsNepaliNumerals(String text) {
    return _nepaliToEnglishDigits.keys.any((nepali) => text.contains(nepali));
  }

  /// Scans an image and extracts document ID numbers.
  /// On web this always returns null (OCR requires native ML Kit).
  Future<String?> extractDocumentId(File imageFile) async {
    try {
      final inputImage = InputImage.fromFilePath(imageFile.path);
      final RecognizedText recognizedText = await _textRecognizer.processImage(inputImage);

      if (recognizedText.text.isEmpty) {
        return null;
      }

      // Collect all text lines
      final List<String> allLines = [];

      for (TextBlock block in recognizedText.blocks) {
        for (TextLine line in block.lines) {
          String lineText = line.text.trim();
          if (lineText.isNotEmpty) {
            allLines.add(lineText);
          }
        }
      }

      if (allLines.isEmpty) {
        return null;
      }

      // Join all lines with space for pattern matching
      String fullText = allLines.join(' ');

      // Try to extract ID-like patterns (numbers, alphanumeric codes)
      // This prioritizes likely ID numbers over all text
      String? extractedId = _extractIdPattern(fullText);

      return extractedId;
    } catch (e) {
      print('Error extracting text: $e');
      return null;
    }
  }

  /// Extracts common ID patterns from text
  /// Looks for patterns like:
  /// - Pure numbers (8+ digits) in English or Nepali numerals
  /// - Alphanumeric codes (passport, license format)
  /// - Common document ID formats
  /// Supports both English (0-9) and Nepali (०-९) numerals
  String? _extractIdPattern(String text) {
    // First, try to find patterns with Nepali numerals
    String? nepaliPattern = _findNepaliNumericPattern(text);
    if (nepaliPattern != null) {
      // Convert to English numerals and return
      return _convertNepaliToEnglish(nepaliPattern);
    }

    // Remove all whitespace for English pattern matching
    String cleanText = text.replaceAll(RegExp(r'\s+'), '');

    // Pattern 1: Look for specific document ID keywords followed by numbers
    // Common patterns: "No:", "Number:", "ID:", etc.
    RegExp keywordPattern = RegExp(
      r'(?:No\.?|Number|ID|Citizenship|License|Passport|Card)[\s:.\-]*([A-Z0-9\-/]{8,})',
      caseSensitive: false,
    );
    Match? keywordMatch = keywordPattern.firstMatch(text);
    if (keywordMatch != null && keywordMatch.group(1) != null) {
      String extracted = keywordMatch.group(1)!.replaceAll(RegExp(r'[\s\-/]'), '');
      if (extracted.length >= 8) {
        return extracted;
      }
    }

    // Pattern 2: Long number sequences (8+ digits)
    // Reduced from 10 to 8 to catch more ID formats
    RegExp longNumberPattern = RegExp(r'\d{8,}');
    Match? longNumberMatch = longNumberPattern.firstMatch(cleanText);
    if (longNumberMatch != null) {
      return longNumberMatch.group(0);
    }

    // Pattern 3: Alphanumeric codes (common in passports, licenses)
    // Example: AB1234567, L123456789, etc.
    RegExp alphanumericPattern = RegExp(r'[A-Z]{1,3}\d{6,}');
    Match? alphanumericMatch = alphanumericPattern.firstMatch(cleanText);
    if (alphanumericMatch != null) {
      return alphanumericMatch.group(0);
    }

    // Pattern 4: Number sequences with dashes, slashes, or spaces
    // Example: 1234-5678-9012, 12-34-56-78910
    RegExp structuredPattern = RegExp(r'[\d\-/\s]{10,}');
    Match? structuredMatch = structuredPattern.firstMatch(text);
    if (structuredMatch != null) {
      String extracted = structuredMatch.group(0)!.replaceAll(RegExp(r'[\s\-/]'), '');
      if (extracted.length >= 8 && RegExp(r'^\d+$').hasMatch(extracted)) {
        return extracted;
      }
    }

    // Pattern 5: Look for the longest continuous digit sequence (minimum 6 digits)
    List<Match> allNumbers = RegExp(r'\d{6,}').allMatches(cleanText).toList();
    if (allNumbers.isNotEmpty) {
      // Sort by length and return the longest
      allNumbers.sort((a, b) => (b.group(0)?.length ?? 0).compareTo(a.group(0)?.length ?? 0));
      return allNumbers.first.group(0);
    }

    // If no specific pattern found, return null instead of all text
    // This prevents showing all the scanned text to the user
    return null;
  }

  /// Finds numeric patterns in text containing Nepali numerals
  /// Returns the text with Nepali numerals if found, null otherwise
  String? _findNepaliNumericPattern(String text) {
    // Pattern 1: Look for Nepali digit sequences (8+ digits)
    RegExp nepaliLongPattern = RegExp(r'[०-९]{8,}');
    Match? match = nepaliLongPattern.firstMatch(text);
    if (match != null) {
      return match.group(0);
    }

    // Pattern 2: Look for mixed Nepali digits with separators
    // Example: ०१-२३-४५६७८९, ०१/२३/४५६७८९
    RegExp nepaliStructuredPattern = RegExp(r'[०-९\-/\s]{10,}');
    match = nepaliStructuredPattern.firstMatch(text);
    if (match != null) {
      String extracted = match.group(0)!;
      // Remove separators and check if we have at least 8 digits
      String digitsOnly = extracted.replaceAll(RegExp(r'[\s\-/]'), '');
      if (digitsOnly.length >= 8 && _containsNepaliNumerals(digitsOnly)) {
        return digitsOnly;
      }
    }

    // Pattern 3: Find the longest sequence of Nepali digits (minimum 6)
    List<Match> allNepaliNumbers = RegExp(r'[०-९]{6,}').allMatches(text).toList();
    if (allNepaliNumbers.isNotEmpty) {
      // Sort by length and return the longest
      allNepaliNumbers.sort((a, b) => (b.group(0)?.length ?? 0).compareTo(a.group(0)?.length ?? 0));
      return allNepaliNumbers.first.group(0);
    }

    return null;
  }

  /// Dispose of the text recognizer
  void dispose() {
    _textRecognizer.close();
  }
}
