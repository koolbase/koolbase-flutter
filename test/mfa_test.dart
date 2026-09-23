import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:koolbase_flutter/koolbase_flutter.dart';
import 'package:koolbase_flutter/src/auth/auth_api.dart';

// Two-step sign-in (MFA) in the SDK.
//
// Every sign-in method must surface mfa_required as MfaRequiredException
// carrying the challenge token — including phone, Google and Apple, which
// have their own error parsers. A method that turned it into a generic error
// would leave the app unable to ask for the second factor.

http.Request? lastRequest;

AuthApi apiReturning(Object body, {int status = 200}) => AuthApi(
      baseUrl: 'https://api.test',
      publicKey: 'pk_test',
      client: MockClient((req) async {
        lastRequest = req;
        return http.Response(jsonEncode(body), status,
            headers: {'content-type': 'application/json'});
      }),
    );

Map<String, dynamic> sessionBody([Map<String, dynamic> extra = const {}]) => {
      'access_token': 'at',
      'refresh_token': 'rt',
      'expires_at': DateTime.now()
          .add(const Duration(hours: 1))
          .toUtc()
          .toIso8601String(),
      'user': {
        'id': 'u1',
        'project_id': 'p1',
        'email': 'ama@example.com',
        'verified': true,
        'created_at': '2026-09-23T10:00:00Z',
        'updated_at': '2026-09-23T10:00:00Z',
      },
      ...extra,
    };

const mfaRequired = {
  'code': 'mfa_required',
  'error': 'two-step sign-in required',
  'details': {
    'challenge_token': 'ct-123',
    'expires_at': '2026-09-23T10:05:00Z'
  },
};

void main() {
  test('every error parser in the auth API maps mfa_required', () {
    // Structural: a sign-in path whose parser lacks the case would hide the
    // challenge from the app. This fails if any switch on the error code —
    // shared, phone, Apple, Google, or one added later — is missing it.
    final src = File('lib/src/auth/auth_api.dart').readAsStringSync();
    final switches = RegExp(r'switch \(code\) \{').allMatches(src).toList();
    expect(switches, isNotEmpty);
    for (var i = 0; i < switches.length; i++) {
      final end = i + 1 < switches.length ? switches[i + 1].start : src.length;
      final block = src.substring(switches[i].start, end);
      expect(block.contains("case 'mfa_required':"), isTrue,
          reason:
              'switch #${i + 1} in auth_api.dart does not map mfa_required');
    }
  });

  test('a first factor that needs MFA throws with the challenge token',
      () async {
    try {
      await apiReturning(mfaRequired, status: 403)
          .login(email: 'ama@example.com', password: 'pw12345678');
      fail('login returned instead of throwing');
    } on MfaRequiredException catch (e) {
      expect(e.challengeToken, 'ct-123');
      expect(e.expiresAt, DateTime.parse('2026-09-23T10:05:00Z'));
      expect(e.code, 'mfa_required');
    }
  });

  test('verifyMfa sends the challenge and returns a session', () async {
    final session = await apiReturning(sessionBody())
        .verifyMfa(challengeToken: 'ct-123', code: '123456');
    expect(session.accessToken, 'at');
    expect(lastRequest!.url.path, '/v1/sdk/auth/mfa/verify');
    expect(jsonDecode(lastRequest!.body),
        {'challenge_token': 'ct-123', 'code': '123456'});
  });

  test('a recovery code sign-in reports how many codes remain', () async {
    final r = await apiReturning(sessionBody({'recovery_codes_remaining': 4}))
        .verifyRecoveryCode(challengeToken: 'ct-123', code: 'abcde-fghij');
    expect(r.session.accessToken, 'at');
    expect(r.remaining, 4);
    expect(lastRequest!.url.path, '/v1/sdk/auth/mfa/verify-recovery');
  });

  test('enrolment returns the setup link and the key', () async {
    final e = await apiReturning(
            {'otpauth_uri': 'otpauth://totp/x', 'secret': 'JBSWY3DP'})
        .enrollMfa('tok');
    expect(e.otpauthUri, 'otpauth://totp/x');
    expect(e.secret, 'JBSWY3DP');
    expect(lastRequest!.headers['authorization'], 'Bearer tok');
  });

  test('confirming returns the recovery codes', () async {
    final codes = await apiReturning({
      'recovery_codes': ['a', 'b']
    }).confirmMfaEnrollment('tok', '123456');
    expect(codes, ['a', 'b']);
  });

  test('status reads enabled and codes left', () async {
    final s =
        await apiReturning({'enabled': true, 'recovery_codes_remaining': 7})
            .mfaStatus('tok');
    expect(s.enabled, isTrue);
    expect(s.recoveryCodesRemaining, 7);
  });

  test('each new code throws its own exception', () async {
    final cases = <String, TypeMatcher>{
      'recent_auth_required': isA<RecentAuthRequiredException>(),
      'recent_mfa_required': isA<RecentMfaRequiredException>(),
      'mfa_already_enabled': isA<MfaAlreadyEnabledException>(),
      'mfa_enrollment_not_found': isA<MfaEnrollmentNotFoundException>(),
      'mfa_not_enabled': isA<MfaNotEnabledException>(),
    };
    for (final e in cases.entries) {
      await expectLater(
        apiReturning({'code': e.key, 'error': 'm'}, status: 403)
            .disableMfa('tok'),
        throwsA(e.value),
        reason: e.key,
      );
    }
  });
}
