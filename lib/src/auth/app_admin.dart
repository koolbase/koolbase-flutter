import 'auth_api.dart';

/// One person in the app, as an app admin sees them.
class KoolbaseMember {
  final String id;
  final String email;
  final String? fullName;
  final String? avatarUrl;

  /// `active`, `invited` (has not signed in yet) or `disabled`.
  final String status;

  /// An app admin. Admins cannot be disabled or have their roles changed
  /// from the app; only the project owner can, in the dashboard.
  final bool isAdmin;

  /// The person's roles: the claims the project marked as ones app admins
  /// can give. Other claims are never sent.
  final Map<String, Object?> roles;

  /// Pass back to [KoolbaseAppAdmin.setRoles] as `expectedVersion`, so a
  /// change made by someone else in between is refused, not overwritten.
  final int version;
  final DateTime joinedAt;
  final DateTime? lastSeenAt;

  const KoolbaseMember({
    required this.id,
    required this.email,
    this.fullName,
    this.avatarUrl,
    required this.status,
    required this.isAdmin,
    required this.roles,
    required this.version,
    required this.joinedAt,
    this.lastSeenAt,
  });

  bool get isActive => status == 'active';
  bool get isInvited => status == 'invited';
  bool get isDisabled => status == 'disabled';

  factory KoolbaseMember.fromJson(Map<String, dynamic> j) => KoolbaseMember(
        id: j['id'] as String,
        email: (j['email'] as String?) ?? '',
        fullName: j['full_name'] as String?,
        avatarUrl: j['avatar_url'] as String?,
        status: (j['status'] as String?) ?? 'active',
        isAdmin: (j['is_admin'] as bool?) ?? false,
        roles: Map<String, Object?>.from(
            (j['roles'] as Map<String, dynamic>?) ?? const {}),
        version: (j['version'] as num?)?.toInt() ?? 0,
        joinedAt: DateTime.parse(j['joined_at'] as String),
        lastSeenAt: j['last_seen_at'] is String
            ? DateTime.tryParse(j['last_seen_at'] as String)
            : null,
      );
}

/// A page of members, with the total across all pages.
class KoolbaseMemberPage {
  final List<KoolbaseMember> members;
  final int total;
  const KoolbaseMemberPage({required this.members, required this.total});

  factory KoolbaseMemberPage.fromJson(Map<String, dynamic> j) =>
      KoolbaseMemberPage(
        members: [
          for (final m in (j['members'] as List<dynamic>? ?? const []))
            KoolbaseMember.fromJson(m as Map<String, dynamic>),
        ],
        total: (j['total'] as num?)?.toInt() ?? 0,
      );
}

/// A role an app admin may give, with how many people hold it.
class KoolbaseAssignableRole {
  final String key;

  /// `string`, `boolean`, `number`, `string_array`, ...
  final String valueType;

  /// The only values allowed, when the project limited them; empty otherwise.
  final List<String> allowedValues;
  final String? description;

  /// How many people hold this role.
  final int holders;

  /// For each value, how many people hold it.
  final Map<String, int> values;

  const KoolbaseAssignableRole({
    required this.key,
    required this.valueType,
    required this.allowedValues,
    this.description,
    required this.holders,
    required this.values,
  });

  factory KoolbaseAssignableRole.fromJson(Map<String, dynamic> j) =>
      KoolbaseAssignableRole(
        key: j['key'] as String,
        valueType: (j['value_type'] as String?) ?? 'string',
        allowedValues: [
          for (final v in (j['allowed_values'] as List<dynamic>? ?? const []))
            v.toString(),
        ],
        description: j['description'] as String?,
        holders: (j['holders'] as num?)?.toInt() ?? 0,
        values: {
          for (final e
              in ((j['values'] as Map<String, dynamic>?) ?? const {}).entries)
            e.key: (e.value as num).toInt(),
        },
      );
}

/// What [KoolbaseAppAdmin.setRoles] leaves: the person's roles now, and the
/// version to pass next time.
class KoolbaseMemberRoles {
  final String id;
  final Map<String, Object?> roles;
  final int version;
  const KoolbaseMemberRoles(
      {required this.id, required this.roles, required this.version});

  factory KoolbaseMemberRoles.fromJson(Map<String, dynamic> j) =>
      KoolbaseMemberRoles(
        id: j['id'] as String,
        roles: Map<String, Object?>.from(
            (j['roles'] as Map<String, dynamic>?) ?? const {}),
        version: (j['version'] as num?)?.toInt() ?? 0,
      );
}

/// Managing the app's people from inside the app, for its own admins.
///
/// Only a signed-in person whose `app_admin` claim is true may use these;
/// the project owner gives that claim in the dashboard. Everyone else gets
/// [NotAppAdminException]. The server checks on every request, so taking
/// the claim away takes effect at once.
///
/// When the admin has two-step sign-in on, disabling, enabling and changing
/// roles need it confirmed in the last ten minutes: catch
/// [RecentMfaRequiredException], call `stepUpMfa`, and try again.
class KoolbaseAppAdmin {
  final AuthApi _api;
  final Future<String> Function() _token;

  /// Reached through `Koolbase.auth.admin`; not built by apps.
  KoolbaseAppAdmin(this._api, this._token);

  /// The app's people, newest first. [query] matches email or name.
  /// [limit] is capped by the server.
  Future<KoolbaseMemberPage> members(
          {String? query, int? limit, int? offset}) async =>
      _api.adminListMembers(await _token(),
          query: query, limit: limit, offset: offset);

  /// The roles admins may give, for a role picker.
  Future<List<KoolbaseAssignableRole>> roles() async =>
      _api.adminRoles(await _token());

  /// Invite someone by email. They get an email to set up their account.
  /// [roles] are given at once. Throws [MemberExistsException] when the
  /// email already has an account.
  Future<KoolbaseMember> invite({
    required String email,
    String? fullName,
    Map<String, Object?>? roles,
  }) async =>
      _api.adminInvite(await _token(),
          email: email, fullName: fullName, roles: roles);

  /// Stop someone signing in, and sign them out everywhere.
  Future<void> disable(String userId) async =>
      _api.adminSetDisabled(await _token(), userId, disabled: true);

  /// Let a disabled person sign in again.
  Future<void> enable(String userId) async =>
      _api.adminSetDisabled(await _token(), userId, disabled: false);

  /// Change someone's roles. Only the keys given change; `null` removes a
  /// role. Pass the [KoolbaseMember.version] you read: when someone else
  /// changed them since, this throws [ClaimsVersionConflictException]
  /// carrying the new version, and nothing is changed.
  Future<KoolbaseMemberRoles> setRoles(
    String userId,
    Map<String, Object?> roles, {
    required int expectedVersion,
  }) async =>
      _api.adminSetRoles(await _token(), userId,
          roles: roles, expectedVersion: expectedVersion);
}
