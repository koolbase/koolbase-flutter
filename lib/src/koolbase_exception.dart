/// The root of every error the SDK raises.
///
/// Each subsystem has its own family beneath this — data, storage, auth — so an
/// application can catch narrowly where it wants to and broadly where it does
/// not:
///
/// ```dart
/// try {
///   await Koolbase.storage.upload(...);
/// } on KoolbaseUnauthenticatedException {
///   await goToLogin();          // any surface, one handler
/// } on KoolbaseStorageException catch (e) {
///   showError(e.message);       // storage-specific
/// } on KoolbaseException catch (e) {
///   report(e);                  // anything else from the SDK
/// }
/// ```
///
/// The families used to be unrelated roots, which meant a failure that belongs
/// to no single subsystem — a rejected session, discovered by whichever call
/// happened to make it — had to be redefined in each one, and applications wrote
/// the same handler several times.
abstract class KoolbaseException implements Exception {
  const KoolbaseException(this.message, {this.code});

  /// What went wrong, in words. From the server where it said something useful.
  final String message;

  /// The server's stable error code, when it sent one. Prefer branching on the
  /// exception type; this is for logging and for codes the SDK does not yet map.
  final String? code;

  @override
  String toString() => '$runtimeType($code): $message';
}

/// The server would not accept the caller's credentials.
///
/// Raised by any surface — a query, an upload, a Function invoke — because a
/// session stops working for the whole SDK at once, not one subsystem at a time.
///
/// Named for what the server actually reports. A 401 covers an expired session,
/// a revoked key, a malformed header, and no credentials at all, and the server
/// does not distinguish them: calling this "session expired" would claim a
/// precision that does not exist, and an app that signed a user out on a revoked
/// API key would be acting on it.
///
/// When the SDK holds a session it clears it before throwing, so by the time an
/// application catches this the user is already signed out and routing to login
/// is safe.
class KoolbaseUnauthenticatedException extends KoolbaseException {
  const KoolbaseUnauthenticatedException(
    super.message, {
    super.code = 'unauthenticated',
  });
}
