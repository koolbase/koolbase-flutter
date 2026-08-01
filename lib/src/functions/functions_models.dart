import '../koolbase_exception.dart';
/// The result of a function invocation.
class FunctionInvokeResult {
  /// HTTP status code returned by the function.
  final int statusCode;

  /// The parsed JSON response body, or null if empty.
  final Map<String, dynamic>? data;

  /// Raw response body as a string.
  final String raw;

  /// Whether the invocation was successful (statusCode 200–299).
  final bool success;

  const FunctionInvokeResult({
    required this.statusCode,
    required this.data,
    required this.raw,
    required this.success,
  });
}

/// Exception thrown when a function invocation fails.
/// A Function call did not succeed.
///
/// Sits under [KoolbaseException] with the other families, so an application can
/// catch any SDK failure in one place when it wants to.
class FunctionInvokeException extends KoolbaseException {
  const FunctionInvokeException(super.message, {this.statusCode, super.code});

  /// The HTTP status, when the call reached the server.
  final int? statusCode;
}

/// The caller may not invoke this Function.
///
/// Distinct from an authentication failure: the credentials were accepted and
/// this caller is not permitted. Retrying will not help and signing the user out
/// would be wrong.
class FunctionPermissionException extends FunctionInvokeException {
  const FunctionPermissionException(super.message)
      : super(statusCode: 403, code: 'permission_denied');
}

/// No Function by that name is deployed to this project.
///
/// Usually a name that does not match what was deployed, or a Function deployed
/// to a different project than the one this app is configured for.
class FunctionNotFoundException extends FunctionInvokeException {
  const FunctionNotFoundException(super.message)
      : super(statusCode: 404, code: 'not_found');
}

/// The Function rejected its arguments.
class FunctionValidationException extends FunctionInvokeException {
  const FunctionValidationException(super.message)
      : super(statusCode: 400, code: 'validation_error');
}

/// The project has used up its Function invocations for the period.
///
/// Nothing about the call is wrong — retrying will not help until the plan
/// allows it. Worth telling a user plainly rather than showing them a generic
/// failure, and worth telling the developer, since it is the one failure here
/// that is fixed by changing a plan rather than changing code.
class FunctionQuotaExceededException extends FunctionInvokeException {
  const FunctionQuotaExceededException(super.message)
      : super(statusCode: 402, code: 'limit_reached');
}

/// The Function ran and failed.
///
/// The error is the Function's own, not the platform's — its message comes from
/// the code that was deployed.
class FunctionExecutionException extends FunctionInvokeException {
  const FunctionExecutionException(super.message, {super.statusCode})
      : super(code: 'execution_failed');
}

/// Builds the right exception for a failed invocation.
///
/// A single type carrying a status number made every failure look alike: a
/// missing Function, a caller without permission, and a Function that threw all
/// arrived identically, and an application had to read the number to tell them
/// apart. The distinction matters — one is a deployment problem, one is a
/// permissions problem, and one is a bug in the Function.
KoolbaseException functionInvokeError(int statusCode, String message) {
  switch (statusCode) {
    case 401:
      // Not a Function failure. A rejected credential stops the whole SDK
      // working, so it raises the shared type.
      return KoolbaseUnauthenticatedException(message);
    case 403:
      return FunctionPermissionException(message);
    case 404:
      return FunctionNotFoundException(message);
    case 400:
      return FunctionValidationException(message);
    case 402:
      return FunctionQuotaExceededException(message);
  }
  if (statusCode >= 500) {
    return FunctionExecutionException(message, statusCode: statusCode);
  }
  return FunctionInvokeException(message, statusCode: statusCode);
}
