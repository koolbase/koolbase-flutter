import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koolbase_flutter/koolbase_flutter.dart';

import 'support/fake_query.dart';

/// KoolbaseCollectionList(groupBy:) (12.20.0): a header above each run of
/// records with the same key; pinned while the list scrolls by itself,
/// inline in a scrolling page; Load more rows join the last section;
/// separators within a section only.

KoolbaseRecord _rec(String id, String day) => KoolbaseRecord(
      id: id,
      collection: 'events',
      createdBy: 'u1',
      data: {'title': id, 'day': day},
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      revision: 1,
    );

/// Records named by day: 'Mon:a' is record a on Mon.
List<KoolbaseRecord> _recs(List<String> specs) => [
      for (final s in specs) _rec(s.split(':')[1], s.split(':')[0]),
    ];

KoolbaseCollectionController _controller(
  List<List<KoolbaseRecord>> pages, {
  required int total,
}) {
  final refresh = StreamController<QueryResult>.broadcast();
  addTearDown(refresh.close);
  var call = 0;
  return KoolbaseCollectionController(
    collection: 'events',
    baseQuery: () => FakeQuery(
      collection: 'events',
      refreshController: refresh,
      onGet: () async {
        final page = pages[call < pages.length ? call : pages.length - 1];
        call++;
        return QueryResult(records: page, total: total);
      },
    ),
  );
}

String _day(KoolbaseRecord r) => r.data['day'] as String;

Widget _list(
  KoolbaseCollectionController c, {
  bool scrollsWithPage = false,
  IndexedWidgetBuilder? separator,
  Widget Function(BuildContext, String)? header,
  EdgeInsetsGeometry? padding,
  double rowHeight = 50,
  bool grouped = true,
}) =>
    KoolbaseCollectionList(
      collection: 'events',
      controller: c,
      scrollsWithPage: scrollsWithPage,
      separatorBuilder: separator,
      sectionHeaderBuilder: header,
      padding: padding,
      groupBy: grouped ? _day : null,
      itemBuilder: (context, r) => SizedBox(
        height: rowHeight,
        child: Text(r.data['title'] as String),
      ),
    );

Widget _app(Widget body, {double height = 600}) => MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: 400, height: height, child: body),
        ),
      ),
    );

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

double _top(WidgetTester tester, String text) =>
    tester.getRect(find.text(text)).top;

/// The top of the header whose label is [label].
double _headerTop(WidgetTester tester, String label) => tester
    .getRect(find.ancestor(
      of: find.text(label),
      matching: find.byType(KoolbaseSectionHeader),
    ))
    .top;

void main() {
  testWidgets('a header above each run, in order', (tester) async {
    final c = _controller([
      _recs(['Mon:a', 'Mon:b', 'Tue:c']),
    ], total: 3);
    await tester.pumpWidget(_app(_list(c)));
    await _settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.byType(KoolbaseSectionHeader), findsNWidgets(2));
    expect(find.text('Mon'), findsOneWidget);
    expect(find.text('Tue'), findsOneWidget);
    expect(_top(tester, 'Mon'), lessThan(_top(tester, 'a')));
    expect(_top(tester, 'a'), lessThan(_top(tester, 'b')));
    expect(_top(tester, 'b'), lessThan(_top(tester, 'Tue')));
    expect(_top(tester, 'Tue'), lessThan(_top(tester, 'c')));
  });

  testWidgets('a key that comes back starts a new section', (tester) async {
    final c = _controller([
      _recs(['Mon:a', 'Tue:b', 'Mon:c']),
    ], total: 3);
    await tester.pumpWidget(_app(_list(c)));
    await _settle(tester);
    expect(find.text('Mon'), findsNWidgets(2));
    expect(find.text('Tue'), findsOneWidget);
  });

  testWidgets('Load more rows join the last section', (tester) async {
    final c = _controller([
      _recs(['Mon:a', 'Tue:b']),
      _recs(['Tue:c', 'Wed:d']),
    ], total: 4);
    await tester.pumpWidget(_app(_list(c)));
    await _settle(tester);
    expect(find.text('Load more'), findsOneWidget);
    expect(
      _top(tester, 'Load more'),
      greaterThan(_top(tester, 'b')),
      reason: 'Load more comes after the last row',
    );
    await tester.tap(find.text('Load more'));
    await _settle(tester);
    expect(find.text('c'), findsOneWidget);
    expect(find.text('Tue'), findsOneWidget, reason: 'one Tue header');
    expect(find.text('Wed'), findsOneWidget);
    expect(find.text('Load more'), findsNothing);
  });

  testWidgets('separators sit between rows of a section only', (tester) async {
    final c = _controller([
      _recs(['Mon:a', 'Mon:b', 'Mon:c', 'Tue:d', 'Tue:e']),
    ], total: 5);
    await tester.pumpWidget(_app(_list(c)));
    await _settle(tester);
    expect(find.byType(Divider), findsNWidgets(3));
  });

  testWidgets('a separator builder gets the index of the row before',
      (tester) async {
    final seen = <int>[];
    final c = _controller([
      _recs(['Mon:a', 'Mon:b', 'Mon:c', 'Tue:d', 'Tue:e']),
    ], total: 5);
    await tester.pumpWidget(_app(_list(c, separator: (context, i) {
      seen.add(i);
      return const SizedBox(height: 4);
    })));
    await _settle(tester);
    expect(seen.toSet(), {0, 1, 3});
  });

  testWidgets('the header stays pinned while its section scrolls',
      (tester) async {
    final c = _controller([
      _recs([
        for (var i = 0; i < 12; i++) 'Mon:m$i',
        for (var i = 0; i < 12; i++) 'Tue:t$i',
      ]),
    ], total: 24);
    await tester.pumpWidget(_app(_list(c), height: 300));
    await _settle(tester);
    expect(_top(tester, 'Mon'), lessThan(_top(tester, 'm0')));

    // Into the middle of Mon: its header holds the top.
    final position =
        tester.state<ScrollableState>(find.byType(Scrollable)).position;
    position.jumpTo(250);
    await tester.pump();
    final listTop = tester.getRect(find.byType(CustomScrollView)).top;
    expect(_headerTop(tester, 'Mon'), moreOrLessEquals(listTop, epsilon: 0.5));
    expect(find.text('m0').hitTestable(), findsNothing,
        reason: 'the first row has scrolled away under the header');

    // Into the middle of Tue: Tue's header holds the top, Mon's has gone.
    position.jumpTo(800);
    await tester.pump();
    expect(_headerTop(tester, 'Tue'), moreOrLessEquals(listTop, epsilon: 0.5));
    expect(find.text('Mon').hitTestable(), findsNothing,
        reason: 'pushed away with its section');
  });

  testWidgets('in a scrolling page: headers inline, no error', (tester) async {
    final c = _controller([
      _recs(['Mon:a', 'Tue:b']),
    ], total: 2);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Top'),
              _list(c, scrollsWithPage: true),
              const Text('After'),
            ],
          ),
        ),
      ),
    ));
    await _settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.byType(CustomScrollView), findsNothing);
    expect(_top(tester, 'Mon'), lessThan(_top(tester, 'a')));
    expect(_top(tester, 'Tue'), greaterThan(_top(tester, 'a')));
    expect(_top(tester, 'After'),
        greaterThanOrEqualTo(_top(tester, 'b') + 50 - 0.5));
  });

  testWidgets('a header builder builds each header from its key',
      (tester) async {
    final c = _controller([
      _recs(['Mon:a', 'Tue:b']),
    ], total: 2);
    await tester.pumpWidget(_app(_list(
      c,
      header: (context, key) => Text('Day $key'),
    )));
    await _settle(tester);
    expect(find.text('Day Mon'), findsOneWidget);
    expect(find.text('Day Tue'), findsOneWidget);
    expect(find.byType(KoolbaseSectionHeader), findsNothing);
  });

  testWidgets('the default header is a heading on an opaque background',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: KoolbaseSectionHeader(label: 'Today')),
    ));
    expect(find.text('Today'), findsOneWidget);
    final semantics = tester.widget<Semantics>(find
        .descendant(
          of: find.byType(KoolbaseSectionHeader),
          matching: find.byType(Semantics),
        )
        .first);
    expect(semantics.properties.header, isTrue);
    final box = tester.widget<ColoredBox>(find.descendant(
      of: find.byType(KoolbaseSectionHeader),
      matching: find.byType(ColoredBox),
    ));
    final theme = Theme.of(tester.element(find.byType(KoolbaseSectionHeader)));
    expect(box.color, theme.scaffoldBackgroundColor,
        reason: 'opaque, so rows do not show through a pinned header');
  });

  testWidgets('padding insets rows and headers', (tester) async {
    final c = _controller([
      _recs(['Mon:a']),
    ], total: 1);
    await tester.pumpWidget(_app(_list(
      c,
      padding: const EdgeInsets.fromLTRB(12, 20, 12, 0),
    )));
    await _settle(tester);
    final list = tester.getRect(find.byType(CustomScrollView));
    expect(tester.getRect(find.text('a')).left, list.left + 12);
    expect(
        tester.getRect(find.byType(KoolbaseSectionHeader)).top, list.top + 20);
  });

  testWidgets('without groupBy: no headers, as before', (tester) async {
    final c = _controller([
      _recs(['Mon:a', 'Tue:b']),
    ], total: 2);
    await tester.pumpWidget(_app(_list(c, grouped: false)));
    await _settle(tester);
    expect(find.byType(KoolbaseSectionHeader), findsNothing);
    expect(find.byType(ListView), findsOneWidget);
    expect(find.byType(Divider), findsOneWidget);
  });
}
