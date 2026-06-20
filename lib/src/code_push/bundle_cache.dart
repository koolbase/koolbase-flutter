import 'dart:io';
import 'package:path_provider/path_provider.dart';

enum CacheSlot { pending, ready, active, archive }

class BundleCache {
  static BundleCache? _instance;
  late final Directory _root;

  BundleCache._();

  static Future<BundleCache> init() async {
    if (_instance != null) return _instance!;
    final base = await getApplicationSupportDirectory();
    final cache = BundleCache._();
    cache._root = Directory('${base.path}/koolbase/code_push');
    for (final slot in CacheSlot.values) {
      await Directory('${cache._root.path}/${slot.name}')
          .create(recursive: true);
    }
    _instance = cache;
    return cache;
  }

  Directory _dir(CacheSlot slot) => Directory('${_root.path}/${slot.name}');

  File _file(CacheSlot slot, String bundleId) =>
      File('${_dir(slot).path}/$bundleId.zip');

  Future<bool> exists(CacheSlot slot, String bundleId) =>
      _file(slot, bundleId).exists();

  Future<File> write(CacheSlot slot, String bundleId, List<int> bytes) async {
    final file = _file(slot, bundleId);
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<File?> get(CacheSlot slot, String bundleId) async {
    final file = _file(slot, bundleId);
    return await file.exists() ? file : null;
  }

  Future<void> promote(
    String bundleId, {
    required CacheSlot from,
    required CacheSlot to,
  }) async {
    final src = _file(from, bundleId);
    final dst = _file(to, bundleId);
    await src.rename(dst.path);
  }

  Future<void> delete(CacheSlot slot, String bundleId) async {
    final file = _file(slot, bundleId);
    if (await file.exists()) await file.delete();
  }

  // Returns the single zip file in a slot, or null
  Future<File?> slotFile(CacheSlot slot) async {
    final files =
        await _dir(slot).list().where((f) => f.path.endsWith('.zip')).toList();
    if (files.isEmpty) return null;
    return File(files.first.path);
  }

  String bundleIdFromFile(File file) =>
      file.uri.pathSegments.last.replaceAll('.zip', '');

  // Pending-revert marker. Written when the server tells this device to roll
  // back (kill-switch); consumed at the start of the next cold launch so the
  // loader reverts BEFORE applying any stored bundle. A plain file so it
  // survives process death the same way the slot zips do.
  File get _revertMarker => File('${_root.path}/revert.marker');

  Future<void> setPendingRevert(int revertTo) async {
    await _revertMarker.writeAsString(revertTo.toString(), flush: true);
  }

  // Reads and clears the pending-revert marker. Returns null when none is set.
  Future<int?> takePendingRevert() async {
    if (!await _revertMarker.exists()) return null;
    try {
      final raw = (await _revertMarker.readAsString()).trim();
      await _revertMarker.delete();
      return int.tryParse(raw);
    } catch (_) {
      if (await _revertMarker.exists()) await _revertMarker.delete();
      return null;
    }
  }

  // Clear all slots — used for testing
  Future<void> clearAll() async {
    for (final slot in CacheSlot.values) {
      final dir = _dir(slot);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        await dir.create();
      }
    }
    if (await _revertMarker.exists()) await _revertMarker.delete();
  }
}
