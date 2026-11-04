// R121 (A5): a list that scrolls by itself loads its next page when the
// person nears the end -- or at once, when its page is too short to fill it
// -- as on Expo and the web; Load more stays for a page that failed. In a
// scrolling page (every row built at once) Load more is a button only.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koolbase_flutter/koolbase_flutter.dart';

import 'support/fake_query.dart';

/// A controller over [total] records, [page] at a time, counting the gets.
({KoolbaseCollectionController c, List<int> gets}) _paged(int total, int page) {
  final refresh = StreamController<QueryResult>.broadcast();
  addTearDown(refresh.close);
  final gets = <int>[];
  final all = [for (var i = 0; i < total; i++) fakeRecord('r$i')];
  final c = KoolbaseCollectionController(
    collection: 'expenses',
    baseQuery: () => FakeQuery(
      refreshController: refresh,
      onGet: () async {
        final from = gets.length * page;
        gets.add(from);
        return QueryResult(records: all.skip(from).take(page).toList(), total: total);
      },
    ),
  );
  return (c: c, gets: gets);
}

Widget _list(KoolbaseCollectionController c, {bool page = false}) => KoolbaseCollectionList(
      collection: 'expenses',
      controller: c,
      scrollsWithPage: page,
      itemBuilder: (context, r) => SizedBox(height: 50, child: Text(r.data['title'] as String)),
    );

Widget _app(Widget body) => MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: 400, height: 600, child: body),
        ),
      ),
    );

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump();
  }
}

void main() {
  testWidgets('a short page: the next one loads by itself', (tester) async {
    final p = _paged(4, 2);
    await tester.pumpWidget(_app(_list(p.c)));
    await _settle(tester);
    expect(find.text('r3'), findsOneWidget, reason: 'page two arrived without a tap');
    expect(find.text('Load more'), findsNothing, reason: 'nothing more to load');
    expect(p.gets, [0, 2]);
  });

  testWidgets('a long page: nothing more until the person nears the end', (tester) async {
    final p = _paged(40, 20);
    await tester.pumpWidget(_app(_list(p.c)));
    await _settle(tester);
    expect(p.gets, [0], reason: 'twenty rows overflow the list: page two waits');
    await tester.drag(find.byType(ListView), const Offset(0, -2000));
    await _settle(tester);
    expect(p.gets, [0, 20], reason: 'near the end, page two loaded by itself');
    expect(find.text('r39'), findsNothing, reason: 'below the fold until scrolled');
  });

  testWidgets('in a scrolling page, Load more is a button only', (tester) async {
    final p = _paged(4, 2);
    await tester.pumpWidget(_app(SingleChildScrollView(child: _list(p.c, page: true))));
    await _settle(tester);
    expect(p.gets, [0], reason: 'every row is built at once there: no automatic page');
    expect(find.text('Load more'), findsOneWidget);
    await tester.tap(find.text('Load more'));
    await _settle(tester);
    expect(find.text('r3'), findsOneWidget);
  });
}
