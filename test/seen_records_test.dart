import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:koolbase_flutter/koolbase_flutter.dart';
import 'package:koolbase_flutter/src/database/seen_records.dart';

// #103: a detail screen opened from a list shows the record at once, even
// where there is no offline storage (the web build, Run). The list's records
// are kept in memory; getSaved answers from them while the server is asked.

Map<String, dynamic> _wire(String id, String title, {int revision = 1}) => {
      r'$id': id,
      r'$collection': 'events',
      r'$createdAt': '2026-10-01T00:00:00Z',
      r'$updatedAt': '2026-10-01T00:00:00Z',
      r'$revision': revision,
      'title': title,
    };

KoolbaseQuery _query(http.Client client, {String? user = 'u1'}) =>
    KoolbaseQuery(
      baseUrl: 'https://api.test',
      publicKey: 'pk',
      collectionName: 'events',
      userId: user,
      client: client,
    );

KoolbaseDocRef _doc(String id, http.Client client, {String? user = 'u1'}) =>
    KoolbaseDocRef(
      baseUrl: 'https://api.test',
      publicKey: 'pk',
      recordId: id,
      userId: user,
      client: client,
    );

void main() {
  setUp(SeenRecords.clear);

  test('a record a list showed is there at once for its detail screen',
      () async {
    var calls = 0;
    final client = MockClient((req) async {
      calls++;
      return http.Response(
          jsonEncode({
            'records': [_wire('e1', 'Launch night'), _wire('e2', 'Open mic')],
            'total': 2,
          }),
          200);
    });
    await _query(client).get();
    final saved = await _doc('e1', client).getSaved();
    expect(saved?.data['title'], 'Launch night');
    expect(saved?.collection, 'events');
    expect(saved?.revision, 1);
    expect(calls, 1, reason: 'getSaved never asks the server');
    expect(await _doc('never-listed', client).getSaved(), isNull);
  });

  test('another person on the same device never sees it', () async {
    final client = MockClient((req) async => http.Response(
        jsonEncode({
          'records': [_wire('e1', 'Mine')],
          'total': 1
        }),
        200));
    await _query(client, user: 'u1').get();
    expect(await _doc('e1', client, user: 'u2').getSaved(), isNull);
    expect(await _doc('e1', client, user: null).getSaved(), isNull);
  });

  test('a record read by id is kept too, and an older copy never replaces it',
      () async {
    final client = MockClient((req) async =>
        http.Response(jsonEncode(_wire('e1', 'New title', revision: 3)), 200));
    await _doc('e1', client).get();
    final older =
        KoolbaseRecord.fromJson(_wire('e1', 'Old title', revision: 2));
    SeenRecords.remember('u1', older);
    expect((await _doc('e1', client).getSaved())?.data['title'], 'New title');
  });

  test('signing out forgets everything; the oldest goes first when full', () {
    for (var i = 0; i < SeenRecords.capacity + 1; i++) {
      SeenRecords.remember('u1', KoolbaseRecord.fromJson(_wire('r$i', 't$i')));
    }
    expect(SeenRecords.recall('u1', 'r0'), isNull);
    expect(SeenRecords.recall('u1', 'r1')?.data['title'], 't1');
    SeenRecords.clear();
    expect(SeenRecords.recall('u1', 'r1'), isNull);
  });
}
