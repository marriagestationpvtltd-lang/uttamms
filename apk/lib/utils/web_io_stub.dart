/// Web stub for dart:io.
///
/// This file is imported instead of `dart:io` when building for web:
///   import 'dart:io' if (dart.library.html) 'package:ms2026/utils/web_io_stub.dart';
///
/// It provides a minimal [File] stub so that code that references
/// `File(path).readAsBytes()` compiles.  All methods throw [UnsupportedError]
/// if actually called on web — callers must guard with `if (!kIsWeb)`.
library web_io_stub;

import 'dart:typed_data';

/// Stub for dart:io Socket exceptions (used in catch blocks).
class SocketException implements Exception {
  const SocketException(this.message, {this.osError, this.address, this.port});
  final String message;
  final Object? osError;
  final Object? address;
  final int? port;
  @override
  String toString() => 'SocketException: $message';
}

class File {
  const File(this.path);
  final String path;

  Future<Uint8List> readAsBytes() =>
      throw UnsupportedError('File.readAsBytes() is not supported on web. '
          'Use XFile.readAsBytes() instead and guard with kIsWeb.');

  Future<String> readAsString() =>
      throw UnsupportedError('File.readAsString() is not supported on web.');

  bool existsSync() => false;

  Future<bool> exists() async => false;

  Stream<List<int>> openRead() =>
      throw UnsupportedError('File.openRead() is not supported on web.');

  Future<int> length() =>
      throw UnsupportedError('File.length() is not supported on web.');
}
