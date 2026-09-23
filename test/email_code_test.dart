import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:koolbase_flutter/koolbase_flutter.dart';
import 'package:koolbase_flutter/src/auth/auth_api.dart';

// Email-code sign-in: the request resolves the same way whatever the
// address, and a verified code returns a session exactly as login does.

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

void main() {
  test('requests a code at the right endpoint', () async {
    await apiReturning({'sent': true}).requestEmailCode('ama@example.com');
    expect(lastRequest!.url.path, '/v1/sdk/auth/email/code');
    expect(jsonDecode(lastRequest!.body), {'email': 'ama@example.com'});
  });

  test('signs in with a code and returns the session', () async {
    final session = await apiReturning({
      'access_token': 'at',
      'refresh_token': 'rt',
      'expires_at': DateTime.now().add(const Duration(hours: 1)).toUtc().toIso8601String(),
      'user': {
        'id': 'u1',
        'project_id': 'p1',
        'email': 'ama@example.com',
        'verified': true,
        'created_at': '2026-09-23T10:00:00Z',
        'updated_at': '2026-09-23T10:00:00Z',
      },
    }).signInWithEmailCode(email: 'ama@example.com', code: '123456');
    expect(session.accessToken, 'at');
    expect(lastRequest!.url.path, '/v1/sdk/auth/email/code/verify');
    expect(jsonDecode(lastRequest!.body), {'email': 'ama@example.com', 'code': '123456'});
  });

  test('a switched-off project throws a class an app can catch', () async {
    expect(
      apiReturning({'code': 'email_code_disabled', 'error': 'switched off'}, status: 403)
          .requestEmailCode('ama@example.com'),
      throwsA(isA<EmailCodeDisabledException>()),
    );
  });

  test('a wrong code throws OtpInvalidException', () async {
    expect(
      apiReturning({'code': 'otp_invalid', 'error': 'invalid code'}, status: 400)
          .signInWithEmailCode(email: 'ama@example.com', code: '000000'),
      throwsA(isA<OtpInvalidException>()),
    );
  });

  test('too many attempts throws OtpMaxAttemptsException', () async {
    expect(
      apiReturning({'code': 'otp_max_attempts', 'error': 'too many'}, status: 400)
          .signInWithEmailCode(email: 'ama@example.com', code: '000000'),
      throwsA(isA<OtpMaxAttemptsException>()),
    );
  });
}
