/// The canonical, platform-wide error boundary.
///
/// Every failure the SDK raises normalizes to a [KoolbaseError]. Applications —
/// generated and hand-written alike — branch on [KoolbaseError.code] and never
/// on the internal exception taxonomy, which is free to grow and rename beneath
/// this contract.
///
/// The division of labour is deliberate:
///
/// ```
/// SDK          exception -> canonical code
/// application  canonical code -> user-facing copy
/// ```
///
/// The SDK does not own presentation, and it ships no translations. An
/// application maps a code to its own localized copy, and can change that copy
/// without an SDK release.
library;

import 'dart:async' show TimeoutException;
import 'dart:io' show SocketException, HttpException;

import 'package:http/http.dart' show ClientException;

import 'koolbase_exception.dart';
import 'auth/auth_exceptions.dart';
import 'database/database_exceptions.dart';
import 'storage/storage_exceptions.dart';

/// What kind of failure occurred, in terms an application can act on.
///
/// These are actionable application-level categories, NOT the SDK's internal
/// exception taxonomy. A member exists only where an application could
/// reasonably make a different product decision because of it: `unauthorized`
/// routes to sign-in, `rateLimited` counts down, `validation` highlights a
/// field. Diagnostic distinctions that do not change what the app does — a
/// malformed auth header versus a bad signature — live in
/// [KoolbaseError.message] and the originating exception, not here.
///
/// This enum is public API. Adding a member is a breaking change for any
/// exhaustive `switch`, so members are added conservatively and never removed.
enum KoolbaseErrorCode {
  /// The request could not reach the server, or the connection failed.
  /// Retryable.
  network,

  /// The server would not accept the caller's credentials.
  ///
  /// When the SDK holds a session it clears it BEFORE throwing, so by the time
  /// an application sees this the user is already signed out and routing to
  /// sign-in is safe — and is the only correct response. Showing a banner and
  /// staying put leaves the user on a screen where every further action fails.
  unauthorized,

  /// The caller is known, and is not allowed to do this. Distinct from
  /// [unauthorized]: signing in again does not help. Not retryable.
  forbidden,

  /// The addressed record, object, or route does not exist.
  ///
  /// On a read this is a real screen — "this item is gone". On a WRITE it means
  /// the same thing as [conflict]: the record is not what the caller thought,
  /// so reload and reapply. Applications should treat it that way in a write
  /// path.
  notFound,

  /// The caller's view of the data is stale — a revision mismatch, a competing
  /// write. Reload and reapply.
  conflict,

  /// The request was well-formed but its contents were refused. Field-level
  /// detail, where the server supplied any, is in [KoolbaseError.details].
  validation,

  /// Too many requests. Distinct from [network] and [server] because the
  /// application's response is different in kind: wait, rather than retry now.
  /// A countdown, a disabled button — not a "Try again" affordance.
  rateLimited,

  /// The account's contact channel is not verified and the project requires
  /// one. The credentials were CORRECT — policy refused. Route to
  /// "resend verification", not to "check your password".
  contactNotVerified,

  /// The account has been disabled. Signing in again will not help; the user
  /// needs support.
  accountDisabled,

  /// The server failed, or the SDK is misconfigured for this project in a way
  /// the end user cannot act on. Generic failure copy is the honest response.
  server,

  /// Nothing above matched.
  ///
  /// Load-bearing, not a placeholder: normalization must be TOTAL. A failure
  /// the SDK has not yet mapped — a new server code, an unexpected throwable —
  /// arrives here rather than escaping the boundary. Applications should
  /// always handle it.
  unknown,
}

/// A normalized SDK failure.
///
/// ```dart
/// try {
///   await Koolbase.db.collection('orders').insert({'total': 42});
/// } catch (e) {
///   final err = KoolbaseError.from(e);
///   switch (err.code) {
///     case KoolbaseErrorCode.unauthorized:
///       await routeToSignIn();          // session already cleared by the SDK
///     case KoolbaseErrorCode.validation:
///       showFieldError(err.details?['field'] as String?);
///     case KoolbaseErrorCode.network:
///       showRetry();                    // err.retryable is true
///     default:
///       showGenericFailure();           // never err.message — see below
///   }
///   log(err.message);                   // diagnostics go to the log
/// }
/// ```
class KoolbaseError {
  /// What kind of failure this is. Branch on this.
  final KoolbaseErrorCode code;

  /// Developer-facing diagnostic information.
  ///
  /// This string is NOT stable API and must not be shown directly to end
  /// users. It is written for whoever is reading a log or a stack trace, in
  /// English, and it may name infrastructure, formats, or configuration —
  /// "Phone number must be in E.164 format", "SMS provider not configured for
  /// this project". Applications map [code] to their own product-specific,
  /// localized copy.
  final String message;

  /// Safe machine-readable context, where the failure carried any: the field
  /// that failed validation, a lockout timestamp, a size limit. Null when the
  /// failure carried none, which is most of the time.
  ///
  /// Contents are not stable API. Read defensively.
  final Map<String, Object?>? details;

  /// The server's raw error code, when it sent one. For logging and for codes
  /// the SDK does not yet map. Prefer [code].
  final String? rawCode;

  const KoolbaseError({
    required this.code,
    required this.message,
    this.details,
    this.rawCode,
  });

  /// Whether trying the same thing again could plausibly succeed without the
  /// user changing anything.
  ///
  /// Derived from [code] rather than stored, so it can never disagree with it.
  /// [rateLimited] is retryable but not IMMEDIATELY so — an application should
  /// wait before retrying.
  bool get retryable =>
      code == KoolbaseErrorCode.network ||
      code == KoolbaseErrorCode.rateLimited ||
      code == KoolbaseErrorCode.server;

  @override
  String toString() => 'KoolbaseError(${code.name}): $message';

  /// Normalizes ANY throwable into a [KoolbaseError].
  ///
  /// Total by construction: an input this does not recognize becomes
  /// [KoolbaseErrorCode.unknown] rather than escaping. That matters because
  /// this runs in error paths, where a second failure has nowhere to go.
  ///
  /// Written as an `if` chain rather than a `switch`, deliberately. Several
  /// families use inheritance — `KoolbaseSessionExpiredException` extends
  /// `KoolbaseUnauthenticatedException`, `KoolbaseConflictException` extends
  /// `KoolbaseDataException` — so order is load-bearing and a reordered
  /// `switch` case would silently swallow subtypes. Each ordering constraint
  /// is commented where it applies.
  factory KoolbaseError.from(Object e) {
    // --- transport, first: these are not KoolbaseExceptions at all ---
    // Most SDK surfaces do not catch these today, so a connection failure
    // arrives here raw. This is the only place transport failure becomes
    // actionable.
    if (e is SocketException ||
        e is TimeoutException ||
        e is ClientException ||
        e is HttpException) {
      return KoolbaseError(
        code: KoolbaseErrorCode.network,
        message: e.toString(),
      );
    }

    if (e is! KoolbaseException) {
      return KoolbaseError(
        code: KoolbaseErrorCode.unknown,
        message: e.toString(),
      );
    }

    final raw = e.code;

    // --- cross-cutting: raised by any surface ---
    // Before every family: a rejected credential is not a subsystem's problem.
    // The SDK has already cleared the session by this point, so the only
    // correct application response is to route to sign-in.
    if (e is KoolbaseUnauthenticatedException) {
      return KoolbaseError(
        code: KoolbaseErrorCode.unauthorized,
        message: e.message,
        rawCode: raw,
      );
    }

    // --- auth family ---
    if (e is KoolbaseAuthException) {
      // Credentials were correct; project policy refused. Routes to
      // "resend verification", not "check your password".
      if (e is ContactNotVerifiedException) {
        return KoolbaseError(
          code: KoolbaseErrorCode.contactNotVerified,
          message: e.message,
          rawCode: raw,
        );
      }
      if (e is UserDisabledException) {
        return KoolbaseError(
          code: KoolbaseErrorCode.accountDisabled,
          message: e.message,
          rawCode: raw,
        );
      }
      if (e is NetworkException) {
        return KoolbaseError(
          code: KoolbaseErrorCode.network,
          message: e.message,
          rawCode: raw,
        );
      }
      // Wait, do not retry now. AccountLocked carries a lockout timestamp
      // when the server supplies one — currently never, kept forward-compatible.
      if (e is AccountLockedException) {
        return KoolbaseError(
          code: KoolbaseErrorCode.rateLimited,
          message: e.message,
          rawCode: raw,
          details: e.lockedUntil == null
              ? null
              : {'locked_until': e.lockedUntil!.toIso8601String()},
        );
      }
      if (e is RateLimitException ||
          e is OtpRateLimitException ||
          e is OtpMaxAttemptsException ||
          e is ResendCooldownException ||
          e is ResendDailyCapException) {
        return KoolbaseError(
          code: KoolbaseErrorCode.rateLimited,
          message: e.message,
          rawCode: raw,
        );
      }
      // Session state the user can fix by acting, not by signing in again.
      if (e is SessionExpiredException || e is TokenRevokedException) {
        return KoolbaseError(
          code: KoolbaseErrorCode.unauthorized,
          message: e.message,
          rawCode: raw,
        );
      }
      // Bad input the user supplied, or a one-shot token that did not hold.
      if (e is InvalidCredentialsException ||
          e is WeakPasswordException ||
          e is InvalidPhoneNumberException ||
          e is OtpExpiredException ||
          e is OtpInvalidException ||
          e is UnlockTokenInvalidException ||
          e is InvalidAppleTokenException ||
          e is InvalidGoogleTokenException ||
          e is AppleEmailRequiredException ||
          e is GoogleEmailRequiredException) {
        return KoolbaseError(
          code: KoolbaseErrorCode.validation,
          message: e.message,
          rawCode: raw,
        );
      }
      // Something already exists: an email, a phone, another account's claim
      // on this identity. Same user action as any other collision.
      if (e is EmailAlreadyInUseException ||
          e is PhoneAlreadyLinkedException ||
          e is OAuthEmailConflictException) {
        return KoolbaseError(
          code: KoolbaseErrorCode.conflict,
          message: e.message,
          rawCode: raw,
        );
      }
      // Developer misconfiguration surfacing at runtime. The user can do
      // nothing, so generic failure copy is the honest response; the code
      // and message preserve it for logs.
      if (e is SmsConfigMissingException ||
          e is AppleSignInNotConfiguredException ||
          e is GoogleSignInNotConfiguredException) {
        return KoolbaseError(
          code: KoolbaseErrorCode.server,
          message: e.message,
          rawCode: raw,
        );
      }
      return KoolbaseError(
        code: KoolbaseErrorCode.unknown,
        message: e.message,
        rawCode: raw,
      );
    }

    // --- data family ---
    if (e is KoolbaseDataException) {
      // Before the base class: both extend KoolbaseDataException.
      if (e is KoolbaseRevisionMismatchException) {
        return KoolbaseError(
          code: KoolbaseErrorCode.conflict,
          message: e.message,
          rawCode: raw,
          details: {
            if (e.expectedRevision != null)
              'expected_revision': e.expectedRevision,
            if (e.currentRevision != null)
              'current_revision': e.currentRevision,
            // The server's current state, returned WITH the refusal so that
            // deciding what to do needs no second fetch. Dropping it here
            // would defeat the reason it is carried.
            if (e.currentRecord != null) 'current_record': e.currentRecord,
          },
        );
      }
      if (e is KoolbaseConflictException) {
        return KoolbaseError(
          code: KoolbaseErrorCode.conflict,
          message: e.message,
          rawCode: raw,
          details: e.field == null ? null : {'field': e.field},
        );
      }
      // The SDK refused to queue an offline write because it cannot know what
      // the change was composed against. IMPRECISE mapping, knowingly: the
      // device may be online, so this is not `network`, and the user's real
      // action — read the record first, or make the change while connected —
      // has no code of its own. `conflict` is the closest honest fit, and a
      // twelfth code no application would branch on differently is not worth
      // the public-API cost.
      if (e is KoolbaseOfflineBaselineUnavailableException) {
        return KoolbaseError(
          code: KoolbaseErrorCode.conflict,
          message: e.message,
          rawCode: raw,
        );
      }
      if (e is KoolbaseNotFoundException) {
        return KoolbaseError(
          code: KoolbaseErrorCode.notFound,
          message: e.message,
          rawCode: raw,
        );
      }
      if (e is KoolbasePermissionException) {
        return KoolbaseError(
          code: KoolbaseErrorCode.forbidden,
          message: e.message,
          rawCode: raw,
        );
      }
      if (e is KoolbaseRateLimitException) {
        return KoolbaseError(
          code: KoolbaseErrorCode.rateLimited,
          message: e.message,
          rawCode: raw,
        );
      }
      if (e is KoolbaseValidationException ||
          e is KoolbaseVectorDimensionMismatchException) {
        return KoolbaseError(
          code: KoolbaseErrorCode.validation,
          message: e.message,
          rawCode: raw,
        );
      }
      // koolbaseDataError returns a bare KoolbaseDataException when nothing
      // matched, carrying an unmapped server code. This is that path.
      return KoolbaseError(
        code: KoolbaseErrorCode.unknown,
        message: e.message,
        rawCode: raw,
      );
    }

    // --- storage family ---
    if (e is KoolbaseStorageException) {
      if (e is KoolbaseStorageConflictException) {
        return KoolbaseError(
          code: KoolbaseErrorCode.conflict,
          message: e.message,
          rawCode: raw,
          details: e.path == null ? null : {'path': e.path},
        );
      }
      // 404-over-403: a cross-tenant access attempt surfaces as not-found,
      // deliberately, to prevent enumeration. An application must therefore
      // keep notFound copy generic — "couldn't load that" — and never invite
      // the user to check the path.
      if (e is KoolbaseStorageNotFoundException) {
        return KoolbaseError(
          code: KoolbaseErrorCode.notFound,
          message: e.message,
          rawCode: raw,
        );
      }
      if (e is KoolbaseStoragePermissionException) {
        return KoolbaseError(
          code: KoolbaseErrorCode.forbidden,
          message: e.message,
          rawCode: raw,
        );
      }
      if (e is KoolbaseStorageMetadataInvalidException) {
        return KoolbaseError(
          code: KoolbaseErrorCode.validation,
          message: e.message,
          rawCode: raw,
          details: e.detail == null ? null : {'detail': e.detail},
        );
      }
      // Policy refusals, not malformed requests — but the user's action is
      // validation's action: pick a different file, free some space, change
      // the format. Same action, same code; `rawCode` says which.
      if (e is KoolbaseStorageValidationException ||
          e is KoolbaseStorageQuotaExceededException ||
          e is KoolbaseStorageFileTooLargeException ||
          e is KoolbaseStorageMimeTypeException) {
        return KoolbaseError(
          code: KoolbaseErrorCode.validation,
          message: e.message,
          rawCode: raw,
        );
      }
      return KoolbaseError(
        code: KoolbaseErrorCode.unknown,
        message: e.message,
        rawCode: raw,
      );
    }

    // KoolbaseException subclasses with no family — functions, realtime, and
    // code push raise these today, having no exception files of their own.
    return KoolbaseError(
      code: KoolbaseErrorCode.unknown,
      message: e.message,
      rawCode: raw,
    );
  }
}
