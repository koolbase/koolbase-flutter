import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:koolbase_flutter/koolbase_flutter.dart';
import 'package:koolbase_flutter/src/auth/auth_api.dart';

// In-app admin: an app's own admins (the app_admin claim) manage its people
// through /v1/sdk/admin. The server decides who may do what; the SDK sends
// the right request and turns each refusal into a type an app can catch.

AuthApi apiAnswering(int status, Object body,
        {void Function(http.Request)? onRequest}) =>
    AuthApi(
      baseUrl: 'https://api.test',
      publicKey: 'pk_test',
      client: MockClient((req) async {
        onRequest?.call(req);
        return http.Response(jsonEncode(body), status,
            headers: {'content-type': 'application/json'});
      }),
    );

KoolbaseAppAdmin adminAnswering(int status, Object body,
        {void Function(http.Request)? onRequest}) =>
    KoolbaseAppAdmin(apiAnswering(status, body, onRequest: onRequest),
        () async => 'token');

final memberJson = {
  'id': 'u1',
  'email': 'ama@example.test',
  'full_name': 'Ama',
  'status': 'invited',
  'is_admin': false,
  'roles': {'role': 'staff'},
  'version': 3,
  'joined_at': '2026-11-01T10:00:00Z',
};

void main() {
  group('reading', () {
    test('members sends the search and paging, and maps the page', () async {
      late http.Request sent;
      final admin = adminAnswering(200, {
        'members': [memberJson],
        'total': 41,
      }, onRequest: (r) => sent = r);

      final page = await admin.members(query: 'ama', limit: 20, offset: 40);
      expect(sent.method, 'GET');
      expect(sent.url.path, '/v1/sdk/admin/members');
      expect(sent.url.queryParameters,
          {'q': 'ama', 'limit': '20', 'offset': '40'});
      expect(sent.headers['authorization'], 'Bearer token');
      expect(page.total, 41);
      final m = page.members.single;
      expect(m.fullName, 'Ama');
      expect(m.isInvited, isTrue);
      expect(m.roles, {'role': 'staff'});
      expect(m.version, 3);
      expect(m.lastSeenAt, isNull);
    });

    test('no search sends no query string', () async {
      late http.Request sent;
      final admin = adminAnswering(200, {'members': [], 'total': 0},
          onRequest: (r) => sent = r);
      await admin.members();
      expect(sent.url.hasQuery, isFalse);
    });

    test('roles maps the counts', () async {
      final admin = adminAnswering(200, {
        'roles': [
          {
            'key': 'role',
            'value_type': 'string',
            'allowed_values': ['staff', 'manager'],
            'holders': 5,
            'values': {'staff': 4, 'manager': 1},
          }
        ]
      });
      final r = (await admin.roles()).single;
      expect(r.key, 'role');
      expect(r.allowedValues, ['staff', 'manager']);
      expect(r.holders, 5);
      expect(r.values['manager'], 1);
    });
  });

  group('changing', () {
    test('invite posts the email, name and roles', () async {
      late http.Request sent;
      final admin =
          adminAnswering(201, memberJson, onRequest: (r) => sent = r);
      final m = await admin.invite(
          email: 'ama@example.test', fullName: 'Ama', roles: {'role': 'staff'});
      expect(sent.url.path, '/v1/sdk/admin/members/invite');
      expect(jsonDecode(sent.body), {
        'email': 'ama@example.test',
        'full_name': 'Ama',
        'roles': {'role': 'staff'},
      });
      expect(m.id, 'u1');
    });

    test('disable and enable post to their own routes', () async {
      final paths = <String>[];
      final admin = adminAnswering(200, {'id': 'u1', 'disabled': true},
          onRequest: (r) => paths.add('${r.method} ${r.url.path}'));
      await admin.disable('u1');
      await admin.enable('u1');
      expect(paths, [
        'POST /v1/sdk/admin/members/u1/disable',
        'POST /v1/sdk/admin/members/u1/enable',
      ]);
    });

    test('setRoles sends the version and keeps a null that clears a role',
        () async {
      late http.Request sent;
      final admin = adminAnswering(
          200, {'id': 'u1', 'roles': {'team': 'north'}, 'version': 4},
          onRequest: (r) => sent = r);
      final out = await admin
          .setRoles('u1', {'role': null, 'team': 'north'}, expectedVersion: 3);
      expect(sent.method, 'PUT');
      expect(sent.url.path, '/v1/sdk/admin/members/u1/roles');
      expect(jsonDecode(sent.body), {
        'roles': {'role': null, 'team': 'north'},
        'expected_version': 3,
      });
      expect(out.version, 4);
      expect(out.roles, {'team': 'north'});
    });
  });

  group('refusals', () {
    Future<Object?> failure(int status, Map<String, Object?> body) async {
      try {
        await adminAnswering(status, body).disable('u1');
      } catch (e) {
        return e;
      }
      return null;
    }

    test('each admin code is its own type', () async {
      expect(await failure(403, {'code': 'app_admin_required', 'error': 'x'}),
          isA<NotAppAdminException>());
      expect(await failure(403, {'code': 'app_admin_self', 'error': 'x'}),
          isA<AppAdminSelfException>());
      expect(
          await failure(
              403, {'code': 'app_admin_target_is_admin', 'error': 'x'}),
          isA<AppAdminTargetIsAdminException>());
      expect(
          await failure(400, {'code': 'role_not_assignable', 'error': 'x'}),
          isA<RoleNotAssignableException>());
      expect(
          await failure(400, {'code': 'role_value_not_allowed', 'error': 'x'}),
          isA<RoleValueNotAllowedException>());
      expect(await failure(409, {'code': 'member_exists', 'error': 'x'}),
          isA<MemberExistsException>());
      expect(await failure(403, {'code': 'recent_mfa_required', 'error': 'x'}),
          isA<RecentMfaRequiredException>());
    });

    test('a version conflict carries the current version', () async {
      final e = await failure(409, {
        'code': 'claims_version_conflict',
        'error': 'changed',
        'version': 9,
      });
      expect(e, isA<ClaimsVersionConflictException>());
      expect((e as ClaimsVersionConflictException).currentVersion, 9);
    });

    test('a plain 409 or 404 keeps the server words, never "email in use"',
        () async {
      final conflict = await failure(409,
          {'code': 'conflict', 'error': 'this app has no way to sign in'});
      expect(conflict, isNot(isA<EmailAlreadyInUseException>()));
      expect((conflict as KoolbaseAuthException).message,
          'this app has no way to sign in');

      final missing =
          await failure(404, {'code': 'not_found', 'error': 'member not found'});
      expect((missing as KoolbaseAuthException).code, 'not_found');
    });

    test('too many requests is a rate limit', () async {
      expect(
          await failure(429, {'code': 'rate_limit', 'error': 'slow down'}),
          isA<RateLimitException>());
    });
  });
}
