import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koolbase_flutter/koolbase_flutter.dart';
import 'package:koolbase_flutter/src/database/database_client.dart';
import 'package:koolbase_flutter/src/database/offline/local_database.dart';
import 'package:koolbase_flutter/src/database/offline/write_queue.dart';

/// Signed out and offline, a write must REFUSE — never enqueue.
///
/// Found on device: a ticket parked while the SDK session was dead was
/// enqueued under userId null. Every per-user surface then correctly refused
/// or filtered (pendingWrites throws signed-out; replay and reads filter
/// r.userId == currentUser) — so the null-owner row matched nothing, forever:
/// physically present, invisible, unreplayable. The write didn't fail loudly
/// or succeed; it vanished into a bucket nobody owns. Refusal at enqueue is
/// the only honest response, and it mirrors the RN SDK's fix of the same bug.
void main() {
  late KoolbaseLocalDatabase db;
  late WriteQueue queue;
  late KoolbaseDatabaseClient client;

  setUp(() {
    db = KoolbaseLocalDatabase.withExecutor(NativeDatabase.memory());
    queue = WriteQueue(db);
    client = KoolbaseDatabaseClient(
      baseUrl: 'http://127.0.0.1:9', // unroutable: every request is "offline"
      publicKey: 'pk_test',
      writeQueue: queue,
    );
    client.setUserId(null); // signed out
  });

  tearDown(() => db.close());

  test('signed-out offline insert refuses — and writes to NO bucket', () async {
    await expectLater(
      client.insert(collection: 'tickets', data: {'name': 'ghost'}),
      throwsA(isA<KoolbaseUnauthenticatedException>()),
    );
    expect(await queue.getPending(), isEmpty,
        reason: 'a refused write must leave the queue untouched — '
            'an orphaned null-owner row is the exact bug this pins');
  });

  test('signed-in offline insert still queues (guard must not overreach)',
      () async {
    client.setUserId('u1');
    final rec =
        await client.insert(collection: 'tickets', data: {'name': 'kept'});
    expect(rec.id, isNotEmpty, reason: 'optimistic record returned');
    final pending = await queue.getPending();
    expect(pending.length, 1);
    expect(pending.single.userId, 'u1',
        reason: 'the queued write must carry its owner');
  });
}
