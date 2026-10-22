// #194: a list and a grid read again when their query's filters change --
// a chip chosen -- and only then. (Test data never filters, so the rows a
// filter returns are the server's to prove; this proves the read happens.)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koolbase_flutter/koolbase_flutter.dart';
import 'package:koolbase_flutter/testing.dart';

const events = {
  'events': [
    {'id': 'e1', 'title': 'Neon Nights', 'category': 'Music'},
    {'id': 'e2', 'title': 'Builders & Coffee', 'category': 'Tech'},
  ],
};

final data = KoolbaseTestData(collections: events, child: const SizedBox());

KoolbaseCollectionController controller() => KoolbaseCollectionController(
      collection: 'events',
      baseQuery: () => data.queryFor('events'),
    );

KoolbaseQueryBuilder byCategory(String c) =>
    (q) => c.isEmpty ? q : q.where('category', isEqualTo: c);

void main() {
  testWidgets('the controller reads again only when the filters change',
      (tester) async {
    final c = controller();
    await c.load();
    var reads = 0;
    c.addListener(() => reads++);

    c.setQuery(byCategory(''));
    await tester.pump();
    expect(reads, 0, reason: 'no filter, as before: nothing to read');

    c.setQuery(byCategory('Music'));
    await tester.pump();
    expect(reads, greaterThan(0), reason: 'a chip chosen: read again');

    reads = 0;
    c.setQuery(byCategory('Music'));
    await tester.pump();
    expect(reads, 0, reason: 'the same filters in a new closure: nothing');
    c.dispose();
  });

  for (final grid in [false, true]) {
    testWidgets(
        '${grid ? 'a grid' : 'a list'} hands a changed query to its controller',
        (tester) async {
      final c = controller();
      final category = ValueNotifier<String>('');
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<String>(
            valueListenable: category,
            builder: (context, v, _) => grid
                ? KoolbaseCollectionGrid(
                    collection: 'events',
                    controller: c,
                    query: byCategory(v),
                    itemBuilder: (context, r) => Text('${r.data['title']}'),
                  )
                : KoolbaseCollectionList(
                    collection: 'events',
                    controller: c,
                    query: byCategory(v),
                    itemBuilder: (context, r) => Text('${r.data['title']}'),
                  ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      var reads = 0;
      c.addListener(() => reads++);

      category.value = 'Music';
      await tester.pumpAndSettle();
      expect(reads, greaterThan(0), reason: 'the chip reached the query');

      reads = 0;
      category.value = 'Music';
      await tester.pumpAndSettle();
      expect(reads, 0);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
  }
}
