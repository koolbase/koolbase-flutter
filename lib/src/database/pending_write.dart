/// A change made offline, waiting to be sent.
///
/// The counterpart to [KoolbaseConflict], one step earlier in the lifecycle: a
/// conflict is a write the server refused; a pending write is one the server
/// has not seen yet. Both are durable state an app should surface — a queue
/// nobody can see accumulates invisibly, and the changes it holds feel saved
/// to the user while existing only on this device.
///
/// The case that makes this API matter: logout. Queues are per-user and
/// survive logout by design, so a user signing out with pending writes walks
/// away believing their edits saved — and they sync whenever that user next
/// signs in on this device, which may be never. Warn before logout:
///
/// ```dart
/// final pending = await Koolbase.db.pendingWrites();
/// if (pending.isNotEmpty) {
///   // "You have 3 unsynced changes. Sync now, or they wait until you
///   //  next sign in on this device."
/// }
/// ```
///
/// [Koolbase.db.pendingWrites] is a snapshot; [Koolbase.db.watchPendingWrites]
/// emits on every change, for a sync badge. Both are per-user: another
/// account's queue on this device is not visible here.
class PendingWrite {
  const PendingWrite({
    required this.id,
    required this.operation,
    required this.collection,
    this.recordId,
    this.data,
    required this.enqueuedAt,
    required this.attempts,
  });

  final String id;

  /// 'insert' | 'update' | 'delete'.
  final String operation;

  final String collection;

  /// Absent for an insert the server has not yet assigned.
  final String? recordId;

  /// What the user changed. Absent for a delete.
  final Map<String, dynamic>? data;

  final DateTime enqueuedAt;

  /// Failed send attempts so far. A count, not a policy — nothing drops it.
  final int attempts;
}
