import 'dart:convert';
import 'package:http/http.dart' as http;

/// Base class for errors surfaced by the Koolbase storage layer (uploads,
/// downloads, deletes, and bucket/object operations). Every storage error
/// carries a human-readable [message] and, when the server provides one,
/// its stable [code] (e.g. `PATH_CONFLICT`).
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
/// `PATH_CONFLICT`. Catch this to give the user an "overwrite this file?"
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
  ]) : super(code: 'PATH_CONFLICT');

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

/// Maps a non-2xx storage-layer response to a typed
/// [KoolbaseStorageException], preferring the server's stable `code` and
/// falling back to the HTTP status for older or uncoded responses. The
/// caller decodes the body once and passes `(statusCode, body)`; this
/// keeps the mapper free of an http dependency at its core while
/// [koolbaseStorageErrorFromResponse] offers a convenience wrapper.
///
/// Always returns an exception to throw — never null.
KoolbaseStorageException koolbaseStorageError(
  int statusCode,
  Map<String, dynamic> body, {
  String fallbackMessage = 'Storage request failed',
}) {
  final code = body['code'] as String?;
  final message = (body['error'] as String?) ?? fallbackMessage;

  // ---- code-first ----
  switch (code) {
    case 'PATH_CONFLICT':
      return KoolbaseStorageConflictException(
        message,
        body['path'] as String?,
      );
  }

  // ---- status fallback (pre-code servers or uncoded paths) ----
  switch (statusCode) {
    case 409:
      return KoolbaseStorageConflictException(message);
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
