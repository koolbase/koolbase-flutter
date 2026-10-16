import 'package:flutter_test/flutter_test.dart';
import 'package:koolbase_flutter/koolbase_flutter.dart';

// Storage S6: an upload refused for malware, and a quarantined file, each
// arrive as their own exception -- by code, and a 423 without one.
void main() {
  test('malware_found is its own exception, with the server message', () {
    final e = koolbaseStorageError(422, {
      'error': 'malware found: Eicar-Signature',
      'code': 'malware_found',
    });
    expect(e, isA<KoolbaseStorageMalwareException>());
    expect(e.message, 'malware found: Eicar-Signature');
    expect(e.code, 'malware_found');
  });

  test('quarantined is its own exception, by code or by 423', () {
    expect(
      koolbaseStorageError(423, {'error': 'x', 'code': 'quarantined'}),
      isA<KoolbaseStorageQuarantinedException>(),
    );
    final bare = koolbaseStorageError(423, {'error': 'locked'});
    expect(bare, isA<KoolbaseStorageQuarantinedException>());
    expect(bare.code, 'quarantined');
  });

  test('both are storage exceptions an app can catch together', () {
    expect(const KoolbaseStorageMalwareException(), isA<KoolbaseStorageException>());
    expect(const KoolbaseStorageQuarantinedException(), isA<KoolbaseStorageException>());
  });
}
