class KoolbaseAuthException implements Exception {
  final String message;
  final String? code;

  const KoolbaseAuthException(this.message, {this.code});

  @override
  String toString() => 'KoolbaseAuthException($code): $message';
}

class InvalidCredentialsException extends KoolbaseAuthException {
  const InvalidCredentialsException()
      : super('Invalid email or password', code: 'invalid_credentials');
}

class EmailAlreadyInUseException extends KoolbaseAuthException {
  const EmailAlreadyInUseException()
      : super('Email is already in use', code: 'email_taken');
}

class SessionExpiredException extends KoolbaseAuthException {
  const SessionExpiredException()
      : super('Session expired, please log in again', code: 'session_expired');
}

class UserDisabledException extends KoolbaseAuthException {
  const UserDisabledException()
      : super('This account has been disabled', code: 'user_disabled');
}

class WeakPasswordException extends KoolbaseAuthException {
  const WeakPasswordException()
      : super('Password must be at least 8 characters', code: 'weak_password');
}

class NetworkException extends KoolbaseAuthException {
  const NetworkException()
      : super('Network error, please check your connection',
            code: 'network_error');
}

class InvalidPhoneNumberException extends KoolbaseAuthException {
  const InvalidPhoneNumberException()
      : super('Phone number must be in E.164 format (e.g. +233XXXXXXXXX)',
            code: 'invalid_phone');
}

class OtpExpiredException extends KoolbaseAuthException {
  const OtpExpiredException()
      : super('OTP has expired, please request a new code',
            code: 'otp_expired');
}

class OtpInvalidException extends KoolbaseAuthException {
  const OtpInvalidException() : super('Invalid OTP code', code: 'otp_invalid');
}

class OtpMaxAttemptsException extends KoolbaseAuthException {
  const OtpMaxAttemptsException()
      : super('Too many incorrect attempts, please request a new code',
            code: 'otp_max_attempts');
}

class OtpRateLimitException extends KoolbaseAuthException {
  const OtpRateLimitException()
      : super('Too many OTP requests, please wait before trying again',
            code: 'otp_rate_limit');
}

class PhoneAlreadyLinkedException extends KoolbaseAuthException {
  const PhoneAlreadyLinkedException()
      : super('Phone number is already associated with another account',
            code: 'phone_taken');
}

class SmsConfigMissingException extends KoolbaseAuthException {
  const SmsConfigMissingException()
      : super('SMS provider not configured for this project',
            code: 'sms_config_missing');
}

/// Thrown when the account is temporarily locked due to too many failed
/// login attempts (brute-force protection). The server uses progressive
/// 5/10/20-attempt lockouts; if an unlock email was issued (level 2+),
/// the user can clear the lock by clicking that link, which calls
/// [KoolbaseAuthClient.unlock] with the token.
///
/// [lockedUntil] is currently null — the server returns a generic 429 but
/// does not yet include the unlock timestamp in the response body. Field
/// is forward-compatible for when the server adds it.
class AccountLockedException extends KoolbaseAuthException {
  final DateTime? lockedUntil;

  const AccountLockedException({this.lockedUntil})
      : super('Account temporarily locked due to too many failed attempts',
            code: 'account_locked');
}

/// Thrown when the server rate-limits a non-phone authentication endpoint
/// (HTTP 429 without the "account temporarily locked" marker). Phone OTP
/// endpoints throw [OtpRateLimitException] instead — they have a separate
/// rate-limiter on the server.
class RateLimitException extends KoolbaseAuthException {
  const RateLimitException([String? message])
      : super(message ?? 'Too many requests, please wait before trying again',
            code: 'rate_limit');
}

/// Thrown when the unlock token (from a brute-force unlock email) is
/// invalid or expired. Unlock tokens are one-shot — once consumed, the
/// same token can't be reused.
class UnlockTokenInvalidException extends KoolbaseAuthException {
  const UnlockTokenInvalidException()
      : super('Unlock link is invalid or has expired',
            code: 'unlock_token_invalid');
}

/// Thrown when the access token references a session that has been
/// revoked centrally — either by the user (via the sessions endpoint) or
/// by an administrator. Distinct from [SessionExpiredException] which
/// indicates the access token TTL elapsed without a successful refresh.
///
/// Forward-compatible: the server's session-aware JWT validation will
/// emit specific revocation signals in a future release; this exception
/// will be thrown when those signals appear.
class TokenRevokedException extends KoolbaseAuthException {
  const TokenRevokedException()
      : super('Session has been revoked, please log in again',
            code: 'token_revoked');
}

class AppleSignInNotConfiguredException extends KoolbaseAuthException {
  const AppleSignInNotConfiguredException()
      : super(
          'Apple Sign-In is not configured for this environment',
          code: 'apple_not_configured',
        );
}

class InvalidAppleTokenException extends KoolbaseAuthException {
  const InvalidAppleTokenException()
      : super(
          'Invalid Apple identity token',
          code: 'invalid_apple_token',
        );
}

class AppleEmailRequiredException extends KoolbaseAuthException {
  const AppleEmailRequiredException()
      : super(
          'Apple did not return email for this sign-in. Revoke this app in iOS Settings → Apple ID and retry.',
          code: 'apple_email_required',
        );
}

class OAuthEmailConflictException extends KoolbaseAuthException {
  const OAuthEmailConflictException()
      : super(
          'Email is already in use by another account. Sign in with your existing method and link Apple from settings.',
          code: 'oauth_email_conflict',
        );
}

class GoogleSignInNotConfiguredException extends KoolbaseAuthException {
  const GoogleSignInNotConfiguredException()
      : super(
          'Google Sign-In is not configured for this environment',
          code: 'google_not_configured',
        );
}

class InvalidGoogleTokenException extends KoolbaseAuthException {
  const InvalidGoogleTokenException()
      : super(
          'Invalid Google identity token',
          code: 'invalid_google_token',
        );
}

class GoogleEmailRequiredException extends KoolbaseAuthException {
  const GoogleEmailRequiredException()
      : super(
          'Google did not return email for this sign-in. Ensure the email scope is requested in the native flow.',
          code: 'google_email_required',
        );
}
