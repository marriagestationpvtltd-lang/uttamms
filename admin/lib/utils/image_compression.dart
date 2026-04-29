import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:file_picker/file_picker.dart';

/// Image compression utilities for admin chat
/// Optimizes images before upload to reduce bandwidth and improve send speed
class AdminImageCompression {
  // Compression quality settings
  static const int thumbnailMaxWidth = 200;
  static const int thumbnailMaxHeight = 200;
  static const int thumbnailQuality = 70;

  static const int previewMaxWidth = 800;
  static const int previewMaxHeight = 800;
  static const int previewQuality = 75;

  // Maximum file size targets
  static const int previewMaxSize = 200 * 1024; // 200KB

  /// Compresses an image from PlatformFile to optimized bytes
  static Future<Uint8List> compressImageForSending(PlatformFile file) async {
    try {
      final bytes = file.bytes;
      if (bytes == null) {
        throw Exception('File has no bytes');
      }

      // Compress with balanced quality settings
      final compressed = await FlutterImageCompress.compressWithList(
        bytes,
        minWidth: previewMaxWidth,
        minHeight: previewMaxHeight,
        quality: previewQuality,
        format: CompressFormat.jpeg,
      );

      // If still too large, compress more aggressively
      if (compressed.length > previewMaxSize) {
        return await FlutterImageCompress.compressWithList(
          bytes,
          minWidth: 600,
          minHeight: 600,
          quality: 70,
          format: CompressFormat.jpeg,
        );
      }

      return compressed;
    } catch (e) {
      debugPrint('Error compressing image: $e');
      // Return original bytes if compression fails
      return file.bytes ?? Uint8List(0);
    }
  }

  /// Generates a thumbnail for instant preview
  static Future<Uint8List> generateThumbnail(PlatformFile file) async {
    try {
      final bytes = file.bytes;
      if (bytes == null) {
        throw Exception('File has no bytes');
      }

      final thumbnail = await FlutterImageCompress.compressWithList(
        bytes,
        minWidth: thumbnailMaxWidth,
        minHeight: thumbnailMaxHeight,
        quality: thumbnailQuality,
        format: CompressFormat.jpeg,
      );

      return thumbnail;
    } catch (e) {
      debugPrint('Error generating thumbnail: $e');
      return file.bytes ?? Uint8List(0);
    }
  }

  /// Compresses multiple images in parallel
  static Future<List<Uint8List>> compressMultipleImages(
    List<PlatformFile> files,
  ) async {
    return await Future.wait(
      files.map((file) => compressImageForSending(file)),
    );
  }

  /// Validates if image needs compression
  static bool needsCompression(int fileSizeBytes) {
    return fileSizeBytes > previewMaxSize;
  }
}
