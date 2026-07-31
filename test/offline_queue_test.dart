import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koolbase_flutter/koolbase_flutter.dart';
import 'package:koolbase_flutter/src/database/offline/local_database.dart';
import 'package:koolbase_flutter/src/database/offline/write_queue.dart';

void main() {
  late KoolbaseLocalDatabase db;
  late WriteQueue queue;

  setUp(() {
    db = KoolbaseLocalDatabase.withExecutor(NativeDatabase.memory());
    queue = WriteQueue(db);
  });

  tearDown(() => db.close());

  group('baseline', () {
    // Insert-then-correct is the ordinary offline sequence: log a reading, spot
    // the mistake, fix it. The correction's baseline is the insert's result, not
    // the server's — the record does not exist server-side yet.
    test('a queued insert supplies the baseline for a later edit', () async {
      await queue.enqueue(
        collection: 'weights',
        operation: 'insert',
        payload: {'kg': 68.0, 'note': 'morning'},
        recordId: 'rec-1',
        userId: 'u1',
      );

      final projected = await queue.projectedState('rec-1');
      expect(projected, isNotNull);
      expect(projected!['kg'], 68.0);
      expect(projected['note'], 'morning');
    });

    // A patch merges: fields the update does not mention survive, matching how
    // the server applies one.
    test('chained updates project forward, keeping untouched fields', () async {
      await queue.enqueue(
          collection: 'weights',
          operation: 'insert',
          payload: {'kg': 68.0, 'note': 'morning'},
          recordId: 'rec-1');
      await queue.enqueue(
          collection: 'weights',
          operation: 'update',
          payload: {'kg': 68.4},
          recordId: 'rec-1');

      final projected = await queue.projectedState('rec-1');
      expect(projected!['kg'], 68.4, reason: 'the later write wins');
      expect(projected['note'], 'morning', reason: 'an unmentioned field survives');
    });

    // Editing a record the client has already deleted locally is a contradiction
    // in the SDK's own state, not a conflict to resolve against the server.
    test('a chain ending in delete leaves no baseline', () async {
      await queue.enqueue(
          collection: 'weights',
          operation: 'insert',
          payload: {'kg': 68.0},
          recordId: 'rec-1');
      await queue.enqueue(
          collection: 'weights', operation: 'delete', payload: {}, recordId: 'rec-1');

      expect(await queue.projectedState('rec-1'), isNull);
    });

    test('an unknown record has no baseline', () async {
      expect(await queue.projectedState('never-seen'), isNull);
    });
  });

  group('conflict', () {
    // A conflict is not a failed write to retry. Left in the queue the retry
    // counter would discard it after three passes, which is the silent loss the
    // whole mechanism exists to prevent.
    test('moves the write out of the queue into durable state', () async {
      final id = await queue.enqueue(
        collection: 'weights',
        operation: 'update',
        payload: {'kg': 70.0},
        recordId: 'rec-1',
        userId: 'u1',
        baseline: {'kg': 68.0},
        baseRevision: 3,
      );
      final write = (await queue.pendingForRecord('rec-1')).single;
      expect(write.id, id);

      await queue.moveToConflict(
        write,
        const KoolbaseRevisionMismatchException(
          'the record has changed since you read it',
          expectedRevision: 3,
          currentRevision: 5,
          currentRecord: {'kg': 69.2, r'$revision': 5},
        ),
      );

      expect(await queue.pendingForRecord('rec-1'), isEmpty,
          reason: 'a conflicted write must not stay queued and be retried');

      final conflicts = await queue.conflicts();
      expect(conflicts, hasLength(1));
      expect(conflicts.single.recordId, 'rec-1');
      expect(conflicts.single.baseRevision, 3);
      expect(conflicts.single.serverRevision, 5);
      expect(conflicts.single.serverState, contains('69.2'),
          reason: 'resolving must not need a second fetch');
      expect(conflicts.single.userId, 'u1');
    });

    // Closing an app must not change the outcome of a write.
    test('conflicts are read from storage, not held in memory', () async {
      await queue.enqueue(
        collection: 'weights',
        operation: 'update',
        payload: {'kg': 70.0},
        recordId: 'rec-1',
        baseline: {'kg': 68.0},
        baseRevision: 1,
      );
      final write = (await queue.pendingForRecord('rec-1')).single;
      await queue.moveToConflict(write,
          const KoolbaseRevisionMismatchException('changed', currentRevision: 2));

      // A second queue over the same database sees the same conflicts.
      final other = WriteQueue(db);
      expect(await other.conflicts(), hasLength(1));
    });
  });
}
