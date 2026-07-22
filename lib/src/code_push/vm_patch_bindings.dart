// VM patch bindings — STOCK STUB.
//
// The real bindings call into the Koolbase-patched Flutter engine via
// dart:_internal (applyKoolbasePatch / koolbaseBuildId, C++ natives bound in
// the fork's internal_patch.dart). That import is a platform-private library:
// the STOCK Dart frontend rejects it at kernel compile, which broke every
// customer build on 9.4.0 (unconditionally reachable via koolbase.dart ->
// patch_client.dart). This stub keeps the same two signatures with no private
// imports, so the package compiles everywhere; on a stock engine code push
// simply reports "engine not present" through the existing failure paths.
//
// The engine-real version is preserved verbatim in
// vm_patch_bindings_engine.dart.txt (non-compiled). Fork/engine-pack builds
// swap it in (engine-bindings branch / build tooling). The structural fix —
// extern "C" wrappers in the fork + dart:ffi runtime lookup, one codepath,
// filed Jul 15 as store-blocking — replaces this swap in an engine session.
import 'dart:typed_data' show Uint8List;

/// Sentinel: the Koolbase engine bindings are not present in this binary
/// (stock engine build). Distinct from engine rejection codes (-400/-405/...)
/// so patch_failed analytics can tell "no engine" from "engine said no".
const int kKoolbaseEngineAbsent = -990;

/// Apply a patch module. On the Koolbase engine: number of overrides applied
/// (>=0) or a negative engine error code. On stock (this stub): always
/// [kKoolbaseEngineAbsent] — flows through the caller's existing rejection
/// path (quarantine + patch_failed event, no crash).
int applyKoolbasePatch(Uint8List bytes) => kKoolbaseEngineAbsent;

/// The running binary's build_id (16 hex chars) read live from the engine.
/// Empty string when the engine did not compute one — which is definitionally
/// true on stock. Callers already treat '' as "fall through to other sources".
String koolbaseBuildId() => '';
