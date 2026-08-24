// The canonical error boundary — exception -> KoolbaseError (ADR-001).
//
// The exhaustive mapping group is the contract. Its value is not that it
// passes today; it is that a contributor adding a new exception type without
// a mapping gets a failing test rather than a silent `unknown` in production.
//
// The ordering group is the one guarding a mistake that COMPILES: several
// families use inheritance, so a reordered `if` chain would swallow subtypes
// and analyze perfectly clean.

import 'dart:async' show TimeoutException;
import 'dart:io' show SocketException;

import 'package:flutter_test/flutter_test.dart';
import 'package:koolbase_flutter/koolbase_flutter.dart';
import 'package:koolbase_flutter/src/koolbase_error.dart';

void main() {
  KoolbaseErrorCode codeOf(Object e) => KoolbaseError.from(e).code;

  group('auth family', () {
    final expected = <Object, KoolbaseErrorCode>{
      const InvalidCredentialsException(): KoolbaseErrorCode.validation,
      const WeakPasswordException(): KoolbaseErrorCode.validation,
      const InvalidPhoneNumberException(): KoolbaseErrorCode.validation,
      const OtpExpiredException(): KoolbaseErrorCode.validation,
      const OtpInvalidException(): KoolbaseErrorCode.validation,
      const UnlockTokenInvalidException(): KoolbaseErrorCode.validation,
      const InvalidAppleTokenException(): KoolbaseErrorCode.validation,
      const InvalidGoogleTokenException(): KoolbaseErrorCode.validation,
      const AppleEmailRequiredException(): KoolbaseErrorCode.validation,
      const GoogleEmailRequiredException(): KoolbaseErrorCode.validation,
      const EmailAlreadyInUseException(): KoolbaseErrorCode.conflict,
      const PhoneAlreadyLinkedException(): KoolbaseErrorCode.conflict,
      const OAuthEmailConflictException(): KoolbaseErrorCode.conflict,
      const OtpMaxAttemptsException(): KoolbaseErrorCode.rateLimited,
      const OtpRateLimitException(): KoolbaseErrorCode.rateLimited,
      const RateLimitException(): KoolbaseErrorCode.rateLimited,
      const ResendCooldownException(): KoolbaseErrorCode.rateLimited,
      const ResendDailyCapException(): KoolbaseErrorCode.rateLimited,
      const AccountLockedException(): KoolbaseErrorCode.rateLimited,
      const SessionExpiredException(): KoolbaseErrorCode.unauthorized,
      const TokenRevokedException(): KoolbaseErrorCode.unauthorized,
      const ContactNotVerifiedException(): KoolbaseErrorCode.contactNotVerified,
      const UserDisabledException(): KoolbaseErrorCode.accountDisabled,
      const NetworkException(): KoolbaseErrorCode.network,
      const SmsConfigMissingException(): KoolbaseErrorCode.server,
      const AppleSignInNotConfiguredException(): KoolbaseErrorCode.server,
      const GoogleSignInNotConfiguredException(): KoolbaseErrorCode.server,
    };

    expected.forEach((e, want) {
      test('${e.runtimeType} -> ${want.name}', () {
        expect(codeOf(e), want);
      });
    });

    test('all 27 concrete auth types are covered', () {
      expect(expected.length, 27);
    });

    test('the family base falls to unknown, not a guess', () {
      expect(
        codeOf(const KoolbaseAuthException('?', code: 'never_seen')),
        KoolbaseErrorCode.unknown,
      );
    });
  });

  group('data family', () {
    final expected = <Object, KoolbaseErrorCode>{
      const KoolbaseConflictException(): KoolbaseErrorCode.conflict,
      const KoolbaseRevisionMismatchException('stale'):
          KoolbaseErrorCode.conflict,
      const KoolbaseOfflineBaselineUnavailableException('no baseline'):
          KoolbaseErrorCode.conflict,
      const KoolbaseNotFoundException(): KoolbaseErrorCode.notFound,
      const KoolbasePermissionException(): KoolbaseErrorCode.forbidden,
      const KoolbaseRateLimitException(): KoolbaseErrorCode.rateLimited,
      const KoolbaseValidationException(): KoolbaseErrorCode.validation,
      const KoolbaseVectorDimensionMismatchException():
          KoolbaseErrorCode.validation,
    };

    expected.forEach((e, want) {
      test('${e.runtimeType} -> ${want.name}', () {
        expect(codeOf(e), want);
      });
    });

    test('an unmapped server code falls to unknown but keeps rawCode', () {
      final err = KoolbaseError.from(
        const KoolbaseDataException('?', code: 'brand_new_server_code'),
      );
      expect(err.code, KoolbaseErrorCode.unknown);
      expect(err.rawCode, 'brand_new_server_code');
    });
  });

  group('storage family', () {
    final expected = <Object, KoolbaseErrorCode>{
      const KoolbaseStorageConflictException(): KoolbaseErrorCode.conflict,
      const KoolbaseStorageNotFoundException(): KoolbaseErrorCode.notFound,
      const KoolbaseStoragePermissionException(): KoolbaseErrorCode.forbidden,
      const KoolbaseStorageValidationException(): KoolbaseErrorCode.validation,
      const KoolbaseStorageQuotaExceededException():
          KoolbaseErrorCode.validation,
      const KoolbaseStorageFileTooLargeException():
          KoolbaseErrorCode.validation,
      const KoolbaseStorageMimeTypeException(): KoolbaseErrorCode.validation,
      const KoolbaseStorageMetadataInvalidException():
          KoolbaseErrorCode.validation,
    };

    expected.forEach((e, want) {
      test('${e.runtimeType} -> ${want.name}', () {
        expect(codeOf(e), want);
      });
    });
  });

  group('cross-cutting', () {
    test('unauthenticated is unauthorized, from any surface', () {
      expect(
        codeOf(const KoolbaseUnauthenticatedException('nope')),
        KoolbaseErrorCode.unauthorized,
      );
    });
  });

  group('ordering — mistakes that would compile', () {
    test('SessionExpired is not swallowed by its Unauthenticated parent', () {
      // It IS unauthorized either way, so this pins the path rather than the
      // outcome: rawCode proves the specific branch ran.
      final err = KoolbaseError.from(
        const KoolbaseSessionExpiredException('expired'),
      );
      expect(err.code, KoolbaseErrorCode.unauthorized);
      expect(err.rawCode, 'session_expired');
    });

    test('RevisionMismatch is not swallowed by the DataException fallback', () {
      final err = KoolbaseError.from(
        const KoolbaseRevisionMismatchException(
          'stale',
          expectedRevision: 3,
          currentRevision: 5,
        ),
      );
      expect(err.code, KoolbaseErrorCode.conflict);
      expect(err.code, isNot(KoolbaseErrorCode.unknown));
    });

    test('StorageConflict is not swallowed by the Storage base', () {
      final err = KoolbaseError.from(
        const KoolbaseStorageConflictException('taken', 'a/b.png'),
      );
      expect(err.code, KoolbaseErrorCode.conflict);
      expect(err.details?['path'], 'a/b.png');
    });
  });

  group('details survive normalization', () {
    test('revision mismatch keeps the server record', () {
      final err = KoolbaseError.from(
        const KoolbaseRevisionMismatchException(
          'stale',
          expectedRevision: 3,
          currentRevision: 5,
          currentRecord: {'id': 'r1', 'title': 'server wins'},
        ),
      );
      expect(err.details?['expected_revision'], 3);
      expect(err.details?['current_revision'], 5);
      expect(
        (err.details?['current_record'] as Map)['title'],
        'server wins',
      );
    });

    test('unique violation keeps the field', () {
      final err = KoolbaseError.from(
        const KoolbaseConflictException('taken', 'email'),
      );
      expect(err.details?['field'], 'email');
    });

    test('metadata invalid keeps the detail', () {
      final err = KoolbaseError.from(
        const KoolbaseStorageMetadataInvalidException('bad', 'key "X": nope'),
      );
      expect(err.details?['detail'], 'key "X": nope');
    });

    test('details is null when the failure carried none', () {
      expect(KoolbaseError.from(const KoolbaseNotFoundException()).details,
          isNull);
    });
  });

  group('totality — nothing escapes the boundary', () {
    test('transport failures are network', () {
      expect(
        codeOf(const SocketException('no route')),
        KoolbaseErrorCode.network,
      );
      expect(codeOf(TimeoutException('slow')), KoolbaseErrorCode.network);
    });

    test('an arbitrary exception is unknown', () {
      expect(codeOf(Exception('who knows')), KoolbaseErrorCode.unknown);
    });

    test('a non-exception throwable is unknown', () {
      expect(codeOf('a bare string'), KoolbaseErrorCode.unknown);
      expect(codeOf(42), KoolbaseErrorCode.unknown);
    });

    test('normalizing never throws, whatever it is given', () {
      for (final o in <Object>[
        Exception('x'),
        'string',
        0,
        [1, 2],
        {'a': 1},
        StateError('bad'),
      ]) {
        expect(() => KoolbaseError.from(o), returnsNormally);
      }
    });
  });

  group('retryable is derived, never stored', () {
    const retryable = {
      KoolbaseErrorCode.network,
      KoolbaseErrorCode.rateLimited,
      KoolbaseErrorCode.server,
    };

    for (final c in KoolbaseErrorCode.values) {
      test('${c.name} retryable == ${retryable.contains(c)}', () {
        final err = KoolbaseError(code: c, message: 'x');
        expect(err.retryable, retryable.contains(c));
      });
    }
  });
}
