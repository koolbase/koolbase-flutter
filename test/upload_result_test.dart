import 'package:flutter_test/flutter_test.dart';
import 'package:koolbase_flutter/koolbase_flutter.dart';

// UploadResult exposes path and publicUrl, not only a signed downloadUrl.
//
// The Designer's exporter reads upload-result fields generically as
// `_r_upload?.<field>`. UploadResult had only object and downloadUrl, so a
// binding to an upload's `path` emitted code that did not compile — and path
// is the field KB-STORE-001 tells the assistant to persist. There was also no
// way to reach a stable public URL, which setting a profile photo needs:
// downloadUrl is signed and expires.

Map<String, dynamic> confirmResponse({String r2Bucket = 'koolbase-storage-public'}) => {
      'id': 'obj_1',
      'project_id': 'proj_1',
      'bucket_id': 'bkt_1',
      'r2_bucket': r2Bucket,
      'path': 'avatars/user 1/photo.jpg',
      'size': 1024,
      'content_type': 'image/jpeg',
      'created_at': '2026-09-21T06:00:00Z',
      'updated_at': '2026-09-21T06:00:00Z',
    };

void main() {
  group('UploadResult', () {
    test('path is the object path', () {
      final r = UploadResult(
        object: KoolbaseObject.fromJson(confirmResponse()),
        downloadUrl: 'https://signed.example/x?sig=abc',
        bucket: 'avatars',
      );
      expect(r.path, 'avatars/user 1/photo.jpg');
    });

    test('publicUrl is a stable CDN URL for a public bucket', () {
      // Decoded from a confirm-shaped response rather than built by hand, so
      // this also covers fromJson reading r2_bucket — the field that decides
      // public vs private, and which defaults to PRIVATE when absent.
      final r = UploadResult(
        object: KoolbaseObject.fromJson(confirmResponse()),
        downloadUrl: 'https://signed.example/x?sig=abc',
        bucket: 'avatars',
      );
      expect(r.publicUrl, isNotNull);
      expect(r.publicUrl, startsWith('https://cdn.koolbase.com/proj_1/avatars/'));
      // Path segments are encoded: a space must not survive raw.
      expect(r.publicUrl, contains('user%201'));
      // And it is not the signed URL: that one expires.
      expect(r.publicUrl, isNot(contains('sig=')));
    });

    test('publicUrl is null for a private bucket', () {
      final r = UploadResult(
        object: KoolbaseObject.fromJson(confirmResponse(r2Bucket: 'koolbase-storage')),
        downloadUrl: 'https://signed.example/x?sig=abc',
        bucket: 'receipts',
      );
      expect(r.publicUrl, isNull);
    });

    test('a confirm response without r2_bucket reads as private', () {
      // The fromJson default. If the API ever stopped sending r2_bucket,
      // every upload would report a null publicUrl, public bucket or not —
      // this pins that behaviour so the dependency on the field is visible.
      final json = confirmResponse()..remove('r2_bucket');
      final r = UploadResult(
        object: KoolbaseObject.fromJson(json),
        downloadUrl: 'https://signed.example/x',
        bucket: 'avatars',
      );
      expect(r.publicUrl, isNull);
    });

    test('publicUrl is null when the bucket is unknown', () {
      final r = UploadResult(
        object: KoolbaseObject.fromJson(confirmResponse()),
        downloadUrl: 'https://signed.example/x',
      );
      expect(r.publicUrl, isNull);
    });

    test('downloadUrl is unchanged', () {
      final r = UploadResult(
        object: KoolbaseObject.fromJson(confirmResponse()),
        downloadUrl: 'https://signed.example/x?sig=abc',
        bucket: 'avatars',
      );
      expect(r.downloadUrl, 'https://signed.example/x?sig=abc');
    });
  });
}
