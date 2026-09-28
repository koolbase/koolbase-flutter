import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koolbase_flutter/koolbase_flutter.dart';
import 'package:koolbase_flutter/testing.dart';

/// KoolbaseCollectionGrid inside a SCROLLING page, the body every new screen
/// in the Designer gets (KB-CERT-008).
const _songs = {
  'songs': [
    {'id': 'cert-1', 'title': 'One'},
    {'id': 'cert-2', 'title': 'Two'},
    {'id': 'cert-3', 'title': 'Three'},
  ],
};

Widget _page(Widget grid, {Map<String, List<Map<String, Object?>>> data = _songs}) =>
    MaterialApp(
      home: Scaffold(
        body: KoolbaseTestData(
          collections: data,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [const Text('Songs'), grid],
            ),
          ),
        ),
      ),
    );

Widget _cell(BuildContext context, KoolbaseRecord r) =>
    Center(child: Text(r.data['title'] as String));

void main() {
  testWidgets('an empty grid lays out inside a scrolling page', (t) async {
    await t.pumpWidget(_page(
      KoolbaseCollectionGrid(collection: 'songs', crossAxisCount: 2, itemBuilder: _cell),
      data: const {'songs': []},
    ));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.text('Nothing here yet'), findsOneWidget);
  });

  testWidgets('page mode: the cells and Load more, then all of them', (t) async {
    await t.pumpWidget(_page(KoolbaseCollectionGrid(
      collection: 'songs',
      crossAxisCount: 2,
      scrollsWithPage: true,
      query: (q) => q.limit(2),
      itemBuilder: _cell,
    )));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.text('One'), findsOneWidget);
    expect(find.text('Three'), findsNothing);
    await t.tap(find.text('Load more'));
    await t.pumpAndSettle();
    expect(find.text('Three'), findsOneWidget);
    expect(find.byType(RefreshIndicator), findsNothing);
  });

  testWidgets('the default mode WITH records throws inside a scrolling page '
      '(why page mode exists)', (t) async {
    await t.pumpWidget(_page(
      KoolbaseCollectionGrid(collection: 'songs', crossAxisCount: 2, itemBuilder: _cell),
    ));
    await t.pumpAndSettle();
    expect(t.takeException(), isNotNull);
  });
}
