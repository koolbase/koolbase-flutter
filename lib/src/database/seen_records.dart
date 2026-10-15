import 'database_models.dart';

/// What this app has read of each record, in memory, for as long as it runs
/// (#103).
///
/// A detail screen opened from a list shows the record at once from here
/// while it asks the server -- saved-first, as [KoolbaseDocRef.getSaved]
/// promises. A device with offline storage has its record cache for that;
/// the web build has none, so every detail screen started on a loader even
/// though the list had just shown the record.
///
/// Never an offline baseline: an edit made offline composes against the
/// record cache only. Kept per user, so one person's records never show for
/// the next on a shared device; bounded, the oldest out first; an older copy
/// never replaces a newer one.
class SeenRecords {
  SeenRecords._();

  /// How many records are kept.
  static const int capacity = 500;

  static final Map<String,
          ({String collection, Map<String, dynamic> data, int? revision})>
      _seen = {};

  static String _key(String? userId, String id) => '${userId ?? ''}\u0000$id';

  /// Keeps [record] as [userId] read it. A record that names no collection
  /// is skipped: a detail screen could not tell it belongs to it.
  static void remember(String? userId, KoolbaseRecord record) {
    final collection = record.collection;
    if (collection == null) return;
    final key = _key(userId, record.id);
    final had = _seen.remove(key);
    if (had != null &&
        had.revision != null &&
        record.revision != null &&
        record.revision! < had.revision!) {
      _seen[key] = had;
      return;
    }
    _seen[key] = (
      collection: collection,
      data: Map<String, dynamic>.of(record.data),
      revision: record.revision,
    );
    while (_seen.length > capacity) {
      _seen.remove(_seen.keys.first);
    }
  }

  /// The record [userId] last read with this [id], or null. Its timestamps
  /// are the epoch: only the data and revision are kept, as the saved copy.
  static KoolbaseRecord? recall(String? userId, String id) {
    final seen = _seen[_key(userId, id)];
    if (seen == null) return null;
    final epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    return KoolbaseRecord(
      id: id,
      collection: seen.collection,
      data: Map<String, dynamic>.of(seen.data),
      createdAt: epoch,
      updatedAt: epoch,
      revision: seen.revision,
    );
  }

  /// Forgets the record: it was deleted.
  static void forget(String? userId, String id) =>
      _seen.remove(_key(userId, id));

  /// Forgets everything: someone signed out.
  static void clear() => _seen.clear();
}
