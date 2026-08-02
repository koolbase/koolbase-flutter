import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koolbase_flutter/src/database/database_client.dart';
import 'package:koolbase_flutter/src/database/offline/cache_store.dart';
import 'package:koolbase_flutter/src/database/offline/local_database.dart'
    hide PendingWrite;
import 'package:koolbase_flutter/src/database/offline/write_queue.dart';
import 'package:koolbase_flutter/src/database/sync_engine.dart';

/// The queue is the same durable state as conflicts, one step earlier: changes
/// the user believes are saved, existing only on this device. conflicts() got
/// a surfacing API with a warning about invisible accumulation; the queue now
/// has the same. Queues are per-user and survive logout by design, so the
/// per-user filter here is the logout warning's foundation — and it must read
/// identity through the sync engine, the same object replay consults, so the
/// two can never disagree.
void main() {
  late KoolbaseLocalDatabase db;
  late WriteQueue queue;
  late KoolbaseDatabaseClient client;
  String? fakeUser;

  setUp(() {
    db = KoolbaseLocalDatabase.withExecutor(NativeDatabase.memory());
    queue = WriteQueue(db);
    client = KoolbaseDatabaseClient(
      baseUrl: 'https://api.test',
      publicKey: 'pk_test',
      writeQueue: queue,
    );
    client.setSyncEngine(SyncEngine(
      baseUrl: 'https://api.test',
      publicKey: 'pk_test',
      cacheStore: CacheStore(db),
      writeQueue: queue,
      currentUserId: () => fakeUser,
    ));
    fakeUser = 'u1';
  });

  tearDown(() => db.close());

  Future<void> seed() async {
    await queue.enqueue(
      collection: 'expenses',
      operation: 'insert',
      payload: {'amount': 50},
      recordId: 'rec-1',
      userId: 'u1',
    );
    await queue.enqueue(
      collection: 'expenses',
      operation: 'delete',
      payload: {},
      recordId: 'rec-2',
      userId: 'u1',
    );
    await queue.enqueue(
      collection: 'expenses',
      operation: 'update',
      payload: {'amount': 99},
      recordId: 'rec-3',
      userId: 'u2',
    );
  }

  test('empty with nothing queued', () async {
    expect(await client.pendingWrites(), isEmpty);
  });

  test('returns the current user\'s writes, oldest first, public fields only',
      () async {
    await seed();
    final pending = await client.pendingWrites();

    expect(pending, hasLength(2));
    expect(pending[0].id, isNotEmpty);
    expect(pending[0].operation, 'insert');
    expect(pending[0].collection, 'expenses');
    expect(pending[0].recordId, 'rec-1');
    expect(pending[0].data, {'amount': 50});
    expect(pending[0].attempts, 0);
    // A delete carries no data: there is nothing the user "changed", only a
    // removal. Exposing its payload would leak replay plumbing.
    expect(pending[1].operation, 'delete');
    expect(pending[1].data, isNull);
  });

  test('identity is read live from the engine — the logout scenario',
      () async {
    await seed();
    expect(await client.pendingWrites(), hasLength(2));

    // Sign out: nothing visible. The writes still exist — they are u1's, held
    // for whenever u1 next signs in on this device.
    fakeUser = null;
    expect(await client.pendingWrites(), isEmpty);

    // A different user sees only their own.
    fakeUser = 'u2';
    final pending = await client.pendingWrites();
    expect(pending, hasLength(1));
    expect(pending[0].recordId, 'rec-3');
  });

  test('watchPendingWrites emits on enqueue', () async {
    final emissions = <int>[];
    final sub = client
        .watchPendingWrites()
        .listen((writes) => emissions.add(writes.length));

    await queue.enqueue(
      collection: 'expenses',
      operation: 'insert',
      payload: {'amount': 10},
      recordId: 'rec-9',
      userId: 'u1',
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await sub.cancel();

    expect(emissions, isNotEmpty);
    expect(emissions.last, 1);
  });
}
