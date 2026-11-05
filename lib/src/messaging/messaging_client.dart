import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

// ─── Models ──────────────────────────────────────────────────────────────────

class KoolbaseMessage {
  final String title;
  final String body;
  final Map<String, dynamic> data;

  const KoolbaseMessage({
    required this.title,
    required this.body,
    this.data = const {},
  });
}

// ─── KoolbaseMessaging ────────────────────────────────────────────────────────

// NOTE: there is deliberately no send() here. Sending requires a secret
// kb_live_ key and is server-initiated only (backend or Koolbase Function) —
// the publishable key this client holds ships inside the app binary and must
// not be able to push to other devices. The API answers 401 to publishable-key
// sends by design. See docs: /sdk/messaging.
class KoolbaseMessaging {
  static const _tag = '[KoolbaseMessaging]';

  /// The platforms a token registers as: a phone's FCM token, or a
  /// browser's (R138).
  static const platforms = {'android', 'ios', 'web'};

  final String baseUrl;
  final String apiKey;

  /// The signed-in person's access token, or null: the device is theirs
  /// only while they are signed in (the API takes the owner from it, never
  /// from the request body).
  final Future<String?> Function()? accessTokenProvider;

  final http.Client? _client;
  String? _deviceId;

  /// The last token registered, and its platform: registered again when
  /// someone signs in or out, so the device follows who is signed in.
  String? _token;
  String? _platform;

  KoolbaseMessaging({
    required this.baseUrl,
    required this.apiKey,
    this.accessTokenProvider,
    http.Client? httpClient,
  }) : _client = httpClient;

  void setDeviceId(String deviceId) {
    _deviceId = deviceId;
  }

  // ─── Register token ───────────────────────────────────────────────────────

  /// Register an FCM device token with Koolbase -- tied to the signed-in
  /// person, if someone is signed in (R138). Call it after obtaining the
  /// token from firebase_messaging, and again when the token changes;
  /// signing in or out registers it again by itself.
  ///
  /// ```dart
  /// final fcmToken = await FirebaseMessaging.instance.getToken();
  /// await Koolbase.messaging.registerToken(
  ///   token: fcmToken!,
  ///   platform: 'android',
  /// );
  /// ```
  ///
  /// [userId] is ignored by the API (the owner comes from the session) and
  /// kept for compatibility.
  Future<bool> registerToken({
    required String token,
    required String platform,
    String? userId,
  }) async {
    if (_deviceId == null) {
      debugPrint('$_tag registerToken called before deviceId is set');
      return false;
    }
    if (!platforms.contains(platform)) {
      debugPrint('$_tag platform must be one of ${platforms.join(', ')}');
      return false;
    }
    _token = token;
    _platform = platform;
    return _send(token, platform);
  }

  /// Someone signed in or out (Koolbase wires it): the last token is
  /// registered again, so it follows who is signed in. Nothing before a
  /// token is registered.
  Future<void> sessionChanged() async {
    final token = _token;
    final platform = _platform;
    if (token == null || platform == null) return;
    await _send(token, platform);
  }

  Future<bool> _send(String token, String platform) async {
    try {
      final headers = <String, String>{
        'Content-Type': 'application/json',
        'x-api-key': apiKey,
      };
      final access = await accessTokenProvider?.call();
      if (access != null && access.isNotEmpty) {
        headers['Authorization'] = 'Bearer $access';
      }
      final url = Uri.parse('$baseUrl/v1/messaging/register');
      final body = jsonEncode({
        'device_id': _deviceId,
        'token': token,
        'platform': platform,
      });
      final client = _client;
      final response = await (client == null
              ? http.post(url, headers: headers, body: body)
              : client.post(url, headers: headers, body: body))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        debugPrint('$_tag token registered successfully');
        return true;
      }

      debugPrint('$_tag failed to register token: ${response.statusCode}');
      return false;
    } catch (e) {
      debugPrint('$_tag registerToken error: $e');
      return false;
    }
  }
}
