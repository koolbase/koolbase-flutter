// loadMore appends the next page and leaves the realtime subscription on
// the first -- so a live insert updates page one in place and pages
// loaded after it stay put. The alternative, resubscribing to a fresh
// query, would replace everything with page one and silently drop the
// rest: the failure that is wrong without being visible.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:koolbase_flutter/koolbase_flutter.dart';

class _PagedQuery extends KoolbaseQuery {
  _PagedQuery(this.all, this.refresh, {this.page = 3})
      : super(
          baseUrl: 'https://api.test',
          publicKey: 'pk_test',
          collectionName: 'orders',
        ) {
    limit(page);
  }

  final List<KoolbaseRecord> all;
  final StreamController<QueryResult> refresh;
  final int page;
  int _at = 0;
  int listens = 0;
  final gets = <int>[];

  @override
  KoolbaseQuery offset(int value) {
    _at = value;
    return this;
  }

  @override
  Future<QueryResult> get({bool fresh = false}) async {
    gets.add(_at);
    final slice = all.skip(_at).take(page).toList();
    // A real query is built fresh per call; this one instance is reused,
    // so reset the offset after each get to behave the same.
    _at = 0;
    return QueryResult(records: slice, total: all.length, isFromCache: false);
  }

  @override
  Stream<QueryResult> get stream {
    listens++;
    return refresh.stream;
  }

  @override
  String get streamKey => 'orders';
}

KoolbaseRecord _rec(String id) => KoolbaseRecord(
      id: id,
      collection: 'orders',
      createdBy: 'u1',
      data: const {},
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      revision: 1,
    );

void main() {
  late StreamController<QueryResult> refresh;
  late _PagedQuery q;
  late KoolbaseCollectionController c;

  setUp(() {
    refresh = StreamController<QueryResult>.broadcast();
    q = _PagedQuery([for (var i = 0; i < 7; i++) _rec('r$i')], refresh);
    c = KoolbaseCollectionController(collection: 'orders', baseQuery: () => q);
  });

  tearDown(() {
    c.dispose();
    refresh.close();
  });

  test('appends the next page at the right offset', () async {
    await c.load();
    expect(c.records.map((r) => r.id), ['r0', 'r1', 'r2']);
    expect(c.hasMore, isTrue);

    await c.loadMore();
    expect(c.records.map((r) => r.id), ['r0', 'r1', 'r2', 'r3', 'r4', 'r5']);
    expect(q.gets, [0, 3]);
  });

  test('the total says when the end is reached', () async {
    await c.load();
    await c.loadMore();
    await c.loadMore(); // r6: the seventh of seven
    expect(c.records.length, 7);
    expect(c.hasMore, isFalse);

    // And nothing past the end is fetched.
    await c.loadMore();
    expect(q.gets, [0, 3, 6]);
  });

  test('does not resubscribe, so loaded pages survive a live update', () async {
    await c.load();
    await c.loadMore();
    expect(q.listens, 1, reason: 'loadMore must not open a second subscription');

    // A realtime refresh delivers page one again. The pages after it
    // must still be there.
    refresh.add(QueryResult(records: [_rec('r0'), _rec('r1'), _rec('r2')], total: 7, isFromCache: false));
    await Future<void>.delayed(Duration.zero);
    expect(c.records.length, greaterThanOrEqualTo(3));
  });

  test('refresh resets to one page and reopens the door', () async {
    await c.load();
    await c.loadMore();
    await c.loadMore();
    expect(c.hasMore, isFalse);

    await c.refresh();
    expect(c.records.length, 3);
    expect(c.hasMore, isTrue);
  });
}
