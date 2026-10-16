// Several uploads in a queue (storage S4). Mirrors @koolbase/core's
// KoolbaseUploadQueue.
//
// Files added together go a few at a time (three unless set), each its own
// SDK upload task -- so a large one still goes in parts, and a bucket's file
// lists still reload as each lands. Every file has its own state and
// progress, and can be cancelled or tried again on its own.
//
//  - queued -> uploading -> verifying -> done, or failed / cancelled
//  - a queued file cancelled never starts; one uploading stops (once the
//    server is verifying it, it lands or fails on its own)
//  - a failed or cancelled file can be tried again: it queues once more,
//    from the start, under the same path
//  - a file that fails never stops the others
//  - progress is the files' average, a cancelled one not counted

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../koolbase.dart';
import '../koolbase_exception.dart';
import 'storage_client.dart';
import 'storage_exceptions.dart';
import 'storage_transfer.dart';

/// Where one file in a queue is.
enum KoolbaseQueuedUploadStatus {
  queued,
  uploading,
  verifying,
  done,
  failed,
  cancelled,
}

/// One file in a [KoolbaseUploadQueue].
@immutable
class KoolbaseQueuedUpload {
  /// The queue's own id for it: what [KoolbaseUploadQueue.cancel] and
  /// [KoolbaseUploadQueue.retry] take.
  final String id;
  final String bucket;

  /// Where it goes in the bucket.
  final String path;

  /// What a person calls it: the name given, else the path's last part.
  final String name;
  final KoolbaseQueuedUploadStatus status;

  /// 0.0 to 1.0: the share of its bytes sent; 1.0 once verifying.
  final double progress;

  /// Why it failed, while [status] is failed.
  final Object? error;

  const KoolbaseQueuedUpload({
    required this.id,
    required this.bucket,
    required this.path,
    required this.name,
    required this.status,
    required this.progress,
    this.error,
  });

  /// Its fields by name -- id, bucket, path, name, status, progress, and
  /// error (a message, or null) -- for code that reads rows by field (a
  /// Designer screen's).
  Map<String, dynamic> toMap() {
    final e = error;
    return {
      'id': id,
      'bucket': bucket,
      'path': path,
      'name': name,
      'status': status.name,
      'progress': progress,
      'error': e is KoolbaseException ? e.message : e?.toString(),
    };
  }

  KoolbaseQueuedUpload _with(
    KoolbaseQueuedUploadStatus status,
    double progress, [
    Object? error,
  ]) =>
      KoolbaseQueuedUpload(
        id: id,
        bucket: bucket,
        path: path,
        name: name,
        status: status,
        progress: progress,
        error: error,
      );
}

/// A file to add to a [KoolbaseUploadQueue]: where it goes, and its bytes.
class KoolbaseQueueFile {
  final String bucket;
  final String path;
  final List<int> bytes;

  /// Shown for it; the path's last part unless set.
  final String? name;
  final String? contentType;
  final Map<String, String>? metadata;
  final bool overwrite;

  const KoolbaseQueueFile({
    required this.bucket,
    required this.path,
    required this.bytes,
    this.name,
    this.contentType,
    this.metadata,
    this.overwrite = false,
  });
}

class _Entry {
  _Entry(this.item, this.source);
  KoolbaseQueuedUpload item;
  final KoolbaseQueueFile source;
  KoolbaseUploadTask? task;
  StreamSubscription<KoolbaseUploadProgress>? follow;

  /// Each start's number: a task a retry replaced reports nothing.
  int run = 0;
}

/// Several uploads, a few at a time, each with its own state, progress,
/// cancel and retry.
///
/// ```dart
/// final queue = KoolbaseUploadQueue();
/// queue.add([
///   for (final f in picked.files)
///     KoolbaseQueueFile(bucket: 'photos', path: 'trips/${f.name}', bytes: f.bytes!),
/// ]);
/// // queue.items, queue.progress; queue.cancel(id), queue.retry(id)
/// ```
class KoolbaseUploadQueue extends ChangeNotifier {
  KoolbaseUploadQueue({
    int concurrency = 3,
    KoolbaseStorageClient? storage,
  })  : concurrency = concurrency < 1 ? 1 : concurrency,
        _storage = storage;

  /// How many files go at once.
  final int concurrency;
  final KoolbaseStorageClient? _storage;
  final _entries = <_Entry>[];
  final _idle = <Completer<void>>[];
  int _nextId = 0;
  bool _disposed = false;

  KoolbaseStorageClient get _client => _storage ?? Koolbase.storage;

  /// Every file added and not cleared, in the order added.
  List<KoolbaseQueuedUpload> get items =>
      List.unmodifiable([for (final e in _entries) e.item]);

  /// 0.0 to 1.0: the files' average progress, a cancelled one not counted.
  double get progress {
    final counted = [
      for (final e in _entries)
        if (e.item.status != KoolbaseQueuedUploadStatus.cancelled) e.item.progress,
    ];
    return counted.isEmpty ? 0 : counted.reduce((a, b) => a + b) / counted.length;
  }

  /// Whether any file is still queued, uploading or verifying.
  bool get running => _entries.any((e) => _live(e.item.status));

  /// How many have landed.
  int get done => _entries
      .where((e) => e.item.status == KoolbaseQueuedUploadStatus.done)
      .length;

  /// How many failed.
  int get failed => _entries
      .where((e) => e.item.status == KoolbaseQueuedUploadStatus.failed)
      .length;

  static bool _live(KoolbaseQueuedUploadStatus s) =>
      s == KoolbaseQueuedUploadStatus.queued ||
      s == KoolbaseQueuedUploadStatus.uploading ||
      s == KoolbaseQueuedUploadStatus.verifying;

  /// Adds files to the end of the queue and starts as many as may run.
  /// Returns their ids.
  List<String> add(List<KoolbaseQueueFile> files) {
    if (_disposed) return const [];
    final ids = <String>[];
    for (final f in files) {
      final id = 'u${++_nextId}';
      ids.add(id);
      final given = f.name;
      final last = f.path.split('/').last;
      _entries.add(_Entry(
        KoolbaseQueuedUpload(
          id: id,
          bucket: f.bucket,
          path: f.path,
          name: given != null && given.isNotEmpty ? given : (last.isEmpty ? f.path : last),
          status: KoolbaseQueuedUploadStatus.queued,
          progress: 0,
        ),
        f,
      ));
    }
    _pump();
    _publish();
    return ids;
  }

  /// Stops one file: a queued one never starts; one uploading stops.
  /// Returns whether it was stopped.
  bool cancel(String id) {
    final e = _find(id);
    if (e == null) return false;
    if (e.item.status == KoolbaseQueuedUploadStatus.queued) {
      e.item = e.item._with(KoolbaseQueuedUploadStatus.cancelled, 0);
      _publish();
      return true;
    }
    if (e.item.status == KoolbaseQueuedUploadStatus.uploading) {
      return e.task?.cancel() ?? false;
    }
    return false;
  }

  /// Stops every file that can still be stopped.
  void cancelAll() {
    for (final e in List.of(_entries)) {
      cancel(e.item.id);
    }
  }

  /// Tries a failed or cancelled file again, from the start. Returns
  /// whether it was queued.
  bool retry(String id) {
    final e = _find(id);
    if (e == null || _disposed) return false;
    if (e.item.status != KoolbaseQueuedUploadStatus.failed &&
        e.item.status != KoolbaseQueuedUploadStatus.cancelled) {
      return false;
    }
    e.follow?.cancel();
    e.follow = null;
    e.task = null;
    e.item = e.item._with(KoolbaseQueuedUploadStatus.queued, 0);
    _pump();
    _publish();
    return true;
  }

  /// Removes the files that have finished: landed, failed or cancelled.
  void clearFinished() {
    final before = _entries.length;
    _entries.removeWhere((e) => !_live(e.item.status));
    if (_entries.length != before) _publish();
  }

  /// Completes once nothing is queued, uploading or verifying.
  Future<void> whenIdle() {
    if (!running) return Future.value();
    final c = Completer<void>();
    _idle.add(c);
    return c.future;
  }

  _Entry? _find(String id) {
    for (final e in _entries) {
      if (e.item.id == id) return e;
    }
    return null;
  }

  void _pump() {
    if (_disposed) return;
    var free = concurrency -
        _entries
            .where((e) =>
                e.item.status == KoolbaseQueuedUploadStatus.uploading ||
                e.item.status == KoolbaseQueuedUploadStatus.verifying)
            .length;
    for (final e in _entries) {
      if (free <= 0) break;
      if (e.item.status != KoolbaseQueuedUploadStatus.queued) continue;
      free--;
      _start(e);
    }
  }

  void _start(_Entry e) {
    final run = ++e.run;
    e.item = e.item._with(KoolbaseQueuedUploadStatus.uploading, 0);
    final KoolbaseUploadTask task;
    try {
      task = _client.startUpload(
        bucket: e.source.bucket,
        path: e.source.path,
        bytes: e.source.bytes,
        contentType: e.source.contentType,
        metadata: e.source.metadata,
        overwrite: e.source.overwrite,
      );
    } catch (err) {
      _finish(e, run, KoolbaseQueuedUploadStatus.failed, err);
      return;
    }
    e.task = task;
    e.follow = task.progress.listen((p) {
      if (e.run != run ||
          p.isDone ||
          e.item.status == KoolbaseQueuedUploadStatus.cancelled) {
        return;
      }
      final status = p.state == KoolbaseUploadState.verifying
          ? KoolbaseQueuedUploadStatus.verifying
          : KoolbaseQueuedUploadStatus.uploading;
      if (status == e.item.status && p.fraction == e.item.progress) return;
      e.item = e.item._with(status, p.fraction);
      _publish();
    });
    task.result.then(
      (_) => _finish(e, run, KoolbaseQueuedUploadStatus.done, null),
      onError: (Object err) => _finish(
        e,
        run,
        err is KoolbaseUploadCancelledException
            ? KoolbaseQueuedUploadStatus.cancelled
            : KoolbaseQueuedUploadStatus.failed,
        err,
      ),
    );
  }

  void _finish(
    _Entry e,
    int run,
    KoolbaseQueuedUploadStatus status,
    Object? err,
  ) {
    if (e.run != run) return;
    e.follow?.cancel();
    e.follow = null;
    e.task = null;
    final progress = status == KoolbaseQueuedUploadStatus.done
        ? 1.0
        : status == KoolbaseQueuedUploadStatus.cancelled
            ? 0.0
            : e.item.progress;
    e.item = e.item._with(
      status,
      progress,
      status == KoolbaseQueuedUploadStatus.failed ? err : null,
    );
    _pump();
    _publish();
  }

  void _publish() {
    if (!running && _idle.isNotEmpty) {
      final waiting = List.of(_idle);
      _idle.clear();
      for (final c in waiting) {
        c.complete();
      }
    }
    if (!_disposed) notifyListeners();
  }

  /// Stops reporting. Uploads already running finish on their own.
  @override
  void dispose() {
    _disposed = true;
    for (final e in _entries) {
      e.follow?.cancel();
      e.follow = null;
    }
    super.dispose();
  }
}
