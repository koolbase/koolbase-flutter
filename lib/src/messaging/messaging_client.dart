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

  final String baseUrl;
  final String apiKey;
  String? _deviceId;

  KoolbaseMessaging({
    required this.baseUrl,
    required this.apiKey,
  });

  void setDeviceId(String deviceId) {
    _deviceId = deviceId;
  }

  // ─── Register token ───────────────────────────────────────────────────────

  /// Register an FCM device token with Koolbase.
  /// Call this after obtaining the token from firebase_messaging.
  ///
  /// ```dart
  /// final fcmToken = await FirebaseMessaging.instance.getToken();
  /// await Koolbase.messaging.registerToken(
  ///   token: fcmToken!,
  ///   platform: 'android',
  /// );
  /// ```
  Future<bool> registerToken({
    required String token,
    required String platform,
    String? userId,
  }) async {
    if (_deviceId == null) {
      debugPrint('$_tag registerToken called before deviceId is set');
      return false;
    }

    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/v1/messaging/register'),
            headers: {
              'Content-Type': 'application/json',
              'x-api-key': apiKey,
            },
            body: jsonEncode({
              'device_id': _deviceId,
              'token': token,
              'platform': platform,
              if (userId != null) 'user_id': userId,
            }),
          )
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
