// R138: a device registers with the signed-in person's session (the API
// takes the owner from it, never the body), on the app's client; a browser
// registers as web; signing in or out registers the last token again.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:koolbase_flutter/koolbase_flutter.dart';

void main() {
  late List<http.Request> sent;
  late MockClient client;
  String? session;

  setUp(() {
    sent = [];
    session = null;
    client = MockClient((r) async {
      sent.add(r);
      return http.Response('{"registered":true}', 200);
    });
  });

  KoolbaseMessaging messaging() => KoolbaseMessaging(
    baseUrl: 'http://koolbase.test',
    apiKey: 'pk_test',
    accessTokenProvider: () async => session,
    httpClient: client,
  )..setDeviceId('device-1');

  test('signed out: the publishable key alone, an ownerless device', () async {
    expect(await messaging().registerToken(token: 'fcm-1', platform: 'android'), isTrue);
    expect(sent.single.url.path, '/v1/messaging/register');
    expect(sent.single.headers['x-api-key'], 'pk_test');
    expect(sent.single.headers.containsKey('Authorization'), isFalse);
    expect(jsonDecode(sent.single.body), {'device_id': 'device-1', 'token': 'fcm-1', 'platform': 'android'});
  });

  test('signed in: the session goes with it, so the device is theirs', () async {
    session = 'access-1';
    await messaging().registerToken(token: 'fcm-1', platform: 'ios', userId: 'ignored');
    expect(sent.single.headers['Authorization'], 'Bearer access-1');
    expect((jsonDecode(sent.single.body) as Map).containsKey('user_id'), isFalse);
  });

  test('a browser registers as web; anything else is refused before sending', () async {
    final m = messaging();
    expect(await m.registerToken(token: 'fcm-w', platform: 'web'), isTrue);
    expect(await m.registerToken(token: 'fcm-x', platform: 'windows'), isFalse);
    expect(sent, hasLength(1));
  });

  test('signing in or out registers the last token again -- nothing before one', () async {
    final m = messaging();
    await m.sessionChanged();
    expect(sent, isEmpty);
    await m.registerToken(token: 'fcm-1', platform: 'android');
    session = 'access-2';
    await m.sessionChanged();
    expect(sent, hasLength(2));
    expect(sent.last.headers['Authorization'], 'Bearer access-2');
    expect((jsonDecode(sent.last.body) as Map)['token'], 'fcm-1');
    session = null;
    await m.sessionChanged();
    expect(sent.last.headers.containsKey('Authorization'), isFalse);
  });

  test('initializeForTesting registers on the test\'s client', () async {
    Koolbase.initializeForTesting(httpClient: client);
    addTearDown(Koolbase.resetForTesting);
    expect(await Koolbase.messaging.registerToken(token: 'fcm-t', platform: 'android'), isTrue);
    expect(jsonDecode(sent.single.body), {'device_id': 'test-device', 'token': 'fcm-t', 'platform': 'android'});
  });
}
