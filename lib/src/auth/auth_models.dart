class KoolbaseUser {
  final String id;
  final String projectId;
  final String email;
  final String? phoneNumber;
  final bool phoneVerified;
  final String? fullName;
  final String? avatarUrl;
  final bool verified;
  final bool disabled;
  final DateTime? lastLoginAt;
  final Map<String, dynamic>? metadata;
  final DateTime createdAt;
  final DateTime updatedAt;

  const KoolbaseUser({
    required this.id,
    required this.projectId,
    required this.email,
    this.phoneNumber,
    this.phoneVerified = false,
    this.fullName,
    this.avatarUrl,
    required this.verified,
    required this.disabled,
    this.lastLoginAt,
    this.metadata,
    required this.createdAt,
    required this.updatedAt,
  });

  factory KoolbaseUser.fromJson(Map<String, dynamic> json) {
    return KoolbaseUser(
      id: json['id'] as String,
      projectId: json['project_id'] as String,
      email: (json['email'] as String?) ?? '',
      phoneNumber: json['phone_number'] as String?,
      phoneVerified: json['phone_verified'] as bool? ?? false,
      fullName: json['full_name'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      verified: json['verified'] as bool? ?? false,
      disabled: json['disabled'] as bool? ?? false,
      lastLoginAt: json['last_login_at'] != null
          ? DateTime.parse(json['last_login_at'] as String)
          : null,
      metadata: json['metadata'] != null
          ? Map<String, dynamic>.from(json['metadata'] as Map)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'project_id': projectId,
        'email': email,
        if (phoneNumber != null) 'phone_number': phoneNumber,
        'phone_verified': phoneVerified,
        'full_name': fullName,
        'avatar_url': avatarUrl,
        'verified': verified,
        'disabled': disabled,
        'last_login_at': lastLoginAt?.toIso8601String(),
        'metadata': metadata,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  KoolbaseUser copyWith({
    String? fullName,
    String? avatarUrl,
    bool? verified,
    String? phoneNumber,
    bool? phoneVerified,
    Map<String, dynamic>? metadata,
  }) {
    return KoolbaseUser(
      id: id,
      projectId: projectId,
      email: email,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      phoneVerified: phoneVerified ?? this.phoneVerified,
      fullName: fullName ?? this.fullName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      verified: verified ?? this.verified,
      disabled: disabled,
      lastLoginAt: lastLoginAt,
      metadata: metadata ?? this.metadata,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}

class AuthSession {
  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
  final KoolbaseUser user;

  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.user,
  });

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String,
      expiresAt: DateTime.parse(json['expires_at'] as String),
      user: KoolbaseUser.fromJson(json['user'] as Map<String, dynamic>),
    );
  }

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

/// Result of [KoolbaseAuthClient.sendOtp] — exposes the OTP expiry timestamp
/// so apps can show a "resend in N seconds" countdown.
class OtpSendResult {
  final DateTime expiresAt;

  const OtpSendResult({required this.expiresAt});

  factory OtpSendResult.fromJson(Map<String, dynamic> json) {
    return OtpSendResult(
      expiresAt: DateTime.parse(json['expires_at'] as String),
    );
  }
}

/// Result of [KoolbaseAuthClient.resendVerificationEmail].
///
/// [alreadyVerified] is true when the account is already verified — nothing
/// was sent, and [expiresAt]/[cooldownUntil] are null. Otherwise the
/// verification email was re-sent: [expiresAt] is the new link's expiry and
/// [cooldownUntil] is when another resend becomes allowed, for a
/// "resend in N seconds" countdown (mirrors [OtpSendResult]).
class ResendVerificationResult {
  final bool alreadyVerified;
  final DateTime? expiresAt;
  final DateTime? cooldownUntil;

  const ResendVerificationResult({
    required this.alreadyVerified,
    this.expiresAt,
    this.cooldownUntil,
  });

  factory ResendVerificationResult.fromJson(Map<String, dynamic> json) {
    return ResendVerificationResult(
      alreadyVerified: json['already_verified'] as bool? ?? false,
      expiresAt: json['expires_at'] != null
          ? DateTime.parse(json['expires_at'] as String)
          : null,
      cooldownUntil: json['cooldown_until'] != null
          ? DateTime.parse(json['cooldown_until'] as String)
          : null,
    );
  }
}

/// Result of [KoolbaseAuthClient.verifyOtp] — wraps the issued [AuthSession]
/// with [isNewUser] so apps can route first-time users to onboarding.
class PhoneVerifyResult {
  final AuthSession session;
  final bool isNewUser;

  const PhoneVerifyResult({required this.session, required this.isNewUser});

  factory PhoneVerifyResult.fromJson(Map<String, dynamic> json) {
    return PhoneVerifyResult(
      session: AuthSession.fromJson(json),
      isNewUser: json['is_new_user'] as bool? ?? false,
    );
  }
}

/// Apple's optional full-name structure returned only on a user's FIRST
/// Sign in with Apple. Both fields nullable; subsequent sign-ins omit
/// this entirely.
///
/// Pass to [KoolbaseAuthClient.signInWithApple] only on first sign-in.
/// The server persists at link time and ignores on subsequent sign-ins
/// (matches Apple's documented contract).
class AppleFullName {
  final String? givenName;
  final String? familyName;

  const AppleFullName({this.givenName, this.familyName});

  Map<String, dynamic> toJson() {
    final result = <String, dynamic>{};
    if (givenName != null && givenName!.isNotEmpty) {
      result['given_name'] = givenName;
    }
    if (familyName != null && familyName!.isNotEmpty) {
      result['family_name'] = familyName;
    }
    return result;
  }
}
