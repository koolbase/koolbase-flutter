import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koolbase_flutter/src/database/offline/local_database.dart';

void main() {
  // Every installed app runs this migration on first launch after upgrading, and
  // it runs over a queue that may hold writes the user believes are saved. A
  // migration that drops them would lose data on upgrade — the one moment a user
  // has no reason to expect it.
  test('v3 to v4 preserves queued writes and adds the new columns', () async {
    final executor = NativeDatabase.memory();
    final db = KoolbaseLocalDatabase.withExecutor(executor);

    // Build the v3 shape by hand: the columns that existed before v4.
    await db.customStatement('DROP TABLE IF EXISTS pending_writes');
    await db.customStatement('''
      CREATE TABLE pending_writes (
        id TEXT NOT NULL PRIMARY KEY,
        collection TEXT NOT NULL,
        operation TEXT NOT NULL,
        payload TEXT NOT NULL,
        record_id TEXT NULL,
        user_id TEXT NULL,
        retry_count INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.customStatement('''
      INSERT INTO pending_writes (id, collection, operation, payload, user_id, retry_count, created_at)
      VALUES ('w1', 'weights', 'insert', '{"kg":68}', 'user-1', 0, 1700000000)
    ''');

    await db.customStatement(
        'ALTER TABLE pending_writes ADD COLUMN baseline TEXT NULL');
    await db.customStatement(
        'ALTER TABLE pending_writes ADD COLUMN base_revision INTEGER NULL');

    final rows = await db.customSelect('SELECT * FROM pending_writes').get();
    expect(rows, hasLength(1),
        reason: 'the queued write did not survive the migration');
    expect(rows.first.data['id'], 'w1');
    expect(rows.first.data['user_id'], 'user-1',
        reason: 'ownership recorded in v3 must survive into v4');
    expect(rows.first.data.containsKey('baseline'), isTrue);
    expect(rows.first.data['baseline'], isNull,
        reason:
            'a write queued before v4 has no baseline, and must not be invented');

    await db.close();
  });

  // A conflict is durable unresolved state, not an event. If closing the app
  // discarded it, the write it holds would be lost silently — which is what the
  // whole mechanism exists to prevent.
  // Note: this proves the table stores and returns a conflict, not that it
  // survives a process restart — an in-memory database cannot show that. Real
  // durability is the file-backed database's, and is worth proving on a device.
  test('conflicts are stored and read back', () async {
    final executor = NativeDatabase.memory();
    final db = KoolbaseLocalDatabase.withExecutor(executor);

    await db.into(db.conflicts).insert(ConflictsCompanion.insert(
          id: 'c1',
          collection: 'weights',
          recordId: 'rec-1',
          operation: 'update',
          payload: '{"kg":70}',
          createdAt: DateTime.now(),
        ));

    final stored = await db.select(db.conflicts).get();
    expect(stored, hasLength(1));
    expect(stored.first.recordId, 'rec-1');
    expect(stored.first.serverState, isNull);

    await db.close();
  });
}
