import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../database_exceptions.dart';
import 'local_database.dart';


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

  // ─── Conflicts ─────────────────────────────────────────────────────────────

  /// Moves a refused write out of the queue and into durable conflict state.
  ///
  /// Both halves in one transaction: a write removed without its conflict
  /// recorded is lost, and a conflict recorded without removing the write would
  /// be replayed again on the next pass and refused again.
  ///
  /// The server's current state is stored alongside, exactly as it was returned
  /// with the refusal. Resolving therefore needs no fetch — and cannot race one,
  /// which is the reason the server returns it in the first place.
  Future<void> moveToConflict(
    PendingWrite write,
    KoolbaseRevisionMismatchException mismatch,
  ) async {
    await _db.transaction(() async {
      await _db.into(_db.conflicts).insert(
            ConflictsCompanion.insert(
              id: _uuid.v4(),
              collection: write.collection,
              recordId: write.recordId ?? '',
              operation: write.operation,
              payload: write.payload,
              baseline: Value(write.baseline),
              serverState: Value(mismatch.currentRecord == null
                  ? null
                  : jsonEncode(mismatch.currentRecord)),
              baseRevision: Value(write.baseRevision),
              serverRevision: Value(mismatch.currentRevision),
              reason: const Value('concurrent_modification'),
              userId: Value(write.userId),
              createdAt: DateTime.now(),
              lastAttemptedAt: Value(DateTime.now()),
            ),
          );
      await (_db.delete(_db.pendingWrites)..where((w) => w.id.equals(write.id)))
          .go();
    });
  }

  /// Points the writes still queued for a record at the state it is now in.
  ///
  /// When a conflict is resolved, the writes held behind it carry baselines
  /// describing the state the conflicted write would have produced — a state
  /// that no longer exists, and may never have. Releasing them unchanged would
  /// apply them conditionally against a revision that has moved on, so every one
  /// would conflict in turn: a single disagreement multiplying into as many
  /// conflicts as the user had queued.
  ///
  /// Refreshing the baseline is sufficient here, and only here, because every
  /// operation this API offers is an absolute assignment. A patch says what a
  /// field becomes, not what to do to it, so it means the same thing whatever it
  /// is applied to. **If a relative operation is ever added — an increment, an
  /// array append — this stops being true and the chain must be replayed through
  /// its projected states instead.**
  Future<void> rebaseAfterResolution(
    String recordId,
    Map<String, dynamic> resolvedState,
    int? resolvedRevision,
  ) async {
    final held = await pendingForRecord(recordId);
    if (held.isEmpty) return;

    var state = Map<String, dynamic>.from(resolvedState);
    for (final w in held) {
      await (_db.update(_db.pendingWrites)..where((p) => p.id.equals(w.id)))
          .write(PendingWritesCompanion(
        baseline: Value(jsonEncode(state)),
        baseRevision: Value(resolvedRevision),
      ));
      // Each write in the chain is composed against the one before it, so the
      // next baseline is this write applied to the last.
      if (w.operation == 'update') {
        state = {...state, ...decodePayload(w)};
      } else if (w.operation == 'delete') {
        break; // nothing after a delete has a state to build on
      }
    }
  }

  /// Records the revision a record now carries, for the writes still queued
  /// behind the one that just landed.
  ///
  /// Each write in a chain is composed against the previous one's result, but
  /// the revision that result carries is not known until the server assigns it.
  /// Without this, the second write in any chain would replay against a revision
  /// the first has already superseded and be refused — turning every multi-write
  /// chain into a conflict the user did not cause. False conflicts are worse
  /// than none: they teach people to reach for overwrite.
  Future<void> advanceChainRevision(String recordId, int? revision) async {
    if (revision == null) return;
    await (_db.update(_db.pendingWrites)
          ..where((p) => p.recordId.equals(recordId)))
        .write(PendingWritesCompanion(baseRevision: Value(revision)));
  }

  /// Clears a resolved conflict.
  ///
  /// Called only once a resolving write has been accepted, or when the
  /// application has explicitly chosen the server's version or abandoned the
  /// change. Removing it before a write lands would lose the change if the write
  /// then failed.
  Future<void> removeConflict(String id) async {
    await (_db.delete(_db.conflicts)..where((c) => c.id.equals(id))).go();
  }

  /// Moves a refused write out of the queue and into durable state.
  ///
  /// Same transaction as a conflict, for the same reason: a write removed
  /// without a record of why is lost, and one recorded without being removed
  /// replays and is refused again.
  ///
  /// Distinguished from a conflict by its reason. A record that moved and a
  /// write the server will not accept are different situations, and an app
  /// showing them to someone should say different things.
  Future<void> moveToRejected(PendingWrite write, String message) async {
    await _db.transaction(() async {
      await _db.into(_db.conflicts).insert(
            ConflictsCompanion.insert(
              id: _uuid.v4(),
              collection: write.collection,
              recordId: write.recordId ?? '',
              operation: write.operation,
              payload: write.payload,
              baseline: Value(write.baseline),
              baseRevision: Value(write.baseRevision),
              userId: Value(write.userId),
              reason: const Value('rejected'),
              message: Value(message),
              createdAt: DateTime.now(),
              lastAttemptedAt: Value(DateTime.now()),
            ),
          );
      await (_db.delete(_db.pendingWrites)..where((w) => w.id.equals(write.id)))
          .go();
    });
  }

  /// Every unresolved conflict, oldest first.
  ///
  /// Read from storage rather than held in memory: closing an app must not
  /// change the outcome of a write, and a conflict discarded by a restart is the
  /// silent loss this whole mechanism exists to prevent.
  Future<List<Conflict>> conflicts() {
    return (_db.select(_db.conflicts)
          ..orderBy([(c) => OrderingTerm.asc(c.createdAt)]))
        .get();
  }

  /// Emits the current conflicts and again whenever they change.
  Stream<List<Conflict>> watchConflicts() {
    return (_db.select(_db.conflicts)
          ..orderBy([(c) => OrderingTerm.asc(c.createdAt)]))
        .watch();
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

  /// One queued write, read fresh.
  ///
  /// Replay updates the revision of writes still queued behind one that has
  /// landed, so a list fetched at the start of a pass goes stale as the pass
  /// proceeds.
  Future<PendingWrite?> byId(String id) {
    return (_db.select(_db.pendingWrites)..where((w) => w.id.equals(id)))
        .getSingleOrNull();
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
