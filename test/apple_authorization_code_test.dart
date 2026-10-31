import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:koolbase_flutter/src/auth/auth_api.dart';

// Sign in with Apple sends the credential's authorization code (A0 piece 6):
// the server exchanges it for the token it revokes when the account is
// deleted, as Apple asks. Only the request matters here, so the fake server
// answers with Apple's own refusal.
void main() {
  late Map<String, dynamic> sent;
  AuthApi api() => AuthApi(
        baseUrl: 'https://api.test',
        publicKey: 'pk_test',
        client: MockClient((req) async {
          sent = jsonDecode(req.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode(
                {'code': 'invalid_oauth_token', 'error': 'invalid token'}),
            401,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

  test('sends authorization_code and client when given', () async {
    await expectLater(
      api().signInWithApple(
        identityToken: 'idt',
        nonce: 'n1',
        authorizationCode: 'code-1',
        client: 'web',
      ),
      throwsA(anything),
    );
    expect(sent, containsPair('identity_token', 'idt'));
    expect(sent, containsPair('nonce', 'n1'));
    expect(sent, containsPair('authorization_code', 'code-1'));
    expect(sent, containsPair('client', 'web'));
  });

  test('sends neither when not given, as before', () async {
    await expectLater(
        api().signInWithApple(identityToken: 'idt'), throwsA(anything));
    expect(sent, containsPair('identity_token', 'idt'));
    expect(sent.containsKey('authorization_code'), isFalse);
    expect(sent.containsKey('client'), isFalse);
  });
}
