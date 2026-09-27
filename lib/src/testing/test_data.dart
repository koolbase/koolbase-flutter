import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:koolbase_flutter/koolbase_flutter.dart';

/// Records for [KoolbaseCollectionList] and [KoolbaseRecordView] in widget
/// tests, so a screen can be pumped POPULATED rather than stuck loading.
///
/// Certification and testing infrastructure -- NOT a local-data API. It
/// replaces only the data SOURCE: the list's base query and the record view's
/// fetch. The controllers, paging, states and rendering after that are the
/// production code, so what renders here is what renders in an app.
///
/// ```dart
/// KoolbaseTestData(
///   collections: {
///     'songs': [
///       {'id': 'cert-1', 'title': 'A song', 'coverUrl': 'https://example.com/c.png'},
///     ],
///   },
///   child: const SongsScreen(),
/// )
/// ```
///
/// A list pages like the server: its limit and offset are honoured and the
/// total is exact, so Load more appears when it would. Filters and order are
/// NOT applied: records come in the order given. A record view finds its
/// record by id, and an unknown id throws [KoolbaseNotFoundException], as the
/// API answers.
class KoolbaseTestData extends InheritedWidget {
  const KoolbaseTestData({
    super.key,
    required this.collections,
    required super.child,
  });

  /// Records per collection name; each map has an `id` and the record's fields.
  final Map<String, List<Map<String, Object?>>> collections;

  /// The test data around [context], or null. Valid in `initState`: it
  /// registers no dependency.
  static KoolbaseTestData? maybeOf(BuildContext context) =>
      context.getElementForInheritedWidgetOfExactType<KoolbaseTestData>()?.widget
          as KoolbaseTestData?;

  @override
  bool updateShouldNotify(KoolbaseTestData oldWidget) =>
      !identical(collections, oldWidget.collections);

  List<KoolbaseRecord> _records(String collection) => [
    for (final m in collections[collection] ?? const <Map<String, Object?>>[])
      KoolbaseRecord(
        id: '${m['id']}',
        collection: collection,
        createdBy: 'cert',
        data: {
          for (final e in m.entries)
            if (e.key != 'id') e.key: e.value,
        },
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
        revision: 1,
      ),
  ];

  /// A query over [collection] answering from this data.
  KoolbaseQuery queryFor(String collection) =>
      _TestDataQuery(_records(collection), collection);

  /// The record [id] of [collection], or [KoolbaseNotFoundException].
  Future<KoolbaseRecord> record(String collection, String id) async {
    for (final r in _records(collection)) {
      if (r.id == id) return r;
    }
    throw const KoolbaseNotFoundException(
      'record not found',
      'record_not_found',
    );
  }
}

/// Pages [_all] as the server would: [limit] and [offset] noted, the slice
/// returned with the exact total. No realtime updates.
class _TestDataQuery extends KoolbaseQuery {
  _TestDataQuery(this._all, String collection)
    : _collection = collection,
      super(
        baseUrl: 'https://test.invalid',
        publicKey: 'pk_test',
        collectionName: collection,
      );

  final List<KoolbaseRecord> _all;
  final String _collection;
  int _pageSize = 20;
  int _from = 0;

  @override
  KoolbaseQuery limit(int value) {
    _pageSize = value;
    return super.limit(value);
  }

  @override
  KoolbaseQuery offset(int value) {
    _from = value;
    return super.offset(value);
  }

  @override
  Future<QueryResult> get({bool fresh = false}) async => QueryResult(
    records: _all.skip(_from).take(_pageSize).toList(),
    total: _all.length,
    isFromCache: false,
  );

  @override
  Stream<QueryResult> get stream => const Stream<QueryResult>.empty();

  @override
  String get streamKey => 'test:$_collection';
}
