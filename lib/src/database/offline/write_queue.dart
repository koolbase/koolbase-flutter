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
            retryCount: const Value(0),
            createdAt: Value(DateTime.now()),
          ),
        );
    return id;
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
