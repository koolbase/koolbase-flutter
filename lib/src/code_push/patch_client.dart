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
import 'vm_patch_bindings.dart' as vm;

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
  bool _newPatchThisLaunch = false;

  // iOS boot-apply outcome, consumed by _reconcileApplied so bookkeeping
  // reflects what ACTUALLY applied this boot instead of inferring from the
  // presence of applied.kbc (which lies after a staged-reject fallback).
  _IosBootOutcome _iosBootOutcome = _IosBootOutcome.none;

  /// True when a NEWLY downloaded patch (staged.kbc) was applied on this
  /// cold launch — i.e. the user just received an update. The routine
  /// re-apply of the durable applied.kbc does NOT set this. Flips shortly
  /// after init() (the apply runs async); sample it, don't read once.
  bool get appliedThisLaunch => _newPatchThisLaunch;

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
    } else if (Platform.isIOS) {
      // iOS: Platform.environment['HOME'] is NULL on release builds
      // (device-proven), so derive Application Support via path_provider — the
      // per-app container's own dir, writable and not system-purged. This is
      // where iOS stages/applies .kbc patches from Dart at boot.
      base = (await getApplicationSupportDirectory()).path;
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

  // iOS applies patches from Dart (this client), so it uses distinct .kbc names.
  // The engine's Android whole-blob hook reads staged.kbpatch/applied.kbpatch at
  // snapshot load; keeping iOS on .kbc leaves that (iOS-forbidden, exec-copy)
  // hook dormant. Android/macOS keep .kbpatch so the engine handshake works.
  File _stagedFile(Directory d) =>
      File('${d.path}/${Platform.isIOS ? "staged.kbc" : "staged.kbpatch"}');
  File _appliedFile(Directory d) =>
      File('${d.path}/${Platform.isIOS ? "applied.kbc" : "applied.kbpatch"}');

  File _buildIdFile(Directory d) => File('${d.path}/runtime_build_id');
  File _bootPendingFile(Directory d) => File('${d.path}/boot_pending');

  /// The build_id the running binary advertises, for build_id-mode matching.
  /// Null when the app uses release_version matching (Play Store) or when the
  /// engine is unpatched. [override] lets a test inject a known build_id.
  Future<String?> runtimeBuildId({String? override}) async {
    if (override != null && override.isNotEmpty) return override;
    // iOS: read the build_id live from the engine (SHA-256(instr)[0:8] via the
    // Internal_koolbaseBuildId native). No CLI stamping, no asset — the engine
    // is the authority and computes it at snapshot load. Device-proven to equal
    // the CLI's analyzeMachO derivation, so build_id-mode matching resolves.
    if (Platform.isIOS) {
      try {
        final id = vm.koolbaseBuildId();
        if (id.isNotEmpty) {
          debugPrint('$_tag ios build_id (engine native)=$id');
          return id;
        }
      } catch (e) {
        debugPrint('$_tag ios koolbaseBuildId failed: $e');
      }
    }
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
    // AWAITED phase — local disk only, no network. On iOS the boot-apply
    // runs to completion here, BEFORE the caller proceeds to runApp: the
    // first frame is already patched, so users never see a v1→v2 flash.
    // Device-measured cost ~5ms (Phase 8, Kobby). Failures degrade to a
    // clean base boot; they never block startup.
    SharedPreferences? prefs;
    Directory? d;
    try {
      prefs = await SharedPreferences.getInstance();
      d = await _vmDir();
      // iOS has no engine apply step (Android patches in the engine at
      // snapshot load). On iOS this client applies staged.kbc from Dart at
      // boot — promoting staged→applied — so the reconcile below sees the
      // same disk state Android's engine produces.
      if (Platform.isIOS) {
        await _applyPendingPatchIOS(d);
      }
      await _reconcileApplied(prefs, d);
      _scheduleHealthyMarkerClear(d);
    } catch (e) {
      debugPrint('$_tag boot phase failed silently: $e');
      return;
    }
    // BACKGROUND phase — network check/download, never blocks startup.
    Future(() async {
      try {

        // Resolve the release identity we'll send. build_id takes precedence
        // (stricter); release_version is the Play-Store-compatible fallback.
        final buildId = await runtimeBuildId(override: buildIdOverride);
        final relVersion = await releaseVersion();
        final fVersion = await runtimeFlutterVersion();
        if ((buildId == null || buildId.isEmpty) &&
            (relVersion == null || relVersion.isEmpty)) {
          debugPrint('$_tag no build_id and no release_version — skipping');
          return;
        }
        final current = prefs!.getInt(_kCurrentPatch) ?? 0;
        await _check(
          prefs,
          d!,
          buildId: buildId ?? '',
          releaseVersion: relVersion ?? '',
          flutterVersion: fVersion ?? '',
          currentPatch: current,
        );
      } catch (e) {
        debugPrint('$_tag init failed silently: $e');
      }
    });
  }

  /// iOS boot-time apply. Reads staged.kbc (a fresh download) or, failing that,
  /// re-applies the durable applied.kbc, via the engine's dart:_internal
  /// applyKoolbasePatch native. Mirrors the Android engine hook in Dart:
  ///   - boot_pending present at entry => the last patched boot crashed before
  ///     the healthy marker cleared => quarantine the active patch, boot base.
  ///   - staged wins over applied (fresh download beats durable).
  ///   - success promotes staged→applied (durable re-apply next boot).
  ///   - a rejected staged (n<0) is quarantined to bad.kbc, then we fall back
  ///     to applied.kbc in the SAME boot so a bad download never costs the user
  ///     their working patch.
  /// The KBPM signature + build_id checks happen inside the native; a negative
  /// return is a clean rejection, never a crash.
  Future<void> _applyPendingPatchIOS(Directory d) async {
    final staged = _stagedFile(d);
    final applied = _appliedFile(d);
    final bad = File('${d.path}/bad.kbc');
    final bootPending = _bootPendingFile(d);

    try {
      // Crash quarantine: marker still present => previous patched boot died.
      if (await bootPending.exists()) {
        if (await staged.exists()) {
          await staged.rename(bad.path);
        } else if (await applied.exists()) {
          await applied.rename(bad.path);
        }
        await bootPending.delete();
        _iosBootOutcome = _IosBootOutcome.baseBoot;
        debugPrint(
            '$_tag ios CRASH-REVERT: quarantined active patch, base boot');
        return;
      }

      Future<bool> tryApply(File f, {required bool fromStaged}) async {
        final bytes = await f.readAsBytes();
        await bootPending.writeAsBytes(const [1], flush: true);
        final n = vm.applyKoolbasePatch(bytes);
        if (n >= 0) {
          if (fromStaged) await staged.rename(applied.path); // promote
          if (fromStaged) _newPatchThisLaunch = true;
          _iosBootOutcome = fromStaged
              ? _IosBootOutcome.stagedApplied
              : _IosBootOutcome.durableApplied;
          debugPrint('$_tag ios boot-applied n=$n '
              '(${fromStaged ? "staged->applied" : "applied"}, ${bytes.length}b)');
          return true;
        }
        // Rejected (bad sig -405 / wrong build_id -400 / malformed): no crash.
        await bootPending.delete();
        // Quarantine the rejected file either way: a rejected durable (stale
        // build_id after an app update, or disk corruption) would otherwise be
        // re-read and re-rejected on every boot forever.
        await f.rename(bad.path);
        _postEvent('patch_failed', metadata: {'code': n, 'from': fromStaged ? 'staged' : 'applied'});
        debugPrint('$_tag ios apply REJECT n=$n '
            '(${fromStaged ? "staged" : "applied"}->bad.kbc)');
        return false;
      }

      if (await staged.exists()) {
        if (await tryApply(staged, fromStaged: true)) return;
        // staged rejected → same-boot fallback to durable applied.
        if (!(await applied.exists()) ||
            !(await tryApply(applied, fromStaged: false))) {
          _iosBootOutcome = _IosBootOutcome.baseBoot;
        }
        return;
      }
      if (await applied.exists()) {
        if (!(await tryApply(applied, fromStaged: false))) {
          _iosBootOutcome = _IosBootOutcome.baseBoot;
        }
      } else {
        _iosBootOutcome = _IosBootOutcome.baseBoot;
      }
    } catch (e) {
      debugPrint('$_tag ios boot-apply error: $e');
    }
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
        // A healthy boot also means any quarantined patch is dead history:
        // remove bad.kbc so rejected artifacts don't linger on disk.
        final bad = File('${d.path}/bad.kbc');
        if (await bad.exists()) {
          await bad.delete();
          debugPrint('$_tag healthy boot — removed quarantined bad.kbc');
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
    // iOS: the boot-apply above knows the real outcome — use it instead of
    // inferring from applied.kbc's presence (which lies after a staged-reject
    // same-boot fallback: the file holds the PRIOR patch's bytes, not the
    // staged one's) and also handles crash-revert/stale-patch base boots by
    // resetting current_patch so the device never reports a patch it isn't
    // running.
    if (Platform.isIOS && _iosBootOutcome != _IosBootOutcome.none) {
      final marker = prefs.getInt(_kStagedPatch);
      switch (_iosBootOutcome) {
        case _IosBootOutcome.stagedApplied:
          if (marker != null) {
            await prefs.setInt(_kCurrentPatch, marker);
            await prefs.remove(_kStagedPatch);
            _postEvent('patch_activated', patchNumber: marker);
            debugPrint(
                '$_tag ios boot applied patch #$marker — current_patch=$marker');
          }
          return;
        case _IosBootOutcome.durableApplied:
          if (marker != null) {
            await prefs.remove(_kStagedPatch);
            debugPrint(
                '$_tag ios staged #$marker rejected — current_patch unchanged');
          }
          return;
        case _IosBootOutcome.baseBoot:
          if (marker != null) await prefs.remove(_kStagedPatch);
          if ((prefs.getInt(_kCurrentPatch) ?? 0) != 0) {
            await prefs.setInt(_kCurrentPatch, 0);
            debugPrint('$_tag ios base boot — current_patch=0');
          }
          return;
        case _IosBootOutcome.none:
          break; // unreachable (guarded above); fall through to legacy
      }
    }
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

  /// The Flutter version this binary was built against, for the resolver's
  /// engine guard. CLI-stamped into assets/koolbase_flutter_version by
  /// `koolbase build` / `koolbase release` (a bare string, identical across
  /// ABIs — unlike build_id there is no per-ABI map). Null when the asset is
  /// absent (older builds, or apps built before the stamping CLI shipped), in
  /// which case no flutter_version is sent and the server falls back to legacy
  /// matching — so this is fully backward-compatible.
  Future<String?> runtimeFlutterVersion() async {
    try {
      final v = (await rootBundle.loadString('assets/koolbase_flutter_version'))
          .trim();
      if (v.isEmpty) return null;
      debugPrint('$_tag flutter_version resolved=$v');
      return v;
    } catch (_) {
      // asset absent — fall back to legacy (no flutter_version sent)
      return null;
    }
  }

  Future<void> _check(SharedPreferences prefs, Directory d,
      {required String buildId,
      required String releaseVersion,
      required String flutterVersion,
      required int currentPatch}) async {
    final query = <String, String>{
      'platform': _platform(),
      'channel': channel,
      'device_id': await _deviceId(),
      'current_patch': currentPatch.toString(),
    };
    if (buildId.isNotEmpty) query['build_id'] = buildId;
    if (releaseVersion.isNotEmpty) query['release_version'] = releaseVersion;
    if (flutterVersion.isNotEmpty) query['flutter_version'] = flutterVersion;

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
    _postEvent('patch_downloaded', patchNumber: patchNumber);
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

  /// Fire-and-forget event report so the resolver/dashboard sees real
  /// device outcomes (patch_downloaded / patch_activated / patch_failed)
  /// instead of inferring installs from patch_check_served. Never awaited
  /// on the boot path; failures are silent.
  void _postEvent(String eventType, {int? patchNumber, Map<String, dynamic>? metadata}) {
    Future(() async {
      try {
        final body = <String, dynamic>{
          'device_id': await _deviceId(),
          'app_version': '',
          'platform': _platform(),
          'channel': channel,
          'event_type': eventType,
          if (metadata != null || patchNumber != null)
            'metadata': {
              if (patchNumber != null) 'patch_number': patchNumber,
              ...?metadata,
            },
        };
        await http
            .post(Uri.parse('$baseUrl/v1/code-push/patch-events'),
                headers: {'x-api-key': apiKey, 'Content-Type': 'application/json'},
                body: jsonEncode(body))
            .timeout(const Duration(seconds: 10));
      } catch (e) {
        debugPrint('$_tag event $eventType not recorded: $e');
      }
    });
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

/// What the iOS boot-apply actually did this launch. Set by
/// _applyPendingPatchIOS, consumed by _reconcileApplied (iOS branch only).
enum _IosBootOutcome { none, stagedApplied, durableApplied, baseBoot }
