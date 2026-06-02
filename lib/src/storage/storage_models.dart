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

  /// Name of the physical R2 bucket holding this object's bytes
  /// (Gap #2). `koolbase-storage-public` means the object has a stable
  /// CDN URL accessible via [publicUrl]; anything else (typically
  /// `koolbase-storage`) means the object is in private storage and
  /// must be fetched via [KoolbaseStorageClient.getDownloadUrl], which
  /// returns a short-lived presigned URL.
  final String r2Bucket;

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
    required this.r2Bucket,
    this.userId,
    required this.path,
    required this.size,
    this.contentType,
    this.metadata = const <String, String>{},
    required this.createdAt,
    required this.updatedAt,
  });

  factory KoolbaseObject.fromJson(Map<String, dynamic> json) {
    final rawMetadata = json['metadata'] as Map<String, dynamic>?;
    final metadata = rawMetadata == null
        ? const <String, String>{}
        : Map<String, String>.from(rawMetadata);

    return KoolbaseObject(
      id: json['id'] as String,
      projectId: json['project_id'] as String,
      bucketId: json['bucket_id'] as String,
      // Default to 'koolbase-storage' so older cached responses (or
      // any non-Koolbase JSON missing the field) decode to a safe
      // value rather than crashing. Matches the server's migration
      // default for the column.
      r2Bucket: json['r2_bucket'] as String? ?? 'koolbase-storage',
      userId: json['user_id'] as String?,
      path: json['path'] as String,
      size: json['size'] as int? ?? 0,
      contentType: json['content_type'] as String?,
      metadata: metadata,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  /// Returns the stable CDN URL for this object if its bytes physically
  /// live in the public R2 bucket, `null` otherwise.
  ///
  /// Returns `null` for:
  ///   - Files in private buckets (no public URL ever)
  ///   - Legacy files in public buckets whose bytes still live in the
  ///     private R2 bucket from before Gap #2 (no permanent URL until
  ///     they're re-uploaded)
  ///
  /// The bucket name must be supplied because [KoolbaseObject] carries
  /// only the bucket ID, not its name. Typically the caller already
  /// knows which bucket they queried.
  ///
  /// For unchecked URL construction (build-time scenarios where you
  /// have a project ID + bucket + path and want the URL pattern
  /// regardless), see [KoolbaseStorageClient.publicUrl].
  String? publicUrl(String bucketName) {
    if (r2Bucket != 'koolbase-storage-public') return null;
    final encoded = path.split('/').map(Uri.encodeComponent).join('/');
    return 'https://cdn.koolbase.com/$projectId/$bucketName/$encoded';
  }
}

class UploadResult {
  final KoolbaseObject object;
  final String downloadUrl;

  const UploadResult({required this.object, required this.downloadUrl});
}
