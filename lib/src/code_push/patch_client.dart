import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../device_id.dart';

/// System B (VM-level) code-push client — companion to [KoolbaseCodePushClient]
/// (System A runtime bundles). This one ships compiled-Dart patches: it checks
/// the resolver for a patch matching the running binary's build_id, downloads
/// the signed .kbpatch, and stages it where the patched Flutter engine reads it
/// at the NEXT cold launch. The engine verifies (Ed25519 + build_id) and applies
/// before any Dart runs, then renames the staged file to mark it applied; on the
/// following launch this client reconciles that into the persisted current_patch.
///
/// Boot order makes the handshake work: engine init writes runtime_build_id and
/// applies any staged patch *before* Dart, so this client just reads the results.
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
  /// `<app-support>/koolbase/vm/`. Keep these in lockstep with the engine.
  Future<Directory> _vmDir() async {
    if (_dir != null) return _dir!;
    // Must match the engine's pure-C path exactly: getenv("HOME") +
    // "/Library/Application Support/koolbase/vm" (no bundle id). We use the
    // same HOME-based path rather than getApplicationSupportDirectory (which
    // appends the bundle id on macOS).
    final home = Platform.environment['HOME'];
    final base = (home != null && home.isNotEmpty)
        ? '$home/Library/Application Support'
        : (await getApplicationSupportDirectory()).path;
    final dir = Directory('$base/koolbase/vm');
    await dir.create(recursive: true);
    _dir = dir;
    return dir;
  }

  File _stagedFile(Directory d) => File('${d.path}/staged.kbpatch');
  File _appliedFile(Directory d) => File('${d.path}/applied.kbpatch');
  File _buildIdFile(Directory d) => File('${d.path}/runtime_build_id');

  /// The build_id the engine wrote this boot. Null if the engine hasn't written
  /// it (e.g. an unpatched engine) — in which case we skip silently. [override]
  /// lets a test inject a known build_id before the engine wires it up.
  Future<String?> runtimeBuildId({String? override}) async {
    if (override != null && override.isNotEmpty) return override;
    // 1. CLI-stamped build_id in the app bundle (production path).
    final stamped = await _stampedBuildId();
    if (stamped != null && stamped.isNotEmpty) return stamped;
    // 2. Fallback: a file in the shared vm dir (tests / pre-seed).
    try {
      final f = _buildIdFile(await _vmDir());
      if (!await f.exists()) return null;
      return (await f.readAsString()).trim();
    } catch (_) {
      return null;
    }
  }

  /// Reads the build_id the CLI stamped into the app bundle. macOS only for
  /// `now: <X.app>/Contents/Resources/koolbase_build_id, derived from the`
  /// `running executable (<X.app>/Contents/MacOS/<exe>). iOS/Android later.`
  Future<String?> _stampedBuildId() async {
    try {
      if (!Platform.isMacOS) return null;
      final exe = Platform.resolvedExecutable;
      final contents = File(exe).parent.parent.path; // <X.app>/Contents
      final f = File('$contents/Resources/koolbase_build_id');
      if (!await f.exists()) return null;
      return (await f.readAsString()).trim();
    } catch (_) {
      return null;
    }
  }

  /// Current applied patch number (0 = base binary).
  Future<int> currentPatch() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kCurrentPatch) ?? 0;
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

        final buildId = await runtimeBuildId(override: buildIdOverride);
        if (buildId == null || buildId.isEmpty) {
          debugPrint('$_tag no runtime build_id — engine unpatched? skipping');
          return;
        }
        final current = prefs.getInt(_kCurrentPatch) ?? 0;
        await _check(prefs, d, buildId: buildId, currentPatch: current);
      } catch (e) {
        debugPrint('$_tag init failed silently: $e');
      }
    });
  }

  /// If the engine left an applied.kbpatch, promote staged number → current.
  Future<void> _reconcileApplied(SharedPreferences prefs, Directory d) async {
    final applied = _appliedFile(d);
    if (!await applied.exists()) return;
    final staged = prefs.getInt(_kStagedPatch);
    if (staged != null) {
      await prefs.setInt(_kCurrentPatch, staged);
      await prefs.remove(_kStagedPatch);
      debugPrint('$_tag engine applied patch #$staged — current_patch=$staged');
    }
    await applied.delete();
  }

  Future<void> _check(SharedPreferences prefs, Directory d,
      {required String buildId, required int currentPatch}) async {
    final uri = Uri.parse('$baseUrl/v1/code-push/patch-check').replace(
      queryParameters: {
        'build_id': buildId,
        'platform': _platform(),
        'channel': channel,
        'device_id': await DeviceIdManager.getOrCreate(),
        'current_patch': currentPatch.toString(),
      },
    );
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
        debugPrint('$_tag rollback requested (revert_to ${body['revert_to']})');
        break;
      default:
        debugPrint('$_tag no update');
    }
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
