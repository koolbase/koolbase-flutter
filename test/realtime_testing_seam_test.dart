// R122 (A5): Koolbase.initializeForTesting takes a realtimeConnector, so a
// test plays the realtime server. A live list -- with no test seam of its
// own, as a generated app builds it -- subscribes through the SDK's own
// realtime client, and someone else's change re-reads page one.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:koolbase_flutter/koolbase_flutter.dart';

Map<String, dynamic> _wire(String id, String title) => KoolbaseRecord(
      id: id,
      collection: 'tasks',
      createdBy: 'someone',
      data: {'title': title},
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      revision: 1,
    ).toJson();

void main() {
  tearDown(Koolbase.resetForTesting);

  testWidgets('a live list follows the realtime server a test plays', (tester) async {
    final rows = [('t1', 'Water plants')];
    var queries = 0;
    final incoming = StreamController<dynamic>();
    addTearDown(incoming.close);
    final sent = <Map<String, dynamic>>[];
    final opened = <Uri>[];

    Koolbase.initializeForTesting(
      httpClient: MockClient((req) async {
        if (req.url.path.endsWith('/v1/sdk/db/query')) {
          queries++;
          return http.Response(
            jsonEncode({
              'records': [for (final r in rows) _wire(r.$1, r.$2)],
              'total': rows.length,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{}', 200, headers: {'content-type': 'application/json'});
      }),
      realtimeConnector: (uri) {
        opened.add(uri);
        return RealtimeConnection(
          stream: incoming.stream,
          send: (m) => sent.add(jsonDecode(m) as Map<String, dynamic>),
          close: () {},
        );
      },
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: KoolbaseCollectionList(
          collection: 'tasks',
          live: true,
          itemBuilder: (context, r) => Text(r.data['title'] as String),
        ),
      ),
    ));
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
    expect(find.text('Water plants'), findsOneWidget);
    final before = queries;

    expect(opened.single.path, '/v1/realtime/ws');
    expect(opened.single.queryParameters['public_key'], 'pk_test',
        reason: 'signed out: the public key');
    expect(sent.where((m) => m['action'] == 'subscribe').map((m) => m['collection']), ['tasks']);

    // Someone else adds a task; the server says so.
    rows.insert(0, ('t2', 'Feed the cat'));
    incoming.add(jsonEncode({
      'type': 'db.record.created',
      'payload': {'collection': 'tasks', 'record': _wire('t2', 'Feed the cat')},
    }));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
    expect(find.text('Feed the cat'), findsOneWidget, reason: 'no tap: the list followed');
    expect(queries, before + 1, reason: 'page one read again, once');

    // The screen closes: the connection stays a moment (the idle grace)
    // for a screen that comes straight back, then unsubscribes.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
    expect(sent.where((m) => m['action'] == 'unsubscribe').map((m) => m['collection']), ['tasks']);
  });

  testWidgets('without a connector, realtime is still unset', (tester) async {
    Koolbase.initializeForTesting();
    expect(() => Koolbase.realtime, throwsA(anything));
  });
}
