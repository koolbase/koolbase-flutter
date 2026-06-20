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
     koolbase_flutter: ^9.2.0
```

4. Initialize before `runApp()`:

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

---

### Semantic search

Find records by meaning, not just field equality. Koolbase ships three
retrieval modes from a single API — pick the one that matches your
query characteristics, or use `hybrid` as a strong production default.

Declare a vector field on the collection from the dashboard or CLI first
(picking a dimension; v1 supports 384, 768, 1024, and 1536).

#### The three search modes

```dart
// Semantic (default) — pure vector search via HNSW + cosine. Best for
// fuzzy or conceptual queries where exact words don't have to match.
final result = await Koolbase.db.collection('articles').searchSemantic(
  field: 'content_embedding',
  queryText: 'how do I move quicker?',
  limit: 10,
);

// Lexical — pure BM25 over the field's source text (Postgres
// ts_rank_cd). Best for exact terms, product codes, names, acronyms.
final result = await Koolbase.db.collection('articles').searchSemantic(
  field: 'content_embedding',
  queryText: 'CVE-2024-1234',
  mode: KoolbaseSearchMode.lexical,
  limit: 10,
);

// Hybrid — vector + lexical fused with reciprocal rank fusion (k=60).
// Generally the strongest default; both rankers vote and the fusion
// score promotes records that score well on either signal.
final result = await Koolbase.db.collection('articles').searchSemantic(
  field: 'content_embedding',
  queryText: 'production deploy pipeline',
  mode: KoolbaseSearchMode.hybrid,
  limit: 10,
);
```

#### Filtering weak matches

For `semantic` and `hybrid` modes, pass `minSimilarity` (0..100) to drop
results below a similarity threshold server-side — saves bandwidth on
weak matches:

```dart
final result = await Koolbase.db.collection('articles').searchSemantic(
  field: 'content_embedding',
  queryText: 'how do I move quicker?',
  mode: KoolbaseSearchMode.hybrid,
  minSimilarity: 70, // only matches at least 70% similar
  limit: 10,
);
```

`minSimilarity` is rejected by the server when used with
`KoolbaseSearchMode.lexical` — BM25 rank scores aren't comparable to
cosine similarity, and silently ignoring the parameter would produce
confusing "I set 80, why did weak results return?" behavior.

#### Server-side embedding (recommended)

Configure an AI provider on the project once (Gemini's free tier works;
OpenAI also supported), tag the vector field with the
provider/model/source_field, and Koolbase auto-embeds records as they're
inserted or updated. Lexical indexing happens automatically on the same
write, so all three search modes work without extra setup:

```dart
// One-time setup: configure provider + tag the vector field via the
// dashboard. Then just write records normally — vectors AND lexical
// rows land within ~1s.
await Koolbase.db.collection('articles').create({
  'title': 'How to ship faster',
  'content': 'Cut scope ruthlessly. Ship the smallest useful slice...',
});

// Iterate over hits the same way regardless of mode:
for (final hit in result.hits) {
  print('${hit.record['title']}  (${hit.distance.toStringAsFixed(3)})');
}

// Backfill records that pre-date the auto-embed config:
await Koolbase.db.collection('articles').embedText(
  recordId: article.id,
  vectorField: 'content_embedding',
);

// Or override the source — useful for combining fields:
await Koolbase.db.collection('articles').embedText(
  recordId: article.id,
  vectorField: 'content_embedding',
  text: '${article.title}\n\n${article.summary}',
);
```

#### Client-side embedding (advanced)

If you'd rather control the embedding model yourself, pass a vector
instead of text. Note that lexical and hybrid modes require text, since
BM25 has no notion of "vector queries":

```dart
// Set a vector you've encoded yourself
await Koolbase.db.doc(articleId).setVector(
  'embedding',
  await myEmbeddingModel.encode(article.content),
);

// Read it back
final v = await Koolbase.db.doc(articleId).getVector('embedding');
print('${v.vector.length}-dim, updated ${v.updatedAt}');

// Search with a precomputed query vector — semantic mode only.
final result = await Koolbase.db.collection('articles').searchSemantic(
  field: 'embedding',
  queryVector: await myEmbeddingModel.encode(userQuery),
  limit: 10,
  where: {'category': 'tech'},
);

// Remove a record's vector when no longer needed
await Koolbase.db.doc(articleId).deleteVector('embedding');
```

#### Behaviors worth knowing

- **Pass exactly one of `queryVector` or `queryText`.** Supplying both or
  neither throws `ArgumentError`.
- **`queryVector` is for semantic mode only.** Lexical and hybrid modes
  need raw text — the server uses it for BM25 ranking (and embeds it
  inline for the vector half of hybrid).
- **Vector length must match the declared dimension.** Mismatches throw
  `KoolbaseVectorDimensionMismatchException` with expected and actual
  dimensions in the message.
- **`minSimilarity` must be 0..100.** Values outside that range throw
  `ArgumentError` client-side before the request is sent.
- **Online-only.** Vector operations are not cached locally or queued
  offline — HNSW similarity and BM25 ranking have no useful offline
  semantics.
- **Read rule applies post-search.** Semantic search respects the
  collection's read rule the same way `.get()` does: `owner`/`scoped`/
  `conditional` records are filtered to the caller after retrieval, so
  strict rules may return fewer than `limit` results.
- **`embedText` is async.** Returns when the job is queued (~100ms). The
  vector typically lands within 1 second once the worker picks it up.
- **Higher dimensions coming.** OpenAI's `text-embedding-3-large` ships
  at 3072 dimensions, supported in a future release once pgvector is
  upgraded. In the meantime, use your model's `dimensions=1536` parameter
  (Matryoshka truncation) for full compatibility.

See [Semantic search docs](https://docs.koolbase.com/database/vectors)
for setup, provider configuration, embedding model recommendations, and
when to pick each mode.

---

## Storage

Upload and serve files via presigned URLs to Cloudflare R2. Uploads are
**safe-by-default** (v6+) — uploading to a path that's already taken throws
`KoolbaseStorageConflictException` instead of silently replacing the
existing file. Pass `overwrite: true` for true upsert semantics.

```dart
// Upload — rejects if `user-123.jpg` already exists
await Koolbase.storage.upload(
  bucket: 'avatars',
  path: 'user-123.jpg',
  file: file,
);

// Upload — silently replaces any existing object at this path
await Koolbase.storage.upload(
  bucket: 'avatars',
  path: 'user-123.jpg',
  file: file,
  overwrite: true,
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

### Public bucket URLs

For files in public buckets, you can construct the stable CDN URL directly — no
network call, no expiry, embeddable anywhere a browser fetches a URL.

```dart
// From a KoolbaseObject you already have (e.g. from upload() or another read)
final obj = result.object;
final url = obj.publicUrl('avatars');
// url is null for private-bucket objects; the CDN URL for public-bucket ones.

if (url != null) {
  // Safe to use — file lives in the public R2 bucket
  return Image.network(url);
}

// For build-time URL construction (no Object on hand)
final url = KoolbaseStorageClient.publicUrl(
  projectId: 'proj_abc',
  bucket: 'avatars',
  path: 'user-123.jpg',
);
// Always returns the URL pattern; caller is responsible for knowing
// the file lives in a public bucket. For files in private buckets,
// the resulting URL will 404.
```

URLs follow the pattern `https://cdn.koolbase.com/{project_id}/{bucket}/{path}` — long-lived, edge-cached, no authentication. For files in private buckets, use `getDownloadUrl` instead, which returns a 1-hour presigned URL.

---

### Image transforms

Public bucket URLs can be transformed at the edge — resize, reformat,
optimize — without any preprocessing. Two ways:

**Direct transforms** — pass a `KoolbaseImageTransform` to `publicUrl`:

```dart
final url = KoolbaseStorageClient.publicUrl(
  projectId: 'proj_abc',
  bucket: 'avatars',
  path: 'user-123.jpg',
  transform: const KoolbaseImageTransform(
    width: 200,
    height: 200,
    fit: KoolbaseImageFit.cover,
    format: KoolbaseImageFormat.auto,
    quality: 85,
  ),
);
```

**Named presets** — store an option set server-side (via the dashboard or
REST API), reference it by name:

```dart
final url = KoolbaseStorageClient.publicUrlWithPreset(
  projectId: 'proj_abc',
  presetName: 'thumbnail',
  bucket: 'avatars',
  path: 'user-123.jpg',
);

// Or from a KoolbaseObject instance:
final url = obj.publicUrlWithPreset('avatars', 'thumbnail');
```

Available options: `width` and `height` (1–2000), `format`
(`auto`/`webp`/`avif`/`jpeg`/`png`), `quality` (1–100), `fit`
(`scaleDown`/`contain`/`cover`/`crop`/`pad`), `dpr` (1–3), `gravity`
(`auto`/`center`/`top`/`bottom`/`left`/`right`/`topLeft`/`topRight`/
`bottomLeft`/`bottomRight`). Transformed responses are edge-cached for 4
hours; Cloudflare includes 5,000 unique transformations/month free per
account.

See [Image Transforms docs](https://docs.koolbase.com/storage/image-transforms)
for the full reference.

---

### Handling upload conflicts

For user-supplied filenames, prompt the user before overwriting:

```dart
try {
  await Koolbase.storage.upload(
    bucket: 'documents',
    path: filename,
    file: file,
  );
} on KoolbaseStorageConflictException catch (e) {
  final ok = await confirmDialog('${e.path} already exists. Overwrite?');
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

---

### Handling bucket limits

Buckets can be configured at creation time with a total size cap
(`max_size_bytes`), a per-file cap (`max_file_size_bytes`), and a
content-type allowlist (`allowed_mime_types`, supports `image/*`-style
wildcards). The server surfaces violations as typed exceptions:

````dart
try {
  await Koolbase.storage.upload(
    bucket: 'user-photos',
    path: filename,
    file: file,
  );
} on KoolbaseStorageMimeTypeException {
  showError('That file type is not allowed in this bucket.');
} on KoolbaseStorageFileTooLargeException {
  showError('That file is too big — pick a smaller one.');
} on KoolbaseStorageQuotaExceededException {
  showError('This bucket is full — delete some files and try again.');
}
````

MIME enforcement runs at presign time — no bytes are transferred before
rejection. File-size and quota enforcement run at confirm time; the
server cleans up the underlying R2 object before returning the error,
so nothing leaks.

See [Error handling](#error-handling) for the full set of storage exceptions.

---

### Object versioning

For buckets with versioning enabled, every overwrite preserves the prior
content as a history version, and deletes are soft (recoverable until
force-purged). Enable versioning on a bucket from the dashboard.

```dart
// List all versions of a path, newest first
final versions = await Koolbase.storage.listVersions(
  bucket: 'documents',
  path: 'contract.pdf',
);

for (final v in versions) {
  print('${v.versionId}: size=${v.size} isCurrent=${v.isCurrent}');
}

// Download a specific historical version
final url = await Koolbase.storage.getDownloadUrl(
  bucket: 'documents',
  path: 'contract.pdf',
  versionId: '019e98ed-eed6-7e71-...',
);

// Bring a history version back as current
// (the existing current is snapshotted to history first)
final restored = await Koolbase.storage.restoreVersion(
  bucket: 'documents',
  path: 'contract.pdf',
  versionId: '019e98ed-eed6-7e71-...',
);

// Hard-remove a single history version (row + R2 bytes)
await Koolbase.storage.purgeVersion(
  bucket: 'documents',
  path: 'contract.pdf',
  versionId: 'old-version-id',
);

// Wipe the entire timeline for a path - every version, every R2 key
await Koolbase.storage.delete(
  bucket: 'documents',
  path: 'contract.pdf',
  forcePurge: true,
);
```

A few behaviors worth knowing:

- **Overwrite snapshots automatically.** Upload to a path that already
  exists in a versioned bucket and the prior bytes are preserved as
  history; the upload becomes the new current.
- **Delete is soft by default.** On a versioned bucket, `delete`
  snapshots the current content and records a delete marker. The
  content is still recoverable via `restoreVersion` until force-purged.
- **Restore is itself a versioned event.** The previously-current row
  gets snapshotted before the target's bytes overwrite canonical. The
  restored row gets a fresh `versionId`; the target stays in history at
  its original id - so you can always undo a restore.
- **Delete markers can be listed but not downloaded.** A marker has
  `size == 0`, `isDeleteMarker == true`, and no bytes. Calling
  `getDownloadUrl` with a marker's `versionId` throws.

---

## Realtime

Stream live changes on a collection. Uses the signed-in user's session, so
subscribe after login. Supports collections whose read rule is `public` or
`authenticated`.

```dart
final sub = Koolbase.realtime.on(collection: 'messages').listen((event) {
  // event.type -> recordCreated | recordUpdated | recordDeleted
  if (event.type == RealtimeEventType.recordDeleted) {
    print('deleted ${event.recordId}');
  } else {
    print('${event.type}: ${event.record}');
  }
});

// Or filter to one kind:
Koolbase.realtime.onRecordCreated(collection: 'messages').listen(print);

await sub.cancel();
```

The socket opens lazily, is shared across subscriptions, and reconnects
automatically. The project is taken from your session — you don't pass it.

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
```

Recall a bundle at any time (`koolbase bundle recall`) to pull it from a channel. Devices on the recalled bundle revert to the previous published bundle — or to the app's built-in defaults if there is none — on their next cold launch.

### VM-level code push (Dart)

Ship actual Dart code changes over the air — no store release — on Android builds compiled with the Koolbase engine via the Koolbase CLI (`koolbase release android`). The SDK checks in, downloads, and stages a patch; the Koolbase engine applies it on the next launch, verifying the signature and build_id and reconstructing the new snapshot at boot, with automatic crash-revert if the patched build fails to start.

```dart
final patcher = KoolbaseVmPatchClient(
  baseUrl: 'https://api.koolbase.com',
  apiKey: 'pk_live_xxxx',
  channel: 'stable',
);

// Check in, download, and stage any available patch. Applies on next launch.
await patcher.init();
```

> VM-level push requires an app built with the Koolbase engine. A standard Flutter build can still use bundle push above, but not Dart code push.

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
| `KoolbaseVectorDimensionMismatchException` | A vector's length doesn't match the field's declared dimension (400, code `vector_dimension_mismatch`). |

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

### Storage errors

All storage failures extend `KoolbaseStorageException` (which implements
`Exception`):

| Exception | When |
|---|---|
| `KoolbaseStorageConflictException` | An upload targets a path that's already taken and `overwrite: false` (409, code `PATH_CONFLICT`). Exposes `.path` — the colliding path. |
| `KoolbaseStorageNotFoundException` | The bucket or object doesn't exist (404). |
| `KoolbaseStorageValidationException` | The request was rejected as invalid — bad path, missing field (400). |
| `KoolbaseStoragePermissionException` | The caller is not allowed to perform the operation (403). |
| `KoolbaseStorageQuotaExceededException` | An upload would push the bucket past its `max_size_bytes` cap (409, code `QUOTA_EXCEEDED`). |
| `KoolbaseStorageFileTooLargeException` | A single file exceeds the bucket's `max_file_size_bytes` cap (413, code `FILE_TOO_LARGE`). |
| `KoolbaseStorageMimeTypeException` | The upload's content-type isn't in the bucket's `allowed_mime_types` allowlist (415, code `MIME_NOT_ALLOWED`). |

```dart
try {
  await Koolbase.storage.upload(
    bucket: 'avatars',
    path: 'me.png',
    file: file,
  );
} on KoolbaseStorageConflictException catch (e) {
  // Already exists — prompt the user to confirm overwrite
  promptOverwrite(e.path);
} on KoolbaseStoragePermissionException {
  showError('You do not have permission to upload here.');
} on KoolbaseStorageException catch (e) {
  // Catch-all for any other storage error
  showError(e.message);
}
```

### Auth errors

Auth methods throw `KoolbaseAuthException` subtypes — `InvalidCredentialsException`,
`AccountLockedException`, `EmailAlreadyInUseException`, `OtpExpiredException`,
and so on — also selected from the server's error `code`.

---

## What's included

- Authentication: email + password, Apple Sign-In, Google Sign-In, phone + OTP
- Database with offline-first cache (Drift), realtime subscriptions, populate for related records, semantic search over vectors
- Storage with presigned uploads and downloads, safe-by-default conflict handling, image transforms, object versioning (history + restore + soft-delete)
- Realtime subscriptions over WebSocket
- Authenticated Dart functions (`ctx.auth` exposes the caller automatically)
- Feature flags and remote config
- Version enforcement (force update, soft update)
- Code push — bundle (config + flag overrides + directives + UI) and VM-level Dart code, no store release
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
