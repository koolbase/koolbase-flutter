// S3: a large file's upload in parts, and a download you can follow.
//
// The server and storage are one scripted MockClient: small parts, signed
// links, a connection that drops, a link that has expired.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:koolbase_flutter/koolbase_flutter.dart';

const _part = 4;
const _content = 'abcdefghijklmnopqrstuvwxyz0123'; // 30 bytes: 8 parts, the last of 2

class _World {
  final parts = <int, String>{};
  final calls = <String>[];
  final bodies = <String, Map<String, dynamic>>{};
  final drops = <int, int>{};
  final expireOnce = <int>{};
  final linkVersion = <int, int>{};
  void Function(int part)? onPart;
  int size = 0;

  Map<String, dynamic> plan(String path) => {
        'upload_id': 'mp-1',
        'path': path,
        'size': size,
        'part_size': _part,
        'part_count': (size + _part - 1) ~/ _part,
        'content_type': 'video/mp4',
      };

  http.StreamedResponse _json(Object body, [int status = 200]) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status);

  late final client = MockClient.streaming((req, body) async {
    final u = req.url;
    calls.add('${req.method} ${u.path}');
    if (u.host == 'r2.test' && u.path.startsWith('/part/')) {
      final n = int.parse(u.pathSegments.last);
      final v = int.parse(u.queryParameters['v']!);
      onPart?.call(n);
      final got = utf8.decode(await body.toBytes());
      final left = drops[n] ?? 0;
      if (left > 0) {
        drops[n] = left - 1;
        throw http.ClientException('connection dropped');
      }
      if (expireOnce.contains(n) && v == 1) {
        return http.StreamedResponse(const Stream.empty(), 403);
      }
      parts[n] = got;
      return http.StreamedResponse(const Stream.empty(), 200);
    }
    if (u.host == 'r2.test' && u.path == '/file') {
      return http.StreamedResponse(Stream.fromIterable([utf8.encode('12345'), utf8.encode('67890')]), 200, contentLength: 10);
    }
    final sent = req.method == 'GET' ? <String, dynamic>{} : (jsonDecode(utf8.decode(await body.toBytes())) as Map<String, dynamic>? ?? {});
    bodies['${req.method} ${u.path}'] = sent;
    switch ('${req.method} ${u.path}') {
      case 'POST /v1/sdk/storage/uploads':
        size = sent['size'] as int;
        return _json(plan(sent['path'] as String), 201);
      case 'GET /v1/sdk/storage/uploads':
        return _json({...plan('talks/keynote.mp4'), 'uploaded': (parts.keys.toList()..sort())});
      case 'DELETE /v1/sdk/storage/uploads':
        return http.StreamedResponse(const Stream.empty(), 204);
      case 'POST /v1/sdk/storage/uploads/parts':
        final links = <String, String>{};
        for (final n in (sent['parts'] as List).cast<int>()) {
          final v = (linkVersion[n] ?? 0) + 1;
          linkVersion[n] = v;
          links['$n'] = 'https://r2.test/part/$n?v=$v';
        }
        return _json({'links': links});
      case 'POST /v1/sdk/storage/uploads/complete':
        return _json({
          'id': 'o1',
          'project_id': 'p1',
          'bucket_id': 'b1',
          'r2_bucket': 'koolbase-storage',
          'path': 'talks/keynote.mp4',
          'size': size,
          'content_type': 'video/mp4',
          'metadata': <String, dynamic>{},
          'created_at': '2026-10-16T10:00:00Z',
          'updated_at': '2026-10-16T10:00:00Z',
        }, 201);
      case 'GET /v1/sdk/storage/download-url':
        return _json({'url': 'https://r2.test/file'});
    }
    return _json({'error': 'unexpected ${req.method} ${u.path}'}, 500);
  });

  String whole() => ([...parts.keys]..sort()).map((n) => parts[n]).join();
  int count(String call) => calls.where((c) => c == call).length;
}

KoolbaseStorageClient _storage() => KoolbaseStorageClient(baseUrl: 'https://api.test', publicKey: 'pk_test');
List<int> _bytes(String s) => utf8.encode(s);

void main() {
  late _World world;
  final threshold = KoolbaseStorageClient.multipartThreshold;
  setUp(() {
    world = _World();
    KoolbaseStorageClient.multipartThreshold = 10;
    koolbasePartRetryDelay = (_) => Duration.zero;
  });
  tearDown(() => KoolbaseStorageClient.multipartThreshold = threshold);

  test('a large file goes up in parts: every part, the bytes rising to the whole, then completed', () async {
    final seen = <KoolbaseUploadProgress>[];
    late KoolbaseUploadTask task;
    final res = await http.runWithClient(() {
      task = _storage().startUpload(bucket: 'video', path: 'talks/keynote.mp4', bytes: _bytes(_content), metadata: {'talk': 'keynote'});
      task.progress.listen(seen.add);
      return task.result;
    }, () => world.client);
    expect(world.whole(), _content);
    expect(res.object.path, 'talks/keynote.mp4');
    expect(task.uploadId, 'mp-1');
    expect(world.count('POST /v1/sdk/storage/upload-url'), 0);
    expect(world.bodies['POST /v1/sdk/storage/uploads/complete'], {
      'bucket': 'video',
      'upload_id': 'mp-1',
      'overwrite': false,
      'metadata': {'talk': 'keynote'},
    });
    final sent = seen.where((p) => p.state == KoolbaseUploadState.uploading).map((p) => p.bytesSent).toList();
    expect(sent.reduce((a, b) => a > b ? a : b), 30);
    expect(seen.last.state, KoolbaseUploadState.completed);
  });

  test('a dropped part is sent again; an expired link is renewed', () async {
    world.drops[2] = 2;
    world.expireOnce.add(5);
    await http.runWithClient(
      () => _storage().startUpload(bucket: 'video', path: 'talks/keynote.mp4', bytes: _bytes(_content)).result,
      () => world.client,
    );
    expect(world.whole(), _content);
    expect(world.linkVersion[5], 2);
    expect(world.count('DELETE /v1/sdk/storage/uploads'), 0);
  });

  test('a part that keeps failing fails the upload, which resumes with only what is missing', () async {
    world.drops[3] = 99;
    late KoolbaseUploadTask task;
    Object? failure;
    await http.runWithClient(() async {
      task = _storage().startUpload(bucket: 'video', path: 'talks/keynote.mp4', bytes: _bytes(_content));
      try {
        await task.result;
      } catch (e) {
        failure = e;
      }
    }, () => world.client);
    expect(failure, isA<KoolbaseStorageNetworkException>());
    expect(task.current.state, KoolbaseUploadState.failed);
    expect(task.uploadId, 'mp-1');
    expect(world.count('DELETE /v1/sdk/storage/uploads'), 0);

    world.drops.clear();
    final before = world.parts.keys.toSet();
    final again = <int>[];
    world.onPart = again.add;
    await http.runWithClient(
      () => _storage().resumeUpload(bucket: 'video', uploadId: 'mp-1', bytes: _bytes(_content)).result,
      () => world.client,
    );
    expect(world.whole(), _content);
    expect(again, contains(3));
    expect(again.where(before.contains), isEmpty);
  });

  test('resuming with another file is refused', () async {
    world.size = 30;
    await expectLater(
      http.runWithClient(
        () => _storage().resumeUpload(bucket: 'video', uploadId: 'mp-1', bytes: _bytes('short')).result,
        () => world.client,
      ),
      throwsA(isA<KoolbaseStorageValidationException>()),
    );
  });

  test('cancelled while sending: the upload is abandoned', () async {
    late KoolbaseUploadTask task;
    Object? failure;
    await http.runWithClient(() async {
      task = _storage().startUpload(bucket: 'video', path: 'talks/keynote.mp4', bytes: _bytes(_content));
      world.onPart = (n) {
        if (n == 2) task.cancel();
      };
      try {
        await task.result;
      } catch (e) {
        failure = e;
      }
    }, () => world.client);
    expect(failure, isA<KoolbaseUploadCancelledException>());
    expect(task.current.state, KoolbaseUploadState.cancelled);
    expect(world.count('DELETE /v1/sdk/storage/uploads'), 1);
    expect(world.count('POST /v1/sdk/storage/uploads/complete'), 0);
  });

  test('an incomplete upload is typed, with what is missing', () {
    final e = koolbaseStorageError(409, {
      'code': 'upload_incomplete',
      'error': 'x',
      'details': {
        'missing': [2, 5],
      },
    });
    expect(e, isA<KoolbaseUploadIncompleteException>());
    expect((e as KoolbaseUploadIncompleteException).missing, [2, 5]);
  });

  test('a download reports the bytes as they arrive', () async {
    final seen = <(int, int?)>[];
    final bytes = await http.runWithClient(
      () => _storage().downloadBytes(bucket: 'video', path: 'a.mp4', onProgress: (r, t) => seen.add((r, t))),
      () => world.client,
    );
    expect(utf8.decode(bytes), '1234567890');
    expect(seen, [(0, 10), (5, 10), (10, 10)]);
  });
}
