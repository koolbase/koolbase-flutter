class KoolbaseCollection {
  final String id;
  final String projectId;
  final String name;
  final String readRule;
  final String writeRule;
  final String deleteRule;
  final DateTime createdAt;
  const KoolbaseCollection({
    required this.id,
    required this.projectId,
    required this.name,
    required this.readRule,
    required this.writeRule,
    required this.deleteRule,
    required this.createdAt,
  });
  factory KoolbaseCollection.fromJson(Map<String, dynamic> json) {
    return KoolbaseCollection(
      id: json['id'] as String,
      projectId: json['project_id'] as String,
      name: json['name'] as String,
      readRule: json['read_rule'] as String,
      writeRule: json['write_rule'] as String,
      deleteRule: json['delete_rule'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class KoolbaseRecord {
  final String id;
  final String? collection;
  final String? createdBy;
  final Map<String, dynamic> data;
  final DateTime createdAt;
  final DateTime updatedAt;
  const KoolbaseRecord({
    required this.id,
    this.collection,
    this.createdBy,
    required this.data,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Direct field access: `record['email']` == `record.data['email']`.
  dynamic operator [](String key) => data[key];
  factory KoolbaseRecord.fromJson(Map<String, dynamic> json) {
    final fields = <String, dynamic>{};
    for (final entry in json.entries) {
      if (!entry.key.startsWith(r'$')) {
        fields[entry.key] = entry.value;
      }
    }
    return KoolbaseRecord(
      id: json[r'$id'] as String,
      collection: json[r'$collection'] as String?,
      createdBy: json[r'$createdBy'] as String?,
      data: fields,
      createdAt: DateTime.parse(json[r'$createdAt'] as String),
      updatedAt: DateTime.parse(json[r'$updatedAt'] as String),
    );
  }
  Map<String, dynamic> toJson() => {
        r'$id': id,
        if (collection != null) r'$collection': collection,
        if (createdBy != null) r'$createdBy': createdBy,
        r'$createdAt': createdAt.toIso8601String(),
        r'$updatedAt': updatedAt.toIso8601String(),
        ...data,
      };
}

class QueryResult {
  final List<KoolbaseRecord> records;
  final int total;
  final bool isFromCache;
  const QueryResult({
    required this.records,
    required this.total,
    this.isFromCache = false,
  });
}

/// Result of an upsert: the resulting [record], and whether it was newly
/// [created] (true) or an existing record was updated (false).
class KoolbaseUpsertResult {
  final KoolbaseRecord record;
  final bool created;
  const KoolbaseUpsertResult({
    required this.record,
    required this.created,
  });
}

/// One operation in an atomic [KoolbaseDatabaseClient.batch].
///
/// Construct with the factory for the op you want — insert/update/delete/upsert.
class KoolbaseBatchOp {
  final String type;
  final String? collection;
  final String? recordId;
  final Map<String, dynamic>? data;
  final Map<String, dynamic>? match;

  const KoolbaseBatchOp._({
    required this.type,
    this.collection,
    this.recordId,
    this.data,
    this.match,
  });

  /// Insert a new record into [collection].
  factory KoolbaseBatchOp.insert(
          String collection, Map<String, dynamic> data) =>
      KoolbaseBatchOp._(type: 'insert', collection: collection, data: data);

  /// Update the record identified by [recordId] with [data].
  factory KoolbaseBatchOp.update(String recordId, Map<String, dynamic> data) =>
      KoolbaseBatchOp._(type: 'update', recordId: recordId, data: data);

  /// Delete the record identified by [recordId].
  factory KoolbaseBatchOp.delete(String recordId) =>
      KoolbaseBatchOp._(type: 'delete', recordId: recordId);

  /// Insert into [collection], or update the existing record matching [match].
  factory KoolbaseBatchOp.upsert(
    String collection, {
    required Map<String, dynamic> match,
    required Map<String, dynamic> data,
  }) =>
      KoolbaseBatchOp._(
          type: 'upsert', collection: collection, match: match, data: data);

  Map<String, dynamic> toJson() => {
        'type': type,
        if (collection != null) 'collection': collection,
        if (recordId != null) 'record_id': recordId,
        if (data != null) 'data': data,
        if (match != null) 'match': match,
      };
}

/// The result of one operation in a [KoolbaseDatabaseClient.batch], in order.
class KoolbaseBatchResult {
  /// The operation type: insert, update, delete, or upsert.
  final String type;

  /// The resulting record for insert/update/upsert; null for delete.
  final KoolbaseRecord? record;

  /// For upsert: true if a new record was inserted, false if one was updated.
  /// Null for non-upsert ops.
  final bool? created;

  /// True for a successful delete.
  final bool deleted;

  const KoolbaseBatchResult({
    required this.type,
    this.record,
    this.created,
    this.deleted = false,
  });

  factory KoolbaseBatchResult.fromJson(Map<String, dynamic> json) {
    return KoolbaseBatchResult(
      type: json['type'] as String? ?? '',
      record: json['record'] != null
          ? KoolbaseRecord.fromJson(json['record'] as Map<String, dynamic>)
          : null,
      created: json['created'] as bool?,
      deleted: json['deleted'] as bool? ?? false,
    );
  }
}
