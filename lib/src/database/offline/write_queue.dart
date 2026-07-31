import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import 'local_database.dart';

const _maxRetries = 3;

class WriteQueue {
  final KoolbaseLocalDatabase _db;
  static const _uuid = Uuid();

  WriteQueue(this._db);

  // ─── Enqueue ───────────────────────────────────────────────────────────────

  Future<String> enqueue({
    required String collection,
    required String operation, // insert | update | delete
    required Map<String, dynamic> payload,
    String? recordId,
    String? userId,
    /// The record's state as the client last saw it, for update and delete.
    ///
    /// Replay compares this against the server's current state to tell an
    /// untouched record from one that moved while the device was offline. A
    /// mutation with no baseline cannot be replayed safely and is refused before
    /// it reaches here.
    Map<String, dynamic>? baseline,

    /// The revision that baseline carried, sent with the replay so the server
    /// refuses the write atomically rather than the client checking first.
    int? baseRevision,
  }) async {
    final id = _uuid.v4();
    await _db.into(_db.pendingWrites).insert(
          PendingWritesCompanion(
            id: Value(id),
            collection: Value(collection),
            operation: Value(operation),
            payload: Value(jsonEncode(payload)),
            userId: Value(userId),
            recordId: Value(recordId),
            baseline: Value(baseline == null ? null : jsonEncode(baseline)),
            baseRevision: Value(baseRevision),
            retryCount: const Value(0),
            createdAt: Value(DateTime.now()),
          ),
        );
    return id;
  }

  // ─── Per-record state ──────────────────────────────────────────────────────

  /// Pending writes for one record, oldest first.
  ///
  /// Needed in two places. Resolving a baseline: a record created offline is not
  /// in the cache as a server record, but its queued insert holds the state a
  /// later edit was composed against — and insert-then-correct is the ordinary
  /// offline sequence. And ordering at replay: writes for one record form a
  /// chain, where each is composed against the one before it rather than against
  /// the server.
  Future<List<PendingWrite>> pendingForRecord(String recordId) {
    return (_db.select(_db.pendingWrites)
          ..where((w) => w.recordId.equals(recordId))
          ..orderBy([(w) => OrderingTerm.asc(w.createdAt)]))
        .get();
  }

  /// The state a record would be in if every queued write for it were applied.
  ///
  /// Returns null when nothing is queued, or when the chain ends in a delete —
  /// a record the client has already removed locally has no state to compose
  /// against, and editing it is a local contradiction rather than a conflict to
  /// resolve later.
  Future<Map<String, dynamic>?> projectedState(String recordId) async {
    final writes = await pendingForRecord(recordId);
    if (writes.isEmpty) return null;

    Map<String, dynamic>? state;
    for (final w in writes) {
      switch (w.operation) {
        case 'insert':
          state = decodePayload(w);
          break;
        case 'update':
          // Merge, matching how the server applies a patch: omitted keys are
          // retained rather than removed.
          state = {...?state, ...decodePayload(w)};
          break;
        case 'delete':
          state = null;
          break;
      }
    }
    return state;
  }

  // ─── Get All ───────────────────────────────────────────────────────────────

  Future<List<PendingWrite>> getPending() async {
    return (_db.select(_db.pendingWrites)
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  // ─── Increment Retry ───────────────────────────────────────────────────────

  Future<void> incrementRetry(String id) async {
    await (_db.update(_db.pendingWrites)..where((t) => t.id.equals(id)))
        .write(PendingWritesCompanion(
      retryCount: Value(
        await _getRetryCount(id) + 1,
      ),
    ));
  }

  // ─── Delete (success or max retries) ──────────────────────────────────────

  Future<void> remove(String id) async {
    await (_db.delete(_db.pendingWrites)..where((t) => t.id.equals(id))).go();
  }

  // ─── Check if should drop ─────────────────────────────────────────────────

  Future<bool> shouldDrop(String id) async {
    return await _getRetryCount(id) >= _maxRetries;
  }

  // ─── Helpers ───────────────────────────────────────────────────────────────

  Future<int> _getRetryCount(String id) async {
    final row = await (_db.select(_db.pendingWrites)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return row?.retryCount ?? 0;
  }

  Map<String, dynamic> decodePayload(PendingWrite write) {
    return jsonDecode(write.payload) as Map<String, dynamic>;
  }
}
