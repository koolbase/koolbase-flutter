// R125 (A5): a shown record follows the app's own writes to its collection,
// as a list does -- online, the server's answer; offline, the device's saved
// copy, which holds the queued change. Before, it kept its old values until
// the screen was opened again.
import 'dart:convert';

import 'package:flutter/material.dart';
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
    switch (r.url.path) {
      case '/v1/sdk/auth/login':
        return json(200, {'access_token': 'at_1', 'refresh_token': 'rt_1', 'expires_at': '2099-01-01T00:00:00Z', 'user': user});
      case '/v1/sdk/db/records/r1':
        if (r.method == 'GET') return json(200, wire());
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        final expected = body['expected_revision'];
        if (expected != null && expected != revision) {
          return json(409, {
            'code': 'revision_mismatch',
            'error': 'the record has changed since you read it',
            'details': {'expected_revision': expected, 'current_revision': revision, 'record': {'title': title}},
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
    Koolbase.initializeForTesting(httpClient: server, offline: true);
  });
  tearDown(Koolbase.resetForTesting);

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
  }

  Widget view() => MaterialApp(
        home: Scaffold(
          body: KoolbaseRecordView(
            collection: 'notes',
            id: 'r1',
            builder: (context, r) => Text(r.data['title'] as String),
          ),
        ),
      );

  testWidgets('online: the record shows the server\'s answer, with no refresh asked for', (tester) async {
    await tester.runAsync(() => Koolbase.auth.login(email: 'ama@example.com', password: 'secret'));
    await tester.pumpWidget(view());
    await settle(tester);
    expect(find.text('Water plants'), findsOneWidget);
    await tester.runAsync(() => Koolbase.db.doc('r1').update({'title': 'Water the garden'}));
    await settle(tester);
    expect(find.text('Water the garden'), findsOneWidget);
  });

  testWidgets('offline: the record shows the queued change from the saved copy', (tester) async {
    await tester.runAsync(() => Koolbase.auth.login(email: 'ama@example.com', password: 'secret'));
    await tester.pumpWidget(view());
    await settle(tester);
    expect(find.text('Water plants'), findsOneWidget);
    online = false;
    await tester.runAsync(() => Koolbase.db.doc('r1').update({'title': 'Water the garden'}));
    await settle(tester);
    expect(find.text('Water the garden'), findsOneWidget);
    expect(title, 'Water plants', reason: 'nothing reached the server');
  });

  testWidgets('discarding a refused change shows the server\'s version, offline too', (tester) async {
    await tester.runAsync(() => Koolbase.auth.login(email: 'ama@example.com', password: 'secret'));
    await tester.pumpWidget(view());
    await settle(tester);
    online = false;
    await tester.runAsync(() => Koolbase.db.doc('r1').update({'title': 'Water the garden'}));
    await settle(tester);
    expect(find.text('Water the garden'), findsOneWidget);
    // Someone else changed it; back online the change is refused.
    title = 'Water the roses';
    revision = 2;
    online = true;
    await tester.runAsync(() => Koolbase.db.syncPendingWrites());
    final conflicts = (await tester.runAsync(() => Koolbase.db.conflicts()))!;
    expect(conflicts, hasLength(1));
    // Discard while offline: the saved copy shows the server's version.
    online = false;
    await tester.runAsync(() async {
      for (final c in conflicts) {
        await c.resolveWithServer();
      }
    });
    await settle(tester);
    expect(find.text('Water the roses'), findsOneWidget);
    expect(find.text('Water the garden'), findsNothing);
  });
}
