import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:koolbase_flutter/koolbase_flutter.dart';
import 'database_models.dart';
import 'offline/cache_store.dart';
import 'offline/write_queue.dart';
import 'database_models.dart';

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
    CacheStore? cacheStore,
    WriteQueue? writeQueue,
  })  : _userId = userId,
        _cacheStore = cacheStore;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'x-api-key': publicKey,
        if (_userId != null) 'x-user-id': _userId!,
      };

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
          headers: _headers,
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 10));

    if (res.statusCode != 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      throw Exception(data['error'] ?? 'Query failed');
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
}

/// Document reference for single record operations
class KoolbaseDocRef {
  final String baseUrl;
  final String publicKey;
  final String recordId;
  final String? _userId;
  final CacheStore? _cacheStore;

  KoolbaseDocRef({
    required this.baseUrl,
    required this.publicKey,
    required this.recordId,
    String? userId,
    CacheStore? cacheStore,
  })  : _userId = userId,
        _cacheStore = cacheStore;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'x-api-key': publicKey,
        if (_userId != null) 'x-user-id': _userId!,
      };

  Future<KoolbaseRecord> get() async {
    final res = await http
        .get(
          Uri.parse('$baseUrl/v1/sdk/db/records/$recordId'),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 10));

    if (res.statusCode != 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      throw Exception(body['error'] ?? 'Record not found');
    }
    return KoolbaseRecord.fromJson(
        jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<KoolbaseRecord> update(Map<String, dynamic> data) async {
    final res = await http
        .patch(
          Uri.parse('$baseUrl/v1/sdk/db/records/$recordId'),
          headers: _headers,
          body: jsonEncode({'data': data}),
        )
        .timeout(const Duration(seconds: 10));

    if (res.statusCode != 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode == 409) {
        throw KoolbaseConflictException(
          body['error'] as String? ?? 'Value violates a unique constraint',
        );
      }
      throw Exception(body['error'] ?? 'Update failed');
    }

    final record =
        KoolbaseRecord.fromJson(jsonDecode(res.body) as Map<String, dynamic>);

    return record;
  }

  Future<void> delete() async {
    final res = await http
        .delete(
          Uri.parse('$baseUrl/v1/sdk/db/records/$recordId'),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 10));

    if (res.statusCode != 204) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      throw Exception(body['error'] ?? 'Delete failed');
    }

    // Remove from local cache
    await _cacheStore?.deleteRecord(recordId);
  }
}
