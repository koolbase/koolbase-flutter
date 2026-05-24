/// Thrown when a write (insert, update, or upsert) is rejected because the
/// value would violate a collection's unique constraint — the server responds
/// with 409 Conflict. Catch this to handle duplicates, e.g. an email or
/// username that's already taken.
///
/// ```dart
/// try {
///   await Koolbase.db.collection('users').insert({'email': email});
/// } on KoolbaseConflictException {
///   showError('That email is already registered.');
/// }
/// ```
class KoolbaseConflictException implements Exception {
  /// Human-readable message from the server.
  final String message;

  const KoolbaseConflictException([
    this.message = 'Value violates a unique constraint',
  ]);

  @override
  String toString() => 'KoolbaseConflictException: $message';
}
