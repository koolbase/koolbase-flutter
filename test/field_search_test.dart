// #160: a search over the fields it names, on the server. The query sends
// field_search; the list's controller searches once the typing pauses, lets
// the newest search win, replaces what it shows with the server's answer
// (never merged with it), pages inside the search, and says when the server
// could not answer -- so a preview is never taken for the answer.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:koolbase_flutter/koolbase_flutter.dart';

KoolbaseRecord _rec(String id, String title) => KoolbaseRecord(
      id: id,
      collection: 'events',
      createdBy: 'u1',
      data: {'title': title},
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      revision: 1,
    );

const _food = KoolbaseFieldSearch(
  text: 'food',
  fields: ['title'],
  choices: [
    KoolbaseChoiceSearch(field: 'stage', values: ['in_progress'], listed: ['draft', 'in_progress']),
  ],
);

/// Answers like the server: the search's matches, or every record, paged.
/// Each get is noted with the search it ran; [hold] keeps a text's answer
/// back until released.
class _Server {
  _Server(this.all);
  final List<KoolbaseRecord> all;
  final asked = <({String? text, int offset})>[];
  final hold = <String, Completer<void>>{};
  Object? failWith;
  // Every read fails: offline.
  Object? failAll;
}

class _Query extends KoolbaseQuery {
  _Query(this.server)
      : super(baseUrl: 'https://api.test', publicKey: 'pk_test', collectionName: 'events') {
    limit(2);
  }
  final _Server server;
  int _at = 0;

  @override
  KoolbaseQuery offset(int value) {
    _at = value;
    return this;
  }

  @override
  Future<QueryResult> get({bool fresh = false}) async {
    final s = currentFieldSearch;
    server.asked.add((text: s?.text, offset: _at));
    final held = s == null ? null : server.hold[s.text];
    if (held != null) await held.future;
    if (server.failAll != null) throw server.failAll!;
    if (s != null && server.failWith != null) throw server.failWith!;
    final rows = s == null
        ? server.all
        : [
            for (final r in server.all)
              if ('${r.data['title']}'.toLowerCase().contains(s.text.toLowerCase())) r,
          ];
    return QueryResult(records: rows.skip(_at).take(2).toList(), total: rows.length, isFromCache: false);
  }

  @override
  Stream<QueryResult> get stream => const Stream.empty();

  @override
  String get streamKey => 'events';
}

void main() {
  test('the query sends field_search; empty text sends none', () async {
    final bodies = <Map<String, dynamic>>[];
    final client = MockClient((req) async {
      bodies.add(jsonDecode(req.body) as Map<String, dynamic>);
      return http.Response(jsonEncode({'records': [], 'total': 0}), 200);
    });
    KoolbaseQuery q() => KoolbaseQuery(
          baseUrl: 'https://api.test',
          publicKey: 'pk_test',
          collectionName: 'events',
          client: client,
        );
    await q().fieldSearch(_food).get();
    expect(bodies.single['field_search'], {
      'text': 'food',
      'fields': ['title'],
      'choices': [
        {'field': 'stage', 'values': ['in_progress'], 'listed': ['draft', 'in_progress']},
      ],
    });
    await q().fieldSearch(const KoolbaseFieldSearch(text: '  ', fields: ['title'])).get();
    expect(bodies.last.containsKey('field_search'), isFalse);
  });

  group('the controller', () {
    late _Server server;
    late KoolbaseCollectionController c;
    setUp(() {
      server = _Server([
        _rec('1', 'Book swap'),
        _rec('2', 'Food truck rally'),
        _rec('3', 'Night market'),
        _rec('4', 'Street food'),
        _rec('5', 'Seafood fair'),
      ]);
      c = KoolbaseCollectionController(
        collection: 'events',
        baseQuery: () => _Query(server),
        searchDelay: const Duration(milliseconds: 20),
      );
    });
    tearDown(() => c.dispose());

    test('searches once the typing pauses; the answer replaces what is shown; pages inside it', () async {
      await c.load();
      expect(c.records.map((r) => r.id), ['1', '2']);
      c.setSearch(const KoolbaseFieldSearch(text: 'f', fields: ['title']));
      c.setSearch(const KoolbaseFieldSearch(text: 'fo', fields: ['title']));
      c.setSearch(_food);
      expect(c.searching, isTrue);
      expect(c.records.map((r) => r.id), ['1', '2'], reason: "the preview's source, until the answer");
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(server.asked.where((a) => a.text != null).map((a) => a.text), ['food']);
      expect(c.searching, isFalse);
      expect(c.records.map((r) => r.id), ['2', '4'], reason: 'replaced, not merged');
      expect(c.hasMore, isTrue);
      await c.loadMore();
      expect(c.records.map((r) => r.id), ['2', '4', '5']);
      expect(server.asked.last, (text: 'food', offset: 2));
      expect(c.hasMore, isFalse);
    });

    test('the newest search wins: an older answer landing late is dropped', () async {
      await c.load();
      server.hold['night'] = Completer<void>();
      c.setSearch(const KoolbaseFieldSearch(text: 'night', fields: ['title']));
      await Future<void>.delayed(const Duration(milliseconds: 40));
      c.setSearch(const KoolbaseFieldSearch(text: 'swap', fields: ['title']));
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(c.records.map((r) => r.id), ['1']);
      server.hold['night']!.complete();
      await Future<void>.delayed(Duration.zero);
      expect(c.records.map((r) => r.id), ['1']);
      expect(c.searching, isFalse);
    });

    test('a search the server could not answer says so; the retry answers it', () async {
      await c.load();
      server.failWith = Exception('field_search: field "starts_at" is datetime');
      c.setSearch(const KoolbaseFieldSearch(text: 'food', fields: ['title']));
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(c.searching, isFalse);
      expect(c.searchError, isNotNull);
      server.failWith = null;
      await c.retrySearch();
      expect(c.searchError, isNull);
      expect(c.records.map((r) => r.id), ['2', '4']);
    });

    test('no next page while a search waits; a refresh that answers it ends the wait', () async {
      await c.load();
      c.setSearch(_food);
      await c.loadMore();
      expect(server.asked.where((a) => a.offset > 0), isEmpty, reason: 'not the old list\'s next page');
      expect(c.loadingMore, isFalse);
      // A pull-to-refresh before the pause ends: the search's matches, and
      // the search answered by it once the pending read has run.
      await c.refresh();
      expect(c.records.map((r) => r.id), ['2', '4']);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(c.searching, isFalse);
      expect(c.loadingMore, isFalse);
    });

    test('a search that fails before anything loaded: the list\'s error, not a spinner', () async {
      server.failWith = Exception('down');
      c = KoolbaseCollectionController(
        collection: 'events',
        baseQuery: () => _Query(server),
        searchDelay: const Duration(milliseconds: 20),
      );
      c.setSearch(_food);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(c.status, KoolbaseListStatus.error);
      expect(c.searchError, isNotNull);
    });

    test('refused by the server: the list unsearched for the app to filter; not asked again', () async {
      await c.load();
      server.failWith = const KoolbaseValidationException(
        'field_search: choice "stage": listed must be its declared values, draft, in_progress, done',
      );
      c.setSearch(_food);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(c.searchLoadedOnly, isTrue);
      expect(c.searchError, isNull);
      expect(c.searching, isFalse);
      expect(c.records.map((r) => r.id), ['1', '2'], reason: 'the list, unsearched');
      final searched = server.asked.where((a) => a.text != null).length;
      expect(searched, 1);
      c.setSearch(const KoolbaseFieldSearch(text: 'night', fields: ['title']));
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(server.asked.where((a) => a.text != null).length, searched, reason: 'not asked again');
      expect(c.searchLoadedOnly, isTrue);
      c.setSearch(null);
      expect(c.searchLoadedOnly, isFalse);
    });

    test('refused on the first load: read unsearched at once', () async {
      server.failWith = const KoolbaseValidationException('field_search: field "venue" is not declared on this collection');
      c = KoolbaseCollectionController(
        collection: 'events',
        baseQuery: () => _Query(server),
        search: _food,
        searchDelay: const Duration(milliseconds: 20),
      );
      await c.load();
      expect(c.status, KoolbaseListStatus.loaded);
      expect(c.searchLoadedOnly, isTrue);
      expect(c.records.map((r) => r.id), ['1', '2']);
    });

    test('wider than the server takes -- a Choice matching over 100 values: not sent; a narrower one is', () async {
      await c.load();
      final listed = [for (var i = 0; i < 150; i++) 'v$i'];
      final wide = KoolbaseFieldSearch(
        text: 'v',
        fields: const ['title'],
        choices: [KoolbaseChoiceSearch(field: 'stage', values: listed.sublist(0, 101), listed: listed)],
      );
      c.setSearch(wide);
      expect(c.searchLoadedOnly, isTrue);
      expect(c.searching, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(server.asked.where((a) => a.text != null), isEmpty);
      c.setSearch(const KoolbaseFieldSearch(text: 'food', fields: ['title']));
      expect(c.searchLoadedOnly, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(c.records.map((r) => r.id), ['2', '4']);
    });

    test('cleared after a read that failed: the list read again, never a search\'s answer shown as the list', () async {
      await c.load();
      c.setSearch(const KoolbaseFieldSearch(text: 'food', fields: ['title']));
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(c.records.map((r) => r.id), ['2', '4']);
      server.failAll = Exception('offline');
      final listed = [for (var i = 0; i < 150; i++) 'v$i'];
      c.setSearch(KoolbaseFieldSearch(
        text: 'v',
        fields: const ['title'],
        choices: [KoolbaseChoiceSearch(field: 'stage', values: listed.sublist(0, 101), listed: listed)],
      ));
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(c.searchError, isNotNull);
      server.failAll = null;
      c.setSearch(null);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(c.records.map((r) => r.id), ['1', '2']);
      expect(c.searchError, isNull);
    });

    test('refused on Load more: the list unsearched', () async {
      c = KoolbaseCollectionController(
        collection: 'events',
        baseQuery: () => _Query(server),
        search: _food,
        searchDelay: const Duration(milliseconds: 20),
      );
      await c.load();
      expect(c.records.map((r) => r.id), ['2', '4']);
      server.failWith = const KoolbaseValidationException('field_search: field "title" is not declared on this collection');
      await c.loadMore();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(c.searchLoadedOnly, isTrue);
      expect(c.loadingMore, isFalse);
      expect(c.records.map((r) => r.id), ['1', '2']);
    });

    test('cleared: the list unsearched again; the same search again does nothing', () async {
      c = KoolbaseCollectionController(
        collection: 'events',
        baseQuery: () => _Query(server),
        search: _food,
        searchDelay: const Duration(milliseconds: 20),
      );
      await c.load();
      expect(c.records.map((r) => r.id), ['2', '4']);
      final asked = server.asked.length;
      c.setSearch(_food);
      expect(c.searching, isFalse);
      expect(server.asked.length, asked);
      c.setSearch(null);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(c.records.map((r) => r.id), ['1', '2']);
    });
  });

  testWidgets('the list: a preview under a progress bar, then the answer; no "empty" before it', (tester) async {
    final server = _Server([_rec('1', 'Book swap'), _rec('2', 'Food truck rally')]);
    // One controller across rebuilds, as the widget keeps it.
    final controller = KoolbaseCollectionController(
      collection: 'events',
      baseQuery: () => _Query(server),
      searchDelay: const Duration(milliseconds: 200),
    );
    Widget appWith(KoolbaseFieldSearch? s) => MaterialApp(
          home: Scaffold(
            body: KoolbaseCollectionList(
              collection: 'events',
              controller: controller,
              search: s,
              visible: (loaded) => s == null
                  ? loaded
                  : [
                      for (final r in loaded)
                        if ('${r.data['title']}'.toLowerCase().contains(s.text)) r,
                    ],
              empty: (_) => const Text('No events'),
              loading: (_) => const Text('Searching'),
              itemBuilder: (_, r) => Text('${r.data['title']}'),
            ),
          ),
        );
    await tester.pumpWidget(appWith(null));
    await tester.pump();
    expect(find.text('Book swap'), findsOneWidget);

    await tester.pumpWidget(appWith(const KoolbaseFieldSearch(text: 'food', fields: ['title'])));
    await tester.pump();
    expect(find.text('Food truck rally'), findsOneWidget, reason: 'the preview');
    expect(find.text('Book swap'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    await tester.pumpWidget(appWith(const KoolbaseFieldSearch(text: 'zzz', fields: ['title'])));
    await tester.pump();
    expect(find.text('Searching'), findsOneWidget, reason: 'nothing loaded matching is not "no results"');
    expect(find.text('No events'), findsNothing);

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(find.text('No events'), findsOneWidget, reason: "the server's answer: none");
    expect(find.byType(LinearProgressIndicator), findsNothing);
    controller.dispose();
  });

  testWidgets('a search the server could not answer, or refused: the matches among those loaded, said -- never the error slot', (tester) async {
    final server = _Server([_rec('1', 'Book swap'), _rec('2', 'Food truck rally')]);
    final controller = KoolbaseCollectionController(
      collection: 'events',
      baseQuery: () => _Query(server),
      searchDelay: const Duration(milliseconds: 20),
    );
    Widget appWith(KoolbaseFieldSearch? s) => MaterialApp(
          home: Scaffold(
            body: KoolbaseCollectionList(
              collection: 'events',
              controller: controller,
              search: s,
              visible: (loaded) => s == null
                  ? loaded
                  : [
                      for (final r in loaded)
                        if ('${r.data['title']}'.toLowerCase().contains(s.text)) r,
                    ],
              error: (_, __, ___) => const Text('Error slot'),
              itemBuilder: (_, r) => Text('${r.data['title']}'),
            ),
          ),
        );
    await tester.pumpWidget(appWith(null));
    await tester.pump();
    server.failWith = Exception('offline');
    await tester.pumpWidget(appWith(const KoolbaseFieldSearch(text: 'food', fields: ['title'])));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump();
    expect(find.text('Food truck rally'), findsOneWidget);
    expect(find.textContaining("Couldn't search all records."), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Error slot'), findsNothing);
    // Refused: the same, with nothing to retry.
    server.failWith = const KoolbaseValidationException('field_search: field "title" is not declared on this collection');
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump();
    expect(find.text('Food truck rally'), findsOneWidget);
    expect(find.text('Showing matches among the records loaded.'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
    controller.dispose();
  });
}
