import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koolbase_flutter/koolbase_flutter.dart';
import 'package:koolbase_flutter/src/auth/auth_api.dart';
import 'package:koolbase_flutter/src/auth/auth_storage.dart';

/// KoolbaseAuthGate behavioral tests.
///
/// The gate exists to make four hand-written-badly behaviors correct by
/// construction; each has a test that fails if the behavior regresses:
///
///  * restoring shows FIRST — a returning user never sees a login flash
///  * the gate seeds synchronously (the auth stream has no replay)
///  * RestoreResult.offline is signed-IN (optimistic restore), with the
///    restoredOffline flag exposed on the scope
///  * a restore that throws lands on signedOut, never an error crash
///
/// The fakes drive KoolbaseAuthClient's REAL restoreSession logic — no
/// network, no secure storage, but the genuine state machine.

class _FakeStorage implements KoolbaseAuthStorage {
  _FakeStorage([this.session]);
  PersistedSession? session;
  int reads = 0;

  @override
  Future<PersistedSession?> readSession() async {
    reads++;
    return session;
  }

  @override
  Future<void> saveSession(PersistedSession s) async => session = s;

  @override
  Future<void> clear() async => session = null;
}

/// AuthApi whose refresh outcome is scripted per test.
class _FakeApi extends AuthApi {
  _FakeApi({this.onRefresh})
      : super(baseUrl: 'https://api.test', publicKey: 'pk_test');

  final Future<AuthSession> Function()? onRefresh;

  @override
  Future<AuthSession> refresh(String refreshToken) {
    final handler = onRefresh;
    if (handler == null) {
      throw StateError('refresh called but this test scripted no outcome');
    }
    return handler();
  }
}

KoolbaseUser _user(String id) => KoolbaseUser(
      id: id,
      projectId: 'p1',
      email: '$id@test.dev',
      phoneNumber: null,
      phoneVerified: false,
      fullName: null,
      avatarUrl: null,
      verified: true,
      disabled: false,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

PersistedSession _session({required bool expired, String userId = 'u1'}) =>
    PersistedSession(
      accessToken: 'at',
      refreshToken: 'rt',
      expiresAt: DateTime.now()
          .add(expired ? const Duration(hours: -1) : const Duration(hours: 1)),
      user: _user(userId),
    );

Widget _gate(KoolbaseAuthClient auth, {WidgetBuilder? restoring}) {
  return MaterialApp(
    home: KoolbaseAuthGate(
      auth: auth,
      restoring: restoring,
      signedIn: (context, user) => Text('IN:${user.id}'),
      signedOut: (context) => const Text('OUT'),
    ),
  );
}

void main() {
  testWidgets('no persisted session: restoring first, then signedOut',
      (tester) async {
    final auth = KoolbaseAuthClient(api: _FakeApi(), storage: _FakeStorage());

    await tester.pumpWidget(_gate(auth));
    // First frame: restore in flight. The default slot is a spinner — and
    // decisively NOT the signedOut builder, which would flash a login
    // screen at returning users (the bug this gate kills).
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('OUT'), findsNothing);

    await tester.pump();
    expect(find.text('OUT'), findsOneWidget);
  });

  testWidgets('valid persisted session: signedIn without any network',
      (tester) async {
    final auth = KoolbaseAuthClient(
      api: _FakeApi(), // no refresh scripted — throws if touched
      storage: _FakeStorage(_session(expired: false)),
    );

    await tester.pumpWidget(_gate(auth));
    await tester.pump();
    expect(find.text('IN:u1'), findsOneWidget);
  });

  testWidgets('expired session, server rejects refresh: signedOut',
      (tester) async {
    final auth = KoolbaseAuthClient(
      api: _FakeApi(
          onRefresh: () =>
              throw const KoolbaseAuthException('refresh token revoked')),
      storage: _FakeStorage(_session(expired: true)),
    );

    await tester.pumpWidget(_gate(auth));
    await tester.pump();
    await tester.pump();
    expect(find.text('OUT'), findsOneWidget);
  });

  testWidgets(
      'expired session, network unreachable: signedIn optimistically, '
      'scope.restoredOffline is true', (tester) async {
    final auth = KoolbaseAuthClient(
      api: _FakeApi(onRefresh: () => throw TimeoutException('no network')),
      storage: _FakeStorage(_session(expired: true)),
    );

    late KoolbaseAuthScope observed;
    await tester.pumpWidget(MaterialApp(
      home: KoolbaseAuthGate(
        auth: auth,
        signedIn: (context, user) {
          observed = KoolbaseAuthScope.of(context);
          return Text('IN:${user.id}');
        },
        signedOut: (context) => const Text('OUT'),
      ),
    ));
    await tester.pump();
    await tester.pump();

    expect(find.text('IN:u1'), findsOneWidget,
        reason: 'offline restore is optimistic sign-in, not an error');
    expect(observed.restoredOffline, isTrue);
  });

  testWidgets('custom restoring slot replaces the default spinner',
      (tester) async {
    final auth = KoolbaseAuthClient(api: _FakeApi(), storage: _FakeStorage());

    await tester.pumpWidget(_gate(
      auth,
      restoring: (context) => const Text('SPLASH'),
    ));
    expect(find.text('SPLASH'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('already signed in at mount: seeds synchronously, skips restore',
      (tester) async {
    final storage = _FakeStorage(_session(expired: false));
    final auth = KoolbaseAuthClient(api: _FakeApi(), storage: storage);
    // Sign in BEFORE the gate exists.
    await auth.restoreSession();
    final readsBeforeMount = storage.reads;

    final auth2 = auth; // same instance the gate receives
    await tester.pumpWidget(_gate(auth2));
    // No pump needed for the signed-in frame: the seed is synchronous.
    expect(find.text('IN:u1'), findsOneWidget,
        reason: 'broadcast stream has no replay; without the synchronous '
            'seed the gate would hang on restoring');
    expect(storage.reads, readsBeforeMount,
        reason: 'a gate mounted after login must not re-run restore');
  });

  testWidgets('auth stream delta flips the gate: OUT then IN', (tester) async {
    final storage = _FakeStorage(); // starts empty → signedOut
    final auth = KoolbaseAuthClient(api: _FakeApi(), storage: storage);

    await tester.pumpWidget(_gate(auth));
    await tester.pump();
    expect(find.text('OUT'), findsOneWidget);

    // A session appears (e.g. login elsewhere); restoreSession emits the
    // user on authStateChanges — the gate must follow the stream.
    storage.session = _session(expired: false, userId: 'u2');
    await auth.restoreSession();
    await tester.pump();

    expect(find.text('IN:u2'), findsOneWidget);
  });
}
