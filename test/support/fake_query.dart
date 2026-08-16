import 'dart:async';

import 'package:koolbase_flutter/koolbase_flutter.dart';

/// A KoolbaseQuery the controller cannot tell from the real one: it subclasses
/// the real thing and overrides only get(), stream and streamKey.
///
/// Shared rather than copied per test file. Two fakes modelling the same
/// semantics drift, and when they drift the tests quietly stop meaning the
/// same thing.
class FakeQuery extends KoolbaseQuery {
  FakeQuery({
    required this.onGet,
    required StreamController<QueryResult> refreshController,
    String identity = 'k1',
    String collection = 'expenses',
  })  : _refresh = refreshController,
        _identity = identity,
        super(
          baseUrl: 'https://api.test',
          publicKey: 'pk_test',
          collectionName: collection,
        );

  final Future<QueryResult> Function() onGet;
  final StreamController<QueryResult> _refresh;
  final String _identity;

  int listens = 0;

  @override
  Future<QueryResult> get({bool fresh = false}) => onGet();

  @override
  Stream<QueryResult> get stream {
    listens++;
    return _refresh.stream;
  }

  @override
  String get streamKey => _identity;
}

KoolbaseRecord fakeRecord(String id, {String collection = 'expenses'}) =>
    KoolbaseRecord(
      id: id,
      collection: collection,
      createdBy: 'u1',
      data: {'title': id},
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      revision: 1,
    );

QueryResult fakeResult(List<String> ids, {bool fromCache = false}) =>
    QueryResult(
      records: [for (final id in ids) fakeRecord(id)],
      total: ids.length,
      isFromCache: fromCache,
    );
