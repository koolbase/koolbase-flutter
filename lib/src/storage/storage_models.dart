class KoolbaseBucket {
  final String id;
  final String projectId;
  final String name;
  final bool public;
  final DateTime createdAt;

  const KoolbaseBucket({
    required this.id,
    required this.projectId,
    required this.name,
    required this.public,
    required this.createdAt,
  });

  factory KoolbaseBucket.fromJson(Map<String, dynamic> json) {
    return KoolbaseBucket(
      id: json['id'] as String,
      projectId: json['project_id'] as String,
      name: json['name'] as String,
      public: json['public'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class KoolbaseObject {
  final String id;
  final String projectId;
  final String bucketId;
  final String? userId;
  final String path;
  final int size;
  final String? contentType;

  /// User-defined key/value metadata attached to this object. Always
  /// non-null — empty when no metadata has been set (the server returns
  /// `{}` rather than null so SDK callers can treat this as a guaranteed
  /// map without nil checks). Set on upload via `upload(metadata: ...)`
  /// or mutated post-upload via `updateMetadata(...)`.
  ///
  /// Validation rules (enforced server-side; violations throw
  /// `KoolbaseStorageMetadataInvalidException`):
  ///   - ≤50 keys; keys 1–64 chars matching `[a-z0-9_]+`; values ≤1024
  ///     chars; total ≤8KB; leading underscore reserved.
  final Map<String, String> metadata;

  final DateTime createdAt;
  final DateTime updatedAt;

  const KoolbaseObject({
    required this.id,
    required this.projectId,
    required this.bucketId,
    this.userId,
    required this.path,
    required this.size,
    this.contentType,
    this.metadata = const <String, String>{},
    required this.createdAt,
    required this.updatedAt,
  });

  factory KoolbaseObject.fromJson(Map<String, dynamic> json) {
    // Defensive decode: the server always emits `metadata` as a (possibly
    // empty) object, but older / cached responses or non-Koolbase JSON
    // might be missing it or send null. Either way we want a typed empty
    // map rather than a runtime cast failure.
    final rawMetadata = json['metadata'] as Map<String, dynamic>?;
    final metadata = rawMetadata == null
        ? const <String, String>{}
        : Map<String, String>.from(rawMetadata);

    return KoolbaseObject(
      id: json['id'] as String,
      projectId: json['project_id'] as String,
      bucketId: json['bucket_id'] as String,
      userId: json['user_id'] as String?,
      path: json['path'] as String,
      size: json['size'] as int? ?? 0,
      contentType: json['content_type'] as String?,
      metadata: metadata,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}

class UploadResult {
  final KoolbaseObject object;
  final String downloadUrl;

  const UploadResult({required this.object, required this.downloadUrl});
}
