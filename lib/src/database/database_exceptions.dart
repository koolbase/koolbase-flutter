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
    String message = 'Value violates a unique constraint',
    this.field,
  ]) : super(message, code: 'unique_violation');

  @override
  String toString() =>
      'KoolbaseConflictException${field != null ? '($field)' : ''}: $message';
}

/// Thrown when the requested record or collection does not exist — the
/// server responds with 404 and code `not_found` / `record_not_found` /
/// `collection_not_found`.
class KoolbaseNotFoundException extends KoolbaseDataException {
  const KoolbaseNotFoundException([
    String message = 'The requested resource was not found',
  ]) : super(message, code: 'not_found');

  @override
  String toString() => 'KoolbaseNotFoundException: $message';
}

/// Thrown when the request is rejected as invalid — the server responds with
/// 400 and code `validation_error` (e.g. a malformed body or a bad field).
class KoolbaseValidationException extends KoolbaseDataException {
  const KoolbaseValidationException([
    String message = 'The request was invalid',
  ]) : super(message, code: 'validation_error');

  @override
  String toString() => 'KoolbaseValidationException: $message';
}

/// Thrown when the caller is authenticated but not allowed to perform the
/// operation — the server responds with 403 and code `permission_denied`
/// (typically a collection access rule rejecting the write/read).
class KoolbasePermissionException extends KoolbaseDataException {
  const KoolbasePermissionException([
    String message = 'You do not have permission to perform this action',
  ]) : super(message, code: 'permission_denied');

  @override
  String toString() => 'KoolbasePermissionException: $message';
}

/// Thrown when the server is rate-limiting the caller — 429 with code
/// `rate_limit`. Back off and retry after a short delay.
class KoolbaseRateLimitException extends KoolbaseDataException {
  const KoolbaseRateLimitException([
    String message = 'Too many requests, please slow down',
  ]) : super(message, code: 'rate_limit');

  @override
  String toString() => 'KoolbaseRateLimitException: $message';
}

/// Maps a non-2xx data-layer response to a typed [KoolbaseDataException],
/// preferring the server's stable `code` and falling back to the HTTP status
/// for older or uncoded responses. The caller decodes the body once and
/// passes `(statusCode, body)`; this keeps the mapper free of an http
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
      return KoolbaseNotFoundException(message);
    case 'permission_denied':
      return KoolbasePermissionException(message);
    case 'rate_limit':
      return KoolbaseRateLimitException(message);
    case 'validation_error':
      return KoolbaseValidationException(message);
  }

  // ---- status fallback (pre-code servers) ----
  switch (statusCode) {
    case 409:
      return KoolbaseConflictException(message);
    case 404:
      return KoolbaseNotFoundException(message);
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
