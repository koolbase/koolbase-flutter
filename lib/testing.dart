/// Testing and certification support for koolbase_flutter.
///
/// Import it in widget tests only:
///
/// ```dart
/// import 'package:koolbase_flutter/testing.dart';
/// ```
///
/// [KoolbaseTestData] supplies records to KoolbaseCollectionList and
/// KoolbaseRecordView so a screen can be pumped populated. It is not a way
/// to ship local data in an app.
library;

export 'src/testing/test_data.dart' show KoolbaseTestData;
