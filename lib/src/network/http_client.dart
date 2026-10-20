import 'dart:convert';
import 'package:http/http.dart' as http;

import 'request_log.dart';

class KoolbaseHttpClient {
  final String baseUrl;
  final String publicKey;
  final Future<String?> Function()? accessTokenProvider;
  final Future<bool> Function()? onUnauthorized;

  const KoolbaseHttpClient({
    required this.baseUrl,
    required this.publicKey,
    this.accessTokenProvider,
    this.onUnauthorized,
  });

  Future<Map<String, String>> _buildHeaders(
      {bool authenticated = false}) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'x-api-key': publicKey,
    };
    if (authenticated && accessTokenProvider != null) {
      final token = await accessTokenProvider!();
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }
    }
    return headers;
  }

  Future<http.Response> get(
    String path, {
    bool authenticated = false,
  }) async {
    final headers = await _buildHeaders(authenticated: authenticated);
    final res = await http
        .get(Uri.parse('$baseUrl$path'), headers: headers)
        .timeout(const Duration(seconds: 10));
    return _handleUnauthorized(
        res, () => get(path, authenticated: authenticated));
  }

  Future<http.Response> post(
    String path, {
    Map<String, dynamic>? body,
    bool authenticated = false,
  }) async {
    final headers = await _buildHeaders(authenticated: authenticated);
    final res = await http
        .post(
          Uri.parse('$baseUrl$path'),
          headers: headers,
          body: body != null ? jsonEncode(body) : null,
        )
        .timeout(const Duration(seconds: 10));
    return _handleUnauthorized(
        res, () => post(path, body: body, authenticated: authenticated));
  }

  Future<http.Response> patch(
    String path, {
    Map<String, dynamic>? body,
    bool authenticated = false,
  }) async {
    final headers = await _buildHeaders(authenticated: authenticated);
    final res = await http
        .patch(
          Uri.parse('$baseUrl$path'),
          headers: headers,
          body: body != null ? jsonEncode(body) : null,
        )
        .timeout(const Duration(seconds: 10));
    return _handleUnauthorized(
        res, () => patch(path, body: body, authenticated: authenticated));
  }

  // A failure the caller receives, traced in a debug build (#169).
  static http.Response _logged(http.Response res) {
    koolbaseLogFailedRequest(res.request, res.statusCode, res.body);
    return res;
  }

  Future<http.Response> _handleUnauthorized(
    http.Response res,
    Future<http.Response> Function() retry,
  ) async {
    if (res.statusCode != 401 || onUnauthorized == null) return _logged(res);
    final refreshed = await onUnauthorized!();
    if (!refreshed) return _logged(res);
    return retry();
  }
}
