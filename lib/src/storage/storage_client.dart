import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../koolbase_exception.dart';
import 'storage_exceptions.dart';
import 'storage_models.dart';

class KoolbaseStorageClient {
  final String baseUrl;
  final String publicKey;

  /// Pulls a currently-valid user access token per request (refresh-aware),
  /// so storage calls carry the logged-in user's identity automatically.
  final Future<String?> Function()? _accessTokenProvider;

  /// Called when the server rejects the caller's credentials.
  ///
  /// A session stops working for the whole SDK at once, not one subsystem at a
  /// time, so a 401 met during an upload has to clear it just as one met during
  /// a query does. Otherwise the app keeps believing it is signed in for every
  /// call that happens not to touch the database.
  final Future<void> Function()? _onSessionExpired;

  KoolbaseStorageClient({
    required this.baseUrl,
    required this.publicKey,
    Future<String?> Function()? accessTokenProvider,
    Future<void> Function()? onSessionExpired,
  })  : _accessTokenProvider = accessTokenProvider,
        _onSessionExpired = onSessionExpired;

  /// Builds the error for a failed response and clears the session when the
  /// credentials were refused, before the exception reaches the caller.
  Future<KoolbaseException> _error(
    http.Response res, {
    String fallbackMessage = 'Storage request failed',
  }) async {
    final err = koolbaseStorageErrorFromResponse(res, fallbackMessage: fallbackMessage);
    if (err is KoolbaseUnauthenticatedException) {
      await _onSessionExpired?.call();
    }
    return err;
  }

  Future<Map<String, String>> _headers() async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'x-api-key': publicKey,
    };
    final token = await _accessTokenProvider?.call();
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  /// Upload a file to a bucket. Returns the object metadata and a download URL.
  ///
  /// By default (`overwrite: false`), uploads to a path where an object
  /// already exists are **rejected** with a [KoolbaseStorageConflictException].
  /// Catch it to prompt the user, then retry with `overwrite: true` to
  /// replace the existing object — or with a different `path`.
  ///
  /// Set `overwrite: true` for true upsert semantics — silently replace
  /// any existing object at this path.
  ///
  /// Pass [metadata] to attach arbitrary user-defined key/value pairs to
  /// the object at confirm time. Subject to the limits documented on
  /// [KoolbaseObject.metadata]; violations throw
  /// [KoolbaseStorageMetadataInvalidException]. On the overwrite path the
  /// metadata REPLACES any prior metadata at this path (matches GCS
  /// semantics — a new upload at a path produces a new object, not a
  /// patch of the old). Use [updateMetadata] for post-upload merge
  /// changes.
  ///
  /// **Breaking change in v7.0.0**: the default flipped from silent
  /// overwrite (legacy behavior in v6.x and earlier) to safe-by-default
  /// (reject on conflict). If you previously relied on uploads overwriting
  /// silently, pass `overwrite: true` explicitly.
  Future<UploadResult> upload({
    required String bucket,
    required String path,
    required File file,
    String? contentType,
    Map<String, String>? metadata,
    bool overwrite = false,
  }) async {
    final mimeType = contentType ?? _inferContentType(path);
    final fileBytes = await file.readAsBytes();
    final fileSize = fileBytes.length;

    // Step 1: Get presigned upload URL
    final urlRes = await http
        .post(
          Uri.parse('$baseUrl/v1/sdk/storage/upload-url'),
          headers: await _headers(),
          body: jsonEncode({
            'bucket': bucket,
            'path': path,
            'content_type': mimeType,
            'overwrite': overwrite,
          }),
        )
        .timeout(const Duration(seconds: 10));

    if (urlRes.statusCode != 200) {
      throw await _error(urlRes,
          fallbackMessage: 'Failed to get upload URL');
    }

    final urlData = jsonDecode(urlRes.body) as Map<String, dynamic>;
    final uploadUrl = urlData['upload_url'] as String;

    // Step 2: Upload directly to R2
    final uploadRes = await http
        .put(
          Uri.parse(uploadUrl),
          headers: {'Content-Type': mimeType},
          body: fileBytes,
        )
        .timeout(const Duration(seconds: 60));

    if (uploadRes.statusCode != 200) {
      // R2 PUT errors don't follow the Koolbase error shape — surface
      // as a generic storage error rather than trying to decode a
      // Koolbase-shaped body that isn't there.
      throw KoolbaseStorageException(
        'Upload to storage failed: ${uploadRes.statusCode}',
      );
    }

    final etag = uploadRes.headers['etag'] ?? '';

    // Step 3: Confirm upload. Build the body conditionally so the
    // `metadata` field is only sent when the caller passed it — keeps
    // the wire shape clean for callers that don't care, and lets the
    // server's omitempty path treat absent as "no metadata."
    final confirmBody = <String, dynamic>{
      'bucket': bucket,
      'path': path,
      'size': fileSize,
      'content_type': mimeType,
      'etag': etag,
      'overwrite': overwrite,
    };
    if (metadata != null) {
      confirmBody['metadata'] = metadata;
    }

    final confirmRes = await http
        .post(
          Uri.parse('$baseUrl/v1/sdk/storage/confirm'),
          headers: await _headers(),
          body: jsonEncode(confirmBody),
        )
        .timeout(const Duration(seconds: 10));

    if (confirmRes.statusCode != 201) {
      throw await _error(confirmRes,
          fallbackMessage: 'Failed to confirm upload');
    }

    final object = KoolbaseObject.fromJson(
        jsonDecode(confirmRes.body) as Map<String, dynamic>);

    // Step 4: Get download URL
    final downloadUrl = await getDownloadUrl(bucket: bucket, path: path);

    return UploadResult(object: object, downloadUrl: downloadUrl);
  }

  /// Apply a partial metadata update to an existing object. Returns the
  /// post-update [KoolbaseObject] with the merged metadata.
  ///
  /// **Merge semantics** (mirrors the server's JSONB merge):
  ///
  ///   - Keys with a non-null string value are SET — added if missing,
  ///     replacing any existing value at the key otherwise.
  ///   - Keys with `null` are DELETED from the stored metadata.
  ///   - Keys ABSENT from [metadata] are untouched — pre-existing entries
  ///     for those keys remain unchanged.
  ///
  /// Validation runs server-side against the same rules as upload-time
  /// metadata; violations throw [KoolbaseStorageMetadataInvalidException]
  /// whose `detail` field names the failing key and rule. The check is
  /// performed against the projected post-merge state, so adding a key
  /// that would push the object past the 50-key or 8KB ceiling is
  /// rejected before the row is mutated.
  ///
  /// ```dart
  /// // Add a tag, update an existing key, and drop another in one call:
  /// final updated = await Koolbase.storage.updateMetadata(
  ///   bucket: 'photos',
  ///   path: 'sunset.jpg',
  ///   metadata: {
  ///     'category': 'landscape',  // SET or UPDATE
  ///     'tag':      'sunset',     // SET or UPDATE
  ///     'owner':    null,         // DELETE
  ///   },
  /// );
  /// print(updated.metadata);  // -> {category: landscape, tag: sunset}
  /// ```
  Future<KoolbaseObject> updateMetadata({
    required String bucket,
    required String path,
    required Map<String, String?> metadata,
  }) async {
    final res = await http
        .patch(
          Uri.parse('$baseUrl/v1/sdk/storage/objects/metadata'),
          headers: await _headers(),
          body: jsonEncode({
            'bucket': bucket,
            'path': path,
            'metadata': metadata,
          }),
        )
        .timeout(const Duration(seconds: 10));

    if (res.statusCode != 200) {
      throw await _error(res,
          fallbackMessage: 'Failed to update metadata');
    }

    return KoolbaseObject.fromJson(
        jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Get a signed download URL for a file
  /// Get a signed download URL for a file. Pass [versionId] to fetch a
  /// specific historical version's bytes; without it, returns a URL to
  /// the current version (existing behavior). On a public bucket the
  /// current-version URL is a CDN URL (long-lived, embeddable); history
  /// versions always return a presigned URL since the .versions/ prefix
  /// isn't routed through the CDN.
  Future<String> getDownloadUrl({
    required String bucket,
    required String path,
    String? versionId,
  }) async {
    final queryParts = <String>['bucket=$bucket', 'path=$path'];
    if (versionId != null) {
      queryParts.add('version_id=$versionId');
    }
    final res = await http
        .get(
          Uri.parse(
              '$baseUrl/v1/sdk/storage/download-url?${queryParts.join('&')}'),
          headers: await _headers(),
        )
        .timeout(const Duration(seconds: 10));

    if (res.statusCode != 200) {
      throw await _error(res,
          fallbackMessage: 'Failed to get download URL');
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return data['url'] as String;
  }

  /// Build the stable public CDN URL for a file in a public bucket.
  ///
  /// Returns the URL unconditionally — no check on whether the file
  /// exists or whether the bucket is actually public. Use when you
  /// know the file is in a public bucket and want the URL without a
  /// network round-trip (build-time URL generation, server-side
  /// rendering, batch image processing, etc.).
  ///
  /// For safer construction from an Object you already have, use
  /// [KoolbaseObject.publicUrl] — it checks the stored `r2_bucket`
  /// value and returns `null` when the object isn't actually in the
  /// public R2 bucket.
  /// Optional [transform] applies Cloudflare Image Transformations to the
  /// returned URL via the `/cdn-cgi/image/<OPTIONS>/` URL prefix. Transforms
  /// are billed against the koolbase.com zone's monthly free allocation
  /// (5,000 unique transforms/month); each unique combination of `path` +
  /// options is cached and billed only once per calendar month. The first
  /// 5,000 transforms each month are free; beyond that, new transforms
  /// return a 9422 from the edge until the next billing cycle.
  static String publicUrl({
    required String projectId,
    required String bucket,
    required String path,
    KoolbaseImageTransform? transform,
  }) {
    // Encode each path segment individually so slashes are preserved
    // while spaces, parens, hashes, and query characters are escaped.
    final encoded = path.split('/').map(Uri.encodeComponent).join('/');
    final opts = transform?.toCloudflareOptions() ?? '';
    if (opts.isEmpty) {
      return 'https://cdn.koolbase.com/$projectId/$bucket/$encoded';
    }
    return 'https://cdn.koolbase.com/cdn-cgi/image/$opts/$projectId/$bucket/$encoded';
  }

  /// Builds a named-preset CDN URL. The preset is resolved at the Cloudflare
  /// edge by the koolbase-cdn-worker, which looks up
  /// `preset:{project_id}:{preset_name}` in Workers KV and applies the
  /// stored transformation options. Presets are managed in the dashboard
  /// under Storage → Presets.
  ///
  /// Unknown preset names yield a 404 at the edge — the URL itself always
  /// constructs successfully without a network round-trip.
  ///
  /// For safer construction from an Object you already have, use
  /// [KoolbaseObject.publicUrlWithPreset] — it checks the stored `r2_bucket`
  /// value and returns `null` when the object isn't actually in the public
  /// R2 bucket.
  static String publicUrlWithPreset({
    required String projectId,
    required String presetName,
    required String bucket,
    required String path,
  }) {
    final encoded = path.split('/').map(Uri.encodeComponent).join('/');
    return 'https://cdn.koolbase.com/p/$projectId/$presetName/$bucket/$encoded';
  }

  /// Delete a file from a bucket. With [forcePurge] true on a versioned
  /// bucket, wipes the entire timeline — every history row, every
  /// .versions/ R2 key, the canonical R2 key, and the current row.
  /// Without the flag, versioned buckets soft-delete with a marker;
  /// non-versioned hard-delete in place.
  Future<void> delete({
    required String bucket,
    required String path,
    bool forcePurge = false,
  }) async {
    final url = forcePurge
        ? '$baseUrl/v1/sdk/storage/object?force_purge=true'
        : '$baseUrl/v1/sdk/storage/object';
    final res = await http
        .delete(
          Uri.parse(url),
          headers: await _headers(),
          body: jsonEncode({'bucket': bucket, 'path': path}),
        )
        .timeout(const Duration(seconds: 10));

    if (res.statusCode != 204) {
      throw await _error(res,
          fallbackMessage: 'Failed to delete file');
    }
  }

  String _inferContentType(String path) {
    final ext = path.split('.').last.toLowerCase();
    const types = {
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'gif': 'image/gif',
      'webp': 'image/webp',
      'pdf': 'application/pdf',
      'mp4': 'video/mp4',
      'mp3': 'audio/mpeg',
      'json': 'application/json',
      'txt': 'text/plain',
    };
    return types[ext] ?? 'application/octet-stream';
  }

  /// List all versions of a file path, newest-first. Returns a flat
  /// list mixing the current row (with [KoolbaseObjectVersion.isCurrent]
  /// true) and all history rows. Delete markers are included so callers
  /// can render the full timeline; filter client-side to hide them if
  /// the UI only wants restorable versions.
  ///
  /// Returns an empty list (not an error) when the path has no history
  /// and no current row.
  Future<List<KoolbaseObjectVersion>> listVersions({
    required String bucket,
    required String path,
  }) async {
    final res = await http
        .get(
          Uri.parse(
              '$baseUrl/v1/sdk/storage/object-versions?bucket=$bucket&path=$path'),
          headers: await _headers(),
        )
        .timeout(const Duration(seconds: 10));

    if (res.statusCode != 200) {
      throw await _error(res,
          fallbackMessage: 'Failed to list versions');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final list = (json['versions'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(KoolbaseObjectVersion.fromJson)
        .toList(growable: false);
    return list;
  }

  /// Fetch metadata for a single version by id. Works against both the
  /// current row and any history row — the response's [isCurrent] tells
  /// you which.
  Future<KoolbaseObjectVersion> getVersion({
    required String bucket,
    required String path,
    required String versionId,
  }) async {
    final res = await http
        .get(
          Uri.parse(
              '$baseUrl/v1/sdk/storage/object-versions/$versionId?bucket=$bucket&path=$path'),
          headers: await _headers(),
        )
        .timeout(const Duration(seconds: 10));

    if (res.statusCode != 200) {
      throw await _error(res,
          fallbackMessage: 'Failed to fetch version');
    }
    return KoolbaseObjectVersion.fromJson(
        jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Bring a history version back as the current version. The
  /// previously-current row (if any) is snapshotted into history first,
  /// so this operation is itself a versioned event you can undo. The
  /// restored row gets a freshly-minted version_id; the target stays in
  /// history at its original version_id.
  ///
  /// Throws if the bucket has versioning off, if the target is the
  /// already-current version, or if the target is a delete marker.
  Future<KoolbaseObject> restoreVersion({
    required String bucket,
    required String path,
    required String versionId,
  }) async {
    final res = await http
        .post(
          Uri.parse(
              '$baseUrl/v1/sdk/storage/object-versions/$versionId/restore?bucket=$bucket&path=$path'),
          headers: await _headers(),
        )
        .timeout(const Duration(seconds: 10));

    if (res.statusCode != 200) {
      throw await _error(res,
          fallbackMessage: 'Failed to restore version');
    }
    return KoolbaseObject.fromJson(
        jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Hard-remove a single history version — both the metadata row and
  /// the .versions/ R2 bytes (or just the row, for delete markers).
  /// Refuses to operate on the current version; use [delete] with
  /// `forcePurge: true` to wipe everything for a path.
  Future<void> purgeVersion({
    required String bucket,
    required String path,
    required String versionId,
  }) async {
    final res = await http
        .delete(
          Uri.parse(
              '$baseUrl/v1/sdk/storage/object-versions/$versionId?bucket=$bucket&path=$path'),
          headers: await _headers(),
        )
        .timeout(const Duration(seconds: 10));

    if (res.statusCode != 204) {
      throw await _error(res,
          fallbackMessage: 'Failed to purge version');
    }
  }
}
