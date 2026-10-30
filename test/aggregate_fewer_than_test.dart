// #299: below the collection's count minimum, the API does not say the
// number. The result and the group carry `fewer_than`, and an app shows
// "Fewer than N" -- never 0.
import 'package:flutter_test/flutter_test.dart';
import 'package:koolbase_flutter/src/database/aggregate.dart';

void main() {
  test('fewer_than reads on the result and on the group', () {
    final r = KoolbaseAggregateResult.fromJson({
      'groups': [
        {
          'category': '',
          'values': {'value': null},
          'fewer_than': 5,
        },
      ],
      'matched': 0,
      'accounting': <String, dynamic>{},
      'fewer_than': 5,
    });
    expect(r.fewerThan, 5);
    expect(r.groups.single.fewerThan, 5);
    expect(r.groups.single.values['value'], isNull);
  });

  test('absent when the number is said', () {
    final r = KoolbaseAggregateResult.fromJson({
      'groups': [
        {
          'category': '',
          'values': {'value': 120},
        },
      ],
      'matched': 120,
      'accounting': {
        'value': {'counted': 120, 'skipped': 0},
      },
    });
    expect(r.fewerThan, isNull);
    expect(r.groups.single.fewerThan, isNull);
    expect(r.groups.single.values['value'], 120);
  });
}
