import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:koolbase_flutter/src/database/database_exceptions.dart';
import 'package:koolbase_flutter/src/functions/functions_models.dart';
import 'package:koolbase_flutter/src/koolbase_error.dart';
import 'package:koolbase_flutter/src/koolbase_exception.dart';
import 'package:koolbase_flutter/src/network/invalid_public_key.dart';

// #168/#169: a refused app key is a setup problem. It is never a session
// failure (which would sign the user out) and never a wrong password.
void main() {
  const body = '{"code":"invalid_public_key","error":"$kInvalidPublicKeyMessage"}';

  test('a data 401 with invalid_public_key does not sign anyone out', () async {
    var signedOut = false;
    final err = await koolbaseDataErrorNotifying(
      http.Response(body, 401),
      onSessionExpired: () async => signedOut = true,
    );
    expect(err, isA<KoolbaseInvalidPublicKeyException>());
    expect(err, isNot(isA<KoolbaseUnauthenticatedException>()));
    expect(signedOut, isFalse);
  });

  test('a data 401 without that code still ends the session', () async {
    var signedOut = false;
    final err = await koolbaseDataErrorNotifying(
      http.Response('{"code":"unauthenticated","error":"no"}', 401),
      onSessionExpired: () async => signedOut = true,
    );
    expect(err, isA<KoolbaseUnauthenticatedException>());
    expect(signedOut, isTrue);
  });

  test('a Function 401 for a refused key is the key, by code or by words', () {
    expect(functionInvokeError(401, 'x', code: 'invalid_public_key'),
        isA<KoolbaseInvalidPublicKeyException>());
    expect(functionInvokeError(401, kInvalidPublicKeyMessage),
        isA<KoolbaseInvalidPublicKeyException>());
    expect(functionInvokeError(401, 'session over'),
        isA<KoolbaseUnauthenticatedException>());
  });

  test('a body names a refused key, and only that', () {
    expect(invalidPublicKeyIn(body), isA<KoolbaseInvalidPublicKeyException>());
    expect(invalidPublicKeyIn('{"code":"unauthenticated"}'), isNull);
    expect(invalidPublicKeyIn('not json'), isNull);
  });

  test('KoolbaseError files it under server, keeping the reason', () {
    final e = KoolbaseError.from(const KoolbaseInvalidPublicKeyException());
    expect(e.code, KoolbaseErrorCode.server);
    expect(e.rawCode, 'invalid_public_key');
  });
}
