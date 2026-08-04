import 'package:flutter_test/flutter_test.dart';
import 'package:koolbase_flutter/src/database/database_query.dart';

/// The stream-contamination guard. Query streams were keyed by collection
/// name alone, so two different queries on one collection shared a
/// controller: each background refresh emitted ITS records to BOTH
/// listeners — silently wrong data on any screen with two lists over the
/// same collection. The fix keys streams by the full query identity
/// (collection + filters + user), the same construction as the cache key.
/// These tests state that property directly.
void main() {
  KoolbaseQuery q(String collection,
      {Map<String, dynamic>? filters, String? userId}) {
    var query = KoolbaseQuery(
      baseUrl: 'https://api.test',
      publicKey: 'pk_test',
      collectionName: collection,
      userId: userId,
    );
    filters?.forEach((field, value) {
      query = query.where(field, isEqualTo: value);
    });
    return query;
  }

  test('different filters on one collection have different stream identities',
      () {
    final mine = q('expenses', filters: {'user_id': 'u1'});
    final all = q('expenses');
    expect(mine.streamKey, isNot(equals(all.streamKey)),
        reason: 'distinct queries sharing a stream is the contamination bug');
  });

  test('different users on one query shape have different stream identities',
      () {
    final u1 = q('expenses', filters: {'status': 'open'}, userId: 'u1');
    final u2 = q('expenses', filters: {'status': 'open'}, userId: 'u2');
    expect(u1.streamKey, isNot(equals(u2.streamKey)));
  });

  test('the same query shape has a stable stream identity', () {
    final a = q('expenses', filters: {'user_id': 'u1'}, userId: 'u1');
    final b = q('expenses', filters: {'user_id': 'u1'}, userId: 'u1');
    expect(a.streamKey, equals(b.streamKey),
        reason: 'same query must share a stream or refreshes are lost');
  });

  test('distinct streams: listening to one query never observes another', () {
    final mine = q('expenses', filters: {'user_id': 'u1'});
    final all = q('expenses');
    expect(identical(mine.stream, all.stream), isFalse);
  });
}
