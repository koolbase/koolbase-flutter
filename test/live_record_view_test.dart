import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:koolbase_flutter/src/database/database_models.dart';
import 'package:koolbase_flutter/src/realtime/realtime_models.dart';
import 'package:koolbase_flutter/src/widgets/record_view.dart';

KoolbaseRecord _record(String id, String title) => KoolbaseRecord.fromJson({
      r'$id': id,
      r'$collection': 'songs',
      r'$createdAt': '2026-10-01T00:00:00Z',
      r'$updatedAt': '2026-10-01T00:00:00Z',
      'title': title,
    });

RealtimeEvent _updated(String id) => RealtimeEvent(
      type: RealtimeEventType.recordUpdated,
      payload: {
        'collection': 'songs',
        'record': {r'$id': id, 'title': 'x'},
      },
      timestamp: DateTime.now(),
    );

RealtimeEvent _deleted(String id) => RealtimeEvent(
      type: RealtimeEventType.recordDeleted,
      payload: {'collection': 'songs', 'record_id': id},
      timestamp: DateTime.now(),
    );

Future<void> _pastDebounce() =>
    Future<void>.delayed(const Duration(milliseconds: 300));

void main() {
  late StreamController<RealtimeEvent> events;
  late int reads;
  late String title;

  KoolbaseRecordController controller({bool live = true, String id = 'r1'}) =>
      KoolbaseRecordController(
        collection: 'songs',
        id: id,
        live: live,
        fetch: () async {
          reads++;
          return _record(id, title);
        },
        liveEvents: (_) => events.stream,
      );

  setUp(() {
    events = StreamController<RealtimeEvent>.broadcast();
    reads = 0;
    title = 'Accra Nights';
  });
  tearDown(() => events.close());

  test('a change to this record re-reads it, silently', () async {
    final c = controller();
    final refreshing = <bool>[];
    c.addListener(() => refreshing.add(c.refreshing));
    await c.load();

    title = 'Morning Light';
    events.add(_updated('r1'));
    await _pastDebounce();

    expect(c.record!.data['title'], 'Morning Light');
    expect(reads, 2);
    expect(refreshing, isNot(contains(true)));
    c.dispose();
  });

  test('changes to other records are ignored', () async {
    final c = controller();
    await c.load();

    events
      ..add(_updated('r2'))
      ..add(_deleted('r2'));
    await _pastDebounce();

    expect(reads, 1);
    expect(c.status, KoolbaseRecordStatus.loaded);
    c.dispose();
  });

  test('a burst of changes is one read', () async {
    final c = controller();
    await c.load();

    events
      ..add(_updated('r1'))
      ..add(_updated('r1'))
      ..add(_updated('r1'));
    await _pastDebounce();

    expect(reads, 2);
    c.dispose();
  });

  test('a delete is notFound at once, without a read', () async {
    final c = controller();
    await c.load();

    events.add(_deleted('r1'));
    await Future<void>.delayed(Duration.zero);
    expect(c.status, KoolbaseRecordStatus.notFound);
    expect(c.record, isNull);

    await _pastDebounce();
    expect(reads, 1);
    c.dispose();
  });

  test('a delete drops a re-read still pending', () async {
    final c = controller();
    await c.load();

    events
      ..add(_updated('r1'))
      ..add(_deleted('r1'));
    await _pastDebounce();

    expect(c.status, KoolbaseRecordStatus.notFound);
    expect(reads, 1);
    c.dispose();
  });

  test('not live: no subscription', () async {
    final c = controller(live: false);
    await c.load();
    expect(events.hasListener, isFalse);
    c.dispose();
  });

  test('no id: nothing to follow, so no subscription', () async {
    final c = controller(id: '');
    await c.load();
    expect(c.status, KoolbaseRecordStatus.notFound);
    expect(events.hasListener, isFalse);
    c.dispose();
  });

  test('dispose unsubscribes and cancels a pending re-read', () async {
    final c = controller();
    await c.load();
    expect(events.hasListener, isTrue);

    events.add(_updated('r1'));
    await Future<void>.delayed(Duration.zero);
    c.dispose();
    await _pastDebounce();

    expect(events.hasListener, isFalse);
    expect(reads, 1);
  });
}
