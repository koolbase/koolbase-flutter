import 'dart:async';
import 'package:flutter/material.dart';

import 'auth_api.dart';
import 'auth_models.dart';
import 'auth_storage.dart';
import 'auth_exceptions.dart';

/// Result of [KoolbaseAuthClient.restoreSession].
///
/// Apps should branch on this to render the correct UI:
/// - [noSession] → show login screen
/// - [restored] → show authenticated UI
/// - [expired] → show login screen with "session expired" message
/// - [offline] → show authenticated UI optimistically; API calls will fail
///   until network is reachable. Apps can show a "reconnecting" indicator.
enum RestoreResult {
  /// No persisted session exists. User must log in.
  noSession,

  /// Session restored successfully (either still valid on disk, or refreshed
  /// successfully against the server).
  restored,

  /// Persisted session existed but the server rejected the refresh token.
  /// User must log in again.
  expired,

  /// Network was unreachable during refresh. The persisted session is
  /// restored optimistically — accessToken/currentUser are populated and
  /// authStateChanges fired — but the access token may be expired. API
  /// calls will fail with [SessionExpiredException] until network returns.
  offline,
}

class KoolbaseAuthClient {
  final AuthApi _api;
  final KoolbaseAuthStorage _storage;

  KoolbaseUser? _currentUser;
  String? _accessToken;
  DateTime? _accessTokenExpiresAt;

  /// Single-flight refresh slot. Multiple concurrent callers that hit
  /// [_ensureValidToken] or [refreshSession] while a refresh is in progress
  /// share the same Future and receive the same resulting session — avoiding
  /// the multi-refresh race where each parallel caller triggers its own
  /// refresh and the server rotates the refresh token from under the
  /// in-flight peers.
  Future<AuthSession>? _ongoingRefresh;

  final StreamController<KoolbaseUser?> _authStateController =
      StreamController<KoolbaseUser?>.broadcast();

  KoolbaseAuthClient({
    required AuthApi api,
    KoolbaseAuthStorage? storage,
  })  : _api = api,
        _storage = storage ?? SecureAuthStorage();

  KoolbaseUser? get currentUser => _currentUser;
  String? get accessToken => _accessToken;
  bool get isAuthenticated => _currentUser != null && _accessToken != null;
  Stream<KoolbaseUser?> get authStateChanges => _authStateController.stream;

  /// Restore a previously saved session on app launch.
  ///
  /// The flow is offline-aware and optimistic:
  /// 1. Read the persisted session from secure storage.
  /// 2. If none exists → return [RestoreResult.noSession].
  /// 3. Populate the in-memory state immediately (accessToken, currentUser,
  ///    expiry) and fire authStateChanges so apps render their authenticated
  ///    UI without waiting for the network.
  /// 4. If the access token is still valid → return [RestoreResult.restored].
  /// 5. Otherwise refresh against the server:
  ///    - Success → return [RestoreResult.restored].
  ///    - Auth rejection (token revoked/expired/invalid) → clear session,
  ///      return [RestoreResult.expired].
  ///    - Network error → keep optimistic state, return [RestoreResult.offline].
  ///      The app can retry later via [refreshSession].
  Future<RestoreResult> restoreSession() async {
    final persisted = await _storage.readSession();
    if (persisted == null) return RestoreResult.noSession;

    // Optimistic restoration — populate state from disk before any network.
    _accessToken = persisted.accessToken;
    _accessTokenExpiresAt = persisted.expiresAt;
    _currentUser = persisted.user;
    _authStateController.add(persisted.user);

    // If the access token is still valid, we're done — no network needed.
    if (!persisted.isAccessTokenExpired) {
      return RestoreResult.restored;
    }

    // Access token expired — attempt to refresh.
    try {
      final session = await _api.refresh(persisted.refreshToken);
      await _setSession(session);
      return RestoreResult.restored;
    } on KoolbaseAuthException {
      // Server rejected the refresh token — clear and require fresh login.
      await _clearSession();
      return RestoreResult.expired;
    } catch (_) {
      // Network error (timeout, DNS, connection refused). Keep the optimistic
      // state — the app UI stays authenticated, API calls will fail until
      // network returns. App can call [refreshSession] when connectivity is
      // restored.
      return RestoreResult.offline;
    }
  }

  Future<KoolbaseUser> signUp({
    required String email,
    required String password,
    String? fullName,
  }) async {
    if (password.length < 8) throw const WeakPasswordException();
    final session = await _api.signUp(
      email: email,
      password: password,
      fullName: fullName,
    );
    await _setSession(session);
    return session.user;
  }

  Future<KoolbaseUser> login({
    required String email,
    required String password,
  }) async {
    final session = await _api.login(email: email, password: password);
    await _setSession(session);
    return session.user;
  }

  Future<void> logout() async {
    try {
      if (_accessToken != null) {
        await _api.logout(_accessToken!);
      }
    } catch (_) {
      // Best effort
    } finally {
      await _clearSession();
    }
  }

  Future<KoolbaseUser> getCurrentUser() async {
    final token = await _ensureValidToken();
    final user = await _api.getMe(token);
    _currentUser = user;
    _authStateController.add(user);
    return user;
  }

  Future<KoolbaseUser> updateProfile({
    String? fullName,
    String? avatarUrl,
  }) async {
    final token = await _ensureValidToken();
    final user = await _api.updateProfile(
      accessToken: token,
      fullName: fullName,
      avatarUrl: avatarUrl,
    );
    _currentUser = user;
    _authStateController.add(user);
    return user;
  }

  Future<void> forgotPassword({required String email}) async {
    await _api.forgotPassword(email);
  }

  Future<void> resetPassword({
    required String token,
    required String password,
  }) async {
    await _api.resetPassword(token: token, password: password);
  }

  Future<void> verifyEmail(String token) async {
    await _api.verifyEmail(token);
  }

  /// Consume an unlock token from a brute-force unlock email. Apps typically
  /// extract this token from a deep link parameter when the user clicks the
  /// unlock link in their email.
  ///
  /// Throws [UnlockTokenInvalidException] if the token is invalid, expired,
  /// or already consumed (one-shot).
  Future<void> unlock(String token) async {
    await _api.unlock(token);
  }

  /// Manually refresh the access token using the persisted refresh token.
  /// Returns true on success, false if no session exists or refresh failed.
  ///
  /// Useful for recovering from [RestoreResult.offline] once network is back,
  /// or for proactively refreshing before a long-running operation.
  ///
  /// Concurrent calls are deduplicated via [_ongoingRefresh] — multiple
  /// simultaneous callers share one underlying refresh and receive the same
  /// result.
  Future<bool> refreshSession() async {
    try {
      await _refreshSingleFlight();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<String> _ensureValidToken() async {
    // Fast path: existing token is still valid (1-min buffer).
    if (_accessToken != null &&
        _accessTokenExpiresAt != null &&
        DateTime.now().isBefore(
            _accessTokenExpiresAt!.subtract(const Duration(minutes: 1)))) {
      return _accessToken!;
    }

    // Slow path: refresh (deduplicated across concurrent callers).
    try {
      final session = await _refreshSingleFlight();
      return session.accessToken;
    } catch (_) {
      throw const SessionExpiredException();
    }
  }

  /// Single-flight refresh. The first caller to find [_ongoingRefresh] null
  /// claims the slot synchronously, performs the refresh, and shares its
  /// Future with any concurrent callers via the field. All callers receive
  /// the same [AuthSession] result (or the same error).
  ///
  /// On failure, [_clearSession] is called once and the error is propagated
  /// to all waiters.
  Future<AuthSession> _refreshSingleFlight() async {
    final inFlight = _ongoingRefresh;
    if (inFlight != null) {
      // Another caller already started a refresh — share their Future.
      return inFlight;
    }

    // Claim the slot synchronously. No awaits between the null-check above
    // and this assignment, so this is atomic relative to other Dart code.
    final completer = Completer<AuthSession>();
    _ongoingRefresh = completer.future;

    try {
      final persisted = await _storage.readSession();
      if (persisted == null) {
        throw const SessionExpiredException();
      }
      final session = await _api.refresh(persisted.refreshToken);
      await _setSession(session);
      completer.complete(session);
      return session;
    } catch (e, st) {
      // Propagate the error to any concurrent waiters before clearing the
      // session, so they don't see a half-cleared state.
      if (!completer.isCompleted) completer.completeError(e, st);
      await _clearSession();
      rethrow;
    } finally {
      _ongoingRefresh = null;
    }
  }

  Future<void> _setSession(AuthSession session) async {
    _accessToken = session.accessToken;
    _accessTokenExpiresAt = session.expiresAt;
    _currentUser = session.user;
    await _storage.saveSession(PersistedSession.fromAuthSession(session));
    _authStateController.add(session.user);
  }

  Future<void> _clearSession() async {
    _accessToken = null;
    _accessTokenExpiresAt = null;
    _currentUser = null;
    await _storage.clear();
    _authStateController.add(null);
  }

  void dispose() {
    _authStateController.close();
  }

  /// Sign in with an OAuth provider (Google, GitHub, Apple).
  ///
  /// **TODO(v2.9.0 Batch C):** rewrite to return [AuthSession], route through
  /// [_setSession] for proper session persistence and listener notification,
  /// and use typed exceptions. Currently returns a raw Map and swallows
  /// errors — known broken; see audit notes.
  Future<Map<String, dynamic>?> oauthLogin({
    required String provider,
    required String token,
    String email = '',
    String name = '',
    String avatarUrl = '',
  }) async {
    try {
      final data = await _api.oauthLogin(
        provider: provider,
        token: token,
        email: email,
        name: name,
        avatarUrl: avatarUrl,
      );
      _accessToken = data['access_token'];
      _currentUser = data['user'];
      return data;
    } catch (e) {
      debugPrint('[KoolbaseAuth] oauthLogin error: $e');
      return null;
    }
  }

  /// Send a 6-digit OTP to the given E.164 phone number.
  /// Returns the OTP expiry timestamp so the app can show a resend countdown.
  Future<OtpSendResult> sendOtp({required String phoneNumber}) async {
    return _api.sendOtp(phoneNumber: phoneNumber);
  }

  /// Verify the OTP code and complete sign-in. If no user exists with this
  /// phone, one is created. The returned [PhoneVerifyResult.isNewUser] flag
  /// lets the app route first-time users to onboarding.
  Future<PhoneVerifyResult> verifyOtp({
    required String phoneNumber,
    required String code,
  }) async {
    final result = await _api.verifyOtp(phoneNumber: phoneNumber, code: code);
    await _setSession(result.session);
    return result;
  }

  /// Link a phone number to the currently authenticated user.
  /// User must already be signed in (via email/password, OAuth, or another
  /// auth method) and must have requested an OTP for this phone number first.
  ///
  /// **TODO(v2.9.0 Batch C):** fire authStateChanges after profile update.
  Future<void> linkPhone({
    required String phoneNumber,
    required String code,
  }) async {
    final token = await _ensureValidToken();
    await _api.linkPhone(
      accessToken: token,
      phoneNumber: phoneNumber,
      code: code,
    );
    final updated = await _api.getMe(token);
    _currentUser = updated;
  }
}
