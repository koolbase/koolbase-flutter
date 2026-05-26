import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'auth/auth_api.dart';
import 'code_push/code_push_client.dart';
import 'code_push/bundle_model.dart';
import 'analytics/analytics_client.dart';
import 'messaging/messaging_client.dart';
export 'messaging/messaging_client.dart'
    show KoolbaseMessaging, KoolbaseMessage;
export 'analytics/analytics_client.dart' show KoolbaseNavigatorObserver;
import 'code_push/flow_models.dart';
import 'rfw/rfw_models.dart';
export 'rfw/dynamic_screen.dart'
    show KoolbaseDynamicScreen, KoolbaseCodePushScope;
export 'rfw/rfw_models.dart' show KoolbaseRfwWidget;
export 'code_push/flow_models.dart' show FlowResult;
export 'code_push/bundle_model.dart';
export 'code_push/runtime_override.dart';
import 'functions/functions_client.dart';
import 'storage/storage_client.dart';
import 'database/database_client.dart';
import 'database/offline/local_database.dart';
import 'database/offline/cache_store.dart';
import 'database/offline/write_queue.dart';
import 'database/sync_engine.dart';
import 'realtime/realtime_client.dart';
export 'realtime/realtime_models.dart';
export 'database/database_models.dart';
export 'database/database_query.dart' show KoolbaseQuery;
export 'storage/storage_models.dart';
import 'auth/auth_client.dart';
import 'auth/device_metadata.dart';
import 'cache.dart';
import 'device_id.dart';
import 'evaluator.dart';
import 'payload.dart';
export 'payload.dart';
export 'auth/auth_models.dart';
export 'auth/auth_exceptions.dart';

/// Configuration for the Koolbase SDK.
class KoolbaseConfig {
  /// Your environment public key (e.g. pk_live_xxxx or pk_test_xxxx)
  final String publicKey;

  final String baseUrl;

  /// How often the SDK refreshes the bootstrap payload in the background.
  final Duration refreshInterval;

  /// The code push channel to subscribe to (default: stable)
  final String codePushChannel;

  /// Optional callback fired when a *mandatory* code-push bundle has been
  /// staged and is awaiting application on the next cold launch. Use it to
  /// prompt the user to restart so the required update takes effect. The
  /// SDK also exposes `Koolbase.codePush.hasMandatoryUpdate` for polling.
  final MandatoryUpdateCallback? onMandatoryUpdate;

  /// Custom rfw widgets to register beyond the defaults
  final List<KoolbaseRfwWidget> rfwWidgets;

  /// Whether to enable analytics (default: true)
  final bool analyticsEnabled;

  /// Whether to enable cloud messaging (default: true)
  final bool messagingEnabled;

  /// Timeout applied to every authentication HTTP request. Default 10s.
  /// Tune up for high-latency networks; tune down for fast-fail UX.
  final Duration authTimeout;

  /// Optional HTTP client used for authentication requests. If provided,
  /// the SDK will use it instead of constructing its own — letting you add
  /// logging, retry middleware, proxy configuration, or share a single
  /// client across your app. The SDK will NOT close a caller-supplied
  /// client; the caller owns its lifecycle.
  ///
  /// Currently scoped to auth requests; other SDK modules (storage,
  /// database, realtime, etc.) will adopt this in a future release.
  final http.Client? httpClient;

  const KoolbaseConfig({
    required this.publicKey,
    required this.baseUrl,
    this.refreshInterval = const Duration(seconds: 60),
    this.codePushChannel = 'stable',
    this.onMandatoryUpdate,
    this.rfwWidgets = const [],
    this.analyticsEnabled = true,
    this.messagingEnabled = true,
    this.authTimeout = const Duration(seconds: 10),
    this.httpClient,
  });
}

/// The main Koolbase SDK client.
class Koolbase {
  static Koolbase? _instance;
  static KoolbaseAuthClient? _auth;
  static KoolbaseStorageClient? _storage;
  static KoolbaseDatabaseClient? _database;
  static KoolbaseRealtimeClient? _realtime;
  static KoolbaseFunctionsClient? _functions;
  static KoolbaseLocalDatabase? _localDb;
  static SyncEngine? _syncEngine;
  static bool _initialized = false;
  static KoolbaseCodePushClient? _codePush;
  static KoolbaseAnalyticsClient? _analytics;
  static KoolbaseMessaging? _messaging;

  final KoolbaseConfig _config;
  KoolbasePayload _payload;
  String _deviceId = '';
  String _appVersion = '';
  String _platform = '';

  Koolbase._(this._config, this._payload);

  /// Initializes the SDK. Call this in main() before runApp().
  static Future<void> initialize(KoolbaseConfig config) async {
    if (_initialized) return;

    final deviceId = await DeviceIdManager.getOrCreate();
    final packageInfo = await PackageInfo.fromPlatform();
    final appVersion = packageInfo.version;
    final platform = _getPlatform();

    // Load cached payload immediately
    final cached = await KoolbaseCache.load();
    final payload = cached ?? KoolbasePayload.empty();

    final instance = Koolbase._(config, payload);
    instance._deviceId = deviceId;
    instance._appVersion = appVersion;
    instance._platform = platform;
    _instance = instance;

    // Initialize auth client
    final deviceMetadata = await DeviceMetadata.build();
    final authApi = AuthApi(
      baseUrl: config.baseUrl,
      publicKey: config.publicKey,
      deviceMetadata: deviceMetadata,
      timeout: config.authTimeout,
      client: config.httpClient,
    );
    _auth = KoolbaseAuthClient(
      api: authApi,
    );

    // Restore auth session from secure storage
    await _auth!.restoreSession();

    // Initialize realtime client
    _realtime = KoolbaseRealtimeClient(
      baseUrl: config.baseUrl,
      publicKey: config.publicKey,
    );

    // Initialize offline database (Drift)
    _localDb = KoolbaseLocalDatabase();
    final cacheStore = CacheStore(_localDb!);
    final writeQueue = WriteQueue(_localDb!);

    // Initialize database client with offline support
    _database = KoolbaseDatabaseClient(
      baseUrl: config.baseUrl,
      publicKey: config.publicKey,
      accessTokenProvider: () =>
          _auth?.validAccessToken() ?? Future<String?>.value(null),
      cacheStore: cacheStore,
      writeQueue: writeQueue,
    );

    // Initialize sync engine — auto-syncs on reconnect
    _syncEngine = SyncEngine(
      baseUrl: config.baseUrl,
      publicKey: config.publicKey,
      cacheStore: cacheStore,
      writeQueue: writeQueue,
      accessTokenProvider: () =>
          _auth?.validAccessToken() ?? Future<String?>.value(null),
    );
    _syncEngine!.start();

    // Initialize storage client
    _storage = KoolbaseStorageClient(
      baseUrl: config.baseUrl,
      publicKey: config.publicKey,
      accessTokenProvider: () =>
          _auth?.validAccessToken() ?? Future<String?>.value(null),
    );

    // Initialize functions client
    _functions = KoolbaseFunctionsClient(
      baseUrl: config.baseUrl,
      publicKey: config.publicKey,
      userAccessTokenProvider: () =>
          _auth?.validAccessToken() ?? Future<String?>.value(null),
    );

    // Initialize code push client
    _codePush = KoolbaseCodePushClient(
      baseUrl: config.baseUrl,
      apiKey: config.publicKey,
      channel: config.codePushChannel,
      onMandatoryUpdate: config.onMandatoryUpdate,
    );

    await _codePush!.init(
      appVersion: appVersion,
      platform: platform,
      deviceId: deviceId,
      remoteConfig: payload.config,
      remoteFlags: payload.flags.map((k, v) => MapEntry(k, v.enabled)),
    );

    // Fetch fresh flags in background
    instance._fetchAndUpdate();
    instance._startPolling();

    // Initialize analytics
    if (config.analyticsEnabled) {
      _analytics = KoolbaseAnalyticsClient(
        baseUrl: config.baseUrl,
        apiKey: config.publicKey,
      );
      await _analytics!.init();
    }

    // Initialize messaging
    if (config.messagingEnabled) {
      _messaging = KoolbaseMessaging(
        baseUrl: config.baseUrl,
        apiKey: config.publicKey,
      );
      _messaging!.setDeviceId(await DeviceIdManager.getOrCreate());
    }

    _initialized = true;
  }

  static void _ensureInitialized() {
    if (!_initialized) {
      throw StateError(
        'Koolbase has not been initialized. '
        'Call Koolbase.initialize() first.',
      );
    }
  }

  static Koolbase get _client {
    _ensureInitialized();
    return _instance!;
  }

  /// Access the realtime client
  static KoolbaseRealtimeClient get realtime {
    _ensureInitialized();
    return _realtime!;
  }

  /// Access the database client
  static KoolbaseDatabaseClient get db {
    _ensureInitialized();
    return _database!;
  }

  /// Access the storage client
  static KoolbaseStorageClient get storage {
    _ensureInitialized();
    return _storage!;
  }

  /// Access the functions client
  static KoolbaseFunctionsClient get functions {
    _ensureInitialized();
    return _functions!;
  }

  /// Access the code push client
  /// Execute a named flow from the active bundle.
  static FlowResult executeFlow({
    required String flowId,
    Map<String, dynamic>? context,
  }) {
    _ensureInitialized();
    return _codePush!.executeFlow(
      flowId: flowId,
      context: context,
    );
  }

  static KoolbaseAnalyticsClient get analytics {
    _ensureInitialized();
    return _analytics!;
  }

  static KoolbaseMessaging get messaging {
    _ensureInitialized();
    return _messaging!;
  }

  static KoolbaseCodePushClient get codePush {
    _ensureInitialized();
    return _codePush!;
  }

  /// Access the auth client
  static KoolbaseAuthClient get auth {
    _ensureInitialized();
    return _auth!;
  }

  // ─── Flag Evaluation ───────────────────────────────────────────────────────

  static bool isEnabled(String flagKey) {
    final client = _client;

    // Bundle override wins over remote flags
    if (_codePush != null && _codePush!.hasActiveBundle) {
      final bundleValue = _codePush!.override.allFlags[flagKey];
      if (bundleValue != null) return bundleValue;
    }

    final flag = client._payload.flags[flagKey];
    if (flag == null) return false;
    return RolloutEvaluator.isEnabled(
      deviceId: client._deviceId,
      flagKey: flagKey,
      flagEnabled: flag.enabled,
      rolloutPercentage: flag.rolloutPercentage,
      killSwitch: flag.killSwitch,
    );
  }

  // ─── Config Access ─────────────────────────────────────────────────────────

  static String configString(String key, {String fallback = ''}) {
    if (_codePush != null && _codePush!.hasActiveBundle) {
      final v = _codePush!.override.getConfig(key);
      if (v != null) return v.toString();
    }
    final value = _client._payload.config[key];
    if (value == null) return fallback;
    return value.toString();
  }

  static int configInt(String key, {int fallback = 0}) {
    if (_codePush != null && _codePush!.hasActiveBundle) {
      final v = _codePush!.override.getConfig(key);
      if (v != null) {
        if (v is int) return v;
        if (v is double) return v.toInt();
        return int.tryParse(v.toString()) ?? fallback;
      }
    }
    final value = _client._payload.config[key];
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is double) return value.toInt();
    return int.tryParse(value.toString()) ?? fallback;
  }

  static double configDouble(String key, {double fallback = 0.0}) {
    if (_codePush != null && _codePush!.hasActiveBundle) {
      final v = _codePush!.override.getConfig(key);
      if (v != null) {
        if (v is double) return v;
        if (v is int) return v.toDouble();
        return double.tryParse(v.toString()) ?? fallback;
      }
    }
    final value = _client._payload.config[key];
    if (value == null) return fallback;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value.toString()) ?? fallback;
  }

  static bool configBool(String key, {bool fallback = false}) {
    if (_codePush != null && _codePush!.hasActiveBundle) {
      final v = _codePush!.override.getConfig(key);
      if (v != null) {
        if (v is bool) return v;
        return v.toString() == 'true';
      }
    }
    final value = _client._payload.config[key];
    if (value == null) return fallback;
    if (value is bool) return value;
    return value.toString() == 'true';
  }

  static Map<String, dynamic> configMap(String key,
      {Map<String, dynamic> fallback = const {}}) {
    final value = _client._payload.config[key];
    if (value == null) return fallback;
    if (value is Map<String, dynamic>) return value;
    return fallback;
  }

  // ─── Version Policy ────────────────────────────────────────────────────────

  static VersionCheckResult checkVersion() {
    final client = _client;
    final policy = client._payload.version;

    if (policy.minVersion.isEmpty) {
      return const VersionCheckResult(
        status: VersionStatus.upToDate,
        message: '',
        latestVersion: '',
      );
    }

    final current = _parseVersion(client._appVersion);
    final minVersion = _parseVersion(policy.minVersion);
    final latestVersion = _parseVersion(policy.latestVersion);

    if (current < minVersion) {
      return VersionCheckResult(
        status: VersionStatus.forceUpdate,
        message: policy.updateMessage,
        latestVersion: policy.latestVersion,
      );
    }

    if (policy.latestVersion.isNotEmpty && current < latestVersion) {
      return VersionCheckResult(
        status: policy.forceUpdate
            ? VersionStatus.forceUpdate
            : VersionStatus.softUpdate,
        message: policy.updateMessage,
        latestVersion: policy.latestVersion,
      );
    }

    return VersionCheckResult(
      status: VersionStatus.upToDate,
      message: '',
      latestVersion: policy.latestVersion,
    );
  }

  // ─── Payload Info ──────────────────────────────────────────────────────────

  static String get payloadVersion => _client._payload.payloadVersion;
  static String get deviceId => _client._deviceId;

  // ─── Internal ──────────────────────────────────────────────────────────────

  Future<void> _fetchAndUpdate() async {
    try {
      final uri = Uri.parse('${_config.baseUrl}/v1/bootstrap').replace(
        queryParameters: {
          'public_key': _config.publicKey,
          'device_id': _deviceId,
          'platform': _platform,
          'app_version': _appVersion,
        },
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final freshPayload = KoolbasePayload.fromJson(json);

        if (freshPayload.payloadVersion != _payload.payloadVersion) {
          _payload = freshPayload;
          await KoolbaseCache.save(freshPayload);
          debugPrint(
              '[Koolbase] Payload updated: ${freshPayload.payloadVersion}');
        } else {
          debugPrint(
              '[Koolbase] Payload unchanged: ${freshPayload.payloadVersion}');
        }
      }
    } on SocketException {
      debugPrint('[Koolbase] Offline — using cached payload');
    } catch (e) {
      debugPrint('[Koolbase] Bootstrap fetch failed: $e');
    }
  }

  void _startPolling() {
    Future.doWhile(() async {
      await Future.delayed(_config.refreshInterval);
      if (_instance == null) return false;
      await _fetchAndUpdate();
      return true;
    });
  }

  static String _getPlatform() {
    try {
      if (Platform.isAndroid) return 'android';
      if (Platform.isIOS) return 'ios';
    } catch (_) {}
    return 'flutter';
  }

  static int _parseVersion(String version) {
    if (version.isEmpty) return 0;
    final parts = version.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final major = parts.isNotEmpty ? parts[0] : 0;
    final minor = parts.length > 1 ? parts[1] : 0;
    final patch = parts.length > 2 ? parts[2] : 0;
    return major * 10000 + minor * 100 + patch;
  }
}
