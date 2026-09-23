import '../koolbase_exception.dart';

/// Something went wrong signing in, signing up, or maintaining a session.
///
/// Sits under [KoolbaseException] with the other families, so an application can
/// catch any SDK failure in one place when it wants to.
class KoolbaseAuthException extends KoolbaseException {
  const KoolbaseAuthException(super.message, {super.code});
}

/// The current password given to [changePassword] did not match, or the
/// account signed up through a provider and has no password to change.
/// The server returns the same code for both so a caller cannot probe
/// which sign-in methods an account has.
class InvalidPasswordException extends KoolbaseAuthException {
  const InvalidPasswordException()
      : super('Current password is incorrect', code: 'invalid_password');
}

class InvalidCredentialsException extends KoolbaseAuthException {
  const InvalidCredentialsException()
      : super('Invalid email or password', code: 'invalid_credentials');
}

class EmailAlreadyInUseException extends KoolbaseAuthException {
  const EmailAlreadyInUseException()
      : super('Email is already in use', code: 'email_in_use');
}

class SessionExpiredException extends KoolbaseAuthException {
  const SessionExpiredException()
      : super('Session expired, please log in again', code: 'invalid_refresh_token');
}

class UserDisabledException extends KoolbaseAuthException {
  const UserDisabledException()
      : super('This account has been disabled', code: 'account_disabled');
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

/// The project has switched off signing in with an emailed code — 403
/// `email_code_disabled`. Applies to every address alike, so it reveals
/// nothing about which accounts exist.
class EmailCodeDisabledException extends KoolbaseAuthException {
  const EmailCodeDisabledException()
      : super('Signing in with an emailed code is switched off for this project',
            code: 'email_code_disabled');
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
            code: 'rate_limit');
}

class PhoneAlreadyLinkedException extends KoolbaseAuthException {
  const PhoneAlreadyLinkedException()
      : super('Phone number is already associated with another account',
            code: 'phone_in_use');
}

class SmsConfigMissingException extends KoolbaseAuthException {
  const SmsConfigMissingException()
      : super('SMS provider not configured for this project',
            code: 'sms_not_configured');
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

/// Thrown by [KoolbaseAuthClient.resendVerificationEmail] when a resend is
/// requested during the cooldown window. Recoverable — retry after the
/// cooldown (see [ResendVerificationResult.cooldownUntil] from a successful
/// send for the countdown).
class ResendCooldownException extends KoolbaseAuthException {
  const ResendCooldownException([String? message])
      : super(
            message ??
                'Please wait before requesting another verification email',
            code: 'resend_cooldown');
}

/// Thrown by [KoolbaseAuthClient.resendVerificationEmail] when the daily
/// verification-email limit has been reached. Not recoverable until the
/// 24-hour window rolls over.
class ResendDailyCapException extends KoolbaseAuthException {
  const ResendDailyCapException([String? message])
      : super(
            message ??
                'Daily verification-email limit reached, try again tomorrow',
            code: 'resend_daily_cap');
}

/// Thrown when the unlock token (from a brute-force unlock email) is
/// invalid or expired. Unlock tokens are one-shot — once consumed, the
/// same token can't be reused.
class UnlockTokenInvalidException extends KoolbaseAuthException {
  const UnlockTokenInvalidException()
      : super('Unlock link is invalid or has expired',
            code: 'invalid_unlock_token');
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
          code: 'oauth_not_configured',
        );
}

class InvalidAppleTokenException extends KoolbaseAuthException {
  const InvalidAppleTokenException()
      : super(
          'Invalid Apple identity token',
          code: 'invalid_oauth_token',
        );
}

class AppleEmailRequiredException extends KoolbaseAuthException {
  const AppleEmailRequiredException()
      : super(
          'Apple did not return email for this sign-in. Revoke this app in iOS Settings → Apple ID and retry.',
          code: 'oauth_email_required',
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
          code: 'oauth_not_configured',
        );
}

class InvalidGoogleTokenException extends KoolbaseAuthException {
  const InvalidGoogleTokenException()
      : super(
          'Invalid Google identity token',
          code: 'invalid_oauth_token',
        );
}

class GoogleEmailRequiredException extends KoolbaseAuthException {
  const GoogleEmailRequiredException()
      : super(
          'Google did not return email for this sign-in. Ensure the email scope is requested in the native flow.',
          code: 'oauth_email_required',
        );
}

/// Thrown when a project requires a verified contact channel and the account
/// has none. The credentials were CORRECT — the project's policy refused.
///
/// Distinct from [InvalidCredentialsException] so apps route the user to
/// "resend verification" rather than "check your password". A project enables
/// this from its Koolbase dashboard (auth settings → require verified
/// contact); it is off by default for existing projects.
///
/// A verified email, a verified phone, or a federated provider identity all
/// satisfy the requirement.
class ContactNotVerifiedException extends KoolbaseAuthException {
  const ContactNotVerifiedException()
      : super(
          'Verify your email or phone before signing in',
          code: 'contact_not_verified',
        );
}

// ─── Added 20 Sep 2026 ──────────────────────────────────────────────────────
//
// Thirteen codes the API emits that nothing here caught, so they arrived as a
// bare KoolbaseAuthException and an app's `on` clause silently never ran.
// Found by comparing the API's declared code list against this file; the
// TypeScript SDKs had the same gap and the same fix.

/// An OAuth sign-in for an email that already has an account by another
/// method. Sign in the existing way first, then connect the provider.
class AccountExistsException extends KoolbaseAuthException {
  const AccountExistsException([String? message])
      : super(
            message ??
                'An account with this email already exists — sign in with your '
                    'existing method first',
            code: 'account_exists');
}

/// The project has registration turned off. Not a credential problem.
class SignupsDisabledException extends KoolbaseAuthException {
  const SignupsDisabledException([String? message])
      : super(message ?? 'Registration is disabled for this project',
            code: 'signups_disabled');
}

/// A verification or reset link that has expired. Request another.
///
/// Distinct from [TokenAlreadyUsedException]: expired means ask again, used
/// usually means it already worked and the user is clicking an old email.
class TokenExpiredException extends KoolbaseAuthException {
  const TokenExpiredException([String? message])
      : super(message ?? 'This link has expired — request a new one',
            code: 'token_expired');
}

/// A one-shot link clicked twice.
class TokenAlreadyUsedException extends KoolbaseAuthException {
  const TokenAlreadyUsedException([String? message])
      : super(message ?? 'This link has already been used',
            code: 'token_used');
}

/// A password attempt against an account that only has Google or Apple.
class OAuthOnlyAccountException extends KoolbaseAuthException {
  const OAuthOnlyAccountException([String? message])
      : super(
            message ??
                'This account uses Google or Apple sign-in and has no password',
            code: 'oauth_only_account');
}

/// A provider the project has not enabled.
class UnsupportedOAuthProviderException extends KoolbaseAuthException {
  const UnsupportedOAuthProviderException([String? message])
      : super(message ?? 'That sign-in method is not available',
            code: 'unsupported_oauth_provider');
}

/// The provider is not connected to this account.
class IdentityNotFoundException extends KoolbaseAuthException {
  const IdentityNotFoundException([String? message])
      : super(message ?? 'That provider is not connected to your account',
            code: 'identity_not_found');
}

/// Connecting a Google or Apple identity that another account already holds.
/// About the provider identity itself, where [AccountExistsException] is
/// about the email.
class ProviderIdentityAlreadyLinkedException extends KoolbaseAuthException {
  const ProviderIdentityAlreadyLinkedException([String? message])
      : super(
            message ??
                'That provider identity is already linked to another account',
            code: 'provider_identity_already_linked');
}

/// Refused because it would remove the account's last way of signing in.
class LastCredentialException extends KoolbaseAuthException {
  const LastCredentialException([String? message])
      : super(
            message ??
                "This is the account's only sign-in method and cannot be removed",
            code: 'last_credential');
}

/// The call needs a signed-in user and did not have one.
class SessionRequiredException extends KoolbaseAuthException {
  const SessionRequiredException([String? message])
      : super(message ?? 'This action requires a signed-in user',
            code: 'session_required');
}

/// The API key's scope is below what the operation requires. Scopes rank
/// read < write < admin. The key is valid — a different key or a dashboard
/// session is needed, so do not tell the user to sign in again.
class InsufficientScopeException extends KoolbaseAuthException {
  const InsufficientScopeException([String? message])
      : super(message ?? "This key's scope does not permit this operation",
            code: 'insufficient_scope');
}

/// Hiding account existence needs verified contact on; the project has it
/// off. A settings-validation refusal, not a user error.
class HideRequiresVerificationException extends KoolbaseAuthException {
  const HideRequiresVerificationException([String? message])
      : super(
            message ??
                'Hiding account existence requires verified contact to be '
                    'enabled',
            code: 'hide_requires_verification');
}
