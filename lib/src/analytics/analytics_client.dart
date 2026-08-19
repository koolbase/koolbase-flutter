import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import '../device_id.dart';

// ─── Models ──────────────────────────────────────────────────────────────────

class KoolbaseEvent {
  final String deviceId;
  final String? userId;
  final String? environmentId;
  final String eventName;
  final Map<String, dynamic> properties;
  final Map<String, dynamic> userProperties;
  final String platform;
  final String appVersion;
  final String sdkVersion;
  final String sessionId;
  final DateTime occurredAt;

  const KoolbaseEvent({
    required this.deviceId,
    this.userId,
    this.environmentId,
    required this.eventName,
    this.properties = const {},
    this.userProperties = const {},
    required this.platform,
    required this.appVersion,
    required this.sdkVersion,
    required this.sessionId,
    required this.occurredAt,
  });

  Map<String, dynamic> toJson() => {
        'device_id': deviceId,
        if (userId != null) 'user_id': userId,
        if (environmentId != null) 'environment_id': environmentId,
        'event_name': eventName,
        'properties': properties,
        'user_properties': userProperties,
        'platform': platform,
        'app_version': appVersion,
        'sdk_version': sdkVersion,
        'session_id': sessionId,
        'occurred_at': occurredAt.toUtc().toIso8601String(),
      };
}

// ─── KoolbaseAnalyticsClient ─────────────────────────────────────────────────

class KoolbaseAnalyticsClient {
  static const _tag = '[KoolbaseAnalytics]';
  static const _sdkVersion = '2.2.0';
  static const _flushInterval = Duration(seconds: 30);
  static const _maxBatchSize = 20;

  final String baseUrl;
  final String apiKey;

  String? _userId;
  String? _environmentId;
  final Map<String, dynamic> _userProperties = {};

  late final String _deviceId;
  late final String _sessionId;
  late String _appVersion;
  late String _platform;

  final List<KoolbaseEvent> _queue = [];
  Timer? _flushTimer;
  bool _initialized = false;

  /// Resolves the currently signed-in user so events carry identity
  /// without the app remembering to call [identify].
  ///
  /// Requiring a manual call guaranteed silent failure: nothing errors
  /// when it is missing, so every event lands anonymous and retention,
  /// funnels and per-user analysis are quietly worthless. The SDK
  /// already knows who is signed in — it should say so.
  final String? Function()? currentUserId;

  KoolbaseAnalyticsClient({
    required this.baseUrl,
    required this.apiKey,
    this.currentUserId,
  });

  // ─── Init ─────────────────────────────────────────────────────────────────

  Future<void> init() async {
    if (_initialized) return;

    _deviceId = await DeviceIdManager.getOrCreate();
    _sessionId = _generateSessionId();

    final info = await PackageInfo.fromPlatform();
    _appVersion = info.version;
    _platform = defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';

    // Start flush timer
    _flushTimer = Timer.periodic(_flushInterval, (_) => flush());

    // Track app_open
    track('app_open');

    _initialized = true;
    debugPrint('$_tag initialized — device: $_deviceId session: $_sessionId');
  }

  // ─── Public API ───────────────────────────────────────────────────────────

  /// Track a custom event with optional properties
  void track(String eventName, {Map<String, dynamic>? properties}) {
    if (!_initialized && eventName != 'app_open') return;

    final event = KoolbaseEvent(
      deviceId: _deviceId,
      // An explicit identify() wins — apps with their own identity
      // system stay in control — otherwise the signed-in Koolbase user
      // is attached automatically.
      userId: _userId ?? currentUserId?.call(),
      environmentId: _environmentId,
      eventName: eventName,
      properties: properties ?? {},
      userProperties: Map<String, dynamic>.from(_userProperties),
      platform: _platform,
      appVersion: _appVersion,
      sdkVersion: _sdkVersion,
      sessionId: _sessionId,
      occurredAt: DateTime.now().toUtc(),
    );

    _queue.add(event);
    debugPrint('$_tag queued: $eventName (queue: ${_queue.length})');

    if (_queue.length >= _maxBatchSize) {
      flush();
    }
  }

  /// Track a screen view
  void screenView(String screenName, {Map<String, dynamic>? properties}) {
    track('screen_view', properties: {
      'screen_name': screenName,
      ...?properties,
    });
  }

  /// Set a user property
  void setUserProperty(String key, dynamic value) {
    _userProperties[key] = value;
  }

  /// Set multiple user properties at once
  void setUserProperties(Map<String, dynamic> properties) {
    _userProperties.addAll(properties);
  }

  /// Identify authenticated user
  void identify(String userId) {
    _userId = userId;
    debugPrint('$_tag identified user: $userId');
  }

  /// Clear user identity on logout
  /// Clear the user identity and properties. Releases an explicit
  /// [identify] override, after which events fall back to the
  /// signed-in Koolbase user (or none, once signed out).
  void reset() {
    _userId = null;
    _userProperties.clear();
  }

  /// Set the environment ID
  void setEnvironment(String environmentId) {
    _environmentId = environmentId;
  }

  // ─── Flush ────────────────────────────────────────────────────────────────

  Future<void> flush() async {
    if (_queue.isEmpty) return;

    final batch = List<KoolbaseEvent>.from(_queue);
    _queue.clear();

    debugPrint('$_tag flushing ${batch.length} events');

    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/v1/analytics/events'),
            headers: {
              'Content-Type': 'application/json',
              'x-api-key': apiKey,
            },
            body: jsonEncode({'events': batch.map((e) => e.toJson()).toList()}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 202) {
        debugPrint('$_tag flushed ${batch.length} events successfully');
      } else {
        debugPrint('$_tag flush failed: ${response.statusCode}');
        // Re-queue events on failure (up to max batch size)
        if (_queue.length < _maxBatchSize) {
          _queue.insertAll(0, batch);
        }
      }
    } catch (e) {
      debugPrint('$_tag flush error: $e');
      // Re-queue on network error
      if (_queue.length < _maxBatchSize) {
        _queue.insertAll(0, batch);
      }
    }
  }

  /// Call on app background/close
  Future<void> dispose() async {
    _flushTimer?.cancel();
    track('session_end');
    await flush();
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────

  String _generateSessionId() {
    final now = DateTime.now().millisecondsSinceEpoch;
    return '$_deviceId-$now';
  }
}

// ─── NavigatorObserver ────────────────────────────────────────────────────────

class KoolbaseNavigatorObserver extends NavigatorObserver {
  final KoolbaseAnalyticsClient client;

  KoolbaseNavigatorObserver({required this.client});

  @override
  void didPush(Route route, Route? previousRoute) {
    super.didPush(route, previousRoute);
    _trackScreen(route);
  }

  @override
  void didReplace({Route? newRoute, Route? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (newRoute != null) _trackScreen(newRoute);
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    super.didPop(route, previousRoute);
    if (previousRoute != null) _trackScreen(previousRoute);
  }

  void _trackScreen(Route route) {
    final name = route.settings.name;
    if (name != null && name.isNotEmpty) {
      client.screenView(name);
    }
  }
}
