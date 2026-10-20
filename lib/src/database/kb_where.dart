import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_timezone/flutter_timezone.dart';

/// A typed filter (#165): which records to read, written as a tree the
/// server validates against the collection's declared fields and runs after
/// its read rule, so a filter can only narrow what the caller may read.
///
/// ```dart
/// Koolbase.db.collection('events').filter(KbWhere.and([
///   KbField('starts_at').after(KbValue.now()),
///   KbWhere.or([
///     KbField('category').isIn(['music', 'food']),
///     KbField('price').eq(0),
///   ]),
/// ]));
/// ```
///
/// Operators follow the field's declared type, and the server refuses one
/// the type does not take (`query_operator_invalid`), or a range or date
/// operator on an undeclared field (`query_field_untyped`). Limits, the
/// server's: groups 3 deep (the outer group is 1), 20 conditions, 100
/// values in a list.
class KbWhere {
  const KbWhere._(this._json);

  final Map<String, Object?> _json;

  /// The tree as the API takes it.
  Map<String, Object?> toJson() => _json;

  /// Every condition must hold.
  static KbWhere and(List<KbWhere> all) => _group('and', all);

  /// At least one condition must hold.
  static KbWhere or(List<KbWhere> any) => _group('or', any);

  static KbWhere _group(String op, List<KbWhere> c) {
    if (c.isEmpty) {
      throw ArgumentError.value(c, 'conditions', 'a group needs at least one condition');
    }
    return KbWhere._({
      'op': op,
      'conditions': [for (final x in c) x._json],
    });
  }

  @override
  String toString() => jsonEncode(_json);
}

/// A record field to filter on: a declared field, or one of the record's
/// own -- `id`, `created_at`, `updated_at`, `created_by`.
class KbField {
  const KbField(this.name);

  final String name;

  KbWhere _with(String op, Object? value) {
    if (value == null) {
      throw ArgumentError.value(value, name, 'no value: use isEmpty() for "has none"');
    }
    return KbWhere._({'field': name, 'operator': op, 'value': KbValue.of(value).toJson()});
  }

  KbWhere _bare(String op) => KbWhere._({'field': name, 'operator': op});

  KbWhere eq(Object value) => _with('eq', value);
  KbWhere neq(Object value) => _with('neq', value);
  KbWhere gt(Object value) => _with('gt', value);
  KbWhere gte(Object value) => _with('gte', value);
  KbWhere lt(Object value) => _with('lt', value);
  KbWhere lte(Object value) => _with('lte', value);
  KbWhere contains(String text) => _with('contains', text);
  KbWhere startsWith(String text) => _with('starts_with', text);

  /// One of [values]: a list, or the caller's claim that holds one.
  KbWhere isIn(Object values) => _with('in', values);
  KbWhere notIn(Object values) => _with('not_in', values);

  /// Inclusive at both ends.
  KbWhere between(Object from, Object to) => KbWhere._({
        'field': name,
        'operator': 'between',
        'value': {
          'kind': 'range',
          'from': KbValue.of(from).toJson(),
          'to': KbValue.of(to).toJson(),
        },
      });

  KbWhere before(Object when) => _with('before', when);
  KbWhere after(Object when) => _with('after', when);
  KbWhere onOrBefore(Object when) => _with('on_or_before', when);
  KbWhere onOrAfter(Object when) => _with('on_or_after', when);

  /// The calendar day of [when] in the query's time zone.
  KbWhere on(Object when) => _with('on', when);

  /// No value: missing, null or an empty list. `0`, `false` and an empty
  /// text are values.
  KbWhere isEmpty() => _bare('is_empty');
  KbWhere isNotEmpty() => _bare('is_not_empty');
  KbWhere isTrue() => _bare('is_true');
  KbWhere isFalse() => _bare('is_false');
}

/// An operand: a literal, a time the server resolves when the query runs,
/// or the signed-in caller, whom the server reads from the session -- a
/// client never supplies who the caller is.
class KbValue {
  const KbValue._(this._json);

  final Map<String, Object?> _json;

  Map<String, Object?> toJson() => _json;

  /// [value] as an operand: a [KbValue] as is; a [DateTime] as an instant
  /// (UTC, RFC 3339); a list item by item; anything else as a literal.
  static KbValue of(Object value) {
    if (value is KbValue) return value;
    if (value is List) {
      return KbValue._({'kind': 'literal', 'value': [for (final v in value) _plain(v)]});
    }
    return KbValue._({'kind': 'literal', 'value': _plain(value)});
  }

  static Object? _plain(Object? v) => v is DateTime ? v.toUtc().toIso8601String() : v;

  /// The server's clock now, optionally moved by [offset].
  static KbValue now({Duration offset = Duration.zero}) => _relative('now', offset: offset);

  /// The start of today in the query's time zone, optionally [days] later
  /// (calendar days, so a clock change never shifts it).
  static KbValue startOfToday({int days = 0}) => _relative('start_of_today', days: days);
  static KbValue startOfTomorrow() => _relative('start_of_tomorrow');

  /// Weeks start on Monday.
  static KbValue startOfWeek() => _relative('start_of_week');
  static KbValue startOfNextWeek() => _relative('start_of_next_week');
  static KbValue startOfMonth() => _relative('start_of_month');

  static KbValue _relative(String preset, {Duration offset = Duration.zero, int days = 0}) {
    Map<String, Object?>? off;
    if (days != 0) {
      off = {'amount': days, 'unit': 'days'};
    } else if (offset != Duration.zero) {
      final m = offset.inMinutes;
      off = m % 60 == 0 ? {'amount': m ~/ 60, 'unit': 'hours'} : {'amount': m, 'unit': 'minutes'};
    }
    return KbValue._({'kind': 'relative_time', 'preset': preset, if (off != null) 'offset': off});
  }

  /// The signed-in user's id, from the session. Refused (`caller_required`)
  /// when no one is signed in.
  static KbValue callerUserId() => const KbValue._({'kind': 'caller', 'path': 'user_id'});

  /// One of the signed-in user's claims, as the server set it. Refused
  /// (`caller_claim_missing`) when the user has none.
  static KbValue callerClaim(String name) => KbValue._({'kind': 'caller', 'path': 'claims.$name'});
}

/// One sort field. Typed by the declaration; values that are empty or do
/// not fit it come last both ways, and the record's id breaks ties.
class KbSort {
  const KbSort._(this.field, this.dir);

  final String field;
  final String dir;

  static KbSort asc(String field) => KbSort._(field, 'asc');
  static KbSort desc(String field) => KbSort._(field, 'desc');

  Map<String, Object?> toJson() => {'field': field, 'dir': dir};
}

String? _deviceZone;

/// The device's IANA time zone ("Africa/Accra"), read once; null when the
/// platform cannot say -- the query then omits it and the server uses UTC.
Future<String?> koolbaseDeviceZone() async {
  final z = _deviceZone;
  if (z != null) return z;
  try {
    final id = (await FlutterTimezone.getLocalTimezone()).identifier;
    if (id.isNotEmpty) _deviceZone = id;
  } catch (_) {
    // No plugin (a test, an unsupported platform): no zone, not a guess.
  }
  return _deviceZone;
}

@visibleForTesting
set debugDeviceZone(String? zone) => _deviceZone = zone;
