import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koolbase_flutter/koolbase_flutter.dart';

import 'support/fake_query.dart';

/// KoolbaseCollectionList inside a SCROLLING page, the body every new screen in
/// the Designer gets. A list with records there has no height to size to: the
/// default mode throws, page mode (scrollsWithPage) lays out. Found running an
/// exported app on a device; smoke tests missed it because with no data a list
/// shows loading or empty, which were already safe.

KoolbaseCollectionController _controller(Future<QueryResult> Function() onGet) {
  final refresh = StreamController<QueryResult>.broadcast();
  addTearDown(refresh.close);
  return KoolbaseCollectionController(
    collection: 'expenses',
    baseQuery: () => FakeQuery(onGet: onGet, refreshController: refresh),
  );
}

Widget _scrollingPage(KoolbaseCollectionController c, {bool page = true}) =>
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Songs'),
              KoolbaseCollectionList(
                collection: 'expenses',
                controller: c,
                scrollsWithPage: page,
                itemBuilder: (context, r) => Text(r.data['title'] as String),
              ),
            ],
          ),
        ),
      ),
    );

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('the default mode WITH records throws inside a scrolling page '
      '(the device crash, pinned)', (tester) async {
    final c = _controller(() async => fakeResult(['a', 'b']));
    await tester.pumpWidget(_scrollingPage(c, page: false));
    await _settle(tester);
    expect(tester.takeException(), isNotNull);
  });

  testWidgets('page mode lays out its rows inside a scrolling page',
      (tester) async {
    final c = _controller(() async => fakeResult(['a', 'b']));
    await tester.pumpWidget(_scrollingPage(c));
    await _settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('a'), findsOneWidget);
    expect(find.text('b'), findsOneWidget);
  });

  testWidgets('page mode: an empty list lays out, with the empty default',
      (tester) async {
    final c = _controller(() async => fakeResult([]));
    await tester.pumpWidget(_scrollingPage(c));
    await _settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Nothing here yet.'), findsOneWidget);
  });

  testWidgets('page mode: a failed load lays out, with the error default',
      (tester) async {
    final c = _controller(() async => throw Exception('offline'));
    await tester.pumpWidget(_scrollingPage(c));
    await _settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.textContaining("Couldn't load"), findsOneWidget);
  });

  testWidgets('page mode has no pull-to-refresh of its own; the default mode '
      'still does', (tester) async {
    final paged = _controller(() async => fakeResult(['a']));
    await tester.pumpWidget(_scrollingPage(paged));
    await _settle(tester);
    expect(find.byType(RefreshIndicator), findsNothing);

    final bounded = _controller(() async => fakeResult(['a']));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 400,
          child: KoolbaseCollectionList(
            collection: 'expenses',
            controller: bounded,
            itemBuilder: (context, r) => Text(r.data['title'] as String),
          ),
        ),
      ),
    ));
    await _settle(tester);
    expect(find.byType(RefreshIndicator), findsOneWidget);
  });
}
