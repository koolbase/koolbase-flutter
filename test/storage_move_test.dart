// S1b: moving and copying a file. The request each sends, the file that
// comes back, and the refusals, typed.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:koolbase_flutter/koolbase_flutter.dart';

KoolbaseStorageClient _client() => KoolbaseStorageClient(baseUrl: 'https://api.test', publicKey: 'pk_test');

Map<String, dynamic> _object(String path) => {
      'id': 'o2',
      'project_id': 'p1',
      'bucket_id': 'b2',
      'r2_bucket': 'koolbase-storage',
      'path': path,
      'size': 4,
      'content_type': 'image/png',
      'metadata': <String, dynamic>{},
      'created_at': '2026-10-16T10:00:00Z',
      'updated_at': '2026-10-16T10:00:00Z',
    };

void main() {
  test('a move to another bucket names both, and returns the moved file', () async {
    final sent = <String, dynamic>{};
    late Uri asked;
    final moved = await http.runWithClient(
      () => _client().move(bucket: 'inbox', from: 'scan.png', toBucket: 'vault', to: '2026/scan.png'),
      () => MockClient((req) async {
        asked = req.url;
        sent.addAll(jsonDecode(req.body) as Map<String, dynamic>);
        return http.Response(jsonEncode(_object('2026/scan.png')), 201);
      }),
    );
    expect(asked.path, '/v1/sdk/storage/move');
    expect(sent, {'bucket': 'inbox', 'from': 'scan.png', 'to': '2026/scan.png', 'to_bucket': 'vault'});
    expect(moved.path, '2026/scan.png');
  });

  test('a copy within a bucket sends no destination bucket', () async {
    final sent = <String, dynamic>{};
    late Uri asked;
    await http.runWithClient(
      () => _client().copy(bucket: 'media', from: 'a.png', to: 'copies/a.png'),
      () => MockClient((req) async {
        asked = req.url;
        sent.addAll(jsonDecode(req.body) as Map<String, dynamic>);
        return http.Response(jsonEncode(_object('copies/a.png')), 201);
      }),
    );
    expect(asked.path, '/v1/sdk/storage/copy');
    expect(sent.containsKey('to_bucket'), isFalse);
  });

  test('refusals arrive typed', () async {
    Future<Object?> failWith(int status, Map<String, dynamic> body) async {
      try {
        await http.runWithClient(
          () => _client().move(bucket: 'posters', from: 'gig.png', to: 'old/gig.png'),
          () => MockClient((_) async => http.Response(jsonEncode(body), status)),
        );
      } catch (e) {
        return e;
      }
      return null;
    }

    final inUse = await failWith(409, {
      'error': 'Used by 2 records in events.poster.',
      'code': 'file_in_use',
      'details': {'field': 'events.poster', 'records': 2},
    });
    expect(inUse, isA<KoolbaseStorageFileInUseException>());
    expect((inUse as KoolbaseStorageFileInUseException).field, 'events.poster');
    expect(inUse.records, 2);
    expect(await failWith(409, {'error': 'x', 'code': 'name_has_history'}), isA<KoolbaseStorageNameHasHistoryException>());
    expect(await failWith(409, {'error': 'x', 'code': 'path_conflict', 'path': 'old/gig.png'}), isA<KoolbaseStorageConflictException>());
    expect(await failWith(403, {'error': 'x', 'code': 'not_allowed'}), isA<KoolbaseStoragePermissionException>());
    expect(await failWith(413, {'error': 'x', 'code': 'file_too_large'}), isA<KoolbaseStorageFileTooLargeException>());
  });
}
