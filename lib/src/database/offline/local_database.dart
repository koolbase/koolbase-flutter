import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'local_database.g.dart';

// ─── Tables ────────────────────────────────────────────────────────────────

class CachedQueries extends Table {
  TextColumn get key => text()(); // hash(collection + filters + userId)
  TextColumn get response => text()(); // JSON string of QueryResult
  TextColumn get collection => text()(); // for invalidation
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {key};
}

class CachedRecords extends Table {
  TextColumn get id => text()();
  TextColumn get collection => text()();
  TextColumn get data => text()(); // JSON
  TextColumn get userId => text().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class PendingWrites extends Table {
  TextColumn get id => text()();
  TextColumn get collection => text()();
  TextColumn get operation => text()(); // insert | update | delete
  TextColumn get payload => text()(); // JSON
  TextColumn get recordId => text().nullable()(); // for update/delete

  /// The user who made this write.
  ///
  /// The queue is per-device, not per-session: a write made offline can
  /// outlive the session that created it, and be replayed after someone else
  /// has signed in on the same device. Without this, their record would be
  /// written under the new user's identity.
  ///
  /// Nullable because writes queued before schema v3 have no owner recorded.
  /// Those are never replayed — see [SyncEngine.syncPendingWrites].
  TextColumn get userId => text().nullable()();
  /// The record's field values as the client last saw them, for update and
  /// delete.
  ///
  /// Replay compares three ways — this write's change, what was there when it
  /// was composed, and what is on the server now — which is the only way to
  /// tell "nothing else touched it" from "someone changed it while you were
  /// offline". Without it, applying a queued write silently discards whatever
  /// happened in between.
  ///
  /// Null for inserts, which have no prior state, and for writes queued before
  /// schema v4.
  TextColumn get baseline => text().nullable()();

  /// The record revision the write was composed against, sent to the server so
  /// it can refuse the write atomically rather than the client checking first
  /// and hoping nothing lands in the gap.
  IntColumn get baseRevision => integer().nullable()();

  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// A write the server would not apply because the record changed underneath it.
///
/// Durable, and deliberately separate from [PendingWrites]: a conflict is not a
/// failed write to retry, it is unresolved state awaiting a decision. Leaving it
/// in the queue would let the retry counter discard it after three passes, which
/// is the silent loss this whole mechanism exists to prevent.
///
/// Survives restarts. Closing an app must not change the outcome of a write.
class Conflicts extends Table {
  TextColumn get id => text()();
  TextColumn get collection => text()();
  TextColumn get recordId => text()();
  TextColumn get operation => text()(); // update | delete

  /// What the write wanted to apply.
  TextColumn get payload => text()();

  /// What the client saw when it was composed.
  TextColumn get baseline => text().nullable()();

  /// What the server holds now, as returned with the refusal — so resolving does
  /// not need a fetch, and cannot race one.
  TextColumn get serverState => text().nullable()();
  IntColumn get baseRevision => integer().nullable()();
  IntColumn get serverRevision => integer().nullable()();

  TextColumn get userId => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get lastAttemptedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// ─── Database ──────────────────────────────────────────────────────────────

@DriftDatabase(tables: [CachedQueries, CachedRecords, PendingWrites, Conflicts])
class KoolbaseLocalDatabase extends _$KoolbaseLocalDatabase {
  KoolbaseLocalDatabase() : super(_openConnection());

  /// Opens against a caller-supplied executor.
  ///
  /// Exists so the offline layer can be tested: the default constructor opens a
  /// file on the device, which a test cannot do in isolation or discard between
  /// cases. Everything here — queued writes, conflict state, the migrations that
  /// move them between versions — is logic worth testing, and none of it was
  /// reachable while the connection was fixed.
  KoolbaseLocalDatabase.withExecutor(super.executor);

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          // v2: record shape changed to the flat, $-namespaced format.
          // Cached query results hold the old envelope shape and would fail
          // the new KoolbaseRecord.fromJson — clear the read caches so they
          // refetch fresh. Pending offline writes are user data → preserved.
          if (from < 2) {
            await delete(cachedQueries).go();
            await delete(cachedRecords).go();
          }
          // v3: pending writes now record who made them, so a write queued
          // offline is never replayed under a different user's session.
          // Existing rows keep a null owner and are not replayed — see the
          // sync engine. Preserved rather than deleted: they are user data.
          if (from < 3) {
            await m.addColumn(pendingWrites, pendingWrites.userId);
          }
          // v4: queued updates and deletes carry what the client last saw, so
          // replay can tell an untouched record from one someone else changed.
          // Conflicts move out of the queue into durable state rather than
          // failing — the retry counter would otherwise discard them.
          if (from < 4) {
            await m.addColumn(pendingWrites, pendingWrites.baseline);
            await m.addColumn(pendingWrites, pendingWrites.baseRevision);
            await m.createTable(conflicts);
          }
        },
      );

  static QueryExecutor _openConnection() {
    return driftDatabase(name: 'koolbase_offline');
  }
}
