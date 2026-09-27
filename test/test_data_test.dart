import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koolbase_flutter/koolbase_flutter.dart';
import 'package:koolbase_flutter/testing.dart';

/// KoolbaseTestData replaces only the data SOURCE; the production controllers,
/// paging, states and rendering run as in an app. Each test pumps a real
/// widget to a settled frame; any Flutter error fails it.

const _songs = {
  'songs': [
    {'id': 'cert-1', 'title': 'Short'},
    {'id': 'cert-2', 'title': 'A much longer title that has to wrap across the width of the row'},
    {'id': 'cert-3', 'title': 'Third'},
  ],
};

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: KoolbaseTestData(collections: _songs, child: child)),
);

Widget _row(BuildContext context, KoolbaseRecord r) =>
    Text(r.data['title'] as String);

void main() {
  testWidgets('a list pages the test data like the server: 2 rows and Load '
      'more, then all 3', (tester) async {
    await tester.pumpWidget(_host(SizedBox(
      height: 600,
      child: KoolbaseCollectionList(
        collection: 'songs',
        query: (q) => q.limit(2),
        itemBuilder: _row,
      ),
    )));
    await tester.pumpAndSettle();
    expect(find.text('Short'), findsOneWidget);
    expect(find.text('Third'), findsNothing);
    expect(find.text('Load more'), findsOneWidget);

    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();
    expect(find.text('Third'), findsOneWidget);
    expect(find.text('Load more'), findsNothing);
  });

  testWidgets('page mode inside a scrolling page, populated, lays out',
      (tester) async {
    await tester.pumpWidget(_host(SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Songs'),
          KoolbaseCollectionList(
            collection: 'songs',
            scrollsWithPage: true,
            itemBuilder: _row,
          ),
        ],
      ),
    )));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Third'), findsOneWidget);
  });

  testWidgets('a record view finds its record; an unknown id is not available',
      (tester) async {
    await tester.pumpWidget(_host(KoolbaseRecordView(
      collection: 'songs',
      id: 'cert-1',
      builder: _row,
    )));
    await tester.pumpAndSettle();
    expect(find.text('Short'), findsOneWidget);

    await tester.pumpWidget(_host(KoolbaseRecordView(
      collection: 'songs',
      id: 'nope',
      builder: _row,
    )));
    await tester.pumpAndSettle();
    expect(find.text('Not available.'), findsOneWidget);
  });
}
