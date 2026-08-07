import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'database_models.dart';
import 'database_query.dart';
import 'conflict.dart';
import 'offline/cache_store.dart';
import 'offline/local_database.dart' show Conflict;
import 'offline/local_database.dart' as drift_rows show PendingWrite;
import 'pending_write.dart';
import 'sync_engine.dart';
import 'offline/write_queue.dart';
import 'database_exceptions.dart';
import '../koolbase_exception.dart';

class KoolbaseDatabaseClient {
  final String baseUrl;
  final String publicKey;
  String? _userId;
  final Future<String?> Function()? _accessTokenProvider;

  /// Called when the server rejects the session token itself.
  ///
  /// A session the server will not honour is not a session: leaving it in
  /// place produces an app that believes it is authenticated and fails every
  /// request, with no path back to login. The auth client clears it, so by the
  /// time [KoolbaseSessionExpiredException] reaches the caller the user is
  /// already signed out and the app can route accordingly.
  final Future<void> Function()? _onSessionExpired;
  CacheStore? _cacheStore;
  WriteQueue? _writeQueue;
  SyncEngine? _syncEngine;
  static const _uuid = Uuid();

  /// Injectable for tests; a real client otherwise. Only the conflict
  /// resolution path uses it so far — the bare http.* calls elsewhere migrate
  /// opportunistically. An unmockable resolution path is why the
  /// refusal-never-teaches bug had no test to catch it.
  final http.Client _http;

  KoolbaseDatabaseClient({
    required this.baseUrl,
    required this.publicKey,
    http.Client? httpClient,
    Future<String?> Function()? accessTokenProvider,
    Future<void> Function()? onSessionExpired,
    CacheStore? cacheStore,
    WriteQueue? writeQueue,
  })  : _http = httpClient ?? http.Client(),
        _accessTokenProvider = accessTokenProvider,
        _onSessionExpired = onSessionExpired,
        _cacheStore = cacheStore,
        _writeQueue = writeQueue;

  /// Set the user id used to tag locally-cached records (offline owner
  /// metadata only). NOT the auth mechanism — request identity comes from the
  /// verified access token via [_accessTokenProvider].
  void setUserId(String? userId) => _userId = userId;

  /// Wires the sync engine used by [syncPendingWrites].
  ///
  /// Set after construction because the engine and this client share a cache
  /// store and write queue, so one has to be built first and handed to the
  /// other.
  void setSyncEngine(SyncEngine engine) => _syncEngine = engine;

  void setOfflineSupport({
    required CacheStore cacheStore,
    required WriteQueue writeQueue,
  }) {
    _cacheStore = cacheStore;
    _writeQueue = writeQueue;
  }

  Future<Map<String, String>> _headers() async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'x-api-key': publicKey,
    };
    final token = await _accessTokenProvider?.call();
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  /// Unresolved conflicts, oldest first.
  ///
  /// A conflict is a change the user made that the server would not apply,
  /// because the record moved in between. It is held rather than discarded, and
  /// survives restarts, until the application decides what should win.
  Future<List<KoolbaseConflict>> conflicts() async {
    final rows = await _writeQueue?.conflicts() ?? const [];
    return rows.map(_mapConflict).toList();
  }

  /// Emits the current conflicts, and again whenever they change.
  Stream<List<KoolbaseConflict>> watchConflicts() {
    final queue = _writeQueue;
    if (queue == null) return Stream.value(const []);
    return queue
        .watchConflicts()
        .map((rows) => rows.map(_mapConflict).toList());
  }

  /// Changes made offline, waiting to be sent. Oldest first.
  ///
  /// For sync indicators ("3 changes waiting") and for warning a user who is
  /// about to log out with unsynced edits — see [PendingWrite] for why that
  /// moment matters. Snapshot; per-user. [watchPendingWrites] is the live
  /// version.
  Future<List<PendingWrite>> pendingWrites() async {
    final queue = _writeQueue;
    if (queue == null) return const [];
    // The same identity replay consults, read from the same object — the
    // filter here must not be able to drift from the skip at replay.
    final currentUser = _syncEngine?.currentUserId?.call();
    // Signed out, per-user state has no answer — and a null filter would not
    // even be empty: it matches legacy null-owner writes. "No user" must be a
    // refusal, never a fake zero (or worse, someone else's rows). Found on
    // device: a signed-out display showed 0 while a user's writes sat queued.
    if (currentUser == null) {
      throw const KoolbaseUnauthenticatedException(
        'Signed out — pending writes are per-user state.',
      );
    }
    final rows = await queue.getPending();
    return [
      for (final r in rows)
        if (r.userId == currentUser) _mapPending(r),
    ];
  }

  /// Emits the pending writes, and again whenever they change.
  ///
  /// For a sync badge that reflects reality. Per-user, like [pendingWrites].
  Stream<List<PendingWrite>> watchPendingWrites() {
    final queue = _writeQueue;
    if (queue == null) return Stream.value(const []);
    return queue.watchPending().map((rows) {
      // Read per emission: the signed-in user can change under a live stream —
      // and a sign-out mid-stream becomes an error event, not a fake-empty
      // emission. The badge stops lying the moment the session dies.
      final currentUser = _syncEngine?.currentUserId?.call();
      if (currentUser == null) {
        throw const KoolbaseUnauthenticatedException(
          'Signed out — pending writes are per-user state.',
        );
      }
      return [
        for (final r in rows)
          if (r.userId == currentUser) _mapPending(r),
      ];
    });
  }

  /// Named fields, deliberately not the row: baseline, baseRevision, and the
  /// raw payload are replay mechanics, and naming each public field keeps new
  /// internals internal until someone chooses otherwise.
  PendingWrite _mapPending(drift_rows.PendingWrite row) => PendingWrite(
        id: row.id,
        operation: row.operation,
        collection: row.collection,
        recordId: row.recordId,
        data:
            row.operation == 'delete' ? null : _writeQueue?.decodePayload(row),
        enqueuedAt: row.createdAt,
        attempts: row.retryCount,
      );

  KoolbaseConflict _mapConflict(Conflict row) => KoolbaseConflict(
        id: row.id,
        collection: row.collection,
        recordId: row.recordId,
        operation: switch (row.operation) {
          'insert' => ConflictOperation.insert,
          'delete' => ConflictOperation.delete,
          _ => ConflictOperation.update,
        },
        // A null reason predates the distinction. Those were all concurrent
        // modifications, since a refusal used to be retried until dropped
        // rather than held — but it is recorded as unknown rather than
        // asserting something about rows written before anyone was tracking it.
        reason: switch (row.reason) {
          'concurrent_modification' => ConflictReason.concurrentModification,
          'rejected' => ConflictReason.rejected,
          _ => ConflictReason.unknown,
        },
        message: row.message,
        baseline: _decodeOrNull(row.baseline),
        local: _decodeOrNull(row.payload),
        server: _decodeOrNull(row.serverState),
        baseRevision: row.baseRevision,
        serverRevision: row.serverRevision,
        createdAt: row.createdAt,
        resolver: _conflictResolver,
      );

  Map<String, dynamic>? _decodeOrNull(String? raw) =>
      raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;

  Future<Conflict> _requireConflict(String id) async {
    final rows = await _writeQueue?.conflicts() ?? const [];
    for (final r in rows) {
      if (r.id == id) return r;
    }
    throw KoolbaseDataException(
        'That conflict is no longer outstanding — it may already have been resolved.',
        code: 'conflict_not_found');
  }

  /// Issues a resolving write, conditional on the revision the refusal reported.
  ///
  /// Builds its own request rather than going through [doc]: that path resolves
  /// a baseline from the cache and queues on network failure, and a resolution
  /// must send the conflict's own revision and leave the conflict standing if it
  /// cannot be delivered.
  Future<void> _resolveWrite(Conflict row, Map<String, dynamic> payload) async {
    try {
      await _resolveWriteInner(row, payload);
    } on KoolbaseRevisionMismatchException catch (e) {
      // A refusal must teach the stored conflict, not just gate it. Without
      // this, the resolving write stays conditional on the revision the
      // ORIGINAL refusal reported, and a conflict whose resolution fails once
      // is permanently unresolvable except by abandon — every retry replays
      // the stale condition. Device-proven on the RN side; same defect here.
      final current = e.currentRevision;
      if (current != null) {
        await _writeQueue?.refreshConflict(
          row.id,
          serverRevision: current,
          serverState: e.currentRecord,
        );
        throw KoolbaseRevisionMismatchException(
          'The record has changed again while deciding. The conflict now '
          'reflects the server\'s current state — review and retry.',
          expectedRevision: e.expectedRevision,
          currentRevision: current,
          currentRecord: e.currentRecord,
        );
      }
      rethrow;
    }
  }

  Future<void> _resolveWriteInner(
      Conflict row, Map<String, dynamic> payload) async {
    final rev = row.serverRevision;
    final http.Response res;
    if (row.operation == 'insert') {
      // Resolving a rejected insert IS the insert, retried — with amended data
      // via resolveWithMerge (the "fix the colliding title" path).
      // Unconditional: there is no revision to be conditional against, because
      // there is no record. The conflict's id rides as the idempotency key, so
      // a resolution whose response is lost returns the original on retry
      // rather than duplicating. Wire-proven on this exact route.
      res = await _http
          .post(
            Uri.parse('$baseUrl/v1/sdk/db/insert'),
            headers: await _headers(),
            body: jsonEncode({
              'collection': row.collection,
              'data': payload,
              'idempotency_key': row.id,
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200 && res.statusCode != 201) {
        throw await koolbaseDataErrorNotifying(res,
            onSessionExpired: _onSessionExpired,
            fallbackMessage: 'Resolving the conflict failed');
      }
    } else if (row.operation == 'delete') {
      res = await _http
          .delete(
            Uri.parse(
                '$baseUrl/v1/sdk/db/records/${row.recordId}${rev != null ? '?expected_revision=$rev' : ''}'),
            headers: await _headers(),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 204) {
        throw await koolbaseDataErrorNotifying(res,
            onSessionExpired: _onSessionExpired,
            fallbackMessage: 'Resolving the conflict failed');
      }
    } else {
      res = await _http
          .patch(
            Uri.parse('$baseUrl/v1/sdk/db/records/${row.recordId}'),
            headers: await _headers(),
            body: jsonEncode({
              'data': payload,
              if (rev != null) 'expected_revision': rev,
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) {
        throw await koolbaseDataErrorNotifying(res,
            onSessionExpired: _onSessionExpired,
            fallbackMessage: 'Resolving the conflict failed');
      }
    }
    // Only once the server has accepted it. A conflict cleared before the write
    // lands would lose the change if the write then failed.
    await _writeQueue?.removeConflict(row.id);

    // Writes held behind this one were composed against the state it would have
    // produced. That state has now been decided, so point them at it — otherwise
    // each would replay against a revision that has moved and conflict in turn,
    // multiplying one disagreement into as many as the user had queued.
    final applied = _revisionFromResponse(res);
    await _writeQueue?.rebaseAfterResolution(
        row.recordId, payload, applied ?? row.serverRevision);

    await _cacheStore?.invalidateCollection(row.collection);
    unawaited(refreshCollectionStreams(row.collection));
  }

  /// Points writes still queued for a record at the server's version, after a
  /// resolution that discarded the local change.
  ///
  /// Uses the state captured when the write was refused. It may have moved again
  /// since — in which case those writes will conflict when they replay, which is
  /// correct: the disagreement is real and belongs to the user, not invented by
  /// a baseline nobody ever saw.
  Future<void> _rebaseOntoServerState(Conflict row) async {
    final raw = row.serverState;
    if (raw == null) return;
    final state = _decodeOrNull(raw);
    if (state == null) return;
    final fields = <String, dynamic>{};
    for (final e in state.entries) {
      if (!e.key.startsWith(r'$')) fields[e.key] = e.value;
    }
    await _writeQueue?.rebaseAfterResolution(
        row.recordId, fields, row.serverRevision);
  }

  int? _revisionFromResponse(http.Response res) {
    try {
      final body = jsonDecode(res.body);
      if (body is Map<String, dynamic>) {
        return (body[r'$revision'] as num?)?.toInt();
      }
    } catch (_) {}
    return null;
  }

  late final _ConflictResolver _conflictResolver = _ConflictResolver(this);

  /// Get a fluent query builder for a collection
  KoolbaseQuery collection(String name) {
    return KoolbaseQuery(
      baseUrl: baseUrl,
      publicKey: publicKey,
      collectionName: name,
      accessTokenProvider: _accessTokenProvider,
      onSessionExpired: _onSessionExpired,
      userId: _userId,
      cacheStore: _cacheStore,
      writeQueue: _writeQueue,
    );
  }

  /// Get a reference to a specific record by ID
  KoolbaseDocRef doc(String recordId) {
    return KoolbaseDocRef(
      baseUrl: baseUrl,
      publicKey: publicKey,
      recordId: recordId,
      accessTokenProvider: _accessTokenProvider,
      onSessionExpired: _onSessionExpired,
      cacheStore: _cacheStore,
      userId: _userId,
      writeQueue: _writeQueue,
    );
  }

  /// Insert a new record into a collection.
  ///
  /// If the network is unreachable, the write is queued locally and synced
  /// when connectivity is restored (the record is optimistically saved to the
  /// local cache immediately). A server-side rejection (e.g. a unique-
  /// constraint conflict, a validation error, or a permission denial) is NOT a
  /// network failure — it surfaces as the corresponding [KoolbaseDataException]
  /// rather than being queued.
  Future<KoolbaseRecord> insert({
    required String collection,
    required Map<String, dynamic> data,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/v1/sdk/db/insert'),
            headers: await _headers(),
            body: jsonEncode({'collection': collection, 'data': data}),
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode != 201) {
        throw await koolbaseDataErrorNotifying(res,
            onSessionExpired: _onSessionExpired,
            fallbackMessage: 'Insert failed');
      }

      final record =
          KoolbaseRecord.fromJson(jsonDecode(res.body) as Map<String, dynamic>);

      // Save to local cache
      await _cacheStore?.saveRecord(
        record.id,
        collection,
        record.data,
        _userId,
        revision: record.revision,
      );

      // Invalidate collection cache so next query is fresh
      await _cacheStore?.invalidateCollection(collection);

      // And tell open streams. Invalidating the cache only affects the NEXT
      // query — a listener already watching this collection sits unchanged
      // until something happens to re-fetch, which is how a sent message
      // failed to appear in its own thread.
      //
      // Not awaited: a write should not block on refreshing other queries,
      // and a failed refresh is logged rather than surfaced — the write
      // itself succeeded.
      unawaited(refreshCollectionStreams(collection));

      return record;
    } catch (e) {
      // A server-side rejection (4xx → typed KoolbaseDataException) means the
      // server was reachable and refused the write — surface it, never queue.
      if (e is KoolbaseDataException) rethrow;

      // Genuine network/timeout failure — queue the write for later sync.
      if (_writeQueue != null) {
        debugPrint('[Koolbase] Offline insert queued for $collection');
        final tempId = _uuid.v4();

        await _writeQueue!.enqueue(
          collection: collection,
          operation: 'insert',
          payload: data,
          // Recorded so this write is never replayed under a different
          // user's session: the queue outlives the session that filled it.
          userId: _userId,
        );

        // Optimistically save to local cache
        // No revision: the record does not exist on the server yet, so there
        // is nothing to be conditional against. An offline edit to it composes
        // against the queued insert rather than a cached revision.
        await _cacheStore?.saveRecord(tempId, collection, data, _userId);
        await _cacheStore?.invalidateCollection(collection);
        unawaited(refreshCollectionStreams(collection));

        // Return optimistic record
        return KoolbaseRecord(
          id: tempId,
          collection: collection,
          createdBy: _userId,
          data: data,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
      }
      rethrow;
    }
  }

  /// Insert a record, or update the existing one matching [match].
  ///
  /// The server decides the outcome: exactly one match updates that record,
  /// no match inserts a new one (seeded with the [match] fields), and more
  /// than one match is an error. The returned [KoolbaseUpsertResult] carries
  /// the resulting record and a `created` flag (true = inserted, false =
  /// updated).
  ///
  /// Online-only by design. Unlike [insert], an upsert is NOT queued offline:
  /// the insert-vs-update decision needs the server's authoritative view of
  /// what already exists, so deferring it could create a duplicate or apply a
  /// wrong update on later sync. It throws on network failure instead.
  Future<KoolbaseUpsertResult> upsert({
    required String collection,
    required Map<String, dynamic> match,
    required Map<String, dynamic> data,
  }) async {
    final res = await http
        .post(
          Uri.parse('$baseUrl/v1/sdk/db/upsert'),
          headers: await _headers(),
          body: jsonEncode({
            'collection': collection,
            'match': match,
            'data': data,
          }),
        )
        .timeout(const Duration(seconds: 10));

    if (res.statusCode != 200 && res.statusCode != 201) {
      throw await koolbaseDataErrorNotifying(res,
          onSessionExpired: _onSessionExpired,
          fallbackMessage: 'Upsert failed');
    }

    final created = res.statusCode == 201;
    final record =
        KoolbaseRecord.fromJson(jsonDecode(res.body) as Map<String, dynamic>);

    // Keep the local cache consistent, same as insert.
    await _cacheStore?.saveRecord(record.id, collection, record.data, _userId,
        revision: record.revision);
    await _cacheStore?.invalidateCollection(collection);
    unawaited(refreshCollectionStreams(collection));

    return KoolbaseUpsertResult(record: record, created: created);
  }

  /// Bulk-delete every record in [collection] matching [filters].
  ///
  /// The server applies the collection's delete rule (scoping to the caller
  /// for owner/scoped rules) and returns the number of records deleted.
  ///
  /// Online-only by design — like [upsert], this is NOT queued offline. A bulk
  /// delete needs the server's authoritative view of what matches, so it throws
  /// on network failure rather than risk deleting the wrong set on later sync.
  /// The local cache for the collection is invalidated on success.
  Future<int> deleteWhere({
    required String collection,
    required Map<String, dynamic> filters,
  }) async {
    final res = await http
        .post(
          Uri.parse('$baseUrl/v1/sdk/db/delete-where'),
          headers: await _headers(),
          body: jsonEncode({'collection': collection, 'filters': filters}),
        )
        .timeout(const Duration(seconds: 10));

    if (res.statusCode != 200) {
      throw await koolbaseDataErrorNotifying(res,
          onSessionExpired: _onSessionExpired,
          fallbackMessage: 'Delete failed');
    }

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final deleted = (body['deleted'] as num?)?.toInt() ?? 0;

    await _cacheStore?.invalidateCollection(collection);
    unawaited(refreshCollectionStreams(collection));

    return deleted;
  }

  /// Run multiple writes as a single atomic transaction.
  ///
  /// All [operations] commit together or none are applied — the server runs
  /// them in one database transaction and rolls back entirely on any failure.
  /// Operations apply in order and may span multiple collections.
  ///
  /// Online-only by design (like [upsert] and [deleteWhere]): atomicity needs
  /// the server's authoritative view, so a batch is never queued offline — it
  /// throws on network failure. A server-side rejection throws a
  /// [KoolbaseDataException] whose message identifies which operation failed;
  /// nothing was persisted.
  ///
  /// Returns one [KoolbaseBatchResult] per operation, in order.
  ///
  /// Example:
  /// ```dart
  /// final results = await Koolbase.db.batch([
  ///   KoolbaseBatchOp.insert('orders', {'total': 50}),
  ///   KoolbaseBatchOp.update(inventoryId, {'stock': 9}),
  ///   KoolbaseBatchOp.upsert('counters', match: {'name': 'orders'}, data: {'value': 1}),
  ///   KoolbaseBatchOp.delete(cartItemId),
  /// ]);
  /// ```
  Future<List<KoolbaseBatchResult>> batch(
      List<KoolbaseBatchOp> operations) async {
    if (operations.isEmpty) {
      throw ArgumentError('batch requires at least one operation');
    }

    final res = await http
        .post(
          Uri.parse('$baseUrl/v1/sdk/db/batch'),
          headers: await _headers(),
          body: jsonEncode({
            'operations': operations.map((o) => o.toJson()).toList(),
          }),
        )
        .timeout(const Duration(seconds: 15));

    if (res.statusCode != 200) {
      throw await koolbaseDataErrorNotifying(res,
          onSessionExpired: _onSessionExpired, fallbackMessage: 'Batch failed');
    }

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final results = (body['results'] as List<dynamic>? ?? [])
        .map((r) => KoolbaseBatchResult.fromJson(r as Map<String, dynamic>))
        .toList();

    // Keep the local cache consistent with what committed: save each written
    // record and invalidate its collection so the next query is fresh.
    for (final r in results) {
      final rec = r.record;
      final col = rec?.collection;
      if (rec != null && col != null) {
        await _cacheStore?.saveRecord(rec.id, col, rec.data, _userId,
            revision: rec.revision);
        await _cacheStore?.invalidateCollection(col);
        unawaited(refreshCollectionStreams(col));
      }
    }

    return results;
  }

  /// Manually sync all pending offline writes to the server.
  ///
  /// This is called automatically when the network is restored.
  /// You can also call it manually at any point.
  ///
  /// Example:
  /// ```dart
  /// await Koolbase.db.syncPendingWrites();
  /// ```
  Future<void> syncPendingWrites() async {
    // Delegates rather than duplicating. This method and SyncEngine were two
    // independent implementations of the same drain, and they had already
    // drifted: one discarded a malformed write, the other retained it forever,
    // and a fix applied to one silently missed the other. One implementation,
    // two entry points — automatic on reconnect, and this, for a "sync now"
    // affordance an app may want in poor connectivity.
    final engine = _syncEngine;
    if (engine == null) {
      debugPrint('[Koolbase] No sync engine configured; nothing to sync');
      return;
    }
    await engine.syncPendingWrites();
  }
}

// ─── Conflicts ───────────────────────────────────────────────────────────────

/// Resolves conflicts on behalf of [KoolbaseConflict], reloading the stored row
/// before acting.
///
/// A conflict object handed to a UI can sit there while someone decides, and a
/// sync pass may resolve it or another write supersede it meanwhile. Acting on
/// values captured when the object was built would write against a state that no
/// longer exists.
class _ConflictResolver implements ConflictResolver {
  _ConflictResolver(this._client);

  final KoolbaseDatabaseClient _client;

  @override
  Future<void> resolveWithLocal(String conflictId) async {
    final row = await _client._requireConflict(conflictId);
    final payload = jsonDecode(row.payload) as Map<String, dynamic>;
    // Conditional on the revision the refusal reported. If the record has moved
    // again while someone was deciding, this is refused in turn rather than
    // overwriting a change nobody has seen.
    await _client._resolveWrite(row, payload);
  }

  @override
  Future<void> resolveWithMerge(
      String conflictId, Map<String, dynamic> data) async {
    final row = await _client._requireConflict(conflictId);
    await _client._resolveWrite(row, data);
  }

  @override
  Future<void> resolveWithServer(String conflictId) async {
    final row = await _client._requireConflict(conflictId);
    // The server's version stands. Recorded as a decision by removing the
    // conflict, rather than the write quietly disappearing.
    await _client._writeQueue?.removeConflict(row.id);
    // The state the held writes were composed against never happened. What won
    // is the server's version, so rebase them onto that — otherwise each would
    // replay against a revision that moved and conflict in turn.
    await _client._rebaseOntoServerState(row);
    debugPrint(
        '[Koolbase] Conflict ${row.id} resolved in favour of the server');
  }

  @override
  Future<void> abandon(String conflictId) async {
    final row = await _client._requireConflict(conflictId);
    await _client._writeQueue?.removeConflict(row.id);
    // Abandoning claims neither version won, so the record stands as the server
    // has it — which is what anything still queued must build on.
    await _client._rebaseOntoServerState(row);
    debugPrint('[Koolbase] Conflict ${row.id} abandoned');
  }
}
