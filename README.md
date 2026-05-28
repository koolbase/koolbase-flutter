# koolbase_flutter

[![pub.dev](https://img.shields.io/pub/v/koolbase_flutter.svg)](https://pub.dev/packages/koolbase_flutter)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://opensource.org/licenses/MIT)

Flutter SDK for [Koolbase](https://koolbase.com) — Backend as a Service built for mobile developers.

Auth, database, storage, realtime, functions, feature flags, remote config, version enforcement, code push, server-driven UI, logic engine, analytics, and cloud messaging — one SDK, one `initialize()` call.

---

## Get started in 2 minutes

1. Create a free account at [app.koolbase.com](https://app.koolbase.com)

2. Create a project and copy your public key from Environments

3. Add the SDK

```yaml
dependencies:
  koolbase_flutter: ^5.0.0
```

**4. Initialize before `runApp()`:**

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Koolbase.initialize(KoolbaseConfig(
    publicKey: 'pk_live_xxxx',
    baseUrl: 'https://api.koolbase.com',
  ));

  runApp(MyApp());
}
```

That's it. Every feature below is now available via `Koolbase.*`.

---

## Authentication

Email + password, Apple Sign-In, Google Sign-In, and phone + OTP — out of the box.

```dart
// Register
await Koolbase.auth.register(email: 'user@example.com', password: 'password');

// Login
await Koolbase.auth.login(email: 'user@example.com', password: 'password');

// Current user
final user = Koolbase.auth.currentUser;

// Logout
await Koolbase.auth.logout();

// Password reset
await Koolbase.auth.forgotPassword(email: 'user@example.com');

// Listen to auth state changes
final subscription = Koolbase.auth.authStateChanges.listen((user) {
  print(user != null ? 'signed in' : 'signed out');
});
```

### OAuth — Apple

Apple Sign-In uses the native authentication flow via the `sign_in_with_apple` package:

```dart
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

final credential = await SignInWithApple.getAppleIDCredential(
  scopes: [
    AppleIDAuthorizationScopes.email,
    AppleIDAuthorizationScopes.fullName,
  ],
);

final user = await Koolbase.auth.signInWithApple(
  identityToken: credential.identityToken!,
  nonce: credential.nonce,
  fullName: credential.givenName != null
      ? AppleFullName(
          givenName: credential.givenName,
          familyName: credential.familyName,
        )
      : null,
);
```

Configure Apple Sign-In for your environment with your iOS app's Bundle ID. Full setup guide at [docs.koolbase.com/auth/oauth](https://docs.koolbase.com/auth/oauth).

### OAuth — Google

Google Sign-In uses the native authentication flow via the `google_sign_in` package:

```dart
import 'package:google_sign_in/google_sign_in.dart';

final googleUser = await GoogleSignIn().signIn();
final googleAuth = await googleUser?.authentication;

final user = await Koolbase.auth.signInWithGoogle(
  idToken: googleAuth!.idToken!,
);
```

Configure Google Sign-In for your environment with the OAuth client IDs from Google Cloud Console (typically one each for iOS, Android, and web). Full setup guide at [docs.koolbase.com/auth/oauth](https://docs.koolbase.com/auth/oauth).

### Phone + OTP

```dart
// Send a one-time code
await Koolbase.auth.sendOtp(phoneE164: '+233200000000');

// Verify and sign in
await Koolbase.auth.verifyOtp(
  phoneE164: '+233200000000',
  code: '123456',
);

// Or link a phone to an existing account
await Koolbase.auth.linkPhone(
  phoneE164: '+233200000000',
  code: '123456',
);
```

Configure your SMS provider (Twilio, Africa's Talking, or Hubtel) in the dashboard under Phone Auth.

---

> **Auth is automatic (v5+).** Database, storage, and functions calls
> authenticate as the currently signed-in user — nothing to pass, no manual
> wiring. Log in (or restore a session) and every data-plane request carries
> that identity. `owner`/`authenticated` collections require an active session.

---

## Database

```dart
// Insert
await Koolbase.db.collection('posts').insert({
  'title': 'Hello world',
  'body': 'My first post',
});

// Query
final records = await Koolbase.db.collection('posts').get();

// Read fields off a record
final posts = await Koolbase.db.collection('posts').get();
for (final post in posts.records) {
  print(post['title']);   // field access (shorthand for post.data['title'])
  print(post.id);         // record id
}

// Filter
final filtered = await Koolbase.db
    .collection('posts')
    .where('status', 'published')
    .get();

// Relational data
final result = await Koolbase.db
    .collection('posts')
    .populate(['author_id:users'])
    .get();

// Update
await Koolbase.db.collection('posts').doc('record-id').update({'title': 'Updated'});

// Delete
await Koolbase.db.collection('posts').doc('record-id').delete();
```

### Handling unique-constraint conflicts

A write that would violate a unique constraint throws `KoolbaseConflictException`:

```dart
try {
  await Koolbase.db.collection('users').insert({'email': email});
} on KoolbaseConflictException catch (e) {
  showError('That ${e.field ?? 'value'} is already registered.');
}
```

See [Error handling](#error-handling) for the full set of typed exceptions.

### Upsert

Insert a record, or update the existing one matching a filter. The server
decides: one match updates it, no match inserts (seeded with the match
fields), more than one match errors.

```dart
final result = await Koolbase.db.upsert(
  collection: 'profiles',
  match: {'user_id': userId},
  data: {'weight_kg': 70},
);

print(result.created); // true if inserted, false if updated
print(result.record.id);
```

> Online-only: an upsert needs the server's view to decide insert vs update,
> so unlike `insert` it isn't queued offline and throws on network failure.

### Delete where

Bulk-delete every record matching a filter. Returns the number deleted.

```dart
final deleted = await Koolbase.db.deleteWhere(
  collection: 'sessions',
  filters: {'user_id': userId, 'status': 'expired'},
);
```

> A non-empty filter is required — Koolbase won't delete an entire collection.
> The collection's delete rule applies; for `owner`/`scoped` rules the delete
> is scoped to your own records. Online-only.

### Offline-first

The SDK caches all reads locally using Drift. Queries return instantly from cache and refresh in the background. Writes are queued and synced automatically when online.

```dart
final result = await Koolbase.db.collection('posts').get();
print(result.isFromCache); // true if served from local cache

await Koolbase.db.syncPendingWrites();
```

---

## Storage

```dart
// Upload
await Koolbase.storage.upload(
  bucket: 'avatars',
  path: 'user-123.jpg',
  file: file,
);

// Get download URL
final url = await Koolbase.storage.getDownloadUrl(
  bucket: 'avatars',
  path: 'user-123.jpg',
);

// Delete
await Koolbase.storage.delete(bucket: 'avatars', path: 'user-123.jpg');
```

---

## Realtime

Stream live changes on a collection. Realtime uses the signed-in user's session,
so subscribe after login. Supports collections whose read rule is `public` or
`authenticated`.

```dart
final sub = Koolbase.realtime
    .on(projectId: yourProjectId, collection: 'messages')
    .listen((event) {
  // event.type -> recordCreated | recordUpdated | recordDeleted
  print('${event.type}: ${event.record}');
});

// Or filter to one kind:
Koolbase.realtime
    .onRecordCreated(projectId: yourProjectId, collection: 'messages')
    .listen((record) => print(record));

await sub.cancel(); // stop listening
```

`yourProjectId` is your project's ID from the dashboard. The socket opens lazily,
is shared across subscriptions, and reconnects automatically.

---

## Functions

Invoke deployed serverless functions. When a user is signed in via `Koolbase.auth`, their access token is automatically forwarded — the function receives the caller's identity via `ctx.auth`. No token handling on the client side.

```dart
// Invoke a deployed function
final result = await Koolbase.functions.invoke(
  'send-welcome-email',
  body: {'userId': '123'},
);

if (result.success) print(result.data);
```

Inside the function, read the caller:

```dart
// In your deployed Dart function
Future<Map<String, dynamic>> handler(Map<String, dynamic> ctx) async {
  final userId = (ctx['auth'] as Map?)?['user_id'] as String?;
  if (userId == null) {
    return {'error': {'code': 'AUTH_REQUIRED'}, 'status': 401};
  }
  // Authenticated logic here
  return {'ok': true};
}
```

Token refresh is transparent — the SDK reads the current token fresh on every invoke. Full docs at [docs.koolbase.com/functions/authentication](https://docs.koolbase.com/functions/authentication).

---

## Feature Flags & Remote Config

```dart
// Feature flag
if (Koolbase.isEnabled('new_checkout')) {
  // show new checkout
}

// Remote config
final timeout = Koolbase.configInt('api_timeout_ms', fallback: 3000);
final url = Koolbase.configString('api_url', fallback: 'https://api.example.com');
final dark = Koolbase.configBool('force_dark_mode', fallback: false);
```

---

## Version Enforcement

```dart
final result = Koolbase.checkVersion();

switch (result.status) {
  case VersionStatus.forceUpdate:
    // Block the app — show update screen
    break;
  case VersionStatus.softUpdate:
    // Show a banner
    break;
  case VersionStatus.upToDate:
    break;
}
```

---

## Code Push

Push config overrides, feature flag overrides, and UI updates to your app without a store release.

```dart
await Koolbase.initialize(KoolbaseConfig(
  publicKey: 'pk_live_xxxx',
  baseUrl: 'https://api.koolbase.com',
  codePushChannel: 'stable',
));

// Bundle values transparently override Remote Config + Feature Flags
final timeout = Koolbase.configInt('api_timeout_ms', fallback: 3000);
final enabled = Koolbase.isEnabled('new_checkout_flow');

// Directive handlers
Koolbase.codePush.onDirective('force_logout_all', (value) {
  if (value == true) Koolbase.auth.logout();
});

### Mandatory updates

Mark a bundle **mandatory** in the dashboard (or via `PATCH /mandatory`) when every device must apply it before continuing. The SDK surfaces it two ways — a push callback and a pollable flag:

```dart
await Koolbase.initialize(KoolbaseConfig(
  publicKey: 'pk_live_xxxx',
  baseUrl: 'https://api.koolbase.com',
  // Fires the moment a mandatory bundle is staged for the next launch
  onMandatoryUpdate: (info) {
    showRestartRequiredDialog(version: info.version);
  },
));

// Or poll it — e.g. when the app resumes — before letting the user proceed
if (Koolbase.codePush.hasMandatoryUpdate) {
  showRestartRequiredDialog();
}
```

A mandatory bundle still activates on the next cold launch like any other; the callback and flag just let you prompt the user to restart now instead of waiting.

```
> Need to ship raw files and read them yourself? Use [Storage](https://docs.koolbase.com/storage/overview) instead.

---

## Server-Driven UI

Push new screen layouts OTA using Flutter's official `rfw` package. Change your app UI without shipping a new binary.

```dart
// Wrap your app
KoolbaseCodePushScope(
  client: Koolbase.codePush,
  child: MaterialApp(...),
)

// Drop a dynamic screen anywhere
KoolbaseDynamicScreen(
  screenId: 'onboarding',
  data: { 'username': user.name },
  onEvent: (name, args) {
    if (name == 'get_started') Navigator.pushNamed(context, '/home');
  },
  fallback: const OnboardingScreen(),
)
```

---

## Logic Engine

Define conditional app behavior as data in your Runtime Bundle — no code changes required.

```dart
final result = Koolbase.executeFlow(
  flowId: 'on_checkout_tap',
  context: { 'plan': user.plan, 'usage': user.usage },
);

if (result.hasEvent) {
  switch (result.eventName) {
    case 'show_upgrade': Navigator.pushNamed(context, '/upgrade');
    case 'go_checkout': Navigator.pushNamed(context, '/checkout');
  }
}
```

**v2 operators:** `eq`, `neq`, `gt`, `gte`, `lt`, `lte`, `contains`, `starts_with`, `ends_with`, `in_list`, `not_in_list`, `between`, `is_true`, `is_false`, `exists`, `not_exists`, `and`, `or`

Full docs at [docs.koolbase.com/sdk/logic-engine](https://docs.koolbase.com/sdk/logic-engine).

---

## Analytics

Track screen views, custom events, and user behaviour. View DAU, WAU, MAU, funnels, and retention in the Koolbase dashboard.

```dart
// Add to MaterialApp for automatic screen tracking
MaterialApp(
  navigatorObservers: [
    KoolbaseNavigatorObserver(client: Koolbase.analytics),
  ],
)

// Custom events
Koolbase.analytics.track('purchase', properties: {
  'value': 1200,
  'currency': 'GHS',
});

// User identity
Koolbase.analytics.identify(user.id);
Koolbase.analytics.setUserProperty('plan', 'pro');

// On logout
Koolbase.analytics.reset();
```

---

## Cloud Messaging

```dart
// Register FCM token
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

---

## Error handling

Koolbase throws typed exceptions you can catch to branch on what went wrong.
The SDK selects the exception from the server's stable error `code`, so your
handling doesn't depend on message text.

### Database errors

All data-layer failures extend `KoolbaseDataException` (which implements
`Exception`), so you can catch them broadly or by specific type:

| Exception | When |
|---|---|
| `KoolbaseConflictException` | A write violates a unique constraint (409). Exposes `.field` — the field that collided, when the server reports it. |
| `KoolbaseNotFoundException` | The record or collection doesn't exist (404). |
| `KoolbaseValidationException` | The request was rejected as invalid (400). |
| `KoolbasePermissionException` | An access rule denied the operation (403). |
| `KoolbaseRateLimitException` | The caller is being rate-limited (429). |

```dart
try {
  await Koolbase.db.insert(
    collection: 'users',
    data: {'email': email},
  );
} on KoolbaseConflictException catch (e) {
  // e.field is 'email' when the server reports which field clashed
  showError('That ${e.field ?? 'value'} is already taken.');
} on KoolbasePermissionException {
  showError('You do not have permission to do that.');
} on KoolbaseDataException catch (e) {
  // Catch-all for any other data-layer error
  showError(e.message);
}
```

> `insert` only queues offline on a genuine network failure. A server-side
> rejection (e.g. a unique conflict) surfaces immediately rather than being
> silently queued.

### Auth errors

Auth methods throw `KoolbaseAuthException` subtypes — `InvalidCredentialsException`,
`AccountLockedException`, `EmailAlreadyInUseException`, `OtpExpiredException`,
and so on — also selected from the server's error `code`.

---

## What's included

- Authentication: email + password, Apple Sign-In, Google Sign-In, phone + OTP
- Database with offline-first cache (Drift), realtime subscriptions, populate for related records
- Storage with download URLs and progress callbacks
- Realtime subscriptions over WebSocket
- Authenticated Dart functions (`ctx.auth` exposes the caller automatically)
- Feature flags and remote config
- Version enforcement (force update, soft update)
- Code push (config + flag overrides + directives, no store release)
- Server-driven UI via Flutter's `rfw` — push new screens OTA
- Logic engine (conditional flows as data, updatable OTA)
- Analytics (DAU/WAU/MAU, funnels, retention)
- Cloud Messaging (FCM token registration, targeted send)
- Flutter-first SDK with Dart-native APIs

---

## Documentation

Full documentation at [docs.koolbase.com](https://docs.koolbase.com)

## Dashboard

Manage your projects at [app.koolbase.com](https://app.koolbase.com)

## Support

- [GitHub Issues](https://github.com/kennedyowusu/koolbase_flutter/issues)
- [docs.koolbase.com](https://docs.koolbase.com)
- Email: <hello@koolbase.com>

## License

MIT
