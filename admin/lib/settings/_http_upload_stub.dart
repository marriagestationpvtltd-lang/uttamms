import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

/// Sends a multipart POST request.
///
/// This stub is used on Flutter Web (and any platform without dart:io).
/// On web the browser's XMLHttpRequest layer handles the low-level HTTP
/// connection; redirect behaviour follows the browser's own rules.
Future<http.StreamedResponse> uploadMultipartPost({
  required String url,
  required String fieldName,
  required Uint8List bytes,
  required String filename,
  MediaType? contentType,
  Map<String, String>? extraHeaders,
  Map<String, String>? fields,
}) {
  final request = http.MultipartRequest('POST', Uri.parse(url));
  if (extraHeaders != null) request.headers.addAll(extraHeaders);
  if (fields != null) request.fields.addAll(fields);
  request.files.add(
    http.MultipartFile.fromBytes(
      fieldName,
      bytes,
      filename: filename,
      contentType: contentType,
    ),
  );
  return request.send();
}

/// Sends a JSON POST request.
///
/// Stub/web version — uses the standard [http.post] which lets the browser
/// or default http client follow redirects.
Future<http.Response> sendJsonPost(
  String url,
  Map<String, dynamic> body, {
  Map<String, String>? extraHeaders,
}) {
  return http.post(
    Uri.parse(url),
    headers: {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (extraHeaders != null) ...extraHeaders,
    },
    body: jsonEncode(body),
  );
}
