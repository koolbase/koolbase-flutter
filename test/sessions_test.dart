import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:koolbase_flutter/koolbase_flutter.dart';
import 'package:koolbase_flutter/src/auth/auth_api.dart';

// Session management: where am I signed in, and sign the others out.
//
// Three endpoints existed on the server and no SDK exposed any of them —
// found on 20 September 2026 by comparing each SDK's public surface against
// the API's routes, after answering a customer's question about one SDK as
// though it were the platform.

AuthApi apiReturning(Object body, {int status = 200}) => AuthApi(
      baseUrl: 'https://api.test',
      publicKey: 'pk_test',
      client: MockClient((_) async => http.Response(
            jsonEncode(body),
            status,
            headers: {'content-type': 'application/json'},
          )),
    );

void main() {
  group('sessions', () {
    test('lists sessions with the server shape mapped', () async {
      final api = apiReturning({
        'sessions': [
          {
            'id': 's1',
            'ip': '1.2.3.4',
            'user_agent': 'koolbase-flutter/12.4.0 (ios; 18.2)',
            'device_label': 'phone',
            'created_at': '2026-09-01T00:00:00Z',
            'expires_at': '2026-10-01T00:00:00Z',
            'is_current': true,
          }
        ],
        'total': 1,
      });

      final List<KoolbaseSessionInfo> sessions = await api.listSessions('token');
      // Typed against the public export deliberately: if KoolbaseSessionInfo
      // stopped being exported, an app could call listSessions and have no
      // way to name what it returns.
      expect(sessions, hasLength(1));
      expect(sessions.first.id, 's1');
      expect(sessions.first.deviceLabel, 'phone');
      expect(sessions.first.isCurrent, isTrue);
      expect(sessions.first.createdAt, DateTime.parse('2026-09-01T00:00:00Z'));
    });

    test('a session missing optional fields still parses', () async {
      // ip and user_agent are omitempty on the server. A list that throws
      // because one row lacks them is a list that fails for the oldest
      // sessions, which are the ones a user most wants to revoke.
      final api = apiReturning({
        'sessions': [
          {
            'id': 's2',
            'created_at': '2026-09-01T00:00:00Z',
            'expires_at': '2026-10-01T00:00:00Z',
            'is_current': false,
          }
        ],
      });

      final sessions = await api.listSessions('token');
      expect(sessions.first.ip, isNull);
      expect(sessions.first.userAgent, isNull);
      expect(sessions.first.isCurrent, isFalse);
    });

    test('an empty list is empty, not an error', () async {
      final api = apiReturning({'total': 0});
      await expectLater(api.listSessions('token'), completion(isEmpty));
    });

    test('no token hash reaches the caller', () async {
      // The server excludes them. If it ever stopped, mapping them through
      // would hand an app a credential-shaped value.
      final api = apiReturning({
        'sessions': [
          {
            'id': 's1',
            'created_at': '2026-09-01T00:00:00Z',
            'expires_at': '2026-10-01T00:00:00Z',
            'is_current': false,
            'access_token_hash': 'leaked',
          }
        ],
      });

      final sessions = await api.listSessions('token');
      expect(sessions.first.toString(), isNot(contains('leaked')));
    });

    test('revokeAllOtherSessions returns how many ended', () async {
      final api = apiReturning({'revoked_count': 3});
      await expectLater(api.revokeAllOtherSessions('token'), completion(3));
    });

    test('a response without a count is zero, not a crash', () async {
      final api = apiReturning({});
      await expectLater(api.revokeAllOtherSessions('token'), completion(0));
    });
  });
}
