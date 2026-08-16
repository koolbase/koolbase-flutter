import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koolbase_flutter/koolbase_flutter.dart';

/// KoolbaseCollectionList behavioral tests.
///
/// The controller owns the properties that justify the component existing;
/// each has a test that fails if it regresses:
///
///  * SWR handled: a cached first arrival is shown (isFromCache), and the
///    stream's later network arrival replaces it — data arriving twice is
///    the designed path, not a glitch
///  * fresh query per fetch: the builder MUTATES its instance and stream
///    identity derives from filters, so load and refresh must each
///    construct a new query
///  * one subscription per query identity: a deterministic builder yields
///    a stable streamKey, so the steady state subscribes exactly once
///  * stale beats blank: a failed refresh keeps the records; only a first
///    load with nothing to show is an error STATE
///
/// _FakeQuery subclasses the real KoolbaseQuery, overriding only get(),
/// stream, and streamKey — the controller cannot tell the difference.

class _FakeQuery extends KoolbaseQuery {
  _FakeQuery({
    required this.onGet,
    required StreamController<QueryResult> refreshController,
    String identity = 'k1',
  })  : _refresh = refreshController,
        _identity = identity,
        super(
          baseUrl: 'https://api.test',
          publicKey: 'pk_test',
          collectionName: 'expenses',
        );

  final Future<QueryResult> Function() onGet;
  final StreamController<QueryResult> _refresh;
  final String _identity;
  int listens = 0;

  @override
  Future<QueryResult> get({bool fresh = false}) => onGet();

  @override
  Stream<QueryResult> get stream {
    listens++;
    return _refresh.stream;
  }

  @override
  String get streamKey => _identity;
}

KoolbaseRecord _record(String id) => KoolbaseRecord(
      id: id,
      collection: 'expenses',
      createdBy: 'u1',
      data: {'title': id},
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      revision: 1,
    );

QueryResult _result(List<String> ids, {bool fromCache = false}) => QueryResult(
      records: [for (final id in ids) _record(id)],
      total: ids.length,
      isFromCache: fromCache,
    );

void main() {
  group('KoolbaseCollectionController', () {
    test('SWR: cached seed shown, stream arrival replaces it', () async {
      final refresh = StreamController<QueryResult>.broadcast();
      final query = _FakeQuery(
        onGet: () async => _result(['a', 'b'], fromCache: true),
        refreshController: refresh,
      );
      final c = KoolbaseCollectionController(
        collection: 'expenses',
        baseQuery: () => query,
      );

      await c.load();
      expect(c.status, KoolbaseListStatus.loaded);
      expect(c.records.map((r) => r.id), ['a', 'b']);
      expect(c.isFromCache, isTrue, reason: 'the SWR first arrival');

      // Background network refresh lands with fresher data.
      refresh.add(_result(['a', 'b', 'c']));
      await Future<void>.delayed(Duration.zero);

      expect(c.records.map((r) => r.id), ['a', 'b', 'c'],
          reason: 'the SWR second arrival must replace the cached seed');
      expect(c.isFromCache, isFalse);

      c.dispose();
      await refresh.close();
    });

    test('first-load failure is an error state; retry recovers', () async {
      final refresh = StreamController<QueryResult>.broadcast();
      var fail = true;
      final query = _FakeQuery(
        onGet: () async {
          if (fail) throw Exception('network down');
          return _result(['a']);
        },
        refreshController: refresh,
      );
      final c = KoolbaseCollectionController(
        collection: 'expenses',
        baseQuery: () => query,
      );

      await c.load();
      expect(c.status, KoolbaseListStatus.error);
      expect(c.error, isNotNull);

      fail = false;
      await c.refresh();
      expect(c.status, KoolbaseListStatus.loaded);
      expect(c.records.single.id, 'a');

      c.dispose();
      await refresh.close();
    });

    test('stale beats blank: a failed refresh keeps the records', () async {
      final refresh = StreamController<QueryResult>.broadcast();
      var fail = false;
      final query = _FakeQuery(
        onGet: () async {
          if (fail) throw Exception('flaky network');
          return _result(['a', 'b']);
        },
        refreshController: refresh,
      );
      final c = KoolbaseCollectionController(
        collection: 'expenses',
        baseQuery: () => query,
      );

      await c.load();
      expect(c.records.length, 2);

      fail = true;
      await c.refresh();

      expect(c.status, KoolbaseListStatus.loaded,
          reason:
              'a failed refresh over existing records is not an error state');
      expect(c.records.length, 2, reason: 'stale beats blank');
      expect(c.refreshing, isFalse);

      c.dispose();
      await refresh.close();
    });

    test('a fresh query is constructed for every fetch', () async {
      final refresh = StreamController<QueryResult>.broadcast();
      var built = 0;
      final c = KoolbaseCollectionController(
        collection: 'expenses',
        baseQuery: () {
          built++;
          return _FakeQuery(
            onGet: () async => _result(['a']),
            refreshController: refresh,
          );
        },
      );

      await c.load();
      await c.refresh();
      await c.refresh();

      expect(built, 3,
          reason: 'KoolbaseQuery.where mutates its instance and stream '
              'identity derives from filters — reuse is forbidden');

      c.dispose();
      await refresh.close();
    });

    test('one subscription per stable query identity', () async {
      final refresh = StreamController<QueryResult>.broadcast();
      final queries = <_FakeQuery>[];
      final c = KoolbaseCollectionController(
        collection: 'expenses',
        baseQuery: () {
          final q = _FakeQuery(
            onGet: () async => _result(['a']),
            refreshController: refresh,
          ); // identity 'k1' every time — a deterministic builder
          queries.add(q);
          return q;
        },
      );

      await c.load();
      await c.refresh();
      await c.refresh();

      final totalListens = queries.fold<int>(0, (sum, q) => sum + q.listens);
      expect(totalListens, 1,
          reason: 'same identity must not stack subscriptions per refresh');

      c.dispose();
      await refresh.close();
    });

    test('dispose stops stream arrivals from mutating state', () async {
      final refresh = StreamController<QueryResult>.broadcast();
      final query = _FakeQuery(
        onGet: () async => _result(['a']),
        refreshController: refresh,
      );
      final c = KoolbaseCollectionController(
        collection: 'expenses',
        baseQuery: () => query,
      );

      await c.load();
      c.dispose();

      refresh.add(_result(['x', 'y', 'z']));
      await Future<void>.delayed(Duration.zero);
      expect(c.records.single.id, 'a',
          reason: 'a disposed controller must not receive arrivals');
      await refresh.close();
    });
  });

  group('KoolbaseCollectionList widget', () {
    Widget app(KoolbaseCollectionController controller,
        {WidgetBuilder? empty}) {
      return MaterialApp(
        home: Scaffold(
          body: KoolbaseCollectionList(
            collection: 'expenses',
            controller: controller,
            empty: empty,
            itemBuilder: (context, record) => Text('ROW:${record.id}'),
          ),
        ),
      );
    }

    testWidgets('loading spinner first, then rows', (tester) async {
      final refresh = StreamController<QueryResult>.broadcast();
      final completer = Completer<QueryResult>();
      final c = KoolbaseCollectionController(
        collection: 'expenses',
        baseQuery: () => _FakeQuery(
          onGet: () => completer.future,
          refreshController: refresh,
        ),
      );

      await tester.pumpWidget(app(c));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      completer.complete(_result(['a', 'b']));
      await tester.pump();

      expect(find.text('ROW:a'), findsOneWidget);
      expect(find.text('ROW:b'), findsOneWidget);
      await refresh.close();
    });

    testWidgets('empty result shows the empty slot, still refreshable',
        (tester) async {
      final refresh = StreamController<QueryResult>.broadcast();
      final c = KoolbaseCollectionController(
        collection: 'expenses',
        baseQuery: () => _FakeQuery(
          onGet: () async => _result(const []),
          refreshController: refresh,
        ),
      );

      await tester.pumpWidget(app(
        c,
        empty: (context) => const Text('NOTHING'),
      ));
      await tester.pump();

      expect(find.text('NOTHING'), findsOneWidget);
      expect(find.byType(RefreshIndicator), findsOneWidget,
          reason: 'an empty list must still accept the pull gesture');
      await refresh.close();
    });

    testWidgets('stream arrival rebuilds the rows', (tester) async {
      final refresh = StreamController<QueryResult>.broadcast();
      final c = KoolbaseCollectionController(
        collection: 'expenses',
        baseQuery: () => _FakeQuery(
          onGet: () async => _result(['a'], fromCache: true),
          refreshController: refresh,
        ),
      );

      await tester.pumpWidget(app(c));
      await tester.pump();
      expect(find.text('ROW:a'), findsOneWidget);

      refresh.add(_result(['a', 'b']));
      await tester.pump();

      expect(find.text('ROW:b'), findsOneWidget,
          reason: 'the SWR second arrival must reach the UI');
      await refresh.close();
    });
  });
}
