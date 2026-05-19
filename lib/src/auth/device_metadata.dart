import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Current Koolbase Flutter SDK version. Bump this when releasing a new
/// SDK version to pub.dev — used in device metadata headers sent on every
/// authentication request so the server can attribute session activity to
/// the correct SDK version.
const koolbaseSdkVersion = '2.10.1';

const _kDeviceLabelKey = 'koolbase_device_label_v1';

/// Metadata about the client device + app, sent on every authentication
/// request as HTTP headers. Lets the server's sessions infrastructure
/// attribute activity to specific devices, apps, and SDK versions for:
/// - Session list / revoke by device
/// - "New device signed in" security alerts (future server feature)
/// - Analytics on SDK and platform versions
/// - User-Agent-based attribution in logs
///
/// Build once during SDK init via [DeviceMetadata.build] and pass to
/// [AuthApi]. Headers are static for the process lifetime; the device
/// label persists across restarts and survives reinstalls on devices
/// with cloud backup enabled (typical iOS/Android default).
class DeviceMetadata {
  /// Platform identifier: 'ios' | 'android' | 'macos' | 'linux' |
  /// 'windows' | 'fuchsia' | 'web'.
  final String platform;

  /// OS version string (e.g. 'Version 17.4 (Build 21E219)', 'Android 14').
  /// Free-form; the server stores as-is for display in session lists.
  final String platformVersion;

  /// Koolbase SDK version (e.g. '2.10.0'). Matches [koolbaseSdkVersion].
  final String sdkVersion;

  /// Consumer app version from package_info_plus in the form
  /// '{version}+{buildNumber}' (e.g. '1.2.3+45'). Falls back to 'unknown'
  /// if package_info_plus can't resolve (rare; e.g. in unit tests).
  final String appVersion;

  /// Stable opaque identifier for this install. Generated once on first
  /// launch and persisted via shared_preferences. The server uses this to
  /// group session activity by device for the sessions UI.
  final String deviceLabel;

  const DeviceMetadata({
    required this.platform,
    required this.platformVersion,
    required this.sdkVersion,
    required this.appVersion,
    required this.deviceLabel,
  });

  /// Build device metadata. Reads/writes the device label via
  /// shared_preferences; collects platform info via dart:io (or 'web'
  /// fallback for kIsWeb); reads app version via package_info_plus.
  ///
  /// Safe to call once at SDK init. Subsequent calls return new instances
  /// with the same persisted deviceLabel.
  static Future<DeviceMetadata> build() async {
    final prefs = await SharedPreferences.getInstance();

    var label = prefs.getString(_kDeviceLabelKey);
    if (label == null) {
      label = const Uuid().v4();
      await prefs.setString(_kDeviceLabelKey, label);
    }

    String platform;
    String platformVersion;
    if (kIsWeb) {
      platform = 'web';
      platformVersion = 'web';
    } else {
      platform = Platform.operatingSystem;
      platformVersion = Platform.operatingSystemVersion;
    }

    String appVersion;
    try {
      final info = await PackageInfo.fromPlatform();
      appVersion = '${info.version}+${info.buildNumber}';
    } catch (_) {
      appVersion = 'unknown';
    }

    return DeviceMetadata(
      platform: platform,
      platformVersion: platformVersion,
      sdkVersion: koolbaseSdkVersion,
      appVersion: appVersion,
      deviceLabel: label,
    );
  }

  /// HTTP headers attached to every authentication request via [AuthApi].
  /// All values are safe-ASCII; no quoting required.
  Map<String, String> toHeaders() => {
        'User-Agent':
            'koolbase-flutter/$sdkVersion ($platform; $platformVersion)',
        'x-koolbase-sdk': 'flutter',
        'x-koolbase-sdk-version': sdkVersion,
        'x-koolbase-platform': platform,
        'x-koolbase-platform-version': platformVersion,
        'x-koolbase-app-version': appVersion,
        'x-koolbase-device-label': deviceLabel,
      };
}
