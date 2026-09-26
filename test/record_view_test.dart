import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koolbase_flutter/koolbase_flutter.dart';

/// KoolbaseRecordController and KoolbaseRecordView: one record by id, as a
/// scope. Each rule the controller exists for has a test that fails if it
/// regresses; the view's own job -- handing the record to the builder, the
/// slots, and a changed id starting a new load -- has the rest.

KoolbaseRecord _record(
  String id, {
  String collection = 'songs',
  String title = 'Harmattan Blues',
}) =>
    KoolbaseRecord(
      id: id,
      collection: collection,
      createdBy: 'u1',
      data: {'title': title},
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      revision: 1,
    );

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

Widget _titleOf(BuildContext context, KoolbaseRecord song) =>
    Text(song.data['title'] as String);

void main() {
  group('KoolbaseRecordController', () {
    test('loads one record', () async {
      final c = KoolbaseRecordController(
        collection: 'songs',
        id: 'r1',
        fetch: () async => _record('r1'),
      );
      expect(c.status, KoolbaseRecordStatus.loading);
      await c.load();
      expect(c.status, KoolbaseRecordStatus.loaded);
      expect(c.record!.data['title'], 'Harmattan Blues');
    });

    test('a not-found answer is notFound, not an error', () async {
      final c = KoolbaseRecordController(
        collection: 'songs',
        id: 'gone',
        fetch: () async => throw const KoolbaseNotFoundException(
          'record not found',
          'record_not_found',
        ),
      );
      await c.load();
      expect(c.status, KoolbaseRecordStatus.notFound);
      expect(c.error, isNull);
    });

    test('no id is notFound, without a fetch', () async {
      var calls = 0;
      final c = KoolbaseRecordController(
        collection: 'songs',
        id: '',
        fetch: () async {
          calls++;
          return _record('r1');
        },
      );
      await c.load();
      expect(c.status, KoolbaseRecordStatus.notFound);
      expect(calls, 0);
    });

    test('a record from another collection is notFound', () async {
      final c = KoolbaseRecordController(
        collection: 'songs',
        id: 'u1',
        fetch: () async => _record('u1', collection: 'users'),
      );
      await c.load();
      expect(c.status, KoolbaseRecordStatus.notFound);
      expect(c.record, isNull);
    });

    test('a failed first load is the error state', () async {
      final c = KoolbaseRecordController(
        collection: 'songs',
        id: 'r1',
        fetch: () async => throw Exception('offline'),
      );
      await c.load();
      expect(c.status, KoolbaseRecordStatus.error);
      expect(c.error, isNotNull);
    });

    test('a failed refresh keeps the record, and a refresh that finds it '
        'deleted is notFound', () async {
      var mode = 'ok';
      final c = KoolbaseRecordController(
        collection: 'songs',
        id: 'r1',
        fetch: () async {
          if (mode == 'offline') throw Exception('offline');
          if (mode == 'deleted') {
            throw const KoolbaseNotFoundException(
              'record not found',
              'record_not_found',
            );
          }
          return _record('r1');
        },
      );
      await c.load();
      mode = 'offline';
      await c.refresh();
      expect(c.status, KoolbaseRecordStatus.loaded);
      expect(c.record!.data['title'], 'Harmattan Blues');
      expect(c.refreshing, isFalse);
      mode = 'deleted';
      await c.refresh();
      expect(c.status, KoolbaseRecordStatus.notFound);
      expect(c.record, isNull);
    });

    test('a result landing after dispose is dropped', () async {
      final landed = Completer<KoolbaseRecord>();
      final c = KoolbaseRecordController(
        collection: 'songs',
        id: 'r1',
        fetch: () => landed.future,
      );
      var notified = 0;
      c.addListener(() => notified++);
      final loading = c.load();
      c.dispose();
      landed.complete(_record('r1'));
      await loading;
      expect(notified, 0);
      expect(c.status, KoolbaseRecordStatus.loading);
    });
  });

  group('KoolbaseRecordView', () {
    testWidgets('hands the record to the builder; no id shows the not-found default',
        (tester) async {
      await tester.pumpWidget(_host(KoolbaseRecordView(
        collection: 'songs',
        id: 'r1',
        fetch: (id) async => _record(id),
        builder: _titleOf,
      )));
      await tester.pump();
      expect(find.text('Harmattan Blues'), findsOneWidget);

      await tester.pumpWidget(_host(KoolbaseRecordView(
        collection: 'songs',
        id: '',
        fetch: (id) async => _record(id),
        builder: _titleOf,
      )));
      await tester.pump();
      expect(find.text('Not available.'), findsOneWidget);
    });

    testWidgets('a changed id shows the new record, never the old one',
        (tester) async {
      Future<KoolbaseRecord> fetch(String id) async =>
          _record(id, title: id == 'r1' ? 'Accra Nights' : 'Morning Light');
      await tester.pumpWidget(_host(KoolbaseRecordView(
        collection: 'songs',
        id: 'r1',
        fetch: fetch,
        builder: _titleOf,
      )));
      await tester.pump();
      expect(find.text('Accra Nights'), findsOneWidget);

      await tester.pumpWidget(_host(KoolbaseRecordView(
        collection: 'songs',
        id: 'r2',
        fetch: fetch,
        builder: _titleOf,
      )));
      await tester.pump();
      expect(find.text('Morning Light'), findsOneWidget);
      expect(find.text('Accra Nights'), findsNothing);
    });

    testWidgets('the error default retries into the record', (tester) async {
      var calls = 0;
      await tester.pumpWidget(_host(KoolbaseRecordView(
        collection: 'songs',
        id: 'r1',
        fetch: (id) async {
          calls++;
          if (calls == 1) throw Exception('offline');
          return _record(id);
        },
        builder: _titleOf,
      )));
      await tester.pump();
      expect(find.text("Couldn't load this."), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Harmattan Blues'), findsOneWidget);
    });
  });
}
