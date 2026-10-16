// S4: a bucket's files as a list. The controller over the real storage
// client (one scripted MockClient): page one with the listing asked for, the
// next page by cursor, a file never shown twice, stale beats blank, a late
// answer dropped, and lists reloaded after an upload, delete, move or copy
// made through the SDK. Then the widget: loading, the rows, Load more,
// empty, and the error with its retry.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:koolbase_flutter/koolbase_flutter.dart';

KoolbaseStorageClient _client() =>
    KoolbaseStorageClient(baseUrl: 'https://api.test', publicKey: 'pk_test');

Map<String, dynamic> _file(String path) => {
      'path': path,
      'size': 4,
      'content_type': 'image/png',
      'metadata': <String, dynamic>{},
      'created_at': '2026-10-16T10:00:00Z',
      'updated_at': '2026-10-16T10:00:00Z',
    };

Map<String, dynamic> _object(String path) => {
      ..._file(path),
      'id': 'o1',
      'project_id': 'p1',
      'bucket_id': 'b1',
      'r2_bucket': 'koolbase-storage',
    };

/// A server: listings answered per bucket from [files] (two to a page, by
/// cursor), and deletes, moves and copies that change them.
class _Server {
  final files = <String, List<String>>{};
  final asked = <Uri>[];
  bool failing = false;
  Completer<void>? hold;

  late final client = MockClient((req) async {
    final u = req.url;
    if (u.path == '/v1/sdk/storage/files') {
      asked.add(u);
      if (hold != null) await hold!.future;
      if (failing) return http.Response(jsonEncode({'error': 'down'}), 500);
      final all = files[u.queryParameters['bucket']] ?? const [];
      final from = int.tryParse(u.queryParameters['cursor'] ?? '') ?? 0;
      final page = all.skip(from).take(2).toList();
      final next = from + 2 < all.length ? '${from + 2}' : null;
      return http.Response(jsonEncode({'files': page.map(_file).toList(), 'next_cursor': next}), 200);
    }
    if (u.path == '/v1/sdk/storage/object' && req.method == 'DELETE') {
      final b = jsonDecode(req.body) as Map<String, dynamic>;
      files[b['bucket']]?.remove(b['path']);
      return http.Response('', 204);
    }
    if (u.path == '/v1/sdk/storage/move' || u.path == '/v1/sdk/storage/copy') {
      final b = jsonDecode(req.body) as Map<String, dynamic>;
      final to = (b['to_bucket'] ?? b['bucket']) as String;
      if (u.path.endsWith('move')) files[b['bucket']]?.remove(b['from']);
      (files[to] ??= []).add(b['to'] as String);
      return http.Response(jsonEncode(_object(b['to'] as String)), 201);
    }
    return http.Response(jsonEncode({'error': 'unexpected ${req.method} ${u.path}'}), 500);
  });

  List<Uri> listings(String bucket) => asked.where((u) => u.queryParameters['bucket'] == bucket).toList();
}

/// A storage client whose listing answers at once from [files], two to a
/// page; no network.
class _FakeStorage extends KoolbaseStorageClient {
  _FakeStorage(this.files) : super(baseUrl: 'https://api.test', publicKey: 'pk_test');

  final Map<String, List<String>> files;
  bool failing = false;

  @override
  Future<KoolbaseFilePage> listFiles({
    required String bucket,
    String? prefix,
    int? limit,
    String? cursor,
    KoolbaseFileSort sort = KoolbaseFileSort.path,
    bool descending = false,
  }) async {
    if (failing) throw const KoolbaseStorageException('down');
    final all = files[bucket] ?? const [];
    final from = int.tryParse(cursor ?? '') ?? 0;
    final next = from + 2 < all.length ? '${from + 2}' : null;
    return KoolbaseFilePage(
      files: [for (final p in all.skip(from).take(2)) KoolbaseFileInfo.fromJson(_file(p))],
      nextCursor: next,
    );
  }
}

List<String> _paths(KoolbaseFilesController c) => c.files.map((f) => f.path).toList();

Future<void> _settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late _Server server;
  setUp(() => server = _Server());

  test('page one with the listing asked for, then the next by cursor, never a file twice', () async {
    server.files['photos'] = ['a.png', 'b.png', 'c.png'];
    await http.runWithClient(() async {
      final c = KoolbaseFilesController(
        bucket: 'photos',
        prefix: 'trips/',
        sort: KoolbaseFileSort.createdAt,
        descending: true,
        limit: 2,
        storage: _client(),
      );
      expect(c.status, KoolbaseListStatus.loading);
      await c.load();
      expect(c.status, KoolbaseListStatus.loaded);
      expect(_paths(c), ['a.png', 'b.png']);
      expect(c.hasMore, isTrue);
      expect(server.asked.first.queryParameters, {
        'bucket': 'photos',
        'prefix': 'trips/',
        'limit': '2',
        'sort': 'created_at',
        'order': 'desc',
      });
      // A file the next page repeats is shown once.
      server.files['photos'] = ['a.png', 'b.png', 'b.png', 'd.png'];
      await c.loadMore();
      expect(server.asked.last.queryParameters['cursor'], '2');
      expect(_paths(c), ['a.png', 'b.png', 'd.png']);
      expect(c.hasMore, isFalse);
      await c.loadMore();
      expect(server.asked, hasLength(2));
      c.dispose();
    }, () => server.client);
  });

  test('a first load that fails is the error; a failed refresh keeps what is shown', () async {
    server.files['photos'] = ['a.png'];
    server.failing = true;
    await http.runWithClient(() async {
      final c = KoolbaseFilesController(bucket: 'photos', storage: _client());
      await c.load();
      expect(c.status, KoolbaseListStatus.error);
      expect(c.error, isNotNull);
      server.failing = false;
      await c.refresh();
      expect(c.status, KoolbaseListStatus.loaded);
      expect(c.refreshing, isFalse);
      server.failing = true;
      await c.refresh();
      expect(c.status, KoolbaseListStatus.loaded);
      expect(_paths(c), ['a.png']);
      expect(c.refreshing, isFalse);
      c.dispose();
    }, () => server.client);
  });

  test('an answer a later load superseded is dropped; nothing changes after dispose', () async {
    server.files['photos'] = ['old.png'];
    await http.runWithClient(() async {
      final c = KoolbaseFilesController(bucket: 'photos', storage: _client());
      server.hold = Completer<void>();
      final first = c.load();
      await _settle();
      server.files['photos'] = ['new.png'];
      final held = server.hold!;
      server.hold = null;
      await c.refresh();
      expect(_paths(c), ['new.png']);
      server.files['photos'] = ['old.png'];
      held.complete();
      await first;
      expect(_paths(c), ['new.png']);
      c.dispose();
      await c.refresh();
      expect(_paths(c), ['new.png']);
    }, () => server.client);
  });

  test('a delete, a move and a copy through the SDK reload the lists on their buckets', () async {
    server.files['photos'] = ['a.png', 'x.png'];
    server.files['docs'] = ['d.pdf'];
    await http.runWithClient(() async {
      final storage = _client();
      final photos = KoolbaseFilesController(bucket: 'photos', storage: storage);
      final docs = KoolbaseFilesController(bucket: 'docs', storage: storage);
      await photos.load();
      await docs.load();

      await storage.delete(bucket: 'photos', path: 'a.png');
      await _settle();
      expect(_paths(photos), ['x.png']);
      expect(server.listings('docs'), hasLength(1));

      await storage.move(bucket: 'photos', from: 'x.png', to: 'x.png', toBucket: 'docs');
      await _settle();
      expect(_paths(photos), isEmpty);
      expect(_paths(docs), ['d.pdf', 'x.png']);

      docs.dispose();
      final before = server.listings('docs').length;
      await storage.copy(bucket: 'docs', from: 'd.pdf', to: 'e.pdf');
      await _settle();
      expect(server.listings('docs'), hasLength(before));
      photos.dispose();
    }, () => server.client);
  });

  test('a file reads as a row by name', () {
    final f = KoolbaseFileInfo.fromJson(_file('trips/beach.png'));
    expect(f.toMap(), {
      'id': 'trips/beach.png',
      'path': 'trips/beach.png',
      'name': 'beach.png',
      'size': 4,
      'contentType': 'image/png',
      'createdAt': DateTime.parse('2026-10-16T10:00:00Z'),
      'updatedAt': DateTime.parse('2026-10-16T10:00:00Z'),
      'uploadedBy': null,
      'publicUrl': null,
      'metadata': <String, String>{},
    });
  });

  testWidgets('the list: a spinner, the rows, Load more, then empty and error views', (tester) async {
    final storage = _FakeStorage({'photos': ['a.png', 'b.png', 'c.png']});
    Widget app(KoolbaseFilesController c) => MaterialApp(
          home: Scaffold(
            body: KoolbaseFileList(
              bucket: c.bucket,
              controller: c,
              itemBuilder: (context, f) => Text('row ${f.name}'),
              empty: (context) => const Text('no photos'),
              error: (context, e, retry) => TextButton(onPressed: retry, child: const Text('try again')),
            ),
          ),
        );

    final c = KoolbaseFilesController(bucket: 'photos', storage: storage);
    await tester.pumpWidget(app(c));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pump();
    expect(find.text('row a.png'), findsOneWidget);
    expect(find.text('row b.png'), findsOneWidget);
    expect(find.text('row c.png'), findsNothing);
    await tester.tap(find.text('Load more'));
    await tester.pump();
    expect(find.text('row c.png'), findsOneWidget);
    expect(find.text('Load more'), findsNothing);

    final empty = KoolbaseFilesController(bucket: 'nothing', storage: storage);
    await tester.pumpWidget(app(empty));
    await tester.pump();
    expect(find.text('no photos'), findsOneWidget);

    storage.failing = true;
    final broken = KoolbaseFilesController(bucket: 'photos', storage: storage);
    await tester.pumpWidget(app(broken));
    await tester.pump();
    expect(find.text('try again'), findsOneWidget);
    storage.failing = false;
    await tester.tap(find.text('try again'));
    await tester.pump();
    expect(find.text('row a.png'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    for (final x in [c, empty, broken]) {
      x.dispose();
    }
  });
}
