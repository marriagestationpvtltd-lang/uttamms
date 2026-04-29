import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:http_parser/http_parser.dart';

const _maxRedirects = 5;
const _connectionTimeout = Duration(seconds: 30);

/// Sends a multipart POST request on native platforms (Android / iOS / desktop).
///
/// Unlike the default [http.MultipartRequest.send], this helper disables
/// automatic redirect-following in [dart:io]'s [HttpClient] and instead
/// re-issues the POST manually whenever the server returns a 3xx redirect.
///
/// Background: RFC 7231 §6.4.2/6.4.3 allows HTTP clients to change the method
/// to GET when following a 301/302 redirect. [dart:io]'s HttpClient does this
/// by default. As a result, a server that redirects (e.g. non-www → www) turns
/// a file-upload POST into a GET, causing PHP's `$_SERVER['REQUEST_METHOD']`
/// to be `GET`, which triggers the "Invalid request method." error.
Future<http.StreamedResponse> uploadMultipartPost({
  required String url,
  required String fieldName,
  required Uint8List bytes,
  required String filename,
  MediaType? contentType,
  Map<String, String>? extraHeaders,
}) async {
  // Build a dart:io HttpClient that will NOT auto-follow redirects.
  final innerClient = HttpClient()
    ..connectionTimeout = _connectionTimeout;
  final client = IOClient(innerClient);

  try {
    var uploadUrl = url;

    // Follow up to _maxRedirects redirects manually, preserving the POST method.
    for (int hop = 0; hop <= _maxRedirects; hop++) {
      final request = http.MultipartRequest('POST', Uri.parse(uploadUrl));
      if (extraHeaders != null) request.headers.addAll(extraHeaders);
      request.files.add(
        http.MultipartFile.fromBytes(
          fieldName,
          bytes,
          filename: filename,
          contentType: contentType,
        ),
      );

      final response = await client.send(request);

      // Not a redirect — return this response to the caller.
      if (response.statusCode < 300 || response.statusCode >= 400) {
        return response;
      }

      // It is a redirect: consume the body so the socket can be reused.
      await response.stream.drain<void>();

      final location = response.headers['location'];
      if (location == null || location.isEmpty) {
        // No Location header — re-issue to the same URL once more.
        break;
      }

      // Resolve the Location against the current URL (handles relative paths).
      uploadUrl = Uri.parse(uploadUrl).resolve(location).toString();
    }

    // Fallback: send one final attempt at the last resolved URL.
    final finalRequest = http.MultipartRequest('POST', Uri.parse(uploadUrl));
    if (extraHeaders != null) finalRequest.headers.addAll(extraHeaders);
    finalRequest.files.add(
      http.MultipartFile.fromBytes(
        fieldName,
        bytes,
        filename: filename,
        contentType: contentType,
      ),
    );
    return client.send(finalRequest);
  } finally {
    client.close();
  }
}

/// Sends a JSON POST request on native platforms, manually following any
/// 301/302 redirects while preserving the POST method.
Future<http.Response> sendJsonPost(
  String url,
  Map<String, dynamic> body, {
  Map<String, String>? extraHeaders,
}) async {
  final innerClient = HttpClient()
    ..connectionTimeout = _connectionTimeout;
  final client = IOClient(innerClient);

  try {
    final bodyStr = jsonEncode(body);
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (extraHeaders != null) ...extraHeaders,
    };

    var postUrl = url;

    for (int hop = 0; hop <= _maxRedirects; hop++) {
      final response = await client.post(
        Uri.parse(postUrl),
        headers: headers,
        body: bodyStr,
      );

      if (response.statusCode < 300 || response.statusCode >= 400) {
        return response;
      }

      final location = response.headers['location'];
      if (location == null || location.isEmpty) break;
      postUrl = Uri.parse(postUrl).resolve(location).toString();
    }

    // Fallback: final attempt at the last resolved URL.
    return client.post(Uri.parse(postUrl), headers: headers, body: bodyStr);
  } finally {
    client.close();
  }
}
