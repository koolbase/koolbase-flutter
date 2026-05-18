import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_models.dart';
import 'auth_exceptions.dart';

class AuthApi {
  final String baseUrl;
  final String publicKey;

  const AuthApi({required this.baseUrl, required this.publicKey});

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'x-api-key': publicKey,
      };

  Map<String, String> _authHeaders(String accessToken) => {
        'Content-Type': 'application/json',
        'x-api-key': publicKey,
        'Authorization': 'Bearer $accessToken',
      };

  Future<AuthSession> signUp({
    required String email,
    required String password,
    String? fullName,
  }) async {
    final res = await http
        .post(
          Uri.parse('$baseUrl/v1/sdk/auth/register'),
          headers: _headers,
          body: jsonEncode({
            'email': email,
            'password': password,
            if (fullName != null) 'full_name': fullName,
          }),
        )
        .timeout(const Duration(seconds: 10));
    return _parseSession(res);
  }

  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    final res = await http
        .post(
          Uri.parse('$baseUrl/v1/sdk/auth/login'),
          headers: _headers,
          body: jsonEncode({'email': email, 'password': password}),
        )
        .timeout(const Duration(seconds: 10));
    return _parseSession(res);
  }

  /// Refresh exchanges a refresh token for a new access token + rotated
  /// refresh token. 401 in this context means the refresh token was rejected
  /// (revoked, expired, or otherwise invalid) — distinct from login's 401
  /// which means bad credentials.
  Future<AuthSession> refresh(String refreshToken) async {
    final res = await http
        .post(
          Uri.parse('$baseUrl/v1/sdk/auth/refresh'),
          headers: _headers,
          body: jsonEncode({'refresh_token': refreshToken}),
        )
        .timeout(const Duration(seconds: 10));
    return _parseSession(res, isRefresh: true);
  }

  Future<void> logout(String accessToken) async {
    await http
        .post(
          Uri.parse('$baseUrl/v1/sdk/auth/logout'),
          headers: _authHeaders(accessToken),
        )
        .timeout(const Duration(seconds: 10));
  }

  Future<KoolbaseUser> getMe(String accessToken) async {
    final res = await http
        .get(
          Uri.parse('$baseUrl/v1/sdk/auth/me'),
          headers: _authHeaders(accessToken),
        )
        .timeout(const Duration(seconds: 10));
    _checkError(res);
    return KoolbaseUser.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<KoolbaseUser> updateProfile({
    required String accessToken,
    String? fullName,
    String? avatarUrl,
  }) async {
    final res = await http
        .patch(
          Uri.parse('$baseUrl/v1/sdk/auth/me'),
          headers: _authHeaders(accessToken),
          body: jsonEncode({
            if (fullName != null) 'full_name': fullName,
            if (avatarUrl != null) 'avatar_url': avatarUrl,
          }),
        )
        .timeout(const Duration(seconds: 10));
    _checkError(res);
    return KoolbaseUser.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<void> forgotPassword(String email) async {
    final res = await http
        .post(
          Uri.parse('$baseUrl/v1/sdk/auth/password-reset'),
          headers: _headers,
          body: jsonEncode({'email': email}),
        )
        .timeout(const Duration(seconds: 10));
    _checkError(res);
  }

  Future<void> resetPassword({
    required String token,
    required String password,
  }) async {
    final res = await http
        .post(
          Uri.parse('$baseUrl/v1/sdk/auth/password-reset/confirm'),
          headers: _headers,
          body: jsonEncode({'token': token, 'password': password}),
        )
        .timeout(const Duration(seconds: 10));
    _checkError(res);
  }

  Future<void> verifyEmail(String token) async {
    final res = await http
        .post(
          Uri.parse('$baseUrl/v1/sdk/auth/verify-email'),
          headers: _headers,
          body: jsonEncode({'token': token}),
        )
        .timeout(const Duration(seconds: 10));
    _checkError(res);
  }

  /// Consume an unlock token from a brute-force unlock email. Returns
  /// nothing on success (204). Throws [UnlockTokenInvalidException] if
  /// the token is invalid, expired, or already consumed.
  Future<void> unlock(String token) async {
    final res = await http
        .post(
          Uri.parse('$baseUrl/v1/sdk/auth/unlock'),
          headers: _headers,
          body: jsonEncode({'token': token}),
        )
        .timeout(const Duration(seconds: 10));
    _checkError(res);
  }

  /// Parse a session-returning response (login, signUp, refresh).
  ///
  /// [isRefresh] controls how 401 is interpreted:
  /// - false (default, login/signUp): 401 = invalid credentials
  /// - true (refresh): 401 = session expired (refresh token was rejected)
  AuthSession _parseSession(http.Response res, {bool isRefresh = false}) {
    if (res.statusCode == 409) throw const EmailAlreadyInUseException();
    if (res.statusCode == 401) {
      throw isRefresh
          ? const SessionExpiredException()
          : const InvalidCredentialsException();
    }
    if (res.statusCode == 403) throw const UserDisabledException();
    _checkError(res);
    return AuthSession.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Map a non-2xx response to a typed exception.
  ///
  /// Status-based routing:
  /// - 429 + "account temporarily locked" → [AccountLockedException]
  /// - 429 (other) → [RateLimitException]
  ///
  /// Message-based routing (for status codes too generic on their own):
  /// - "invalid or expired unlock token" → [UnlockTokenInvalidException]
  /// - "session revoked" / "token revoked" → [TokenRevokedException]
  ///   (forward-compatible; server may not yet emit these markers)
  ///
  /// Fallback: generic [KoolbaseAuthException] with the server-provided
  /// message or a default.
  void _checkError(http.Response res) {
    if (res.statusCode >= 200 && res.statusCode < 300) return;
    Map<String, dynamic> body = {};
    try {
      body = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {}
    final msg = (body['error'] as String?) ?? '';

    // 429 — account lock vs general rate limit
    if (res.statusCode == 429) {
      if (msg.contains('account temporarily locked')) {
        throw const AccountLockedException();
      }
      throw RateLimitException(msg.isEmpty ? null : msg);
    }

    // 400 — unlock token invalid (specific message)
    if (msg.contains('invalid or expired unlock token')) {
      throw const UnlockTokenInvalidException();
    }

    // 401 — token revoked (forward-compatible; server messages may evolve)
    if (msg.contains('session revoked') ||
        msg.contains('token revoked') ||
        msg.contains('session has been revoked')) {
      throw const TokenRevokedException();
    }

    throw KoolbaseAuthException(
      msg.isEmpty ? 'An unexpected error occurred' : msg,
    );
  }

  Future<Map<String, dynamic>> oauthLogin({
    required String provider,
    required String token,
    String email = '',
    String name = '',
    String avatarUrl = '',
  }) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/v1/auth/oauth'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'provider': provider,
            'token': token,
            'email': email,
            'name': name,
            'avatar_url': avatarUrl,
          }),
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('OAuth login failed: \${response.statusCode}');
  }

  Future<OtpSendResult> sendOtp({required String phoneNumber}) async {
    final res = await http
        .post(
          Uri.parse('$baseUrl/v1/sdk/auth/phone/send-otp'),
          headers: _headers,
          body: jsonEncode({'phone_number': phoneNumber}),
        )
        .timeout(const Duration(seconds: 10));
    _checkPhoneError(res);
    return OtpSendResult.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<PhoneVerifyResult> verifyOtp({
    required String phoneNumber,
    required String code,
  }) async {
    final res = await http
        .post(
          Uri.parse('$baseUrl/v1/sdk/auth/phone/verify-otp'),
          headers: _headers,
          body: jsonEncode({'phone_number': phoneNumber, 'code': code}),
        )
        .timeout(const Duration(seconds: 10));
    _checkPhoneError(res);
    return PhoneVerifyResult.fromJson(
        jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<void> linkPhone({
    required String accessToken,
    required String phoneNumber,
    required String code,
  }) async {
    final res = await http
        .post(
          Uri.parse('$baseUrl/v1/sdk/auth/phone/link'),
          headers: _authHeaders(accessToken),
          body: jsonEncode({'phone_number': phoneNumber, 'code': code}),
        )
        .timeout(const Duration(seconds: 10));
    _checkPhoneError(res);
  }

  void _checkPhoneError(http.Response res) {
    if (res.statusCode >= 200 && res.statusCode < 300) return;
    Map<String, dynamic> body = {};
    try {
      body = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {}
    final msg = (body['error'] as String?) ?? '';

    if (res.statusCode == 429) throw const OtpRateLimitException();
    if (res.statusCode == 409) throw const PhoneAlreadyLinkedException();

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
        msg.isEmpty ? 'An unexpected error occurred' : msg);
  }
}
