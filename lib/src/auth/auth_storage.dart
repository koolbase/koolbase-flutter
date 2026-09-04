import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'auth_models.dart';

/// A complete persisted session — refresh token, access token, expiry, user.
///
/// Persisting all four fields (not just refresh token) lets the SDK restore
/// authentication optimistically on app launch without a network round-trip.
/// Apps can render their authenticated UI immediately and refresh in the
/// background if needed.
class PersistedSession {
  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
  final KoolbaseUser user;

  const PersistedSession({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.user,
  });

  factory PersistedSession.fromAuthSession(AuthSession session) {
    return PersistedSession(
      accessToken: session.accessToken,
      refreshToken: session.refreshToken,
      expiresAt: session.expiresAt,
      user: session.user,
    );
  }

  factory PersistedSession.fromJson(Map<String, dynamic> json) {
    return PersistedSession(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String,
      expiresAt: DateTime.parse(json['expires_at'] as String),
      user: KoolbaseUser.fromJson(json['user'] as Map<String, dynamic>),
    );
  }

  Map<String, dynamic> toJson() => {
        'access_token': accessToken,
        'refresh_token': refreshToken,
        'expires_at': expiresAt.toIso8601String(),
        'user': user.toJson(),
      };

  bool get isAccessTokenExpired => DateTime.now().isAfter(expiresAt);
}

/// Abstract storage interface for persisting authentication state.
///
/// The SDK ships with [SecureAuthStorage] as the default, backed by
/// `flutter_secure_storage` (iOS Keychain, Android EncryptedSharedPreferences).
///
/// Apps with custom requirements — HIPAA-compliant encryption layers, web
/// targets, in-memory storage for testing, or alternate secure backends —
/// can implement this interface and inject it into [KoolbaseAuthClient]:
///
/// ```dart
/// class MyCustomStorage implements KoolbaseAuthStorage {
///   @override
///   Future<void> saveSession(PersistedSession session) async { ... }
///   // ...
/// }
///
/// final client = KoolbaseAuthClient(
///   api: api,
///   storage: MyCustomStorage(),
/// );
/// ```
abstract class KoolbaseAuthStorage {
  /// Persist the full session (access token, refresh token, expiry, user).
  /// Implementations must be atomic — partial writes leave authentication
  /// in an undefined state.
  Future<void> saveSession(PersistedSession session);

  /// Read the persisted session, or null if none exists.
  /// Returning null on read errors (corrupt data, missing key) is acceptable
  /// — the SDK treats it the same as "no session".
  Future<PersistedSession?> readSession();

  /// Clear all persisted authentication state.
  Future<void> clear();
}

/// In-memory storage for tests. Holds a session for the life of the
/// object and forgets it after; never touches the keychain. Also what
/// [Koolbase.initializeForTesting] uses, so an auth gate can restore to
/// signed-out and render its children without a platform channel.
class InMemoryAuthStorage implements KoolbaseAuthStorage {
  PersistedSession? _session;

  @override
  Future<void> saveSession(PersistedSession session) async {
    _session = session;
  }

  @override
  Future<PersistedSession?> readSession() async => _session;

  @override
  Future<void> clear() async {
    _session = null;
  }
}

/// Default storage implementation backed by `flutter_secure_storage`.
///
/// Uses platform-native secure stores:
/// - iOS: Keychain (accessibility: `first_unlock_this_device` — accessible
///   after first unlock, never synced to iCloud, doesn't migrate to new
///   devices via backup restore)
/// - Android: EncryptedSharedPreferences (AES-256-GCM, AndroidKeystore-wrapped)
class SecureAuthStorage implements KoolbaseAuthStorage {
  static const _sessionKey = 'koolbase_session_v2';

  final FlutterSecureStorage _storage;

  SecureAuthStorage({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
            );

  @override
  Future<void> saveSession(PersistedSession session) async {
    final encoded = jsonEncode(session.toJson());
    await _storage.write(key: _sessionKey, value: encoded);
  }

  @override
  Future<PersistedSession?> readSession() async {
    try {
      final raw = await _storage.read(key: _sessionKey);
      if (raw == null) return null;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return PersistedSession.fromJson(json);
    } catch (_) {
      // Corrupt data, schema mismatch from older SDK, or platform-level
      // keychain error. Treat as no session — caller will trigger fresh login.
      return null;
    }
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _sessionKey);
    // Best-effort cleanup of pre-v2.9.0 storage keys (refresh token only).
    // Safe to call even if the legacy key doesn't exist.
    await _storage.delete(key: 'koolbase_refresh_token');
  }
}
