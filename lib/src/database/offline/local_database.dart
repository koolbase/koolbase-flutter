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
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

// ─── Database ──────────────────────────────────────────────────────────────

@DriftDatabase(tables: [CachedQueries, CachedRecords, PendingWrites])
class KoolbaseLocalDatabase extends _$KoolbaseLocalDatabase {
  KoolbaseLocalDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 3;

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
        },
      );

  static QueryExecutor _openConnection() {
    return driftDatabase(name: 'koolbase_offline');
  }
}
