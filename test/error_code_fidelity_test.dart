import 'package:flutter_test/flutter_test.dart';
import 'package:koolbase_flutter/koolbase_flutter.dart';

// Every exception reports a code the server actually sends.
//
// The switches in the API layer map a server code to an exception. They do
// not check what that exception then reports, and the two are different
// things: an app can catch EmailAlreadyInUseException correctly while its
// `code` field says 'email_taken' for a server that has always said
// 'email_in_use'. Fourteen were wrong that way, here and in the TypeScript
// SDKs, for months — invisible because every documented example catches by
// type.
//
// `code` is a public field. Anyone reading it instead of catching by type is
// comparing against a string that will never arrive.
//
// API_CODES is the API's own list, from platform/respond/codes.go. When the
// API declares a new code, it goes here.

const apiCodes = <String>{
  'account_disabled', 'account_exists', 'account_locked', 'ambiguous_match',
  'batch_failed', 'cap_below_usage', 'collection_not_found', 'conflict',
  'constraint_exists', 'constraint_not_found', 'contact_not_verified',
  'duplicate', 'duplicate_values', 'email_in_use', 'email_not_verified',
  'error', 'field_not_auto_embed', 'file_too_large',
  'hide_requires_verification', 'idempotency_conflict',
  'idempotency_key_reused', 'identity_not_found', 'insufficient_authority',
  'insufficient_scope', 'internal_error', 'invalid', 'invalid_body',
  'invalid_credentials', 'invalid_embedding_config', 'invalid_oauth_token',
  'invalid_password', 'invalid_phone', 'invalid_refresh_token',
  'invalid_seed_file', 'invalid_token', 'invalid_unlock_token',
  'invitation_invalid', 'last_credential', 'metadata_invalid',
  'mime_not_allowed', 'no_changes', 'not_found', 'oauth_email_conflict',
  'oauth_email_required', 'oauth_not_configured', 'oauth_only_account',
  'otp_expired', 'otp_invalid', 'otp_max_attempts', 'path_conflict',
  'permission_denied', 'phone_in_use', 'plan_limit_reached',
  'project_invalid', 'provider_identity_already_linked', 'provider_invalid',
  'provider_not_configured', 'quota_exceeded', 'rate_limit',
  'record_not_found', 'resend_cooldown', 'resend_daily_cap',
  'revision_mismatch', 'seed_conflicts_require_force', 'seed_key_not_unique',
  'seed_needs_decision', 'session_required', 'signups_disabled',
  'slug_taken', 'sms_not_configured', 'state_conflict', 'token_expired',
  'token_used', 'unauthenticated', 'unique_violation',
  'unsupported_dimension', 'unsupported_oauth_provider', 'upload_expired',
  'upload_url_failed', 'validation_error', 'vector_collection_mismatch',
  'vector_dimension_mismatch', 'vector_field_exists', 'vector_field_not_found',
  'vector_not_found', 'weak_password',
};

// Codes with no server counterpart, each for a checked reason.
const clientOnly = <String>{
  // Raised by the SDK itself; no server involved, or the response was the
  // problem.
  'network_error', // the request never reached a server
  'conflict_not_found', // the local write queue has no such conflict
  'project_identity_unavailable', // bootstrap has not completed
  'offline_baseline_unavailable',
  'execution_failed', // function invokes map by status, not by code

  // Reserved. TokenRevokedException exists for a contract that does not yet
  // exist: explicit revocation is worth telling a user about differently
  // from an expiry, but the server cannot currently establish it — a
  // rejected refresh token is indistinguishable from a deleted one. Nothing
  // throws this today. It stays because removing a public class is
  // breaking, and because the contract is worth building.
  'token_revoked',
};

/// One instance of every exception the SDK can hand an application.
final exceptions = <KoolbaseException>[
  const InvalidCredentialsException(),
  const InvalidPasswordException(),
  const WeakPasswordException(),
  const EmailAlreadyInUseException(),
  const UserDisabledException(),
  const ContactNotVerifiedException(),
  const AccountLockedException(),
  const SessionExpiredException(),
  const TokenRevokedException(),
  const UnlockTokenInvalidException(),
  const InvalidPhoneNumberException(),
  const OtpExpiredException(),
  const OtpInvalidException(),
  const OtpMaxAttemptsException(),
  const OtpRateLimitException(),
  const PhoneAlreadyLinkedException(),
  const SmsConfigMissingException(),
  const NetworkException(),
  RateLimitException(null),
  ResendCooldownException(null),
  ResendDailyCapException(null),
];

void main() {
  group('exception codes are codes the server sends', () {
    for (final e in exceptions) {
      test('${e.runtimeType} reports ${e.code}', () {
        final code = e.code;
        if (code == null || code.isEmpty) return;
        if (clientOnly.contains(code)) return;

        expect(
          apiCodes.contains(code),
          isTrue,
          reason:
              '${e.runtimeType} reports "$code", which the API never sends. '
              'Either the class is wrong, or the code belongs in clientOnly '
              'with a reason.',
        );
      });
    }
  });
}
