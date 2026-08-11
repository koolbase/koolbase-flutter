import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koolbase_flutter/koolbase_flutter.dart';

import 'support/fake_query.dart';

/// KoolbaseCollectionGrid behavioral tests.
///
/// Deliberately narrow: the grid shares KoolbaseCollectionController with the
/// list, and collection_list_test.dart already covers the properties that
/// justify the controller existing (SWR, fresh query per fetch, one
/// subscription per identity, stale beats blank). Re-testing those here would
/// be testing the same code twice.
///
/// What IS the grid's own: laying records out in a grid, and the loading,
/// empty and error slots firing at the right moments.
void main() {
  group('KoolbaseCollectionGrid widget', () {
    Widget app(
      KoolbaseCollectionController controller, {
      WidgetBuilder? empty,
      int crossAxisCount = 2,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: KoolbaseCollectionGrid(
            collection: 'expenses',
            controller: controller,
            crossAxisCount: crossAxisCount,
            empty: empty,
            itemBuilder: (context, record) => Text('TILE:${record.id}'),
          ),
        ),
      );
    }

    testWidgets('spinner first, then a tile per record', (tester) async {
      final refresh = StreamController<QueryResult>.broadcast();
      final completer = Completer<QueryResult>();
      final c = KoolbaseCollectionController(
        collection: 'expenses',
        baseQuery: () => FakeQuery(
          onGet: () => completer.future,
          refreshController: refresh,
        ),
      );

      await tester.pumpWidget(app(c));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      completer.complete(fakeResult(['a', 'b', 'c']));
      await tester.pump();

      expect(find.text('TILE:a'), findsOneWidget);
      expect(find.text('TILE:b'), findsOneWidget);
      expect(find.text('TILE:c'), findsOneWidget);
      expect(find.byType(GridView), findsOneWidget);

      await refresh.close();
      c.dispose();
    });

    testWidgets('an empty collection shows the empty slot', (tester) async {
      final refresh = StreamController<QueryResult>.broadcast();
      final c = KoolbaseCollectionController(
        collection: 'expenses',
        baseQuery: () => FakeQuery(
          onGet: () async => fakeResult(const []),
          refreshController: refresh,
        ),
      );

      await tester.pumpWidget(
        app(c, empty: (context) => const Text('NOTHING YET')),
      );
      await tester.pumpAndSettle();

      expect(find.text('NOTHING YET'), findsOneWidget);

      await refresh.close();
      c.dispose();
    });
  });
}
