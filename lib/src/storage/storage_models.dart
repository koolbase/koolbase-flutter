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
  /// Optional [transform] applies Cloudflare Image Transformations to the
  /// returned URL via the `/cdn-cgi/image/<OPTIONS>/` URL prefix. Transforms
  /// are billed against the koolbase.com zone's monthly free allocation
  /// (5,000 unique transforms/month); each unique combination of `path` +
  /// options is cached and billed only once per calendar month.
  String? publicUrl(String bucketName, {KoolbaseImageTransform? transform}) {
    if (r2Bucket != 'koolbase-storage-public') return null;
    final encoded = path.split('/').map(Uri.encodeComponent).join('/');
    final opts = transform?.toCloudflareOptions() ?? '';
    if (opts.isEmpty) {
      return 'https://cdn.koolbase.com/$projectId/$bucketName/$encoded';
    }
    return 'https://cdn.koolbase.com/cdn-cgi/image/$opts/$projectId/$bucketName/$encoded';
  }

  /// Returns the named-preset CDN URL for this object, or `null` if the
  /// object isn't in the public R2 bucket.
  ///
  /// The named preset is resolved at the Cloudflare edge by the
  /// koolbase-cdn-worker: it looks up `preset:{project_id}:{preset_name}`
  /// in Workers KV, applies the stored transformation options, and serves
  /// the transformed image. Presets are managed in the dashboard under
  /// Storage → Presets.
  ///
  /// Unknown preset names yield a 404 at the edge — the URL itself always
  /// constructs successfully.
  String? publicUrlWithPreset(String bucketName, String presetName) {
    if (r2Bucket != 'koolbase-storage-public') return null;
    final encoded = path.split('/').map(Uri.encodeComponent).join('/');
    return 'https://cdn.koolbase.com/p/$projectId/$presetName/$bucketName/$encoded';
  }
}

class UploadResult {
  final KoolbaseObject object;
  final String downloadUrl;

  const UploadResult({required this.object, required this.downloadUrl});
}

/// Output format for image transformations served via Cloudflare's
/// `/cdn-cgi/image/` URL prefix. [auto] negotiates the best modern format
/// (typically `webp` or `avif`) based on the requesting browser's `Accept`
/// header; pin an explicit format only when you need deterministic output.
enum KoolbaseImageFormat { auto, webp, avif, jpeg, png }

/// Resize mode when both [KoolbaseImageTransform.width] and
/// [KoolbaseImageTransform.height] are specified. Maps 1:1 to Cloudflare's
/// `fit` parameter.
///
/// * [scaleDown] — never enlarge; fit inside the box.
/// * [contain]   — fit inside the box, may enlarge.
/// * [cover]     — fill the box (crop overflow). Default with `gravity=auto`.
/// * [crop]      — fill the box exactly, crop overflow without aspect lock.
/// * [pad]       — fit inside the box, pad with the background.
enum KoolbaseImageFit { scaleDown, contain, cover, crop, pad }

/// Anchor point when cropping. Use with [KoolbaseImageFit.cover] or
/// [KoolbaseImageFit.crop]. [auto] runs Cloudflare's saliency detection;
/// the others fix the anchor explicitly.
enum KoolbaseImageGravity {
  auto,
  center,
  top,
  bottom,
  left,
  right,
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
}

/// Image-transformation options for `KoolbaseStorageClient.publicUrl` and
/// `KoolbaseObject.publicUrl`. Each field maps to one Cloudflare Image
/// Transformations parameter; unset fields are omitted.
///
/// All numeric inputs are clamped silently to Cloudflare-supported ranges
/// (width/height 1–2000, quality 1–100, dpr 1–3) so a stray `width: 99999`
/// can't trigger error 9422 at the edge.
///
/// Example:
/// ```dart
/// final url = KoolbaseStorageClient.publicUrl(
///   projectId: pid, bucket: 'avatars', path: 'user.jpg',
///   transform: const KoolbaseImageTransform(
///     width: 400, height: 400,
///     format: KoolbaseImageFormat.webp,
///     quality: 80, fit: KoolbaseImageFit.cover,
///   ),
/// );
/// ```
class KoolbaseImageTransform {
  final int? width;
  final int? height;
  final KoolbaseImageFormat? format;
  final int? quality;
  final KoolbaseImageFit? fit;
  final int? dpr;
  final KoolbaseImageGravity? gravity;

  const KoolbaseImageTransform({
    this.width,
    this.height,
    this.format,
    this.quality,
    this.fit,
    this.dpr,
    this.gravity,
  });

  bool get isEmpty =>
      width == null &&
      height == null &&
      format == null &&
      quality == null &&
      fit == null &&
      dpr == null &&
      gravity == null;

  /// Serializes to Cloudflare's comma-separated key=value options segment,
  /// e.g. `width=400,format=webp,quality=80`. Returns an empty string when
  /// no fields are set — callers can use that to skip the `/cdn-cgi/image/`
  /// prefix entirely.
  String toCloudflareOptions() {
    if (isEmpty) return '';
    final parts = <String>[];
    if (width != null) parts.add('width=${_clamp(width!, 1, 2000)}');
    if (height != null) parts.add('height=${_clamp(height!, 1, 2000)}');
    if (format != null) parts.add('format=${_formatStr(format!)}');
    if (quality != null) parts.add('quality=${_clamp(quality!, 1, 100)}');
    if (fit != null) parts.add('fit=${_fitStr(fit!)}');
    if (dpr != null) parts.add('dpr=${_clamp(dpr!, 1, 3)}');
    if (gravity != null) parts.add('gravity=${_gravityStr(gravity!)}');
    return parts.join(',');
  }

  static int _clamp(int v, int min, int max) =>
      v < min ? min : (v > max ? max : v);

  static String _formatStr(KoolbaseImageFormat f) {
    switch (f) {
      case KoolbaseImageFormat.auto:
        return 'auto';
      case KoolbaseImageFormat.webp:
        return 'webp';
      case KoolbaseImageFormat.avif:
        return 'avif';
      case KoolbaseImageFormat.jpeg:
        return 'jpeg';
      case KoolbaseImageFormat.png:
        return 'png';
    }
  }

  static String _fitStr(KoolbaseImageFit f) {
    switch (f) {
      case KoolbaseImageFit.scaleDown:
        return 'scale-down';
      case KoolbaseImageFit.contain:
        return 'contain';
      case KoolbaseImageFit.cover:
        return 'cover';
      case KoolbaseImageFit.crop:
        return 'crop';
      case KoolbaseImageFit.pad:
        return 'pad';
    }
  }

  static String _gravityStr(KoolbaseImageGravity g) {
    switch (g) {
      case KoolbaseImageGravity.auto:
        return 'auto';
      case KoolbaseImageGravity.center:
        return 'center';
      case KoolbaseImageGravity.top:
        return 'top';
      case KoolbaseImageGravity.bottom:
        return 'bottom';
      case KoolbaseImageGravity.left:
        return 'left';
      case KoolbaseImageGravity.right:
        return 'right';
      case KoolbaseImageGravity.topLeft:
        return 'top-left';
      case KoolbaseImageGravity.topRight:
        return 'top-right';
      case KoolbaseImageGravity.bottomLeft:
        return 'bottom-left';
      case KoolbaseImageGravity.bottomRight:
        return 'bottom-right';
    }
  }
}
