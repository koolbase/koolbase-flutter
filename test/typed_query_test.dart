import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:koolbase_flutter/koolbase_flutter.dart';
import 'package:koolbase_flutter/src/database/kb_where.dart' show debugDeviceZone;

// #165b: the typed query as the Flutter SDK sends it. Each builder writes
// exactly the JSON the API parses (claude/query_contract_165.md); a typed
// query never sends the old keys, never shares a cache entry or a stream
// with another query, and a refusal arrives with its code.
void main() {
  late List<Map<String, dynamic>> bodies;
  late http.Response Function() answer;

  KoolbaseQuery q() => KoolbaseQuery(
        baseUrl: 'https://api.test',
        publicKey: 'pk_test',
        collectionName: 'events',
        client: MockClient((req) async {
          bodies.add(jsonDecode(req.body) as Map<String, dynamic>);
          return answer();
        }),
      );

  setUp(() {
    bodies = [];
    answer = () => http.Response(jsonEncode({'records': [], 'total': 0}), 200);
    debugDeviceZone = 'Africa/Accra';
  });
  tearDown(() => debugDeviceZone = null);

  test('builders write the contract JSON', () {
    final tree = KbWhere.and([
      KbField('starts_at').after(KbValue.now()),
      KbWhere.or([
        KbField('category').isIn(['music', 'food']),
        KbField('price').eq(0),
      ]),
      KbField('price').between(10, 100),
      KbField('created_by').eq(KbValue.callerUserId()),
      KbField('org').eq(KbValue.callerClaim('org')),
      KbField('poster').isNotEmpty(),
      KbField('starts_at').on(KbValue.startOfToday(days: 1)),
      KbField('starts_at').before(KbValue.now(offset: const Duration(hours: 2))),
      KbField('starts_at').after(KbValue.now(offset: const Duration(minutes: -30))),
      KbField('starts_at').after(DateTime.utc(2026, 11, 7, 18)),
    ]);
    expect(tree.toJson(), {
      'op': 'and',
      'conditions': [
        {'field': 'starts_at', 'operator': 'after', 'value': {'kind': 'relative_time', 'preset': 'now'}},
        {
          'op': 'or',
          'conditions': [
            {'field': 'category', 'operator': 'in', 'value': {'kind': 'literal', 'value': ['music', 'food']}},
            {'field': 'price', 'operator': 'eq', 'value': {'kind': 'literal', 'value': 0}},
          ],
        },
        {
          'field': 'price',
          'operator': 'between',
          'value': {'kind': 'range', 'from': {'kind': 'literal', 'value': 10}, 'to': {'kind': 'literal', 'value': 100}},
        },
        {'field': 'created_by', 'operator': 'eq', 'value': {'kind': 'caller', 'path': 'user_id'}},
        {'field': 'org', 'operator': 'eq', 'value': {'kind': 'caller', 'path': 'claims.org'}},
        {'field': 'poster', 'operator': 'is_not_empty'},
        {
          'field': 'starts_at',
          'operator': 'on',
          'value': {'kind': 'relative_time', 'preset': 'start_of_today', 'offset': {'amount': 1, 'unit': 'days'}},
        },
        {
          'field': 'starts_at',
          'operator': 'before',
          'value': {'kind': 'relative_time', 'preset': 'now', 'offset': {'amount': 2, 'unit': 'hours'}},
        },
        {
          'field': 'starts_at',
          'operator': 'after',
          'value': {'kind': 'relative_time', 'preset': 'now', 'offset': {'amount': -30, 'unit': 'minutes'}},
        },
        {'field': 'starts_at', 'operator': 'after', 'value': {'kind': 'literal', 'value': '2026-11-07T18:00:00.000Z'}},
      ],
    });
    expect([KbSort.desc('featured').toJson(), KbSort.asc('starts_at').toJson()], [
      {'field': 'featured', 'dir': 'desc'},
      {'field': 'starts_at', 'dir': 'asc'},
    ]);
  });

  test('builders refuse what the API would', () {
    expect(() => KbWhere.and([]), throwsArgumentError);
    expect(() => KbWhere.or([]), throwsArgumentError);
  });

  test('a typed query sends where, sort and the device zone, never the old keys', () async {
    await q()
        .filter(KbField('starts_at').after(KbValue.now()))
        .sort([KbSort.desc('featured'), KbSort.asc('starts_at')])
        .get(fresh: true);
    final b = bodies.single;
    expect(b['where'], {'field': 'starts_at', 'operator': 'after', 'value': {'kind': 'relative_time', 'preset': 'now'}});
    expect(b['sort'], [
      {'field': 'featured', 'dir': 'desc'},
      {'field': 'starts_at', 'dir': 'asc'},
    ]);
    expect(b['timezone'], 'Africa/Accra');
    for (final k in ['filters', 'order_by', 'order_desc']) {
      expect(b.containsKey(k), isFalse, reason: k);
    }
  });

  test('an explicit zone wins; no known zone sends none', () async {
    await q().filter(KbField('price').gt(0)).timezone('Europe/London').get(fresh: true);
    expect(bodies.last['timezone'], 'Europe/London');
    debugDeviceZone = null; // as a platform that cannot say, under test
    await q().filter(KbField('price').gt(0)).get(fresh: true);
    expect(bodies.last.containsKey('timezone'), isFalse);
  });

  test('the old query is sent exactly as before', () async {
    await q().where('status', isEqualTo: 'published').orderBy('starts_at').get(fresh: true);
    final b = bodies.single;
    expect(b['filters'], {'status': 'published'});
    expect(b['order_by'], 'starts_at');
    expect(b['order_desc'], false);
    expect(b.containsKey('where'), isFalse);
    expect(b.containsKey('timezone'), isFalse);
  });

  test('old and typed are never combined', () async {
    await expectLater(
      q().where('status', isEqualTo: 'published').filter(KbField('price').gt(0)).get(fresh: true),
      throwsArgumentError,
    );
    await expectLater(
      q().orderBy('price').sort([KbSort.asc('starts_at')]).get(fresh: true),
      throwsArgumentError,
    );
    expect(bodies, isEmpty, reason: 'nothing is sent');
  });

  test('a typed query is its own cache entry and stream', () {
    final upcoming = q().filter(KbField('starts_at').after(KbValue.now())).streamKey;
    final past = q().filter(KbField('starts_at').before(KbValue.now())).streamKey;
    final plain = q().streamKey;
    expect({upcoming, past, plain}, hasLength(3));
    expect(q().filter(KbField('starts_at').after(KbValue.now())).streamKey, upcoming);
    final sorted = q().sort([KbSort.asc('price')]).streamKey;
    expect(sorted, isNot(plain));
  });

  test('a refusal arrives with its code', () async {
    answer = () => http.Response(
        jsonEncode({'code': 'query_field_untyped', 'error': 'rank is not declared, so gt cannot compare it'}), 400);
    try {
      await q().filter(KbField('rank').gt(1)).get(fresh: true);
      fail('expected a refusal');
    } on KoolbaseValidationException catch (e) {
      expect(e.code, 'query_field_untyped');
      expect(e.message, contains('rank'));
    }
  });
}
