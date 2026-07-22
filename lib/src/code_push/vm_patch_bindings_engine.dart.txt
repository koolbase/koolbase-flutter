// ignore_for_file: import_internal_library, undefined_function
// These resolve only against the Koolbase-patched Flutter engine (dart:_internal
// allowlisted for package:koolbase_flutter; applyKoolbasePatch/koolbaseBuildId
// added to internal_patch.dart). The stock analyzer/SDK can't see them, so it
// flags them — expected. The local-engine build resolves them correctly.

// VM patch native bindings. These call into the Koolbase-patched Flutter
// engine via dart:_internal (allowlisted for package:koolbase_flutter in the
// engine's CFE target rules). iOS-only in practice: Android applies patches in
// the engine at snapshot load, so it never calls applyKoolbasePatch from Dart.
import 'dart:_internal' as internal;
import 'dart:typed_data' show Uint8List;

/// Apply a patch module: override matching host functions with patch bytecode.
/// Returns the number of overrides applied (>=0) or a negative engine error code.
int applyKoolbasePatch(Uint8List bytes) => internal.applyKoolbasePatch(bytes);

/// The running binary's build_id (16 hex chars), read live from the engine.
/// Empty string if the engine did not compute one (unpatched engine).
String koolbaseBuildId() => internal.koolbaseBuildId();
