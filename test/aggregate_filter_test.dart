// Totals take the typed filter: sent as `where` (an object), as a list's.
import 'package:flutter_test/flutter_test.dart';
import 'package:koolbase_flutter/koolbase_flutter.dart';

void main() {
  test('a total with the typed filter sends the tree as where, and its zone', () {
    final upcoming = KbField('starts_at').after(KbValue.now());
    final j = KoolbaseAggregate(
      collection: 'events',
      filter: upcoming,
      timezone: 'Africa/Accra',
      measures: const [KoolbaseMeasure.count(as: 'value')],
    ).toJson();
    expect(j['where'], upcoming.toJson());
    expect(j['timezone'], 'Africa/Accra');
  });

  test('the old filters are sent exactly as before', () {
    final j = const KoolbaseAggregate(
      collection: 'events',
      where: [KoolbaseAggregateFilter('featured', 'eq', true)],
      measures: [KoolbaseMeasure.count(as: 'value')],
    ).toJson();
    expect(j['where'], [
      {'field': 'featured', 'op': 'eq', 'value': true},
    ]);
    expect(j.containsKey('timezone'), isFalse);
  });

  test('filter and where together: refused before anything is sent', () {
    expect(
      () => KoolbaseAggregate(
        collection: 'events',
        where: const [KoolbaseAggregateFilter('featured', 'eq', true)],
        filter: KbField('starts_at').after(KbValue.now()),
        measures: const [KoolbaseMeasure.count(as: 'value')],
      ).toJson(),
      throwsArgumentError,
    );
  });
}
