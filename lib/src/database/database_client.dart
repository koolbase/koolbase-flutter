import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'database_models.dart';
import 'database_query.dart';
import 'offline/cache_store.dart';
import 'offline/write_queue.dart';
import 'database_exceptions.dart';

class KoolbaseDatabaseClient {
  final String baseUrl;
  final String publicKey;
  String? _userId;
  CacheStore? _cacheStore;
  WriteQueue? _writeQueue;
  static const _uuid = Uuid();

  KoolbaseDatabaseClient({
    required this.baseUrl,
    required this.publicKey,
    CacheStore? cacheStore,
    WriteQueue? writeQueue,
  })  : _cacheStore = cacheStore,
        _writeQueue = writeQueue;

  void setUserId(String? userId) => _userId = userId;

  void setOfflineSupport({
    required CacheStore cacheStore,
    required WriteQueue writeQueue,
  }) {
    _cacheStore = cacheStore;
    _writeQueue = writeQueue;
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'x-api-key': publicKey,
        if (_userId != null) 'x-user-id': _userId!,
      };

  /// Get a fluent query builder for a collection
  KoolbaseQuery collection(String name) {
    return KoolbaseQuery(
      baseUrl: baseUrl,
      publicKey: publicKey,
      collectionName: name,
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
      userId: _userId,
      cacheStore: _cacheStore,
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
            headers: _headers,
            body: jsonEncode({'collection': collection, 'data': data}),
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode != 201) {
        throw koolbaseDataErrorFromResponse(res,
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
        );

        // Optimistically save to local cache
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
          headers: _headers,
          body: jsonEncode({
            'collection': collection,
            'match': match,
            'data': data,
          }),
        )
        .timeout(const Duration(seconds: 10));

    if (res.statusCode != 200 && res.statusCode != 201) {
      throw koolbaseDataErrorFromResponse(res,
          fallbackMessage: 'Upsert failed');
    }

    final created = res.statusCode == 201;
    final record =
        KoolbaseRecord.fromJson(jsonDecode(res.body) as Map<String, dynamic>);

    // Keep the local cache consistent, same as insert.
    await _cacheStore?.saveRecord(record.id, collection, record.data, _userId);
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
          headers: _headers,
          body: jsonEncode({'collection': collection, 'filters': filters}),
        )
        .timeout(const Duration(seconds: 10));

    if (res.statusCode != 200) {
      throw koolbaseDataErrorFromResponse(res,
          fallbackMessage: 'Delete failed');
    }

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final deleted = (body['deleted'] as num?)?.toInt() ?? 0;

    await _cacheStore?.invalidateCollection(collection);

    return deleted;
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
    if (_writeQueue == null || _cacheStore == null) return;

    final writes = await _writeQueue!.getPending();
    if (writes.isEmpty) return;

    debugPrint('[Koolbase] Syncing ${writes.length} pending write(s)');

    for (final write in writes) {
      if (await _writeQueue!.shouldDrop(write.id)) {
        debugPrint(
            '[Koolbase] Dropping failed write after max retries: ${write.id}');
        await _writeQueue!.remove(write.id);
        continue;
      }

      try {
        final payload = _writeQueue!.decodePayload(write);

        switch (write.operation) {
          case 'insert':
            final res = await http
                .post(
                  Uri.parse('$baseUrl/v1/sdk/db/insert'),
                  headers: _headers,
                  body: jsonEncode({
                    'collection': write.collection,
                    'data': payload,
                  }),
                )
                .timeout(const Duration(seconds: 10));
            if (res.statusCode != 201) {
              throw Exception('Insert sync failed: ${res.statusCode}');
            }
            break;

          case 'update':
            if (write.recordId == null) continue;
            final res = await http
                .patch(
                  Uri.parse('$baseUrl/v1/sdk/db/records/${write.recordId}'),
                  headers: _headers,
                  body: jsonEncode({'data': payload}),
                )
                .timeout(const Duration(seconds: 10));
            if (res.statusCode != 200) {
              throw Exception('Update sync failed: ${res.statusCode}');
            }
            break;

          case 'delete':
            if (write.recordId == null) continue;
            final res = await http
                .delete(
                  Uri.parse('$baseUrl/v1/sdk/db/records/${write.recordId}'),
                  headers: _headers,
                )
                .timeout(const Duration(seconds: 10));
            if (res.statusCode != 204) {
              throw Exception('Delete sync failed: ${res.statusCode}');
            }
            break;
        }

        await _writeQueue!.remove(write.id);
        await _cacheStore!.invalidateCollection(write.collection);
        debugPrint('[Koolbase] Write synced: ${write.id}');
      } catch (e) {
        debugPrint('[Koolbase] Write sync failed for ${write.id}: $e');
        await _writeQueue!.incrementRetry(write.id);
      }
    }
  }
}
