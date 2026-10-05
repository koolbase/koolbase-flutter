import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:koolbase_flutter/koolbase_flutter.dart';
import 'package:koolbase_flutter/src/database/offline/cache_store.dart';
import 'package:koolbase_flutter/src/database/offline/local_database.dart';
import 'package:koolbase_flutter/src/database/offline/write_queue.dart';
import 'package:koolbase_flutter/src/database/sync_engine.dart';

/// Offline correctness (12.17.1). Each case fails on 12.17.0.
void main() {
  late KoolbaseLocalDatabase db;
  late WriteQueue queue;
  late CacheStore cache;

  setUp(() {
    db = KoolbaseLocalDatabase.withExecutor(NativeDatabase.memory());
    queue = WriteQueue(db);
    cache = CacheStore(db);
  });

  tearDown(() => db.close());

  KoolbaseDatabaseClient offlineClient() {
    final client = KoolbaseDatabaseClient(
      baseUrl: 'http://127.0.0.1:9', // unroutable: every request is "offline"
      publicKey: 'pk_test',
      writeQueue: queue,
    );
    client.setUserId('u1');
    return client;
  }

  SyncEngine engine() => SyncEngine(
        baseUrl: 'https://api.test',
        publicKey: 'pk_test',
        cacheStore: cache,
        writeQueue: queue,
        accessTokenProvider: () async => 'token',
        currentUserId: () => 'u1',
      );

  http.Response respond(int status, Object body) => http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
      );

  group('an offline add has one id from birth', () {
    test('the queued add carries the id the app was given', () async {
      final rec = await offlineClient()
          .insert(collection: 'tickets', data: {'name': 'kept'});
      final pending = (await queue.getPending()).single;
      expect(pending.recordId, rec.id);
      expect(queue.decodePayload(pending)['id'], rec.id);
      expect(rec.data['id'], rec.id);
    });

    test('add then edit offline replays as one chain on that id', () async {
      final client = offlineClient();
      final rec =
          await client.insert(collection: 'tickets', data: {'name': 'first'});
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await client.doc(rec.id).update({'name': 'fixed'});

      final pending = await queue.getPending();
      expect(pending.map((w) => w.operation).toList(), ['insert', 'update']);
      expect(pending.map((w) => w.recordId).toList(), [rec.id, rec.id]);

      final requests = <String>[];
      await http.runWithClient(
        () => engine().syncPendingWrites(),
        () => MockClient((req) async {
          requests.add('${req.method} ${req.url.path}');
          final body = jsonDecode(req.body.isEmpty ? '{}' : req.body)
              as Map<String, dynamic>;
          if (req.url.path.endsWith('/v1/sdk/db/insert')) {
            final data = body['data'] as Map<String, dynamic>;
            // The server honours a caller-supplied id.
            return respond(201, {...data, r'$id': data['id'], r'$revision': 1});
          }
          return respond(
              200, {r'$id': rec.id, r'$revision': 2, 'name': 'fixed'});
        }),
      );

      expect(requests, [
        'POST /v1/sdk/db/insert',
        'PATCH /v1/sdk/db/records/${rec.id}',
      ]);
      expect(await queue.getPending(), isEmpty);
      expect(await queue.conflicts(), isEmpty);
    });
  });

  test('a refused offline add leaves the saved record and the saved lists',
      () async {
    final key = CacheStore.buildKey('tickets', const {}, 'u1');
    await cache.saveQuery(key, 'tickets', [
      {r'$id': 'r1', 'name': 'collides'},
      {r'$id': 'r2', 'name': 'other'},
    ]);
    await cache.saveRecord('r1', 'tickets', {'name': 'collides'}, 'u1');
    await queue.enqueue(
      collection: 'tickets',
      operation: 'insert',
      payload: {'id': 'r1', 'name': 'collides'},
      recordId: 'r1',
      userId: 'u1',
    );

    await http.runWithClient(
      () => engine().syncPendingWrites(),
      () => MockClient((req) async =>
          respond(409, {'code': 'unique_violation', 'error': 'name taken'})),
    );

    final conflicts = await queue.conflicts();
    expect(conflicts.single.reason, 'rejected');
    expect(await cache.getRecord('r1'), isNull);
    final list = await cache.getQuery(key);
    expect(list!.map((r) => r[r'$id']).toList(), ['r2']);
  });

  test('a write held behind a conflict stays held on a later pass', () async {
    await queue.enqueue(
      collection: 'tickets',
      operation: 'update',
      payload: {'name': 'mine'},
      recordId: 'rec-1',
      userId: 'u1',
      baseline: {'name': 'before'},
      baseRevision: 3,
    );
    final first = (await queue.pendingForRecord('rec-1')).single;
    await queue.moveToConflict(
      first,
      const KoolbaseRevisionMismatchException(
        'the record has changed since you read it',
        expectedRevision: 3,
        currentRevision: 5,
        currentRecord: {'name': 'theirs', r'$revision': 5},
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await queue.enqueue(
      collection: 'tickets',
      operation: 'update',
      payload: {'name': 'later'},
      recordId: 'rec-1',
      userId: 'u1',
      baseline: {'name': 'mine'},
      baseRevision: 3,
    );

    final requests = <String>[];
    await http.runWithClient(
      () => engine().syncPendingWrites(),
      () => MockClient((req) async {
        requests.add('${req.method} ${req.url.path}');
        return respond(200, {r'$id': 'rec-1', r'$revision': 9});
      }),
    );

    expect(requests, isEmpty);
    expect((await queue.getPending()).single.recordId, 'rec-1');
  });
}
