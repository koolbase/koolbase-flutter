// S4: one file's details, by path. The controller over a storage client
// (asked for exactly that file; an empty path asks nothing), not found as
// not found, stale beats blank, a late answer dropped, and a change made
// through the SDK in the bucket shown by itself -- deleted, the file is not
// found; replaced, its new size; none after dispose. Then the widget: a
// spinner, the file, Not available, the error with its retry, and a new
// path starting a new load.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:koolbase_flutter/koolbase_flutter.dart';
import 'package:koolbase_flutter/src/storage/files_controller.dart' show koolbaseFilesChanged;

Map<String, dynamic> _info(String path, {int size = 4}) => {
      'path': path,
      'size': size,
      'content_type': 'image/png',
      'metadata': <String, dynamic>{},
      'uploaded_by': 'u1',
      'created_at': '2026-10-16T10:00:00Z',
      'updated_at': '2026-10-16T10:00:00Z',
    };

/// Files by bucket, each with its size; answers at once, no network.
class _FakeStorage extends KoolbaseStorageClient {
  _FakeStorage(this.files) : super(baseUrl: 'https://api.test', publicKey: 'pk_test');

  final Map<String, Map<String, int>> files;
  final asked = <String>[];
  bool failing = false;
  Completer<void>? hold;

  @override
  Future<KoolbaseFileInfo> getFileInfo({required String bucket, required String path}) async {
    asked.add('$bucket/$path');
    final wait = hold;
    if (wait != null) await wait.future;
    if (failing) throw const KoolbaseStorageException('down');
    final size = files[bucket]?[path];
    if (size == null) throw const KoolbaseStorageNotFoundException();
    return KoolbaseFileInfo.fromJson(_info(path, size: size));
  }
}

Future<void> _settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('asks the API for exactly that file, its path as it is', () async {
    final asked = <Uri>[];
    final client = MockClient((req) async {
      asked.add(req.url);
      return http.Response(jsonEncode(_info('trips/Q&A 1.png')), 200);
    });
    await http.runWithClient(() async {
      final c = KoolbaseFileController(
        bucket: 'photos',
        path: 'trips/Q&A 1.png',
        storage: KoolbaseStorageClient(baseUrl: 'https://api.test', publicKey: 'pk_test'),
      );
      await c.load();
      expect(c.status, KoolbaseRecordStatus.loaded);
      expect(c.file!.name, 'Q&A 1.png');
      expect(c.file!.uploadedBy, 'u1');
      c.dispose();
    }, () => client);
    expect(asked.single.path, '/v1/sdk/storage/file');
    expect(asked.single.queryParameters, {'bucket': 'photos', 'path': 'trips/Q&A 1.png'});
  });

  test('an empty path is not found without a request; a missing file is not found, not an error', () async {
    final s = _FakeStorage({'photos': {'a.png': 4}});
    final none = KoolbaseFileController(bucket: 'photos', path: '', storage: s);
    await none.load();
    expect(none.status, KoolbaseRecordStatus.notFound);
    expect(s.asked, isEmpty);
    final gone = KoolbaseFileController(bucket: 'photos', path: 'z.png', storage: s);
    await gone.load();
    expect(gone.status, KoolbaseRecordStatus.notFound);
    expect(gone.error, isNull);
    none.dispose();
    gone.dispose();
  });

  test('a failed first load is the error; a failed refresh keeps the file', () async {
    final s = _FakeStorage({'photos': {'a.png': 4}})..failing = true;
    final c = KoolbaseFileController(bucket: 'photos', path: 'a.png', storage: s);
    await c.load();
    expect(c.status, KoolbaseRecordStatus.error);
    expect(c.error, isA<KoolbaseStorageException>());
    s.failing = false;
    await c.refresh();
    expect(c.status, KoolbaseRecordStatus.loaded);
    s.failing = true;
    await c.refresh();
    expect(c.status, KoolbaseRecordStatus.loaded);
    expect(c.file!.path, 'a.png');
    expect(c.refreshing, isFalse);
    c.dispose();
  });

  test('an answer a later load superseded is dropped', () async {
    final s = _FakeStorage({'photos': {'a.png': 4}});
    final c = KoolbaseFileController(bucket: 'photos', path: 'a.png', storage: s);
    final gate = Completer<void>();
    s.hold = gate;
    final first = c.load();
    await _settle();
    s.hold = null;
    s.files['photos']!['a.png'] = 9;
    await c.refresh();
    expect(c.file!.size, 9);
    // The first answer lands late, reading the old size: the newer one stays.
    s.files['photos']!['a.png'] = 4;
    gate.complete();
    await first;
    expect(c.file!.size, 9);
    c.dispose();
  });

  test('a change in the bucket reads it again: replaced, then deleted; none after dispose', () async {
    final s = _FakeStorage({'photos': {'a.png': 4}});
    final c = KoolbaseFileController(bucket: 'photos', path: 'a.png', storage: s);
    await c.load();
    s.files['photos']!['a.png'] = 12;
    koolbaseFilesChanged(['other']);
    await _settle();
    expect(c.file!.size, 4, reason: 'another bucket changing is not this file');
    koolbaseFilesChanged(['photos']);
    await _settle();
    expect(c.file!.size, 12);
    s.files['photos']!.remove('a.png');
    koolbaseFilesChanged(['photos']);
    await _settle();
    expect(c.status, KoolbaseRecordStatus.notFound);
    c.dispose();
    final before = s.asked.length;
    koolbaseFilesChanged(['photos']);
    await _settle();
    expect(s.asked.length, before, reason: 'a disposed view is let go');
  });

  testWidgets('the view: a spinner, the file, Not available, the error and its retry, a new path', (tester) async {
    final s = _FakeStorage({'photos': {'a.png': 4, 'b.png': 8}});
    Widget app(String? path, {bool slots = false}) => MaterialApp(
          home: Scaffold(
            body: KoolbaseFileView(
              bucket: 'photos',
              path: path,
              storage: s,
              builder: (context, f) => Text('${f.name}: ${f.size} bytes'),
              notFound: slots ? (context) => const Text('no such photo') : null,
              error: slots ? (context, e, retry) => TextButton(onPressed: retry, child: const Text('try again')) : null,
            ),
          ),
        );

    s.hold = Completer<void>();
    await tester.pumpWidget(app('a.png'));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    s.hold!.complete();
    s.hold = null;
    await tester.pump();
    expect(find.text('a.png: 4 bytes'), findsOneWidget);

    await tester.pumpWidget(app('b.png'));
    await tester.pump();
    expect(find.text('b.png: 8 bytes'), findsOneWidget, reason: 'a new path is a new load');

    await tester.pumpWidget(app('z.png'));
    await tester.pump();
    expect(find.text('Not available.'), findsOneWidget);
    await tester.pumpWidget(app(null, slots: true));
    await tester.pump();
    expect(find.text('no such photo'), findsOneWidget);

    s.failing = true;
    await tester.pumpWidget(app('a.png', slots: true));
    await tester.pump();
    expect(find.text('try again'), findsOneWidget);
    s.failing = false;
    await tester.tap(find.text('try again'));
    await tester.pump();
    expect(find.text('a.png: 4 bytes'), findsOneWidget);
  });
}
