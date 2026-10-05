import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koolbase_flutter/koolbase_flutter.dart';
import 'package:koolbase_flutter/src/database/offline/cache_store.dart';
import 'package:koolbase_flutter/src/database/offline/local_database.dart';
import 'package:koolbase_flutter/src/database/offline/write_queue.dart';
import 'package:koolbase_flutter/src/database/sync_engine.dart';

/// Offline observability (12.18.0): connectivity, live per-user state,
/// saved-first records, and saved lists that follow offline changes.
Future<void> _settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

KoolbaseRecord _rec(String id, Map<String, dynamic> data, {int revision = 1}) =>
    KoolbaseRecord(
      id: id,
      collection: 'songs',
      data: data,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      revision: revision,
    );

void main() {
  group('connectivity', () {
    late Completer<List<ConnectivityResult>> answer;
    late StreamController<List<ConnectivityResult>> events;

    KoolbaseConnectivity make() {
      answer = Completer<List<ConnectivityResult>>();
      events = StreamController<List<ConnectivityResult>>.broadcast();
      return KoolbaseConnectivity(
          check: () => answer.future, changes: events.stream);
    }

    test('unknown until the platform answers, then follows it', () async {
      final c = make()..start();
      expect(c.state, KoolbaseConnectivityState.unknown);
      answer.complete([ConnectivityResult.none]);
      await _settle();
      expect(c.state, KoolbaseConnectivityState.offline);
      events.add([ConnectivityResult.wifi]);
      await _settle();
      expect(c.state, KoolbaseConnectivityState.online);
    });

    test('a change event beats a late first answer', () async {
      final c = make()..start();
      events.add([ConnectivityResult.mobile]);
      await _settle();
      answer.complete([ConnectivityResult.none]);
      await _settle();
      expect(c.state, KoolbaseConnectivityState.online);
    });
  });

  group('offline state', () {
    late KoolbaseLocalDatabase db;
    late WriteQueue queue;
    late CacheStore cache;
    String? user;

    setUp(() {
      db = KoolbaseLocalDatabase.withExecutor(NativeDatabase.memory());
      queue = WriteQueue(db);
      cache = CacheStore(db);
      user = 'u1';
    });

    tearDown(() async {
      debugClearStreamRefreshers();
      await db.close();
    });

    KoolbaseDatabaseClient client() {
      final c = KoolbaseDatabaseClient(
        baseUrl: 'http://127.0.0.1:9', // unroutable: every request is "offline"
        publicKey: 'pk_test',
        cacheStore: cache,
        writeQueue: queue,
      );
      c.setUserId(user);
      c.setSyncEngine(SyncEngine(
        baseUrl: 'http://127.0.0.1:9',
        publicKey: 'pk_test',
        cacheStore: cache,
        writeQueue: queue,
        currentUserId: () => user,
      ));
      return c;
    }

    test('pending writes are read again when the user changes', () async {
      final c = client();
      await queue.enqueue(
          collection: 'songs',
          operation: 'insert',
          payload: {'id': 'r1'},
          recordId: 'r1',
          userId: 'u1');
      final seen = <Object>[];
      final sub = c.watchPendingWrites().listen((w) => seen.add(w.length),
          onError: (Object e) => seen.add('signed out'));
      await _settle();
      expect(seen, [1]);

      user = 'u2';
      c.sessionChanged();
      await _settle();
      expect(seen.last, 0);

      user = null;
      c.sessionChanged();
      await _settle();
      expect(seen.last, 'signed out');
      await sub.cancel();
    });

    test('a second offline edit keeps the fields neither touched', () async {
      await queue.enqueue(
        collection: 'songs',
        operation: 'update',
        payload: {'plays': 2},
        recordId: 'r1',
        userId: 'u1',
        baseline: {'title': 'Accra Nights', 'plays': 1},
        baseRevision: 3,
      );
      expect(await queue.projectedState('r1'),
          {'title': 'Accra Nights', 'plays': 2});
    });

    test('getSaved: the saved copy with queued changes, never the network',
        () async {
      await cache.saveRecord(
          'r1', 'songs', {'title': 'Accra Nights', 'plays': 1}, 'u1',
          revision: 3);
      final c = client();
      final saved = await c.doc('r1').getSaved();
      expect(saved!.data, {'title': 'Accra Nights', 'plays': 1});
      expect(saved.collection, 'songs');
      expect(saved.revision, 3);
      expect(await c.doc('never-seen').getSaved(), isNull);
    });

    test('an offline add, edit and delete update the saved lists in place',
        () async {
      final key = CacheStore.buildKey('songs', const {}, 'u1');
      await cache.saveQuery(key, 'songs', [
        _rec('r1', {'title': 'A'}).toJson(),
        _rec('r2', {'title': 'B'}).toJson(),
      ]);
      await cache.saveRecord('r1', 'songs', {'title': 'A'}, 'u1', revision: 1);
      await cache.saveRecord('r2', 'songs', {'title': 'B'}, 'u1', revision: 1);
      final c = client();

      await c.doc('r1').update({'title': 'A2'});
      await c.doc('r2').delete();
      final added = await c.insert(collection: 'songs', data: {'title': 'C'});

      final list = (await cache.getQuery(key))!;
      expect(list.map((r) => r[r'$id']).toList(), [added.id, 'r1']);
      expect(list[1]['title'], 'A2');
      expect(list.map(KoolbaseRecord.fromJson).length, 2,
          reason: 'saved rows must still read as records');
    });

    test('an open list that cannot reach the server gets the saved copy',
        () async {
      final key = CacheStore.buildKey('songs', const {}, 'u1');
      await cache.saveQuery(key, 'songs', [
        _rec('r1', {'title': 'A'}).toJson()
      ]);
      final c = client();
      final arrivals = <QueryResult>[];
      final sub = c.collection('songs').stream.listen(arrivals.add);
      await _settle();
      await refreshCollectionStreams('songs');
      await _settle();
      expect(arrivals, isNotEmpty);
      expect(arrivals.last.isFromCache, isTrue);
      expect(arrivals.last.records.single.data['title'], 'A');
      await sub.cancel();
    });
  });

  group('saved-first record controller', () {
    final savedCopy = _rec('r1', {'title': 'Saved'}, revision: 3);

    test('offline: the saved copy shows, isSaved stays true', () async {
      final c = KoolbaseRecordController(
        collection: 'songs',
        id: 'r1',
        saved: () async => savedCopy,
        fetch: () async => throw Exception('offline'),
      );
      await c.load();
      expect(c.status, KoolbaseRecordStatus.loaded);
      expect(c.isSaved, isTrue);
      expect(c.record!.data['title'], 'Saved');
    });

    test('online: the server answer replaces it, isSaved false', () async {
      final seen = <bool>[];
      final c = KoolbaseRecordController(
        collection: 'songs',
        id: 'r1',
        saved: () async => savedCopy,
        fetch: () async => _rec('r1', {'title': 'Fresh'}, revision: 4),
      );
      c.addListener(() => seen.add(c.isSaved));
      await c.load();
      expect(seen.first, isTrue);
      expect(c.isSaved, isFalse);
      expect(c.record!.data['title'], 'Fresh');
    });

    test('a saved copy the server says is gone becomes notFound', () async {
      final c = KoolbaseRecordController(
        collection: 'songs',
        id: 'r1',
        saved: () async => savedCopy,
        fetch: () async => throw const KoolbaseNotFoundException(
            'record not found', 'record_not_found'),
      );
      await c.load();
      expect(c.status, KoolbaseRecordStatus.notFound);
      expect(c.isSaved, isFalse);
    });

    test('no saved copy and no network: the error state, not isSaved',
        () async {
      final c = KoolbaseRecordController(
        collection: 'songs',
        id: 'r1',
        saved: () async => null,
        fetch: () async => throw Exception('offline'),
      );
      await c.load();
      expect(c.status, KoolbaseRecordStatus.error);
      expect(c.isSaved, isFalse);
    });
  });
}
