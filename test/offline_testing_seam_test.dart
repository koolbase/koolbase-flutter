// R124 (A5): Koolbase.initializeForTesting(offline: true) sets up the offline
// layer as an app's is, on an in-memory database: a change the network fails
// is queued, Koolbase.db.syncPendingWrites() replays it through the test's
// client (standing in for the device reconnecting), and a change the server
// refuses -- the record changed elsewhere -- becomes a conflict that keeping
// the server's version clears.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:koolbase_flutter/koolbase_flutter.dart';

void main() {
  const user = {
    'id': 'usr_t',
    'project_id': 'prj_t',
    'email': 'ama@example.com',
    'full_name': 'Ama Mensah',
    'verified': true,
    'disabled': false,
    'providers': <String>[],
    'created_at': '2026-11-01T00:00:00Z',
    'updated_at': '2026-11-01T00:00:00Z',
  };
  http.Response json(int status, Object body) =>
      http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

  var online = true;
  var title = 'Water plants';
  var revision = 1;
  final calls = <String>[];
  Map<String, dynamic> wire() => KoolbaseRecord(
        id: 'r1',
        collection: 'notes',
        createdBy: 'usr_t',
        data: {'title': title},
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
        revision: revision,
      ).toJson();

  final server = MockClient((r) async {
    if (!online && r.url.path.startsWith('/v1/sdk/db/')) {
      throw http.ClientException('network is unreachable', r.url);
    }
    calls.add('${r.method} ${r.url.path}');
    switch (r.url.path) {
      case '/v1/sdk/auth/login':
        return json(200, {'access_token': 'at_1', 'refresh_token': 'rt_1', 'expires_at': '2099-01-01T00:00:00Z', 'user': user});
      case '/v1/sdk/db/query':
        return json(200, {'records': [wire()], 'total': 1});
      case '/v1/sdk/db/records/r1':
        if (r.method == 'GET') return json(200, wire());
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        if (body['expected_revision'] != revision) {
          return json(409, {
            'code': 'revision_mismatch',
            'error': 'the record has changed since you read it',
            'details': {'expected_revision': body['expected_revision'], 'current_revision': revision, 'record': {'title': title}},
          });
        }
        title = (body['data'] as Map)['title'] as String;
        revision++;
        return json(200, wire());
    }
    return json(404, {'error': 'not found', 'code': 'not_found'});
  });

  setUp(() {
    online = true;
    title = 'Water plants';
    revision = 1;
    calls.clear();
    Koolbase.initializeForTesting(httpClient: server, offline: true);
  });
  tearDown(Koolbase.resetForTesting);

  test('an offline change, refused on replay, becomes a conflict; keeping theirs clears it', () async {
    await Koolbase.auth.login(email: 'ama@example.com', password: 'secret');
    final first = await Koolbase.db.collection('notes').get(fresh: true);
    expect(first.records.single.data['title'], 'Water plants');

    // Offline: the change is queued.
    online = false;
    await Koolbase.db.doc('r1').update({'title': 'Water the garden'});
    expect(await Koolbase.db.pendingWrites(), hasLength(1));

    // Meanwhile someone else changed it; the device reconnects.
    title = 'Water the roses';
    revision = 2;
    online = true;
    await Koolbase.db.syncPendingWrites();
    expect(calls.where((c) => c == 'PATCH /v1/sdk/db/records/r1'), hasLength(1), reason: 'replayed once: $calls');
    final conflicts = await Koolbase.db.conflicts();
    expect(conflicts, hasLength(1), reason: 'the refused change is a conflict');

    // Discard: keep the server's version.
    for (final c in conflicts) {
      await c.resolveWithServer();
    }
    expect(await Koolbase.db.conflicts(), isEmpty);
    expect(await Koolbase.db.pendingWrites(), isEmpty);
    expect(title, 'Water the roses', reason: 'nothing was sent over theirs');
  });

  test('without offline, nothing is queued: a failed write fails', () async {
    Koolbase.resetForTesting();
    Koolbase.initializeForTesting(httpClient: server);
    await Koolbase.auth.login(email: 'ama@example.com', password: 'secret');
    online = false;
    await expectLater(Koolbase.db.doc('r1').update({'title': 'x'}), throwsA(anything));
  });
}
