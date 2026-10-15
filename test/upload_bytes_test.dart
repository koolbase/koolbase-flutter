import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:koolbase_flutter/koolbase_flutter.dart';

// uploadBytes (12.24.0): a file's contents uploaded with no file on disk --
// what the web has, where a picked file has bytes but no path. The same
// three steps as upload: an upload address, the bytes, the confirmation.
void main() {
  test('the bytes go to the upload address, and the object comes back',
      () async {
    final calls = <String>[];
    List<int>? sent;
    String? sentType;
    final client = MockClient((req) async {
      calls.add('${req.method} ${req.url.path}');
      switch (req.url.path) {
        case '/v1/sdk/storage/upload-url':
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          expect(body['path'], 'events/1_poster.png');
          expect(body['content_type'], 'image/png');
          return http.Response(
              jsonEncode({'upload_url': 'https://r2.example/put'}), 200);
        case '/put':
          sent = req.bodyBytes;
          sentType = req.headers['Content-Type'];
          return http.Response('', 200, headers: {'etag': '"abc"'});
        case '/v1/sdk/storage/confirm':
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          expect(body['size'], 3);
          return http.Response(
            jsonEncode({
              'id': 'obj_1',
              'project_id': 'proj_1',
              'bucket_id': 'bkt_1',
              'r2_bucket': 'koolbase-storage-public',
              'path': 'events/1_poster.png',
              'size': 3,
              'content_type': 'image/png',
              'created_at': '2026-10-15T09:00:00Z',
              'updated_at': '2026-10-15T09:00:00Z',
            }),
            201,
          );
        case '/v1/sdk/storage/download-url':
          return http.Response(
              jsonEncode({'url': 'https://signed.example/x'}), 200);
      }
      return http.Response('not found', 404);
    });

    final result = await http.runWithClient(
      () => KoolbaseStorageClient(
        baseUrl: 'https://api.example.com',
        publicKey: 'pk_test_x',
      ).uploadBytes(
        bucket: 'posters',
        path: 'events/1_poster.png',
        bytes: const [1, 2, 3],
      ),
      () => client,
    );

    expect(sent, [1, 2, 3]);
    expect(sentType, 'image/png');
    expect(result.path, 'events/1_poster.png');
    expect(result.bucket, 'posters');
    expect(calls, [
      'POST /v1/sdk/storage/upload-url',
      'PUT /put',
      'POST /v1/sdk/storage/confirm',
      'GET /v1/sdk/storage/download-url',
    ]);
  });

  test('a refused upload address throws, as upload does', () async {
    final client = MockClient((req) async => http.Response(
          jsonEncode({'code': 'permission_denied', 'error': 'no'}),
          403,
        ));
    await expectLater(
      http.runWithClient(
        () => KoolbaseStorageClient(
          baseUrl: 'https://api.example.com',
          publicKey: 'pk_test_x',
        ).uploadBytes(bucket: 'posters', path: 'a.png', bytes: const [1]),
        () => client,
      ),
      throwsA(isA<KoolbaseException>()),
    );
  });
}
