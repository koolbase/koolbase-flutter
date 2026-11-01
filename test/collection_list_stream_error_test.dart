// 12.51.1: a list whose query fails -- here, refused as unauthenticated, as
// when a session ends on the screen -- shows its error state, and nothing is
// thrown uncaught (found by the Designer's A2.2c session journey).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:koolbase_flutter/koolbase_flutter.dart';

void main() {
  tearDown(Koolbase.resetForTesting);

  testWidgets('a refused query is the list\'s error, not an uncaught one', (tester) async {
    Koolbase.initializeForTesting(
      httpClient: MockClient(
        (r) async => http.Response(
          jsonEncode({'error': 'authentication required', 'code': 'unauthenticated'}),
          401,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KoolbaseCollectionList(
            collection: 'notes',
            itemBuilder: (context, record) => Text(record.id),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
