/// The full bootstrap payload returned by the Koolbase API.
class KoolbasePayload {
  final String payloadVersion;

  /// The project this environment belongs to. Empty when the server
  /// predates identity metadata or the cached payload was written by an
  /// older SDK; storage public-URL construction requires it and throws
  /// [KoolbaseStorageProjectIdentityException] while it is unavailable.
  final String projectId;
  final Map<String, KoolbaseFlag> flags;
  final Map<String, dynamic> config;
  final KoolbaseVersionPolicy version;

  const KoolbasePayload({
    required this.payloadVersion,
    this.projectId = '',
    required this.flags,
    required this.config,
    required this.version,
  });

  factory KoolbasePayload.fromJson(Map<String, dynamic> json) {
    final rawFlags = json['flags'] as Map<String, dynamic>? ?? {};
    final rawConfig = json['config'] as Map<String, dynamic>? ?? {};
    final rawVersion = json['version'] as Map<String, dynamic>? ?? {};

    return KoolbasePayload(
      payloadVersion: json['payload_version'] as String? ?? '',
      projectId: json['project_id'] as String? ?? '',
      flags: rawFlags.map(
        (key, value) => MapEntry(
          key,
          KoolbaseFlag.fromJson(value as Map<String, dynamic>),
        ),
      ),
      config: rawConfig,
      version: KoolbaseVersionPolicy.fromJson(rawVersion),
    );
  }

  Map<String, dynamic> toJson() => {
        'payload_version': payloadVersion,
        'project_id': projectId,
        'flags': flags.map((k, v) => MapEntry(k, v.toJson())),
        'config': config,
        'version': version.toJson(),
      };

  static KoolbasePayload empty() => KoolbasePayload(
        payloadVersion: '',
        flags: {},
        config: {},
        version: KoolbaseVersionPolicy.empty(),
      );
}

/// A single feature flag rule.
/// SDK evaluates: stableHash(deviceId + ":" + flagKey) % 100 < rolloutPercentage
class KoolbaseFlag {
  final bool enabled;
  final int rolloutPercentage;
  final bool killSwitch;

  const KoolbaseFlag({
    required this.enabled,
    required this.rolloutPercentage,
    required this.killSwitch,
  });

  factory KoolbaseFlag.fromJson(Map<String, dynamic> json) => KoolbaseFlag(
        enabled: json['enabled'] as bool? ?? false,
        rolloutPercentage: json['rollout_percentage'] as int? ?? 0,
        killSwitch: json['kill_switch'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'rollout_percentage': rolloutPercentage,
        'kill_switch': killSwitch,
      };
}

/// Version policy for forced/soft update enforcement.
class KoolbaseVersionPolicy {
  final String latestVersion; // latest_version from API
  final String minVersion; // min_version from API
  final bool forceUpdate; // force_update from API (boolean)
  final String updateMessage;

  const KoolbaseVersionPolicy({
    required this.latestVersion,
    required this.minVersion,
    required this.forceUpdate,
    required this.updateMessage,
  });

  factory KoolbaseVersionPolicy.fromJson(Map<String, dynamic> json) =>
      KoolbaseVersionPolicy(
        latestVersion: json['latest_version'] as String? ?? '',
        minVersion: json['min_version'] as String? ?? '',
        forceUpdate: json['force_update'] as bool? ?? false,
        updateMessage: json['update_message'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'latest_version': latestVersion,
        'min_version': minVersion,
        'force_update': forceUpdate,
        'update_message': updateMessage,
      };

  static KoolbaseVersionPolicy empty() => const KoolbaseVersionPolicy(
        latestVersion: '',
        minVersion: '',
        forceUpdate: false,
        updateMessage: '',
      );
}

/// Result of a version check.
enum VersionStatus { upToDate, softUpdate, forceUpdate }

class VersionCheckResult {
  final VersionStatus status;
  final String message;
  final String latestVersion;

  const VersionCheckResult({
    required this.status,
    required this.message,
    required this.latestVersion,
  });
}
