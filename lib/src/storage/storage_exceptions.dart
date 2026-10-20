import '../koolbase_exception.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// Base class for errors surfaced by the Koolbase storage layer (uploads,
/// downloads, deletes, and bucket/object operations). Every storage error
/// carries a human-readable [message] and, when the server provides one,
/// its stable [code] (e.g. `path_conflict`).
///
/// Catch this to handle any storage failure generically, or catch a
/// specific subtype ([KoolbaseStorageConflictException],
/// [KoolbaseStorageNotFoundException], …) to branch on the kind of failure.
/// Something went wrong uploading, downloading, or managing stored objects.
///
/// Sits under [KoolbaseException] with the other families, so an application can
/// catch any SDK failure in one place when it wants to.
class KoolbaseStorageException extends KoolbaseException {
  const KoolbaseStorageException(super.message, {super.code});
}

/// Thrown by [KoolbaseStorageClient.publicUrlFor] when the SDK has not yet
/// learned which project it belongs to. Project identity arrives with the
/// bootstrap payload (and persists in its cache); it is unavailable when the
/// very first bootstrap has not completed — a fresh install starting
/// offline — or when the server predates identity metadata.
///
/// This is a DIFFERENT state from a `null` public URL: null means the
/// project is known but the object cannot have a public URL (private
/// bucket). Identity-unavailable is transient and heals on the next
/// successful bootstrap refresh, which calling the method also nudges.
///
/// Stable [code]: `project_identity_unavailable`.
class KoolbaseStorageProjectIdentityException
    extends KoolbaseStorageException {
  const KoolbaseStorageProjectIdentityException()
      : super(
          'The SDK has not yet learned its project identity — it arrives '
          'with the first successful bootstrap. Retry after connectivity '
          'is available.',
          code: 'project_identity_unavailable',
        );
}

/// Thrown when an upload is rejected because an object already exists at
/// the requested path — the server responds with 409 Conflict and code
/// `path_conflict`. Catch this to give the user an "overwrite this file?"
/// prompt, then retry the upload with `overwrite: true`.
///
/// [path] is the colliding path the server rejected, surfaced from the
/// response body for diagnostics and UI.
///
/// ```dart
/// try {
///   await Koolbase.storage.upload(
///     bucket: 'avatars',
///     path: 'me.png',
///     file: file,
///   );
/// } on KoolbaseStorageConflictException catch (e) {
///   final ok = await confirmDialog('${e.path} already exists. Overwrite?');
///   if (ok) {
///     await Koolbase.storage.upload(
///       bucket: 'avatars',
///       path: 'me.png',
///       file: file,
///       overwrite: true,
///     );
///   }
/// }
/// ```
class KoolbaseStorageConflictException extends KoolbaseStorageException {
  /// The path that collided with an existing object.
  final String? path;

  const KoolbaseStorageConflictException([
    super.message = 'An object already exists at this path',
    this.path,
  ]) : super(code: 'path_conflict');

  @override
  String toString() =>
      'KoolbaseStorageConflictException${path != null ? '($path)' : ''}: $message';
}

/// Thrown when the requested bucket or object does not exist — the server
/// responds with 404. Also surfaced for cross-tenant access attempts
/// (Koolbase's 404-over-403 convention prevents enumeration in
/// multi-tenant contexts).
class KoolbaseStorageNotFoundException extends KoolbaseStorageException {
  const KoolbaseStorageNotFoundException([
    super.message = 'The requested bucket or object was not found',
  ]) : super(code: 'not_found');

  @override
  String toString() => 'KoolbaseStorageNotFoundException: $message';
}

/// Thrown when the request is rejected as invalid — the server responds
/// with 400 (e.g. a malformed path, missing field, invalid bucket name).
class KoolbaseStorageValidationException extends KoolbaseStorageException {
  const KoolbaseStorageValidationException([
    super.message = 'The storage request was invalid',
  ]) : super(code: 'validation_error');

  @override
  String toString() => 'KoolbaseStorageValidationException: $message';
}

/// Thrown when the caller is authenticated but not allowed to perform the
/// storage operation — the server responds with 403.
class KoolbaseStoragePermissionException extends KoolbaseStorageException {
  const KoolbaseStoragePermissionException([
    super.message = 'You do not have permission to perform this storage action',
  ]) : super(code: 'permission_denied');

  @override
  String toString() => 'KoolbaseStoragePermissionException: $message';
}

/// Thrown when an upload would push the bucket past its configured
/// `max_size_bytes` quota — the server responds with 409 Conflict and code
/// `quota_exceeded`. The server cleans up the underlying R2 object before
/// returning; nothing leaks. Catch this to surface a "bucket is full"
/// message or prompt the caller to delete older files. The per-bucket
/// quota is set at bucket creation time and is currently immutable.
///
/// Distinct from [KoolbaseStorageConflictException] (which also uses 409
/// but means "path collides"); branch on the exception type, not status.
/// The presigned upload was confirmed after its window closed.
///
/// An upload URL has a lifetime. A user who picks a file, gets distracted
/// and comes back later hits this — so it is a retry, not a failure:
/// presign again and send the same bytes. Worth catching rather than showing
/// "upload failed" to someone whose file was fine.
class KoolbaseUploadExpiredException extends KoolbaseStorageException {
  const KoolbaseUploadExpiredException([
    super.message =
        'This upload is past the confirmation window — please re-upload',
  ]) : super(code: 'upload_expired');
}

/// A bucket cap set below what the bucket already holds. A dashboard
/// operation, mapped so it does not arrive untyped.
class KoolbaseCapBelowUsageException extends KoolbaseStorageException {
  const KoolbaseCapBelowUsageException([
    super.message = "The cap is below the bucket's current usage",
  ]) : super(code: 'cap_below_usage');
}

/// Minting a presigned upload URL failed. Not the user's doing and not a
/// retry they can fix — distinct from [KoolbaseUploadExpiredException],
/// which is a retry that will work.
class KoolbaseUploadURLFailedException extends KoolbaseStorageException {
  const KoolbaseUploadURLFailedException([
    super.message = 'Could not create an upload URL',
  ]) : super(code: 'upload_url_failed');
}

class KoolbaseStorageQuotaExceededException extends KoolbaseStorageException {
  const KoolbaseStorageQuotaExceededException([
    super.message = 'Bucket quota exceeded',
  ]) : super(code: 'quota_exceeded');

  @override
  String toString() => 'KoolbaseStorageQuotaExceededException: $message';
}

/// Thrown when a single file exceeds the bucket's configured
/// `max_file_size_bytes` — the server responds with 413 Payload Too Large
/// and code `file_too_large`. The server cleans up the underlying R2
/// object before returning. The configured per-file limit lives on the
/// bucket record; check `Bucket.maxFileSizeBytes` to surface a clear
/// "files must be under X MB" message at the call site.
class KoolbaseStorageFileTooLargeException extends KoolbaseStorageException {
  const KoolbaseStorageFileTooLargeException([
    super.message = 'File exceeds the bucket maximum file size',
  ]) : super(code: 'file_too_large');

  @override
  String toString() => 'KoolbaseStorageFileTooLargeException: $message';
}

/// Thrown when an upload's content-type isn't in the bucket's configured
/// `allowed_mime_types` allowlist — the server responds with 415
/// Unsupported Media Type and code `mime_not_allowed`. The check runs at
/// presign time, so no bytes are transferred before rejection.
///
/// Allowlists support `type/*` wildcards (e.g. `image/*` matches every
/// image content-type). A bucket with no allowlist configured accepts
/// every type.
class KoolbaseStorageMimeTypeException extends KoolbaseStorageException {
  const KoolbaseStorageMimeTypeException([
    super.message = 'Content-type not allowed for this bucket',
  ]) : super(code: 'mime_not_allowed');

  @override
  String toString() => 'KoolbaseStorageMimeTypeException: $message';
}

/// Thrown when an object metadata payload (either at upload-confirm time
/// or via `updateMetadata`) fails server-side validation — the server
/// responds with 400 and code `metadata_invalid`.
///
/// [detail] carries the specific reason from the server — e.g.
/// `'key "foo bar": must match [a-z0-9_]+'`, `'exceeds 50 keys (got 53)'`,
/// or `'exceeds 8192 bytes total (sum of all key + value lengths)'`. The
/// detail names the failing key and rule so callers can fix the offending
/// entry without guessing what shape rule was violated.
///
/// Validation rules (enforced server-side):
///   - At most 50 keys per object.
///   - At most 8KB total (sum of byte lengths across all keys + values).
///   - Keys: 1–64 chars, must match `[a-z0-9_]+`.
///   - Keys with a leading underscore are reserved for system use.
///   - Values: at most 1024 chars each.
///
/// ```dart
/// try {
///   await Koolbase.storage.updateMetadata(
///     bucket: 'photos',
///     path: 'sunset.jpg',
///     metadata: {'tag': 'sunset', 'BAD KEY': 'oops'},
///   );
/// } on KoolbaseStorageMetadataInvalidException catch (e) {
///   debugPrint('Metadata rejected: ${e.detail}');
///   // -> 'Metadata rejected: key "BAD KEY": must match [a-z0-9_]+'
/// }
/// ```
class KoolbaseStorageMetadataInvalidException extends KoolbaseStorageException {
  /// The specific validation failure reported by the server. Names the
  /// failing key (if applicable) and the rule that was violated. Surface
  /// this directly to the developer or to the user via UI.
  final String? detail;

  const KoolbaseStorageMetadataInvalidException([
    super.message = 'Metadata payload is invalid',
    this.detail,
  ]) : super(code: 'metadata_invalid');

  @override
  String toString() =>
      'KoolbaseStorageMetadataInvalidException${detail != null ? '($detail)' : ''}: $message';
}

/// The upload was cancelled before the server began checking it (S1).
/// Nothing was stored.
class KoolbaseUploadCancelledException extends KoolbaseStorageException {
  const KoolbaseUploadCancelledException([
    super.message = 'The upload was cancelled',
  ]) : super(code: 'upload_cancelled');
}

/// The upload could not reach the server or storage: no connection, or it
/// dropped. A retry with the same bytes may work.
class KoolbaseStorageNetworkException extends KoolbaseStorageException {
  const KoolbaseStorageNetworkException([
    super.message = 'Could not reach storage',
  ]) : super(code: 'network_error');
}

/// The confirm found no upload of yours with these bytes: they never
/// arrived, or the link was someone else's (S0). Upload again.
class KoolbaseUploadNotFoundException extends KoolbaseStorageException {
  const KoolbaseUploadNotFoundException([
    super.message = 'Upload not found: upload the file again',
  ]) : super(code: 'upload_not_found');
}

/// Too many changes to the bucket at once (S0). Safe to retry in a moment.
class KoolbaseStorageBusyException extends KoolbaseStorageException {
  const KoolbaseStorageBusyException([
    super.message = 'The bucket is busy; try again',
  ]) : super(code: 'bucket_busy');
}

/// A listing cursor from another listing, or from another sort (S1). Start
/// the listing again.
class KoolbaseStorageInvalidCursorException extends KoolbaseStorageException {
  const KoolbaseStorageInvalidCursorException([
    super.message = 'Invalid cursor: start the listing again',
  ]) : super(code: 'invalid_cursor');
}

/// The bucket's rules need someone signed in for this (S1). Not a session
/// that ended: nobody was signed in.
class KoolbaseStorageSignInRequiredException extends KoolbaseStorageException {
  const KoolbaseStorageSignInRequiredException([
    super.message = "Sign in to do this: this bucket's rules need someone signed in",
  ]) : super(code: 'sign_in_required');
}

/// A move refused while records point at the file (S1b): [field] holds its
/// path in [records] records. Change those first, or copy the file.
class KoolbaseStorageFileInUseException extends KoolbaseStorageException {
  /// The declared file field that holds the path, e.g. `events.poster`.
  final String? field;

  /// How many records hold it.
  final int records;

  const KoolbaseStorageFileInUseException([
    super.message = 'Records still point at this file',
    this.field,
    this.records = 0,
  ]) : super(code: 'file_in_use');
}

/// A move, within a bucket, to a name a deleted file's kept versions still
/// use (S1b): the two histories would become one. Choose another name.
class KoolbaseStorageNameHasHistoryException extends KoolbaseStorageException {
  const KoolbaseStorageNameHasHistoryException([
    super.message = 'A deleted file by that name still has kept versions; choose another name',
  ]) : super(code: 'name_has_history');
}

/// An upload refused because malware was found in it (storage S6). Nothing
/// of it was kept; [message] names what was found. Tell the person the file
/// cannot be uploaded; trying again with the same file will be refused
/// again.
class KoolbaseStorageMalwareException extends KoolbaseStorageException {
  const KoolbaseStorageMalwareException([
    super.message = 'This file contains malware and was not uploaded',
  ]) : super(code: 'malware_found');

  @override
  String toString() => 'KoolbaseStorageMalwareException: $message';
}

/// A file found to contain malware after it was stored (storage S6): it is
/// quarantined, and no link to it is given. The server answers 423.
class KoolbaseStorageQuarantinedException extends KoolbaseStorageException {
  const KoolbaseStorageQuarantinedException([
    super.message = 'This file is quarantined: malware was found in it',
  ]) : super(code: 'quarantined');

  @override
  String toString() => 'KoolbaseStorageQuarantinedException: $message';
}

/// Completing an upload in parts with parts missing or the wrong size (S3):
/// resume it, which sends [missing].
class KoolbaseUploadIncompleteException extends KoolbaseStorageException {
  final List<int> missing;

  const KoolbaseUploadIncompleteException([
    super.message = 'The upload is missing parts; resume it',
    this.missing = const [],
  ]) : super(code: 'upload_incomplete');
}

/// Maps a non-2xx storage-layer response to a typed
/// [KoolbaseStorageException], preferring the server's stable `code` and
/// falling back to the HTTP status for older or uncoded responses. The
/// caller decodes the body once and passes `(statusCode, body)`; this
/// keeps the mapper free of an http dependency at its core while
/// [koolbaseStorageErrorFromResponse] offers a convenience wrapper.
///
/// Always returns an exception to throw — never null.
///
/// Status-fallback note: HTTP 409 covers both path_conflict and
/// quota_exceeded. Without a `code` field, the mapper defaults 409 to
/// [KoolbaseStorageConflictException] since path collisions are the more
/// common case. Modern Koolbase servers always emit `code`, so this only
/// matters for very old API responses or non-Koolbase 409s.
KoolbaseException koolbaseStorageError(
  int statusCode,
  Map<String, dynamic> body, {
  String fallbackMessage = 'Storage request failed',
}) {
  final code = body['code'] as String?;
  final message = (body['error'] as String?) ?? fallbackMessage;

  // ---- code-first ----
  switch (code) {
    case 'path_conflict':
      return KoolbaseStorageConflictException(
        message,
        body['path'] as String?,
      );
    case 'quota_exceeded':
      return KoolbaseStorageQuotaExceededException(message);
    case 'placement_unavailable':
      return KoolbaseServiceUnavailableException(message);
    case 'plan_limit_reached':
      final details = body['details'] as Map<String, dynamic>?;
      return KoolbasePlanLimitException(
        message,
        resource: details?['resource'] as String?,
        limit: (details?['limit'] as num?)?.toInt(),
        plan: details?['plan'] as String?,
      );
    case 'upload_expired':
      return KoolbaseUploadExpiredException(message);
    case 'cap_below_usage':
      return KoolbaseCapBelowUsageException(message);
    case 'upload_url_failed':
      return KoolbaseUploadURLFailedException(message);
    case 'file_too_large':
      return KoolbaseStorageFileTooLargeException(message);
    case 'mime_not_allowed':
      return KoolbaseStorageMimeTypeException(message);
    case 'metadata_invalid':
      return KoolbaseStorageMetadataInvalidException(
        message,
        body['detail'] as String?,
      );
    // A setup problem, not a session one (#169): never signs anyone out.
    case 'invalid_public_key':
      return KoolbaseInvalidPublicKeyException(message);
    case 'upload_not_found':
      return KoolbaseUploadNotFoundException(message);
    case 'bucket_busy':
      return KoolbaseStorageBusyException(message);
    case 'invalid_cursor':
      return KoolbaseStorageInvalidCursorException(message);
    case 'sign_in_required':
      return KoolbaseStorageSignInRequiredException(message);
    case 'not_allowed':
      return KoolbaseStoragePermissionException(message);
    case 'file_in_use':
      final inUse = body['details'] as Map<String, dynamic>?;
      return KoolbaseStorageFileInUseException(
        message,
        inUse?['field'] as String?,
        (inUse?['records'] as num?)?.toInt() ?? 0,
      );
    case 'name_has_history':
      return KoolbaseStorageNameHasHistoryException(message);
    case 'malware_found':
      return KoolbaseStorageMalwareException(message);
    case 'quarantined':
      return KoolbaseStorageQuarantinedException(message);
    case 'upload_incomplete':
      final parts = (body['details'] as Map<String, dynamic>?)?['missing'] as List?;
      return KoolbaseUploadIncompleteException(
        message,
        [for (final n in parts ?? const []) (n as num).toInt()],
      );
  }

  // ---- status fallback (pre-code servers or uncoded paths) ----
  switch (statusCode) {
    case 409:
      return KoolbaseStorageConflictException(message);
    case 413:
      return KoolbaseStorageFileTooLargeException(message);
    case 415:
      return KoolbaseStorageMimeTypeException(message);
    case 423:
      return KoolbaseStorageQuarantinedException(message);
    case 404:
      return KoolbaseStorageNotFoundException(message);
    case 401:
      // A rejected credential is not a storage problem, so it raises the shared
      // type: a session stops working for the whole SDK at once, and an
      // application should not need a handler per subsystem to notice.
      return KoolbaseUnauthenticatedException(message);
    case 403:
      return KoolbaseStoragePermissionException(message);
    case 400:
      return KoolbaseStorageValidationException(message);
  }

  return KoolbaseStorageException(message, code: code);
}

/// Convenience wrapper over [koolbaseStorageError] that decodes the
/// response body for you. Use at call sites that have the raw [http.Response].
KoolbaseException koolbaseStorageErrorFromResponse(
  http.Response res, {
  String fallbackMessage = 'Storage request failed',
}) {
  Map<String, dynamic> body = {};
  try {
    body = jsonDecode(res.body) as Map<String, dynamic>;
  } catch (_) {}
  return koolbaseStorageError(res.statusCode, body,
      fallbackMessage: fallbackMessage);
}
