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

  /// Drops cached query results for a collection.
  ///
  /// Deliberately leaves [cachedRecords] alone. An invalidated query means the
  /// membership or ordering of a result set is no longer trustworthy — not that
  /// the SDK has never seen the records in it. Clearing them would remove the
  /// baselines that make offline mutation possible, and since invalidation runs
  /// after every write, a user's own edit would take away their ability to make
  /// the next one offline.
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
    String? userId, {
    int? revision,
  }) async {
    await _db.into(_db.cachedRecords).insertOnConflictUpdate(
          CachedRecordsCompanion(
            id: Value(id),
            collection: Value(collection),
            data: Value(jsonEncode(data)),
            userId: Value(userId),
            revision: Value(revision),
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
  Future<({String collection, Map<String, dynamic> data})?>
      getRecordWithCollection(String id) async {
    final row = await (_db.select(_db.cachedRecords)
          ..where((t) => t.id.equals(id)))
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

  /// Records every record a query returned, so anything the user has seen can be
  /// mutated offline.
  ///
  /// The query cache answers "what did this query return"; the record cache
  /// answers "what is the latest copy of this record the SDK has seen". A
  /// baseline belongs to the second, and scanning query blobs for one would mean
  /// the same record appearing in several snapshots at different revisions with
  /// no principled way to choose.
  ///
  /// An older response must not overwrite a newer copy: query results can arrive
  /// out of order, and rolling a record backwards would compose a mutation
  /// against a stale revision, producing a conflict the user never caused. False
  /// conflicts train people to force-overwrite, which is worse than none.
  Future<void> cacheRecordsFromQuery(
    String collection,
    List<Map<String, dynamic>> records,
    String? userId,
  ) async {
    for (final json in records) {
      final id = json[r'$id'] as String?;
      if (id == null) continue;
      final incoming = (json[r'$revision'] as num?)?.toInt();

      final existing = await (_db.select(_db.cachedRecords)
            ..where((t) => t.id.equals(id)))
          .getSingleOrNull();

      // Unrevisioned records cannot be ordered against each other, so the newer
      // write wins by arrival — they are not eligible for offline mutation
      // anyway.
      if (existing != null && existing.revision != null && incoming != null) {
        if (incoming < existing.revision!) continue;
      }

      final fields = <String, dynamic>{};
      for (final e in json.entries) {
        if (!e.key.startsWith(r'$')) fields[e.key] = e.value;
      }
      await saveRecord(id, collection, fields, userId, revision: incoming);
    }
  }

  /// The revision a cached record was read at.
  ///
  /// Kept separate from the record's fields: it is metadata about when the copy
  /// was taken, not part of the record. An offline mutation sends it so the
  /// server can refuse the write if anything has moved since.
  ///
  /// Null for records cached before revisions existed — those cannot be mutated
  /// offline, and the baseline rules refuse rather than replay blindly.
  Future<int?> revisionFor(String id) async {
    final row = await (_db.select(_db.cachedRecords)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return row?.revision;
  }

  Future<void> deleteRecord(String id) async {
    await (_db.delete(_db.cachedRecords)..where((t) => t.id.equals(id))).go();
  }

  /// Puts a record made offline at the top of every cached result of
  /// [collection], so saved lists show it (filters and order are the server's
  /// to apply when it next answers).
  Future<void> addToQueries(
      String collection, Map<String, dynamic> json) async {
    final rows = await (_db.select(_db.cachedQueries)
          ..where((t) => t.collection.equals(collection)))
        .get();
    for (final row in rows) {
      final List<dynamic> list;
      try {
        list = jsonDecode(row.response) as List<dynamic>;
      } catch (_) {
        continue;
      }
      await (_db.update(_db.cachedQueries)..where((t) => t.key.equals(row.key)))
          .write(CachedQueriesCompanion(
              response: Value(jsonEncode([json, ...list]))));
    }
  }

  /// Applies an offline edit to the record wherever a cached result holds it.
  Future<void> updateInQueries(
      String collection, String recordId, Map<String, dynamic> data) async {
    final rows = await (_db.select(_db.cachedQueries)
          ..where((t) => t.collection.equals(collection)))
        .get();
    for (final row in rows) {
      final List<dynamic> list;
      try {
        list = jsonDecode(row.response) as List<dynamic>;
      } catch (_) {
        continue;
      }
      var changed = false;
      final next = [
        for (final r in list)
          if (r is Map && r[r'$id'] == recordId)
            (() {
              changed = true;
              return {...r, ...data};
            })()
          else
            r,
      ];
      if (!changed) continue;
      await (_db.update(_db.cachedQueries)..where((t) => t.key.equals(row.key)))
          .write(CachedQueriesCompanion(response: Value(jsonEncode(next))));
    }
  }

  /// Takes one record out of every cached result of [collection].
  ///
  /// Precise on purpose: [invalidateCollection] would also get rid of it, by
  /// dropping every saved list of the collection -- leaving a device that is
  /// still offline with nothing to show, to remove one record.
  Future<void> removeFromQueries(String collection, String recordId) async {
    final rows = await (_db.select(_db.cachedQueries)
          ..where((t) => t.collection.equals(collection)))
        .get();
    for (final row in rows) {
      final List<dynamic> list;
      try {
        list = jsonDecode(row.response) as List<dynamic>;
      } catch (_) {
        continue;
      }
      final kept = [
        for (final r in list)
          if (!(r is Map && (r[r'$id'] == recordId || r['id'] == recordId))) r,
      ];
      if (kept.length == list.length) continue;
      await (_db.update(_db.cachedQueries)..where((t) => t.key.equals(row.key)))
          .write(CachedQueriesCompanion(response: Value(jsonEncode(kept))));
    }
  }
}
