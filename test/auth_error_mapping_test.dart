import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:koolbase_flutter/koolbase_flutter.dart';
import 'package:koolbase_flutter/src/auth/auth_api.dart';

// Every auth error code the API emits, mapped to the exception an app
// catches.
//
// This is the first test the auth error mapping has ever had, in the SDK
// with real users on it. A code with no case falls through to a bare
// KoolbaseAuthException, and the app's `on SomeException` clause silently
// never runs — nothing inside the SDK can detect that. Thirteen codes went
// unmapped that way until 20 Sep 2026.
//
// Two things per code: it produces the right type, and that type reports the
// code the server sent. The second is what error_code_fidelity_test checks
// for the classes; this checks it for the path.

AuthApi apiAnswering(String code) => AuthApi(
      baseUrl: 'https://api.test',
      publicKey: 'pk_test',
      client: MockClient((_) async => http.Response(
            jsonEncode({'code': code, 'error': 'server message'}),
            400,
            headers: {'content-type': 'application/json'},
          )),
    );

/// (server code, matcher for the exception it must produce)
final cases = <(String, Matcher)>[
  ('invalid_credentials', isA<InvalidCredentialsException>()),
  ('invalid_password', isA<InvalidPasswordException>()),
  ('weak_password', isA<WeakPasswordException>()),
  ('email_in_use', isA<EmailAlreadyInUseException>()),
  ('account_disabled', isA<UserDisabledException>()),
  ('contact_not_verified', isA<ContactNotVerifiedException>()),
  ('account_locked', isA<AccountLockedException>()),
  ('invalid_refresh_token', isA<SessionExpiredException>()),
  ('invalid_unlock_token', isA<UnlockTokenInvalidException>()),
  ('rate_limit', isA<RateLimitException>()),
  ('resend_cooldown', isA<ResendCooldownException>()),
  ('resend_daily_cap', isA<ResendDailyCapException>()),

  // Added 20 Sep 2026.
  ('email_not_verified', isA<ContactNotVerifiedException>()),
  ('account_exists', isA<AccountExistsException>()),
  ('signups_disabled', isA<SignupsDisabledException>()),
  ('token_expired', isA<TokenExpiredException>()),
  ('token_used', isA<TokenAlreadyUsedException>()),
  ('oauth_only_account', isA<OAuthOnlyAccountException>()),
  ('unsupported_oauth_provider', isA<UnsupportedOAuthProviderException>()),
  ('identity_not_found', isA<IdentityNotFoundException>()),
  ('provider_identity_already_linked',
      isA<ProviderIdentityAlreadyLinkedException>()),
  ('last_credential', isA<LastCredentialException>()),
  ('session_required', isA<SessionRequiredException>()),
  ('insufficient_scope', isA<InsufficientScopeException>()),
  ('hide_requires_verification', isA<HideRequiresVerificationException>()),
];

void main() {
  group('auth error mapping', () {
    for (final (code, matcher) in cases) {
      test('$code maps to its own exception', () async {
        final api = apiAnswering(code);
        await expectLater(
          api.login(email: 'a@b.test', password: 'password123'),
          throwsA(matcher),
        );
      });

      test('$code is reported as itself', () async {
        // email_not_verified is the one deliberate exception: it maps to the
        // same class as contact_not_verified, which reports that code. The
        // two are one situation named twice, and the class picks one name.
        if (code == 'email_not_verified') return;

        final api = apiAnswering(code);
        try {
          await api.login(email: 'a@b.test', password: 'password123');
          fail('expected an exception');
        } on KoolbaseAuthException catch (e) {
          expect(e.code, code,
              reason: '${e.runtimeType} reports "${e.code}" for a server '
                  'that sent "$code"');
        }
      });
    }
  });
}
