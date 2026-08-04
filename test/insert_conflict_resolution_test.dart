import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:koolbase_flutter/src/database/conflict.dart';
import 'package:koolbase_flutter/src/database/database_client.dart';
import 'package:koolbase_flutter/src/database/offline/local_database.dart'
    hide PendingWrite;
import 'package:koolbase_flutter/src/database/offline/write_queue.dart';

/// Unique constraints made insert-conflicts real: a queued insert refused as a
/// duplicate is held like any other terminal refusal — and until this change,
/// the client coerced its operation to `update`, and resolving it issued a
/// PATCH against a record id that exists nowhere. Resolving a rejected insert
/// IS the insert, retried: unconditional (no record, no revision), carrying
/// the conflict's id as the idempotency key so a lost response cannot
/// duplicate on retry.
void main() {
  late KoolbaseLocalDatabase db;
  late WriteQueue queue;
  late List<http.Request> requests;

  KoolbaseDatabaseClient clientWith(http.Client scripted) =>
      KoolbaseDatabaseClient(
        baseUrl: 'https://api.test',
        publicKey: 'pk_test',
        httpClient: scripted,
        writeQueue: queue,
      );

  http.Client scriptedServer() => MockClient((req) async {
        requests.add(req);
        if (req.method == 'POST' && req.url.path == '/v1/sdk/db/insert') {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'record': {'id': 'srv-1', 'data': body['data'], 'revision': 1}
            }),
            201,
          );
        }
        // Any other route is the regression this file exists to prevent —
        // e.g. the pre-fix PATCH against a nonexistent record. Refuse loudly.
        return http.Response(
          jsonEncode({'code': 'wrong_route', 'error': 'unexpected ${req.method} ${req.url.path}'}),
          500,
        );
      });

  setUp(() async {
    db = KoolbaseLocalDatabase.withExecutor(NativeDatabase.memory());
    queue = WriteQueue(db);
    requests = [];
    // Seed through the production path: a queued insert, terminally refused.
    await queue.enqueue(
      collection: 'expenses',
      operation: 'insert',
      payload: {'title': 'COLLIDE', 'amount': 5},
      recordId: 'local-rec-1',
      userId: 'u1',
    );
    final write = (await queue.getPending()).single;
    await queue.moveToRejected(write, 'value violates a unique constraint');
  });

  tearDown(() => db.close());

  test('a rejected insert surfaces as ConflictOperation.insert', () async {
    final conflicts = await clientWith(scriptedServer()).conflicts();
    expect(conflicts.single.operation, ConflictOperation.insert);
  });

  test('resolveWithMerge IS the insert, retried — amended data, conflict-id key',
      () async {
    final client = clientWith(scriptedServer());
    final c = (await client.conflicts()).single;
    await c.resolveWithMerge({'title': 'FIXED', 'amount': 5});

    expect(requests, hasLength(1));
    final req = requests.single;
    expect(req.method, 'POST');
    expect(req.url.path, '/v1/sdk/db/insert');
    final body = jsonDecode(req.body) as Map<String, dynamic>;
    expect(body['data'], {'title': 'FIXED', 'amount': 5});
    expect(body['idempotency_key'], c.id);
    expect(await queue.conflicts(), isEmpty);
  });

  test('resolveWithServer clears with zero requests — the colliding row stands',
      () async {
    final client = clientWith(scriptedServer());
    final c = (await client.conflicts()).single;
    await c.resolveWithServer();
    expect(requests, isEmpty);
    expect(await queue.conflicts(), isEmpty);
  });
}
