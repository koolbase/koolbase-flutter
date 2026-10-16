// S4: several uploads in a queue. Each file is its own SDK task, run by a
// fake storage whose tasks the test moves along: three at a time, in
// order; a failure never stops the others and can be tried again; cancel
// before starting, while uploading, and not once verifying; the average
// leaving a cancelled file out; cancelAll, whenIdle and clearFinished; and
// nothing heard after dispose.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:koolbase_flutter/koolbase_flutter.dart';
import 'package:koolbase_flutter/src/storage/storage_transfer.dart'
    show runUploadTask, KoolbaseUploadTaskControl;

UploadResult _result(String path) => UploadResult(
      object: KoolbaseObject.fromJson({
        'id': 'o1',
        'project_id': 'p1',
        'bucket_id': 'b1',
        'r2_bucket': 'koolbase-storage',
        'path': path,
        'size': 100,
        'content_type': 'image/png',
        'metadata': <String, dynamic>{},
        'created_at': '2026-10-16T10:00:00Z',
        'updated_at': '2026-10-16T10:00:00Z',
      }),
      downloadUrl: 'https://cdn.test/$path',
      bucket: 'photos',
    );

/// One upload the test moves along.
class _Run {
  _Run(this.path);
  final String path;
  KoolbaseUploadTaskControl? step;
  final end = Completer<UploadResult>();

  void uploading(int sent) => step!.uploading(sent);
  void verifying() => step!.verifying();
  void succeed() => end.complete(_result(path));
  void fail([String why = 'refused']) => end.completeError(KoolbaseStorageException(why));

  /// Lets a cancelled upload notice it was cancelled.
  void release() => end.complete(_result(path));
}

class _FakeStorage extends KoolbaseStorageClient {
  _FakeStorage() : super(baseUrl: 'https://api.test', publicKey: 'pk_test');

  final runs = <_Run>[];

  /// The latest run for [path].
  _Run of(String path) => runs.lastWhere((r) => r.path == path);
  List<String> get started => [for (final r in runs) r.path];

  @override
  KoolbaseUploadTask startUpload({
    required String bucket,
    required String path,
    required List<int> bytes,
    String? contentType,
    Map<String, String>? metadata,
    bool overwrite = false,
  }) {
    final run = _Run(path);
    runs.add(run);
    return runUploadTask(100, (step) async {
      run.step = step;
      final r = await run.end.future;
      step.checkCancelled();
      return r;
    });
  }
}

Future<void> _settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

List<KoolbaseQueueFile> _files(List<String> names) => [
      for (final n in names)
        KoolbaseQueueFile(bucket: 'photos', path: 'trips/$n', bytes: const [1, 2, 3]),
    ];

Map<String, String> _statuses(KoolbaseUploadQueue q) =>
    {for (final i in q.items) i.name: i.status.name};

void main() {
  test('runs three at a time, in order, each with its own state; the next starts as one lands', () async {
    final storage = _FakeStorage();
    final q = KoolbaseUploadQueue(storage: storage);
    final ids = q.add(_files(['a.jpg', 'b.jpg', 'c.jpg', 'd.jpg']));
    expect(ids, ['u1', 'u2', 'u3', 'u4']);
    await _settle();
    expect(storage.started, ['trips/a.jpg', 'trips/b.jpg', 'trips/c.jpg']);
    expect(_statuses(q)['d.jpg'], 'queued');

    storage.of('trips/b.jpg').uploading(50);
    expect(q.items[1].progress, 0.5);
    expect(q.items[1].status, KoolbaseQueuedUploadStatus.uploading);
    storage.of('trips/b.jpg').verifying();
    expect(q.items[1].status, KoolbaseQueuedUploadStatus.verifying);
    expect(q.items[1].progress, 1.0);

    storage.of('trips/a.jpg').succeed();
    await _settle();
    expect(_statuses(q)['a.jpg'], 'done');
    expect(storage.started.last, 'trips/d.jpg');
    expect(q.done, 1);
    expect(q.running, isTrue);
    expect(q.items.first.toMap()['status'], 'done');
  });

  test('a file that fails never stops the others; it can be tried again, from the start', () async {
    final storage = _FakeStorage();
    final q = KoolbaseUploadQueue(storage: storage);
    q.add(_files(['a.jpg', 'b.jpg']));
    await _settle();
    storage.of('trips/a.jpg').uploading(60);
    storage.of('trips/a.jpg').fail('too big');
    await _settle();
    expect(_statuses(q), {'a.jpg': 'failed', 'b.jpg': 'uploading'});
    expect(q.items.first.error.toString(), contains('too big'));
    expect(q.items.first.toMap()['error'], 'too big');
    expect(q.failed, 1);

    expect(q.retry('u2'), isFalse); // not failed
    expect(q.retry('u1'), isTrue);
    expect(q.items.first.progress, 0);
    await _settle();
    expect(storage.runs.where((r) => r.path == 'trips/a.jpg').length, 2);
    storage.of('trips/a.jpg').succeed();
    storage.of('trips/b.jpg').succeed();
    await _settle();
    expect(_statuses(q), {'a.jpg': 'done', 'b.jpg': 'done'});
    expect(q.items.first.error, isNull);
    expect(q.failed, 0);
  });

  test('cancel: a queued file never starts; one uploading stops; not once verifying', () async {
    final storage = _FakeStorage();
    final q = KoolbaseUploadQueue(storage: storage, concurrency: 3);
    q.add(_files(['a.jpg', 'b.jpg', 'c.jpg', 'd.jpg']));
    await _settle();

    expect(q.cancel('u4'), isTrue);
    expect(_statuses(q)['d.jpg'], 'cancelled');

    storage.of('trips/a.jpg').uploading(40);
    expect(q.cancel('u1'), isTrue);
    storage.of('trips/a.jpg').release();
    await _settle();
    expect(_statuses(q)['a.jpg'], 'cancelled');
    expect(q.items.first.progress, 0);

    storage.of('trips/c.jpg').verifying();
    expect(q.cancel('u3'), isFalse);
    storage.of('trips/b.jpg').uploading(50);
    // a.jpg and d.jpg cancelled are left out: (0.5 + 1.0) / 2
    expect(q.progress, closeTo(0.75, 1e-9));
    expect(storage.started, isNot(contains('trips/d.jpg')));

    expect(q.retry('u4'), isTrue);
    await _settle();
    expect(storage.started.last, 'trips/d.jpg');
  });

  test('cancelAll, whenIdle and clearFinished', () async {
    final storage = _FakeStorage();
    final q = KoolbaseUploadQueue(storage: storage, concurrency: 1);
    q.add(_files(['a.jpg', 'b.jpg', 'c.jpg']));
    await _settle();
    var idle = false;
    unawaited(q.whenIdle().then((_) => idle = true));
    storage.of('trips/a.jpg').succeed();
    await _settle();
    expect(idle, isFalse);

    q.cancelAll();
    storage.of('trips/b.jpg').release();
    await _settle();
    expect(_statuses(q), {'a.jpg': 'done', 'b.jpg': 'cancelled', 'c.jpg': 'cancelled'});
    expect(idle, isTrue);
    expect(q.running, isFalse);
    await q.whenIdle();

    q.clearFinished();
    expect(q.items, isEmpty);
    expect(q.progress, 0);
  });

  test('notifies on every change; nothing after dispose', () async {
    final storage = _FakeStorage();
    final q = KoolbaseUploadQueue(storage: storage);
    var heard = 0;
    q.addListener(() => heard++);
    q.add(_files(['a.jpg']));
    expect(heard, 1);
    await _settle();
    storage.of('trips/a.jpg').uploading(10);
    expect(heard, 2);
    q.dispose();
    storage.of('trips/a.jpg').uploading(20);
    storage.of('trips/a.jpg').succeed();
    await _settle();
    expect(heard, 2);
    expect(q.add(_files(['b.jpg'])), isEmpty);
  });
}
