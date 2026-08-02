import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koolbase_flutter/src/database/database_client.dart';
import 'package:koolbase_flutter/src/database/offline/cache_store.dart';
import 'package:koolbase_flutter/src/database/offline/local_database.dart'
    hide PendingWrite;
import 'package:koolbase_flutter/src/database/offline/write_queue.dart';
import 'package:koolbase_flutter/src/database/sync_engine.dart';
import 'package:koolbase_flutter/src/koolbase_exception.dart';

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

    // Sign out: refusal, not a fake zero. (This test originally expected
    // isEmpty here — the device session then proved silent-empty is a lie
    // that hides queued work, and the contract changed to a throw.)
    fakeUser = null;
    expect(client.pendingWrites(), throwsA(isA<KoolbaseUnauthenticatedException>()));

    // A different user sees only their own.
    fakeUser = 'u2';
    final pending = await client.pendingWrites();
    expect(pending, hasLength(1));
    expect(pending[0].recordId, 'rec-3');
  });

  test('signed out, pendingWrites refuses — no answer is not empty', () async {
    await seed();
    fakeUser = null;
    expect(client.pendingWrites(), throwsA(isA<KoolbaseUnauthenticatedException>()));
  });

  test('legacy null-owner writes are not shown signed out', () async {
    // Pre-9.7.0 writes have no recorded owner. A null == null filter would
    // have shown them to nobody-in-particular — worse than a fake zero:
    // someone else's rows. The refusal covers both lies.
    await queue.enqueue(
      collection: 'expenses',
      operation: 'insert',
      payload: {'amount': 1},
      recordId: 'rec-legacy',
      userId: null,
    );
    fakeUser = null;
    expect(client.pendingWrites(), throwsA(isA<KoolbaseUnauthenticatedException>()));
  });

  test('the queue survives a sign-out/sign-in cycle — the device timeline',
      () async {
    await seed();
    expect(await client.pendingWrites(), hasLength(2));
    fakeUser = null;
    expect(client.pendingWrites(), throwsA(isA<KoolbaseUnauthenticatedException>()));
    fakeUser = 'u1';
    expect(await client.pendingWrites(), hasLength(2));
  });

  test('a mid-stream sign-out becomes an error event, not a fake empty',
      () async {
    final events = <Object>[];
    final sub = client.watchPendingWrites().listen(
          (w) => events.add(w.length),
          onError: (Object e) => events.add(e),
        );
    await queue.enqueue(
      collection: 'expenses',
      operation: 'insert',
      payload: {'amount': 10},
      recordId: 'rec-9',
      userId: 'u1',
    );
    await Future<void>.delayed(const Duration(milliseconds: 80));
    fakeUser = null;
    // Any change re-emits; the emission under a dead session must error.
    await queue.enqueue(
      collection: 'expenses',
      operation: 'insert',
      payload: {'amount': 11},
      recordId: 'rec-10',
      userId: 'u1',
    );
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await sub.cancel();
    expect(events.whereType<KoolbaseUnauthenticatedException>(), isNotEmpty);
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
