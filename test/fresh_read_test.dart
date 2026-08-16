import 'package:flutter_test/flutter_test.dart';
import 'package:koolbase_flutter/src/database/database_query.dart';
import 'package:koolbase_flutter/src/database/offline/cache_store.dart';

/// get(fresh: true) exists because SWR cannot express read-after-write: a
/// cached answer is by definition the state BEFORE your write, and awaiting
/// the background-refresh stream proved racy on-device (the emission can
/// pass before a listener attaches — observed as a projection that tracked
/// the server exactly one sale behind). A caller verifying its own write, or
/// feeding a local projection that must only ingest server-provenance data,
/// needs the network's answer on demand.
///
/// The contract pinned here:
///   1. plain get() with a warm cache serves the cache (SWR unchanged);
///   2. get(fresh: true) with a warm cache DOES NOT consult it — it goes to
///      the network. HTTP isn't injectable, so the network attempt is proven
///      by pointing baseUrl at an unroutable host and asserting the fresh
///      read THROWS where the cached read succeeded. The failure is the
///      proof the cache was skipped.

/// CacheStore requires a db in its constructor; subclass with a late-bound
/// alternative: override the two methods get() touches and give the super a
/// null-ish db it will never use.
class _FakeCache implements CacheStore {
  int getQueryCalls = 0;

  @override
  Future<List<Map<String, dynamic>>?> getQuery(String key) async {
    getQueryCalls++;
    return [
      {
        r'$id': 'cached-1',
        r'$collection': 'expenses',
        r'$createdAt': '2026-01-01T00:00:00Z',
        r'$updatedAt': '2026-01-01T00:00:00Z',
        'title': 'from-cache',
      }
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) async => null;
}

void main() {
  KoolbaseQuery query(_FakeCache cache) => KoolbaseQuery(
        baseUrl: 'http://127.0.0.1:9', // unroutable: any network attempt fails
        publicKey: 'pk_test',
        collectionName: 'expenses',
        userId: 'u1',
        cacheStore: cache,
      );

  test('plain get() serves a warm cache (SWR contract unchanged)', () async {
    final cache = _FakeCache();
    final result = await query(cache).get();
    expect(result.isFromCache, isTrue);
    expect(cache.getQueryCalls, 1);
    expect(result.records.single.data['title'], 'from-cache');
  });

  test('get(fresh: true) skips the cache and goes to the network', () async {
    final cache = _FakeCache();
    await expectLater(
      query(cache).get(fresh: true),
      throwsA(anything),
      reason: 'an unroutable baseUrl must fail — proving the warm cache '
          'was never consulted for a fresh read',
    );
    expect(cache.getQueryCalls, 0,
        reason: 'fresh: true must not touch the query cache');
  });
}
