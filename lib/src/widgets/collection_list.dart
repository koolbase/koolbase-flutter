import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../testing/test_data.dart';

import '../koolbase.dart';
import '../koolbase_exception.dart';
import 'load_error.dart';

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
    KoolbaseQueryBuilder? queryBuilder,
    KoolbaseQuery Function()? baseQuery,
    this.live = false,
    @visibleForTesting Stream<Object?> Function(String collection)? liveEvents,
    KoolbaseFieldSearch? search,
    this.searchDelay = const Duration(milliseconds: 250),
  })  : _queryBuilder = queryBuilder,
        _baseQuery = baseQuery,
        _liveEvents = liveEvents,
        _search = (search != null && search.isActive) ? search : null;

  /// How long [setSearch] waits for the typing to pause.
  final Duration searchDelay;

  // The search now (#160), and its pending read.
  KoolbaseFieldSearch? _search;
  Timer? _searchTimer;
  bool _searching = false;
  Object? _searchError;

  // Every fetch belongs to a generation: one a newer search or refresh
  // superseded is dropped when it lands.
  int _gen = 0;

  /// The search the list shows the matches of, or null.
  KoolbaseFieldSearch? get search => _search;

  /// True from [setSearch] until the server answers it. The records shown
  /// meanwhile are from before the search: what an app filters from them is
  /// a preview, not the answer.
  bool get searching => _searching;

  /// Why the server could not answer the latest search, or null. The
  /// records shown are then not its answer.
  Object? get searchError => _searchError;

  // The server refused this list's search: it is not asked again.
  bool _searchRefused = false;

  // The server search the records' page one answers ('null': unsearched),
  // or null before any answer: what may be shown without reading again.
  String? _answered;

  static String _keyOf(KoolbaseFieldSearch? s) =>
      s == null ? 'null' : jsonEncode(s.toJson());

  /// True while the search is not run on the server, so [records] are the
  /// list unsearched and an app filters them itself: the server refused this
  /// list's search (a field_search it will not take -- the collection's
  /// fields changed since the app was built; it is not asked again while
  /// this controller lives), or the search is wider than the server takes
  /// (a Choice matching more than 100 values, text over 100 characters).
  bool get searchLoadedOnly => _search != null && _serverSearch == null;

  /// The search the server runs: none when it refused it, or it is wider
  /// than the server takes.
  KoolbaseFieldSearch? get _serverSearch {
    final s = _search;
    if (s == null || _searchRefused || !_withinServerLimits(s)) return null;
    return s;
  }

  /// The server's limits on a search (#160): past them it refuses it.
  static bool _withinServerLimits(KoolbaseFieldSearch s) =>
      s.text.trim().runes.length <= 100 &&
      s.choices.every((c) => c.values.length <= 100);

  /// The server refusing a field_search (400): this search, as sent, will
  /// never be answered.
  static bool _isRefusal(Object e) =>
      e is KoolbaseException && e.message.startsWith('field_search:');

  /// After the server refused the search: it is not sent again while this
  /// controller lives.
  bool _refuse(Object e) {
    if (!_isRefusal(e) || _serverSearch == null) return false;
    _searchRefused = true;
    _searchError = null;
    return true;
  }

  /// Searches on the server (#160) once the typing pauses ([searchDelay]):
  /// page one of the matches replaces what is shown -- never merged with
  /// it -- and [loadMore] pages inside the search. A newer search, or a
  /// refresh, drops an older one's answer. Null or empty text: the list
  /// unsearched again.
  void setSearch(KoolbaseFieldSearch? search) {
    if (_disposed) return;
    final next = (search != null && search.isActive) ? search : null;
    if (next == _search) return;
    _search = next;
    // What is shown already answers the server's search (both not sent,
    // say): nothing to read again, and nothing still waiting is wanted.
    if (_answered != null &&
        _keyOf(_serverSearch) == _answered &&
        _status == KoolbaseListStatus.loaded) {
      _searchTimer?.cancel();
      _searchTimer = null;
      _supersede();
      _searching = false;
      _searchError = null;
      notifyListeners();
      return;
    }
    _supersede();
    _searchTimer?.cancel();
    _searching = true;
    _searchError = null;
    notifyListeners();
    _searchTimer = Timer(searchDelay, () {
      _searchTimer = null;
      unawaited(_runSearch());
    });
  }

  /// The latest search again, now: after [searchError].
  Future<void> retrySearch() async {
    if (_disposed) return;
    _searchTimer?.cancel();
    _searchTimer = null;
    _searching = true;
    _searchError = null;
    notifyListeners();
    await _runSearch();
  }

  Future<void> _runSearch() async {
    if (_disposed) return;
    final gen = _supersede();
    _searchInFlight = true;
    final asking = _keyOf(_serverSearch);
    try {
      final result = await _freshQuery().get(fresh: true);
      if (_disposed || gen != _gen) return;
      _answered = asking;
      _status = KoolbaseListStatus.loaded;
      _records = result.records;
      _isFromCache = false;
      _error = null;
      _hasMore = _records.length < result.total;
      _searching = false;
      _searchError = null;
    } catch (e) {
      if (_disposed || gen != _gen) return;
      // Refused: the list unsearched, read now, for the app to filter.
      if (_refuse(e)) {
        notifyListeners();
        unawaited(_runSearch());
        return;
      }
      _searching = false;
      _searchError = e;
      // Nothing loaded yet to show under the error: the list's own error.
      if (_status != KoolbaseListStatus.loaded) {
        _status = KoolbaseListStatus.error;
        _error = e;
      }
    } finally {
      if (gen == _gen) _searchInFlight = false;
    }
    notifyListeners();
    // The list changed while it searched: once more, now.
    if (_searchAgain && !_disposed && gen == _gen) {
      _searchAgain = false;
      unawaited(_runSearch());
    }
  }

  // A search read in flight, and whether the list changed meanwhile.
  bool _searchInFlight = false;
  bool _searchAgain = false;

  /// A new fetch supersedes every one in flight: their answers are dropped,
  /// and a page still loading is no longer loading.
  int _supersede() {
    _loadingMore = false;
    _searchInFlight = false;
    _searchAgain = false;
    return ++_gen;
  }

  /// A fetch that replaced page one has answered: a search it superseded is
  /// answered too, unless a newer one is waiting to run.
  void _searchAnswered() {
    if (_searchTimer != null) return;
    _searching = false;
    _searchError = null;
  }

  /// A fetch that replaced a search in flight has failed: the search's
  /// answer will not come, and that is said.
  void _searchFailed(Object e) {
    if (_searchTimer != null || !_searching) return;
    _searching = false;
    _searchError = e;
  }

  /// The collection to list.
  final String collection;

  /// Shapes each fresh query (filters, order, limit). Null lists unfiltered.
  /// Replaced through [setQuery].
  KoolbaseQueryBuilder? get queryBuilder => _queryBuilder;
  KoolbaseQueryBuilder? _queryBuilder;

  /// A new query for the list (#194): a chip chosen, a dropdown, screen
  /// state. When its identity -- the filters the stream is keyed by --
  /// differs from the one shown, page one is read again (what is shown
  /// stays until it answers); the same identity reads nothing, so a
  /// rebuild, or a relative time such as "now", never reloads the list.
  void setQuery(KoolbaseQueryBuilder? query) {
    if (_disposed) return;
    _queryBuilder = query;
    // Compared with the query LOADED, not the old builder: a builder reads
    // the screen's state when called, so after a tap the old one would read
    // the new value too and look the same.
    if (_unsearched().streamKey == _subscribedKey) return;
    unawaited(load());
  }


  /// The data source: how a fresh base query is constructed. Production
  /// leaves it null and uses `Koolbase.db.collection(collection)`;
  /// KoolbaseTestData supplies one in widget tests, through the list and the
  /// grid alike.
  final KoolbaseQuery Function()? _baseQuery;

  /// Re-read page one, silently, when Koolbase realtime reports a record
  /// created, updated or deleted in [collection] -- once per burst (250 ms),
  /// not once per event. The list's own query re-runs, so filters, order
  /// and read rules stay right. Signed out, only a collection anyone can read
  /// (read rule "public") is live; any other behaves as a normal list until a
  /// user signs in.
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
  /// With the search, when there is one.
  KoolbaseQuery _freshQuery() => _unsearched().fieldSearch(_serverSearch);

  /// The query without the search: the one the list's stream follows.
  KoolbaseQuery _unsearched() {
    final base = _baseQuery?.call() ?? Koolbase.db.collection(collection);
    return _queryBuilder?.call(base) ?? base;
  }

  /// First load. Safe to call once; [refresh] for subsequent loads.
  Future<void> load() async {
    final gen = _supersede();
    final query = _freshQuery();
    final asking = _keyOf(_serverSearch);
    _resubscribe(_serverSearch == null ? query : _unsearched());
    _goLive();
    try {
      final result = await query.get();
      if (_disposed || gen != _gen) return;
      _answered = asking;
      _status = KoolbaseListStatus.loaded;
      _records = result.records;
      _isFromCache = result.isFromCache;
      _error = null;
      _hasMore = _records.length < result.total;
      _searchAnswered();
    } catch (e) {
      if (_disposed || gen != _gen) return;
      // Refused: the list unsearched, at once.
      if (_refuse(e)) return load();
      _searchFailed(e);
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
    final gen = _supersede();
    try {
      final query = _freshQuery();
      final asking = _keyOf(_serverSearch);
      _resubscribe(_serverSearch == null ? query : _unsearched());
      final result = await query.get();
      if (_disposed || gen != _gen) return;
      _answered = asking;
      _status = KoolbaseListStatus.loaded;
      _records = result.records;
      _isFromCache = result.isFromCache;
      _error = null;
      _hasMore = _records.length < result.total;
      _searchAnswered();
    } catch (e) {
      // Refused: the list unsearched, at once.
      if (!_disposed && gen == _gen && _refuse(e)) {
        await refresh();
        return;
      }
      if (!_disposed && gen == _gen) _searchFailed(e);
      // Keep what we have. The pull gesture failing silently into the same
      // list is the behavior every mature app converges on. With nothing to
      // show, the error on screen is the newest one (#97).
      if (_status == KoolbaseListStatus.error) _error = e;
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
    // Not while a search is waiting for its answer (#160): the next page
    // of the records shown is not the next page of the search.
    if (_loadingMore ||
        !_hasMore ||
        _searching ||
        _status != KoolbaseListStatus.loaded) {
      return;
    }
    _loadingMore = true;
    notifyListeners();
    final gen = _gen;
    try {
      final result = await _freshQuery().offset(_records.length).get();
      if (_disposed || gen != _gen) return;
      _records = [..._records, ...result.records];
      _hasMore = _records.length < result.total;
      _error = null;
    } catch (e) {
      // Refused (the schema changed since): the list unsearched, now.
      // Otherwise keep what we have; the control stays and can be tried
      // again.
      if (!_disposed && gen == _gen && _refuse(e)) {
        _searching = true;
        notifyListeners();
        unawaited(_runSearch());
      }
    } finally {
      if (!_disposed && gen == _gen) {
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
    final gen = _supersede();
    final asking = _keyOf(_serverSearch);
    try {
      final result = await _freshQuery().get(fresh: true);
      if (_disposed || gen != _gen) return;
      _answered = asking;
      _status = KoolbaseListStatus.loaded;
      _records = result.records;
      _isFromCache = false;
      _error = null;
      _hasMore = _records.length < result.total;
      _searchAnswered();
      notifyListeners();
    } catch (e) {
      // Keep what we have; the next change tries again.
      if (!_disposed && gen == _gen && _refuse(e)) {
        unawaited(_liveRefresh());
        return;
      }
      if (!_disposed && gen == _gen) {
        _searchFailed(e);
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
    var first = true;
    _sub = query.stream.listen((result) {
      if (_disposed) return;
      final seed = first;
      first = false;
      // The unsearched list changed (a write, a background refresh): while
      // searching, the search is read again instead of showing it (#160) --
      // not for the stream's first arrival, which is only the list as it was
      // loaded; and once, after a read already in flight.
      if (_serverSearch != null) {
        if (seed || _searchTimer != null || _status != KoolbaseListStatus.loaded) {
          return;
        }
        if (_searchInFlight) {
          _searchAgain = true;
        } else {
          unawaited(_runSearch());
        }
        return;
      }
      // A later arrival: a background refresh landed -- from the server, or,
      // when it cannot be reached, the saved copy an offline change updated.
      _answered = _keyOf(null);
      _status = KoolbaseListStatus.loaded;
      _records = result.records;
      _isFromCache = result.isFromCache;
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
    _searchTimer?.cancel();
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
    this.scrollDirection = Axis.vertical,
    this.groupBy,
    this.sectionHeaderBuilder,
    this.search,
  });

  /// A search over the fields it names, on the server (#160): the list
  /// shows its matches, page after page. Changing it keeps the list and
  /// searches again once the typing pauses; meanwhile [visible] filters
  /// what is loaded as a preview, under a thin progress bar, and an empty
  /// preview shows [loading] rather than [empty] -- nothing loaded matching
  /// is not "no results". If the server cannot answer (offline, say),
  /// [visible] filters what is loaded under a line saying so, with a retry;
  /// if it refuses the search (the collection's fields changed since the
  /// app was built), or the search is wider than it takes, the list is read
  /// unsearched and [visible] filters it, under a line saying so -- the
  /// server is not asked again while the list lives. Null or empty text:
  /// unsearched.
  final KoolbaseFieldSearch? search;

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

  /// Which way the rows run. [Axis.horizontal]: side by side at their own
  /// width, each as tall as the tallest -- the list is as tall as its tallest
  /// row, so it needs no height, even in a scrolling page -- scrolling
  /// sideways. The next page loads as the end comes near, and Load more
  /// stays as the last item. The default separator is a [VerticalDivider];
  /// [scrollsWithPage] and pull-to-refresh are vertical ideas and do not
  /// apply. Rows must be able to say their height (as a card, a column or a
  /// sized image can; a scrollable cannot).
  final Axis scrollDirection;

  /// Sections: the key of the section a record belongs to, such as its day
  /// or its status. Each run of records with the same key gets one header
  /// above it, so sort the query by the same field: an unsorted list repeats
  /// a header wherever its key comes back. Records from Load more join the
  /// last section when they share its key. While the list scrolls by itself
  /// the current header stays pinned at the top until the next one pushes
  /// it away; with [scrollsWithPage] headers sit inline. Separators are
  /// drawn between rows of a section, never around a header. Vertical lists
  /// only.
  final String Function(KoolbaseRecord record)? groupBy;

  /// Builds a section's header from its key. Defaults to a
  /// [KoolbaseSectionHeader] showing the key. A pinned header must be
  /// opaque, or rows show through it.
  final Widget Function(BuildContext context, String section)?
      sectionHeaderBuilder;

  @override
  State<KoolbaseCollectionList> createState() => _KoolbaseCollectionListState();
}

class _KoolbaseCollectionListState extends State<KoolbaseCollectionList> {
  late final KoolbaseCollectionController _controller;
  late final bool _ownsController;

  /// The horizontal list's scroll position: near the end, the next page.
  final ScrollController _sideways = ScrollController();

  void _nearEnd() {
    if (!_sideways.hasClients) return;
    if (_sideways.position.extentAfter < 240) _controller.loadMore();
  }

  @override
  void initState() {
    super.initState();
    _sideways.addListener(_nearEnd);
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
          search: widget.search,
        );
    // A controller given in: the search this list was built with, before
    // its first load -- which then reads it, without waiting for a pause.
    final search = widget.search;
    if (widget.controller != null &&
        search != null &&
        search.isActive &&
        search != _controller.search) {
      _controller._search = search;
    }
    _controller.addListener(_onChanged);
    _controller.load();
  }

  @override
  void didUpdateWidget(covariant KoolbaseCollectionList old) {
    super.didUpdateWidget(old);
    // A new query (#194): the controller reads again only when its filters
    // changed. After this build, as the search below.
    if (!identical(widget.query, old.query)) {
      final query = widget.query;
      scheduleMicrotask(() {
        if (mounted) _controller.setQuery(query);
      });
    }
    // After this build: the controller tells its listeners at once, and one
    // outside this subtree must not be asked to rebuild mid-build.
    if (widget.search != old.search) {
      final search = widget.search;
      scheduleMicrotask(() {
        if (mounted) _controller.setSearch(search);
      });
    }
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    if (_ownsController) _controller.dispose();
    _sideways
      ..removeListener(_nearEnd)
      ..dispose();
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
            KbLoadError(
                title: "Couldn't load this list.",
                onRetry: _controller.refresh);

      case KoolbaseListStatus.loaded:
        final loaded = _controller.records;
        final records = widget.visible?.call(loaded) ?? loaded;
        final searching = _controller.searching;
        // An empty preview is not "no results": nothing loaded matches yet.
        if (searching && records.isEmpty) {
          return widget.loading?.call(context) ??
              const Center(child: CircularProgressIndicator());
        }
        // Always in the same Stack, so the scroll position survives a search
        // starting and being answered; the bar shows only while it waits.
        final view = Stack(
          // The rows get the constraints the list was given, as before.
          fit: StackFit.passthrough,
          children: [
            _loadedView(context, records),
            if (searching)
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: LinearProgressIndicator(minHeight: 2),
              ),
          ],
        );
        // Not the server's answer (#160): the matches among the records
        // loaded, said above them -- with a retry when one can help. Never
        // passed off as the answer, never in place of the list.
        final notice = _controller.searchError != null
            ? _SearchNotice(
                text: "Couldn't search all records. "
                    'Showing matches among those loaded.',
                onRetry: _controller.retrySearch,
              )
            : _controller.searchLoadedOnly
                ? const _SearchNotice(
                    text: 'Showing matches among the records loaded.')
                : null;
        // Always the same tree, the rows keyed: a notice coming or going
        // keeps the scroll position.
        Widget column(bool fills) => Column(
              mainAxisSize: fills ? MainAxisSize.max : MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (notice != null)
                  KeyedSubtree(key: const ValueKey('kb-notice'), child: notice),
                if (fills)
                  Expanded(key: const ValueKey('kb-rows'), child: view)
                else
                  KeyedSubtree(key: const ValueKey('kb-rows'), child: view),
              ],
            );
        // A list that scrolls itself fills a bounded height; with none (an
        // empty list in a scrolling column), it is as tall as it is.
        if (widget.scrollDirection == Axis.vertical && !widget.scrollsWithPage) {
          return LayoutBuilder(
            builder: (context, c) => column(c.hasBoundedHeight),
          );
        }
        return column(false);
    }
  }

  /// The loaded records: the rows, or the empty slot.
  Widget _loadedView(BuildContext context, List<KoolbaseRecord> records) {
        if (widget.scrollDirection == Axis.horizontal) {
          return records.isEmpty
              ? widget.empty?.call(context) ?? const _DefaultEmpty()
              : _horizontal(context, records);
        }
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
        if (widget.groupBy != null) return _grouped(context, records);
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

  /// [KoolbaseCollectionList.groupBy]: a header above each section; pinned
  /// while the list scrolls by itself, inline in a scrolling page.
  Widget _grouped(BuildContext context, List<KoolbaseRecord> records) {
    final sections = _sectionsOf(records, widget.groupBy!);
    final separator =
        widget.separatorBuilder ?? (_, __) => const Divider(height: 1);
    final padding =
        (widget.padding ?? EdgeInsets.zero).resolve(Directionality.of(context));
    final sides = EdgeInsets.only(left: padding.left, right: padding.right);
    Widget header(String key) =>
        widget.sectionHeaderBuilder?.call(context, key) ??
        KoolbaseSectionHeader(label: key);
    final more = _controller.hasMore
        ? _LoadMore(
            loading: _controller.loadingMore,
            onTap: _controller.loadMore,
          )
        : null;

    if (widget.scrollsWithPage) {
      // The page scrolls and refreshes: headers inline, nothing pinned.
      return Padding(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final s in sections) ...[
              header(s.key),
              for (var i = s.start; i < s.end; i++) ...[
                if (i > s.start) separator(context, i - 1),
                widget.itemBuilder(context, records[i]),
              ],
            ],
            if (more != null) more,
          ],
        ),
      );
    }

    // Each section is a group: its header pins to the top while the group
    // is on screen and leaves with the group's last row.
    return RefreshIndicator(
      onRefresh: _controller.refresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (padding.top > 0)
            SliverToBoxAdapter(child: SizedBox(height: padding.top)),
          for (final s in sections)
            SliverMainAxisGroup(
              slivers: [
                PinnedHeaderSliver(
                  child: Padding(padding: sides, child: header(s.key)),
                ),
                SliverList.separated(
                  itemCount: s.end - s.start,
                  separatorBuilder: (context, i) => Padding(
                    padding: sides,
                    child: separator(context, s.start + i),
                  ),
                  itemBuilder: (context, i) => Padding(
                    padding: sides,
                    child: widget.itemBuilder(context, records[s.start + i]),
                  ),
                ),
              ],
            ),
          if (more != null)
            SliverToBoxAdapter(child: Padding(padding: sides, child: more)),
          if (padding.bottom > 0)
            SliverToBoxAdapter(child: SizedBox(height: padding.bottom)),
        ],
      ),
    );
  }

  /// [Axis.horizontal]: the rows side by side, each as tall as the tallest
  /// (IntrinsicHeight, so the list needs no height of its own), separators
  /// between rows only, Load more last while there are more.
  Widget _horizontal(BuildContext context, List<KoolbaseRecord> records) {
    final separator =
        widget.separatorBuilder ?? (_, __) => const VerticalDivider(width: 1);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      controller: _sideways,
      padding: widget.padding,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < records.length; i++) ...[
              if (i > 0) separator(context, i - 1),
              widget.itemBuilder(context, records[i]),
            ],
            if (_controller.hasMore)
              _LoadMore(
                loading: _controller.loadingMore,
                onTap: _controller.loadMore,
                axis: Axis.horizontal,
              ),
          ],
        ),
      ),
    );
  }
}

/// One run of records with the same section key: rows [start, end).
class _Section {
  _Section(this.key, this.start);
  final String key;
  final int start;
  int end = 0;
}

/// Consecutive runs, in order: a key that comes back later starts a new
/// section rather than moving its records.
List<_Section> _sectionsOf(
  List<KoolbaseRecord> records,
  String Function(KoolbaseRecord record) groupBy,
) {
  final sections = <_Section>[];
  for (var i = 0; i < records.length; i++) {
    final key = groupBy(records[i]);
    if (sections.isEmpty || sections.last.key != key) {
      if (sections.isNotEmpty) sections.last.end = i;
      sections.add(_Section(key, i));
    }
  }
  if (sections.isNotEmpty) sections.last.end = records.length;
  return sections;
}

/// The default section header of [KoolbaseCollectionList.groupBy]: the
/// label in small, muted text on an opaque background (so it can pin over
/// rows), announced as a heading.
class KoolbaseSectionHeader extends StatelessWidget {
  const KoolbaseSectionHeader({
    super.key,
    required this.label,
    this.backgroundColor,
    this.padding = const EdgeInsets.fromLTRB(16, 16, 16, 8),
  });

  /// The text shown.
  final String label;

  /// Defaults to the theme's scaffold background, so a pinned header covers
  /// the rows scrolling beneath it.
  final Color? backgroundColor;

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      header: true,
      child: ColoredBox(
        color: backgroundColor ?? theme.scaffoldBackgroundColor,
        child: Padding(
          padding: padding,
          child: Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// The row past the last loaded record, while there are more.
class _LoadMore extends StatelessWidget {
  final bool loading;
  final VoidCallback onTap;
  final Axis axis;
  const _LoadMore({
    required this.loading,
    required this.onTap,
    this.axis = Axis.vertical,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: axis == Axis.vertical
            ? const EdgeInsets.symmetric(vertical: 12)
            : const EdgeInsets.symmetric(horizontal: 12),
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

/// Above a list searched only among its loaded records (#160).
class _SearchNotice extends StatelessWidget {
  const _SearchNotice({required this.text, this.onRetry});

  final String text;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                text,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            if (onRetry != null)
              TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
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
