import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:koolbase_flutter/koolbase_flutter.dart';
import 'offline/cache_store.dart';
import 'offline/write_queue.dart';

/// Broadcast stream controller for background refresh notifications
/// Keyed by collection name
final Map<String, StreamController<QueryResult>> _refreshControllers = {};

StreamController<QueryResult> _getController(String collection) {
  if (!_refreshControllers.containsKey(collection) ||
      _refreshControllers[collection]!.isClosed) {
    _refreshControllers[collection] = StreamController<QueryResult>.broadcast();
  }
  return _refreshControllers[collection]!;
}

/// Fluent query builder for a collection
class KoolbaseQuery {
  final String baseUrl;
  final String publicKey;
  final String collectionName;
  final String? _userId;
  final Future<String?> Function()? _accessTokenProvider;
  final Future<void> Function()? _onSessionExpired;
  final CacheStore? _cacheStore;
  final Map<String, dynamic> _filters = {};
  final List<String> _populate = [];
  int _limit = 20;
  int _offset = 0;
  String? _orderBy;
  bool _orderDesc = false;

  KoolbaseQuery({
    required this.baseUrl,
    required this.publicKey,
    required this.collectionName,
    String? userId,
    Future<String?> Function()? accessTokenProvider,
    Future<void> Function()? onSessionExpired,
    CacheStore? cacheStore,
    WriteQueue? writeQueue,
  })  : _userId = userId,
        _accessTokenProvider = accessTokenProvider,
        _onSessionExpired = onSessionExpired,
        _cacheStore = cacheStore;

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

  KoolbaseQuery where(String field, {required dynamic isEqualTo}) {
    _filters[field] = isEqualTo;
    return this;
  }

  KoolbaseQuery limit(int value) {
    _limit = value;
    return this;
  }

  KoolbaseQuery offset(int value) {
    _offset = value;
    return this;
  }

  KoolbaseQuery orderBy(String field, {bool descending = false}) {
    _orderBy = field;
    _orderDesc = descending;
    return this;
  }

  /// Populate related records from another collection.
  ///
  /// Pass one or more strings in the format "field_name:collection_name".
  ///
  /// Example:
  /// ```dart
  /// await Koolbase.db
  ///   .collection('posts')
  ///   .populate(['author_id:users'])
  ///   .get();
  /// ```
  KoolbaseQuery populate(List<String> fields) {
    _populate.addAll(fields);
    return this;
  }

  /// Stream of fresh results after background network refresh.
  /// Listen to this to update UI when fresh data arrives.
  ///
  /// Example:
  /// ```dart
  /// Koolbase.db.collection('posts').stream.listen((result) {
  ///   setState(() => posts = result.records);
  /// });
  /// ```
  Stream<QueryResult> get stream => _getController(collectionName).stream;

  /// Fetch records — cache-first with background network refresh.
  ///
  /// Returns cached data immediately if available, then refreshes
  /// from the network in the background and emits via [stream].
  Future<QueryResult> get() async {
    final cacheKey = CacheStore.buildKey(
      collectionName,
      _filters,
      _userId,
    );

    // 1. Try cache first
    if (_cacheStore != null) {
      final cached = await _cacheStore!.getQuery(cacheKey);
      if (cached != null) {
        final records = cached.map((e) => KoolbaseRecord.fromJson(e)).toList();
        // Fire background refresh without blocking
        _refreshFromNetwork(cacheKey);
        return QueryResult(
          records: records,
          total: records.length,
          isFromCache: true,
        );
      }
    }

    // 2. No cache — fetch from network
    return await _fetchFromNetwork(cacheKey);
  }

  /// Background network refresh — updates cache and notifies stream
  void _refreshFromNetwork(String cacheKey) {
    _fetchFromNetwork(cacheKey).then((result) {
      _getController(collectionName).add(result);
    }).catchError((e) {
      debugPrint('[Koolbase] Background refresh failed: $e');
    });
  }

  Future<QueryResult> _fetchFromNetwork(String cacheKey) async {
    final body = <String, dynamic>{
      'collection': collectionName,
      'filters': _filters,
      'limit': _limit,
      'offset': _offset,
      if (_orderBy != null) 'order_by': _orderBy,
      'order_desc': _orderDesc,
      if (_populate.isNotEmpty) 'populate': _populate,
    };

    final res = await http
        .post(
          Uri.parse('$baseUrl/v1/sdk/db/query'),
          headers: await _headers(),
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 10));

    if (res.statusCode != 200) {
      throw await koolbaseDataErrorNotifying(res, onSessionExpired: _onSessionExpired, fallbackMessage: 'Query failed');
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final records = (data['records'] as List)
        .map((e) => KoolbaseRecord.fromJson(e as Map<String, dynamic>))
        .toList();

    // Save to cache
    if (_cacheStore != null) {
      final asJson = records.map((r) => r.toJson()).toList();
      await _cacheStore!.saveQuery(cacheKey, collectionName, asJson);
      // Also individually, so a record the user has seen can be edited
      // offline. The query cache says what a query returned; the record cache
      // says what the SDK last saw of each record, and a mutation baseline
      // belongs to the second.
      await _cacheStore!.cacheRecordsFromQuery(collectionName, asJson, _userId);
    }

    return QueryResult(
      records: records,
      total: data['total'] as int,
      isFromCache: false,
    );
  }

  /// final result = await Koolbase.db.collection('articles').searchSemantic(
  ///   field: 'content_embedding',
  ///   queryText: 'how do I configure CI/CD?',
  ///   limit: 10,
  /// );
  ///
  /// // Client-side embedding (when you've already encoded the query):
  /// final result = await Koolbase.db.collection('articles').searchSemantic(
  ///   field: 'content_embedding',
  ///   queryVector: precomputed,
  ///   limit: 10,
  /// );
  ///
  /// // Hybrid search (vector + BM25, RRF-fused):
  /// final result = await Koolbase.db.collection('articles').searchSemantic(
  ///   field: 'content_embedding',
  ///   queryText: 'how do I configure CI/CD?',
  ///   mode: KoolbaseSearchMode.hybrid,
  ///   minSimilarity: 70,
  /// );
  /// ```
  ///
  /// [mode] selects the retrieval strategy:
  /// - [KoolbaseSearchMode.semantic] (default) — pure vector search via HNSW
  /// - [KoolbaseSearchMode.lexical] — pure BM25 over the field's source text
  /// - [KoolbaseSearchMode.hybrid] — vector + lexical fused with reciprocal
  ///   rank fusion (k=60). Generally the strongest default for production.
  ///
  /// [minSimilarity], if set (0..100), filters out results below the given
  /// similarity percentage. Server-side filter — saves bandwidth on weak
  /// matches. Only valid for semantic and hybrid; setting it on lexical
  /// throws a server-side validation error (BM25 ranks aren't comparable
  /// to cosine similarity).
  ///
  /// Throws [KoolbaseNotFoundException] if [field] is not declared on
  /// this collection. Throws [KoolbaseVectorDimensionMismatchException]
  /// if [queryVector]'s length does not match the field's dimension.
  /// Throws [ArgumentError] if both or neither of [queryVector] / [queryText]
  /// are supplied, or if [minSimilarity] is outside 0..100.
  Future<KoolbaseSemanticSearchResult> searchSemantic({
    required String field,
    List<double>? queryVector,
    String? queryText,
    int limit = 20,
    Map<String, dynamic>? where,
    KoolbaseSearchMode mode = KoolbaseSearchMode.semantic,
    double? minSimilarity,
  }) async {
    final hasVector = queryVector != null && queryVector.isNotEmpty;
    final hasText = queryText != null && queryText.trim().isNotEmpty;
    if (!hasVector && !hasText) {
      throw ArgumentError('Provide either queryVector or queryText.');
    }
    if (hasVector && hasText) {
      throw ArgumentError('Provide only one of queryVector or queryText.');
    }
    if (minSimilarity != null && (minSimilarity < 0 || minSimilarity > 100)) {
      throw ArgumentError(
          'minSimilarity must be between 0 and 100, got $minSimilarity.');
    }
    final body = <String, dynamic>{
      'collection': collectionName,
      'field': field,
      'limit': limit,
      if (hasVector) 'query_vector': queryVector,
      if (hasText) 'query_text': queryText,
      if (where != null && where.isNotEmpty) 'where': where,
      // Always send mode so the server uses the SDK's intent rather than
      // its own default. Omitting for `semantic` would also work (server
      // defaults to semantic) but explicit is safer if defaults ever shift.
      'mode': mode.wireValue,
      if (minSimilarity != null) 'min_similarity': minSimilarity,
    };
    final res = await http
        .post(
          Uri.parse('$baseUrl/v1/sdk/db/search-semantic'),
          headers: await _headers(),
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      throw await koolbaseDataErrorNotifying(res, onSessionExpired: _onSessionExpired,
          fallbackMessage: 'Semantic search failed');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final hits = (data['results'] as List<dynamic>? ?? [])
        .map((e) => KoolbaseSemanticHit.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
    return KoolbaseSemanticSearchResult(hits: hits, total: hits.length);
  }

  /// Queue an embedding job for a record on this collection. The server's
  /// embedding worker picks it up within ~1 second, calls the configured
  /// provider, and writes the resulting vector to the record.
  ///
  /// If [text] is omitted, the value of the vector field's configured
  /// `source_field` on the record is used. Pass [text] explicitly for
  /// backfills, A/B comparisons, or when you want to embed something other
  /// than the record's source field.
  ///
  /// ```dart
  /// // Re-embed using the record's content field (the configured source):
  /// await Koolbase.db.collection('articles').embedText(
  ///   recordId: article.id,
  ///   vectorField: 'content_embedding',
  /// );
  ///
  /// // Embed a custom string for this record:
  /// await Koolbase.db.collection('articles').embedText(
  ///   recordId: article.id,
  ///   vectorField: 'content_embedding',
  ///   text: '${article.title}\n\n${article.summary}',
  /// );
  /// ```
  ///
  /// Returns when the job is queued — not when the vector lands. Poll the
  /// vector via [KoolbaseDocRef.getVector] if you need to wait for it.
  Future<void> embedText({
    required String recordId,
    required String vectorField,
    String? text,
  }) async {
    final body = <String, dynamic>{
      'collection': collectionName,
      'record_id': recordId,
      'vector_field': vectorField,
      if (text != null && text.isNotEmpty) 'text': text,
    };

    final res = await http
        .post(
          Uri.parse('$baseUrl/v1/sdk/db/embed-text'),
          headers: await _headers(),
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 10));

    if (res.statusCode != 200) {
      throw await koolbaseDataErrorNotifying(res, onSessionExpired: _onSessionExpired,
          fallbackMessage: 'embedText failed');
    }
  }
}

/// Document reference for single record operations
class KoolbaseDocRef {
  final String baseUrl;
  final String publicKey;
  final String recordId;
  final Future<String?> Function()? _accessTokenProvider;
  final Future<void> Function()? _onSessionExpired;
  final CacheStore? _cacheStore;
  final String? _userId;

  /// Queues a mutation that could not reach the server because the network
  /// was unreachable. Null when offline support is not configured, in which
  /// case update and delete surface the failure as they always did.
  final WriteQueue? _writeQueue;

  KoolbaseDocRef({
    required this.baseUrl,
    required this.publicKey,
    required this.recordId,
    Future<String?> Function()? accessTokenProvider,
    Future<void> Function()? onSessionExpired,
    CacheStore? cacheStore,
    String? userId,
    WriteQueue? writeQueue,
  })  : _accessTokenProvider = accessTokenProvider,
        _onSessionExpired = onSessionExpired,
        _cacheStore = cacheStore,
        _userId = userId,
        _writeQueue = writeQueue;

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

  Future<KoolbaseRecord> get() async {
    final res = await http
        .get(
          Uri.parse('$baseUrl/v1/sdk/db/records/$recordId'),
          headers: await _headers(),
        )
        .timeout(const Duration(seconds: 10));

    if (res.statusCode != 200) {
      throw await koolbaseDataErrorNotifying(res, onSessionExpired: _onSessionExpired,
          fallbackMessage: 'Record not found');
    }
    final record =
        KoolbaseRecord.fromJson(jsonDecode(res.body) as Map<String, dynamic>);

    // Cached individually, with its revision, so a record the user has opened
    // can be edited offline. Reading one record then editing it is the ordinary
    // flow — without this the most common path would have no baseline and the
    // edit would be refused.
    final col = record.collection;
    if (col != null) {
      await _cacheStore?.saveRecord(
          record.id, col, record.data, _userId, revision: record.revision);
    }
    return record;
  }

  /// Applies a partial update, merging with what is already stored.
  ///
  /// Offline, the change is queued and replayed when connectivity returns — but
  /// only if the SDK knows what the record looked like when the change was
  /// composed. That baseline is what lets replay tell an untouched record from
  /// one someone else changed meanwhile; without it the write would be applied
  /// blindly, overwriting whatever happened while the device was away.
  ///
  /// Throws [KoolbaseOfflineBaselineUnavailableException] when there is no such
  /// baseline: read the record first, or make the change online.
  Future<KoolbaseRecord> update(Map<String, dynamic> data) async {
    Map<String, dynamic>? baseline;
    int? baseRevision;
    String? collection;

    // Resolved before the request, so a network failure has somewhere to go.
    if (_writeQueue != null) {
      final resolved = await _resolveBaseline();
      baseline = resolved?.baseline;
      baseRevision = resolved?.revision;
      collection = resolved?.collection;
    }

    final http.Response res;
    try {
      res = await http
          .patch(
            Uri.parse('$baseUrl/v1/sdk/db/records/$recordId'),
            headers: await _headers(),
            // Deliberately unconditional. This release adds optimistic
            // concurrency to queued replay only: a direct online write keeps the
            // overwrite semantics applications already depend on, and making
            // every write conditional because a revision happens to be cached
            // would be a breaking change nobody opted into. An explicit
            // conditional API comes later.
            body: jsonEncode({'data': data}),
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      // The network was unreachable. A server that answered — with a rejection,
      // a conflict, anything — is not this case and must never be queued.
      if (_writeQueue == null) rethrow;
      // Checked before the collection: a record never seen has neither, and the
      // useful thing to say is "read it first", not the socket error underneath.
      if (baseline == null || collection == null) {
        throw const KoolbaseOfflineBaselineUnavailableException(
            'This record must be read at least once before it can be updated offline.');
      }
      await _writeQueue!.enqueue(
        collection: collection,
        operation: 'update',
        payload: data,
        recordId: recordId,
        userId: _userId,
        baseline: baseline,
        baseRevision: baseRevision,
      );
      final merged = {...baseline, ...data};
      await _cacheStore?.saveRecord(recordId, collection, merged, _userId,
          revision: baseRevision);
      // Optimistic: durable locally and queued to send, not yet accepted.
      return KoolbaseRecord(
        id: recordId,
        collection: collection,
        data: merged,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        revision: baseRevision,
      );
    }

    if (res.statusCode != 200) {
      throw await koolbaseDataErrorNotifying(res,
          onSessionExpired: _onSessionExpired, fallbackMessage: 'Update failed');
    }

    final record =
        KoolbaseRecord.fromJson(jsonDecode(res.body) as Map<String, dynamic>);

    final col = record.collection ?? collection;
    if (col != null) {
      await _cacheStore?.saveRecord(record.id, col, record.data, _userId,
          revision: record.revision);
    }
    return record;
  }

  /// The record's state as the SDK last knew it, for composing an offline
  /// mutation against.
  ///
  /// Two sources, in order. A record created offline is not in the cache as a
  /// server record, but its queued insert holds the state a later edit builds
  /// on — insert-then-correct is the ordinary offline sequence. Otherwise the
  /// cached copy, with the revision it was read at.
  ///
  /// Null when neither exists: never seen on this device, or a queued delete has
  /// already removed it locally.
  Future<({Map<String, dynamic> baseline, int? revision, String collection})?>
      _resolveBaseline() async {
    final pending = await _writeQueue?.pendingForRecord(recordId) ?? const [];
    if (pending.isNotEmpty) {
      final projected = await _writeQueue?.projectedState(recordId);
      if (projected == null) return null; // the chain ends in a delete
      return (
        baseline: projected,
        revision: pending.last.baseRevision,
        collection: pending.first.collection,
      );
    }
    final cached = await _cacheStore?.getRecordWithCollection(recordId);
    if (cached == null) return null;
    return (
      baseline: cached.data,
      revision: await _cacheStore?.revisionFor(recordId),
      collection: cached.collection,
    );
  }

  /// Deletes the record.
  ///
  /// Offline, the delete is queued and replayed when connectivity returns, but
  /// only when the SDK knows what the record looked like at the time. A delete
  /// replayed blindly would remove something the user last saw hours earlier and
  /// which may have changed since — the most destructive kind of stale write.
  ///
  /// Throws [KoolbaseOfflineBaselineUnavailableException] when there is no such
  /// baseline: read the record first, or delete it while online.
  Future<void> delete() async {
    Map<String, dynamic>? baseline;
    int? baseRevision;
    String? collection;

    if (_writeQueue != null) {
      final resolved = await _resolveBaseline();
      baseline = resolved?.baseline;
      baseRevision = resolved?.revision;
      collection = resolved?.collection;
    }

    final http.Response res;
    try {
      res = await http
          .delete(
            // Unconditional, as above: the guarantee belongs to queued replay,
            // not to every direct call.
            Uri.parse('$baseUrl/v1/sdk/db/records/$recordId'),
            headers: await _headers(),
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      if (_writeQueue == null) rethrow;
      // Checked before the collection: a record never seen has neither, and the
      // useful thing to say is "read it first", not the socket error underneath.
      if (baseline == null || collection == null) {
        throw const KoolbaseOfflineBaselineUnavailableException(
            'This record must be read at least once before it can be deleted offline.');
      }
      await _writeQueue!.enqueue(
        collection: collection,
        operation: 'delete',
        payload: const {},
        recordId: recordId,
        userId: _userId,
        baseline: baseline,
        baseRevision: baseRevision,
      );
      // The queued write holds its own copy of the baseline, so removing the
      // cached record now costs nothing and keeps local reads consistent with
      // what the user just did.
      await _cacheStore?.deleteRecord(recordId);
      return;
    }

    if (res.statusCode != 204) {
      throw await koolbaseDataErrorNotifying(res,
          onSessionExpired: _onSessionExpired, fallbackMessage: 'Delete failed');
    }

    await _cacheStore?.deleteRecord(recordId);
  }

  /// Write (or replace) a vector for this record on the named [field].
  ///
  /// The field must already be declared on the collection (dashboard or
  /// CLI). [vector]'s length must match the field's declared dimension;
  /// otherwise throws [KoolbaseVectorDimensionMismatchException].
  ///
  /// Online-only (no offline cache for vectors).
  ///
  /// ```dart
  /// await Koolbase.db.doc(articleId).setVector(
  ///   'embedding',
  ///   await myEmbeddingModel.encode(article.content),
  /// );
  /// ```
  ///
  /// Throws [KoolbaseNotFoundException] if the record or vector field
  /// does not exist; throws [KoolbasePermissionException] if the caller
  /// is not allowed to write this record per the collection's write rule.
  Future<void> setVector(String field, List<double> vector) async {
    final res = await http
        .post(
          Uri.parse('$baseUrl/v1/sdk/db/set-vector'),
          headers: await _headers(),
          body: jsonEncode({
            'record_id': recordId,
            'field': field,
            'vector': vector,
          }),
        )
        .timeout(const Duration(seconds: 10));

    if (res.statusCode != 204) {
      throw await koolbaseDataErrorNotifying(res, onSessionExpired: _onSessionExpired,
          fallbackMessage: 'Set vector failed');
    }
  }

  /// Read this record's stored vector on the named [field].
  ///
  /// Returns the full [KoolbaseVector] including the float values plus
  /// timestamps. Throws [KoolbaseNotFoundException] if either the
  /// field is not declared, or no vector has been set for this record
  /// on this field. Throws [KoolbasePermissionException] if the caller
  /// cannot read this record per the collection's read rule.
  ///
  /// Online-only.
  ///
  /// ```dart
  /// final v = await Koolbase.db.doc(articleId).getVector('embedding');
  /// print('${v.vector.length}-dim vector, updated ${v.updatedAt}');
  /// ```
  Future<KoolbaseVector> getVector(String field) async {
    final res = await http
        .post(
          Uri.parse('$baseUrl/v1/sdk/db/get-vector'),
          headers: await _headers(),
          body: jsonEncode({
            'record_id': recordId,
            'field': field,
          }),
        )
        .timeout(const Duration(seconds: 10));

    if (res.statusCode != 200) {
      throw await koolbaseDataErrorNotifying(res, onSessionExpired: _onSessionExpired,
          fallbackMessage: 'Get vector failed');
    }
    return KoolbaseVector.fromJson(
        jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Remove this record's stored vector on the named [field].
  ///
  /// Online-only. Throws [KoolbaseNotFoundException] if no vector is
  /// set for (record, field); throws [KoolbasePermissionException] if
  /// the caller cannot write this record per the collection's write rule.
  ///
  /// Note: this removes the vector from the dimension table but does NOT
  /// remove the field declaration itself — the field stays on the
  /// collection and is still settable on other records.
  Future<void> deleteVector(String field) async {
    final res = await http
        .post(
          Uri.parse('$baseUrl/v1/sdk/db/delete-vector'),
          headers: await _headers(),
          body: jsonEncode({
            'record_id': recordId,
            'field': field,
          }),
        )
        .timeout(const Duration(seconds: 10));

    if (res.statusCode != 204) {
      throw await koolbaseDataErrorNotifying(res, onSessionExpired: _onSessionExpired,
          fallbackMessage: 'Delete vector failed');
    }
  }
}
