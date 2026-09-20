import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:koolbase_flutter/src/auth/auth_api.dart';

// Asking for a new verification email with no session.
//
// A project requiring verified contact issues no session until the account
// verifies, and refuses login until then. So a user whose verification email
// went to spam, or who waited past the 24-hour link expiry, cannot sign in to
// ask for another one — resendVerificationEmail needs the session they cannot
// get. Built for the TypeScript SDKs on 20 September; this is Flutter's half.

void main() {
  group('resendVerificationEmailToAddress', () {
    test('posts the address and returns nothing', () async {
      late String body;
      final api = AuthApi(
        baseUrl: 'https://api.test',
        publicKey: 'pk_test',
        client: MockClient((req) async {
          body = req.body;
          return http.Response(
            jsonEncode({'message': 'If that email needs verifying, a new link has been sent'}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      await expectLater(
        api.resendVerificationEmailToAddress('someone@example.test'),
        completes,
      );
      expect(jsonDecode(body), {'email': 'someone@example.test'});
    });

    test('sends no Authorization header', () async {
      // The whole point is that there is no session. Attaching one would
      // make it fail for exactly the user it exists to serve.
      late http.Request seen;
      final api = AuthApi(
        baseUrl: 'https://api.test',
        publicKey: 'pk_test',
        client: MockClient((req) async {
          seen = req;
          return http.Response('{}', 200,
              headers: {'content-type': 'application/json'});
        }),
      );

      await api.resendVerificationEmailToAddress('someone@example.test');
      expect(seen.headers.keys.map((k) => k.toLowerCase()),
          isNot(contains('authorization')));
      expect(seen.url.path, endsWith('/v1/sdk/auth/resend-verification/by-email'));
    });

    test('an unknown address is not an error', () async {
      // The server answers the same whatever happened, so an app shows one
      // message. Throwing for an unknown address would leak who has signed up.
      final api = AuthApi(
        baseUrl: 'https://api.test',
        publicKey: 'pk_test',
        client: MockClient((_) async => http.Response(
              jsonEncode({'message': 'If that email needs verifying, a new link has been sent'}),
              200,
              headers: {'content-type': 'application/json'},
            )),
      );

      await expectLater(
        api.resendVerificationEmailToAddress('nobody@example.invalid'),
        completes,
      );
    });
  });
}
