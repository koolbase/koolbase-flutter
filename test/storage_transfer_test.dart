// S1: an upload you can follow and cancel, and a bucket's files listed.
//
// The server and storage are a scripted MockClient: the presign answers
// with an upload_id, the PUT is read a chunk at a time (as a connection
// takes it), and the confirm must name the upload.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:koolbase_flutter/koolbase_flutter.dart';

const _base = 'https://api.test';

KoolbaseStorageClient _client() => KoolbaseStorageClient(baseUrl: _base, publicKey: 'pk_test');

Map<String, dynamic> _object(String path, int size) => {
      'id': 'o1',
      'project_id': 'p1',
      'bucket_id': 'b1',
      'r2_bucket': 'koolbase-storage',
      'path': path,
      'size': size,
      'content_type': 'image/png',
      'metadata': <String, dynamic>{},
      'created_at': '2026-10-15T10:00:00Z',
      'updated_at': '2026-10-15T10:00:00Z',
    };

/// A server that serves one upload; [onChunk] runs as each PUT chunk is read.
MockClient _server({
  required List<String> calls,
  void Function(int read)? onChunk,
  Map<String, dynamic>? confirmed,
}) =>
    MockClient.streaming((req, body) async {
      final path = req.url.path;
      calls.add('${req.method} $path');
      if (path.endsWith('/upload-url')) {
        return http.StreamedResponse(
          Stream.value(utf8.encode(jsonEncode({'upload_url': 'https://r2.test/stage/x', 'file_key': 'k', 'upload_id': 'up-1'}))),
          200,
        );
      }
      if (req.url.host == 'r2.test') {
        var read = 0;
        await for (final chunk in body) {
          read += chunk.length;
          onChunk?.call(read);
        }
        return http.StreamedResponse(const Stream.empty(), 200, headers: {'etag': '"e1"'});
      }
      if (path.endsWith('/confirm')) {
        final sent = jsonDecode(utf8.decode(await body.toBytes())) as Map<String, dynamic>;
        confirmed?.addAll(sent);
        return http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(_object(sent['path'] as String, sent['size'] as int)))), 201);
      }
      if (path.endsWith('/download-url')) {
        return http.StreamedResponse(Stream.value(utf8.encode(jsonEncode({'url': 'https://r2.test/signed'}))), 200);
      }
      return http.StreamedResponse(Stream.value(utf8.encode('{"error":"unexpected"}')), 500);
    });

void main() {
  test('an upload reports pending, the bytes sent, verifying, then completed', () async {
    final calls = <String>[];
    final confirmed = <String, dynamic>{};
    final bytes = List<int>.filled(200 * 1024, 7);
    final seen = <KoolbaseUploadProgress>[];
    final result = await http.runWithClient(
      () => _client().uploadBytes(bucket: 'posters', path: 'gig.png', bytes: bytes, onProgress: seen.add),
      () => _server(calls: calls, confirmed: confirmed),
    );
    expect(result.object.path, 'gig.png');
    final states = seen.map((p) => p.state).toSet();
    expect(states, containsAll([KoolbaseUploadState.uploading, KoolbaseUploadState.verifying, KoolbaseUploadState.completed]));
    final sent = seen.where((p) => p.state == KoolbaseUploadState.uploading).map((p) => p.bytesSent).toList();
    expect(sent.length, greaterThan(2), reason: 'reported a chunk at a time');
    for (var i = 1; i < sent.length; i++) {
      expect(sent[i], greaterThanOrEqualTo(sent[i - 1]));
    }
    expect(sent.last, bytes.length);
    expect(seen.last.state, KoolbaseUploadState.completed);
    expect(seen.last.fraction, 1.0);
    // The confirm names its upload.
    expect(confirmed['upload_id'], 'up-1');
    expect(calls.first, 'POST /v1/sdk/storage/upload-url');
  });

  test('cancelled while sending: nothing is confirmed', () async {
    final calls = <String>[];
    late KoolbaseUploadTask task;
    final outcome = await http.runWithClient(() async {
      task = _client().startUpload(bucket: 'posters', path: 'gig.png', bytes: List<int>.filled(512 * 1024, 1));
      try {
        await task.result;
        return 'completed';
      } on KoolbaseUploadCancelledException {
        return 'cancelled';
      }
    }, () => _server(calls: calls, onChunk: (read) {
          if (read >= 128 * 1024) task.cancel();
        }));
    expect(outcome, 'cancelled');
    expect(task.current.state, KoolbaseUploadState.cancelled);
    expect(calls.where((c) => c.endsWith('/confirm')), isEmpty);
    expect(task.cancel(), isFalse, reason: 'already over');
  });

  test('a page of files, and the next', () async {
    final asked = <Uri>[];
    final page = await http.runWithClient(
      () => _client().listFiles(bucket: 'posters', prefix: 'events/', limit: 2, sort: KoolbaseFileSort.createdAt, descending: true),
      () => MockClient((req) async {
        asked.add(req.url);
        return http.Response(
            jsonEncode({
              'files': [
                {
                  'path': 'events/a.png',
                  'size': 3,
                  'metadata': {'shared': 'yes'},
                  'created_at': '2026-10-15T10:00:00Z',
                  'updated_at': '2026-10-15T10:00:00Z',
                  'public_url': 'https://cdn.test/a.png',
                },
              ],
              'next_cursor': 'abc',
            }),
            200);
      }),
    );
    expect(asked.single.path, '/v1/sdk/storage/files');
    expect(asked.single.queryParameters, {
      'bucket': 'posters',
      'prefix': 'events/',
      'limit': '2',
      'sort': 'created_at',
      'order': 'desc',
    });
    expect(page.files.single.name, 'a.png');
    expect(page.files.single.metadata['shared'], 'yes');
    expect(page.files.single.publicUrl, 'https://cdn.test/a.png');
    expect(page.hasMore, isTrue);
    expect(page.nextCursor, 'abc');
  });

  test('errors arrive typed', () async {
    Future<Object?> failWith(int status, String code) async {
      try {
        await http.runWithClient(
          () => _client().getFileInfo(bucket: 'posters', path: 'x.png'),
          () => MockClient((_) async => http.Response(jsonEncode({'error': 'no', 'code': code}), status)),
        );
      } catch (e) {
        return e;
      }
      return null;
    }

    expect(await failWith(503, 'bucket_busy'), isA<KoolbaseStorageBusyException>());
    expect(await failWith(400, 'invalid_cursor'), isA<KoolbaseStorageInvalidCursorException>());
    expect(await failWith(404, 'upload_not_found'), isA<KoolbaseUploadNotFoundException>());
    // Nobody signed in: not a session that ended.
    expect(await failWith(401, 'sign_in_required'), isA<KoolbaseStorageSignInRequiredException>());
    expect(await failWith(403, 'not_allowed'), isA<KoolbaseStoragePermissionException>());
  });
}
