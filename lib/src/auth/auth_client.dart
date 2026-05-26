import 'dart:async';

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

  /// Returns a currently-valid access token for data-plane requests, refreshing
  /// (single-flight) if the cached one is at/near expiry. Returns null when no
  /// user is authenticated or a refresh fails — callers then send the request
  /// api-key-only and the server treats it as having no end-user identity.
  ///
  /// This is the token source the db/storage/functions clients pull from on
  /// every request, so identity follows the live session automatically.
  Future<String?> validAccessToken() async {
    if (!isAuthenticated) return null;
    try {
      return await _ensureValidToken();
    } catch (_) {
      return null;
    }
  }

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

  /// Sign in with Apple using a credential obtained from a native Apple
  /// Sign-In SDK.
  ///
  /// The SDK is library-agnostic — use any native Apple Sign-In package
  /// (`sign_in_with_apple`, etc.) and pass the resulting [identityToken],
  /// optional [nonce], and optional [fullName].
  ///
  /// [fullName] is meaningful only on first sign-in — Apple omits name
  /// data on subsequent sign-ins. The server persists at link time and
  /// ignores on subsequent sign-ins.
  ///
  /// On success the session is persisted via [KoolbaseAuthStorage] and
  /// [authStateChanges] fires with the resolved user. Returns the user
  /// directly for convenience (mirrors [login] and [signUp]).
  ///
  /// Throws:
  ///   - [AppleSignInNotConfiguredException] (400) — provider not enabled
  ///     in dashboard OAuth config for this environment.
  ///   - [InvalidAppleTokenException] (401) — token signature, audience,
  ///     expiry, replay, or nonce check failed server-side.
  ///   - [UserDisabledException] (403) — account flag set to disabled.
  ///   - [AppleEmailRequiredException] (400) — Apple did not return email
  ///     for a new-account sign-in. Recovery: revoke this app's Apple ID
  ///     access in iOS Settings.
  ///   - [OAuthEmailConflictException] (409) — email matches existing
  ///     user but auto-link rule blocked. Recovery: sign in with existing
  ///     method, link from settings.
  Future<KoolbaseUser> signInWithApple({
    required String identityToken,
    String? nonce,
    AppleFullName? fullName,
  }) async {
    final session = await _api.signInWithApple(
      identityToken: identityToken,
      nonce: nonce,
      fullName: fullName,
    );
    await _setSession(session);
    return session.user;
  }

  /// Sign in with Google using an idToken obtained from a native Google
  /// Sign-In SDK.
  ///
  /// The SDK is library-agnostic — use any native Google Sign-In package
  /// (`google_sign_in`, etc.) and pass the resulting [idToken]. Google
  /// embeds the user's name and email in the idToken itself, so this
  /// method does not take a fullName parameter (unlike [signInWithApple]).
  ///
  /// On success the session is persisted via [KoolbaseAuthStorage] and
  /// [authStateChanges] fires with the resolved user.
  ///
  /// Throws:
  ///   - [GoogleSignInNotConfiguredException] (400) — provider not enabled
  ///     in OAuth config for this environment.
  ///   - [InvalidGoogleTokenException] (401) — token signature, audience,
  ///     expiry, replay, or nonce check failed server-side.
  ///   - [UserDisabledException] (403) — account flag set to disabled.
  ///   - [GoogleEmailRequiredException] (400) — Google did not return
  ///     email for a new-account sign-in. Recovery: ensure the email
  ///     scope is requested in the native flow.
  ///   - [OAuthEmailConflictException] (409) — email matches existing
  ///     user but auto-link rule blocked. Recovery: sign in with existing
  ///     method, link from settings.
  Future<KoolbaseUser> signInWithGoogle({
    required String idToken,
    String? nonce,
  }) async {
    final session = await _api.signInWithGoogle(
      idToken: idToken,
      nonce: nonce,
    );
    await _setSession(session);
    return session.user;
  }

  /// Log the user out.
  ///
  /// The local session is **always cleared**, regardless of whether the
  /// server-side logout succeeded. This is intentional: a network error
  /// during logout should not leave the user locally "logged in" with a
  /// stale token — that's a worse UX (and a security regression on
  /// shared devices) than a silent server-side stale-session.
  ///
  /// Returns `true` if the server-side logout succeeded (or if there was
  /// no access token to invalidate); `false` if the server call failed
  /// (network error, server rejected, etc). Apps that need to handle the
  /// server-side failure explicitly — for example, prompting the user to
  /// re-sign-in from a shared device once network returns — can branch on
  /// this; apps that don't care can ignore the return value.
  Future<bool> logout() async {
    bool serverLogoutSucceeded = true;
    try {
      if (_accessToken != null) {
        await _api.logout(_accessToken!);
      }
    } catch (_) {
      serverLogoutSucceeded = false;
    } finally {
      await _clearSession();
    }
    return serverLogoutSucceeded;
  }

  Future<KoolbaseUser> getCurrentUser() async {
    final token = await _ensureValidToken();
    final user = await _api.getMe(token);
    await _updateUserAndPersist(user);
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
    await _updateUserAndPersist(user);
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

  /// Update the in-memory user, fire the auth-state listener, and persist
  /// the change so it survives app restarts.
  ///
  /// Use this whenever the user object changes WITHOUT a fresh session
  /// (profile updates, phone linking, account verification toggles, etc.).
  /// For full session changes — login, refresh, OAuth — go through
  /// [_setSession] instead.
  Future<void> _updateUserAndPersist(KoolbaseUser user) async {
    _currentUser = user;
    _authStateController.add(user);

    // Update persisted session with the new user so the change survives
    // app restart. Skip silently if no session is persisted (caller is
    // unauthenticated and shouldn't be updating their user anyway).
    final persisted = await _storage.readSession();
    if (persisted != null) {
      await _storage.saveSession(PersistedSession(
        accessToken: persisted.accessToken,
        refreshToken: persisted.refreshToken,
        expiresAt: persisted.expiresAt,
        user: user,
      ));
    }
  }

  Future<void> _clearSession() async {
    _accessToken = null;
    _accessTokenExpiresAt = null;
    _currentUser = null;
    await _storage.clear();
    _authStateController.add(null);
  }

  /// Dispose of the auth client. Closes the auth state stream and cascades
  /// to [AuthApi.dispose] which closes the underlying HTTP client iff the
  /// SDK owns it (caller-supplied clients are not closed).
  ///
  /// Safe to call multiple times. After dispose, the client should not be
  /// used.
  void dispose() {
    _authStateController.close();
    _api.dispose();
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

  /// Link a phone number to the currently authenticated user. User must
  /// already be signed in (via email/password or another auth method) and
  /// must have requested an OTP for this phone number first.
  ///
  /// On success, the updated user (with phoneNumber + phoneVerified=true)
  /// is fetched, persisted, and emitted via [authStateChanges] so listening
  /// apps see the change immediately and the phone number survives restart.
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
    await _updateUserAndPersist(updated);
  }
}
