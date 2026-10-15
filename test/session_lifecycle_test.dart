import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:koolbase_flutter/koolbase_flutter.dart';
import 'package:koolbase_flutter/src/auth/auth_api.dart';
import 'package:koolbase_flutter/src/auth/auth_storage.dart';
import 'package:koolbase_flutter/src/network/session_client.dart';

// Sessions across a restart and past their expiry (#96, #104).
//
// #104: after signing out, the app reopened signed in on a stale local
// session. #96: hours later the session was not renewed, every list failed,
// and Retry did not help. These prove the rules that fix both: a restart asks
// the server before trusting a session; a refused request renews once and
// goes again; only a refused renewal signs anyone out; and two tabs renewing
// at the same moment share one session rather than both signing out.

/// One device's keychain: what survives a restart.
class _Device implements KoolbaseAuthStorage {
  PersistedSession? session;

  @override
  Future<PersistedSession?> readSession() async => session;

  @override
  Future<void> saveSession(PersistedSession s) async => session = s;

  @override
  Future<void> clear() async => session = null;
}

/// The server, scripted per test.
class _Api extends AuthApi {
  _Api({this.onMe, this.onRefresh})
      : super(baseUrl: 'https://api.test', publicKey: 'pk_test');

  final Future<KoolbaseUser> Function(String token)? onMe;
  final Future<AuthSession> Function(String refreshToken)? onRefresh;

  final calls = <String>[];

  @override
  Future<KoolbaseUser> getMe(String accessToken) {
    calls.add('me');
    return onMe?.call(accessToken) ??
        Future<KoolbaseUser>.error(TimeoutException('no network'));
  }

  @override
  Future<AuthSession> refresh(String refreshToken) {
    calls.add('refresh:$refreshToken');
    return onRefresh?.call(refreshToken) ??
        Future<AuthSession>.error(TimeoutException('no network'));
  }

  @override
  Future<void> logout(String accessToken) async {
    calls.add('logout');
  }
}

KoolbaseUser _user() => KoolbaseUser(
      id: 'u1',
      projectId: 'p1',
      email: 'u1@test.dev',
      phoneNumber: null,
      phoneVerified: false,
      fullName: null,
      avatarUrl: null,
      verified: true,
      disabled: false,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

PersistedSession _stored(String at, String rt, {bool expired = false}) =>
    PersistedSession(
      accessToken: at,
      refreshToken: rt,
      expiresAt: DateTime.now().add(
          expired ? const Duration(minutes: -1) : const Duration(minutes: 15)),
      user: _user(),
    );

AuthSession _fresh(String at, String rt) => AuthSession(
      accessToken: at,
      refreshToken: rt,
      expiresAt: DateTime.now().add(const Duration(minutes: 15)),
      user: _user(),
    );

void main() {
  group('a restart', () {
    test('after signing out opens signed out (#104)', () async {
      final device = _Device()..session = _stored('at1', 'rt1');
      final before = KoolbaseAuthClient(
          api: _Api(onMe: (_) async => _user()), storage: device);
      expect(await before.restoreSession(), RestoreResult.restored);
      await before.logout();
      expect(before.lastSignOutReason, KoolbaseSignOutReason.signedOut);
      expect(device.session, isNull);

      final after = KoolbaseAuthClient(api: _Api(), storage: device);
      expect(await after.restoreSession(), RestoreResult.noSession);
      expect(after.currentUser, isNull);
    });

    test(
        'with a session revoked on the server opens signed out, though its '
        'token has not expired (#104)', () async {
      final device = _Device()..session = _stored('at1', 'rt1');
      final api = _Api(
        onMe: (_) => Future.error(const InvalidCredentialsException()),
        onRefresh: (_) => Future.error(const SessionExpiredException()),
      );
      final auth = KoolbaseAuthClient(api: api, storage: device);
      expect(await auth.restoreSession(), RestoreResult.expired);
      expect(auth.currentUser, isNull);
      expect(auth.lastSignOutReason, KoolbaseSignOutReason.sessionEnded);
      expect(device.session, isNull);
      expect(api.calls, ['me', 'refresh:rt1']);
    });

    test('with a good session asks the server once and stays signed in',
        () async {
      final device = _Device()..session = _stored('at1', 'rt1');
      final api = _Api(onMe: (_) async => _user());
      final auth = KoolbaseAuthClient(api: api, storage: device);
      expect(await auth.restoreSession(), RestoreResult.restored);
      expect(auth.currentUser?.id, 'u1');
      expect(api.calls, ['me']);
    });

    test('offline keeps the session, to be checked when the network returns',
        () async {
      final device = _Device()..session = _stored('at1', 'rt1');
      final auth = KoolbaseAuthClient(api: _Api(), storage: device);
      expect(await auth.restoreSession(), RestoreResult.offline);
      expect(auth.currentUser?.id, 'u1');
      expect(device.session, isNotNull);
    });

    test('a server error on /me is not a refusal', () async {
      final device = _Device()..session = _stored('at1', 'rt1');
      final auth = KoolbaseAuthClient(
        api: _Api(
            onMe: (_) => Future.error(
                const KoolbaseAuthException('An unexpected error occurred'))),
        storage: device,
      );
      expect(await auth.restoreSession(), RestoreResult.offline);
      expect(device.session, isNotNull);
    });

    test('with an expired access token renews it and stays signed in',
        () async {
      final device = _Device()..session = _stored('at1', 'rt1', expired: true);
      final auth = KoolbaseAuthClient(
          api: _Api(onRefresh: (_) async => _fresh('at2', 'rt2')),
          storage: device);
      expect(await auth.restoreSession(), RestoreResult.restored);
      expect(device.session?.refreshToken, 'rt2');
    });
  });

  group('a request refused as unauthenticated (#96)', () {
    tearDown(() => KoolbaseSessionClient.renew = null);

    test('renews the session once and goes again, unseen by the caller',
        () async {
      final device = _Device()..session = _stored('at1', 'rt1');
      final auth = KoolbaseAuthClient(
        api: _Api(
            onMe: (_) async => _user(),
            onRefresh: (_) async => _fresh('at2', 'rt2')),
        storage: device,
      );
      await auth.restoreSession();
      KoolbaseSessionClient.renew = auth.renewRejected;
      final sent = <String?>[];
      final client = KoolbaseSessionClient(MockClient((req) async {
        sent.add(req.headers['Authorization']);
        return req.headers['Authorization'] == 'Bearer at1'
            ? http.Response('{"error":"unauthorized"}', 401)
            : http.Response(jsonEncode({'records': [], 'total': 0}), 200);
      }));

      final res = await client.post(
          Uri.parse('https://api.test/v1/sdk/db/query'),
          headers: {'Authorization': 'Bearer at1'},
          body: '{"collection":"events"}');
      expect(res.statusCode, 200);
      expect(sent, ['Bearer at1', 'Bearer at2']);
      expect(auth.currentUser?.id, 'u1');
      expect(device.session?.accessToken, 'at2');
    });

    test('signs out when renewal is refused too, and says the session ended',
        () async {
      final device = _Device()..session = _stored('at1', 'rt1');
      final auth = KoolbaseAuthClient(
        api: _Api(
            onMe: (_) async => _user(),
            onRefresh: (_) => Future.error(const SessionExpiredException())),
        storage: device,
      );
      await auth.restoreSession();
      KoolbaseSessionClient.renew = auth.renewRejected;
      final client = KoolbaseSessionClient(MockClient(
          (_) async => http.Response('{"error":"unauthorized"}', 401)));

      final res = await client.get(
          Uri.parse('https://api.test/v1/sdk/db/records/x'),
          headers: {'Authorization': 'Bearer at1'});
      expect(res.statusCode, 401);
      // The data client hears the refusal and calls sessionRejected.
      await auth.sessionRejected();
      expect(auth.currentUser, isNull);
      expect(auth.lastSignOutReason, KoolbaseSignOutReason.sessionEnded);
      expect(device.session, isNull);
    });

    test('keeps the session when renewal finds no network', () async {
      final device = _Device()..session = _stored('at1', 'rt1');
      final auth = KoolbaseAuthClient(
          api: _Api(onMe: (_) async => _user()), storage: device);
      await auth.restoreSession();
      expect(await auth.renewRejected('at1'), isNull);
      await auth.sessionRejected();
      expect(auth.currentUser?.id, 'u1');
      expect(device.session, isNotNull);
    });

    test('an expired token with no network fails the request, not the session',
        () async {
      final device = _Device()..session = _stored('at1', 'rt1', expired: true);
      final auth = KoolbaseAuthClient(api: _Api(), storage: device);
      expect(await auth.restoreSession(), RestoreResult.offline);
      // Not null: a null would send the request as a signed-out visitor.
      await expectLater(
          auth.validAccessToken(), throwsA(isA<TimeoutException>()));
      expect(auth.currentUser?.id, 'u1');
    });

    test('a request without a token passes straight through', () async {
      var calls = 0;
      KoolbaseSessionClient.renew = (_) async {
        calls++;
        return 'never';
      };
      final client = KoolbaseSessionClient(MockClient(
          (_) async => http.Response('{"error":"unauthorized"}', 401)));
      final res = await client.get(Uri.parse('https://api.test/x'));
      expect(res.statusCode, 401);
      expect(calls, 0);
    });
  });

  test('two tabs renewing at the same moment share the winner\'s session',
      () async {
    // One browser profile: both tabs read and write the same stored session.
    final device = _Device()..session = _stored('at1', 'rt1', expired: true);
    var spent = false;
    Future<AuthSession> serverRefresh(String rt) async {
      if (rt == 'rt1' && !spent) {
        spent = true;
        return _fresh('at2', 'rt2');
      }
      throw const SessionExpiredException();
    }

    final a = KoolbaseAuthClient(
        api: _Api(onRefresh: serverRefresh), storage: device);
    // Tab B sends rt1 just after tab A's renewal spent it.
    final b = KoolbaseAuthClient(
      api: _Api(onRefresh: (rt) async {
        if (!spent) await a.refreshSession();
        return serverRefresh(rt);
      }),
      storage: device,
    );
    expect(await b.restoreSession(), RestoreResult.restored);

    expect(a.currentUser?.id, 'u1');
    expect(b.currentUser?.id, 'u1');
    expect(b.accessToken, 'at2');
    expect(device.session?.refreshToken, 'rt2');
  });
}
