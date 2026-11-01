// R49: Koolbase.initializeForTesting runs the SDK's own auth and session
// code against the client a test gives it -- fake the server, never the SDK.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:koolbase_flutter/koolbase_flutter.dart';

void main() {
  const user = {
    'id': 'usr_t',
    'project_id': 'prj_t',
    'email': 'ama@example.com',
    'full_name': 'Ama Mensah',
    'verified': true,
    'disabled': false,
    'providers': <String>[],
    'created_at': '2026-11-01T00:00:00Z',
    'updated_at': '2026-11-01T00:00:00Z',
  };
  Map<String, Object> session(int n) => {
        'access_token': 'at_$n',
        'refresh_token': 'rt_$n',
        'expires_at': '2099-01-01T00:00:00Z',
        'user': user,
      };

  var expired = false;
  final calls = <String>[];
  http.Response json(int status, Object body) => http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
      );
  final server = MockClient((r) async {
    calls.add('${r.method} ${r.url.path}');
    switch (r.url.path) {
      case '/v1/sdk/auth/login':
        return json(200, session(1));
      case '/v1/sdk/auth/refresh':
        return expired
            ? json(401, {'error': 'invalid or expired refresh token', 'code': 'invalid_refresh_token'})
            : json(200, session(2));
      case '/v1/sdk/auth/logout':
        return http.Response('', 204);
      case '/v1/sdk/db/query':
        return expired
            ? json(401, {'error': 'authentication required', 'code': 'unauthenticated'})
            : json(200, {'records': <Object>[], 'total': 0});
    }
    return json(404, {'error': 'not found', 'code': 'not_found'});
  });

  setUp(() {
    expired = false;
    calls.clear();
    Koolbase.initializeForTesting(httpClient: server);
  });
  tearDown(Koolbase.resetForTesting);

  test('signs in, reads and signs out against the client it is given', () async {
    await Koolbase.auth.login(email: 'ama@example.com', password: 'secret');
    expect(Koolbase.auth.currentUser?.email, 'ama@example.com');
    final res = await Koolbase.db.collection('notes').get(fresh: true);
    expect(res.records, isEmpty);
    await Koolbase.auth.logout();
    expect(Koolbase.auth.currentUser, isNull);
    expect(calls, containsAllInOrder(['POST /v1/sdk/auth/login', 'POST /v1/sdk/db/query', 'POST /v1/sdk/auth/logout']));
  });

  test('a data request refused after sign-in renews once; a refused renewal ends the session', () async {
    await Koolbase.auth.login(email: 'ama@example.com', password: 'secret');
    expired = true;
    await expectLater(Koolbase.db.collection('notes').get(fresh: true), throwsA(anything));
    // The real path: the refusal, the renewal tried, the session ended.
    expect(calls, containsAllInOrder(['POST /v1/sdk/db/query', 'POST /v1/sdk/auth/refresh']));
    expect(Koolbase.auth.currentUser, isNull);
    expect(Koolbase.auth.lastSignOutReason, KoolbaseSignOutReason.sessionEnded);
  });
}
