import 'package:drift/drift.dart';
import 'package:drift/native.dart';

/// A fresh in-memory database (R124), gone with the test.
QueryExecutor koolbaseMemoryExecutor() => NativeDatabase.memory();
