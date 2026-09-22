import '../koolbase_exception.dart';
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
/// Something went wrong reading or writing records.
///
/// Sits under [KoolbaseException] with the other families, so an application can
/// catch any SDK failure in one place when it wants to.
class KoolbaseDataException extends KoolbaseException {
  const KoolbaseDataException(super.message, {super.code});
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
/// Thrown when a reference field points at a record that does not exist, is
/// deleted, or lives in another collection — 400 `reference_invalid`.
///
/// References are checked when the write commits, so this can surface from an
/// insert, an update, an upsert or a batch. In a batch the whole transaction
/// is refused: nothing in it was written.
class KoolbaseReferenceInvalidException extends KoolbaseDataException {
  const KoolbaseReferenceInvalidException([
    super.message = 'A reference points at a record that does not exist',
  ]) : super(code: 'reference_invalid');

  @override
  String toString() => 'KoolbaseReferenceInvalidException: $message';
}

/// Thrown when a record cannot be deleted because live records still
/// reference it, under a reference declared `on_delete: restrict` — 409
/// `reference_in_use`.
///
/// Delete the referencing records first, or in the SAME batch: the check runs
/// at commit, so one batch may delete a parent and its children in any order.
class KoolbaseReferenceInUseException extends KoolbaseDataException {
  const KoolbaseReferenceInUseException([
    super.message = 'This record is still referenced by other records',
  ]) : super(code: 'reference_in_use');

  @override
  String toString() => 'KoolbaseReferenceInUseException: $message';
}

/// Thrown when a reference cannot be declared because existing records
/// already point at records that do not exist — 409 `dangling_references`.
///
/// [dangling] lists the offending records so they can be repaired; Koolbase
/// never repairs them for you. It is capped at the first 50.
class KoolbaseDanglingReferencesException extends KoolbaseDataException {
  /// The records whose reference points at nothing, as record id to value.
  final List<({String recordId, String value})> dangling;

  const KoolbaseDanglingReferencesException([
    super.message = 'Existing records point at records that do not exist',
    this.dangling = const [],
  ]) : super(code: 'dangling_references');

  @override
  String toString() =>
      'KoolbaseDanglingReferencesException(${dangling.length}): $message';
}

/// Thrown when a collection cannot be deleted because another collection has
/// a reference field pointing at it — 409 `collection_referenced`. Remove
/// that reference first.
class KoolbaseCollectionReferencedException extends KoolbaseDataException {
  const KoolbaseCollectionReferencedException([
    super.message = 'Another collection references this one',
  ]) : super(code: 'collection_referenced');

  @override
  String toString() => 'KoolbaseCollectionReferencedException: $message';
}

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
  /// [code] is carried rather than fixed: the server says which thing was
  /// missing — a record, a collection, a vector field — and an app reading
  /// `code` should get that answer, not the category. Catching the class
  /// still works for anyone who only cares that something was absent.
  const KoolbaseNotFoundException([
    super.message = 'The requested resource was not found',
    String code = 'not_found',
  ]) : super(code: code);

  @override
  String toString() => 'KoolbaseNotFoundException: $message';
}

/// Thrown when the request is rejected as invalid — the server responds with
/// 400 and code `validation_error` (e.g. a malformed body or a bad field).
class KoolbaseValidationException extends KoolbaseDataException {
  /// [code] is carried for the same reason as [KoolbaseNotFoundException]:
  /// an unsupported dimension and a vector pointed at the wrong collection
  /// are both validation failures, and an app should be able to tell which.
  const KoolbaseValidationException([
    super.message = 'The request was invalid',
    String code = 'validation_error',
  ]) : super(code: code);

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
// ─── Added 20 Sep 2026 ──────────────────────────────────────────────────────
//
// Fifteen codes the API emits that nothing here caught. Found by comparing the
// API's declared list against this switch; the TypeScript SDKs had the same
// gap and the same groupings.

/// An upsert whose filter matched more than one record. Refused rather than
/// resolved: picking one would be a silent guess about which row the caller
/// meant. Narrow the filter, or add a unique constraint over those fields.
class KoolbaseAmbiguousMatchException extends KoolbaseDataException {
  const KoolbaseAmbiguousMatchException([
    super.message = 'Upsert match resolved to more than one record',
  ]) : super(code: 'ambiguous_match');
}

/// A unique constraint already covers those fields.
class KoolbaseConstraintExistsException extends KoolbaseDataException {
  const KoolbaseConstraintExistsException([
    super.message = 'A unique constraint already exists for these fields',
  ]) : super(code: 'constraint_exists');
}

/// No such unique constraint.
class KoolbaseConstraintNotFoundException extends KoolbaseDataException {
  const KoolbaseConstraintNotFoundException([
    super.message = 'Unique constraint not found',
  ]) : super(code: 'constraint_not_found');
}

/// Creating a unique constraint over data that already breaks it. The
/// server's details carry the offending values.
class KoolbaseDuplicateValuesException extends KoolbaseDataException {
  const KoolbaseDuplicateValuesException([
    super.message = 'The collection has duplicate values for these fields',
  ]) : super(code: 'duplicate_values');
}

/// The same idempotency key sent with different data. Refused rather than
/// replayed: the two requests do not agree, so neither answer is safe.
///
/// [code] is carried because the database package calls this
/// `idempotency_key_reused` and fiscal calls it `idempotency_conflict`.
class KoolbaseIdempotencyKeyReusedException extends KoolbaseDataException {
  const KoolbaseIdempotencyKeyReusedException([
    super.message = 'Idempotency key reused with different data',
    String code = 'idempotency_key_reused',
  ]) : super(code: code);
}

/// A batch write failed for a reason the server did not classify further.
class KoolbaseBatchFailedException extends KoolbaseDataException {
  const KoolbaseBatchFailedException([
    super.message = 'The batch write failed',
  ]) : super(code: 'batch_failed');
}

/// Authenticated, and not permitted to do this — a destructive operation
/// such as a seed overwrite or a snapshot restore. Distinct from
/// [KoolbasePermissionException], which is a rule denying a record.
class KoolbaseInsufficientAuthorityException extends KoolbaseDataException {
  const KoolbaseInsufficientAuthorityException([
    super.message = 'You do not have the authority to perform this action',
  ]) : super(code: 'insufficient_authority');
}

/// A vector field with that name already exists on the collection.
class KoolbaseVectorFieldExistsException extends KoolbaseDataException {
  const KoolbaseVectorFieldExistsException([
    super.message = 'A vector field with that name already exists',
  ]) : super(code: 'vector_field_exists');
}

/// A backfill was asked for on a field that embeds nothing automatically.
class KoolbaseFieldNotAutoEmbedException extends KoolbaseDataException {
  const KoolbaseFieldNotAutoEmbedException([
    super.message =
        'This vector field has no auto-embedding config; set provider, model '
            'and source_field first',
  ]) : super(code: 'field_not_auto_embed');
}

/// Embedding config is partial. Provider, model and source_field are set
/// together or cleared together.
class KoolbaseInvalidEmbeddingConfigException extends KoolbaseDataException {
  const KoolbaseInvalidEmbeddingConfigException([
    super.message =
        'Embedding config requires provider, model and source_field together, '
            'or all cleared',
  ]) : super(code: 'invalid_embedding_config');
}

/// The project has no embedding provider configured.
class KoolbaseProviderNotConfiguredException extends KoolbaseDataException {
  const KoolbaseProviderNotConfiguredException([
    super.message = 'No embedding provider is configured for this project',
  ]) : super(code: 'provider_not_configured');
}

/// The configured provider's credentials were rejected by the provider.
class KoolbaseProviderInvalidException extends KoolbaseDataException {
  const KoolbaseProviderInvalidException([
    super.message = 'The embedding provider credentials are not valid',
  ]) : super(code: 'provider_invalid');
}

/// The request body could not be decoded.
class KoolbaseInvalidBodyException extends KoolbaseDataException {
  const KoolbaseInvalidBodyException([
    super.message = 'Could not decode the request body',
  ]) : super(code: 'invalid_body');
}

/// Something already exists, or is in the wrong state, where the server did
/// not say more. [code] is whichever generic code arrived.
class KoolbaseStateConflictException extends KoolbaseDataException {
  const KoolbaseStateConflictException(super.message, String code)
      : super(code: code);
}

/// A project slug that another project already holds.
class KoolbaseSlugTakenException extends KoolbaseDataException {
  const KoolbaseSlugTakenException([
    super.message = 'A project with this slug already exists',
  ]) : super(code: 'slug_taken');
}

/// An invitation that has been revoked or has expired.
class KoolbaseInvitationInvalidException extends KoolbaseDataException {
  const KoolbaseInvitationInvalidException([
    super.message = 'This invitation has been revoked or expired',
  ]) : super(code: 'invitation_invalid');
}

/// The project id in the request is not valid.
class KoolbaseProjectInvalidException extends KoolbaseDataException {
  const KoolbaseProjectInvalidException([
    super.message = 'Invalid project id',
  ]) : super(code: 'project_invalid');
}

/// The request asked for no change.
class KoolbaseNoChangesException extends KoolbaseDataException {
  const KoolbaseNoChangesException([
    super.message = 'The request contains no changes',
  ]) : super(code: 'no_changes');
}

/// A seed or import operation was refused. [code] says which stage:
/// `invalid_seed_file`, `seed_key_not_unique`, `seed_needs_decision`, or
/// `seed_conflicts_require_force`. One class rather than four: these are
/// dashboard and CLI operations, and a caller handles them the same way —
/// show the reason and let a human decide.
class KoolbaseSeedException extends KoolbaseDataException {
  const KoolbaseSeedException(super.message, String code)
      : super(code: code);
}

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

@Deprecated(
    'Use KoolbaseUnauthenticatedException. A 401 covers an expired session, a '
    'revoked key, and malformed or missing credentials, and the server does not '
    'distinguish them — the old name claimed a precision that does not exist. '
    'Kept so existing catches keep working; will be removed in 11.0.0.')
class KoolbaseSessionExpiredException extends KoolbaseUnauthenticatedException {
  const KoolbaseSessionExpiredException(super.message)
      : super(code: 'invalid_refresh_token');
}

/// dependency at its core while [koolbaseDataErrorFromResponse] offers a
/// convenience wrapper.
///
/// Always returns an exception to throw — never null.
KoolbaseException koolbaseDataError(
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
    case 'reference_invalid':
      return KoolbaseReferenceInvalidException(message);
    case 'reference_in_use':
      return KoolbaseReferenceInUseException(message);
    case 'dangling_references':
      return KoolbaseDanglingReferencesException(
        message,
        [
          for (final d in (details?['dangling'] as List<dynamic>? ?? []))
            (
              recordId: (d as Map<String, dynamic>)['record_id'] as String? ?? '',
              value: d['value'] as String? ?? '',
            ),
        ],
      );
    case 'collection_referenced':
      return KoolbaseCollectionReferencedException(message);
    case 'plan_limit_reached':
      return KoolbasePlanLimitException(
        message,
        resource: details?['resource'] as String?,
        limit: (details?['limit'] as num?)?.toInt(),
        plan: details?['plan'] as String?,
      );
    case 'ambiguous_match':
      return KoolbaseAmbiguousMatchException(message);
    case 'constraint_exists':
      return KoolbaseConstraintExistsException(message);
    case 'constraint_not_found':
      return KoolbaseConstraintNotFoundException(message);
    case 'duplicate_values':
      return KoolbaseDuplicateValuesException(message);
    case 'idempotency_key_reused':
    case 'idempotency_conflict':
      return KoolbaseIdempotencyKeyReusedException(message, code!);
    case 'batch_failed':
      return KoolbaseBatchFailedException(message);
    case 'insufficient_authority':
      return KoolbaseInsufficientAuthorityException(message);
    case 'vector_field_exists':
      return KoolbaseVectorFieldExistsException(message);
    case 'field_not_auto_embed':
      return KoolbaseFieldNotAutoEmbedException(message);
    case 'invalid_embedding_config':
      return KoolbaseInvalidEmbeddingConfigException(message);
    case 'provider_not_configured':
      return KoolbaseProviderNotConfiguredException(message);
    case 'provider_invalid':
      return KoolbaseProviderInvalidException(message);
    case 'invalid_body':
      return KoolbaseInvalidBodyException(message);
    case 'conflict':
    case 'duplicate':
    case 'state_conflict':
      return KoolbaseStateConflictException(message, code!);
    case 'slug_taken':
      return KoolbaseSlugTakenException(message);
    case 'invitation_invalid':
      return KoolbaseInvitationInvalidException(message);
    case 'project_invalid':
      return KoolbaseProjectInvalidException(message);
    case 'no_changes':
      return KoolbaseNoChangesException(message);
    case 'invalid_seed_file':
    case 'seed_key_not_unique':
    case 'seed_needs_decision':
    case 'seed_conflicts_require_force':
      return KoolbaseSeedException(message, code!);
    case 'not_found':
    case 'record_not_found':
    case 'collection_not_found':
    case 'vector_not_found':
    case 'vector_field_not_found':
      return KoolbaseNotFoundException(message, code!);
    case 'revision_mismatch':
      return KoolbaseRevisionMismatchException(
        message,
        expectedRevision: (details?['expected_revision'] as num?)?.toInt(),
        currentRevision: (details?['current_revision'] as num?)?.toInt(),
        currentRecord: details?['record'] as Map<String, dynamic>?,
      );
    // invalid_refresh_token is what the server actually sends when a session
    // is over. It was unmapped, so it fell through to the generic fallback
    // and koolbaseDataErrorNotifying never fired — leaving an app holding a
    // token the server refuses, which is the failure that notifier exists to
    // prevent.
    //
    // It returns the SessionExpired subclass because that is the exception
    // four doc comments tell applications to catch, and nothing had ever
    // constructed it. The notifier still fires: the subclass IS a
    // KoolbaseUnauthenticatedException.
    //
    // session_expired is gone. The API has never emitted it.
    case 'invalid_refresh_token':
      return KoolbaseSessionExpiredException(message);
    case 'invalid_token':
    case 'unauthenticated':
      return KoolbaseUnauthenticatedException(message);
    case 'permission_denied':
      return KoolbasePermissionException(message);
    case 'rate_limit':
      return KoolbaseRateLimitException(message);
    case 'validation_error':
    case 'vector_collection_mismatch':
    case 'unsupported_dimension':
      return KoolbaseValidationException(message, code!);
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
      // The status carries the meaning: every 401 from this server reports the
      // same code, so it cannot say whether the session expired, the key was
      // revoked, or the header was malformed. Safe to treat uniformly because a
      // permission failure is 403 — a 401 means the credentials were not
      // accepted, not that this caller may not proceed.
      return KoolbaseUnauthenticatedException(message);
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
KoolbaseException koolbaseDataErrorFromResponse(
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
Future<KoolbaseException> koolbaseDataErrorNotifying(
  http.Response res, {
  String fallbackMessage = 'Request failed',
  Future<void> Function()? onSessionExpired,
}) async {
  final err = koolbaseDataErrorFromResponse(res, fallbackMessage: fallbackMessage);
  if (err is KoolbaseUnauthenticatedException) {
    await onSessionExpired?.call();
  }
  return err;
}
