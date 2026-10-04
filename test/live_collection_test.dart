import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:koolbase_flutter/koolbase_flutter.dart';

import 'support/fake_query.dart';

/// Live lists: a realtime change in the collection re-reads page one,
/// silently and once per burst; without `live` nothing subscribes; dispose
/// cancels both the subscription and a pending re-read.
void main() {
  late StreamController<QueryResult> refresh;
  late StreamController<Object?> events;
  late List<String> page;
  late int gets;
  late bool cancelled;
  late List<String> subscribed;
  late bool failGets;

  setUp(() {
    refresh = StreamController<QueryResult>.broadcast();
    cancelled = false;
    events = StreamController<Object?>(onCancel: () => cancelled = true);
    page = ['a'];
    gets = 0;
    subscribed = [];
    failGets = false;
  });

  KoolbaseCollectionController controller({bool live = true}) =>
      KoolbaseCollectionController(
        collection: 'expenses',
        live: live,
        baseQuery: () => FakeQuery(
          onGet: () async {
            gets++;
            if (failGets) throw StateError('network down');
            return fakeResult(page);
          },
          refreshController: refresh,
        ),
        liveEvents: (collection) {
          subscribed.add(collection);
          return events.stream;
        },
      );

  Future<void> pastDebounce() =>
      Future<void>.delayed(const Duration(milliseconds: 300));
  List<String> ids(KoolbaseCollectionController c) =>
      [for (final r in c.records) r.id];

  test('a change re-reads page one silently', () async {
    final c = controller();
    final refreshingSeen = <bool>[];
    c.addListener(() => refreshingSeen.add(c.refreshing));
    await c.load();
    expect(subscribed, ['expenses']);

    page = ['a', 'b'];
    events.add(null);
    await pastDebounce();

    expect(ids(c), ['a', 'b']);
    expect(refreshingSeen, isNot(contains(true)),
        reason: 'a live change is not the pull-to-refresh state');
    c.dispose();
  });

  test('a burst of changes is one read', () async {
    final c = controller();
    await c.load();
    final before = gets;

    events
      ..add(null)
      ..add(null)
      ..add(null);
    await pastDebounce();

    expect(gets, before + 1);
    c.dispose();
  });

  test('a list that is not live does not subscribe', () async {
    final c = controller(live: false);
    await c.load();
    expect(subscribed, isEmpty);
    c.dispose();
  });

  test('dispose unsubscribes and cancels a pending re-read', () async {
    final c = controller();
    await c.load();
    final before = gets;

    events.add(null);
    await Future<void>.delayed(Duration.zero);
    c.dispose();
    await pastDebounce();

    expect(cancelled, isTrue);
    expect(gets, before);
  });

  test('a failed live re-read keeps the records', () async {
    final c = controller();
    await c.load();

    failGets = true;
    events.add(null);
    await pastDebounce();

    expect(ids(c), ['a']);
    expect(c.status, KoolbaseListStatus.loaded);
    c.dispose();
  });
}
