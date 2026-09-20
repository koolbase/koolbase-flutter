import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:koolbase_flutter/koolbase_flutter.dart';
import 'package:koolbase_flutter/src/auth/auth_api.dart';

// The account's own security log, for a "recent activity" screen.
//
// The endpoint existed and no SDK exposed it. The server sanitizes each
// event against a per-type field allowlist — a lockout may name the address
// that was attempted, a successful login carries nothing — and the SDK
// passes through what survived rather than filtering again.

AuthApi apiReturning(Object body, {void Function(http.Request)? onRequest}) =>
    AuthApi(
      baseUrl: 'https://api.test',
      publicKey: 'pk_test',
      client: MockClient((req) async {
        onRequest?.call(req);
        return http.Response(jsonEncode(body), 200,
            headers: {'content-type': 'application/json'});
      }),
    );

void main() {
  group('audit log', () {
    test('maps the server shape and keeps the page counts', () async {
      final api = apiReturning({
        'events': [
          {
            'id': 'e1',
            'event_type': 'auth.account.locked',
            'occurred_at': '2026-09-19T22:00:00Z',
            'ip': '1.2.3.4',
            'user_agent': 'koolbase-flutter/12.4.0 (ios; 18.2)',
            'event_data': {'lock_level': 'account', 'attempted_email': 'a@b.test'},
          }
        ],
        'total': 41,
        'limit': 50,
        'offset': 0,
      });

      final KoolbaseAuditPage page = await api.listAudit(accessToken: 'token');
      expect(page.events.first.eventType, 'auth.account.locked');
      expect(page.events.first.occurredAt,
          DateTime.parse('2026-09-19T22:00:00Z'));
      expect(page.events.first.eventData['attempted_email'], 'a@b.test');
      // total is across all pages: an app needs it to offer "show more".
      expect(page.total, 41);
    });

    test('an event with no data is an empty map', () async {
      // auth.login.success carries nothing. A null here would make every
      // caller null-check a map that is simply empty.
      final api = apiReturning({
        'events': [
          {
            'id': 'e2',
            'event_type': 'auth.login.success',
            'occurred_at': '2026-09-19T22:00:00Z',
          }
        ],
        'total': 1,
        'limit': 50,
        'offset': 0,
      });

      final page = await api.listAudit(accessToken: 'token');
      expect(page.events.first.eventData, isEmpty);
      expect(page.events.first.ip, isNull);
    });

    test('passes limit and offset as query parameters', () async {
      Uri? seen;
      final api = apiReturning({'events': [], 'total': 0, 'limit': 10, 'offset': 20},
          onRequest: (req) => seen = req.url);

      await api.listAudit(accessToken: 'token', limit: 10, offset: 20);
      expect(seen!.queryParameters['limit'], '10');
      expect(seen!.queryParameters['offset'], '20');
    });

    test('sends no query string when nothing was asked for', () async {
      Uri? seen;
      final api = apiReturning({'events': [], 'total': 0, 'limit': 50, 'offset': 0},
          onRequest: (req) => seen = req.url);

      await api.listAudit(accessToken: 'token');
      expect(seen!.hasQuery, isFalse);
    });

    test('an empty log is an empty page, not an error', () async {
      final api = apiReturning({'total': 0, 'limit': 50, 'offset': 0});
      final page = await api.listAudit(accessToken: 'token');
      expect(page.events, isEmpty);
      expect(page.total, 0);
    });
  });
}
