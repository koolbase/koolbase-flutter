import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koolbase_flutter/koolbase_flutter.dart';
import 'package:koolbase_flutter/src/widgets/load_error.dart';

import 'support/fake_query.dart';

// #97: a failed load's Retry shows that it is working, and says when it
// failed again.

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets(
      'Retry shows "Retrying…" while it runs, at least for a moment, '
      'then says it failed again', (tester) async {
    var calls = 0;
    final pending = Completer<void>();
    await tester.pumpWidget(_host(KbLoadError(
      title: "Couldn't load this list.",
      onRetry: () {
        calls++;
        return pending.future;
      },
    )));
    expect(find.text(kRetryFailedAgain), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(find.text('Retrying…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    // Disabled while it runs: a second tap starts nothing.
    await tester.tap(find.text('Retrying…'));
    await tester.pump();
    expect(calls, 1);

    pending.complete();
    await tester.pump();
    // Failed at once: still shown, for at least kRetryMinShown.
    expect(find.text('Retrying…'), findsOneWidget);
    await tester.pump(kRetryMinShown);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text(kRetryFailedAgain), findsOneWidget);
  });

  testWidgets('a list whose retry fails, then works', (tester) async {
    final refresh = StreamController<QueryResult>.broadcast();
    addTearDown(refresh.close);
    var fails = 2;
    final c = KoolbaseCollectionController(
      collection: 'events',
      baseQuery: () => FakeQuery(
        onGet: () async {
          if (fails > 0) {
            fails--;
            throw Exception('offline');
          }
          return fakeResult(['Launch']);
        },
        refreshController: refresh,
      ),
    );
    await tester.pumpWidget(_host(KoolbaseCollectionList(
      collection: 'events',
      controller: c,
      itemBuilder: (context, r) => Text(r.data['title'] as String),
    )));
    await tester.pump();
    expect(find.text("Couldn't load this list."), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(find.text('Retrying…'), findsOneWidget);
    await tester.pump(kRetryMinShown);
    expect(find.text(kRetryFailedAgain), findsOneWidget);
    expect(c.error.toString(), contains('offline'));

    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Launch'), findsOneWidget);
    expect(find.text("Couldn't load this list."), findsNothing);
  });

  testWidgets('a grid that failed shows the same view, not the raw error',
      (tester) async {
    final refresh = StreamController<QueryResult>.broadcast();
    addTearDown(refresh.close);
    final c = KoolbaseCollectionController(
      collection: 'events',
      baseQuery: () => FakeQuery(
        onGet: () async => throw Exception('offline'),
        refreshController: refresh,
      ),
    );
    await tester.pumpWidget(_host(KoolbaseCollectionGrid(
      collection: 'events',
      controller: c,
      itemBuilder: (context, r) => const SizedBox(),
    )));
    await tester.pump();
    expect(find.text("Couldn't load this list."), findsOneWidget);
    expect(find.textContaining('Exception'), findsNothing);
    expect(find.text('Retry'), findsOneWidget);
  });
}
