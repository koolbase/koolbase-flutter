import 'package:flutter_test/flutter_test.dart';
import 'package:koolbase_flutter/koolbase_flutter.dart';

// G5: a location field's within and the nearest-first sort, exactly as the
// API parses them.
void main() {
  test('within: the point and the distance', () {
    expect(KbField('place').within(5.6037, -0.187, 25).toJson(), {
      'field': 'place',
      'operator': 'within',
      'value': {
        'kind': 'literal',
        'value': {'lat': 5.6037, 'lng': -0.187, 'km': 25.0},
      },
    });
  });

  test('near: nearest first from the point', () {
    expect(KbSort.near('place', 5.6, -0.18).toJson(), {
      'field': 'place',
      'dir': 'asc',
      'near': {'lat': 5.6, 'lng': -0.18},
    });
    expect(KbSort.asc('title').toJson(), {'field': 'title', 'dir': 'asc'});
  });

  test('a point off the Earth, or no distance, is refused here', () {
    expect(() => KbField('place').within(91, 0, 5), throwsArgumentError);
    expect(() => KbField('place').within(0, 181, 5), throwsArgumentError);
    expect(() => KbField('place').within(0, 0, 0), throwsArgumentError);
    expect(() => KbSort.near('place', -91, 0), throwsArgumentError);
  });
}
