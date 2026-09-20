import 'package:flutter_test/flutter_test.dart';
import 'package:koolbase_flutter/src/auth/device_metadata.dart';

// The exact header set this SDK sends.
//
// The API declares what it allows in platform/clientheaders and derives its
// CORS list from it. This is the other end: adding a header here fails this
// test, which is the prompt to add it there first.
//
// That matters because of how the failure looks when it goes wrong. A
// browser refuses a request whose preflight does not list the headers it
// carries, and the server never sees it — nothing logged, no error raised.
// On 18 September 2026 the API's allowance was missing all six identity
// headers and every authenticated call from @koolbase/js failed, on every
// endpoint, silently. Flutter is native and never preflights, so it would
// not have noticed — which is exactly why this test exists here too: this
// SDK can drift without symptom.

const expected = <String>{
  // Native clients may set User-Agent, and this one does. A browser sets it
  // automatically and forbids JavaScript from changing it, which is why the
  // six below exist: they carry what it says for clients that cannot send
  // it. The server reads both.
  'User-Agent',
  'x-koolbase-sdk',
  'x-koolbase-sdk-version',
  'x-koolbase-platform',
  'x-koolbase-platform-version',
  'x-koolbase-app-version',
  'x-koolbase-device-label',
};

const sample = DeviceMetadata(
  platform: 'ios',
  platformVersion: '18.2',
  sdkVersion: '12.4.0',
  appVersion: '1.2.3+45',
  deviceLabel: 'device-abc',
);

void main() {
  group('device headers', () {
    test('sends exactly the set the API knows about', () {
      expect(sample.toHeaders().keys.toSet(), expected);
    });

    test('every header carries a value', () {
      // An empty header is stored as nothing, which looks like an SDK that
      // never reported itself rather than one that reported blank.
      sample.toHeaders().forEach((name, value) {
        expect(value, isNotEmpty, reason: '$name is empty');
      });
    });

    test('the User-Agent identifies the SDK and the host', () {
      // The server reads this into session records for every client. It
      // should say which SDK and what it is running on, not just a version.
      final ua = sample.toHeaders()['User-Agent']!;
      expect(ua, contains('koolbase-flutter'));
      expect(ua, contains('12.4.0'));
      expect(ua, contains('ios'));
    });
  });
}
