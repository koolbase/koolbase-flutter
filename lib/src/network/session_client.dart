import 'package:http/http.dart' as http;

/// The HTTP client every data request goes through (#96).
///
/// A request refused as unauthenticated (401) while carrying the signed-in
/// person's token is the session needing renewal, not ending: the access
/// token expired early, the device clock is off, or another tab of the same
/// web app renewed it. The session is renewed once and the request sent again
/// with the new token, so the caller never sees the first refusal. Only when
/// renewal is refused does the 401 reach the caller, and with it the client's
/// onSessionExpired, which ends the session.
///
/// A request without a bearer token (a signed-out visitor, a presigned
/// upload) passes straight through, as does one whose body cannot be sent
/// twice.
class KoolbaseSessionClient extends http.BaseClient {
  KoolbaseSessionClient([this._inner]);

  /// The client to send through; null sends each request through its own
  /// http.Client(), as http's get and post do -- so http.runWithClient (a
  /// test's MockClient, an app's own client) is honoured wherever the request
  /// is made.
  final http.Client? _inner;

  /// Renews the session a request was refused with, returning the token to
  /// send again with, or null. Installed by `Koolbase.initialize`; null when
  /// nothing renews (tests, before initialize).
  static Future<String?> Function(String refusedToken)? renew;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final auth = request.headers['Authorization'];
    final renewer = renew;
    final again = (auth != null &&
            auth.startsWith('Bearer ') &&
            renewer != null &&
            request is http.Request)
        ? _copy(request)
        : null;
    final res = await _send(request);
    if (res.statusCode != 401 || again == null) return res;
    final fresh = await renewer!(auth!.substring('Bearer '.length));
    if (fresh == null) return res;
    // The refusal is answered; its body is not needed.
    await res.stream.drain<void>();
    again.headers['Authorization'] = 'Bearer $fresh';
    return _send(again);
  }

  Future<http.StreamedResponse> _send(http.BaseRequest request) async {
    final inner = _inner;
    if (inner != null) return inner.send(request);
    // A client for this request alone, closed once its answer is read.
    final client = http.Client();
    try {
      final res = await client.send(request);
      final bytes = await res.stream.toBytes();
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
    } finally {
      client.close();
    }
  }

  static http.Request _copy(http.Request r) => http.Request(r.method, r.url)
    ..headers.addAll(r.headers)
    ..followRedirects = r.followRedirects
    ..maxRedirects = r.maxRedirects
    ..persistentConnection = r.persistentConnection
    ..bodyBytes = r.bodyBytes;

  @override
  void close() => _inner?.close();
}

/// The one shared instance: data clients send through it unless a test gives
/// them their own client.
final http.Client koolbaseHttp = KoolbaseSessionClient();
