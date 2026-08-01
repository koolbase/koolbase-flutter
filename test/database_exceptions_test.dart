import 'package:flutter_test/flutter_test.dart';
import 'package:koolbase_flutter/koolbase_flutter.dart';

void main() {
  group('401 classification', () {
    // A session the server refuses is not a session. Before this, a 401 fell
    // through to a bare KoolbaseDataException, indistinguishable from any other
    // failure — so an app kept believing it was authenticated and looped.
    test('a 401 is an authentication failure, not a generic one', () {
      final err = koolbaseDataError(401, {'error': 'unauthorized'});
      expect(err, isA<KoolbaseUnauthenticatedException>());
    });

    // The distinction that makes clearing safe: a permission failure means the
    // session is valid but this caller may not touch that resource. Clearing on
    // one of those would sign people out for opening the wrong record.
    test('a 403 is a permission failure, and does not clear the session', () {
      final err = koolbaseDataError(403, {'error': 'not allowed'});
      expect(err, isA<KoolbasePermissionException>());
      expect(err, isNot(isA<KoolbaseUnauthenticatedException>()));
    });

    test('permission_denied is a permission failure whatever the status', () {
      final err = koolbaseDataError(401, {
        'code': 'permission_denied',
        'error': 'not allowed',
      });
      expect(err, isA<KoolbasePermissionException>());
    });

    // Servers do not send a code on 401 today, so the status carries the
    // meaning. These cases exist so the SDK is correct once they do, without
    // depending on it.
    test('an explicit session code is honoured', () {
      for (final code in ['session_expired', 'invalid_token']) {
        expect(
          koolbaseDataError(400, {'code': code, 'error': 'nope'}),
          isA<KoolbaseUnauthenticatedException>(),
          reason: code,
        );
      }
    });

    test('the server message survives', () {
      final err = koolbaseDataError(401, {'error': 'token does not resolve'});
      expect(err.message, 'token does not resolve');
    });

    test('other failures are unaffected', () {
      expect(koolbaseDataError(404, {'error': 'gone'}),
          isA<KoolbaseNotFoundException>());
      expect(koolbaseDataError(429, {'error': 'slow down'}),
          isA<KoolbaseRateLimitException>());
      expect(koolbaseDataError(409, {'code': 'unique_violation', 'error': 'dup'}),
          isA<KoolbaseConflictException>());
    });
  });

  group('record revision', () {
    // A record that loses its revision cannot make its next write conditional,
    // so the guarantee would silently degrade to last-write-wins.
    test('survives a round trip through json', () {
      final rec = KoolbaseRecord.fromJson({
        r'$id': 'rec-1',
        r'$collection': 'weights',
        r'$createdAt': '2026-01-01T00:00:00Z',
        r'$updatedAt': '2026-01-02T00:00:00Z',
        r'$revision': 7,
        'kg': 68.4,
      });
      expect(rec.revision, 7);
      expect(rec.data.containsKey(r'$revision'), isFalse,
          reason: 'the revision is metadata, not one of the user\'s fields');

      final back = KoolbaseRecord.fromJson(rec.toJson());
      expect(back.revision, 7, reason: 'a cached record must keep its revision');
    });

    // Servers that predate revisions, and records cached by an earlier SDK.
    test('is null when the server does not send one', () {
      final rec = KoolbaseRecord.fromJson({
        r'$id': 'rec-1',
        r'$createdAt': '2026-01-01T00:00:00Z',
        r'$updatedAt': '2026-01-01T00:00:00Z',
        'kg': 68.4,
      });
      expect(rec.revision, isNull);
      expect(rec.toJson().containsKey(r'$revision'), isFalse);
    });
  });

  // The point of the shared root: a rejected credential is not a data problem or
  // a storage problem, and an application should not need a handler per
  // subsystem to notice one.
  test('a 401 from any surface is the same type', () {
    final fromData = koolbaseDataError(401, {'error': 'unauthorized'});
    final fromStorage = koolbaseStorageError(401, {'error': 'unauthorized'});

    expect(fromData, isA<KoolbaseUnauthenticatedException>());
    expect(fromStorage, isA<KoolbaseUnauthenticatedException>());

    // And both are still catchable as any SDK failure.
    expect(fromData, isA<KoolbaseException>());
    expect(fromStorage, isA<KoolbaseException>());
  });

  group('function invocation errors', () {
    // One type carrying a status number made every failure look alike: a missing
    // Function, a caller without permission, and a Function that threw all
    // arrived identically. The distinction matters — one is a deployment
    // problem, one is permissions, one is a bug in the Function.
    test('failures are told apart', () {
      expect(functionInvokeError(403, 'no'), isA<FunctionPermissionException>());
      expect(functionInvokeError(404, 'no such function'),
          isA<FunctionNotFoundException>());
      expect(functionInvokeError(400, 'bad args'),
          isA<FunctionValidationException>());
      expect(functionInvokeError(500, 'threw'),
          isA<FunctionExecutionException>());
      expect(functionInvokeError(402, 'limit reached'),
          isA<FunctionQuotaExceededException>(),
          reason: 'a plan limit is fixed by changing a plan, not by retrying');
    });

    // A rejected credential is not a Function failure.
    test('a 401 is an authentication failure, shared with every surface', () {
      final err = functionInvokeError(401, 'unauthorized');
      expect(err, isA<KoolbaseUnauthenticatedException>());
      expect(err, isNot(isA<FunctionInvokeException>()));
    });

    // A permission failure must not be mistaken for one: signing the user out
    // for calling a Function they may not call would be wrong.
    test('a 403 does not sign the user out', () {
      expect(functionInvokeError(403, 'no'),
          isNot(isA<KoolbaseUnauthenticatedException>()));
    });

    test('everything is catchable as an SDK failure', () {
      for (final status in [400, 401, 403, 404, 418, 500]) {
        expect(functionInvokeError(status, 'x'), isA<KoolbaseException>(),
            reason: 'status $status');
      }
    });
  });
}
