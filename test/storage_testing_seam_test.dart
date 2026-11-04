// R123 (A5): Koolbase.initializeForTesting answers storage on the test's
// client -- the API calls and an upload's bytes alike -- so a test plays the
// storage server, holds an upload open and cancels it, through the SDK's own
// storage code.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:koolbase_flutter/koolbase_flutter.dart';

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

Map<String, Object?> _object(String path) => {
      'id': 'o_$path',
      'project_id': 'test-project',
      'bucket_id': 'b1',
      'path': path,
      'size': 3,
      'content_type': 'text/plain',
      'created_at': '2026-01-01T00:00:00Z',
      'updated_at': '2026-01-01T00:00:00Z',
    };

/// A pretend storage server; [hold] keeps the next upload's bytes waiting.
class _Storage {
  final asked = <String>[];
  Completer<void>? hold;

  late final MockClient client = MockClient((req) async {
    asked.add('${req.method} ${req.url.path}');
    final body = req.url.path.startsWith('/v1/') && req.body.isNotEmpty
        ? jsonDecode(req.body) as Map<String, dynamic>
        : const <String, dynamic>{};
    switch (req.url.path) {
      case '/v1/sdk/storage/upload-url':
        return _json({'upload_url': 'http://localhost/put/${body['path']}'});
      case '/v1/sdk/storage/confirm':
        return _json(_object(body['path'] as String), 201);
      case '/v1/sdk/storage/download-url':
        return _json({'url': 'http://localhost/get/${req.url.queryParameters['path']}'});
      case '/v1/sdk/storage/copy' || '/v1/sdk/storage/move':
        return _json(_object(body['to'] as String), 201);
    }
    if (req.url.path.startsWith('/put/')) {
      final h = hold;
      if (h != null) await h.future;
      return http.Response('', 200, headers: {'etag': '"e1"'});
    }
    return _json({}, 404);
  });
}

void main() {
  tearDown(Koolbase.resetForTesting);

  test('an upload, a copy and a move go to the test\'s client', () async {
    final s = _Storage();
    Koolbase.initializeForTesting(httpClient: s.client);
    final up = await Koolbase.storage.uploadBytes(bucket: 'docs', path: 'a/notes.txt', bytes: [1, 2, 3]);
    expect(up.object.path, 'a/notes.txt');
    final copied = await Koolbase.storage.copy(bucket: 'docs', from: 'a/notes.txt', to: 'b/notes.txt');
    expect(copied.path, 'b/notes.txt');
    await Koolbase.storage.move(bucket: 'docs', from: 'b/notes.txt', to: 'c/notes.txt');
    expect(s.asked, [
      'POST /v1/sdk/storage/upload-url',
      'PUT /put/a/notes.txt',
      'POST /v1/sdk/storage/confirm',
      'GET /v1/sdk/storage/download-url',
      'POST /v1/sdk/storage/copy',
      'POST /v1/sdk/storage/move',
    ]);
  });

  test('an upload held open is cancelled; the test\'s client stays usable', () async {
    final s = _Storage()..hold = Completer<void>();
    Koolbase.initializeForTesting(httpClient: s.client);
    final task = Koolbase.storage.startUpload(bucket: 'docs', path: 'a/big.txt', bytes: [1, 2, 3]);
    while (!s.asked.contains('PUT /put/a/big.txt')) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(task.cancel(), isTrue);
    s.hold!.complete();
    await expectLater(task.result, throwsA(isA<KoolbaseUploadCancelledException>()));
    expect(s.asked, isNot(contains('POST /v1/sdk/storage/confirm')), reason: 'cancelled before the server checked it');
    // The shared client was lent, not closed: the next upload goes through.
    s.hold = null;
    final again = await Koolbase.storage.uploadBytes(bucket: 'docs', path: 'a/big.txt', bytes: [1, 2, 3]);
    expect(again.object.path, 'a/big.txt');
  });
}
