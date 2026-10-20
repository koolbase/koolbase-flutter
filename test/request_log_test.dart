import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:koolbase_flutter/src/network/request_log.dart';
import 'package:koolbase_flutter/src/network/session_client.dart';

// #169: a failed request leaves one line in a debug build -- method, path,
// status, reason -- and never the key, a token, the query or the body.
void main() {
  const key = 'pk_live_doNotPrintMe0123456789';
  const token = 'eyJhbGciOiJIUzI1NiJ9.secret.token';
  late List<String> lines;
  late DebugPrintCallback saved;

  setUp(() {
    lines = [];
    saved = debugPrint;
    debugPrint = (String? m, {int? wrapWidth}) => lines.add(m ?? '');
  });
  tearDown(() => debugPrint = saved);

  http.Request req(String method, String url) => http.Request(method, Uri.parse(url))
    ..headers['x-api-key'] = key
    ..headers['Authorization'] = 'Bearer $token'
    ..body = jsonEncode({'email': 'person@example.com'});

  test('a failure prints its method, path, status and reason, nothing else', () async {
    const body = '{"code":"invalid_public_key","error":"This app\'s Koolbase key isn\'t valid for this project."}';
    final client = KoolbaseSessionClient(MockClient((_) async => http.Response(body, 401)));
    final res = await client.send(req('POST', 'https://api.koolbase.com/v1/sdk/auth/email/code?email=person%40example.com'));

    expect(lines, hasLength(1));
    final line = lines.single;
    expect(line, startsWith('[Koolbase] POST /v1/sdk/auth/email/code -> 401 invalid_public_key: '));
    for (final secret in [key, token, 'person', 'example.com', 'api.koolbase.com', '?']) {
      expect(line, isNot(contains(secret)), reason: 'printed "$secret"');
    }
    // The caller still reads the whole answer.
    expect(await res.stream.bytesToString(), body);
  });

  test('a success prints nothing', () async {
    final client = KoolbaseSessionClient(MockClient((_) async => http.Response('{}', 200)));
    await client.send(req('GET', 'https://api.koolbase.com/v1/sdk/x'));
    expect(lines, isEmpty);
  });

  test('a body that is not JSON still gives method, path and status', () async {
    final client = KoolbaseLoggingClient(MockClient((_) async => http.Response('<html>bad gateway</html>', 502)));
    await client.send(req('GET', 'https://api.koolbase.com/v1/sdk/records'));
    expect(lines, ['[Koolbase] GET /v1/sdk/records -> 502']);
  });
}
