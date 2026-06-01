# 6.1.0

* feat(storage): three new typed exceptions for bucket-limit failures
  introduced server-side in Storage #2. All extend
  `KoolbaseStorageException` so existing catch-all blocks continue to
  work; catch the specifics to branch on the kind of limit hit.
  - `KoolbaseStorageQuotaExceededException` — 409 + `QUOTA_EXCEEDED`,
    thrown when an upload would push the bucket past its
    `max_size_bytes` cap.
  - `KoolbaseStorageFileTooLargeException` — 413 + `FILE_TOO_LARGE`,
    thrown when a single file exceeds the bucket's
    `max_file_size_bytes` cap.
  - `KoolbaseStorageMimeTypeException` — 415 + `MIME_NOT_ALLOWED`,
    thrown when an upload's content-type isn't in the bucket's
    `allowed_mime_types` allowlist (supports `type/*` wildcards).
* Mapper (`koolbaseStorageError` / `koolbaseStorageErrorFromResponse`)
  recognizes the new codes and the new HTTP statuses (413, 415).
* Backwards-compatible: existing callers using
  `on KoolbaseStorageException` keep working; the new types let callers
  surface clearer messages or prompt the user to delete files / pick a
  smaller file / pick a different file type.

## 6.0.0

### Breaking — realtime

- `Koolbase.realtime.on` / `onRecordCreated` / `onRecordUpdated` / `onRecordDeleted` no longer take a `projectId` — the project is derived from your session token, matching the React Native SDK. Migrate `on(projectId: ..., collection: 'x')` to `on(collection: 'x')`.

### Breaking — storage

- `KoolbaseStorageClient.upload()` is now **safe-by-default**. Uploads to a
  path where an object already exists are **rejected** with a new
  `KoolbaseStorageConflictException` instead of silently overwriting the
  existing object. Pass `overwrite: true` to opt into the previous
  replacing behavior.
- Storage operations now throw typed `KoolbaseStorageException` subtypes
  instead of generic `Exception` — catching `Exception` still works but
  catching the specific subtypes (or the `KoolbaseStorageException` base)
  gives you cleaner branching.

### Added

- `KoolbaseStorageException` — base class for all storage failures, mirroring
  the `KoolbaseDataException` pattern from the database layer.
- `KoolbaseStorageConflictException` (`code: PATH_CONFLICT`) — thrown when an
  upload would replace an existing object and `overwrite: false`. Exposes the
  colliding `path` from the server response.
- `KoolbaseStorageNotFoundException`, `KoolbaseStorageValidationException`,
  `KoolbaseStoragePermissionException` — typed exceptions for the other
  storage error classes (404, 400, 403). Storage operations now throw these
  instead of a generic `Exception`.
- `koolbaseStorageError(statusCode, body)` and
  `koolbaseStorageErrorFromResponse(res)` — code-first response-to-exception
  mappers, matching the database layer's pattern.

### Migration — storage uploads

**If your app uploads to deterministic paths** (e.g. `avatars/{user_id}.png`)
**and relied on the upload silently replacing the previous file:**

```dart
// Before — silent overwrite
await Koolbase.storage.upload(
  bucket: 'avatars',
  path: 'me.png',
  file: file,
);

// After — explicit overwrite
await Koolbase.storage.upload(
  bucket: 'avatars',
  path: 'me.png',
  file: file,
  overwrite: true,
);
```

**If you want a conflict prompt** (recommended for user-supplied filenames):

```dart
try {
  await Koolbase.storage.upload(
    bucket: 'documents',
    path: filename,
    file: file,
  );
} on KoolbaseStorageConflictException catch (e) {
  final ok = await showConfirm('${e.path} already exists. Overwrite?');
  if (ok) {
    await Koolbase.storage.upload(
      bucket: 'documents',
      path: filename,
      file: file,
      overwrite: true,
    );
  }
}
```

**If you catch generic exceptions from storage operations**, consider
catching `KoolbaseStorageException` (or specific subtypes) for cleaner
error handling:

```dart
try {
  await Koolbase.storage.upload(...);
} on KoolbaseStorageConflictException {
  // Path already exists — prompt user
} on KoolbaseStorageNotFoundException {
  // Bucket missing or deleted
} on KoolbaseStoragePermissionException {
  // Caller not authorized
} on KoolbaseStorageException catch (e) {
  // Any other storage error
  showError(e.message);
}
```

### Server requirements

- Requires a Koolbase server build with `PATH_CONFLICT` 409 support
  (shipped alongside this release).

# 5.1.0

### Fixed

- Realtime now connects. The client was protocol-correct but was never handed an access token (the push-based `setToken` was never wired), so it never connected. Switched to the same token-provider model as the other clients; it now authenticates with the user session and streams `created`/`updated`/`deleted` events.

### Removed

- `KoolbaseRealtimeClient.setToken` — dead push-model plumbing that was never wired. The token now flows from the SDK automatically.

# 5.0.0

### BREAKING — security

- Data-plane requests (database, storage, functions, offline sync)
  authenticate with the signed-in user's access token (Authorization: Bearer)
  instead of the x-user-id header. The header is no longer sent or trusted.
  Requires the matching Koolbase server build.
- KoolbaseStorageClient.upload() no longer accepts a `userId` parameter —
  identity comes from the active session automatically.
- End-user identity now flows automatically from Koolbase.auth; manual
  Koolbase.db.setUserId(...) is no longer needed for auth (it remains only for
  tagging offline-cached records).

### Added

- KoolbaseAuthClient.validAccessToken() — returns a currently-valid token,
  refreshing (single-flight) near expiry; data-plane clients pull from it per
  request so identity follows the live session.

## 4.1.0

- **Code Push — mandatory bundles.** The SDK now honors a bundle's `mandatory` flag (set from the dashboard or via `PATCH /mandatory`). When a mandatory bundle is staged for the next launch:
  - `Koolbase.codePush.hasMandatoryUpdate` returns `true` — poll it on resume to gate your UI.
  - The optional `onMandatoryUpdate` callback on `KoolbaseConfig` fires immediately with `MandatoryUpdateInfo(version, bundleId)`, so you can prompt the user to restart and apply the required update.
- No breaking changes.

## 4.0.0

### Breaking

- Removed the `Koolbase.ota` client (`KoolbaseOtaClient`) and its models
  (`OtaCheckResult`, `OtaProgress`, `OtaDownloadState`). Use `Koolbase.codePush`
  for config/flag/directive overrides, or Koolbase Storage for shipping and
  reading raw files. This consolidates onto a single bundle client — matching the
  React Native SDK and the server, which already use code push exclusively.
- Dropped the `sign_in_with_apple` dependency — it was only used by the removed
  `KoolbaseAppleAuth`. The current `signInWithApple({identityToken})` is
  library-agnostic, so the SDK no longer pulls it. If your app uses Apple
  Sign-In, declare `sign_in_with_apple` in your own `pubspec.yaml`.

# 3.3.0

- Auth exceptions are now selected from the server's stable error `code`
  (with status/message fallback for older servers), retiring brittle message
  string-matching.
- New typed data-layer exceptions — `KoolbaseNotFoundException`,
  `KoolbaseValidationException`, `KoolbasePermissionException`,
  `KoolbaseRateLimitException` — plus a shared `KoolbaseDataException` base.
  Database operations now throw these (code-first) instead of a generic
  `Exception`.
- `KoolbaseConflictException` now exposes the collided `field` when the
  server reports it.
- Fix: `insert` no longer queues a server-rejected write (e.g. a unique
  conflict) as an offline write — 4xx rejections surface immediately; only
  genuine network failures are queued.

## 3.2.0

- Added `KoolbaseConflictException`, thrown by `insert`, `update`, and `upsert` when a write violates a collection's unique constraint (HTTP 409). Catch it to handle duplicates.

## 3.1.1

- Docs: document `upsert` and `deleteWhere` in the README (no code changes).

## 3.1.0

- Added `Koolbase.db.upsert(collection:, match:, data:)` — insert-or-update by a match filter; returns `KoolbaseUpsertResult { record, created }`. Online-only.
- Added `Koolbase.db.deleteWhere(collection:, filters:)` — bulk delete by filter; returns the number of records deleted. Online-only.

## 3.0.0

### Breaking

- **Flat record shape.** `KoolbaseRecord` no longer wraps your fields under a
  `data` envelope. Your fields are now top-level, with system metadata in a
  reserved `$`-prefixed namespace: `$id`, `$createdAt`, `$updatedAt`,
  `$collection`, and `$createdBy` (when set).
- Removed `KoolbaseRecord.projectId` and `KoolbaseRecord.collectionId` —
  internal identifiers are no longer exposed on records.
- Requires a Koolbase server on the flat record contract (shipped alongside
  this release). Older servers return the legacy envelope and will not parse.

### Added

- `record['field']` — direct field access, shorthand for `record.data['field']`.
- `record.collection` — the record's collection name.

### Changed

- Populated/related records (via `populate()`) and realtime payloads now use
  the same flat `$`-shape as direct reads.
- Offline cache (Drift) bumped to schema v2: stale read caches are cleared on
  upgrade so they refetch in the new shape; pending offline writes are preserved.

### Migration

- Remove any `record.projectId` / `record.collectionId` usage — those fields
  are gone.
- `record.data['field']` still works; `record['field']` is the new shorthand.

## 2.11.0

### Added

- **Sign in with Google** — production-ready end-user OAuth via
  `Koolbase.auth.signInWithGoogle(idToken: ..., nonce: ...)`. Routes to
  the server endpoint at `/v1/sdk/auth/oauth/google` with RS256-only
  JWKS verification against Google's certs endpoint, multi-audience
  support (iOS / Android / web client IDs configured per environment),
  15-minute replay defense, and optional nonce check.
- Three new typed exceptions in `auth_exceptions.dart`:
  `GoogleSignInNotConfiguredException`, `InvalidGoogleTokenException`,
  `GoogleEmailRequiredException`. Reuses existing `OAuthEmailConflictException`
  and `UserDisabledException`.

#### Example with the `google_sign_in` package

```dart
import 'package:google_sign_in/google_sign_in.dart';

final googleUser = await GoogleSignIn().signIn();
final googleAuth = await googleUser?.authentication;

final user = await Koolbase.auth.signInWithGoogle(
  idToken: googleAuth!.idToken!,
);
```

### Auto-link policy

Same as Apple Sign-In (v2.10.0). A new Google identity attaches to an
existing user only when BOTH the Google email AND the existing user's
email are verified, AND emails match (case-insensitive). Otherwise
sign-in either creates a new user (no email collision) or surfaces
`OAuthEmailConflictException`.

### Configuration required

Before users can sign in with Google, configure the provider for your
environment. Run this against your Koolbase project's `project_oauth_configs`
(dashboard UI for OAuth config lands in a later release):

```sql
UPDATE project_oauth_configs
   SET google_client_ids = ARRAY[
         '<your-ios-client-id>.apps.googleusercontent.com',
         '<your-android-client-id>.apps.googleusercontent.com',
         '<your-web-client-id>.apps.googleusercontent.com'
       ],
       enabled = true
 WHERE environment_id = '<your-env-id>'
   AND provider = 'google';
```

Get the client IDs from Google Cloud Console under Credentials → OAuth 2.0
Client IDs. You'll need one per platform (iOS, Android, web).

### Coming next

- **React Native SDK v1.11.0** — same surface
- **Dashboard UI** for OAuth config — replaces the SQL workflow

### Documentation

- README rewritten to accurately reflect the v2.10.0 SDK surface. No SDK
  code changes; this release exists to refresh the README rendered on the
  pub.dev package page.
- Removed fictional `Koolbase.auth.signInWithGoogle` reference. Google
  Sign-In is planned for v2.11.0 — noted explicitly in the OAuth section.
- Replaced the deprecated `KoolbaseAppleAuth.signIn()` example with the
  new `Koolbase.auth.signInWithApple(identityToken: ..., nonce: ..., fullName: ...)`
  v2.10.0 API using the `sign_in_with_apple` package.
- Added `Koolbase.auth.authStateChanges.listen()` example.
- Replaced the Firebase/Supabase comparison table with a Koolbase-only
  feature inventory.
- Bumped install snippet from `^2.8.0` to `^2.10.0`.

# 2.10.0

## ✨ New features

**Sign in with Apple — production-ready end-user OAuth.**

After being deprecated in v2.5.0 through v2.9.x (the old implementation
routed to the dashboard OAuth endpoint at `/v1/auth/oauth` and never
created project-scoped end-user sessions), Apple Sign-In is now properly
supported via a dedicated server endpoint at
`/v1/sdk/auth/oauth/apple`.

```dart
// Get the Apple credential using any native Apple Sign-In library
// (sign_in_with_apple, etc.) — the SDK is library-agnostic.
final credential = await SignInWithApple.getAppleIDCredential(
  scopes: [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName],
);

// Pass the credential to Koolbase.
final user = await koolbase.auth.signInWithApple(
  identityToken: credential.identityToken!,
  nonce: credential.nonce,  // optional but recommended (replay defense)
  fullName: credential.givenName != null
      ? AppleFullName(
          givenName: credential.givenName,
          familyName: credential.familyName,
        )
      : null,
);
```

**Server-side verification** runs against the project's configured Bundle
ID via Apple's JWKS — RS256-only, audience-bound to your project's iOS
app, with replay defense (iat max-age of 15min) and optional nonce check.

**Auto-link policy:** A new Apple identity attaches to an existing user
only when BOTH the provider email AND the existing user's email are
verified, AND emails match (case-insensitive). Otherwise sign-in either
creates a new user (no email collision) or surfaces
`OAuthEmailConflictException` (collision but auto-link rule blocked — user
can sign in with existing method and link from settings).

**Four new typed exceptions** for granular error handling:

| Exception | When |
|---|---|
| `AppleSignInNotConfiguredException` | Apple not enabled for this environment in dashboard OAuth config |
| `InvalidAppleTokenException` | Token signature, audience, expiry, replay, or nonce check failed |
| `AppleEmailRequiredException` | Apple didn't return email AND no existing identity. Recovery: revoke this app's Apple ID access in iOS Settings → Apple ID → Sign-In & Security → Apps Using Apple ID |
| `OAuthEmailConflictException` | Email matches existing user but auto-link rule blocked |

### Configuration required

Before users can sign in with Apple, configure the provider for your
environment via direct DB insert against `project_oauth_configs` (the
dashboard UI is on its way — landing in v2.10.1 or v2.11.0):

```sql
INSERT INTO project_oauth_configs (environment_id, provider, bundle_id, enabled)
VALUES ('<your-environment-id>', 'apple', 'com.yourapp.bundle', true);
```

You'll need your iOS app's Bundle ID — it's the audience claim in identity
tokens from native Sign in with Apple, and must match exactly.

### Still deprecated — `KoolbaseAppleAuth.signIn` and `oauthLogin`

These remain deprecated and continue to throw `UnimplementedError`. The
v2.10.0 surface is `koolbase.auth.signInWithApple(...)` on the auth client
— same place as all other auth methods. The class-level
`KoolbaseAppleAuth.signIn(callback)` API from v1.5.0 was a wrong-shape
design (callback-based, locked consumers to a specific native library) and
won't be revived.

### Coming next

- **Dashboard UI** for OAuth config (v2.10.1) — minimal Bundle-ID input,
  enable/disable toggle, validation. Removes the SQL-direct workflow.
- **Google Sign-In** (v2.11.0) — same endpoint pattern at
  `/v1/sdk/auth/oauth/google`
- **GitHub OAuth** (v2.12.0) — code-exchange flow

### 2.9.1

Polish release: configurable HTTP timeout, injectable HTTP client, and a `logout()` that lets you know whether the server-side call succeeded. Also fixes a wiring oversight from v2.9.0: the device metadata headers introduced in that release were not actually being attached to requests — the SDK had the code but no construction site. v2.9.1 wires it through properly.

### Fixed

- **Device metadata headers (from v2.9.0) are now actually attached to authentication requests.** v2.9.0 introduced the `DeviceMetadata` class and the supporting `koolbaseSdkVersion` constant, and `AuthApi` was updated to accept a `DeviceMetadata` instance — but the `Koolbase.initialize()` flow was not updated to construct one and pass it in. As a result, no `x-koolbase-*` headers or structured `User-Agent` were sent on the wire from v2.9.0. v2.9.1 restores the intended behavior. Upgrade from v2.9.0 to get the metadata features described in the v2.9.0 release notes.

### Added (2.9.1)

- **`KoolbaseConfig.authTimeout`** (`Duration`, default 10s): timeout applied to every authentication HTTP request. Tune up for high-latency networks; tune down for fast-fail UX on first-byte latency.
- **`KoolbaseConfig.httpClient`** (`http.Client?`, default null): inject your own HTTP client for logging interception, retry middleware, proxy configuration, or sharing connection pools. The SDK will NOT close a caller-supplied client; the caller owns its lifecycle. Currently scoped to auth requests; other SDK modules (storage, database, realtime, etc.) will adopt this in a future release.
- **`AuthApi.dispose()`** closes the underlying HTTP client iff the SDK owns it. Called automatically by `KoolbaseAuthClient.dispose()` for clean shutdown.

### Changed

- **`KoolbaseAuthClient.logout()`** now returns `Future<bool>` instead of `Future<void>`. The local session is **always cleared** regardless of whether the server-side logout succeeded (intentional best-effort behavior to avoid leaving stale tokens client-side after a network error). The return value indicates whether the server-side call succeeded — `true` if it did (or if there was no access token to invalidate), `false` if the server call failed. Source-compatible for callers ignoring the return value.
- **`KoolbaseAuthClient.dispose()`** now also cascades to `AuthApi.dispose()` so the HTTP client gets closed on shutdown.

### Usage

```dart
// Default: 10s auth timeout, SDK-owned http.Client
await Koolbase.initialize(KoolbaseConfig(
  publicKey: 'pk_live_...',
  baseUrl: 'https://api.koolbase.com',
));

// Custom timeout for slow networks
await Koolbase.initialize(KoolbaseConfig(
  publicKey: 'pk_live_...',
  baseUrl: 'https://api.koolbase.com',
  authTimeout: const Duration(seconds: 30),
));

// Inject your own HTTP client (logging, retries, proxy, etc.)
final myClient = MyLoggingClient();
await Koolbase.initialize(KoolbaseConfig(
  publicKey: 'pk_live_...',
  baseUrl: 'https://api.koolbase.com',
  httpClient: myClient,
));

// Check whether server logout succeeded
final ok = await Koolbase.auth.logout();
if (!ok) {
  // Local session was cleared; server may not be fully aware
}
```

# 2.9.0

A comprehensive overhaul of the authentication module. This release closes seven independent gaps identified by a focused security and reliability audit, adds proper device-attributed session tracking, fixes a refresh-token race that could invalidate concurrent in-flight requests, and honestly deprecates OAuth methods that were never fully wired up on the server side.

## Highlights

- **Pluggable storage**: a new `KoolbaseAuthStorage` abstract interface lets you plug in custom storage backends (compliant encryption layers, web targets, in-memory test mocks). The default `SecureAuthStorage` now persists the full session — access token, refresh token, expiry, and user — not just the refresh token.
- **Offline-aware session restoration**: `restoreSession()` returns a `RestoreResult` enum (`noSession` / `restored` / `expired` / `offline`) so your app can render the correct UI immediately. App launches no longer require a network round-trip to show authenticated state.
- **Single-flight refresh**: concurrent API calls that find an expired token now share one underlying refresh call, fixing a race where parallel refreshes could invalidate each other's tokens.
- **Expanded typed exceptions**: `AccountLockedException`, `RateLimitException`, `UnlockTokenInvalidException`, `TokenRevokedException` — covering brute-force lockouts (HTTP 429), general rate limits, the unlock-email flow, and centrally revoked sessions.
- **Device metadata on every auth request**: a structured `User-Agent` plus `x-koolbase-*` headers (SDK version, platform, app version, stable per-install device label) so the server's sessions infrastructure can attribute activity for the sessions UI, future security alerts, and analytics.

## Added

- `KoolbaseAuthStorage` abstract interface — implement your own to plug in custom auth storage backends.
- `SecureAuthStorage` default implementation backed by `flutter_secure_storage` with explicit iOS Keychain accessibility (`first_unlock_this_device`) and Android EncryptedSharedPreferences.
- `PersistedSession` value class for fully-typed session persistence.
- `RestoreResult` enum returned by `KoolbaseAuthClient.restoreSession()`.
- `KoolbaseAuthClient.unlock(String token)` — consume an unlock token from a brute-force unlock email.
- `DeviceMetadata` class built automatically at `Koolbase.initialize()`; persists a stable per-install device label.
- `koolbaseSdkVersion` constant exported for consumers who need to assert SDK version at runtime.
- New typed exceptions:
  - `AccountLockedException` — brute-force lockout (HTTP 429 + lockout marker). Includes a forward-compatible nullable `lockedUntil` field.
  - `RateLimitException` — general HTTP 429 without the lockout marker.
  - `UnlockTokenInvalidException` — invalid or expired unlock email token (one-shot).
  - `TokenRevokedException` — session has been revoked centrally (distinct from `SessionExpiredException`).

### Changed

- **`KoolbaseAuthClient.restoreSession()`** signature changed from `Future<void>` to `Future<RestoreResult>`. Source-compatible for callers ignoring the return value; callers wanting offline-aware UI should branch on the enum.
- **`AuthApi`** constructor is no longer `const` — it now accepts optional `DeviceMetadata`. Source-compatible for code that doesn't use the `const` keyword (the default in most apps).
- **`KoolbaseAuthClient.refreshSession()`** and the internal `_ensureValidToken()` go through a single-flight refresh path; concurrent callers share one underlying refresh.
- Every authenticated request now carries `User-Agent`, `x-koolbase-sdk`, `x-koolbase-sdk-version`, `x-koolbase-platform`, `x-koolbase-platform-version`, `x-koolbase-app-version`, and `x-koolbase-device-label` headers.

### Fixed

- **Refresh-token race**: parallel API calls hitting an expired token no longer trigger competing refresh calls. Server-side refresh-token rotation no longer invalidates peer in-flight tokens.
- **Offline launch**: `restoreSession()` previously cleared all auth state on any error including network failures, silently logging users out. It now distinguishes auth rejection from network errors and keeps optimistic state in the offline case.
- **401-on-refresh**: refresh failures returning HTTP 401 previously surfaced as `InvalidCredentialsException` ("wrong password"). They now correctly throw `SessionExpiredException`.
- **Profile updates not persisting**: `updateProfile()`, `getCurrentUser()`, and `linkPhone()` updated in-memory state but didn't re-persist the user. Changes were lost on app restart. Now persisted via a new internal helper.
- **`linkPhone` listener not firing**: profile updates after phone linking now correctly emit on `authStateChanges`.
- **`forgotPassword` silently swallowed errors**: now properly checks the response status and surfaces errors as typed exceptions.

### Deprecated

- **OAuth methods**: `KoolbaseAuthClient.oauthLogin()`, `AuthApi.oauthLogin()`, and `KoolbaseAppleAuth.signIn()`. The previous implementations targeted `/v1/auth/oauth` — the dashboard's developer OAuth handler — which never created project-scoped sessions for end-users. All three methods now throw `UnimplementedError`. Proper end-user OAuth endpoints (`/v1/sdk/auth/oauth/apple`, `/google`, `/github`) are tracked for v2.10.x. Use `KoolbaseAuthClient.login()` with email/password until then.
- **`AuthStorage`** class: replaced by `SecureAuthStorage`. The old class remains as a `@Deprecated` subclass for source compatibility and will be removed in v3.0.0.

### Migration

**If you construct `AuthStorage` directly:**

```dart
// Before
final client = KoolbaseAuthClient(api: api, storage: AuthStorage());

// After (recommended — uses the default)
final client = KoolbaseAuthClient(api: api);

// Or explicit
final client = KoolbaseAuthClient(api: api, storage: SecureAuthStorage());
```

**If you handle `restoreSession()`:**

```dart
// Before
await Koolbase.auth.restoreSession();
if (Koolbase.auth.isAuthenticated) {
  // Show app
} else {
  // Show login
}

// After (recommended — branch on outcome)
final result = await Koolbase.auth.restoreSession();
switch (result) {
  case RestoreResult.noSession:
    // Show login
  case RestoreResult.restored:
    // Show app
  case RestoreResult.expired:
    // Show login with "session expired" message
  case RestoreResult.offline:
    // Show app optimistically; retry refresh when network returns
}
```

**If you call `oauthLogin()` or `KoolbaseAppleAuth.signIn()`:**

These now throw `UnimplementedError`. End-user OAuth is blocked on a server-side endpoint that ships in v2.10.x. Use email/password authentication via `KoolbaseAuthClient.login()` for now.

**If you catch generic `KoolbaseAuthException` for lockout or rate-limit cases:**

Consider catching the more specific types now:

```dart
try {
  await Koolbase.auth.login(email: email, password: password);
} on AccountLockedException {
  // Show "account temporarily locked" UI; offer "unlock via email" path
} on RateLimitException {
  // Show "too many attempts, please wait" UI
} on InvalidCredentialsException {
  // Show "wrong email or password"
}
```

### Internal

- `KoolbaseAuthClient` no longer imports `package:flutter/material.dart` (was only needed for `debugPrint` in OAuth error paths, which are now deprecated stubs).
- New `lib/src/auth/device_metadata.dart` module.

# 2.8.0

- **Functions:** Authenticated invocations now forward the signed-in user's session automatically.
  - When a user is signed in via `Koolbase.auth`, calls to `Koolbase.functions.invoke()` include their access token in the request.
  - Functions receive caller identity via `ctx.auth` — a map with `user_id` (string or null) and `is_authenticated` (bool).
  - Unauthenticated invokes continue to work; Functions decide whether they require auth and respond with `AUTH_REQUIRED` if needed.
  - Token refresh is handled transparently — the next invoke after a refresh uses the fresh token without any client-side wiring.
- Backwards compatible: no breaking changes. Existing code paths continue to work.

## 2.7.0

### Phone + OTP authentication

Sign users in with their phone number — for emerging markets and apps where email isn't the primary identifier.

New methods on `Koolbase.auth`:

- `sendOtp({required String phoneNumber})` — sends a 6-digit OTP to an E.164 phone number, returns the expiry timestamp.
- `verifyOtp({required String phoneNumber, required String code})` — verifies the code and signs the user in (creates the account if new). Returns `PhoneVerifyResult` with an `isNewUser` flag for routing first-time users to onboarding.
- `linkPhone({required String phoneNumber, required String code})` — links a phone number to an already-authenticated user.

New types: `OtpSendResult`, `PhoneVerifyResult`.

`KoolbaseUser` now exposes `phoneNumber` and `phoneVerified` fields.

New exceptions: `InvalidPhoneNumberException`, `OtpExpiredException`, `OtpInvalidException`, `OtpMaxAttemptsException`, `OtpRateLimitException`, `PhoneAlreadyLinkedException`, `SmsConfigMissingException`.

Phone numbers must be in E.164 format (e.g. `+233244000000`). Configure your SMS provider (Twilio, Africa's Talking, or Hubtel) in the Koolbase dashboard before using.

## 2.6.4

- README update — full feature documentation

## 2.6.3

- Updated drift to ^2.31.0
- Updated drift_flutter to ^0.2.8

## 2.6.2

- Updated dependencies to latest versions
- Fixed static analysis warnings
- Removed deprecated encryptedSharedPreferences parameter

## 2.6.1

- README update — Logic Engine v2 operators

## 2.6.0

### Logic Engine v2 — Richer conditions

New operators:

- `gte` — greater than or equals
- `lte` — less than or equals
- `contains` — string or list contains value
- `starts_with` — string starts with
- `ends_with` — string ends with
- `in_list` — value is in a list
- `not_in_list` — value is not in a list
- `between` — numeric value in range [min, max]
- `is_true` — value is boolean true
- `is_false` — value is boolean false
- `not_exists` — value is null or missing

All operators work with AND/OR condition groups.

### Example

```json
{
  "op": "and",
  "conditions": [
    { "op": "gte", "left": { "from": "context.usage" }, "right": 5 },
    { "op": "in_list", "left": { "from": "context.plan" }, "right": ["free", "trial"] }
  ]
}
```

## 2.5.1

- README update — added Sign in with Apple section

## 2.5.0

### Sign in with Apple

- Added `KoolbaseAppleAuth.signIn()` — Sign in with Apple for Flutter
- Added `KoolbaseAuthClient.oauthLogin()` — unified OAuth login method
- Added `AuthApi.oauthLogin()` — server-side Apple identity token verification
- Apple identity token verified server-side using Apple's JWKS endpoint
- Supports email relay addresses from Apple private email relay

### Usage

```dart
import 'package:koolbase_flutter/koolbase_flutter.dart';

final session = await KoolbaseAppleAuth.signIn();
if (session != null) {
  print('Signed in: \${session['user']['email']}');
}
```

### Setup required

Add `sign_in_with_apple` to your pubspec.yaml and configure your App ID in the Apple Developer portal.

## 2.4.0

### Koolbase Cloud Messaging

- Added `KoolbaseMessaging` — push notification delivery via FCM
- Added `Koolbase.messaging.registerToken(token, platform)` — register FCM device token with Koolbase
- Added `Koolbase.messaging.send(to, title, body, data)` — send push notification to a specific device
- `KoolbaseConfig` extended with `messagingEnabled` parameter (default: true)
- Device ID automatically attached to token registration

### Usage

```dart
// After obtaining FCM token from firebase_messaging
final fcmToken = await FirebaseMessaging.instance.getToken();
await Koolbase.messaging.registerToken(
  token: fcmToken!,
  platform: 'android', // or 'ios'
);

// Send to a specific device
await Koolbase.messaging.send(
  to: deviceToken,
  title: 'Your order is ready',
  body: 'Pick up at counter 3',
  data: {'order_id': '123'},
);
```

### Setup required

Add your FCM server key as a project secret named `FCM_SERVER_KEY` in the Koolbase dashboard.

## 2.3.1

- Updated README — added Code Push, Analytics, Logic Engine sections, comparison table, clearer get started guide

## 2.3.0

### Koolbase Analytics

- Added `KoolbaseAnalyticsClient` — event tracking with batched flush
- Added `Koolbase.analytics` — top-level static accessor
- Added `Koolbase.analytics.track(eventName, properties)` — custom event tracking
- Added `Koolbase.analytics.screenView(screenName)` — screen view tracking
- Added `Koolbase.analytics.setUserProperty(key, value)` — user property management
- Added `Koolbase.analytics.identify(userId)` — attach authenticated user to events
- Added `Koolbase.analytics.reset()` — clear user identity on logout
- Added `KoolbaseNavigatorObserver` — auto screen tracking via Flutter navigator
- Auto events: `app_open`, `screen_view`, `session_end`
- Batch flush: every 30 seconds, on background, on close, or when 20 events queued
- Events retry on network failure — re-queued up to batch size limit
- `KoolbaseConfig` extended with `analyticsEnabled` parameter (default: true)

### Usage

```dart
// Auto screen tracking
MaterialApp(
  navigatorObservers: [
    KoolbaseNavigatorObserver(client: Koolbase.analytics),
  ],
)

// Manual tracking
Koolbase.analytics.track('purchase', properties: {
  'value': 1200,
  'currency': 'GHS',
});

// User identity
Koolbase.analytics.identify(user.id);
Koolbase.analytics.setUserProperty('plan', 'pro');

// Flush on app background
Koolbase.analytics.flush();
```

## 2.2.0

### Logic Engine v1 — Event-Driven Flows

- Added `FlowExecutor` — safe, deterministic runtime for evaluating flow node trees
- Added `FlowContext` — resolves data from context, config, and flags with dot-notation support
- Added `FlowResult` — typed result with event name, args, and error state
- Supported node types: `if`, `sequence`, `event` (terminal), `set`
- Supported operators: `eq`, `neq`, `gt`, `lt`, `and`, `or`, `exists`
- Supported data sources: `context` (app-provided), `config` (bundle), `flags` (bundle)
- `BundlePayload` extended with `flows` field — `Map<String, dynamic>` defaulting to `{}`
- `KoolbaseDynamicScreen` now auto-executes flows on rfw events — if a flow emits a new event, that event is passed to `onEvent` instead
- `Koolbase.executeFlow()` — top-level static accessor
- `KoolbaseCodePushClient.executeFlow()` — direct client access
- `KoolbaseScreenClient` abstract interface extended with `executeFlow()`

### Usage

```dart
// In your bundle's flows.json
{
  "on_checkout_tap": {
    "type": "if",
    "condition": {
      "op": "eq",
      "left": { "from": "context.plan" },
      "right": "free"
    },
    "then": { "type": "event", "name": "show_upgrade" },
    "else": { "type": "event", "name": "go_checkout" }
  }
}

// In your app — flows execute automatically from KoolbaseDynamicScreen events
// Or call directly:
final result = Koolbase.executeFlow(
  flowId: 'on_checkout_tap',
  context: { 'plan': user.plan },
);
if (result.hasEvent) {
  Navigator.pushNamed(context, result.eventName!);
}
```

## 2.1.0

### Layer 2 — Server-Driven UI via rfw

- Added `KoolbaseDynamicScreen` — drop-in widget that renders server-defined UI from the active bundle
- Added `KoolbaseCodePushScope` — InheritedWidget that wires the code push client into the widget tree
- Added `KoolbaseRfwWidget` — registration type for custom widgets in the rfw runtime
- Added default widget library: Column, Row, Stack, Container, Padding, SizedBox, Expanded, Center, Text, ElevatedButton, TextButton, OutlinedButton, Card, Divider, CircularProgressIndicator, KoolbaseText, KoolbaseButton, KoolbaseSpacer, KoolbaseBadge
- Added `ScreenResolver` — extracts and caches rfw binaries from the active bundle zip
- Bundle payload now supports `screens` field — map of screenId to .rfw filename
- `KoolbaseDynamicScreen` guarantees: never crash, never block, never surprise — all failures fall back to the local widget
- Fixed: `KoolbaseCodePushScope.of(context)` moved to `didChangeDependencies` to avoid initState context restrictions

### Usage

```dart
// Wrap your app with KoolbaseCodePushScope
KoolbaseCodePushScope(
  client: Koolbase.codePush,
  child: MyApp(),
)

// Drop KoolbaseDynamicScreen anywhere
KoolbaseDynamicScreen(
  screenId: 'onboarding',
  data: {'username': user.name},
  onEvent: (name, args) {
    if (name == 'get_started') Navigator.pushNamed(context, '/home');
  },
  fallback: const OnboardingScreen(),
)
```

## 2.0.0

### Code Push — Runtime Bundle Delivery

- Added `KoolbaseCodePushClient` — full bundle lifecycle management (check, download, verify, cache, activate)
- Added `BundleCache` — four-slot cache system (pending, ready, active, archive)
- Added `BundleVerifier` — sha256 checksum verification on every download
- Added `KoolbaseUpdater` — background check and download on cold launch
- Added `BundleLoader` — promotes ready bundles to active, handles rollback
- Added `RuntimeOverrideEngine` — merges bundle config and flags with merge precedence: app defaults → Remote Config → Runtime Bundle
- `Koolbase.configInt()`, `configString()`, `configDouble()`, `configBool()` — now transparently return bundle values when a bundle is active
- `Koolbase.isEnabled()` — now checks bundle flag overrides first
- `KoolbaseConfig` — new `codePushChannel` parameter (default: `'stable'`)
- `Koolbase.codePush` — new static accessor for the code push client

### Migration from 1.x

Add `codePushChannel` to your `KoolbaseConfig` if you want to subscribe to a specific channel:

```dart
await Koolbase.initialize(KoolbaseConfig(
  publicKey: 'pk_live_xxx',
  baseUrl: 'https://api.koolbase.com',
  codePushChannel: 'stable', // new — defaults to 'stable'
));
```

No other breaking changes.

## 1.9.0

- **Functions:** Added Dart runtime support
  - New `FunctionRuntime` enum — `FunctionRuntime.deno` and `FunctionRuntime.dart`
  - New `deploy()` method — deploy functions directly from Flutter
  - Fixed `invoke()` request body format

## 1.8.0

- **Database:** Offline-first support powered by Drift
  - Cache-first reads — instant UI, background network refresh
  - Optimistic writes — insert locally, sync when online
  - Auto-sync on network reconnect via connectivity_plus
  - Manual `Koolbase.db.syncPendingWrites()`
  - `QueryResult.isFromCache` flag
  - Write queue with max 3 retries before dropping
  - User-scoped cache — no cross-user data leakage

## 1.7.0

- **Database:** Added `.populate()` support on query builder for relational data
  - Fetch related records from other collections in a single query
  - Usage: `.populate(['author_id:users', 'category_id:categories'])`
  - Populated records are injected into `data` with the `_id` suffix removed (e.g. `author_id` → `author`)

## 1.6.0

- Full BaaS feature set — auth, database, storage, realtime, functions, feature flags, remote config, version enforcement, OTA updates

## 1.5.0

- **OTA Updates:** Added `Koolbase.ota` — over-the-air bundle updates for Flutter apps

## 1.4.0

- **Realtime:** Added `Koolbase.realtime` — WebSocket realtime SDK
  - `Koolbase.realtime.on(projectId, collection)` — stream of all events
  - `Koolbase.realtime.onRecordCreated(projectId, collection)` — stream of new records
  - `Koolbase.realtime.onRecordUpdated(projectId, collection)` — stream of updated records
  - `Koolbase.realtime.onRecordDeleted(projectId, collection)` — stream of deleted record IDs
  - `Koolbase.realtime.connectionState` — stream of connection status (true/false)
  - `Koolbase.realtime.setToken(token)` — set auth token for subscriptions
  - Auto-reconnect with 3 second backoff
  - Reference-counted subscriptions — safe for multiple listeners

## 1.3.0

- **Database:** Added `Koolbase.db` — database SDK
  - `Koolbase.db.collection('name').get()` — query records with fluent builder
  - `Koolbase.db.collection('name').where('field', isEqualTo: value).limit(20).get()`
  - `Koolbase.db.insert(collection: 'name', data: {...})` — insert records
  - `Koolbase.db.doc(id).get()` — fetch single record
  - `Koolbase.db.doc(id).update({...})` — patch record fields
  - `Koolbase.db.doc(id).delete()` — soft delete record
  - `KoolbaseRecord`, `KoolbaseCollection`, `QueryResult` models
  - Collection-level permission enforcement (public, authenticated, owner)

## 1.2.0

- **Storage:** Added `Koolbase.storage` — file storage SDK
  - `upload()` — upload files directly to Cloudflare R2 via presigned URLs
  - `getDownloadUrl()` — get signed download URLs for private files
  - `delete()` — delete files from storage
  - `KoolbaseObject`, `KoolbaseBucket`, `UploadResult` models
  - Three-step upload flow: get URL → upload → confirm

## 1.1.0

- **Auth:** Added `Koolbase.auth` — full authentication SDK
  - `signUp`, `login`, `logout`, `forgotPassword`, `resetPassword`, `verifyEmail`
  - `currentUser`, `isAuthenticated`, `authStateChanges` stream
  - Automatic session restoration on app start
  - Secure token storage via `flutter_secure_storage`
  - JWT access tokens with automatic refresh
  - `KoolbaseUser`, `AuthSession` models
  - `KoolbaseAuthException` and typed exceptions

## 1.0.0

- Initial release
- Feature flags with rollout percentages and kill switches
- Remote config (string, int, double, bool, map)
- Version enforcement with force/soft update policies
- Offline support with local cache
- Background polling
