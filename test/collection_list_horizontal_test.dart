import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koolbase_flutter/koolbase_flutter.dart';

import 'support/fake_query.dart';

/// KoolbaseCollectionList(scrollDirection: Axis.horizontal) (12.19.0): rows
/// side by side, as tall as the tallest, scrolling sideways; separators
/// between rows only; the next page loads as the end comes near, and Load
/// more stays as the last item. It lays out inside a vertically scrolling
/// page without being given a height.

KoolbaseCollectionController _controller(
  Future<QueryResult> Function() onGet,
) {
  final refresh = StreamController<QueryResult>.broadcast();
  addTearDown(refresh.close);
  return KoolbaseCollectionController(
    collection: 'expenses',
    baseQuery: () => FakeQuery(onGet: onGet, refreshController: refresh),
  );
}

QueryResult _page(List<String> ids, {required int total}) => QueryResult(
      records: [for (final id in ids) fakeRecord(id)],
      total: total,
    );

Widget _row(KoolbaseRecord r) => SizedBox(
      width: 160,
      // Different natural heights: the row is as tall as the tallest.
      height: r.id == 'b' ? 80 : 40,
      child: Text(r.data['title'] as String),
    );

Widget _app(
  KoolbaseCollectionController c, {
  bool scrollingPage = false,
  IndexedWidgetBuilder? separator,
}) {
  final list = KoolbaseCollectionList(
    collection: 'expenses',
    controller: c,
    scrollDirection: Axis.horizontal,
    separatorBuilder: separator,
    itemBuilder: (context, r) => _row(r),
  );
  return MaterialApp(
    home: Scaffold(
      body: scrollingPage
          ? SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [const Text('Discover'), list, const Text('After')],
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [list],
            ),
    ),
  );
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('rows sit side by side, as tall as the tallest', (tester) async {
    final c = _controller(() async => _page(['a', 'b', 'c'], total: 3));
    await tester.pumpWidget(_app(c));
    await _settle(tester);
    expect(tester.takeException(), isNull);
    final a = tester.getRect(find.text('a'));
    final b = tester.getRect(find.text('b'));
    expect(a.top, b.top);
    expect(b.left, greaterThan(a.right));
    final rowA = tester.getSize(find
        .ancestor(of: find.text('a'), matching: find.byType(SizedBox))
        .first);
    expect(rowA.height, 80, reason: 'stretched to the tallest row');
  });

  testWidgets('inside a vertically scrolling page, with no height given',
      (tester) async {
    final c = _controller(() async => _page(['a', 'b'], total: 2));
    await tester.pumpWidget(_app(c, scrollingPage: true));
    await _settle(tester);
    expect(tester.takeException(), isNull);
    final b = tester.getRect(find.text('b'));
    final after = tester.getRect(find.text('After'));
    expect(after.top, greaterThanOrEqualTo(b.top + 80 - 0.5),
        reason: 'the list is as tall as its tallest row');
  });

  testWidgets('the default separator is a vertical line between rows only',
      (tester) async {
    final c = _controller(() async => _page(['a', 'b', 'c'], total: 3));
    await tester.pumpWidget(_app(c));
    await _settle(tester);
    expect(find.byType(VerticalDivider), findsNWidgets(2));
  });

  testWidgets('a separator builder gets each gap\'s index', (tester) async {
    final seen = <int>[];
    final c = _controller(() async => _page(['a', 'b', 'c'], total: 3));
    await tester.pumpWidget(_app(c, separator: (context, i) {
      seen.add(i);
      return const SizedBox(width: 8);
    }));
    await _settle(tester);
    expect(seen, [0, 1]);
  });

  testWidgets('Load more is the last item while there are more',
      (tester) async {
    final c = _controller(() async => _page(['a', 'b'], total: 9));
    await tester.pumpWidget(_app(c));
    await _settle(tester);
    expect(find.text('Load more'), findsOneWidget);
    final more = tester.getRect(find.text('Load more'));
    expect(more.left, greaterThan(tester.getRect(find.text('b')).right));
  });

  testWidgets('scrolling near the end loads the next page', (tester) async {
    var gets = 0;
    final c = _controller(() async {
      gets++;
      return _page(['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'], total: 20);
    });
    await tester.pumpWidget(_app(c));
    await _settle(tester);
    expect(gets, 1);
    await tester.drag(
        find.byType(SingleChildScrollView), const Offset(-2000, 0));
    await _settle(tester);
    expect(gets, greaterThan(1));
  });

  testWidgets('empty: the empty slot, laid out', (tester) async {
    final c = _controller(() async => _page([], total: 0));
    await tester.pumpWidget(_app(c, scrollingPage: true));
    await _settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Nothing here yet.'), findsOneWidget);
  });

  testWidgets('vertical stays the default', (tester) async {
    final c = _controller(() async => _page(['a', 'b'], total: 2));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: KoolbaseCollectionList(
          collection: 'expenses',
          controller: c,
          itemBuilder: (context, r) => Text(r.data['title'] as String),
        ),
      ),
    ));
    await _settle(tester);
    expect(tester.getRect(find.text('b')).top,
        greaterThan(tester.getRect(find.text('a')).bottom - 0.5));
  });
}
