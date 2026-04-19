import 'dart:io' show File;
import 'package:cunning_document_scanner/cunning_document_scanner.dart'
    if (dart.library.html) 'package:ms2026/utils/web_document_scanner_stub.dart';

/// Service for scanning documents with automatic edge detection and cropping
class DocumentScannerService {
  /// Scan a document from the camera
  /// Returns a list of scanned image paths (can be multiple pages)
  /// Returns null if user cancels or if scanning fails
  Future<List<String>?> scanFromCamera() async {
    try {
      final pictures = await CunningDocumentScanner.getPictures(
        noOfPages: 1, // Single page document
        isGalleryImportAllowed: false, // Only camera
      );

      if (pictures != null && pictures.isNotEmpty) {
        return pictures;
      }

      return null;
    } catch (e) {
      print('Error scanning from camera: $e');
      return null;
    }
  }

  /// Scan a document from the gallery
  /// Returns a list of scanned image paths (can be multiple pages)
  /// Returns null if user cancels or if scanning fails
  Future<List<String>?> scanFromGallery() async {
    try {
      final pictures = await CunningDocumentScanner.getPictures(
        noOfPages: 1, // Single page document
        isGalleryImportAllowed: true, // Gallery enabled
      );

      if (pictures != null && pictures.isNotEmpty) {
        return pictures;
      }

      return null;
    } catch (e) {
      print('Error scanning from gallery: $e');
      return null;
    }
  }

  /// Scan a document allowing user to choose between camera or gallery
  /// Returns a list of scanned image paths (can be multiple pages)
  /// Returns null if user cancels or if scanning fails
  Future<List<String>?> scanDocument({
    int numberOfPages = 1,
    bool allowGallery = true,
  }) async {
    try {
      final pictures = await CunningDocumentScanner.getPictures(
        noOfPages: numberOfPages,
        isGalleryImportAllowed: allowGallery,
      );

      if (pictures != null && pictures.isNotEmpty) {
        return pictures;
      }

      return null;
    } catch (e) {
      print('Error scanning document: $e');
      return null;
    }
  }

  /// Convert scanned image path to File
  File? getFileFromPath(String? path) {
    if (path == null || path.isEmpty) return null;
    return File(path);
  }

  /// Convert list of scanned image paths to Files
  List<File> getFilesFromPaths(List<String>? paths) {
    if (paths == null || paths.isEmpty) return [];
    return paths.map((path) => File(path)).toList();
  }
}
