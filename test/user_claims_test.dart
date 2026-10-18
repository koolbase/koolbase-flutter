// #155b: the signed-in user's claims -- only the keys the project's owner made
// readable by the user reach the app, on every session and on /me.

import 'package:flutter_test/flutter_test.dart';
import 'package:koolbase_flutter/koolbase_flutter.dart';

Map<String, dynamic> _json({Map<String, dynamic>? claims}) => {
  'id': 'u1',
  'project_id': 'p1',
  'email': 'maya@example.com',
  'full_name': 'Maya Mensah',
  'verified': true,
  'disabled': false,
  'created_at': '2026-01-01T00:00:00Z',
  'updated_at': '2026-01-01T00:00:00Z',
  if (claims != null) 'claims': claims,
};

void main() {
  test("read from the server's user, by key", () {
    final u = KoolbaseUser.fromJson(_json(claims: {'role': 'organiser', 'org': 'gather'}));
    expect(u.claims, {'role': 'organiser', 'org': 'gather'});
    expect(u.claim('role'), 'organiser');
    expect(u.claim('plan'), isNull);
  });

  test('kept with the persisted session, and through copyWith', () {
    final u = KoolbaseUser.fromJson(_json(claims: {'role': 'organiser'}));
    final back = KoolbaseUser.fromJson(u.toJson());
    expect(back.claims, {'role': 'organiser'});
    expect(u.copyWith(fullName: 'Maya').claims, {'role': 'organiser'});
  });

  test('none: null, and nothing written for it', () {
    final u = KoolbaseUser.fromJson(_json());
    expect(u.claims, isNull);
    expect(u.claim('role'), isNull);
    expect(u.toJson().containsKey('claims'), isFalse);
  });
}
