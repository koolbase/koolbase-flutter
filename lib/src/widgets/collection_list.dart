import 'dart:async';

import 'package:flutter/material.dart';

import '../testing/test_data.dart';

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
    KoolbaseQuery Function()? baseQuery,
    this.live = false,
    @visibleForTesting Stream<Object?> Function(String collection)? liveEvents,
  })  : _baseQuery = baseQuery,
        _liveEvents = liveEvents;

  /// The collection to list.
  final String collection;

  /// Shapes each fresh query (filters, order, limit). Null lists unfiltered.
  final KoolbaseQueryBuilder? queryBuilder;

  /// The data source: how a fresh base query is constructed. Production
  /// leaves it null and uses `Koolbase.db.collection(collection)`;
  /// KoolbaseTestData supplies one in widget tests, through the list and the
  /// grid alike.
  final KoolbaseQuery Function()? _baseQuery;

  /// Re-read page one, silently, when Koolbase realtime reports a record
  /// created, updated or deleted in [collection] -- once per burst (250 ms),
  /// not once per event. The list's own query re-runs, so filters, order
  /// and read rules stay right. Realtime needs a signed-in user; until there
  /// is one the list behaves as a normal list.
  final bool live;

  /// Test seam only: the collection's realtime events. Production uses
  /// `Koolbase.realtime.on(collection:)`.
  final Stream<Object?> Function(String collection)? _liveEvents;

  StreamSubscription<Object?>? _liveSub;
  Timer? _liveTimer;

  KoolbaseListStatus _status = KoolbaseListStatus.loading;
  List<KoolbaseRecord> _records = const [];
  Object? _error;
  bool _isFromCache = false;
  bool _refreshing = false;
  bool _loadingMore = false;
  bool _hasMore = true;

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
    _goLive();
    try {
      final result = await query.get();
      if (_disposed) return;
      _status = KoolbaseListStatus.loaded;
      _records = result.records;
      _isFromCache = result.isFromCache;
      _error = null;
      _hasMore = _records.length < result.total;
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
      _hasMore = _records.length < result.total;
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

  /// True while [loadMore] runs, for a spinner at the foot of the list.
  bool get loadingMore => _loadingMore;

  /// Whether the collection has records past what is loaded. Exact:
  /// every page comes back with the query's total, so this is
  /// loaded < total, not a guess from a short page. True before the
  /// first load -- "we do not know yet" reads as "there may be more".
  bool get hasMore => _hasMore;

  /// The next page, appended.
  ///
  /// Deliberately does NOT resubscribe. The realtime subscription stays
  /// on the first page, so a live insert updates that page in place and
  /// the pages loaded after it stay put; resubscribing to a fresh query
  /// would replace everything with page one and silently drop the rest.
  /// So: live for the first page, static for the ones after, and
  /// [refresh] resets to one page. An honest compromise, stated.
  ///
  Future<void> loadMore() async {
    if (_loadingMore || !_hasMore || _status != KoolbaseListStatus.loaded) {
      return;
    }
    _loadingMore = true;
    notifyListeners();
    try {
      final result = await _freshQuery().offset(_records.length).get();
      if (_disposed) return;
      _records = [..._records, ...result.records];
      _hasMore = _records.length < result.total;
      _error = null;
    } catch (_) {
      // Keep what we have; the control stays and can be tried again.
    } finally {
      if (!_disposed) {
        _loadingMore = false;
        notifyListeners();
      }
    }
  }

  /// A live list's realtime subscription. Once, on the first load.
  void _goLive() {
    if (!live || _liveSub != null || _disposed) return;
    final events = _liveEvents?.call(collection) ?? _realtimeEvents(collection);
    _liveSub = events.listen((_) => _scheduleLiveRefresh(), onError: (_) {});
  }

  /// Record events only: not the subscribe acknowledgements. Before Koolbase
  /// is initialized there is no realtime client, and a live list is simply a
  /// list.
  static Stream<Object?> _realtimeEvents(String collection) {
    try {
      return Koolbase.realtime.on(collection: collection).where((e) =>
          e.type == RealtimeEventType.recordCreated ||
          e.type == RealtimeEventType.recordUpdated ||
          e.type == RealtimeEventType.recordDeleted);
    } catch (_) {
      return const Stream<Object?>.empty();
    }
  }

  /// A change someone made, reported by realtime: page one again, once per
  /// burst.
  void _scheduleLiveRefresh() {
    if (_disposed || _liveTimer != null) return;
    _liveTimer = Timer(const Duration(milliseconds: 250), () {
      _liveTimer = null;
      unawaited(_liveRefresh());
    });
  }

  /// Page one from the network, shown without the [refreshing] state -- the
  /// list just changes, as it does after the app's own writes. A failure
  /// keeps what is shown (stale beats blank).
  Future<void> _liveRefresh() async {
    if (_disposed) return;
    try {
      final result = await _freshQuery().get(fresh: true);
      if (_disposed) return;
      _status = KoolbaseListStatus.loaded;
      _records = result.records;
      _isFromCache = false;
      _error = null;
      _hasMore = _records.length < result.total;
      notifyListeners();
    } catch (_) {
      // Keep what we have; the next change tries again.
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
    _liveSub?.cancel();
    _liveTimer?.cancel();
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
    this.visible,
    this.scrollsWithPage = false,
    this.live = false,
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

  /// Transforms the loaded records before BOTH the empty decision and the
  /// rows, so a filter that leaves nothing shows the empty slot. Runs on
  /// every build over the records already loaded — it does not query. The
  /// Designer's search-on-list is built on this: a case-insensitive
  /// substring filter over the loaded page.
  final List<KoolbaseRecord> Function(List<KoolbaseRecord> loaded)? visible;

  /// For a list inside a scrolling page -- a screen whose body scrolls. The
  /// rows lay out at their natural height and the PAGE scrolls; Load more
  /// stays a row. Pull-to-refresh belongs to the page, so the list adds none.
  /// Without it, a list with records inside a scrolling column has no height
  /// to size to and throws ("Vertical viewport was given unbounded height").
  /// Default false: the list fills a bounded space and scrolls by itself.
  final bool scrollsWithPage;

  /// Keeps the list current with changes other people make: page one is
  /// re-read silently when realtime reports a change in [collection]. Needs
  /// a signed-in user. See [KoolbaseCollectionController.live].
  final bool live;

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
    // The data SOURCE, and only that: under KoolbaseTestData (widget tests),
    // the base query answers from its records; everything after is the
    // production controller.
    final testData = KoolbaseTestData.maybeOf(context);
    _controller = widget.controller ??
        KoolbaseCollectionController(
          collection: widget.collection,
          queryBuilder: widget.query,
          live: widget.live,
          baseQuery: testData == null
              ? null
              : () => testData.queryFor(widget.collection),
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
        final loaded = _controller.records;
        final records = widget.visible?.call(loaded) ?? loaded;
        if (records.isEmpty) {
          // In page mode the page scrolls and refreshes: the empty widget
          // alone, with no scroll view of its own.
          if (widget.scrollsWithPage) {
            return widget.empty?.call(context) ?? const _DefaultEmpty();
          }
          // Refreshable even when empty: wrap in a scrollable so the pull
          // gesture works over the empty slot.
          // The empty slot fills the available height so the pull gesture
          // has somewhere to happen — but only when a height IS available.
          // Inside an unbounded parent (a scrolling column, a column with no
          // Expanded) maxHeight is infinite, and pinning minHeight to it
          // forced the empty widget to infinite height: every empty list in
          // a scrolling screen threw. Found by a generated smoke test, not
          // by a user, which is the point of shipping them.
          return RefreshIndicator(
            onRefresh: _controller.refresh,
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight.isFinite
                        ? constraints.maxHeight
                        : 0,
                  ),
                  child: widget.empty?.call(context) ?? const _DefaultEmpty(),
                ),
              ),
            ),
          );
        }
        final list = ListView.separated(
            shrinkWrap: widget.scrollsWithPage,
            physics: widget.scrollsWithPage
                ? const NeverScrollableScrollPhysics()
                : const AlwaysScrollableScrollPhysics(),
            padding: widget.padding,
            // One more row while there is more to load: the control that
            // says so. A list that showed twenty and stopped was quietly
            // claiming to be the whole collection.
            itemCount: records.length + (_controller.hasMore ? 1 : 0),
            separatorBuilder:
                widget.separatorBuilder ?? (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              if (index == records.length) {
                return _LoadMore(
                  loading: _controller.loadingMore,
                  onTap: _controller.loadMore,
                );
              }
              return widget.itemBuilder(context, records[index]);
            },
          );
        // In page mode the page scrolls and refreshes; the list only lays out
        // its rows.
        if (widget.scrollsWithPage) return list;
        return RefreshIndicator(onRefresh: _controller.refresh, child: list);
    }
  }
}

/// The row past the last loaded record, while there are more.
class _LoadMore extends StatelessWidget {
  final bool loading;
  final VoidCallback onTap;
  const _LoadMore({required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : TextButton(onPressed: onTap, child: const Text('Load more')),
        ),
      );
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
