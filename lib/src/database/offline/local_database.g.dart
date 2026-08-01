// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'local_database.dart';

// ignore_for_file: type=lint
class $CachedQueriesTable extends CachedQueries
    with TableInfo<$CachedQueriesTable, CachedQuery> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedQueriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
      'key', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _responseMeta =
      const VerificationMeta('response');
  @override
  late final GeneratedColumn<String> response = GeneratedColumn<String>(
      'response', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _collectionMeta =
      const VerificationMeta('collection');
  @override
  late final GeneratedColumn<String> collection = GeneratedColumn<String>(
      'collection', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [key, response, collection, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_queries';
  @override
  VerificationContext validateIntegrity(Insertable<CachedQuery> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
          _keyMeta, key.isAcceptableOrUnknown(data['key']!, _keyMeta));
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('response')) {
      context.handle(_responseMeta,
          response.isAcceptableOrUnknown(data['response']!, _responseMeta));
    } else if (isInserting) {
      context.missing(_responseMeta);
    }
    if (data.containsKey('collection')) {
      context.handle(
          _collectionMeta,
          collection.isAcceptableOrUnknown(
              data['collection']!, _collectionMeta));
    } else if (isInserting) {
      context.missing(_collectionMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  CachedQuery map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedQuery(
      key: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}key'])!,
      response: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}response'])!,
      collection: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}collection'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $CachedQueriesTable createAlias(String alias) {
    return $CachedQueriesTable(attachedDatabase, alias);
  }
}

class CachedQuery extends DataClass implements Insertable<CachedQuery> {
  final String key;
  final String response;
  final String collection;
  final DateTime updatedAt;
  const CachedQuery(
      {required this.key,
      required this.response,
      required this.collection,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['response'] = Variable<String>(response);
    map['collection'] = Variable<String>(collection);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  CachedQueriesCompanion toCompanion(bool nullToAbsent) {
    return CachedQueriesCompanion(
      key: Value(key),
      response: Value(response),
      collection: Value(collection),
      updatedAt: Value(updatedAt),
    );
  }

  factory CachedQuery.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedQuery(
      key: serializer.fromJson<String>(json['key']),
      response: serializer.fromJson<String>(json['response']),
      collection: serializer.fromJson<String>(json['collection']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'response': serializer.toJson<String>(response),
      'collection': serializer.toJson<String>(collection),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  CachedQuery copyWith(
          {String? key,
          String? response,
          String? collection,
          DateTime? updatedAt}) =>
      CachedQuery(
        key: key ?? this.key,
        response: response ?? this.response,
        collection: collection ?? this.collection,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  CachedQuery copyWithCompanion(CachedQueriesCompanion data) {
    return CachedQuery(
      key: data.key.present ? data.key.value : this.key,
      response: data.response.present ? data.response.value : this.response,
      collection:
          data.collection.present ? data.collection.value : this.collection,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedQuery(')
          ..write('key: $key, ')
          ..write('response: $response, ')
          ..write('collection: $collection, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, response, collection, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedQuery &&
          other.key == this.key &&
          other.response == this.response &&
          other.collection == this.collection &&
          other.updatedAt == this.updatedAt);
}

class CachedQueriesCompanion extends UpdateCompanion<CachedQuery> {
  final Value<String> key;
  final Value<String> response;
  final Value<String> collection;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const CachedQueriesCompanion({
    this.key = const Value.absent(),
    this.response = const Value.absent(),
    this.collection = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedQueriesCompanion.insert({
    required String key,
    required String response,
    required String collection,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  })  : key = Value(key),
        response = Value(response),
        collection = Value(collection),
        updatedAt = Value(updatedAt);
  static Insertable<CachedQuery> custom({
    Expression<String>? key,
    Expression<String>? response,
    Expression<String>? collection,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (response != null) 'response': response,
      if (collection != null) 'collection': collection,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedQueriesCompanion copyWith(
      {Value<String>? key,
      Value<String>? response,
      Value<String>? collection,
      Value<DateTime>? updatedAt,
      Value<int>? rowid}) {
    return CachedQueriesCompanion(
      key: key ?? this.key,
      response: response ?? this.response,
      collection: collection ?? this.collection,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (response.present) {
      map['response'] = Variable<String>(response.value);
    }
    if (collection.present) {
      map['collection'] = Variable<String>(collection.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedQueriesCompanion(')
          ..write('key: $key, ')
          ..write('response: $response, ')
          ..write('collection: $collection, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedRecordsTable extends CachedRecords
    with TableInfo<$CachedRecordsTable, CachedRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _collectionMeta =
      const VerificationMeta('collection');
  @override
  late final GeneratedColumn<String> collection = GeneratedColumn<String>(
      'collection', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _dataMeta = const VerificationMeta('data');
  @override
  late final GeneratedColumn<String> data = GeneratedColumn<String>(
      'data', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _revisionMeta =
      const VerificationMeta('revision');
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
      'revision', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
      'user_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, collection, data, revision, userId, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_records';
  @override
  VerificationContext validateIntegrity(Insertable<CachedRecord> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('collection')) {
      context.handle(
          _collectionMeta,
          collection.isAcceptableOrUnknown(
              data['collection']!, _collectionMeta));
    } else if (isInserting) {
      context.missing(_collectionMeta);
    }
    if (data.containsKey('data')) {
      context.handle(
          _dataMeta, this.data.isAcceptableOrUnknown(data['data']!, _dataMeta));
    } else if (isInserting) {
      context.missing(_dataMeta);
    }
    if (data.containsKey('revision')) {
      context.handle(_revisionMeta,
          revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta));
    }
    if (data.containsKey('user_id')) {
      context.handle(_userIdMeta,
          userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CachedRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedRecord(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      collection: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}collection'])!,
      data: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}data'])!,
      revision: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}revision']),
      userId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}user_id']),
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $CachedRecordsTable createAlias(String alias) {
    return $CachedRecordsTable(attachedDatabase, alias);
  }
}

class CachedRecord extends DataClass implements Insertable<CachedRecord> {
  final String id;
  final String collection;
  final String data;

  /// The revision this copy was read at.
  ///
  /// An offline mutation is composed against a cached record, and replays with
  /// the revision that copy carried — which is how the server can refuse the
  /// write atomically rather than the client checking first and hoping nothing
  /// lands in the gap.
  ///
  /// Null for records cached before this version, and for servers that predate
  /// revisions. Those cannot be mutated offline: the baseline rules refuse
  /// rather than replay blindly.
  final int? revision;
  final String? userId;
  final DateTime updatedAt;
  const CachedRecord(
      {required this.id,
      required this.collection,
      required this.data,
      this.revision,
      this.userId,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['collection'] = Variable<String>(collection);
    map['data'] = Variable<String>(data);
    if (!nullToAbsent || revision != null) {
      map['revision'] = Variable<int>(revision);
    }
    if (!nullToAbsent || userId != null) {
      map['user_id'] = Variable<String>(userId);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  CachedRecordsCompanion toCompanion(bool nullToAbsent) {
    return CachedRecordsCompanion(
      id: Value(id),
      collection: Value(collection),
      data: Value(data),
      revision: revision == null && nullToAbsent
          ? const Value.absent()
          : Value(revision),
      userId:
          userId == null && nullToAbsent ? const Value.absent() : Value(userId),
      updatedAt: Value(updatedAt),
    );
  }

  factory CachedRecord.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedRecord(
      id: serializer.fromJson<String>(json['id']),
      collection: serializer.fromJson<String>(json['collection']),
      data: serializer.fromJson<String>(json['data']),
      revision: serializer.fromJson<int?>(json['revision']),
      userId: serializer.fromJson<String?>(json['userId']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'collection': serializer.toJson<String>(collection),
      'data': serializer.toJson<String>(data),
      'revision': serializer.toJson<int?>(revision),
      'userId': serializer.toJson<String?>(userId),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  CachedRecord copyWith(
          {String? id,
          String? collection,
          String? data,
          Value<int?> revision = const Value.absent(),
          Value<String?> userId = const Value.absent(),
          DateTime? updatedAt}) =>
      CachedRecord(
        id: id ?? this.id,
        collection: collection ?? this.collection,
        data: data ?? this.data,
        revision: revision.present ? revision.value : this.revision,
        userId: userId.present ? userId.value : this.userId,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  CachedRecord copyWithCompanion(CachedRecordsCompanion data) {
    return CachedRecord(
      id: data.id.present ? data.id.value : this.id,
      collection:
          data.collection.present ? data.collection.value : this.collection,
      data: data.data.present ? data.data.value : this.data,
      revision: data.revision.present ? data.revision.value : this.revision,
      userId: data.userId.present ? data.userId.value : this.userId,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedRecord(')
          ..write('id: $id, ')
          ..write('collection: $collection, ')
          ..write('data: $data, ')
          ..write('revision: $revision, ')
          ..write('userId: $userId, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, collection, data, revision, userId, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedRecord &&
          other.id == this.id &&
          other.collection == this.collection &&
          other.data == this.data &&
          other.revision == this.revision &&
          other.userId == this.userId &&
          other.updatedAt == this.updatedAt);
}

class CachedRecordsCompanion extends UpdateCompanion<CachedRecord> {
  final Value<String> id;
  final Value<String> collection;
  final Value<String> data;
  final Value<int?> revision;
  final Value<String?> userId;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const CachedRecordsCompanion({
    this.id = const Value.absent(),
    this.collection = const Value.absent(),
    this.data = const Value.absent(),
    this.revision = const Value.absent(),
    this.userId = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedRecordsCompanion.insert({
    required String id,
    required String collection,
    required String data,
    this.revision = const Value.absent(),
    this.userId = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        collection = Value(collection),
        data = Value(data),
        updatedAt = Value(updatedAt);
  static Insertable<CachedRecord> custom({
    Expression<String>? id,
    Expression<String>? collection,
    Expression<String>? data,
    Expression<int>? revision,
    Expression<String>? userId,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (collection != null) 'collection': collection,
      if (data != null) 'data': data,
      if (revision != null) 'revision': revision,
      if (userId != null) 'user_id': userId,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedRecordsCompanion copyWith(
      {Value<String>? id,
      Value<String>? collection,
      Value<String>? data,
      Value<int?>? revision,
      Value<String?>? userId,
      Value<DateTime>? updatedAt,
      Value<int>? rowid}) {
    return CachedRecordsCompanion(
      id: id ?? this.id,
      collection: collection ?? this.collection,
      data: data ?? this.data,
      revision: revision ?? this.revision,
      userId: userId ?? this.userId,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (collection.present) {
      map['collection'] = Variable<String>(collection.value);
    }
    if (data.present) {
      map['data'] = Variable<String>(data.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedRecordsCompanion(')
          ..write('id: $id, ')
          ..write('collection: $collection, ')
          ..write('data: $data, ')
          ..write('revision: $revision, ')
          ..write('userId: $userId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PendingWritesTable extends PendingWrites
    with TableInfo<$PendingWritesTable, PendingWrite> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PendingWritesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _collectionMeta =
      const VerificationMeta('collection');
  @override
  late final GeneratedColumn<String> collection = GeneratedColumn<String>(
      'collection', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _operationMeta =
      const VerificationMeta('operation');
  @override
  late final GeneratedColumn<String> operation = GeneratedColumn<String>(
      'operation', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _payloadMeta =
      const VerificationMeta('payload');
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
      'payload', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _recordIdMeta =
      const VerificationMeta('recordId');
  @override
  late final GeneratedColumn<String> recordId = GeneratedColumn<String>(
      'record_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
      'user_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _baselineMeta =
      const VerificationMeta('baseline');
  @override
  late final GeneratedColumn<String> baseline = GeneratedColumn<String>(
      'baseline', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _baseRevisionMeta =
      const VerificationMeta('baseRevision');
  @override
  late final GeneratedColumn<int> baseRevision = GeneratedColumn<int>(
      'base_revision', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _retryCountMeta =
      const VerificationMeta('retryCount');
  @override
  late final GeneratedColumn<int> retryCount = GeneratedColumn<int>(
      'retry_count', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        collection,
        operation,
        payload,
        recordId,
        userId,
        baseline,
        baseRevision,
        retryCount,
        createdAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pending_writes';
  @override
  VerificationContext validateIntegrity(Insertable<PendingWrite> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('collection')) {
      context.handle(
          _collectionMeta,
          collection.isAcceptableOrUnknown(
              data['collection']!, _collectionMeta));
    } else if (isInserting) {
      context.missing(_collectionMeta);
    }
    if (data.containsKey('operation')) {
      context.handle(_operationMeta,
          operation.isAcceptableOrUnknown(data['operation']!, _operationMeta));
    } else if (isInserting) {
      context.missing(_operationMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(_payloadMeta,
          payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta));
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('record_id')) {
      context.handle(_recordIdMeta,
          recordId.isAcceptableOrUnknown(data['record_id']!, _recordIdMeta));
    }
    if (data.containsKey('user_id')) {
      context.handle(_userIdMeta,
          userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta));
    }
    if (data.containsKey('baseline')) {
      context.handle(_baselineMeta,
          baseline.isAcceptableOrUnknown(data['baseline']!, _baselineMeta));
    }
    if (data.containsKey('base_revision')) {
      context.handle(
          _baseRevisionMeta,
          baseRevision.isAcceptableOrUnknown(
              data['base_revision']!, _baseRevisionMeta));
    }
    if (data.containsKey('retry_count')) {
      context.handle(
          _retryCountMeta,
          retryCount.isAcceptableOrUnknown(
              data['retry_count']!, _retryCountMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PendingWrite map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PendingWrite(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      collection: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}collection'])!,
      operation: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}operation'])!,
      payload: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}payload'])!,
      recordId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}record_id']),
      userId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}user_id']),
      baseline: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}baseline']),
      baseRevision: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}base_revision']),
      retryCount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}retry_count'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $PendingWritesTable createAlias(String alias) {
    return $PendingWritesTable(attachedDatabase, alias);
  }
}

class PendingWrite extends DataClass implements Insertable<PendingWrite> {
  final String id;
  final String collection;
  final String operation;
  final String payload;
  final String? recordId;

  /// The user who made this write.
  ///
  /// The queue is per-device, not per-session: a write made offline can
  /// outlive the session that created it, and be replayed after someone else
  /// has signed in on the same device. Without this, their record would be
  /// written under the new user's identity.
  ///
  /// Nullable because writes queued before schema v3 have no owner recorded.
  /// Those are never replayed — see [SyncEngine.syncPendingWrites].
  final String? userId;

  /// The record's field values as the client last saw them, for update and
  /// delete.
  ///
  /// Replay compares three ways — this write's change, what was there when it
  /// was composed, and what is on the server now — which is the only way to
  /// tell "nothing else touched it" from "someone changed it while you were
  /// offline". Without it, applying a queued write silently discards whatever
  /// happened in between.
  ///
  /// Null for inserts, which have no prior state, and for writes queued before
  /// schema v4.
  final String? baseline;

  /// The record revision the write was composed against, sent to the server so
  /// it can refuse the write atomically rather than the client checking first
  /// and hoping nothing lands in the gap.
  final int? baseRevision;
  final int retryCount;
  final DateTime createdAt;
  const PendingWrite(
      {required this.id,
      required this.collection,
      required this.operation,
      required this.payload,
      this.recordId,
      this.userId,
      this.baseline,
      this.baseRevision,
      required this.retryCount,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['collection'] = Variable<String>(collection);
    map['operation'] = Variable<String>(operation);
    map['payload'] = Variable<String>(payload);
    if (!nullToAbsent || recordId != null) {
      map['record_id'] = Variable<String>(recordId);
    }
    if (!nullToAbsent || userId != null) {
      map['user_id'] = Variable<String>(userId);
    }
    if (!nullToAbsent || baseline != null) {
      map['baseline'] = Variable<String>(baseline);
    }
    if (!nullToAbsent || baseRevision != null) {
      map['base_revision'] = Variable<int>(baseRevision);
    }
    map['retry_count'] = Variable<int>(retryCount);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  PendingWritesCompanion toCompanion(bool nullToAbsent) {
    return PendingWritesCompanion(
      id: Value(id),
      collection: Value(collection),
      operation: Value(operation),
      payload: Value(payload),
      recordId: recordId == null && nullToAbsent
          ? const Value.absent()
          : Value(recordId),
      userId:
          userId == null && nullToAbsent ? const Value.absent() : Value(userId),
      baseline: baseline == null && nullToAbsent
          ? const Value.absent()
          : Value(baseline),
      baseRevision: baseRevision == null && nullToAbsent
          ? const Value.absent()
          : Value(baseRevision),
      retryCount: Value(retryCount),
      createdAt: Value(createdAt),
    );
  }

  factory PendingWrite.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PendingWrite(
      id: serializer.fromJson<String>(json['id']),
      collection: serializer.fromJson<String>(json['collection']),
      operation: serializer.fromJson<String>(json['operation']),
      payload: serializer.fromJson<String>(json['payload']),
      recordId: serializer.fromJson<String?>(json['recordId']),
      userId: serializer.fromJson<String?>(json['userId']),
      baseline: serializer.fromJson<String?>(json['baseline']),
      baseRevision: serializer.fromJson<int?>(json['baseRevision']),
      retryCount: serializer.fromJson<int>(json['retryCount']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'collection': serializer.toJson<String>(collection),
      'operation': serializer.toJson<String>(operation),
      'payload': serializer.toJson<String>(payload),
      'recordId': serializer.toJson<String?>(recordId),
      'userId': serializer.toJson<String?>(userId),
      'baseline': serializer.toJson<String?>(baseline),
      'baseRevision': serializer.toJson<int?>(baseRevision),
      'retryCount': serializer.toJson<int>(retryCount),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  PendingWrite copyWith(
          {String? id,
          String? collection,
          String? operation,
          String? payload,
          Value<String?> recordId = const Value.absent(),
          Value<String?> userId = const Value.absent(),
          Value<String?> baseline = const Value.absent(),
          Value<int?> baseRevision = const Value.absent(),
          int? retryCount,
          DateTime? createdAt}) =>
      PendingWrite(
        id: id ?? this.id,
        collection: collection ?? this.collection,
        operation: operation ?? this.operation,
        payload: payload ?? this.payload,
        recordId: recordId.present ? recordId.value : this.recordId,
        userId: userId.present ? userId.value : this.userId,
        baseline: baseline.present ? baseline.value : this.baseline,
        baseRevision:
            baseRevision.present ? baseRevision.value : this.baseRevision,
        retryCount: retryCount ?? this.retryCount,
        createdAt: createdAt ?? this.createdAt,
      );
  PendingWrite copyWithCompanion(PendingWritesCompanion data) {
    return PendingWrite(
      id: data.id.present ? data.id.value : this.id,
      collection:
          data.collection.present ? data.collection.value : this.collection,
      operation: data.operation.present ? data.operation.value : this.operation,
      payload: data.payload.present ? data.payload.value : this.payload,
      recordId: data.recordId.present ? data.recordId.value : this.recordId,
      userId: data.userId.present ? data.userId.value : this.userId,
      baseline: data.baseline.present ? data.baseline.value : this.baseline,
      baseRevision: data.baseRevision.present
          ? data.baseRevision.value
          : this.baseRevision,
      retryCount:
          data.retryCount.present ? data.retryCount.value : this.retryCount,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PendingWrite(')
          ..write('id: $id, ')
          ..write('collection: $collection, ')
          ..write('operation: $operation, ')
          ..write('payload: $payload, ')
          ..write('recordId: $recordId, ')
          ..write('userId: $userId, ')
          ..write('baseline: $baseline, ')
          ..write('baseRevision: $baseRevision, ')
          ..write('retryCount: $retryCount, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, collection, operation, payload, recordId,
      userId, baseline, baseRevision, retryCount, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PendingWrite &&
          other.id == this.id &&
          other.collection == this.collection &&
          other.operation == this.operation &&
          other.payload == this.payload &&
          other.recordId == this.recordId &&
          other.userId == this.userId &&
          other.baseline == this.baseline &&
          other.baseRevision == this.baseRevision &&
          other.retryCount == this.retryCount &&
          other.createdAt == this.createdAt);
}

class PendingWritesCompanion extends UpdateCompanion<PendingWrite> {
  final Value<String> id;
  final Value<String> collection;
  final Value<String> operation;
  final Value<String> payload;
  final Value<String?> recordId;
  final Value<String?> userId;
  final Value<String?> baseline;
  final Value<int?> baseRevision;
  final Value<int> retryCount;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const PendingWritesCompanion({
    this.id = const Value.absent(),
    this.collection = const Value.absent(),
    this.operation = const Value.absent(),
    this.payload = const Value.absent(),
    this.recordId = const Value.absent(),
    this.userId = const Value.absent(),
    this.baseline = const Value.absent(),
    this.baseRevision = const Value.absent(),
    this.retryCount = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PendingWritesCompanion.insert({
    required String id,
    required String collection,
    required String operation,
    required String payload,
    this.recordId = const Value.absent(),
    this.userId = const Value.absent(),
    this.baseline = const Value.absent(),
    this.baseRevision = const Value.absent(),
    this.retryCount = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        collection = Value(collection),
        operation = Value(operation),
        payload = Value(payload),
        createdAt = Value(createdAt);
  static Insertable<PendingWrite> custom({
    Expression<String>? id,
    Expression<String>? collection,
    Expression<String>? operation,
    Expression<String>? payload,
    Expression<String>? recordId,
    Expression<String>? userId,
    Expression<String>? baseline,
    Expression<int>? baseRevision,
    Expression<int>? retryCount,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (collection != null) 'collection': collection,
      if (operation != null) 'operation': operation,
      if (payload != null) 'payload': payload,
      if (recordId != null) 'record_id': recordId,
      if (userId != null) 'user_id': userId,
      if (baseline != null) 'baseline': baseline,
      if (baseRevision != null) 'base_revision': baseRevision,
      if (retryCount != null) 'retry_count': retryCount,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PendingWritesCompanion copyWith(
      {Value<String>? id,
      Value<String>? collection,
      Value<String>? operation,
      Value<String>? payload,
      Value<String?>? recordId,
      Value<String?>? userId,
      Value<String?>? baseline,
      Value<int?>? baseRevision,
      Value<int>? retryCount,
      Value<DateTime>? createdAt,
      Value<int>? rowid}) {
    return PendingWritesCompanion(
      id: id ?? this.id,
      collection: collection ?? this.collection,
      operation: operation ?? this.operation,
      payload: payload ?? this.payload,
      recordId: recordId ?? this.recordId,
      userId: userId ?? this.userId,
      baseline: baseline ?? this.baseline,
      baseRevision: baseRevision ?? this.baseRevision,
      retryCount: retryCount ?? this.retryCount,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (collection.present) {
      map['collection'] = Variable<String>(collection.value);
    }
    if (operation.present) {
      map['operation'] = Variable<String>(operation.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (recordId.present) {
      map['record_id'] = Variable<String>(recordId.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (baseline.present) {
      map['baseline'] = Variable<String>(baseline.value);
    }
    if (baseRevision.present) {
      map['base_revision'] = Variable<int>(baseRevision.value);
    }
    if (retryCount.present) {
      map['retry_count'] = Variable<int>(retryCount.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PendingWritesCompanion(')
          ..write('id: $id, ')
          ..write('collection: $collection, ')
          ..write('operation: $operation, ')
          ..write('payload: $payload, ')
          ..write('recordId: $recordId, ')
          ..write('userId: $userId, ')
          ..write('baseline: $baseline, ')
          ..write('baseRevision: $baseRevision, ')
          ..write('retryCount: $retryCount, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ConflictsTable extends Conflicts
    with TableInfo<$ConflictsTable, Conflict> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ConflictsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _collectionMeta =
      const VerificationMeta('collection');
  @override
  late final GeneratedColumn<String> collection = GeneratedColumn<String>(
      'collection', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _recordIdMeta =
      const VerificationMeta('recordId');
  @override
  late final GeneratedColumn<String> recordId = GeneratedColumn<String>(
      'record_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _operationMeta =
      const VerificationMeta('operation');
  @override
  late final GeneratedColumn<String> operation = GeneratedColumn<String>(
      'operation', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _payloadMeta =
      const VerificationMeta('payload');
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
      'payload', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _baselineMeta =
      const VerificationMeta('baseline');
  @override
  late final GeneratedColumn<String> baseline = GeneratedColumn<String>(
      'baseline', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _serverStateMeta =
      const VerificationMeta('serverState');
  @override
  late final GeneratedColumn<String> serverState = GeneratedColumn<String>(
      'server_state', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _baseRevisionMeta =
      const VerificationMeta('baseRevision');
  @override
  late final GeneratedColumn<int> baseRevision = GeneratedColumn<int>(
      'base_revision', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _serverRevisionMeta =
      const VerificationMeta('serverRevision');
  @override
  late final GeneratedColumn<int> serverRevision = GeneratedColumn<int>(
      'server_revision', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
      'user_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _reasonMeta = const VerificationMeta('reason');
  @override
  late final GeneratedColumn<String> reason = GeneratedColumn<String>(
      'reason', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _messageMeta =
      const VerificationMeta('message');
  @override
  late final GeneratedColumn<String> message = GeneratedColumn<String>(
      'message', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _lastAttemptedAtMeta =
      const VerificationMeta('lastAttemptedAt');
  @override
  late final GeneratedColumn<DateTime> lastAttemptedAt =
      GeneratedColumn<DateTime>('last_attempted_at', aliasedName, true,
          type: DriftSqlType.dateTime, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        collection,
        recordId,
        operation,
        payload,
        baseline,
        serverState,
        baseRevision,
        serverRevision,
        userId,
        reason,
        message,
        createdAt,
        lastAttemptedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'conflicts';
  @override
  VerificationContext validateIntegrity(Insertable<Conflict> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('collection')) {
      context.handle(
          _collectionMeta,
          collection.isAcceptableOrUnknown(
              data['collection']!, _collectionMeta));
    } else if (isInserting) {
      context.missing(_collectionMeta);
    }
    if (data.containsKey('record_id')) {
      context.handle(_recordIdMeta,
          recordId.isAcceptableOrUnknown(data['record_id']!, _recordIdMeta));
    } else if (isInserting) {
      context.missing(_recordIdMeta);
    }
    if (data.containsKey('operation')) {
      context.handle(_operationMeta,
          operation.isAcceptableOrUnknown(data['operation']!, _operationMeta));
    } else if (isInserting) {
      context.missing(_operationMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(_payloadMeta,
          payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta));
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('baseline')) {
      context.handle(_baselineMeta,
          baseline.isAcceptableOrUnknown(data['baseline']!, _baselineMeta));
    }
    if (data.containsKey('server_state')) {
      context.handle(
          _serverStateMeta,
          serverState.isAcceptableOrUnknown(
              data['server_state']!, _serverStateMeta));
    }
    if (data.containsKey('base_revision')) {
      context.handle(
          _baseRevisionMeta,
          baseRevision.isAcceptableOrUnknown(
              data['base_revision']!, _baseRevisionMeta));
    }
    if (data.containsKey('server_revision')) {
      context.handle(
          _serverRevisionMeta,
          serverRevision.isAcceptableOrUnknown(
              data['server_revision']!, _serverRevisionMeta));
    }
    if (data.containsKey('user_id')) {
      context.handle(_userIdMeta,
          userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta));
    }
    if (data.containsKey('reason')) {
      context.handle(_reasonMeta,
          reason.isAcceptableOrUnknown(data['reason']!, _reasonMeta));
    }
    if (data.containsKey('message')) {
      context.handle(_messageMeta,
          message.isAcceptableOrUnknown(data['message']!, _messageMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('last_attempted_at')) {
      context.handle(
          _lastAttemptedAtMeta,
          lastAttemptedAt.isAcceptableOrUnknown(
              data['last_attempted_at']!, _lastAttemptedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Conflict map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Conflict(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      collection: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}collection'])!,
      recordId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}record_id'])!,
      operation: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}operation'])!,
      payload: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}payload'])!,
      baseline: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}baseline']),
      serverState: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}server_state']),
      baseRevision: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}base_revision']),
      serverRevision: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}server_revision']),
      userId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}user_id']),
      reason: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}reason']),
      message: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}message']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      lastAttemptedAt: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}last_attempted_at']),
    );
  }

  @override
  $ConflictsTable createAlias(String alias) {
    return $ConflictsTable(attachedDatabase, alias);
  }
}

class Conflict extends DataClass implements Insertable<Conflict> {
  final String id;
  final String collection;
  final String recordId;
  final String operation;

  /// What the write wanted to apply.
  final String payload;

  /// What the client saw when it was composed.
  final String? baseline;

  /// What the server holds now, as returned with the refusal — so resolving does
  /// not need a fetch, and cannot race one.
  final String? serverState;
  final int? baseRevision;
  final int? serverRevision;
  final String? userId;

  /// Why this write is waiting.
  ///
  /// 'concurrent_modification' — the record moved between the change being made
  /// and the queue reaching it. 'rejected' — the server refused for a reason
  /// retrying cannot change. Different situations, and an app showing them to
  /// someone should say different things.
  ///
  /// Null for conflicts recorded before this column existed; those were all
  /// concurrent modifications, since that was the only kind.
  final String? reason;

  /// What the server said, when it refused for a terminal reason.
  final String? message;
  final DateTime createdAt;
  final DateTime? lastAttemptedAt;
  const Conflict(
      {required this.id,
      required this.collection,
      required this.recordId,
      required this.operation,
      required this.payload,
      this.baseline,
      this.serverState,
      this.baseRevision,
      this.serverRevision,
      this.userId,
      this.reason,
      this.message,
      required this.createdAt,
      this.lastAttemptedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['collection'] = Variable<String>(collection);
    map['record_id'] = Variable<String>(recordId);
    map['operation'] = Variable<String>(operation);
    map['payload'] = Variable<String>(payload);
    if (!nullToAbsent || baseline != null) {
      map['baseline'] = Variable<String>(baseline);
    }
    if (!nullToAbsent || serverState != null) {
      map['server_state'] = Variable<String>(serverState);
    }
    if (!nullToAbsent || baseRevision != null) {
      map['base_revision'] = Variable<int>(baseRevision);
    }
    if (!nullToAbsent || serverRevision != null) {
      map['server_revision'] = Variable<int>(serverRevision);
    }
    if (!nullToAbsent || userId != null) {
      map['user_id'] = Variable<String>(userId);
    }
    if (!nullToAbsent || reason != null) {
      map['reason'] = Variable<String>(reason);
    }
    if (!nullToAbsent || message != null) {
      map['message'] = Variable<String>(message);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || lastAttemptedAt != null) {
      map['last_attempted_at'] = Variable<DateTime>(lastAttemptedAt);
    }
    return map;
  }

  ConflictsCompanion toCompanion(bool nullToAbsent) {
    return ConflictsCompanion(
      id: Value(id),
      collection: Value(collection),
      recordId: Value(recordId),
      operation: Value(operation),
      payload: Value(payload),
      baseline: baseline == null && nullToAbsent
          ? const Value.absent()
          : Value(baseline),
      serverState: serverState == null && nullToAbsent
          ? const Value.absent()
          : Value(serverState),
      baseRevision: baseRevision == null && nullToAbsent
          ? const Value.absent()
          : Value(baseRevision),
      serverRevision: serverRevision == null && nullToAbsent
          ? const Value.absent()
          : Value(serverRevision),
      userId:
          userId == null && nullToAbsent ? const Value.absent() : Value(userId),
      reason:
          reason == null && nullToAbsent ? const Value.absent() : Value(reason),
      message: message == null && nullToAbsent
          ? const Value.absent()
          : Value(message),
      createdAt: Value(createdAt),
      lastAttemptedAt: lastAttemptedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastAttemptedAt),
    );
  }

  factory Conflict.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Conflict(
      id: serializer.fromJson<String>(json['id']),
      collection: serializer.fromJson<String>(json['collection']),
      recordId: serializer.fromJson<String>(json['recordId']),
      operation: serializer.fromJson<String>(json['operation']),
      payload: serializer.fromJson<String>(json['payload']),
      baseline: serializer.fromJson<String?>(json['baseline']),
      serverState: serializer.fromJson<String?>(json['serverState']),
      baseRevision: serializer.fromJson<int?>(json['baseRevision']),
      serverRevision: serializer.fromJson<int?>(json['serverRevision']),
      userId: serializer.fromJson<String?>(json['userId']),
      reason: serializer.fromJson<String?>(json['reason']),
      message: serializer.fromJson<String?>(json['message']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      lastAttemptedAt: serializer.fromJson<DateTime?>(json['lastAttemptedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'collection': serializer.toJson<String>(collection),
      'recordId': serializer.toJson<String>(recordId),
      'operation': serializer.toJson<String>(operation),
      'payload': serializer.toJson<String>(payload),
      'baseline': serializer.toJson<String?>(baseline),
      'serverState': serializer.toJson<String?>(serverState),
      'baseRevision': serializer.toJson<int?>(baseRevision),
      'serverRevision': serializer.toJson<int?>(serverRevision),
      'userId': serializer.toJson<String?>(userId),
      'reason': serializer.toJson<String?>(reason),
      'message': serializer.toJson<String?>(message),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'lastAttemptedAt': serializer.toJson<DateTime?>(lastAttemptedAt),
    };
  }

  Conflict copyWith(
          {String? id,
          String? collection,
          String? recordId,
          String? operation,
          String? payload,
          Value<String?> baseline = const Value.absent(),
          Value<String?> serverState = const Value.absent(),
          Value<int?> baseRevision = const Value.absent(),
          Value<int?> serverRevision = const Value.absent(),
          Value<String?> userId = const Value.absent(),
          Value<String?> reason = const Value.absent(),
          Value<String?> message = const Value.absent(),
          DateTime? createdAt,
          Value<DateTime?> lastAttemptedAt = const Value.absent()}) =>
      Conflict(
        id: id ?? this.id,
        collection: collection ?? this.collection,
        recordId: recordId ?? this.recordId,
        operation: operation ?? this.operation,
        payload: payload ?? this.payload,
        baseline: baseline.present ? baseline.value : this.baseline,
        serverState: serverState.present ? serverState.value : this.serverState,
        baseRevision:
            baseRevision.present ? baseRevision.value : this.baseRevision,
        serverRevision:
            serverRevision.present ? serverRevision.value : this.serverRevision,
        userId: userId.present ? userId.value : this.userId,
        reason: reason.present ? reason.value : this.reason,
        message: message.present ? message.value : this.message,
        createdAt: createdAt ?? this.createdAt,
        lastAttemptedAt: lastAttemptedAt.present
            ? lastAttemptedAt.value
            : this.lastAttemptedAt,
      );
  Conflict copyWithCompanion(ConflictsCompanion data) {
    return Conflict(
      id: data.id.present ? data.id.value : this.id,
      collection:
          data.collection.present ? data.collection.value : this.collection,
      recordId: data.recordId.present ? data.recordId.value : this.recordId,
      operation: data.operation.present ? data.operation.value : this.operation,
      payload: data.payload.present ? data.payload.value : this.payload,
      baseline: data.baseline.present ? data.baseline.value : this.baseline,
      serverState:
          data.serverState.present ? data.serverState.value : this.serverState,
      baseRevision: data.baseRevision.present
          ? data.baseRevision.value
          : this.baseRevision,
      serverRevision: data.serverRevision.present
          ? data.serverRevision.value
          : this.serverRevision,
      userId: data.userId.present ? data.userId.value : this.userId,
      reason: data.reason.present ? data.reason.value : this.reason,
      message: data.message.present ? data.message.value : this.message,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      lastAttemptedAt: data.lastAttemptedAt.present
          ? data.lastAttemptedAt.value
          : this.lastAttemptedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Conflict(')
          ..write('id: $id, ')
          ..write('collection: $collection, ')
          ..write('recordId: $recordId, ')
          ..write('operation: $operation, ')
          ..write('payload: $payload, ')
          ..write('baseline: $baseline, ')
          ..write('serverState: $serverState, ')
          ..write('baseRevision: $baseRevision, ')
          ..write('serverRevision: $serverRevision, ')
          ..write('userId: $userId, ')
          ..write('reason: $reason, ')
          ..write('message: $message, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastAttemptedAt: $lastAttemptedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      collection,
      recordId,
      operation,
      payload,
      baseline,
      serverState,
      baseRevision,
      serverRevision,
      userId,
      reason,
      message,
      createdAt,
      lastAttemptedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Conflict &&
          other.id == this.id &&
          other.collection == this.collection &&
          other.recordId == this.recordId &&
          other.operation == this.operation &&
          other.payload == this.payload &&
          other.baseline == this.baseline &&
          other.serverState == this.serverState &&
          other.baseRevision == this.baseRevision &&
          other.serverRevision == this.serverRevision &&
          other.userId == this.userId &&
          other.reason == this.reason &&
          other.message == this.message &&
          other.createdAt == this.createdAt &&
          other.lastAttemptedAt == this.lastAttemptedAt);
}

class ConflictsCompanion extends UpdateCompanion<Conflict> {
  final Value<String> id;
  final Value<String> collection;
  final Value<String> recordId;
  final Value<String> operation;
  final Value<String> payload;
  final Value<String?> baseline;
  final Value<String?> serverState;
  final Value<int?> baseRevision;
  final Value<int?> serverRevision;
  final Value<String?> userId;
  final Value<String?> reason;
  final Value<String?> message;
  final Value<DateTime> createdAt;
  final Value<DateTime?> lastAttemptedAt;
  final Value<int> rowid;
  const ConflictsCompanion({
    this.id = const Value.absent(),
    this.collection = const Value.absent(),
    this.recordId = const Value.absent(),
    this.operation = const Value.absent(),
    this.payload = const Value.absent(),
    this.baseline = const Value.absent(),
    this.serverState = const Value.absent(),
    this.baseRevision = const Value.absent(),
    this.serverRevision = const Value.absent(),
    this.userId = const Value.absent(),
    this.reason = const Value.absent(),
    this.message = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.lastAttemptedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ConflictsCompanion.insert({
    required String id,
    required String collection,
    required String recordId,
    required String operation,
    required String payload,
    this.baseline = const Value.absent(),
    this.serverState = const Value.absent(),
    this.baseRevision = const Value.absent(),
    this.serverRevision = const Value.absent(),
    this.userId = const Value.absent(),
    this.reason = const Value.absent(),
    this.message = const Value.absent(),
    required DateTime createdAt,
    this.lastAttemptedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        collection = Value(collection),
        recordId = Value(recordId),
        operation = Value(operation),
        payload = Value(payload),
        createdAt = Value(createdAt);
  static Insertable<Conflict> custom({
    Expression<String>? id,
    Expression<String>? collection,
    Expression<String>? recordId,
    Expression<String>? operation,
    Expression<String>? payload,
    Expression<String>? baseline,
    Expression<String>? serverState,
    Expression<int>? baseRevision,
    Expression<int>? serverRevision,
    Expression<String>? userId,
    Expression<String>? reason,
    Expression<String>? message,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? lastAttemptedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (collection != null) 'collection': collection,
      if (recordId != null) 'record_id': recordId,
      if (operation != null) 'operation': operation,
      if (payload != null) 'payload': payload,
      if (baseline != null) 'baseline': baseline,
      if (serverState != null) 'server_state': serverState,
      if (baseRevision != null) 'base_revision': baseRevision,
      if (serverRevision != null) 'server_revision': serverRevision,
      if (userId != null) 'user_id': userId,
      if (reason != null) 'reason': reason,
      if (message != null) 'message': message,
      if (createdAt != null) 'created_at': createdAt,
      if (lastAttemptedAt != null) 'last_attempted_at': lastAttemptedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ConflictsCompanion copyWith(
      {Value<String>? id,
      Value<String>? collection,
      Value<String>? recordId,
      Value<String>? operation,
      Value<String>? payload,
      Value<String?>? baseline,
      Value<String?>? serverState,
      Value<int?>? baseRevision,
      Value<int?>? serverRevision,
      Value<String?>? userId,
      Value<String?>? reason,
      Value<String?>? message,
      Value<DateTime>? createdAt,
      Value<DateTime?>? lastAttemptedAt,
      Value<int>? rowid}) {
    return ConflictsCompanion(
      id: id ?? this.id,
      collection: collection ?? this.collection,
      recordId: recordId ?? this.recordId,
      operation: operation ?? this.operation,
      payload: payload ?? this.payload,
      baseline: baseline ?? this.baseline,
      serverState: serverState ?? this.serverState,
      baseRevision: baseRevision ?? this.baseRevision,
      serverRevision: serverRevision ?? this.serverRevision,
      userId: userId ?? this.userId,
      reason: reason ?? this.reason,
      message: message ?? this.message,
      createdAt: createdAt ?? this.createdAt,
      lastAttemptedAt: lastAttemptedAt ?? this.lastAttemptedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (collection.present) {
      map['collection'] = Variable<String>(collection.value);
    }
    if (recordId.present) {
      map['record_id'] = Variable<String>(recordId.value);
    }
    if (operation.present) {
      map['operation'] = Variable<String>(operation.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (baseline.present) {
      map['baseline'] = Variable<String>(baseline.value);
    }
    if (serverState.present) {
      map['server_state'] = Variable<String>(serverState.value);
    }
    if (baseRevision.present) {
      map['base_revision'] = Variable<int>(baseRevision.value);
    }
    if (serverRevision.present) {
      map['server_revision'] = Variable<int>(serverRevision.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (reason.present) {
      map['reason'] = Variable<String>(reason.value);
    }
    if (message.present) {
      map['message'] = Variable<String>(message.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (lastAttemptedAt.present) {
      map['last_attempted_at'] = Variable<DateTime>(lastAttemptedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ConflictsCompanion(')
          ..write('id: $id, ')
          ..write('collection: $collection, ')
          ..write('recordId: $recordId, ')
          ..write('operation: $operation, ')
          ..write('payload: $payload, ')
          ..write('baseline: $baseline, ')
          ..write('serverState: $serverState, ')
          ..write('baseRevision: $baseRevision, ')
          ..write('serverRevision: $serverRevision, ')
          ..write('userId: $userId, ')
          ..write('reason: $reason, ')
          ..write('message: $message, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastAttemptedAt: $lastAttemptedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$KoolbaseLocalDatabase extends GeneratedDatabase {
  _$KoolbaseLocalDatabase(QueryExecutor e) : super(e);
  $KoolbaseLocalDatabaseManager get managers =>
      $KoolbaseLocalDatabaseManager(this);
  late final $CachedQueriesTable cachedQueries = $CachedQueriesTable(this);
  late final $CachedRecordsTable cachedRecords = $CachedRecordsTable(this);
  late final $PendingWritesTable pendingWrites = $PendingWritesTable(this);
  late final $ConflictsTable conflicts = $ConflictsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities =>
      [cachedQueries, cachedRecords, pendingWrites, conflicts];
}

typedef $$CachedQueriesTableCreateCompanionBuilder = CachedQueriesCompanion
    Function({
  required String key,
  required String response,
  required String collection,
  required DateTime updatedAt,
  Value<int> rowid,
});
typedef $$CachedQueriesTableUpdateCompanionBuilder = CachedQueriesCompanion
    Function({
  Value<String> key,
  Value<String> response,
  Value<String> collection,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$CachedQueriesTableFilterComposer
    extends Composer<_$KoolbaseLocalDatabase, $CachedQueriesTable> {
  $$CachedQueriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
      column: $table.key, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get response => $composableBuilder(
      column: $table.response, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get collection => $composableBuilder(
      column: $table.collection, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$CachedQueriesTableOrderingComposer
    extends Composer<_$KoolbaseLocalDatabase, $CachedQueriesTable> {
  $$CachedQueriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
      column: $table.key, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get response => $composableBuilder(
      column: $table.response, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get collection => $composableBuilder(
      column: $table.collection, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$CachedQueriesTableAnnotationComposer
    extends Composer<_$KoolbaseLocalDatabase, $CachedQueriesTable> {
  $$CachedQueriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get response =>
      $composableBuilder(column: $table.response, builder: (column) => column);

  GeneratedColumn<String> get collection => $composableBuilder(
      column: $table.collection, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$CachedQueriesTableTableManager extends RootTableManager<
    _$KoolbaseLocalDatabase,
    $CachedQueriesTable,
    CachedQuery,
    $$CachedQueriesTableFilterComposer,
    $$CachedQueriesTableOrderingComposer,
    $$CachedQueriesTableAnnotationComposer,
    $$CachedQueriesTableCreateCompanionBuilder,
    $$CachedQueriesTableUpdateCompanionBuilder,
    (
      CachedQuery,
      BaseReferences<_$KoolbaseLocalDatabase, $CachedQueriesTable, CachedQuery>
    ),
    CachedQuery,
    PrefetchHooks Function()> {
  $$CachedQueriesTableTableManager(
      _$KoolbaseLocalDatabase db, $CachedQueriesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedQueriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedQueriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedQueriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String> response = const Value.absent(),
            Value<String> collection = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CachedQueriesCompanion(
            key: key,
            response: response,
            collection: collection,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String key,
            required String response,
            required String collection,
            required DateTime updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              CachedQueriesCompanion.insert(
            key: key,
            response: response,
            collection: collection,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CachedQueriesTableProcessedTableManager = ProcessedTableManager<
    _$KoolbaseLocalDatabase,
    $CachedQueriesTable,
    CachedQuery,
    $$CachedQueriesTableFilterComposer,
    $$CachedQueriesTableOrderingComposer,
    $$CachedQueriesTableAnnotationComposer,
    $$CachedQueriesTableCreateCompanionBuilder,
    $$CachedQueriesTableUpdateCompanionBuilder,
    (
      CachedQuery,
      BaseReferences<_$KoolbaseLocalDatabase, $CachedQueriesTable, CachedQuery>
    ),
    CachedQuery,
    PrefetchHooks Function()>;
typedef $$CachedRecordsTableCreateCompanionBuilder = CachedRecordsCompanion
    Function({
  required String id,
  required String collection,
  required String data,
  Value<int?> revision,
  Value<String?> userId,
  required DateTime updatedAt,
  Value<int> rowid,
});
typedef $$CachedRecordsTableUpdateCompanionBuilder = CachedRecordsCompanion
    Function({
  Value<String> id,
  Value<String> collection,
  Value<String> data,
  Value<int?> revision,
  Value<String?> userId,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$CachedRecordsTableFilterComposer
    extends Composer<_$KoolbaseLocalDatabase, $CachedRecordsTable> {
  $$CachedRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get collection => $composableBuilder(
      column: $table.collection, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get data => $composableBuilder(
      column: $table.data, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get revision => $composableBuilder(
      column: $table.revision, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get userId => $composableBuilder(
      column: $table.userId, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$CachedRecordsTableOrderingComposer
    extends Composer<_$KoolbaseLocalDatabase, $CachedRecordsTable> {
  $$CachedRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get collection => $composableBuilder(
      column: $table.collection, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get data => $composableBuilder(
      column: $table.data, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get revision => $composableBuilder(
      column: $table.revision, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get userId => $composableBuilder(
      column: $table.userId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$CachedRecordsTableAnnotationComposer
    extends Composer<_$KoolbaseLocalDatabase, $CachedRecordsTable> {
  $$CachedRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get collection => $composableBuilder(
      column: $table.collection, builder: (column) => column);

  GeneratedColumn<String> get data =>
      $composableBuilder(column: $table.data, builder: (column) => column);

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$CachedRecordsTableTableManager extends RootTableManager<
    _$KoolbaseLocalDatabase,
    $CachedRecordsTable,
    CachedRecord,
    $$CachedRecordsTableFilterComposer,
    $$CachedRecordsTableOrderingComposer,
    $$CachedRecordsTableAnnotationComposer,
    $$CachedRecordsTableCreateCompanionBuilder,
    $$CachedRecordsTableUpdateCompanionBuilder,
    (
      CachedRecord,
      BaseReferences<_$KoolbaseLocalDatabase, $CachedRecordsTable, CachedRecord>
    ),
    CachedRecord,
    PrefetchHooks Function()> {
  $$CachedRecordsTableTableManager(
      _$KoolbaseLocalDatabase db, $CachedRecordsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedRecordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> collection = const Value.absent(),
            Value<String> data = const Value.absent(),
            Value<int?> revision = const Value.absent(),
            Value<String?> userId = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CachedRecordsCompanion(
            id: id,
            collection: collection,
            data: data,
            revision: revision,
            userId: userId,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String collection,
            required String data,
            Value<int?> revision = const Value.absent(),
            Value<String?> userId = const Value.absent(),
            required DateTime updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              CachedRecordsCompanion.insert(
            id: id,
            collection: collection,
            data: data,
            revision: revision,
            userId: userId,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CachedRecordsTableProcessedTableManager = ProcessedTableManager<
    _$KoolbaseLocalDatabase,
    $CachedRecordsTable,
    CachedRecord,
    $$CachedRecordsTableFilterComposer,
    $$CachedRecordsTableOrderingComposer,
    $$CachedRecordsTableAnnotationComposer,
    $$CachedRecordsTableCreateCompanionBuilder,
    $$CachedRecordsTableUpdateCompanionBuilder,
    (
      CachedRecord,
      BaseReferences<_$KoolbaseLocalDatabase, $CachedRecordsTable, CachedRecord>
    ),
    CachedRecord,
    PrefetchHooks Function()>;
typedef $$PendingWritesTableCreateCompanionBuilder = PendingWritesCompanion
    Function({
  required String id,
  required String collection,
  required String operation,
  required String payload,
  Value<String?> recordId,
  Value<String?> userId,
  Value<String?> baseline,
  Value<int?> baseRevision,
  Value<int> retryCount,
  required DateTime createdAt,
  Value<int> rowid,
});
typedef $$PendingWritesTableUpdateCompanionBuilder = PendingWritesCompanion
    Function({
  Value<String> id,
  Value<String> collection,
  Value<String> operation,
  Value<String> payload,
  Value<String?> recordId,
  Value<String?> userId,
  Value<String?> baseline,
  Value<int?> baseRevision,
  Value<int> retryCount,
  Value<DateTime> createdAt,
  Value<int> rowid,
});

class $$PendingWritesTableFilterComposer
    extends Composer<_$KoolbaseLocalDatabase, $PendingWritesTable> {
  $$PendingWritesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get collection => $composableBuilder(
      column: $table.collection, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get operation => $composableBuilder(
      column: $table.operation, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get payload => $composableBuilder(
      column: $table.payload, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get recordId => $composableBuilder(
      column: $table.recordId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get userId => $composableBuilder(
      column: $table.userId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get baseline => $composableBuilder(
      column: $table.baseline, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get baseRevision => $composableBuilder(
      column: $table.baseRevision, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get retryCount => $composableBuilder(
      column: $table.retryCount, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));
}

class $$PendingWritesTableOrderingComposer
    extends Composer<_$KoolbaseLocalDatabase, $PendingWritesTable> {
  $$PendingWritesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get collection => $composableBuilder(
      column: $table.collection, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get operation => $composableBuilder(
      column: $table.operation, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get payload => $composableBuilder(
      column: $table.payload, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get recordId => $composableBuilder(
      column: $table.recordId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get userId => $composableBuilder(
      column: $table.userId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get baseline => $composableBuilder(
      column: $table.baseline, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get baseRevision => $composableBuilder(
      column: $table.baseRevision,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get retryCount => $composableBuilder(
      column: $table.retryCount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));
}

class $$PendingWritesTableAnnotationComposer
    extends Composer<_$KoolbaseLocalDatabase, $PendingWritesTable> {
  $$PendingWritesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get collection => $composableBuilder(
      column: $table.collection, builder: (column) => column);

  GeneratedColumn<String> get operation =>
      $composableBuilder(column: $table.operation, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<String> get recordId =>
      $composableBuilder(column: $table.recordId, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get baseline =>
      $composableBuilder(column: $table.baseline, builder: (column) => column);

  GeneratedColumn<int> get baseRevision => $composableBuilder(
      column: $table.baseRevision, builder: (column) => column);

  GeneratedColumn<int> get retryCount => $composableBuilder(
      column: $table.retryCount, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$PendingWritesTableTableManager extends RootTableManager<
    _$KoolbaseLocalDatabase,
    $PendingWritesTable,
    PendingWrite,
    $$PendingWritesTableFilterComposer,
    $$PendingWritesTableOrderingComposer,
    $$PendingWritesTableAnnotationComposer,
    $$PendingWritesTableCreateCompanionBuilder,
    $$PendingWritesTableUpdateCompanionBuilder,
    (
      PendingWrite,
      BaseReferences<_$KoolbaseLocalDatabase, $PendingWritesTable, PendingWrite>
    ),
    PendingWrite,
    PrefetchHooks Function()> {
  $$PendingWritesTableTableManager(
      _$KoolbaseLocalDatabase db, $PendingWritesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PendingWritesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PendingWritesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PendingWritesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> collection = const Value.absent(),
            Value<String> operation = const Value.absent(),
            Value<String> payload = const Value.absent(),
            Value<String?> recordId = const Value.absent(),
            Value<String?> userId = const Value.absent(),
            Value<String?> baseline = const Value.absent(),
            Value<int?> baseRevision = const Value.absent(),
            Value<int> retryCount = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              PendingWritesCompanion(
            id: id,
            collection: collection,
            operation: operation,
            payload: payload,
            recordId: recordId,
            userId: userId,
            baseline: baseline,
            baseRevision: baseRevision,
            retryCount: retryCount,
            createdAt: createdAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String collection,
            required String operation,
            required String payload,
            Value<String?> recordId = const Value.absent(),
            Value<String?> userId = const Value.absent(),
            Value<String?> baseline = const Value.absent(),
            Value<int?> baseRevision = const Value.absent(),
            Value<int> retryCount = const Value.absent(),
            required DateTime createdAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              PendingWritesCompanion.insert(
            id: id,
            collection: collection,
            operation: operation,
            payload: payload,
            recordId: recordId,
            userId: userId,
            baseline: baseline,
            baseRevision: baseRevision,
            retryCount: retryCount,
            createdAt: createdAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$PendingWritesTableProcessedTableManager = ProcessedTableManager<
    _$KoolbaseLocalDatabase,
    $PendingWritesTable,
    PendingWrite,
    $$PendingWritesTableFilterComposer,
    $$PendingWritesTableOrderingComposer,
    $$PendingWritesTableAnnotationComposer,
    $$PendingWritesTableCreateCompanionBuilder,
    $$PendingWritesTableUpdateCompanionBuilder,
    (
      PendingWrite,
      BaseReferences<_$KoolbaseLocalDatabase, $PendingWritesTable, PendingWrite>
    ),
    PendingWrite,
    PrefetchHooks Function()>;
typedef $$ConflictsTableCreateCompanionBuilder = ConflictsCompanion Function({
  required String id,
  required String collection,
  required String recordId,
  required String operation,
  required String payload,
  Value<String?> baseline,
  Value<String?> serverState,
  Value<int?> baseRevision,
  Value<int?> serverRevision,
  Value<String?> userId,
  Value<String?> reason,
  Value<String?> message,
  required DateTime createdAt,
  Value<DateTime?> lastAttemptedAt,
  Value<int> rowid,
});
typedef $$ConflictsTableUpdateCompanionBuilder = ConflictsCompanion Function({
  Value<String> id,
  Value<String> collection,
  Value<String> recordId,
  Value<String> operation,
  Value<String> payload,
  Value<String?> baseline,
  Value<String?> serverState,
  Value<int?> baseRevision,
  Value<int?> serverRevision,
  Value<String?> userId,
  Value<String?> reason,
  Value<String?> message,
  Value<DateTime> createdAt,
  Value<DateTime?> lastAttemptedAt,
  Value<int> rowid,
});

class $$ConflictsTableFilterComposer
    extends Composer<_$KoolbaseLocalDatabase, $ConflictsTable> {
  $$ConflictsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get collection => $composableBuilder(
      column: $table.collection, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get recordId => $composableBuilder(
      column: $table.recordId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get operation => $composableBuilder(
      column: $table.operation, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get payload => $composableBuilder(
      column: $table.payload, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get baseline => $composableBuilder(
      column: $table.baseline, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get serverState => $composableBuilder(
      column: $table.serverState, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get baseRevision => $composableBuilder(
      column: $table.baseRevision, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get serverRevision => $composableBuilder(
      column: $table.serverRevision,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get userId => $composableBuilder(
      column: $table.userId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get reason => $composableBuilder(
      column: $table.reason, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get message => $composableBuilder(
      column: $table.message, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get lastAttemptedAt => $composableBuilder(
      column: $table.lastAttemptedAt,
      builder: (column) => ColumnFilters(column));
}

class $$ConflictsTableOrderingComposer
    extends Composer<_$KoolbaseLocalDatabase, $ConflictsTable> {
  $$ConflictsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get collection => $composableBuilder(
      column: $table.collection, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get recordId => $composableBuilder(
      column: $table.recordId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get operation => $composableBuilder(
      column: $table.operation, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get payload => $composableBuilder(
      column: $table.payload, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get baseline => $composableBuilder(
      column: $table.baseline, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get serverState => $composableBuilder(
      column: $table.serverState, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get baseRevision => $composableBuilder(
      column: $table.baseRevision,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get serverRevision => $composableBuilder(
      column: $table.serverRevision,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get userId => $composableBuilder(
      column: $table.userId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get reason => $composableBuilder(
      column: $table.reason, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get message => $composableBuilder(
      column: $table.message, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get lastAttemptedAt => $composableBuilder(
      column: $table.lastAttemptedAt,
      builder: (column) => ColumnOrderings(column));
}

class $$ConflictsTableAnnotationComposer
    extends Composer<_$KoolbaseLocalDatabase, $ConflictsTable> {
  $$ConflictsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get collection => $composableBuilder(
      column: $table.collection, builder: (column) => column);

  GeneratedColumn<String> get recordId =>
      $composableBuilder(column: $table.recordId, builder: (column) => column);

  GeneratedColumn<String> get operation =>
      $composableBuilder(column: $table.operation, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<String> get baseline =>
      $composableBuilder(column: $table.baseline, builder: (column) => column);

  GeneratedColumn<String> get serverState => $composableBuilder(
      column: $table.serverState, builder: (column) => column);

  GeneratedColumn<int> get baseRevision => $composableBuilder(
      column: $table.baseRevision, builder: (column) => column);

  GeneratedColumn<int> get serverRevision => $composableBuilder(
      column: $table.serverRevision, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get reason =>
      $composableBuilder(column: $table.reason, builder: (column) => column);

  GeneratedColumn<String> get message =>
      $composableBuilder(column: $table.message, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get lastAttemptedAt => $composableBuilder(
      column: $table.lastAttemptedAt, builder: (column) => column);
}

class $$ConflictsTableTableManager extends RootTableManager<
    _$KoolbaseLocalDatabase,
    $ConflictsTable,
    Conflict,
    $$ConflictsTableFilterComposer,
    $$ConflictsTableOrderingComposer,
    $$ConflictsTableAnnotationComposer,
    $$ConflictsTableCreateCompanionBuilder,
    $$ConflictsTableUpdateCompanionBuilder,
    (
      Conflict,
      BaseReferences<_$KoolbaseLocalDatabase, $ConflictsTable, Conflict>
    ),
    Conflict,
    PrefetchHooks Function()> {
  $$ConflictsTableTableManager(
      _$KoolbaseLocalDatabase db, $ConflictsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ConflictsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ConflictsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ConflictsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> collection = const Value.absent(),
            Value<String> recordId = const Value.absent(),
            Value<String> operation = const Value.absent(),
            Value<String> payload = const Value.absent(),
            Value<String?> baseline = const Value.absent(),
            Value<String?> serverState = const Value.absent(),
            Value<int?> baseRevision = const Value.absent(),
            Value<int?> serverRevision = const Value.absent(),
            Value<String?> userId = const Value.absent(),
            Value<String?> reason = const Value.absent(),
            Value<String?> message = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime?> lastAttemptedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ConflictsCompanion(
            id: id,
            collection: collection,
            recordId: recordId,
            operation: operation,
            payload: payload,
            baseline: baseline,
            serverState: serverState,
            baseRevision: baseRevision,
            serverRevision: serverRevision,
            userId: userId,
            reason: reason,
            message: message,
            createdAt: createdAt,
            lastAttemptedAt: lastAttemptedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String collection,
            required String recordId,
            required String operation,
            required String payload,
            Value<String?> baseline = const Value.absent(),
            Value<String?> serverState = const Value.absent(),
            Value<int?> baseRevision = const Value.absent(),
            Value<int?> serverRevision = const Value.absent(),
            Value<String?> userId = const Value.absent(),
            Value<String?> reason = const Value.absent(),
            Value<String?> message = const Value.absent(),
            required DateTime createdAt,
            Value<DateTime?> lastAttemptedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ConflictsCompanion.insert(
            id: id,
            collection: collection,
            recordId: recordId,
            operation: operation,
            payload: payload,
            baseline: baseline,
            serverState: serverState,
            baseRevision: baseRevision,
            serverRevision: serverRevision,
            userId: userId,
            reason: reason,
            message: message,
            createdAt: createdAt,
            lastAttemptedAt: lastAttemptedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$ConflictsTableProcessedTableManager = ProcessedTableManager<
    _$KoolbaseLocalDatabase,
    $ConflictsTable,
    Conflict,
    $$ConflictsTableFilterComposer,
    $$ConflictsTableOrderingComposer,
    $$ConflictsTableAnnotationComposer,
    $$ConflictsTableCreateCompanionBuilder,
    $$ConflictsTableUpdateCompanionBuilder,
    (
      Conflict,
      BaseReferences<_$KoolbaseLocalDatabase, $ConflictsTable, Conflict>
    ),
    Conflict,
    PrefetchHooks Function()>;

class $KoolbaseLocalDatabaseManager {
  final _$KoolbaseLocalDatabase _db;
  $KoolbaseLocalDatabaseManager(this._db);
  $$CachedQueriesTableTableManager get cachedQueries =>
      $$CachedQueriesTableTableManager(_db, _db.cachedQueries);
  $$CachedRecordsTableTableManager get cachedRecords =>
      $$CachedRecordsTableTableManager(_db, _db.cachedRecords);
  $$PendingWritesTableTableManager get pendingWrites =>
      $$PendingWritesTableTableManager(_db, _db.pendingWrites);
  $$ConflictsTableTableManager get conflicts =>
      $$ConflictsTableTableManager(_db, _db.conflicts);
}
