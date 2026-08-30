// VM-level code push — WEB STUB.
//
// System B stages compiled-Dart patches on disk and relies on a patched
// Flutter engine reading them at cold launch. Neither exists on the web:
// there is no filesystem to stage into and no VM to patch. The feature is
// not "unavailable pending work", it is structurally absent.
//
// This stub exists because the io implementation imports dart:io (and
// formerly dart:ffi), which the web frontend rejects at kernel compile --
// making the WHOLE package uncompilable for web through
// koolbase.dart -> patch_client.dart. Same failure shape as 9.4.0, which
// broke every customer build via a platform-private import on that exact
// path.
//
// Every method answers honestly rather than throwing: an app that happens
// to query patch state on web gets "nothing here", not a crash.
class KoolbaseVmPatchClient {
  KoolbaseVmPatchClient({
    required this.baseUrl,
    required this.apiKey,
    this.channel = 'stable',
  });

  final String baseUrl;
  final String apiKey;
  final String channel;

  Future<void> init({String? buildIdOverride}) async {}

  Future<String?> runtimeBuildId({String? override}) async => null;

  Future<String?> releaseVersion() async => null;

  Future<int> currentPatch() async => 0;

  Future<String?> runtimeFlutterVersion() async => null;
}
