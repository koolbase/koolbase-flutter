import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:koolbase_flutter/koolbase_flutter.dart';
import 'package:koolbase_flutter/src/auth/auth_api.dart';

// #244: a rate-limited request says when to try again -- the body's
// retry_after, else the Retry-After header, else nothing.
AuthApi api(Object body, {Map<String, String> headers = const {}}) => AuthApi(
      baseUrl: 'https://api.test',
      publicKey: 'pk_test',
      client: MockClient((req) async => http.Response(jsonEncode(body), 429,
          headers: {'content-type': 'application/json', ...headers})),
    );

Matcher waits(Duration? d) =>
    throwsA(isA<RateLimitException>().having((e) => e.retryAfter, 'retryAfter', d));

void main() {
  test('the body says how long', () {
    expect(
      api({'code': 'rate_limit', 'error': 'too many codes requested; try again later', 'retry_after': 462})
          .requestEmailCode('ama@example.com'),
      waits(const Duration(seconds: 462)),
    );
  });

  test('else the header', () {
    expect(
      api({'code': 'rate_limit', 'error': 'too many requests, please slow down'},
              headers: {'retry-after': '30'})
          .requestEmailCode('ama@example.com'),
      waits(const Duration(seconds: 30)),
    );
  });

  test('a server that says nothing: null, as before', () {
    expect(
      api({'error': 'too many requests'}).requestEmailCode('ama@example.com'),
      waits(null),
    );
  });
}
