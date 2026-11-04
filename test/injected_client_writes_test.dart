// R120 (A5): every data call goes through the client the database client
// was given -- in an app, KoolbaseSessionClient, which renews an expired
// session and retries once; in a test, its fake. insert, aggregate, upsert,
// deleteWhere and batch went straight to package:http, so an insert made
// with a token that had just expired failed as unauthorized instead of
// renewing, and a test's fake was never asked.
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:koolbase_flutter/koolbase_flutter.dart' show Koolbase;
import 'package:koolbase_flutter/src/database/aggregate.dart';
import 'package:koolbase_flutter/src/database/database_client.dart';
import 'package:koolbase_flutter/src/database/database_models.dart';

void main() {
  test('insert, aggregate, upsert, deleteWhere and batch use the given client', () async {
    final asked = <String>[];
    final db = KoolbaseDatabaseClient(
      baseUrl: 'https://api.test',
      publicKey: 'pk_test',
      // Refused, so nothing parses an answer: only where each call went
      // matters here.
      httpClient: MockClient((req) async {
        asked.add(req.url.path);
        return http.Response('{"error":"refused"}', 403, headers: {'content-type': 'application/json'});
      }),
    );
    Future<void> attempt(Future<Object?> Function() call) async {
      try {
        await call();
      } catch (_) {}
    }

    await attempt(() => db.insert(collection: 'tasks', data: {'title': 'a'}));
    await attempt(() => db.aggregate(const KoolbaseAggregate(collection: 'tasks', measures: [KoolbaseMeasure.count(as: 'n')])));
    await attempt(() => db.upsert(collection: 'tasks', match: {'title': 'a'}, data: {'title': 'b'}));
    await attempt(() => db.deleteWhere(collection: 'tasks', filters: {'title': 'a'}));
    await attempt(() => db.batch([KoolbaseBatchOp.insert('tasks', {'title': 'a'})]));
    expect(asked, [
      '/v1/sdk/db/insert',
      '/v1/sdk/db/aggregate',
      '/v1/sdk/db/upsert',
      '/v1/sdk/db/delete-where',
      '/v1/sdk/db/batch',
    ]);
  });

  test('Koolbase.initializeForTesting answers Functions through the client it was given', () async {
    final asked = <String>[];
    Koolbase.initializeForTesting(
      httpClient: MockClient((req) async {
        asked.add(req.url.path);
        return http.Response('{"ok":true}', 200, headers: {'content-type': 'application/json'});
      }),
    );
    addTearDown(Koolbase.resetForTesting);
    final r = await Koolbase.functions.invoke('plan_week');
    expect(r.success, isTrue);
    expect(asked, ['/v1/sdk/functions/plan_week']);
  });
}
