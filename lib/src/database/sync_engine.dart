import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'database_exceptions.dart';
import 'offline/cache_store.dart';
import 'offline/local_database.dart';
import 'offline/write_queue.dart';

/// Raised when a queued write cannot be replayed no matter how many times it is
/// tried — an update or delete with no record id, or an operation the SDK does
/// not recognise.
///
/// Distinct from a transient failure so the queue can discard it immediately
/// rather than retrying it to death or holding it forever. The two sync
/// implementations this file replaced did one of those each.
class _MalformedWrite implements Exception {
  final String reason;
  const _MalformedWrite(this.reason);
  @override
  String toString() => reason;
}

class SyncEngine {
  final String baseUrl;
  final String publicKey;
  final CacheStore cacheStore;
  final WriteQueue writeQueue;

  /// Pulls a currently-valid user access token at sync time (refresh-aware) so
  /// replayed offline writes carry the user's identity instead of going up
  /// anonymously. Wired to KoolbaseAuthClient.validAccessToken.
  final Future<String?> Function()? accessTokenProvider;

  /// The user the current session belongs to.
  ///
  /// A queued write is only replayed under a session for the same user: the
  /// queue is per-device and outlives sessions, so replaying without this
  /// would attribute one user's offline work to whoever signed in next.
  final String? Function()? currentUserId;

  /// Called when the server rejects the session token itself.
  ///
  /// Background sync is the likeliest place to meet a dead session: the queue
  /// replays writes made while offline, potentially long after the session that
  /// made them stopped being honoured. Without this the pass burns a retry per
  /// write until each is dropped -- losing the data to an auth failure that has
  /// nothing to do with it.
  final Future<void> Function()? onSessionExpired;

  StreamSubscription? _connectivitySubscription;

  SyncEngine({
    required this.baseUrl,
    required this.publicKey,
    required this.cacheStore,
    required this.writeQueue,
    this.accessTokenProvider,
    this.currentUserId,
    this.onSessionExpired,
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
    final currentUser = currentUserId?.call();

    // Records whose chain stopped this pass, so later writes for them are held
    // rather than applied against a state their baseline does not describe.
    final blocked = <String?>{};

    for (final write in writes) {
      if (write.recordId != null && blocked.contains(write.recordId)) {
        debugPrint(
            '[Koolbase] Holding ${write.id}: an earlier write for this record is unresolved');
        continue;
      }

      // A queued write belongs to the session that made it. The queue is
      // per-device and outlives sessions, so replaying under a different
      // token would attribute one user's offline work to another. Writes
      // with no recorded owner predate schema v3 and are never replayed.
      if (write.userId != currentUser) {
        debugPrint(
            '[Koolbase] Skipping queued write ${write.id}: not this session\'s');
        continue;
      }
      // Drop writes that have exceeded max retries
      if (await writeQueue.shouldDrop(write.id)) {
        debugPrint(
            '[Koolbase] Dropping failed write after max retries: ${write.id}');
        await writeQueue.remove(write.id);
        continue;
      }

      try {
        final applied = await _executeWrite(write);
        await writeQueue.remove(write.id);
        // Anything queued behind this for the same record was composed against
        // this write's result, and now knows the revision that result carries.
        if (write.recordId != null) {
          await writeQueue.advanceChainRevision(write.recordId!, applied);
        }
        // Invalidate cache for this collection so next read is fresh
        await cacheStore.invalidateCollection(write.collection);
      } on KoolbaseRevisionMismatchException catch (e) {
        // The record moved since this write was composed. Not a failure to
        // retry — retrying cannot help, and the retry counter would discard the
        // write after three passes, which is the silent loss this exists to
        // prevent. It becomes durable unresolved state instead.
        debugPrint('[Koolbase] Conflict on ${write.id}: the record has changed');
        await writeQueue.moveToConflict(write, e);
        // Everything queued after this for the same record was composed against
        // the state this write would have produced. Replaying those now would
        // apply them against a state their baselines never described.
        blocked.add(write.recordId);
      } on _MalformedWrite catch (e) {
        // Cannot succeed on any attempt. Retrying would burn the budget and
        // then drop it anyway; keeping it would hold it forever.
        debugPrint('[Koolbase] Discarding unreplayable write ${write.id}: $e');
        await writeQueue.remove(write.id);
      } on KoolbaseSessionExpiredException {
        // The session is gone, so nothing else in the queue can succeed
        // either. Stop rather than spending a retry on every remaining write
        // against a token the server has already refused. onSessionExpired has
        // cleared the session; the queue is intact and replays after login.
        debugPrint('[Koolbase] Sync stopped: the session was rejected');
        return;
      } catch (e) {
        debugPrint('[Koolbase] Write sync failed for ${write.id}: $e');
        await writeQueue.incrementRetry(write.id);
        // Continue to next write — don't block the queue
      }
    }
  }

  // ─── Execute a single write against the API ───────────────────────────────

  /// Sends one queued write, returning the revision the record now carries.
  ///
  /// The revision matters to whatever is queued behind this for the same record:
  /// those writes were composed against this one's result and cannot know its
  /// revision until the server assigns it.
  Future<int?> _executeWrite(PendingWrite write) async {
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
          throw await koolbaseDataErrorNotifying(res,
              onSessionExpired: onSessionExpired, fallbackMessage: 'Insert sync failed');
        }
        return _revisionOf(res);

      case 'update':
        if (write.recordId == null) {
          throw const _MalformedWrite('update has no record id');
        }
        final res = await http
            .patch(
              Uri.parse('$baseUrl/v1/sdk/db/records/${write.recordId}'),
              headers: headers,
              // The revision the write was composed against. The server applies
              // the change only if the record still carries it, so nothing can
              // land between the client deciding the write is safe and the
              // server applying it. Replay is where this guarantee belongs:
              // hours may have passed since the user made the change.
              body: jsonEncode({
                'data': payload,
                if (write.baseRevision != null)
                  'expected_revision': write.baseRevision,
              }),
            )
            .timeout(const Duration(seconds: 10));
        if (res.statusCode != 200) {
          throw await koolbaseDataErrorNotifying(res,
              onSessionExpired: onSessionExpired, fallbackMessage: 'Update sync failed');
        }
        return _revisionOf(res);

      case 'delete':
        if (write.recordId == null) {
          throw const _MalformedWrite('delete has no record id');
        }
        final res = await http
            .delete(
              Uri.parse(
                  '$baseUrl/v1/sdk/db/records/${write.recordId}${write.baseRevision != null ? '?expected_revision=${write.baseRevision}' : ''}'),
              headers: headers,
            )
            .timeout(const Duration(seconds: 10));
        if (res.statusCode != 204) {
          throw await koolbaseDataErrorNotifying(res,
              onSessionExpired: onSessionExpired, fallbackMessage: 'Delete sync failed');
        }
        return null;

      default:
        throw _MalformedWrite('unknown operation "${write.operation}"');
    }
  }

  /// The revision from a write response, when the body carries one.
  int? _revisionOf(http.Response res) {
    try {
      final body = jsonDecode(res.body);
      if (body is Map<String, dynamic>) {
        return (body[r'\$revision'] as num?)?.toInt();
      }
    } catch (_) {}
    return null;
  }
}
