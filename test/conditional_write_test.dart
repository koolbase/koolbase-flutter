import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koolbase_flutter/koolbase_flutter.dart';
import 'package:koolbase_flutter/src/database/database_client.dart';
import 'package:koolbase_flutter/src/database/offline/cache_store.dart';
import 'package:koolbase_flutter/src/database/offline/local_database.dart';
import 'package:koolbase_flutter/src/database/offline/write_queue.dart';

/// update() and delete() are CONDITIONAL BY DEFAULT.
///
/// The rule that matters is the refusal: with no known revision, the write is
/// refused rather than downgraded to unconditional. Falling back would make
/// the guarantee "safe when convenient" -- and it would degrade precisely when
/// the record was never read locally, which is when a concurrent edit is most
/// likely.
void main() {
  late KoolbaseLocalDatabase db;
  late WriteQueue queue;
  late CacheStore cache;
  late KoolbaseDatabaseClient client;

  setUp(() {
    db = KoolbaseLocalDatabase.withExecutor(NativeDatabase.memory());
    queue = WriteQueue(db);
    cache = CacheStore(db);
    client = KoolbaseDatabaseClient(
      baseUrl: 'http://127.0.0.1:9', // unroutable: every request is "offline"
      publicKey: 'pk_test',
      writeQueue: queue,
      cacheStore: cache,
    );
    client.setUserId('u_1');
  });

  tearDown(() => db.close());

  group('no known revision', () {
    test('update refuses rather than writing unconditionally', () async {
      await expectLater(
        client.update(id: 'rec_unknown', data: {'done': true}),
        throwsA(isA<KoolbaseDataException>()),
      );
      expect(await queue.getPending(), isEmpty,
          reason: 'a refused write must not reach the queue');
    });

    test('delete refuses too', () async {
      await expectLater(
        client.delete(id: 'rec_unknown'),
        throwsA(isA<KoolbaseDataException>()),
      );
      expect(await queue.getPending(), isEmpty);
    });

    test('a record cached WITHOUT a revision is still refused', () async {
      // Records cached before revisions existed cannot be mutated safely.
      await cache.saveRecord('rec_old', 'tasks', {'title': 'x'}, 'u_1');
      await expectLater(
        client.update(id: 'rec_old', data: {'done': true}),
        throwsA(isA<KoolbaseDataException>()),
      );
    });
  });

  group('the escape hatches', () {
    test('unconditional update proceeds with no revision at all', () async {
      await cache.saveRecord('rec_1', 'tasks', {'title': 'x'}, 'u_1');
      // Offline, so it queues rather than reaching a server -- the point is
      // that it was ALLOWED to get that far.
      final r = await client.update(
        id: 'rec_1',
        data: {'done': true},
        unconditional: true,
      );
      expect(r.id, 'rec_1');
      final pending = await queue.getPending();
      expect(pending, hasLength(1));
      expect(pending.single.operation, 'update');
      expect(pending.single.recordId, 'rec_1');
      expect(pending.single.baseRevision, isNull,
          reason: 'unconditional means no baseline is carried');
    });

    test('an explicit revision overrides the cached one', () async {
      await cache.saveRecord('rec_2', 'tasks', {'title': 'x'}, 'u_1',
          revision: 7);
      await client.update(
        id: 'rec_2',
        data: {'done': true},
        expectedRevision: 3,
      );
      final pending = await queue.getPending();
      expect(pending.single.baseRevision, 3);
    });
  });

  group('the automatic path', () {
    test('a cached revision protects the write without being asked', () async {
      await cache.saveRecord('rec_3', 'tasks', {'title': 'x'}, 'u_1',
          revision: 11);
      await client.update(id: 'rec_3', data: {'done': true});
      final pending = await queue.getPending();
      expect(pending.single.baseRevision, 11,
          reason: 'safe by default: the caller asked for nothing special');
    });

    test('the collection comes from the cache, not the caller', () async {
      await cache.saveRecord('rec_4', 'invoices', {'total': 1}, 'u_1',
          revision: 2);
      await client.update(id: 'rec_4', data: {'total': 2});
      final pending = await queue.getPending();
      expect(pending.single.collection, 'invoices',
          reason: 'a record reference carries only an id; the caller should '
              'not have to know its collection');
    });

    test('an offline update leaves optimistic local state', () async {
      await cache.saveRecord('rec_5', 'tasks', {'title': 'x', 'done': false},
          'u_1', revision: 4);
      await client.update(id: 'rec_5', data: {'done': true});
      final local = await cache.getRecord('rec_5');
      expect(local, {'title': 'x', 'done': true},
          reason: 'the changed fields over what was cached');
      expect(await cache.revisionFor('rec_5'), 4,
          reason: 'the baseline must NOT advance -- the server has not seen '
              'this yet, and replay still needs what it was composed against');
    });

    test('an offline delete removes the record locally', () async {
      await cache.saveRecord('rec_6', 'tasks', {'title': 'x'}, 'u_1',
          revision: 1);
      await client.delete(id: 'rec_6');
      expect(await cache.getRecord('rec_6'), isNull);
      final pending = await queue.getPending();
      expect(pending.single.operation, 'delete');
      expect(pending.single.baseRevision, 1);
    });
  });
}
