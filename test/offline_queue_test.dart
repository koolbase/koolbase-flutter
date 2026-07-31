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

  group('rebasing', () {
    // A conflict resolved one way leaves the writes behind it composed against a
    // state that never happened. Releasing them unchanged would make each replay
    // against a revision that has moved, turning one disagreement into as many
    // conflicts as the user had queued.
    test('held writes are pointed at the resolved state', () async {
      await queue.enqueue(
        collection: 'weights',
        operation: 'update',
        payload: {'kg': 70.0},
        recordId: 'rec-1',
        baseline: {'kg': 68.0, 'note': 'morning'},
        baseRevision: 3,
      );
      await queue.enqueue(
        collection: 'weights',
        operation: 'update',
        payload: {'note': 'evening'},
        recordId: 'rec-1',
        baseline: {'kg': 70.0, 'note': 'morning'},
        baseRevision: 3,
      );

      // The first conflicts and is resolved by taking the server's version.
      final first = (await queue.pendingForRecord('rec-1')).first;
      await queue.moveToConflict(
        first,
        const KoolbaseRevisionMismatchException('changed',
            currentRevision: 9, currentRecord: {'kg': 69.2, 'note': 'morning'}),
      );
      await queue.rebaseAfterResolution(
          'rec-1', {'kg': 69.2, 'note': 'morning'}, 9);

      final remaining = (await queue.pendingForRecord('rec-1')).single;
      expect(remaining.baseRevision, 9,
          reason: 'a stale revision would conflict on replay');
      expect(remaining.baseline, contains('69.2'),
          reason: 'the baseline must describe the state that actually won');
      expect(remaining.payload, contains('evening'),
          reason: 'the change itself is untouched — only what it builds on moved');
    });

    // Each write in a chain builds on the one before it, so rebasing walks
    // forward rather than pointing them all at the same state.
    test('a chain rebases through its own writes', () async {
      for (final p in [
        {'a': 1},
        {'b': 2},
        {'c': 3}
      ]) {
        await queue.enqueue(
          collection: 'things',
          operation: 'update',
          payload: p,
          recordId: 'rec-2',
          baseline: {'a': 0},
          baseRevision: 1,
        );
      }
      await queue.rebaseAfterResolution('rec-2', {'base': true}, 5);

      final writes = await queue.pendingForRecord('rec-2');
      expect(writes[0].baseline, contains('base'));
      expect(writes[1].baseline, contains('"a":1'),
          reason: 'the second builds on the first');
      expect(writes[2].baseline, contains('"b":2'),
          reason: 'the third builds on the second');
    });

    // The revision a write produces is not known until the server assigns it, so
    // the next write in the chain has to be told.
    test('a landed write advances the revision for those behind it', () async {
      await queue.enqueue(
          collection: 'things',
          operation: 'update',
          payload: {'a': 1},
          recordId: 'rec-3',
          baseRevision: 4);
      await queue.advanceChainRevision('rec-3', 11);

      expect((await queue.pendingForRecord('rec-3')).single.baseRevision, 11);
    });
  });
}
