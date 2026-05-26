import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'offline/cache_store.dart';
import 'offline/local_database.dart';
import 'offline/write_queue.dart';

class SyncEngine {
  final String baseUrl;
  final String publicKey;
  final CacheStore cacheStore;
  final WriteQueue writeQueue;

  /// Pulls a currently-valid user access token at sync time (refresh-aware) so
  /// replayed offline writes carry the user's identity instead of going up
  /// anonymously. Wired to KoolbaseAuthClient.validAccessToken.
  final Future<String?> Function()? accessTokenProvider;

  StreamSubscription? _connectivitySubscription;

  SyncEngine({
    required this.baseUrl,
    required this.publicKey,
    required this.cacheStore,
    required this.writeQueue,
    this.accessTokenProvider,
  });

  // ─── Start auto-sync on reconnect ─────────────────────────────────────────

  void start() {
    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen((results) {
      final isConnected = results.any((r) => r != ConnectivityResult.none);
      if (isConnected) {
        debugPrint('[Koolbase] Network restored — syncing pending writes');
        syncPendingWrites();
      }
    });
  }

  void dispose() {
    _connectivitySubscription?.cancel();
  }

  // ─── Sync pending writes ───────────────────────────────────────────────────

  Future<void> syncPendingWrites() async {
    final writes = await writeQueue.getPending();

    for (final write in writes) {
      // Drop writes that have exceeded max retries
      if (await writeQueue.shouldDrop(write.id)) {
        debugPrint(
            '[Koolbase] Dropping failed write after max retries: ${write.id}');
        await writeQueue.remove(write.id);
        continue;
      }

      try {
        await _executeWrite(write);
        await writeQueue.remove(write.id);
        // Invalidate cache for this collection so next read is fresh
        await cacheStore.invalidateCollection(write.collection);
      } catch (e) {
        debugPrint('[Koolbase] Write sync failed for ${write.id}: $e');
        await writeQueue.incrementRetry(write.id);
        // Continue to next write — don't block the queue
      }
    }
  }

  // ─── Execute a single write against the API ───────────────────────────────

  Future<void> _executeWrite(PendingWrite write) async {
    final payload = writeQueue.decodePayload(write);
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'x-api-key': publicKey,
    };
    final token = await accessTokenProvider?.call();
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    switch (write.operation) {
      case 'insert':
        final res = await http
            .post(
              Uri.parse('$baseUrl/v1/sdk/db/insert'),
              headers: headers,
              body: jsonEncode({
                'collection': write.collection,
                'data': payload,
              }),
            )
            .timeout(const Duration(seconds: 10));
        if (res.statusCode != 201) {
          throw Exception('Insert failed: ${res.statusCode}');
        }
        break;

      case 'update':
        if (write.recordId == null) {
          throw Exception('recordId required for update');
        }
        final res = await http
            .patch(
              Uri.parse('$baseUrl/v1/sdk/db/records/${write.recordId}'),
              headers: headers,
              body: jsonEncode({'data': payload}),
            )
            .timeout(const Duration(seconds: 10));
        if (res.statusCode != 200) {
          throw Exception('Update failed: ${res.statusCode}');
        }
        break;

      case 'delete':
        if (write.recordId == null) {
          throw Exception('recordId required for delete');
        }
        final res = await http
            .delete(
              Uri.parse('$baseUrl/v1/sdk/db/records/${write.recordId}'),
              headers: headers,
            )
            .timeout(const Duration(seconds: 10));
        if (res.statusCode != 204) {
          throw Exception('Delete failed: ${res.statusCode}');
        }
        break;

      default:
        throw Exception('Unknown operation: ${write.operation}');
    }
  }
}
