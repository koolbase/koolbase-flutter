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
    CacheStore? cacheStore,
    WriteQueue? writeQueue,
  })  : _userId = userId,
        _accessTokenProvider = accessTokenProvider,
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
      throw koolbaseDataErrorFromResponse(res, fallbackMessage: 'Query failed');
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final records = (data['records'] as List)
        .map((e) => KoolbaseRecord.fromJson(e as Map<String, dynamic>))
        .toList();

    // Save to cache
    if (_cacheStore != null) {
      await _cacheStore!.saveQuery(
        cacheKey,
        collectionName,
        records.map((r) => r.toJson()).toList(),
      );
    }

    return QueryResult(
      records: records,
      total: data['total'] as int,
      isFromCache: false,
    );
  }

  /// Semantic search over a vector field. Supply EITHER a precomputed
  /// `queryVector` OR a `queryText` string — the server will embed text
  /// inline using the vector field's configured provider.
  ///
  /// ```dart
  /// // Server-side embedding (most common — set up an AI provider on the project):
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
  /// ```
  ///
  /// Throws [KoolbaseNotFoundException] if [field] is not declared on
  /// this collection. Throws [KoolbaseVectorDimensionMismatchException]
  /// if [queryVector]'s length does not match the field's dimension.
  /// Throws [ArgumentError] if both or neither of [queryVector] / [queryText]
  /// are supplied.
  Future<KoolbaseSemanticSearchResult> searchSemantic({
    required String field,
    List<double>? queryVector,
    String? queryText,
    int limit = 20,
    Map<String, dynamic>? where,
  }) async {
    final hasVector = queryVector != null && queryVector.isNotEmpty;
    final hasText = queryText != null && queryText.trim().isNotEmpty;
    if (!hasVector && !hasText) {
      throw ArgumentError('Provide either queryVector or queryText.');
    }
    if (hasVector && hasText) {
      throw ArgumentError('Provide only one of queryVector or queryText.');
    }

    final body = <String, dynamic>{
      'collection': collectionName,
      'field': field,
      'limit': limit,
      if (hasVector) 'query_vector': queryVector,
      if (hasText) 'query_text': queryText,
      if (where != null && where.isNotEmpty) 'where': where,
    };

    final res = await http
        .post(
          Uri.parse('$baseUrl/v1/sdk/db/search-semantic'),
          headers: await _headers(),
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 10));

    if (res.statusCode != 200) {
      throw koolbaseDataErrorFromResponse(res,
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
      throw koolbaseDataErrorFromResponse(res,
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
  final CacheStore? _cacheStore;

  KoolbaseDocRef({
    required this.baseUrl,
    required this.publicKey,
    required this.recordId,
    Future<String?> Function()? accessTokenProvider,
    CacheStore? cacheStore,
  })  : _accessTokenProvider = accessTokenProvider,
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

  Future<KoolbaseRecord> get() async {
    final res = await http
        .get(
          Uri.parse('$baseUrl/v1/sdk/db/records/$recordId'),
          headers: await _headers(),
        )
        .timeout(const Duration(seconds: 10));

    if (res.statusCode != 200) {
      throw koolbaseDataErrorFromResponse(res,
          fallbackMessage: 'Record not found');
    }
    return KoolbaseRecord.fromJson(
        jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<KoolbaseRecord> update(Map<String, dynamic> data) async {
    final res = await http
        .patch(
          Uri.parse('$baseUrl/v1/sdk/db/records/$recordId'),
          headers: await _headers(),
          body: jsonEncode({'data': data}),
        )
        .timeout(const Duration(seconds: 10));

    if (res.statusCode != 200) {
      throw koolbaseDataErrorFromResponse(res,
          fallbackMessage: 'Update failed');
    }

    final record =
        KoolbaseRecord.fromJson(jsonDecode(res.body) as Map<String, dynamic>);

    return record;
  }

  Future<void> delete() async {
    final res = await http
        .delete(
          Uri.parse('$baseUrl/v1/sdk/db/records/$recordId'),
          headers: await _headers(),
        )
        .timeout(const Duration(seconds: 10));

    if (res.statusCode != 204) {
      throw koolbaseDataErrorFromResponse(res,
          fallbackMessage: 'Delete failed');
    }

    // Remove from local cache
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
      throw koolbaseDataErrorFromResponse(res,
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
      throw koolbaseDataErrorFromResponse(res,
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
      throw koolbaseDataErrorFromResponse(res,
          fallbackMessage: 'Delete vector failed');
    }
  }
}
