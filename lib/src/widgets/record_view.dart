import 'package:flutter/material.dart';

import '../database/database_exceptions.dart';
import '../koolbase.dart';

/// The phases a one-record load moves through.
enum KoolbaseRecordStatus {
  /// First fetch in flight, nothing to show yet.
  loading,

  /// The record is available.
  loaded,

  /// There is no record to show: no id, no such record, one this user may
  /// not read (the API does not tell those apart), or a record from a
  /// different collection than the one asked for.
  notFound,

  /// The first fetch failed and there is nothing to show.
  error,
}

/// The data half of [KoolbaseRecordView], deliberately widget-free: one
/// record of a collection, by id. The one-record twin of
/// [KoolbaseCollectionController], with the same rules:
///
///  * an empty id is [KoolbaseRecordStatus.notFound] with no request
///  * a not-found answer is notFound, not an error: the API answers a
///    denied read as not found too, so a detail screen says "not
///    available" rather than "something went wrong"
///  * a record from another collection is notFound, so a mistyped or
///    crafted id cannot put another collection's record on this screen
///  * stale beats blank: a failed refresh keeps the record
///  * a result that lands after [dispose], or that a later refresh
///    superseded, is dropped
class KoolbaseRecordController extends ChangeNotifier {
  KoolbaseRecordController({
    required this.collection,
    required this.id,
    @visibleForTesting Future<KoolbaseRecord> Function()? fetch,
  }) : _fetch = fetch;

  /// The collection the record must belong to.
  final String collection;

  /// The record's id. Empty means none was given.
  final String id;

  /// Test seam only: how the record is fetched. Production uses
  /// `Koolbase.db.doc(id).get()`.
  final Future<KoolbaseRecord> Function()? _fetch;

  KoolbaseRecordStatus _status = KoolbaseRecordStatus.loading;
  KoolbaseRecord? _record;
  Object? _error;
  bool _refreshing = false;
  int _generation = 0;
  bool _disposed = false;

  KoolbaseRecordStatus get status => _status;
  KoolbaseRecord? get record => _record;

  /// Why the first load failed, while [status] is error.
  Object? get error => _error;

  /// True while an explicit [refresh] is in flight.
  bool get refreshing => _refreshing;

  /// First load. Safe to call once; [refresh] for later loads.
  Future<void> load() async {
    if (_disposed) return;
    await _run();
  }

  /// Fetch again. The record stays visible while it runs, and stays if it
  /// fails.
  Future<void> refresh() async {
    if (_disposed) return;
    _refreshing = true;
    notifyListeners();
    final gen = await _run();
    if (!_isStale(gen)) {
      _refreshing = false;
      notifyListeners();
    }
  }

  Future<int> _run() async {
    final gen = ++_generation;
    if (id.isEmpty) {
      _show(KoolbaseRecordStatus.notFound, null, null);
      return gen;
    }
    try {
      final record = await (_fetch?.call() ?? Koolbase.db.doc(id).get());
      if (_isStale(gen)) return gen;
      final other = record.collection != null && record.collection != collection;
      _show(
        other ? KoolbaseRecordStatus.notFound : KoolbaseRecordStatus.loaded,
        other ? null : record,
        null,
      );
    } on KoolbaseNotFoundException {
      if (_isStale(gen)) return gen;
      _show(KoolbaseRecordStatus.notFound, null, null);
    } catch (e) {
      if (_isStale(gen)) return gen;
      // Only a first load with nothing to show is an error state.
      if (_record == null) _show(KoolbaseRecordStatus.error, null, e);
    }
    return gen;
  }

  bool _isStale(int gen) => _disposed || gen != _generation;

  void _show(KoolbaseRecordStatus status, KoolbaseRecord? record, Object? error) {
    if (_disposed) return;
    _status = status;
    _record = record;
    _error = error;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// One record of a collection, by id, handed to [builder] -- a SCOPE, not a
/// screen: it adds no scrolling and no layout of its own. The widget
/// [builder] returns is the caller's, and everything inside it reads the
/// record it was given, as a list row's children read theirs. Loading,
/// not-found and error are slotted.
///
/// ```dart
/// KoolbaseRecordView(
///   collection: 'songs',
///   id: songId,
///   builder: (context, song) => Column(children: [
///     Text(song.data['title'] as String),
///   ]),
/// )
/// ```
///
/// A changed [id] or [collection] starts a new load: the same detail route
/// opened for another record shows that record, never the previous one.
class KoolbaseRecordView extends StatefulWidget {
  const KoolbaseRecordView({
    super.key,
    required this.collection,
    required this.id,
    required this.builder,
    this.loading,
    this.notFound,
    this.error,
    @visibleForTesting this.fetch,
  });

  /// The collection the record must belong to.
  final String collection;

  /// The record's id. Null or empty shows [notFound] without a request.
  final String? id;

  /// Builds what shows the record. Appearance is entirely the caller's.
  final Widget Function(BuildContext context, KoolbaseRecord record) builder;

  /// Shown during the first load. Defaults to a centered spinner.
  final WidgetBuilder? loading;

  /// Shown when there is no record to show. Defaults to "Not available."
  final WidgetBuilder? notFound;

  /// Shown when the first load failed. Receives the error and a retry.
  final Widget Function(
      BuildContext context, Object error, Future<void> Function() retry)? error;

  /// Test seam only: fetch a record by id instead of calling the SDK.
  final Future<KoolbaseRecord> Function(String id)? fetch;

  @override
  State<KoolbaseRecordView> createState() => _KoolbaseRecordViewState();
}

class _KoolbaseRecordViewState extends State<KoolbaseRecordView> {
  late KoolbaseRecordController _controller;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    final id = widget.id ?? '';
    final fetch = widget.fetch;
    _controller = KoolbaseRecordController(
      collection: widget.collection,
      id: id,
      fetch: fetch == null ? null : () => fetch(id),
    )..addListener(_onChanged);
    _controller.load();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(KoolbaseRecordView old) {
    super.didUpdateWidget(old);
    if (old.id != widget.id || old.collection != widget.collection) {
      _controller
        ..removeListener(_onChanged)
        ..dispose();
      _start();
    }
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    switch (_controller.status) {
      case KoolbaseRecordStatus.loading:
        return widget.loading?.call(context) ??
            const Center(child: CircularProgressIndicator());
      case KoolbaseRecordStatus.notFound:
        return widget.notFound?.call(context) ?? const _DefaultNotFound();
      case KoolbaseRecordStatus.error:
        final err = _controller.error!;
        return widget.error?.call(context, err, _controller.refresh) ??
            _DefaultError(onRetry: _controller.refresh);
      case KoolbaseRecordStatus.loaded:
        return widget.builder(context, _controller.record!);
    }
  }
}

class _DefaultNotFound extends StatelessWidget {
  const _DefaultNotFound();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Not available.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}

class _DefaultError extends StatelessWidget {
  const _DefaultError({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Couldn't load this.",
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
