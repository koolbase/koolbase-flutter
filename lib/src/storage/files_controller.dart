// A bucket's files read as a list (storage S4): the data half of a file
// gallery, widget-free. Mirrors @koolbase/core's KoolbaseFilesController.
//
//  - only a first load with nothing to show is the error state; a failed
//    refresh or loadMore keeps what is shown (stale beats blank)
//  - loadMore appends the next page while there is one; a file already
//    shown is never shown twice (matched by path)
//  - an upload, delete, move, copy, metadata change or restore made through
//    this SDK in the bucket reloads page one silently
//  - every fetch belongs to a generation: an answer a later load superseded,
//    or one landing after dispose, is dropped

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../koolbase.dart';
import '../widgets/collection_list.dart' show KoolbaseListStatus;
import '../widgets/record_view.dart' show KoolbaseRecordStatus;
import 'storage_client.dart';
import 'storage_exceptions.dart';
import 'storage_files.dart';

final _refreshers = <int, ({String bucket, Future<void> Function() reload})>{};
var _nextRefresher = 0;

/// Reloads every file list on [buckets], after a change made through this
/// SDK. One after another; a failure in one never stops the others, and
/// never reaches the change that caused it.
void koolbaseFilesChanged(Iterable<String> buckets) {
  final due = [
    for (final r in _refreshers.values)
      if (buckets.contains(r.bucket)) r.reload,
  ];
  unawaited(() async {
    for (final reload in due) {
      try {
        await reload();
      } catch (_) {
        // A list that cannot reload keeps what it shows.
      }
    }
  }());
}

/// The data half of [KoolbaseFileList]: a bucket's files you may view,
/// page by page.
class KoolbaseFilesController extends ChangeNotifier {
  KoolbaseFilesController({
    required this.bucket,
    this.prefix,
    this.sort = KoolbaseFileSort.path,
    this.descending = false,
    this.limit,
    @visibleForTesting KoolbaseStorageClient? storage,
  }) : _storage = storage;

  /// The bucket to list.
  final String bucket;

  /// Only files whose path starts with this, taken literally.
  final String? prefix;

  /// The order, and which way.
  final KoolbaseFileSort sort;
  final bool descending;

  /// Files per page: 50 unless set, at most 100.
  final int? limit;

  final KoolbaseStorageClient? _storage;

  KoolbaseListStatus _status = KoolbaseListStatus.loading;
  List<KoolbaseFileInfo> _pageOne = const [];
  List<KoolbaseFileInfo> _later = const [];
  List<KoolbaseFileInfo> _files = const [];
  String? _cursor;
  Object? _error;
  bool _refreshing = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _generation = 0;
  int? _refresher;
  bool _disposed = false;

  KoolbaseListStatus get status => _status;

  /// The files loaded so far, in the listing's order.
  List<KoolbaseFileInfo> get files => _files;

  /// Why the first load failed, while [status] is error.
  Object? get error => _error;

  /// True while [refresh] runs.
  bool get refreshing => _refreshing;

  /// True while [loadMore] runs.
  bool get loadingMore => _loadingMore;

  /// Whether there is a page past the last one loaded. True before the first
  /// load.
  bool get hasMore => _hasMore;

  KoolbaseStorageClient get _client => _storage ?? Koolbase.storage;

  /// The first load. Call once; [refresh] for later loads.
  Future<void> load() async {
    if (_disposed) return;
    final id = _refresher ??= _nextRefresher++;
    _refreshers[id] = (bucket: bucket, reload: _firstPage);
    await _firstPage();
  }

  /// Page one again. What is shown stays while it runs, and stays if it
  /// fails.
  Future<void> refresh() async {
    if (_disposed) return;
    _refreshing = true;
    notifyListeners();
    await _firstPage();
  }

  /// The next page, appended. Does nothing unless loaded with a page to come.
  Future<void> loadMore() async {
    final cursor = _cursor;
    if (_disposed ||
        _loadingMore ||
        !_hasMore ||
        cursor == null ||
        _status != KoolbaseListStatus.loaded) {
      return;
    }
    final gen = _generation;
    _loadingMore = true;
    notifyListeners();
    try {
      final page = await _list(cursor);
      if (_stale(gen)) return;
      _later = [..._later, ...page.files];
      _cursor = page.nextCursor;
      _publish();
    } catch (_) {
      // Keep what is shown; the control stays and can be tried again.
    } finally {
      if (!_stale(gen)) {
        _loadingMore = false;
        notifyListeners();
      }
    }
  }

  Future<void> _firstPage() async {
    if (_disposed) return;
    final gen = ++_generation;
    _loadingMore = false;
    try {
      final page = await _list(null);
      if (_stale(gen)) return;
      _pageOne = page.files;
      _later = const [];
      _cursor = page.nextCursor;
      _status = KoolbaseListStatus.loaded;
      _error = null;
      _publish();
    } catch (e) {
      if (_stale(gen)) return;
      // Only a first load with nothing to show is the error state.
      if (_files.isEmpty) {
        _status = KoolbaseListStatus.error;
        _error = e;
      }
    }
    // Whichever load is newest ends a refresh, a silent one included.
    _refreshing = false;
    notifyListeners();
  }

  Future<KoolbaseFilePage> _list(String? cursor) => _client.listFiles(
        bucket: bucket,
        prefix: prefix,
        limit: limit,
        cursor: cursor,
        sort: sort,
        descending: descending,
      );

  void _publish() {
    final seen = <String>{};
    _files = [
      for (final f in [..._pageOne, ..._later])
        if (seen.add(f.path)) f,
    ];
    _hasMore = _cursor != null;
  }

  bool _stale(int gen) => _disposed || gen != _generation;

  @override
  void dispose() {
    _disposed = true;
    final id = _refresher;
    if (id != null) _refreshers.remove(id);
    super.dispose();
  }
}

/// The data half of [KoolbaseFileView]: one file's details, by path
/// (storage S4). The one-file twin of [KoolbaseFilesController], with the
/// record view's rules:
///
///  * an empty path is notFound, with no request
///  * not found is not an error: the API answers a file you may not view
///    as not found too, so a detail screen says "not available"
///  * stale beats blank: a failed refresh keeps the file shown
///  * a change made through this SDK in the bucket -- an upload, a delete,
///    a move, a metadata change, a restore -- reads it again silently: a
///    deleted or moved file is notFound, a replaced one shows its new size
///  * an answer a later load superseded, or one landing after dispose, is
///    dropped
class KoolbaseFileController extends ChangeNotifier {
  KoolbaseFileController({
    required this.bucket,
    required this.path,
    KoolbaseStorageClient? storage,
  }) : _storage = storage;

  /// The bucket the file is in.
  final String bucket;

  /// The file's path in [bucket]. Empty means none was given.
  final String path;

  final KoolbaseStorageClient? _storage;

  KoolbaseRecordStatus _status = KoolbaseRecordStatus.loading;
  KoolbaseFileInfo? _file;
  Object? _error;
  bool _refreshing = false;
  int _generation = 0;
  int? _refresher;
  bool _disposed = false;

  KoolbaseRecordStatus get status => _status;

  /// The file's details, while [status] is loaded.
  KoolbaseFileInfo? get file => _file;

  /// Why the first load failed, while [status] is error.
  Object? get error => _error;

  /// True while [refresh] runs.
  bool get refreshing => _refreshing;

  KoolbaseStorageClient get _client => _storage ?? Koolbase.storage;

  /// The first load. Call once; [refresh] for later loads.
  Future<void> load() async {
    if (_disposed) return;
    if (path.isNotEmpty) {
      final id = _refresher ??= _nextRefresher++;
      _refreshers[id] = (bucket: bucket, reload: _run);
    }
    await _run();
  }

  /// Read it again. The file stays shown while it runs, and stays if it
  /// fails.
  Future<void> refresh() async {
    if (_disposed) return;
    _refreshing = true;
    notifyListeners();
    await _run();
  }

  Future<void> _run() async {
    if (_disposed) return;
    final gen = ++_generation;
    if (path.isEmpty) {
      _show(KoolbaseRecordStatus.notFound, null, null);
      return;
    }
    try {
      final file = await _client.getFileInfo(bucket: bucket, path: path);
      if (_stale(gen)) return;
      _show(KoolbaseRecordStatus.loaded, file, null);
    } on KoolbaseStorageNotFoundException {
      if (_stale(gen)) return;
      _show(KoolbaseRecordStatus.notFound, null, null);
    } catch (e) {
      if (_stale(gen)) return;
      // Only a first load with nothing to show is the error state.
      if (_file == null) {
        _show(KoolbaseRecordStatus.error, null, e);
      } else {
        _refreshing = false;
        notifyListeners();
      }
    }
  }

  void _show(KoolbaseRecordStatus status, KoolbaseFileInfo? file, Object? error) {
    if (_disposed) return;
    _status = status;
    _file = file;
    _error = error;
    _refreshing = false;
    notifyListeners();
  }

  bool _stale(int gen) => _disposed || gen != _generation;

  @override
  void dispose() {
    _disposed = true;
    final id = _refresher;
    if (id != null) _refreshers.remove(id);
    _refresher = null;
    super.dispose();
  }
}
