/// Asking "how many" and "how much" over a collection, correctly.
///
/// Correct means the WHOLE authorized set -- never the first page -- with
/// the caller's read rule applied inside the query, and never a bare
/// number: collections are schemaless, so a total that quietly excluded
/// three malformed rows would be a wrong number that looks right. Every
/// result carries its accounting.
///
/// ```dart
/// final r = await Koolbase.db.aggregate(
///   KoolbaseAggregate(
///     collection: 'orders',
///     groupBy: KoolbaseGroupBy.month('created_at', timezone: 'Africa/Accra'),
///     measures: [KoolbaseMeasure.sum('total', as: 'revenue')],
///   ),
/// );
/// for (final g in r.groups) {
///   print('${g.category}: ${g.values['revenue']}');
/// }
/// if (r.accounting['revenue']!.skipped > 0) {
///   // some orders had a total that was not a number -- say so
/// }
/// ```
library;

/// One aggregation request.
class KoolbaseAggregate {
  final String collection;

  /// AND-ed record filters on top of the read rule.
  final List<KoolbaseAggregateFilter> where;

  /// Absent means one group: the measures over everything.
  final KoolbaseGroupBy? groupBy;

  /// At least one.
  final List<KoolbaseMeasure> measures;

  const KoolbaseAggregate({
    required this.collection,
    this.where = const [],
    this.groupBy,
    required this.measures,
  });

  Map<String, dynamic> toJson() => {
        'collection': collection,
        if (where.isNotEmpty) 'where': [for (final f in where) f.toJson()],
        if (groupBy != null) 'group_by': groupBy!.toJson(),
        'measures': [for (final m in measures) m.toJson()],
      };
}

class KoolbaseAggregateFilter {
  final String field;

  /// eq | neq | in | gt | gte | lt | lte
  final String op;
  final Object? value;

  const KoolbaseAggregateFilter(this.field, this.op, this.value);

  Map<String, dynamic> toJson() => {'field': field, 'op': op, 'value': value};
}

/// The category axis: a field's value, or a calendar bucket of a
/// timestamp field.
///
/// A bucket REQUIRES a timezone. "Midnight" means nothing without one,
/// and Africa/Accra and UTC disagree about which day a 23:30 sale
/// belongs to. The API refuses a bucket without one; this constructor
/// makes the omission impossible to write.
class KoolbaseGroupBy {
  final String field;
  final String? bucket;
  final String? timezone;

  const KoolbaseGroupBy.field(this.field)
      : bucket = null,
        timezone = null;

  const KoolbaseGroupBy.day(this.field, {required String this.timezone})
      : bucket = 'day';
  const KoolbaseGroupBy.week(this.field, {required String this.timezone})
      : bucket = 'week';
  const KoolbaseGroupBy.month(this.field, {required String this.timezone})
      : bucket = 'month';
  const KoolbaseGroupBy.year(this.field, {required String this.timezone})
      : bucket = 'year';

  Map<String, dynamic> toJson() => {
        'field': field,
        if (bucket != null) 'bucket': bucket,
        if (timezone != null) 'timezone': timezone,
      };
}

/// One number per group.
class KoolbaseMeasure {
  final String? field;

  /// count | sum | avg | min | max
  final String aggregate;

  /// The key it comes back under in [KoolbaseAggregateGroup.values].
  final String as;

  const KoolbaseMeasure._(this.field, this.aggregate, this.as);

  /// Counts RECORDS, so it needs no field and skips nothing.
  const KoolbaseMeasure.count({required String as}) : this._(null, 'count', as);
  const KoolbaseMeasure.sum(String field, {required String as})
      : this._(field, 'sum', as);
  const KoolbaseMeasure.avg(String field, {required String as})
      : this._(field, 'avg', as);
  const KoolbaseMeasure.min(String field, {required String as})
      : this._(field, 'min', as);
  const KoolbaseMeasure.max(String field, {required String as})
      : this._(field, 'max', as);

  Map<String, dynamic> toJson() => {
        if (field != null) 'field': field,
        'aggregate': aggregate,
        'as': as,
      };
}

/// The whole answer, including what could not be counted.
class KoolbaseAggregateResult {
  /// One per category, sorted, or exactly one with an empty category
  /// when there was no groupBy.
  final List<KoolbaseAggregateGroup> groups;

  /// Records that matched the read rule and filters: the denominator.
  final int matched;

  /// Per measure name: how many records contributed and how many were
  /// skipped. Skipped is not an error. It is what you need to decide
  /// whether the number means what it appears to mean.
  final Map<String, KoolbaseAggregateAccounting> accounting;

  /// True when the groupBy produced more categories than allowed and
  /// the whole request was refused. [groups] is EMPTY when this is set:
  /// a partial set drawn as the whole would be exactly the wrong number
  /// this API exists to prevent.
  final bool tooManyGroups;

  const KoolbaseAggregateResult({
    required this.groups,
    required this.matched,
    required this.accounting,
    this.tooManyGroups = false,
  });

  factory KoolbaseAggregateResult.fromJson(Map<String, dynamic> j) =>
      KoolbaseAggregateResult(
        groups: [
          for (final g in (j['groups'] as List<dynamic>? ?? const []))
            KoolbaseAggregateGroup.fromJson(g as Map<String, dynamic>),
        ],
        matched: (j['matched'] as num?)?.toInt() ?? 0,
        accounting: {
          for (final e
              in (j['accounting'] as Map<String, dynamic>? ?? const {}).entries)
            e.key: KoolbaseAggregateAccounting.fromJson(
                e.value as Map<String, dynamic>),
        },
        tooManyGroups: j['too_many_groups'] == true,
      );
}

class KoolbaseAggregateGroup {
  /// The field's value, or the bucket start as an ISO 8601 local time.
  /// Records with no value for the field group under '' -- reported,
  /// not hidden.
  final String category;

  /// Keyed by [KoolbaseMeasure.as]. A null value is a group where every
  /// record was skipped for that measure: nothing to sum, which is
  /// different from a sum of zero.
  final Map<String, double?> values;

  const KoolbaseAggregateGroup({required this.category, required this.values});

  factory KoolbaseAggregateGroup.fromJson(Map<String, dynamic> j) =>
      KoolbaseAggregateGroup(
        category: j['category'] as String? ?? '',
        values: {
          for (final e in (j['values'] as Map<String, dynamic>? ?? const {}).entries)
            e.key: (e.value as num?)?.toDouble(),
        },
      );
}

class KoolbaseAggregateAccounting {
  final int counted;
  final int skipped;

  /// Present when [skipped] > 0: 'missing', 'not_numeric', or 'mixed'.
  final String? skippedReason;

  const KoolbaseAggregateAccounting({
    required this.counted,
    required this.skipped,
    this.skippedReason,
  });

  factory KoolbaseAggregateAccounting.fromJson(Map<String, dynamic> j) =>
      KoolbaseAggregateAccounting(
        counted: (j['counted'] as num?)?.toInt() ?? 0,
        skipped: (j['skipped'] as num?)?.toInt() ?? 0,
        skippedReason: j['skipped_reason'] as String?,
      );
}
