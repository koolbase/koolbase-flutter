import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:http/http.dart' as http;

/// #169: a failed Koolbase request leaves a trace in a debug build.
///
/// One line per failure the caller receives: the method, the path, the
/// status and the server's reason --
/// `[Koolbase] POST /v1/sdk/auth/email/code -> 401 invalid_public_key: ...`.
/// Never the host, the query, a header, the key, a token or the request
/// body: the line is safe to paste into a bug report. Release builds print
/// nothing.
void koolbaseLogFailedRequest(http.BaseRequest? request, int status, String? body) {
  if (!kDebugMode || request == null || status < 400) return;
  final reason = _reasonIn(body);
  debugPrint('[Koolbase] ${request.method} ${request.url.path} -> $status'
      '${reason.isEmpty ? '' : ' $reason'}');
}

String _reasonIn(String? body) {
  if (body == null || body.isEmpty) return '';
  try {
    final j = jsonDecode(body);
    if (j is! Map) return '';
    final code = j['code'];
    final error = j['error'];
    return [
      if (code is String && code.isNotEmpty) code,
      if (error is String && error.isNotEmpty) error,
    ].join(': ');
  } catch (_) {
    return '';
  }
}

/// A streamed response, logged when it failed; its body still readable.
Future<http.StreamedResponse> koolbaseLogged(
    http.BaseRequest request, http.StreamedResponse res) async {
  if (!kDebugMode || res.statusCode < 400) return res;
  final bytes = await res.stream.toBytes();
  koolbaseLogFailedRequest(
      request, res.statusCode, utf8.decode(bytes, allowMalformed: true));
  return http.StreamedResponse(
    http.ByteStream.fromBytes(bytes),
    res.statusCode,
    contentLength: bytes.length,
    request: res.request,
    headers: res.headers,
    isRedirect: res.isRedirect,
    persistentConnection: res.persistentConnection,
    reasonPhrase: res.reasonPhrase,
  );
}

/// A client that logs every failed response it passes on (#169).
class KoolbaseLoggingClient extends http.BaseClient {
  KoolbaseLoggingClient(this._inner);

  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      koolbaseLogged(request, await _inner.send(request));

  @override
  void close() => _inner.close();
}
