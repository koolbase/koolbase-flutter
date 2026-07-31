/// What the user was trying to do when the write was refused.
enum ConflictOperation { update, delete }

/// Resolves conflicts by id.
///
/// Deliberately by id rather than by value: a conflict object handed to a UI can
/// sit there while someone decides, and in that time a sync pass may have
/// resolved it or another write may have superseded it. Acting on captured
/// values would write against a state that no longer exists, so the resolver
/// reloads the stored conflict before doing anything.
abstract interface class ConflictResolver {
  /// Reapply the user's change against the record as it is now.
  Future<void> resolveWithLocal(String conflictId);

  /// Keep the server's version and discard the user's change.
  Future<void> resolveWithServer(String conflictId);

  /// Apply a merged result the application composed from both versions.
  Future<void> resolveWithMerge(String conflictId, Map<String, dynamic> data);

  /// Drop the change without claiming either version won.
  Future<void> abandon(String conflictId);
}

/// A queued offline write the server would not apply, because the record changed
/// between the change being made and the queue reaching it.
///
/// Not an error to dismiss and not a write to retry: retrying cannot help, and
/// discarding it would lose a change the user believes is saved. It waits, and
/// keeps waiting across restarts, until the application decides.
///
/// Only the application can decide. Whether a later edit should win depends on
/// what the data means, and a platform that chooses for everyone is wrong for
/// someone.
class KoolbaseConflict {
  KoolbaseConflict({
    required this.id,
    required this.collection,
    required this.recordId,
    required this.operation,
    required this.baseline,
    required this.local,
    required this.server,
    required this.baseRevision,
    required this.serverRevision,
    required this.createdAt,
    required ConflictResolver resolver,
  }) : _resolver = resolver;

  final String id;
  final String collection;
  final String recordId;
  final ConflictOperation operation;

  /// The record as it was when the change was composed.
  final Map<String, dynamic>? baseline;

  /// The change the user made, still unapplied.
  final Map<String, dynamic>? local;

  /// The record as the server held it when the write was refused. Captured with
  /// the refusal, so showing both versions costs no fetch and cannot race one.
  final Map<String, dynamic>? server;

  final int? baseRevision;
  final int? serverRevision;
  final DateTime createdAt;

  final ConflictResolver _resolver;

  /// Fields where the user's change and the server's version disagree.
  ///
  /// Only the fields the change touches: a record accumulates values the write
  /// never asserted, and listing those would bury the real disagreement.
  List<String> get divergentFields {
    final change = local;
    if (change == null) return const [];
    final current = server;
    if (current == null) return change.keys.toList();
    return change.entries
        .where((e) => '${current[e.key]}' != '${e.value}')
        .map((e) => e.key)
        .toList();
  }

  /// How long this has been waiting.
  ///
  /// Metadata, not a deletion rule. Conflicts do not expire on their own: a
  /// buildup is a signal worth seeing, and expiring them would hide it while
  /// reintroducing the loss this exists to prevent.
  Duration get age => DateTime.now().difference(createdAt);

  /// Reapplies the user's change to the record as it stands now.
  ///
  /// An explicit decision to overwrite the server's version of the fields that
  /// disagree. Conditional on the revision the conflict recorded, so if the
  /// record has moved again while someone was deciding, this produces a new
  /// conflict rather than overwriting blindly.
  Future<void> resolveWithLocal() => _resolver.resolveWithLocal(id);

  /// Keeps the server's version and discards the user's change.
  ///
  /// Recorded as a decision rather than a silent deletion.
  Future<void> resolveWithServer() => _resolver.resolveWithServer(id);

  /// Applies a merged result the application composed from both versions.
  ///
  /// Also conditional: the record may have moved again while the merge was being
  /// made, and this can conflict in turn.
  Future<void> resolveWithMerge(Map<String, dynamic> data) =>
      _resolver.resolveWithMerge(id, data);

  /// Drops the change without claiming either version won.
  ///
  /// For when the original intent no longer applies.
  Future<void> abandon() => _resolver.abandon(id);

  @override
  String toString() => 'KoolbaseConflict(${operation.name} '
      '$collection/$recordId, ${divergentFields.join(", ")})';
}
