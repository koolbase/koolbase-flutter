import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'database_models.dart';
import 'database_query.dart';
import 'conflict.dart';
import 'offline/cache_store.dart';
import 'offline/local_database.dart' show Conflict;
import 'sync_engine.dart';
import 'offline/write_queue.dart';
import 'database_exceptions.dart';

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

  KoolbaseDatabaseClient({
    required this.baseUrl,
    required this.publicKey,
    Future<String?> Function()? accessTokenProvider,
    Future<void> Function()? onSessionExpired,
    CacheStore? cacheStore,
    WriteQueue? writeQueue,
  })  : _accessTokenProvider = accessTokenProvider,
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
    return queue.watchConflicts().map((rows) => rows.map(_mapConflict).toList());
  }

  KoolbaseConflict _mapConflict(Conflict row) => KoolbaseConflict(
        id: row.id,
        collection: row.collection,
        recordId: row.recordId,
        operation: row.operation == 'delete'
            ? ConflictOperation.delete
            : ConflictOperation.update,
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
    final rev = row.serverRevision;
    final http.Response res;
    if (row.operation == 'delete') {
      res = await http
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
      res = await http
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
    await _cacheStore?.invalidateCollection(row.collection);
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
        throw await koolbaseDataErrorNotifying(res, onSessionExpired: _onSessionExpired,
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
      throw await koolbaseDataErrorNotifying(res, onSessionExpired: _onSessionExpired,
          fallbackMessage: 'Upsert failed');
    }

    final created = res.statusCode == 201;
    final record =
        KoolbaseRecord.fromJson(jsonDecode(res.body) as Map<String, dynamic>);

    // Keep the local cache consistent, same as insert.
    await _cacheStore?.saveRecord(record.id, collection, record.data, _userId,
        revision: record.revision);
    await _cacheStore?.invalidateCollection(collection);

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
      throw await koolbaseDataErrorNotifying(res, onSessionExpired: _onSessionExpired,
          fallbackMessage: 'Delete failed');
    }

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final deleted = (body['deleted'] as num?)?.toInt() ?? 0;

    await _cacheStore?.invalidateCollection(collection);

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
      throw await koolbaseDataErrorNotifying(res, onSessionExpired: _onSessionExpired, fallbackMessage: 'Batch failed');
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
    debugPrint('[Koolbase] Conflict ${row.id} resolved in favour of the server');
  }

  @override
  Future<void> abandon(String conflictId) async {
    final row = await _client._requireConflict(conflictId);
    await _client._writeQueue?.removeConflict(row.id);
    debugPrint('[Koolbase] Conflict ${row.id} abandoned');
  }
}
