import 'dart:async';

import 'package:flutter/material.dart';

import '../koolbase.dart';

/// Configures a fresh base query for one fetch. Called every time the
/// component fetches or refreshes — never with a reused instance.
///
/// MUST be deterministic: the same inputs must shape the same query. Query
/// streams are keyed by query identity (collection + filters + user), so a
/// callback that shapes a different query per call would strand the
/// component's stream subscription on a stale identity.
///
/// The builder MUTATES the query it is given (KoolbaseQuery is a mutating
/// fluent builder) — configure and return it; do not retain it.
typedef KoolbaseQueryBuilder = KoolbaseQuery Function(KoolbaseQuery query);

/// The phases a collection load moves through, as the controller models them.
enum KoolbaseListStatus {
  /// First fetch in flight, nothing to show yet.
  loading,

  /// Records available (possibly from cache, possibly refreshed since).
  loaded,

  /// The first fetch failed and there is nothing to show.
  error,
}

/// The data half of [KoolbaseCollectionList], deliberately widget-free.
///
/// Owns everything about GETTING the records correctly:
///
///  * a FRESH query per fetch — [KoolbaseQuery.where] mutates its instance,
///    and stream identity is derived from the filters, so a reused query
///    whose shape drifts would change identity after subscription
///  * the stale-while-revalidate contract: [KoolbaseQuery.get] seeds
///    (cache-first), the query's stream delivers background refreshes, and
///    both land through one path so data arriving twice is normal
///  * subscription lifecycle: one stream subscription per query identity,
///    replaced only if the identity changes, cancelled on [dispose]
///  * refresh: a new fetch through the same discipline
///
/// The widget below is one opinionated skin over this. A custom-scroll or
/// grid variant later consumes this controller unchanged.
class KoolbaseCollectionController extends ChangeNotifier {
  KoolbaseCollectionController({
    required this.collection,
    this.queryBuilder,
    @visibleForTesting KoolbaseQuery Function()? baseQuery,
  }) : _baseQuery = baseQuery;

  /// The collection to list.
  final String collection;

  /// Shapes each fresh query (filters, order, limit). Null lists unfiltered.
  final KoolbaseQueryBuilder? queryBuilder;

  /// Test seam only: how a fresh base query is constructed. Production uses
  /// `Koolbase.db.collection(collection)`.
  final KoolbaseQuery Function()? _baseQuery;

  KoolbaseListStatus _status = KoolbaseListStatus.loading;
  List<KoolbaseRecord> _records = const [];
  Object? _error;
  bool _isFromCache = false;
  bool _refreshing = false;

  StreamSubscription<QueryResult>? _sub;
  String? _subscribedKey;
  bool _disposed = false;

  KoolbaseListStatus get status => _status;
  List<KoolbaseRecord> get records => _records;
  Object? get error => _error;

  /// True while the shown records came from cache and no network result has
  /// replaced them yet — the SWR first arrival. UIs can show a subtle
  /// refreshing hint.
  bool get isFromCache => _isFromCache;

  /// True while an explicit [refresh] is in flight.
  bool get refreshing => _refreshing;

  /// Builds THE fresh query for one fetch. Never cached, never reused.
  KoolbaseQuery _freshQuery() {
    final base = _baseQuery?.call() ?? Koolbase.db.collection(collection);
    return queryBuilder?.call(base) ?? base;
  }

  /// First load. Safe to call once; [refresh] for subsequent loads.
  Future<void> load() async {
    final query = _freshQuery();
    _resubscribe(query);
    try {
      final result = await query.get();
      if (_disposed) return;
      _status = KoolbaseListStatus.loaded;
      _records = result.records;
      _isFromCache = result.isFromCache;
      _error = null;
    } catch (e) {
      if (_disposed) return;
      // Only a first load with nothing to show is an error STATE; a failed
      // refresh over existing records keeps the records (stale beats blank).
      if (_records.isEmpty) {
        _status = KoolbaseListStatus.error;
        _error = e;
      }
    }
    notifyListeners();
  }

  /// Fetch again through a fresh query. Existing records stay visible while
  /// it runs; a failure keeps them (stale beats blank).
  Future<void> refresh() async {
    _refreshing = true;
    notifyListeners();
    try {
      final query = _freshQuery();
      _resubscribe(query);
      final result = await query.get();
      if (_disposed) return;
      _status = KoolbaseListStatus.loaded;
      _records = result.records;
      _isFromCache = result.isFromCache;
      _error = null;
    } catch (_) {
      // Keep what we have. The pull gesture failing silently into the same
      // list is the behavior every mature app converges on.
    } finally {
      if (!_disposed) {
        _refreshing = false;
        notifyListeners();
      }
    }
  }

  /// Subscribes to the query's refresh stream, replacing the subscription
  /// only when the query IDENTITY changes — a deterministic builder yields
  /// the same identity every time, so in the steady state this subscribes
  /// exactly once.
  void _resubscribe(KoolbaseQuery query) {
    final key = query.streamKey;
    if (key == _subscribedKey) return;
    _sub?.cancel();
    _subscribedKey = key;
    _sub = query.stream.listen((result) {
      if (_disposed) return;
      // SWR later arrival: a background network refresh landed.
      _status = KoolbaseListStatus.loaded;
      _records = result.records;
      _isFromCache = false;
      _error = null;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    super.dispose();
  }
}

/// An opinionated list over a Koolbase collection.
///
/// NOT headless (unlike [KoolbaseAuthGate]): this component owns a
/// [ListView.separated] inside a [RefreshIndicator], because a scrollable,
/// pull-to-refresh list is what nearly every collection screen is. What it
/// owns about DATA lives in [KoolbaseCollectionController], deliberately
/// separable, so grid/sliver/custom-scroll variants can be added later
/// without touching the fetch and stream lifecycle. Per-item appearance is
/// entirely yours via [itemBuilder]; empty/error/loading are slotted.
///
/// ```dart
/// KoolbaseCollectionList(
///   collection: 'expenses',
///   query: (q) => q
///       .where('user_id', isEqualTo: KoolbaseAuthScope.of(context).user!.id)
///       .orderBy('created_at', descending: true),
///   itemBuilder: (context, record) => ExpenseTile(record),
/// )
/// ```
///
/// The `query` callback runs for EVERY fetch and refresh with a fresh query
/// instance, and must be deterministic — see [KoolbaseQueryBuilder]. For a
/// scoped collection, filter on the rule's owner_field exactly as
/// koolbase_describe_project reports it; the server enforces the rule either
/// way, but the filter is what makes the query return the caller's records.
class KoolbaseCollectionList extends StatefulWidget {
  const KoolbaseCollectionList({
    super.key,
    required this.collection,
    required this.itemBuilder,
    this.query,
    this.empty,
    this.error,
    this.loading,
    this.separatorBuilder,
    this.padding,
    @visibleForTesting this.controller,
  });

  /// The collection to list.
  final String collection;

  /// Builds one record's row. Appearance is entirely the caller's.
  final Widget Function(BuildContext context, KoolbaseRecord record)
      itemBuilder;

  /// Shapes each fresh query. Null lists the collection unfiltered.
  final KoolbaseQueryBuilder? query;

  /// Shown when the load succeeded and there are no records.
  final WidgetBuilder? empty;

  /// Shown when the FIRST load failed with nothing to show. Receives the
  /// error and a retry callback. Later refresh failures keep the records.
  final Widget Function(
      BuildContext context, Object error, Future<void> Function() retry)? error;

  /// Shown during the first load. Defaults to a centered spinner.
  final WidgetBuilder? loading;

  /// Separator between rows. Defaults to a hairline [Divider].
  final IndexedWidgetBuilder? separatorBuilder;

  /// Padding for the list. Defaults to none.
  final EdgeInsetsGeometry? padding;

  /// Test seam only: inject a controller instead of constructing one.
  final KoolbaseCollectionController? controller;

  @override
  State<KoolbaseCollectionList> createState() => _KoolbaseCollectionListState();
}

class _KoolbaseCollectionListState extends State<KoolbaseCollectionList> {
  late final KoolbaseCollectionController _controller;
  late final bool _ownsController;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ??
        KoolbaseCollectionController(
          collection: widget.collection,
          queryBuilder: widget.query,
        );
    _controller.addListener(_onChanged);
    _controller.load();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    switch (_controller.status) {
      case KoolbaseListStatus.loading:
        return widget.loading?.call(context) ??
            const Center(child: CircularProgressIndicator());

      case KoolbaseListStatus.error:
        final err = _controller.error!;
        return widget.error?.call(context, err, _controller.refresh) ??
            _DefaultError(error: err, onRetry: _controller.refresh);

      case KoolbaseListStatus.loaded:
        final records = _controller.records;
        if (records.isEmpty) {
          // Refreshable even when empty: wrap in a scrollable so the pull
          // gesture works over the empty slot.
          return RefreshIndicator(
            onRefresh: _controller.refresh,
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: widget.empty?.call(context) ?? const _DefaultEmpty(),
                ),
              ),
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: _controller.refresh,
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: widget.padding,
            itemCount: records.length,
            separatorBuilder:
                widget.separatorBuilder ?? (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) =>
                widget.itemBuilder(context, records[index]),
          ),
        );
    }
  }
}

class _DefaultEmpty extends StatelessWidget {
  const _DefaultEmpty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Nothing here yet.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}

class _DefaultError extends StatelessWidget {
  const _DefaultError({required this.error, required this.onRetry});

  final Object error;
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
              "Couldn't load this list.",
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
