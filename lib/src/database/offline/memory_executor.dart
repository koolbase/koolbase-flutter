// An in-memory database for initializeForTesting(offline: true) (R124):
// drift's NativeDatabase on platforms with dart:ffi, nothing on the web (no
// offline layer there, and dart:ffi does not compile for it).
export 'memory_executor_stub.dart' if (dart.library.ffi) 'memory_executor_io.dart';
