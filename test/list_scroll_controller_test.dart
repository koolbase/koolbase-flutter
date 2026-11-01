// 12.52.0 (A2.3): a list scrolls on the app's controller, so a "Back to top"
// can move it, and never disposes a controller it was given.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:koolbase_flutter/koolbase_flutter.dart';

void main() {
  tearDown(Koolbase.resetForTesting);

  testWidgets('the app\'s controller is the list\'s, and stays the app\'s', (tester) async {
    Koolbase.initializeForTesting(
      httpClient: MockClient(
        (r) async => http.Response(
          jsonEncode({'records': [], 'total': 0}),
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
    final controller = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KoolbaseCollectionList(
            collection: 'notes',
            scrollController: controller,
            itemBuilder: (context, record) => Text(record.id),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.hasClients, isTrue);
    await tester.pumpWidget(const SizedBox());
    // Still the app's: a disposed controller refuses a listener.
    expect(() => controller.addListener(() {}), returnsNormally);
    controller.dispose();
  });
}
