// #224: a list says how many rows it shows (onRows) -- null while it loads,
// then its rows; 0 for none; told again only when the number changes.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koolbase_flutter/koolbase_flutter.dart';
import 'package:koolbase_flutter/testing.dart';

Widget _list(Map<String, List<Map<String, Object?>>> data, void Function(int?) onRows,
        {List<KoolbaseRecord> Function(List<KoolbaseRecord>)? visible}) =>
    MaterialApp(
      home: Scaffold(
        body: KoolbaseTestData(
          collections: data,
          child: KoolbaseCollectionList(
            collection: 'events',
            itemBuilder: (context, r) => Text('${r.data['title']}'),
            empty: (context) => const SizedBox.shrink(),
            visible: visible,
            onRows: onRows,
          ),
        ),
      ),
    );

void main() {
  testWidgets('loading, then its rows; told once per change', (tester) async {
    final told = <int?>[];
    await tester.pumpWidget(_list({
      'events': [
        {'id': 'e1', 'title': 'Neon Nights'},
        {'id': 'e2', 'title': 'Street Food'},
      ],
    }, told.add));
    await tester.pumpAndSettle();
    expect(told, [null, 2]);
    await tester.pump();
    expect(told, [null, 2], reason: 'a rebuild with the same rows tells nothing');
  });

  testWidgets('none: 0, so a heading can hide with it', (tester) async {
    final told = <int?>[];
    await tester.pumpWidget(_list({'events': []}, told.add));
    await tester.pumpAndSettle();
    expect(told.last, 0);
    expect(find.byType(SizedBox), findsWidgets);
  });

  testWidgets('a filter that leaves nothing shows: 0', (tester) async {
    final told = <int?>[];
    await tester.pumpWidget(_list({
      'events': [
        {'id': 'e1', 'title': 'Neon Nights'},
      ],
    }, told.add, visible: (rows) => const []));
    await tester.pumpAndSettle();
    expect(told.last, 0);
  });
}
