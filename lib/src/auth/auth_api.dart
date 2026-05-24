import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_models.dart';
import 'auth_exceptions.dart';
import 'device_metadata.dart';

class AuthApi {
  final String baseUrl;
  final String publicKey;

  /// Optional device metadata. When provided, all authentication requests
  /// (login, register, refresh, me, profile updates, OTP flows, etc.)
  /// carry x-koolbase-* headers + a structured User-Agent — letting the
  /// server attribute session activity to the SDK version, platform, app
  /// version, and a stable per-install device label.
  ///
  /// Build via [DeviceMetadata.build] once at SDK init.
  final DeviceMetadata? deviceMetadata;

  /// Timeout applied to every authentication HTTP request. Default 10s.
  ///
  /// Tune up for high-latency networks (e.g. cross-region mobile in
  /// emerging markets); tune down for fast-fail UX on first-byte latency.
  final Duration timeout;

  final http.Client _client;
  final bool _ownsClient;

  /// Construct an AuthApi.
  ///
  /// [client] is optional. If provided, the SDK will use it for all auth
  /// requests and will NOT close it on [dispose] — the caller owns the
  /// client's lifecycle. Provide your own client to add logging, retries,
  /// proxy config, or to share connection pools across SDK modules.
  ///
  /// If omitted, a fresh [http.Client] is constructed and is closed by
  /// [dispose].
  AuthApi({
    required this.baseUrl,
    required this.publicKey,
    this.deviceMetadata,
    this.timeout = const Duration(seconds: 10),
    http.Client? client,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null;

  /// Close the underlying HTTP client if this AuthApi owns it. Safe to
  /// call multiple times; no-op for caller-supplied clients.
  ///
  /// Called automatically by [KoolbaseAuthClient.dispose].
  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'x-api-key': publicKey,
        ...?deviceMetadata?.toHeaders(),
      };

  Map<String, String> _authHeaders(String accessToken) => {
        'Content-Type': 'application/json',
        'x-api-key': publicKey,
        'Authorization': 'Bearer $accessToken',
        ...?deviceMetadata?.toHeaders(),
      };

  Future<AuthSession> signUp({
    required String email,
    required String password,
    String? fullName,
  }) async {
    final res = await _client
        .post(
          Uri.parse('$baseUrl/v1/sdk/auth/register'),
          headers: _headers,
          body: jsonEncode({
            'email': email,
            'password': password,
            if (fullName != null) 'full_name': fullName,
          }),
        )
        .timeout(timeout);
    return _parseSession(res);
  }

  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    final res = await _client
        .post(
          Uri.parse('$baseUrl/v1/sdk/auth/login'),
          headers: _headers,
          body: jsonEncode({'email': email, 'password': password}),
        )
        .timeout(timeout);
    return _parseSession(res);
  }

  /// Refresh exchanges a refresh token for a new access token + rotated
  /// refresh token. 401 in this context means the refresh token was rejected
  /// (revoked, expired, or otherwise invalid) — distinct from login's 401
  /// which means bad credentials.
  Future<AuthSession> refresh(String refreshToken) async {
    final res = await _client
        .post(
          Uri.parse('$baseUrl/v1/sdk/auth/refresh'),
          headers: _headers,
          body: jsonEncode({'refresh_token': refreshToken}),
        )
        .timeout(timeout);
    return _parseSession(res, isRefresh: true);
  }

  Future<void> logout(String accessToken) async {
    final res = await _client
        .post(
          Uri.parse('$baseUrl/v1/sdk/auth/logout'),
          headers: _authHeaders(accessToken),
        )
        .timeout(timeout);
    _checkError(res);
  }

  Future<KoolbaseUser> getMe(String accessToken) async {
    final res = await _client
        .get(
          Uri.parse('$baseUrl/v1/sdk/auth/me'),
          headers: _authHeaders(accessToken),
        )
        .timeout(timeout);
    _checkError(res);
    return KoolbaseUser.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<KoolbaseUser> updateProfile({
    required String accessToken,
    String? fullName,
    String? avatarUrl,
  }) async {
    final res = await _client
        .patch(
          Uri.parse('$baseUrl/v1/sdk/auth/me'),
          headers: _authHeaders(accessToken),
          body: jsonEncode({
            if (fullName != null) 'full_name': fullName,
            if (avatarUrl != null) 'avatar_url': avatarUrl,
          }),
        )
        .timeout(timeout);
    _checkError(res);
    return KoolbaseUser.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<void> forgotPassword(String email) async {
    final res = await _client
        .post(
          Uri.parse('$baseUrl/v1/sdk/auth/password-reset'),
          headers: _headers,
          body: jsonEncode({'email': email}),
        )
        .timeout(timeout);
    _checkError(res);
  }

  Future<void> resetPassword({
    required String token,
    required String password,
  }) async {
    final res = await _client
        .post(
          Uri.parse('$baseUrl/v1/sdk/auth/password-reset/confirm'),
          headers: _headers,
          body: jsonEncode({'token': token, 'password': password}),
        )
        .timeout(timeout);
    _checkError(res);
  }

  Future<void> verifyEmail(String token) async {
    final res = await _client
        .post(
          Uri.parse('$baseUrl/v1/sdk/auth/verify-email'),
          headers: _headers,
          body: jsonEncode({'token': token}),
        )
        .timeout(timeout);
    _checkError(res);
  }

  /// Consume an unlock token from a brute-force unlock email. Returns
  /// nothing on success (204). Throws [UnlockTokenInvalidException] if
  /// the token is invalid, expired, or already consumed.
  Future<void> unlock(String token) async {
    final res = await _client
        .post(
          Uri.parse('$baseUrl/v1/sdk/auth/unlock'),
          headers: _headers,
          body: jsonEncode({'token': token}),
        )
        .timeout(timeout);
    _checkError(res);
  }

  /// Parse a session-returning response (login, signUp, refresh).
  ///
  /// [isRefresh] controls how a bare 401 (no `code`, older server) is
  /// interpreted in the fallback path:
  /// - false (default, login/signUp): 401 = invalid credentials
  /// - true (refresh): 401 = session expired (refresh token was rejected)
  AuthSession _parseSession(http.Response res, {bool isRefresh = false}) {
    if (res.statusCode < 200 || res.statusCode >= 300) {
      _checkError(res, isRefresh: isRefresh); // never returns
    }
    return AuthSession.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Map a non-2xx credential/session response to a typed exception.
  ///
  /// Code-first: the server now emits a stable `code` on every error
  /// (contract conformance), so we switch on `body['code']`. The status +
  /// message logic is retained as a fallback for older servers or any
  /// response that arrives without a code.
  void _checkError(http.Response res, {bool isRefresh = false}) {
    if (res.statusCode >= 200 && res.statusCode < 300) return;

    Map<String, dynamic> body = {};
    try {
      body = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {}
    final code = (body['code'] as String?) ?? '';
    final msg = (body['error'] as String?) ?? '';

    // ---- code-first ----
    switch (code) {
      case 'invalid_credentials':
        throw const InvalidCredentialsException();
      case 'email_in_use':
        throw const EmailAlreadyInUseException();
      case 'account_disabled':
        throw const UserDisabledException();
      case 'account_locked':
        throw const AccountLockedException();
      case 'invalid_refresh_token':
        // Refresh token rejected — the session is unrecoverable; re-login.
        throw const SessionExpiredException();
      case 'token_revoked':
        throw const TokenRevokedException();
      case 'invalid_unlock_token':
        throw const UnlockTokenInvalidException();
      case 'rate_limit':
        throw RateLimitException(msg.isEmpty ? null : msg);
    }

    // ---- status fallback (pre-code servers) ----
    switch (res.statusCode) {
      case 409:
        throw const EmailAlreadyInUseException();
      case 401:
        throw isRefresh
            ? const SessionExpiredException()
            : const InvalidCredentialsException();
      case 403:
        throw const UserDisabledException();
      case 429:
        if (msg.contains('account temporarily locked')) {
          throw const AccountLockedException();
        }
        throw RateLimitException(msg.isEmpty ? null : msg);
    }

    // ---- legacy message fallback ----
    if (msg.contains('invalid or expired unlock token')) {
      throw const UnlockTokenInvalidException();
    }
    if (msg.contains('session revoked') ||
        msg.contains('token revoked') ||
        msg.contains('session has been revoked')) {
      throw const TokenRevokedException();
    }

    throw KoolbaseAuthException(
      msg.isEmpty ? 'An unexpected error occurred' : msg,
      code: code.isEmpty ? null : code,
    );
  }

  /// **DEPRECATED.** The server-side `/v1/sdk/auth/oauth` endpoint for
  /// end-user OAuth (Google, GitHub) does not yet exist. The previous
  /// implementation incorrectly targeted `/v1/auth/oauth`, which is the
  /// dashboard's developer OAuth handler — not a customer-app surface.
  ///
  /// This method is retained as a stub to preserve the call surface. It
  /// will be properly implemented in v2.10.x once the server endpoint
  /// ships. For Sign in with Apple, use [KoolbaseAppleAuth.signIn] —
  /// that flow uses a different server endpoint and works today.
  @Deprecated(
      'End-user OAuth server endpoint not yet shipped. Use email/password '
      'or KoolbaseAppleAuth.signIn for now. Tracking: v2.10.x.')
  Future<Map<String, dynamic>> oauthLogin({
    required String provider,
    required String token,
    String email = '',
    String name = '',
    String avatarUrl = '',
  }) async {
    throw UnimplementedError(
      'AuthApi.oauthLogin is not yet supported. The server-side '
      '/v1/sdk/auth/oauth endpoint is on the roadmap for v2.10.x. For now, '
      'use email/password authentication or KoolbaseAppleAuth.signIn for '
      'Sign in with Apple.',
    );
  }

  Future<OtpSendResult> sendOtp({required String phoneNumber}) async {
    final res = await _client
        .post(
          Uri.parse('$baseUrl/v1/sdk/auth/phone/send-otp'),
          headers: _headers,
          body: jsonEncode({'phone_number': phoneNumber}),
        )
        .timeout(timeout);
    _checkPhoneError(res);
    return OtpSendResult.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<PhoneVerifyResult> verifyOtp({
    required String phoneNumber,
    required String code,
  }) async {
    final res = await _client
        .post(
          Uri.parse('$baseUrl/v1/sdk/auth/phone/verify-otp'),
          headers: _headers,
          body: jsonEncode({'phone_number': phoneNumber, 'code': code}),
        )
        .timeout(timeout);
    _checkPhoneError(res);
    return PhoneVerifyResult.fromJson(
        jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<void> linkPhone({
    required String accessToken,
    required String phoneNumber,
    required String code,
  }) async {
    final res = await _client
        .post(
          Uri.parse('$baseUrl/v1/sdk/auth/phone/link'),
          headers: _authHeaders(accessToken),
          body: jsonEncode({'phone_number': phoneNumber, 'code': code}),
        )
        .timeout(timeout);
    _checkPhoneError(res);
  }

  /// Map a non-2xx phone-auth response to a typed exception.
  ///
  /// Code-first, with a phone-specific twist: the server emits the generic
  /// `rate_limit` code for the phone endpoints (they share the default 429),
  /// but phone has a dedicated server-side rate-limiter, so we surface the
  /// phone-specific [OtpRateLimitException] rather than [RateLimitException].
  /// Status + message logic is kept as a fallback for older servers.
  void _checkPhoneError(http.Response res) {
    if (res.statusCode >= 200 && res.statusCode < 300) return;

    Map<String, dynamic> body = {};
    try {
      body = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {}
    final code = (body['code'] as String?) ?? '';
    final msg = (body['error'] as String?) ?? '';

    // ---- code-first ----
    switch (code) {
      case 'invalid_phone':
        throw const InvalidPhoneNumberException();
      case 'otp_expired':
        throw const OtpExpiredException();
      case 'otp_invalid':
        throw const OtpInvalidException();
      case 'otp_max_attempts':
        throw const OtpMaxAttemptsException();
      case 'phone_in_use':
        throw const PhoneAlreadyLinkedException();
      case 'sms_not_configured':
        throw const SmsConfigMissingException();
      case 'rate_limit':
        throw const OtpRateLimitException();
    }

    // ---- status fallback (pre-code servers) ----
    switch (res.statusCode) {
      case 429:
        throw const OtpRateLimitException();
      case 409:
        throw const PhoneAlreadyLinkedException();
    }

    // ---- legacy message fallback ----
    if (msg.contains('E.164')) throw const InvalidPhoneNumberException();
    if (msg.contains('OTP has expired')) throw const OtpExpiredException();
    if (msg.contains('too many incorrect attempts')) {
      throw const OtpMaxAttemptsException();
    }
    if (msg.contains('invalid OTP') || msg.contains('invalid or expired OTP')) {
      throw const OtpInvalidException();
    }
    if (msg.contains('SMS provider not configured')) {
      throw const SmsConfigMissingException();
    }

    throw KoolbaseAuthException(
      msg.isEmpty ? 'An unexpected error occurred' : msg,
      code: code.isEmpty ? null : code,
    );
  }

  /// POST /v1/sdk/auth/oauth/apple — server-side Apple Sign-In.
  ///
  /// [identityToken] is the JWT from a native Apple Sign-In credential.
  /// [nonce], if provided, must match what was passed to the native
  /// sign-in flow (replay defense). [fullName] is only sent on first
  /// sign-in (Apple omits name data on subsequent sign-ins).
  Future<AuthSession> signInWithApple({
    required String identityToken,
    String? nonce,
    AppleFullName? fullName,
  }) async {
    final body = <String, dynamic>{
      'identity_token': identityToken,
    };
    if (nonce != null && nonce.isNotEmpty) {
      body['nonce'] = nonce;
    }
    if (fullName != null) {
      final nameJson = fullName.toJson();
      if (nameJson.isNotEmpty) {
        body['full_name'] = nameJson;
      }
    }

    final res = await _client
        .post(
          Uri.parse('$baseUrl/v1/sdk/auth/oauth/apple'),
          headers: _headers,
          body: jsonEncode(body),
        )
        .timeout(timeout);

    return _parseAppleSessionResponse(res);
  }

  /// Parses a /v1/sdk/auth/oauth/apple response. Code-first: the server
  /// emits unified OAuth codes (oauth_not_configured, invalid_oauth_token,
  /// oauth_email_required, oauth_email_conflict) for both Apple and Google;
  /// the provider distinction is made here at the call site, so Apple codes
  /// map to Apple-specific exceptions. Status + message logic is retained as
  /// a fallback for older servers.
  Future<AuthSession> _parseAppleSessionResponse(http.Response response) async {
    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return AuthSession.fromJson(json);
    }

    Map<String, dynamic> body = {};
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {}
    final code = (body['code'] as String?) ?? '';
    final errorMessage = (body['error'] as String?) ?? '';

    // ---- code-first ----
    switch (code) {
      case 'oauth_not_configured':
        throw const AppleSignInNotConfiguredException();
      case 'invalid_oauth_token':
        throw const InvalidAppleTokenException();
      case 'account_disabled':
        throw const UserDisabledException();
      case 'oauth_email_required':
        throw const AppleEmailRequiredException();
      case 'oauth_email_conflict':
        throw const OAuthEmailConflictException();
      case 'rate_limit':
        throw RateLimitException(errorMessage.isEmpty ? null : errorMessage);
    }

    // ---- status + message fallback (pre-code servers) ----
    switch (response.statusCode) {
      case 400:
        if (errorMessage.contains('not configured')) {
          throw const AppleSignInNotConfiguredException();
        }
        if (errorMessage.contains('did not return email')) {
          throw const AppleEmailRequiredException();
        }
        throw KoolbaseAuthException('apple sign-in failed: $errorMessage');
      case 401:
        throw const InvalidAppleTokenException();
      case 403:
        throw const UserDisabledException();
      case 409:
        throw const OAuthEmailConflictException();
      case 429:
        throw RateLimitException(errorMessage.isEmpty ? null : errorMessage);
      default:
        throw KoolbaseAuthException(
          'apple sign-in failed: ${response.statusCode} $errorMessage',
        );
    }
  }

  /// POST /v1/sdk/auth/oauth/google — server-side Google Sign-In.
  ///
  /// [idToken] is the JWT from a native Google Sign-In credential.
  /// [nonce], if provided, must match what was passed to the native
  /// sign-in flow (replay defense). Google embeds the user's name and
  /// email in the token itself, so unlike Apple this method does not
  /// take a fullName parameter.
  Future<AuthSession> signInWithGoogle({
    required String idToken,
    String? nonce,
  }) async {
    final body = <String, dynamic>{
      'identity_token': idToken,
    };
    if (nonce != null && nonce.isNotEmpty) {
      body['nonce'] = nonce;
    }

    final res = await _client
        .post(
          Uri.parse('$baseUrl/v1/sdk/auth/oauth/google'),
          headers: _headers,
          body: jsonEncode(body),
        )
        .timeout(timeout);

    return _parseGoogleSessionResponse(res);
  }

  /// Parses a /v1/sdk/auth/oauth/google response. Code-first; the provider
  /// distinction is made here so the server's unified OAuth codes map to
  /// Google-specific exceptions. Status + message logic is retained as a
  /// fallback for older servers.
  Future<AuthSession> _parseGoogleSessionResponse(
      http.Response response) async {
    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return AuthSession.fromJson(json);
    }

    Map<String, dynamic> body = {};
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {}
    final code = (body['code'] as String?) ?? '';
    final errorMessage = (body['error'] as String?) ?? '';

    // ---- code-first ----
    switch (code) {
      case 'oauth_not_configured':
        throw const GoogleSignInNotConfiguredException();
      case 'invalid_oauth_token':
        throw const InvalidGoogleTokenException();
      case 'account_disabled':
        throw const UserDisabledException();
      case 'oauth_email_required':
        throw const GoogleEmailRequiredException();
      case 'oauth_email_conflict':
        throw const OAuthEmailConflictException();
      case 'rate_limit':
        throw RateLimitException(errorMessage.isEmpty ? null : errorMessage);
    }

    // ---- status + message fallback (pre-code servers) ----
    switch (response.statusCode) {
      case 400:
        if (errorMessage.contains('not configured')) {
          throw const GoogleSignInNotConfiguredException();
        }
        if (errorMessage.contains('did not return email')) {
          throw const GoogleEmailRequiredException();
        }
        throw KoolbaseAuthException('google sign-in failed: $errorMessage');
      case 401:
        throw const InvalidGoogleTokenException();
      case 403:
        throw const UserDisabledException();
      case 409:
        throw const OAuthEmailConflictException();
      case 429:
        throw RateLimitException(errorMessage.isEmpty ? null : errorMessage);
      default:
        throw KoolbaseAuthException(
          'google sign-in failed: ${response.statusCode} $errorMessage',
        );
    }
  }
}
