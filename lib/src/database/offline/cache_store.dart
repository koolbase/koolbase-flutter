import 'dart:convert';
import 'package:drift/drift.dart';
import 'local_database.dart';

class CacheStore {
  final KoolbaseLocalDatabase _db;

  CacheStore(this._db);

  // ─── Cache Key ─────────────────────────────────────────────────────────────

  static String buildKey(
    String collection,
    Map<String, dynamic> filters,
    String? userId,
  ) {
    final filtersJson = jsonEncode(filters);
    return '$collection:$filtersJson:${userId ?? 'anon'}';
  }

  // ─── Read ──────────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>?> getQuery(String key) async {
    final row = await (_db.select(_db.cachedQueries)
          ..where((t) => t.key.equals(key)))
        .getSingleOrNull();

    if (row == null) return null;

    try {
      final decoded = jsonDecode(row.response) as List;
      return decoded.cast<Map<String, dynamic>>();
    } catch (_) {
      return null;
    }
  }

  // ─── Write ─────────────────────────────────────────────────────────────────

  Future<void> saveQuery(
    String key,
    String collection,
    List<Map<String, dynamic>> records,
  ) async {
    await _db.into(_db.cachedQueries).insertOnConflictUpdate(
          CachedQueriesCompanion(
            key: Value(key),
            collection: Value(collection),
            response: Value(jsonEncode(records)),
            updatedAt: Value(DateTime.now()),
          ),
        );
  }

  // ─── Invalidate ────────────────────────────────────────────────────────────

  Future<void> invalidateCollection(String collection) async {
    await (_db.delete(_db.cachedQueries)
          ..where((t) => t.collection.equals(collection)))
        .go();
  }

  // ─── Records ───────────────────────────────────────────────────────────────

  Future<void> saveRecord(
    String id,
    String collection,
    Map<String, dynamic> data,
    String? userId,
  ) async {
    await _db.into(_db.cachedRecords).insertOnConflictUpdate(
          CachedRecordsCompanion(
            id: Value(id),
            collection: Value(collection),
            data: Value(jsonEncode(data)),
            userId: Value(userId),
            updatedAt: Value(DateTime.now()),
          ),
        );
  }

  Future<Map<String, dynamic>?> getRecord(String id) async {
    final row = await (_db.select(_db.cachedRecords)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();

    if (row == null) return null;

    try {
      return jsonDecode(row.data) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// A cached record with the collection it belongs to.
  ///
  /// [getRecord] drops the collection, but an offline mutation needs it: a
  /// queued write records which collection it targets, and a record reference
  /// carries only an id. Since an offline update already requires the record to
  /// be cached — that is where its baseline comes from — the same lookup can
  /// supply both, and no API change is needed to ask callers for a collection
  /// they should not have to know.
  Future<({String collection, Map<String, dynamic> data})?> getRecordWithCollection(
      String id) async {
    final row = await (_db.select(_db.cachedRecords)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (row == null) return null;
    try {
      return (
        collection: row.collection,
        data: jsonDecode(row.data) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> deleteRecord(String id) async {
    await (_db.delete(_db.cachedRecords)..where((t) => t.id.equals(id))).go();
  }
}
