import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io' if (dart.library.html) 'package:ms2026/utils/web_io_stub.dart';

/// Image compression and optimization utilities for chat messages
///
/// This utility provides optimized image processing for chat applications,
/// similar to WhatsApp's approach of instant sending with progressive quality.
class ImageCompressionUtils {
  // WhatsApp-like quality settings
  static const int thumbnailMaxWidth = 200;
  static const int thumbnailMaxHeight = 200;
  static const int thumbnailQuality = 70;

  static const int previewMaxWidth = 800;
  static const int previewMaxHeight = 800;
  static const int previewQuality = 75;

  static const int fullMaxWidth = 1920;
  static const int fullMaxHeight = 1920;
  static const int fullQuality = 85;

  // Maximum file size targets (in bytes)
  static const int thumbnailMaxSize = 50 * 1024; // 50KB for thumbnails
  static const int previewMaxSize = 200 * 1024; // 200KB for previews
  static const int fullMaxSize = 1024 * 1024; // 1MB for full images

  /// Compresses an image from XFile to optimized bytes
  /// Returns compressed image data suitable for sending
  static Future<Uint8List> compressImageForSending(XFile imageFile) async {
    try {
      final bytes = await imageFile.readAsBytes();

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
      return await imageFile.readAsBytes();
    }
  }

  /// Generates a thumbnail for instant preview display
  /// This is shown immediately while the full image uploads
  static Future<Uint8List> generateThumbnail(XFile imageFile) async {
    try {
      final bytes = await imageFile.readAsBytes();

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
      return await imageFile.readAsBytes();
    }
  }

  /// Compresses multiple images in parallel for gallery messages
  static Future<List<CompressedImage>> compressMultipleImages(
    List<XFile> images,
  ) async {
    return await Future.wait(
      images.map((image) async {
        final compressed = await compressImageForSending(image);
        final thumbnail = await generateThumbnail(image);
        return CompressedImage(
          compressed: compressed,
          thumbnail: thumbnail,
          originalName: image.name,
        );
      }),
    );
  }

  /// Gets optimal image dimensions while maintaining aspect ratio
  static Size getOptimalDimensions(int width, int height, int maxDimension) {
    if (width <= maxDimension && height <= maxDimension) {
      return Size(width.toDouble(), height.toDouble());
    }

    final aspectRatio = width / height;
    if (width > height) {
      return Size(
        maxDimension.toDouble(),
        (maxDimension / aspectRatio).toDouble(),
      );
    } else {
      return Size(
        (maxDimension * aspectRatio).toDouble(),
        maxDimension.toDouble(),
      );
    }
  }

  /// Creates a blurred placeholder from thumbnail for progressive loading
  static Future<Uint8List> createBlurredPlaceholder(Uint8List thumbnail) async {
    try {
      // Further reduce thumbnail size for blur placeholder
      final blurred = await FlutterImageCompress.compressWithList(
        thumbnail,
        minWidth: 50,
        minHeight: 50,
        quality: 50,
        format: CompressFormat.jpeg,
      );
      return blurred;
    } catch (e) {
      return thumbnail;
    }
  }

  /// Validates if image needs compression based on file size
  static bool needsCompression(int fileSizeBytes) {
    return fileSizeBytes > previewMaxSize;
  }

  /// Estimates compression ratio based on image size
  static double estimateCompressionRatio(int originalSize) {
    if (originalSize < 500 * 1024) return 0.8; // 80% of original
    if (originalSize < 1024 * 1024) return 0.5; // 50% of original
    if (originalSize < 3 * 1024 * 1024) return 0.3; // 30% of original
    return 0.2; // 20% of original for very large images
  }
}

/// Container for compressed image data
class CompressedImage {
  final Uint8List compressed;
  final Uint8List thumbnail;
  final String originalName;

  CompressedImage({
    required this.compressed,
    required this.thumbnail,
    required this.originalName,
  });
}

/// Memory image provider that uses base64 data for instant preview
class MemoryImageProvider extends MemoryImage {
  MemoryImageProvider(Uint8List bytes) : super(bytes);

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType) return false;
    return other is MemoryImageProvider && other.bytes == bytes;
  }

  @override
  int get hashCode => bytes.hashCode;
}
