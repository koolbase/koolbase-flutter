import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:koolbase_flutter/koolbase_flutter.dart';

// 12.29.1: a file's path reaches the server as itself in every storage query.
// A name is a person's: "&", "#", "+", "%" and spaces are in real ones.
void main() {
  const path = 'notes/Q&A #1 + 100%.pdf';
  const versionId = 'v/1';

  Future<List<http.Request>> calls(Future<void> Function(KoolbaseStorageClient s) run) async {
    final seen = <http.Request>[];
    final client = MockClient((req) async {
      seen.add(req);
      if (req.url.path.endsWith('/download-url')) {
        return http.Response(jsonEncode({'url': 'https://signed.example/x'}), 200);
      }
      if (req.method == 'DELETE') return http.Response('', 204);
      if (req.url.path == '/v1/sdk/storage/object-versions') {
        return http.Response(jsonEncode({'versions': []}), 200);
      }
      return http.Response('{}', 500);
    });
    await http.runWithClient(
      () => run(KoolbaseStorageClient(baseUrl: 'https://api.example.com', publicKey: 'pk_test_x')),
      () => client,
    );
    return seen;
  }

  test('getDownloadUrl sends the path, the bucket and the version as they are', () async {
    final seen = await calls((s) async {
      expect(await s.getDownloadUrl(bucket: 'docs', path: path), 'https://signed.example/x');
      await s.getDownloadUrl(bucket: 'docs', path: path, versionId: versionId);
    });
    expect(seen[0].url.path, '/v1/sdk/storage/download-url');
    expect(seen[0].url.queryParameters, {'bucket': 'docs', 'path': path});
    expect(seen[1].url.queryParameters, {'bucket': 'docs', 'path': path, 'version_id': versionId});
  });

  test('getDownloadUrl names a preset when given one, none when empty', () async {
    final seen = await calls((s) async {
      await s.getDownloadUrl(bucket: 'vault', path: path, preset: 'card');
      await s.getDownloadUrl(bucket: 'vault', path: path, preset: '');
    });
    expect(seen[0].url.queryParameters, {'bucket': 'vault', 'path': path, 'preset': 'card'});
    expect(seen[1].url.queryParameters, {'bucket': 'vault', 'path': path});
  });

  test('the version requests send the path as it is, the version id as one segment', () async {
    final seen = await calls((s) async {
      await s.listVersions(bucket: 'docs', path: path);
      // Answered 500 here: only the request is under test.
      await expectLater(s.getVersion(bucket: 'docs', path: path, versionId: versionId), throwsA(anything));
      await expectLater(s.restoreVersion(bucket: 'docs', path: path, versionId: versionId), throwsA(anything));
      await s.purgeVersion(bucket: 'docs', path: path, versionId: versionId);
    });
    for (final r in seen) {
      expect(r.url.queryParameters, {'bucket': 'docs', 'path': path}, reason: '${r.method} ${r.url}');
    }
    expect(seen[0].url.path, '/v1/sdk/storage/object-versions');
    expect(seen[1].url.pathSegments.last, versionId);
    expect(seen[2].url.pathSegments.reversed.skip(1).first, versionId);
    expect(seen[3].method, 'DELETE');
    expect(seen[3].url.pathSegments.last, versionId);
  });
}
