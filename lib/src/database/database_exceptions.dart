import 'dart:convert';
import 'package:http/http.dart' as http;

/// Base class for errors surfaced by the Koolbase data layer (database
/// reads and writes). Every data error carries a human-readable [message]
/// and, when the server provides one, its stable [code] (e.g. `not_found`,
/// `validation_error`, `unique_violation`).
///
/// Catch this to handle any data-layer failure generically, or catch a
/// specific subtype ([KoolbaseConflictException], [KoolbaseNotFoundException],
/// …) to branch on the kind of failure.
class KoolbaseDataException implements Exception {
  /// Human-readable message from the server (or a sensible default).
  final String message;

  /// The server's stable error code, when present.
  final String? code;

  const KoolbaseDataException(this.message, {this.code});

  @override
  String toString() => 'KoolbaseDataException($code): $message';
}

/// Thrown when a write (insert, update, or upsert) is rejected because the
/// value would violate a collection's unique constraint — the server responds
/// with 409 Conflict and code `unique_violation`. Catch this to handle
/// duplicates, e.g. an email or username that's already taken.
///
/// [field] names the field that collided, when the server reports it
/// (`details.field`) — useful when a collection has more than one unique
/// constraint and you need to know which value clashed.
///
/// ```dart
/// try {
///   await Koolbase.db.collection('users').insert({'email': email});
/// } on KoolbaseConflictException catch (e) {
///   showError('That ${e.field ?? 'value'} is already registered.');
/// }
/// ```
class KoolbaseConflictException extends KoolbaseDataException {
  /// The field that violated the unique constraint, when known.
  final String? field;

  const KoolbaseConflictException([
    super.message = 'Value violates a unique constraint',
    this.field,
  ]) : super(code: 'unique_violation');

  @override
  String toString() =>
      'KoolbaseConflictException${field != null ? '($field)' : ''}: $message';
}

/// Thrown when the requested record or collection does not exist — the
/// server responds with 404 and code `not_found` / `record_not_found` /
/// `collection_not_found`.
class KoolbaseNotFoundException extends KoolbaseDataException {
  const KoolbaseNotFoundException([
    super.message = 'The requested resource was not found',
  ]) : super(code: 'not_found');

  @override
  String toString() => 'KoolbaseNotFoundException: $message';
}

/// Thrown when the request is rejected as invalid — the server responds with
/// 400 and code `validation_error` (e.g. a malformed body or a bad field).
class KoolbaseValidationException extends KoolbaseDataException {
  const KoolbaseValidationException([
    super.message = 'The request was invalid',
  ]) : super(code: 'validation_error');

  @override
  String toString() => 'KoolbaseValidationException: $message';
}

/// Thrown when the caller is authenticated but not allowed to perform the
/// operation — the server responds with 403 and code `permission_denied`
/// (typically a collection access rule rejecting the write/read).
class KoolbasePermissionException extends KoolbaseDataException {
  const KoolbasePermissionException([
    super.message = 'You do not have permission to perform this action',
  ]) : super(code: 'permission_denied');

  @override
  String toString() => 'KoolbasePermissionException: $message';
}

/// Thrown when the server is rate-limiting the caller — 429 with code
/// `rate_limit`. Back off and retry after a short delay.
class KoolbaseRateLimitException extends KoolbaseDataException {
  const KoolbaseRateLimitException([
    super.message = 'Too many requests, please slow down',
  ]) : super(code: 'rate_limit');

  @override
  String toString() => 'KoolbaseRateLimitException: $message';
}

/// Thrown when the supplied vector's length does not match the dimension
/// declared on the collection's vector field — the server responds with
/// 400 and code `vector_dimension_mismatch`. The [message] includes both
/// the expected and actual dimensions so you can surface a precise error.
///
/// ```dart
/// try {
///   await Koolbase.db.doc(id).setVector('embedding', [0.1, 0.2]); // 2 dims
/// } on KoolbaseVectorDimensionMismatchException catch (e) {
///   showError(e.message);  // "expected 1536, got 2"
/// }
/// ```
class KoolbaseVectorDimensionMismatchException extends KoolbaseDataException {
  const KoolbaseVectorDimensionMismatchException([
    super.message = 'Vector dimension does not match field declaration',
  ]) : super(code: 'vector_dimension_mismatch');

  @override
  String toString() => 'KoolbaseVectorDimensionMismatchException: $message';
}

/// Maps a non-2xx data-layer response to a typed [KoolbaseDataException],
/// preferring the server's stable `code` and falling back to the HTTP status
/// for older or uncoded responses. The caller decodes the body once and
/// passes `(statusCode, body)`; this keeps the mapper free of an http
/// Thrown when the server rejects the session token itself — expired, revoked,
/// or belonging to a different project than the one this app is configured for.
///
/// Distinct from [KoolbasePermissionException], which means the session is valid
/// but the caller may not touch that resource. The difference decides what an app
/// should do: a permission failure is a message, a session failure is a login.
///
/// The SDK clears the stored session before this is thrown, so by the time an app
/// catches it the user is already signed out and the app can route to login. That
/// is deliberate: a session the server will not honour is not a session, and
/// leaving it in place produces an app that believes it is authenticated and
/// fails every request.
/// Thrown when an offline update or delete cannot be queued because the SDK has
/// no record of what the change was composed against.
///
/// Replaying a mutation without knowing the state it was based on means applying
/// it blindly: whatever changed on the server in the meantime is overwritten,
/// silently, with nobody able to tell it happened. Koolbase accepts an offline
/// mutation only when it can persist that baseline.
///
/// A baseline is available when the record is in the local cache, or when it was
/// created offline and its insert is still queued. It is unavailable when the
/// record has never been read on this device — so read it, or make the change
/// while online, where the server arbitrates directly.
///
/// Deliberate rather than lenient: queueing these unconditionally would mean most
/// offline updates are conflict-safe and some quietly are not, which is a worse
/// guarantee than a clear refusal.
class KoolbaseOfflineBaselineUnavailableException extends KoolbaseDataException {
  const KoolbaseOfflineBaselineUnavailableException(super.message)
      : super(code: 'offline_baseline_unavailable');
}

/// Thrown when a write was refused because the record changed since it was
/// composed.
///
/// Carries the server's current state, returned with the refusal, so deciding
/// what to do needs no second fetch — and cannot race one, which is the whole
/// point of the server checking and applying atomically.
///
/// On the direct write path this surfaces to the caller. During replay of a
/// queued offline write it becomes a persisted conflict instead: the write is
/// not lost, and not applied, until someone decides.
class KoolbaseRevisionMismatchException extends KoolbaseDataException {
  /// The revision the write expected.
  final int? expectedRevision;

  /// The revision the record now carries.
  final int? currentRevision;

  /// The record as the server holds it now.
  final Map<String, dynamic>? currentRecord;

  const KoolbaseRevisionMismatchException(
    super.message, {
    this.expectedRevision,
    this.currentRevision,
    this.currentRecord,
  }) : super(code: 'revision_mismatch');
}

class KoolbaseSessionExpiredException extends KoolbaseDataException {
  const KoolbaseSessionExpiredException(super.message)
      : super(code: 'session_expired');
}

/// dependency at its core while [koolbaseDataErrorFromResponse] offers a
/// convenience wrapper.
///
/// Always returns an exception to throw — never null.
KoolbaseDataException koolbaseDataError(
  int statusCode,
  Map<String, dynamic> body, {
  String fallbackMessage = 'Request failed',
}) {
  final code = body['code'] as String?;
  final message = (body['error'] as String?) ?? fallbackMessage;
  final details = body['details'] as Map<String, dynamic>?;

  // ---- code-first ----
  switch (code) {
    case 'unique_violation':
      return KoolbaseConflictException(message, details?['field'] as String?);
    case 'not_found':
    case 'record_not_found':
    case 'collection_not_found':
    case 'vector_not_found':
    case 'vector_field_not_found':
      return KoolbaseNotFoundException(message);
    case 'revision_mismatch':
      return KoolbaseRevisionMismatchException(
        message,
        expectedRevision: (details?['expected_revision'] as num?)?.toInt(),
        currentRevision: (details?['current_revision'] as num?)?.toInt(),
        currentRecord: details?['record'] as Map<String, dynamic>?,
      );
    case 'session_expired':
    case 'invalid_token':
      return KoolbaseSessionExpiredException(message);
    case 'permission_denied':
      return KoolbasePermissionException(message);
    case 'rate_limit':
      return KoolbaseRateLimitException(message);
    case 'validation_error':
    case 'vector_collection_mismatch':
    case 'unsupported_dimension':
      return KoolbaseValidationException(message);
    case 'vector_dimension_mismatch':
      return KoolbaseVectorDimensionMismatchException(message);
  }

  // ---- status fallback (pre-code servers) ----
  switch (statusCode) {
    case 409:
      return KoolbaseConflictException(message);
    case 404:
      return KoolbaseNotFoundException(message);
    case 401:
      // Servers do not currently send a code here, so the status carries the
      // meaning. Safe because a permission failure is 403: a 401 means the
      // token itself was not accepted, not that this caller may not proceed.
      return KoolbaseSessionExpiredException(message);
    case 403:
      return KoolbasePermissionException(message);
    case 429:
      return KoolbaseRateLimitException(message);
    case 400:
      return KoolbaseValidationException(message);
  }

  return KoolbaseDataException(message, code: code);
}

/// Convenience wrapper over [koolbaseDataError] that decodes the response
/// body for you. Use at call sites that have the raw [http.Response].
KoolbaseDataException koolbaseDataErrorFromResponse(
  http.Response res, {
  String fallbackMessage = 'Request failed',
}) {
  Map<String, dynamic> body = {};
  try {
    body = jsonDecode(res.body) as Map<String, dynamic>;
  } catch (_) {}
  return koolbaseDataError(res.statusCode, body,
      fallbackMessage: fallbackMessage);
}

/// Builds the exception for a failed response and notifies [onSessionExpired]
/// when the server rejected the session token itself.
///
/// The notification happens before the exception is thrown, so by the time a
/// caller catches [KoolbaseSessionExpiredException] the session is already
/// cleared and the app can route to login without racing the SDK.
///
/// Shared by every client rather than duplicated: a path that forgot to notify
/// would leave an app authenticated against a token the server refuses, which is
/// the failure this exists to prevent.
Future<KoolbaseDataException> koolbaseDataErrorNotifying(
  http.Response res, {
  String fallbackMessage = 'Request failed',
  Future<void> Function()? onSessionExpired,
}) async {
  final err = koolbaseDataErrorFromResponse(res, fallbackMessage: fallbackMessage);
  if (err is KoolbaseSessionExpiredException) {
    await onSessionExpired?.call();
  }
  return err;
}
