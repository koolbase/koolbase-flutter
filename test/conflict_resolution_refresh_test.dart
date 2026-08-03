import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:koolbase_flutter/src/database/database_client.dart';
import 'package:koolbase_flutter/src/database/database_exceptions.dart';
import 'package:koolbase_flutter/src/database/offline/local_database.dart'
    hide PendingWrite;
import 'package:koolbase_flutter/src/database/offline/write_queue.dart';

/// A refused resolution must teach the stored conflict, not just gate it.
/// Device-proven on RN: conflict held at rev 8, server moved to rev 9,
/// resolution correctly refused — then refused again, identically, forever.
/// The 409 carried current_revision and the record; _resolveWrite threw them
/// away, so every retry replayed the stale condition. Same defect here.
void main() {
  late KoolbaseLocalDatabase db;
  late WriteQueue queue;
  late List<int?> sentRevisions;

  KoolbaseDatabaseClient clientWith(http.Client scripted) {
    final c = KoolbaseDatabaseClient(
      baseUrl: 'https://api.test',
      publicKey: 'pk_test',
      httpClient: scripted,
      writeQueue: queue,
    );
    return c;
  }

  http.Client scriptedServer() => MockClient((req) async {
        final body = req.body.isNotEmpty
            ? jsonDecode(req.body) as Map<String, dynamic>
            : const <String, dynamic>{};
        final rev = body['expected_revision'] as int?;
        sentRevisions.add(rev);
        if (rev == 8) {
          return http.Response(
            jsonEncode({
              'code': 'revision_mismatch',
              'error': 'the record has changed since you read it',
              'details': {
                'expected_revision': 8,
                'current_revision': 9,
                'record': {'amount': 3000},
              },
            }),
            409,
          );
        }
        return http.Response(
          jsonEncode({
            'record': {'id': 'rec-1', 'data': body['data'], 'revision': 10}
          }),
          200,
        );
      });

  setUp(() async {
    db = KoolbaseLocalDatabase.withExecutor(NativeDatabase.memory());
    queue = WriteQueue(db);
    sentRevisions = [];
    // Seed through the production path: a queued write refused with the
    // original 409 becomes the conflict — same route the sync engine takes.
    await queue.enqueue(
      collection: 'expenses',
      operation: 'update',
      payload: {'amount': 48},
      recordId: 'rec-1',
      userId: 'u1',
    );
    final write = (await queue.getPending()).single;
    await queue.moveToConflict(
      write,
      const KoolbaseRevisionMismatchException(
        'the record has changed since you read it',
        expectedRevision: 7,
        currentRevision: 8,
        currentRecord: {'amount': 10},
      ),
    );
  });

  tearDown(() => db.close());

  test('a refusal absorbs the 409, and the retry succeeds — [8, 9]', () async {
    final client = clientWith(scriptedServer());
    final conflicts = await client.conflicts();
    expect(conflicts, hasLength(1));

    // Attempt 1: refused — and the refusal teaches.
    await expectLater(
      conflicts.first.resolveWithLocal(),
      throwsA(isA<KoolbaseRevisionMismatchException>()
          .having((e) => e.currentRevision, 'currentRevision', 9)
          .having((e) => e.message, 'message', contains('review and retry'))),
    );
    final stored = await queue.conflicts();
    expect(stored.first.serverRevision, 9);
    expect(jsonDecode(stored.first.serverState!), {'amount': 3000});

    // Attempt 2: same conflict, server unmoved — succeeds against reality.
    final retry = await client.conflicts();
    await retry.first.resolveWithLocal();
    expect(sentRevisions, [8, 9]);
    expect(await queue.conflicts(), isEmpty);
  });

  test('a non-mismatch failure leaves the conflict untouched', () async {
    final client = clientWith(MockClient((req) async => http.Response(
        jsonEncode({'code': 'permission_denied', 'error': 'no'}), 403)));
    final conflicts = await client.conflicts();
    await expectLater(conflicts.first.resolveWithLocal(), throwsA(anything));
    expect((await queue.conflicts()).first.serverRevision, 8);
  });
}
