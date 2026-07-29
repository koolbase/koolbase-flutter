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
      [id, collection, data, userId, updatedAt];
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
  final String? userId;
  final DateTime updatedAt;
  const CachedRecord(
      {required this.id,
      required this.collection,
      required this.data,
      this.userId,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['collection'] = Variable<String>(collection);
    map['data'] = Variable<String>(data);
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
      'userId': serializer.toJson<String?>(userId),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  CachedRecord copyWith(
          {String? id,
          String? collection,
          String? data,
          Value<String?> userId = const Value.absent(),
          DateTime? updatedAt}) =>
      CachedRecord(
        id: id ?? this.id,
        collection: collection ?? this.collection,
        data: data ?? this.data,
        userId: userId.present ? userId.value : this.userId,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  CachedRecord copyWithCompanion(CachedRecordsCompanion data) {
    return CachedRecord(
      id: data.id.present ? data.id.value : this.id,
      collection:
          data.collection.present ? data.collection.value : this.collection,
      data: data.data.present ? data.data.value : this.data,
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
          ..write('userId: $userId, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, collection, data, userId, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedRecord &&
          other.id == this.id &&
          other.collection == this.collection &&
          other.data == this.data &&
          other.userId == this.userId &&
          other.updatedAt == this.updatedAt);
}

class CachedRecordsCompanion extends UpdateCompanion<CachedRecord> {
  final Value<String> id;
  final Value<String> collection;
  final Value<String> data;
  final Value<String?> userId;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const CachedRecordsCompanion({
    this.id = const Value.absent(),
    this.collection = const Value.absent(),
    this.data = const Value.absent(),
    this.userId = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedRecordsCompanion.insert({
    required String id,
    required String collection,
    required String data,
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
    Expression<String>? userId,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (collection != null) 'collection': collection,
      if (data != null) 'data': data,
      if (userId != null) 'user_id': userId,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedRecordsCompanion copyWith(
      {Value<String>? id,
      Value<String>? collection,
      Value<String>? data,
      Value<String?>? userId,
      Value<DateTime>? updatedAt,
      Value<int>? rowid}) {
    return CachedRecordsCompanion(
      id: id ?? this.id,
      collection: collection ?? this.collection,
      data: data ?? this.data,
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
  final int retryCount;
  final DateTime createdAt;
  const PendingWrite(
      {required this.id,
      required this.collection,
      required this.operation,
      required this.payload,
      this.recordId,
      this.userId,
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
          int? retryCount,
          DateTime? createdAt}) =>
      PendingWrite(
        id: id ?? this.id,
        collection: collection ?? this.collection,
        operation: operation ?? this.operation,
        payload: payload ?? this.payload,
        recordId: recordId.present ? recordId.value : this.recordId,
        userId: userId.present ? userId.value : this.userId,
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
          ..write('retryCount: $retryCount, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, collection, operation, payload, recordId,
      userId, retryCount, createdAt);
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
          ..write('retryCount: $retryCount, ')
          ..write('createdAt: $createdAt, ')
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
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities =>
      [cachedQueries, cachedRecords, pendingWrites];
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
  Value<String?> userId,
  required DateTime updatedAt,
  Value<int> rowid,
});
typedef $$CachedRecordsTableUpdateCompanionBuilder = CachedRecordsCompanion
    Function({
  Value<String> id,
  Value<String> collection,
  Value<String> data,
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
            Value<String?> userId = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CachedRecordsCompanion(
            id: id,
            collection: collection,
            data: data,
            userId: userId,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String collection,
            required String data,
            Value<String?> userId = const Value.absent(),
            required DateTime updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              CachedRecordsCompanion.insert(
            id: id,
            collection: collection,
            data: data,
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

class $KoolbaseLocalDatabaseManager {
  final _$KoolbaseLocalDatabase _db;
  $KoolbaseLocalDatabaseManager(this._db);
  $$CachedQueriesTableTableManager get cachedQueries =>
      $$CachedQueriesTableTableManager(_db, _db.cachedQueries);
  $$CachedRecordsTableTableManager get cachedRecords =>
      $$CachedRecordsTableTableManager(_db, _db.cachedRecords);
  $$PendingWritesTableTableManager get pendingWrites =>
      $$PendingWritesTableTableManager(_db, _db.pendingWrites);
}
