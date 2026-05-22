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
  int get schemaVersion => 2;

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
        },
      );

  static QueryExecutor _openConnection() {
    return driftDatabase(name: 'koolbase_offline');
  }
}
