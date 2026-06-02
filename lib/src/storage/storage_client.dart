import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'storage_exceptions.dart';
import 'storage_models.dart';

class KoolbaseStorageClient {
  final String baseUrl;
  final String publicKey;

  /// Pulls a currently-valid user access token per request (refresh-aware),
  /// so storage calls carry the logged-in user's identity automatically.
  final Future<String?> Function()? _accessTokenProvider;

  KoolbaseStorageClient({
    required this.baseUrl,
    required this.publicKey,
    Future<String?> Function()? accessTokenProvider,
  }) : _accessTokenProvider = accessTokenProvider;

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
      throw koolbaseStorageErrorFromResponse(urlRes,
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
      throw koolbaseStorageErrorFromResponse(confirmRes,
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
      throw koolbaseStorageErrorFromResponse(res,
          fallbackMessage: 'Failed to update metadata');
    }

    return KoolbaseObject.fromJson(
        jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Get a signed download URL for a file
  Future<String> getDownloadUrl({
    required String bucket,
    required String path,
  }) async {
    final res = await http
        .get(
          Uri.parse(
              '$baseUrl/v1/sdk/storage/download-url?bucket=$bucket&path=$path'),
          headers: await _headers(),
        )
        .timeout(const Duration(seconds: 10));

    if (res.statusCode != 200) {
      throw koolbaseStorageErrorFromResponse(res,
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
  static String publicUrl({
    required String projectId,
    required String bucket,
    required String path,
  }) {
    // Encode each path segment individually so slashes are preserved
    // while spaces, parens, hashes, and query characters are escaped.
    final encoded = path.split('/').map(Uri.encodeComponent).join('/');
    return 'https://cdn.koolbase.com/$projectId/$bucket/$encoded';
  }

  /// Delete a file from a bucket
  Future<void> delete({
    required String bucket,
    required String path,
  }) async {
    final res = await http
        .delete(
          Uri.parse('$baseUrl/v1/sdk/storage/object'),
          headers: await _headers(),
          body: jsonEncode({'bucket': bucket, 'path': path}),
        )
        .timeout(const Duration(seconds: 10));

    if (res.statusCode != 204) {
      throw koolbaseStorageErrorFromResponse(res,
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
}
