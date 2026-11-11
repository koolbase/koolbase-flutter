import 'package:flutter_test/flutter_test.dart';
import 'package:koolbase_flutter/koolbase_flutter.dart';

// The version policy exactly as the API sends it (bootstrap "version", Nov
// 2026): the app's own platform's policy, with store_url when one is set.
KoolbasePayload _payload(Map<String, dynamic> version) => KoolbasePayload.fromJson({
      'payload_version': '1',
      'flags': <String, dynamic>{},
      'config': <String, dynamic>{},
      'version': version,
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const store = 'https://apps.apple.com/app/id123';

  test('a forced update carries the store link', () {
    Koolbase.initializeForTesting(
      appVersion: '1.9.0',
      payload: _payload({'min_version': '2.0.0', 'latest_version': '2.1.0', 'force_update': false, 'update_message': 'Update', 'store_url': store}),
    );
    final r = Koolbase.checkVersion();
    expect(r.status, VersionStatus.forceUpdate);
    expect(r.storeUrl, store);
  });

  test('a suggested update carries it too', () {
    Koolbase.initializeForTesting(
      appVersion: '2.0.0',
      payload: _payload({'min_version': '1.0.0', 'latest_version': '2.1.0', 'force_update': false, 'update_message': 'New', 'store_url': store}),
    );
    final r = Koolbase.checkVersion();
    expect(r.status, VersionStatus.softUpdate);
    expect(r.storeUrl, store);
  });

  test('no store link set: null', () {
    Koolbase.initializeForTesting(
      appVersion: '1.0.0',
      payload: _payload({'min_version': '2.0.0', 'latest_version': '2.0.0', 'force_update': false, 'update_message': 'Update'}),
    );
    expect(Koolbase.checkVersion().storeUrl, isNull);
  });

  test('up to date: no store link', () {
    Koolbase.initializeForTesting(
      appVersion: '2.0.0',
      payload: _payload({'min_version': '1.0.0', 'latest_version': '2.0.0', 'force_update': false, 'update_message': '', 'store_url': store}),
    );
    final r = Koolbase.checkVersion();
    expect(r.status, VersionStatus.upToDate);
    expect(r.storeUrl, isNull);
  });

  test('the saved copy keeps the store link', () {
    final p = KoolbaseVersionPolicy.fromJson({'min_version': '1.0.0', 'store_url': store});
    expect(KoolbaseVersionPolicy.fromJson(p.toJson()).storeUrl, store);
  });
}
