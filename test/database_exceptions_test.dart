import 'package:flutter_test/flutter_test.dart';
import 'package:koolbase_flutter/koolbase_flutter.dart';

void main() {
  group('401 classification', () {
    // A session the server refuses is not a session. Before this, a 401 fell
    // through to a bare KoolbaseDataException, indistinguishable from any other
    // failure — so an app kept believing it was authenticated and looped.
    test('a 401 is a session failure, not a generic one', () {
      final err = koolbaseDataError(401, {'error': 'unauthorized'});
      expect(err, isA<KoolbaseSessionExpiredException>());
    });

    // The distinction that makes clearing safe: a permission failure means the
    // session is valid but this caller may not touch that resource. Clearing on
    // one of those would sign people out for opening the wrong record.
    test('a 403 is a permission failure, and does not clear the session', () {
      final err = koolbaseDataError(403, {'error': 'not allowed'});
      expect(err, isA<KoolbasePermissionException>());
      expect(err, isNot(isA<KoolbaseSessionExpiredException>()));
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
          isA<KoolbaseSessionExpiredException>(),
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
}
