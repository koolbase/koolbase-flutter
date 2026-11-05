import 'package:drift/drift.dart';

/// No offline layer on the web (R124).
QueryExecutor koolbaseMemoryExecutor() =>
    throw UnsupportedError('The offline layer runs on iOS, Android and desktop, not the web.');
