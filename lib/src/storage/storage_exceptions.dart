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
class KoolbaseStorageException implements Exception {
  /// Human-readable message from the server (or a sensible default).
  final String message;

  /// The server's stable error code, when present.
  final String? code;

  const KoolbaseStorageException(this.message, {this.code});

  @override
  String toString() => 'KoolbaseStorageException($code): $message';
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
KoolbaseStorageException koolbaseStorageError(
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
    case 'file_too_large':
      return KoolbaseStorageFileTooLargeException(message);
    case 'mime_not_allowed':
      return KoolbaseStorageMimeTypeException(message);
    case 'metadata_invalid':
      return KoolbaseStorageMetadataInvalidException(
        message,
        body['detail'] as String?,
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
    case 404:
      return KoolbaseStorageNotFoundException(message);
    case 403:
      return KoolbaseStoragePermissionException(message);
    case 400:
      return KoolbaseStorageValidationException(message);
  }

  return KoolbaseStorageException(message, code: code);
}

/// Convenience wrapper over [koolbaseStorageError] that decodes the
/// response body for you. Use at call sites that have the raw [http.Response].
KoolbaseStorageException koolbaseStorageErrorFromResponse(
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
