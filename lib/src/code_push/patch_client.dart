import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../device_id.dart';

/// System B (VM-level) code-push client — companion to [KoolbaseCodePushClient]
/// (System A runtime bundles). This one ships compiled-Dart patches: it checks
/// the resolver for a patch matching the running binary, downloads the signed
/// .kbpatch, and stages it where the patched Flutter engine reads it at the
/// NEXT cold launch. The engine verifies (Ed25519 + build_id) and applies
/// before any Dart runs, then renames the staged file to mark it applied; on the
/// following launch this client reconciles that into the persisted current_patch.
///
/// Boot order makes the handshake work: engine init writes runtime_build_id and
/// applies any staged patch *before* Dart, so this client just reads the results.
///
/// Matching model (dual): the client sends whichever release identity it has.
/// - build_id (content hash) — self-distributed/sideloaded apps where the CLI
///   stamps the build_id. Engine verifies it cryptographically.
/// - release_version (store versionName+versionCode) — Play Store apps, the
///   only identity that survives Play App Signing. Sent when available.
class KoolbaseVmPatchClient {
  final String baseUrl;
  final String apiKey;
  final String channel;

  static const _tag = '[KoolbaseVmPatch]';
  static const _kCurrentPatch = 'koolbase_vm_current_patch';
  static const _kStagedPatch = 'koolbase_vm_staged_patch_number';

  Directory? _dir;
  bool _initialized = false;

  KoolbaseVmPatchClient({
    required this.baseUrl,
    required this.apiKey,
    this.channel = 'stable',
  });

  /// Shared directory both this client and the engine compute independently:
  /// `<platform-cache>/koolbase/vm/`. Must match the engine's path EXACTLY.
  ///
  /// - Android: <data>/code_cache/koolbase/vm. The engine receives
  ///   getCodeCacheDir() as temp_directory_path; path_provider's temp dir is
  ///   getCacheDir() (<data>/cache), so code_cache is its sibling — derived
  ///   here so the SDK needs no native MethodChannel.
  /// - macOS: HOME/Library/Application Support/koolbase/vm — matches the
  ///   engine's pure-C getenv("HOME")-based path (no bundle id).
  Future<Directory> _vmDir() async {
    if (_dir != null) return _dir!;
    String base;
    if (Platform.isAndroid) {
      // The engine reads patches from getCodeCacheDir() (<data>/code_cache),
      // which it receives as settings.temp_directory_path. path_provider's temp
      // dir is getCacheDir() (<data>/cache); code_cache is its sibling. Deriving
      // it here keeps the SDK pure-Dart — no app-side MethodChannel wiring.
      final cache = await getTemporaryDirectory();
      base = '${cache.parent.path}/code_cache';
    } else {
      // macOS (and fallback): HOME-based app support dir.
      final home = Platform.environment['HOME'];
      base = (home != null && home.isNotEmpty)
          ? '$home/Library/Application Support'
          : (await getApplicationSupportDirectory()).path;
    }
    final dir = Directory('$base/koolbase/vm');
    await dir.create(recursive: true);
    _dir = dir;
    debugPrint('$_tag vmDir=${dir.path}');
    return dir;
  }

  File _stagedFile(Directory d) => File('${d.path}/staged.kbpatch');
  File _appliedFile(Directory d) => File('${d.path}/applied.kbpatch');
  File _buildIdFile(Directory d) => File('${d.path}/runtime_build_id');
  File _bootPendingFile(Directory d) => File('${d.path}/boot_pending');

  /// The build_id the running binary advertises, for build_id-mode matching.
  /// Null when the app uses release_version matching (Play Store) or when the
  /// engine is unpatched. [override] lets a test inject a known build_id.
  Future<String?> runtimeBuildId({String? override}) async {
    if (override != null && override.isNotEmpty) return override;
    // 1. CLI-stamped build_id in the app bundle (production self-distributed).
    final stamped = await _stampedBuildId();
    if (stamped != null && stamped.isNotEmpty) return stamped;
    // 2. Android: CLI-stamped asset written by `koolbase build android`.
    //    Single-ABI builds store the bare build_id. A multi-ABI release AAB
    //    (one bundle, several ABIs) stores a JSON map {abi: build_id}; we pick
    //    the entry for the ABI THIS device is running, so every split reports
    //    its own build_id from the one uploaded artifact.
    if (Platform.isAndroid) {
      try {
        final raw =
            (await rootBundle.loadString('assets/koolbase_build_id')).trim();
        final resolved = await _resolveAndroidBuildId(raw);
        if (resolved != null && resolved.isNotEmpty) {
          debugPrint('$_tag android build_id resolved=$resolved');
          return resolved;
        }
      } catch (_) {
        // asset absent — fall through to the file/release_version paths
      }
    }
    // 3. Fallback: a file in the shared vm dir (tests / pre-seed).
    try {
      final f = _buildIdFile(await _vmDir());
      if (!await f.exists()) return null;
      return (await f.readAsString()).trim();
    } catch (_) {
      return null;
    }
  }

  /// Resolves the Android build_id from the stamped asset. The asset is either a
  /// bare build_id string (single-ABI build) or a JSON object {abi: build_id}
  /// (multi-ABI release AAB). For the map case we select the entry matching the
  /// ABI this device actually runs; an unknown ABI returns null so matching
  /// falls back to release_version rather than reporting a wrong build_id.
  Future<String?> _resolveAndroidBuildId(String raw) async {
    if (raw.isEmpty) return null;
    if (raw.startsWith('{')) {
      try {
        final map = (jsonDecode(raw) as Map).cast<String, dynamic>();
        final abi = _primaryAbi();
        if (abi != null && map[abi] is String) {
          return (map[abi] as String).trim();
        }
        debugPrint('$_tag build_id map present but ABI "$abi" not in it');
        return null;
      } catch (_) {
        return null;
      }
    }
    return raw; // legacy single-ABI bare build_id
  }

  /// The ABI this app is actually RUNNING as, read from the Dart VM itself
  /// (Abi.current()). NOT Build.SUPPORTED_ABIS[0]: on a 64-bit device that is
  /// the device's preferred ABI (arm64-v8a) even when the loaded split is
  /// 32-bit. Abi.current() reflects the split that actually loaded.
  String? _primaryAbi() {
    switch (Abi.current()) {
      case Abi.androidArm64:
        return 'arm64-v8a';
      case Abi.androidArm:
        return 'armeabi-v7a';
      case Abi.androidX64:
        return 'x86_64';
      case Abi.androidIA32:
        return 'x86';
      default:
        return null;
    }
  }

  /// Reads the CLI-stamped build_id from the app bundle (self-distributed mode).
  /// macOS: `<X.app>/Contents/Resources/koolbase_build_id`. Android stamping is
  /// CLI-asset based and read by the platform layer; returns null here so the
  /// runtimeBuildId fallback (engine-written file) or release_version is used.
  Future<String?> _stampedBuildId() async {
    try {
      if (Platform.isMacOS) {
        final exe = Platform.resolvedExecutable;
        final contents = File(exe).parent.parent.path; // <X.app>/Contents
        final f = File('$contents/Resources/koolbase_build_id');
        if (!await f.exists()) return null;
        return (await f.readAsString()).trim();
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// The store release version (versionName+versionCode) for release_version
  /// matching. Android only; resolved by the platform layer. Null elsewhere.
  Future<String?> releaseVersion() async {
    try {
      if (!Platform.isAndroid) return null;
      final info = await PackageInfo.fromPlatform();
      final name = info.version.isNotEmpty ? info.version : '0.0.0';
      return '$name+${info.buildNumber}';
    } catch (_) {
      return null;
    }
  }

  /// Current applied patch number (0 = base binary).
  Future<int> currentPatch() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kCurrentPatch) ?? 0;
  }

  /// Stable device id for rollout bucketing. Prefers the keychain-backed id;
  /// if secure storage is unavailable, falls back to a shared_prefs id so the
  /// check-in still works — device_id is non-critical bucketing data.
  Future<String> _deviceId() async {
    try {
      return await DeviceIdManager.getOrCreate();
    } catch (_) {
      final prefs = await SharedPreferences.getInstance();
      var id = prefs.getString('koolbase_vm_device_id');
      if (id == null || id.isEmpty) {
        id = 'dev-${DateTime.now().microsecondsSinceEpoch}';
        await prefs.setString('koolbase_vm_device_id', id);
      }
      return id;
    }
  }

  /// Reconcile + background check. Non-blocking, like System A.
  Future<void> init({String? buildIdOverride}) async {
    if (_initialized) return;
    _initialized = true;
    Future(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final d = await _vmDir();
        await _reconcileApplied(prefs, d);
        _scheduleHealthyMarkerClear(d);

        // Resolve the release identity we'll send. build_id takes precedence
        // (stricter); release_version is the Play-Store-compatible fallback.
        final buildId = await runtimeBuildId(override: buildIdOverride);
        final relVersion = await releaseVersion();
        if ((buildId == null || buildId.isEmpty) &&
            (relVersion == null || relVersion.isEmpty)) {
          debugPrint('$_tag no build_id and no release_version — skipping');
          return;
        }
        final current = prefs.getInt(_kCurrentPatch) ?? 0;
        await _check(
          prefs,
          d,
          buildId: buildId ?? '',
          releaseVersion: relVersion ?? '',
          currentPatch: current,
        );
      } catch (e) {
        debugPrint('$_tag init failed silently: $e');
      }
    });
  }

  /// Clears the engine's boot_pending marker once the app has demonstrably
  /// survived startup. The engine writes boot_pending before running a patched
  /// snapshot; if this app crashes before the delay elapses, the marker remains
  /// and the engine quarantines the bad patch + falls back on the next launch.
  /// A healthy app clears it, so good patches are never quarantined.
  void _scheduleHealthyMarkerClear(Directory d) {
    // ~5s of survival is a strong signal the patched code booted cleanly.
    Future.delayed(const Duration(seconds: 5), () async {
      try {
        final f = _bootPendingFile(d);
        if (await f.exists()) {
          await f.delete();
          debugPrint('$_tag healthy boot — cleared boot_pending');
        }
      } catch (e) {
        debugPrint('$_tag could not clear boot_pending: $e');
      }
    });
  }

  /// Reconcile after the engine's boot. In the durable-patch model the engine
  /// keeps applied.kbpatch on disk and re-applies it every launch, so this MUST
  /// NOT delete it. The signal that the engine just promoted our newly-staged
  /// patch is the staged patch-number we recorded plus the presence of
  /// applied.kbpatch. We bump current_patch once and clear only the staged
  /// number — the patch file itself stays durable.
  Future<void> _reconcileApplied(SharedPreferences prefs, Directory d) async {
    final staged = prefs.getInt(_kStagedPatch);
    if (staged == null) {
      return; // nothing staged → durable patch persists untouched
    }
    final applied = _appliedFile(d);
    if (await applied.exists()) {
      // Engine promoted staged → applied: the new patch booted.
      await prefs.setInt(_kCurrentPatch, staged);
      await prefs.remove(_kStagedPatch);
      debugPrint('$_tag engine applied patch #$staged — current_patch=$staged');
    } else {
      // Staged but no applied: engine did not apply it (e.g. verification
      // failed). Drop the stale staged marker; current_patch is unchanged.
      await prefs.remove(_kStagedPatch);
      debugPrint(
          '$_tag staged patch #$staged was not applied by engine — cleared');
    }
  }

  Future<void> _check(SharedPreferences prefs, Directory d,
      {required String buildId,
      required String releaseVersion,
      required int currentPatch}) async {
    final query = <String, String>{
      'platform': _platform(),
      'channel': channel,
      'device_id': await _deviceId(),
      'current_patch': currentPatch.toString(),
    };
    if (buildId.isNotEmpty) query['build_id'] = buildId;
    if (releaseVersion.isNotEmpty) query['release_version'] = releaseVersion;

    final uri = Uri.parse('$baseUrl/v1/code-push/patch-check')
        .replace(queryParameters: query);
    debugPrint('$_tag CHECK build_id=${query['build_id']} url=$uri');
    final res = await http.get(uri,
        headers: {'x-api-key': apiKey}).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      debugPrint('$_tag check HTTP ${res.statusCode}');
      return;
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    switch (body['status'] as String?) {
      case 'update_available':
        await _download(prefs, d, body['patch'] as Map<String, dynamic>);
        break;
      case 'rollback':
        await _rollback(prefs, d, body['revert_to'],
            body['patch'] as Map<String, dynamic>?);
        break;
      default:
        debugPrint('$_tag no update');
    }
  }

  /// Recall/kill-switch: the resolver told this device to revert. Remove the
  /// durable patch files so the engine finds nothing and boots the BASE binary
  /// on the next cold launch, and reset current_patch to the revert target.
  /// revert_to may arrive as an int or a string ("0"); we parse defensively.
  Future<void> _rollback(SharedPreferences prefs, Directory d, dynamic revertTo,
      Map<String, dynamic>? patch) async {
    var target = 0;
    if (revertTo is int) {
      target = revertTo;
    } else if (revertTo is String) {
      target = int.tryParse(revertTo) ?? 0;
    }

    // Reverting to a prior PUBLISHED patch (target > 0) and the server gave us
    // that patch's artifact: download + stage it so the engine applies the real
    // prior-patch code on the next launch. This is authoritative (server-chosen
    // target, verified download) and handles reverts to any prior patch.
    if (target > 0 && patch != null) {
      debugPrint('$_tag rollback to prior patch #$target — fetching artifact');
      await _download(prefs, d, patch);
      // _download stages the artifact and records it as the staged patch number;
      // reconcile on next launch promotes it to current. Leave applied.kbpatch
      // in place until the engine swaps in the staged one.
      return;
    }

    // Revert to base: remove the patch files so the engine boots the base binary.
    try {
      final applied = _appliedFile(d);
      if (await applied.exists()) await applied.delete();
      final staged = _stagedFile(d);
      if (await staged.exists()) await staged.delete();
    } catch (e) {
      debugPrint('$_tag rollback file cleanup error: $e');
    }
    await prefs.setInt(_kCurrentPatch, 0);
    await prefs.remove(_kStagedPatch);
    debugPrint('$_tag rollback to base — patch files cleared');
  }

  Future<void> _download(
      SharedPreferences prefs, Directory d, Map<String, dynamic> patch) async {
    final patchNumber = patch['patch_number'] as int;
    final url = patch['download_url'] as String;
    final checksum = patch['checksum'] as String? ?? '';
    debugPrint('$_tag downloading patch #$patchNumber...');
    final res =
        await http.get(Uri.parse(url)).timeout(const Duration(seconds: 60));
    if (res.statusCode != 200) {
      debugPrint('$_tag download failed: ${res.statusCode}');
      return;
    }
    final bytes = res.bodyBytes;
    if (!_checksumOk(bytes, checksum)) {
      debugPrint('$_tag checksum mismatch — discarding');
      return;
    }
    // Stage atomically: write .tmp then rename onto staged.kbpatch.
    final tmp = File('${d.path}/staged.kbpatch.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(_stagedFile(d).path);
    await prefs.setInt(_kStagedPatch, patchNumber);
    debugPrint(
        '$_tag patch #$patchNumber staged (${bytes.length} bytes) — applies next launch');
  }

  bool _checksumOk(List<int> bytes, String checksum) {
    if (checksum.isEmpty) return true; // tolerate missing (dev)
    final hex = sha256.convert(bytes).toString();
    final expected =
        checksum.startsWith('sha256:') ? checksum.substring(7) : checksum;
    return hex == expected;
  }

  String _platform() {
    try {
      if (Platform.isMacOS) return 'macos';
      if (Platform.isAndroid) return 'android';
      if (Platform.isIOS) return 'ios';
    } catch (_) {}
    return 'macos';
  }
}
