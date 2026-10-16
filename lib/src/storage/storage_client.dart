import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../koolbase_exception.dart';
import 'storage_exceptions.dart';
import 'storage_models.dart';
import 'storage_transfer.dart';
import 'storage_files.dart';
import 'storage_multipart.dart';
import 'files_controller.dart' show koolbaseFilesChanged;
import 'dart:typed_data';
import '../network/session_client.dart';

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

  /// Supplies the project id learned from the bootstrap payload, or an
  /// empty string while identity has not yet arrived (see
  /// [KoolbaseStorageProjectIdentityException]).
  final String Function()? _projectIdProvider;

  /// Fire-and-forget nudge to refresh the bootstrap payload — called when
  /// [publicUrlFor] finds identity missing, so a transient startup failure
  /// heals within the session instead of waiting for the next scheduled
  /// refresh.
  final void Function()? _nudgeBootstrap;

  KoolbaseStorageClient({
    required this.baseUrl,
    required this.publicKey,
    Future<String?> Function()? accessTokenProvider,
    Future<void> Function()? onSessionExpired,
    String Function()? projectIdProvider,
    void Function()? nudgeBootstrap,
  })  : _accessTokenProvider = accessTokenProvider,
        _onSessionExpired = onSessionExpired,
        _projectIdProvider = projectIdProvider,
        _nudgeBootstrap = nudgeBootstrap;

  /// Builds the error for a failed response and clears the session when the
  /// credentials were refused, before the exception reaches the caller.
  Future<KoolbaseException> _error(
    http.Response res, {
    String fallbackMessage = 'Storage request failed',
  }) async {
    final err =
        koolbaseStorageErrorFromResponse(res, fallbackMessage: fallbackMessage);
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
  /// Pass [metadata] to attach key/value pairs (see [KoolbaseObject.metadata]);
  /// on the overwrite path it REPLACES any prior metadata. Use
  /// [updateMetadata] for post-upload merge changes.
  ///
  /// Pass [onProgress] to follow it: pending, uploading (bytes sent of
  /// total), verifying, then completed. To cancel an upload, use
  /// [startUpload], which returns a [KoolbaseUploadTask].
  Future<UploadResult> upload({
    required String bucket,
    required String path,
    required File file,
    String? contentType,
    Map<String, String>? metadata,
    bool overwrite = false,
    void Function(KoolbaseUploadProgress progress)? onProgress,
  }) async => uploadBytes(
        bucket: bucket,
        path: path,
        bytes: await file.readAsBytes(),
        contentType: contentType,
        metadata: metadata,
        overwrite: overwrite,
        onProgress: onProgress,
      );

  /// Upload a file's contents to a bucket: [upload] for a file with no
  /// path on disk -- what the web has, where a picked file is bytes. The
  /// same steps, rules and result as [upload]; the content type is
  /// inferred from [path] unless given.
  Future<UploadResult> uploadBytes({
    required String bucket,
    required String path,
    required List<int> bytes,
    String? contentType,
    Map<String, String>? metadata,
    bool overwrite = false,
    void Function(KoolbaseUploadProgress progress)? onProgress,
  }) {
    final task = startUpload(
      bucket: bucket,
      path: path,
      bytes: bytes,
      contentType: contentType,
      metadata: metadata,
      overwrite: overwrite,
    );
    if (onProgress != null) task.progress.listen(onProgress);
    return task.result;
  }

  /// Start an upload you can follow and cancel (S1).
  ///
  /// ```dart
  /// final task = Koolbase.storage.startUpload(bucket: 'posters', path: 'gig.png', bytes: bytes);
  /// task.progress.listen((p) => setState(() => percent = p.fraction));
  /// // ...
  /// task.cancel(); // before the server starts checking it
  /// final result = await task.result;
  /// ```
  ///
  /// The bytes go to a holding place and become the file only once the
  /// server has checked them (verifying): a refused upload -- too large,
  /// over the bucket's cap, refused by its rules -- never touches the file
  /// already at [path].
  KoolbaseUploadTask startUpload({
    required String bucket,
    required String path,
    required List<int> bytes,
    String? contentType,
    Map<String, String>? metadata,
    bool overwrite = false,
  }) {
    final mimeType = contentType ?? _inferContentType(path);
    return _listsReload(bucket, runUploadTask(bytes.length, (step) async {
      // Large files go in parts: resumable, each part retried (S3).
      if (bytes.length > multipartThreshold) {
        return _runInParts(step, bucket,
            path: path, bytes: bytes, contentType: mimeType, metadata: metadata, overwrite: overwrite);
      }
      // 1. An upload link, for this upload alone.
      final urlRes = await koolbaseHttp
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
          .timeout(const Duration(seconds: 15));
      if (urlRes.statusCode != 200) {
        throw await _error(urlRes, fallbackMessage: 'Failed to get upload URL');
      }
      final urlData = jsonDecode(urlRes.body) as Map<String, dynamic>;
      final uploadUrl = urlData['upload_url'] as String;
      final uploadId = urlData['upload_id'] as String?;

      // 2. The bytes, straight to storage, a chunk at a time.
      final putRes = await step.put(Uri.parse(uploadUrl), bytes, mimeType,
          timeout: Duration(seconds: 60 + bytes.length ~/ (32 * 1024)));
      if (putRes.statusCode != 200) {
        // R2 PUT errors don't follow the Koolbase error shape.
        throw KoolbaseStorageException(
          'Upload to storage failed: ${putRes.statusCode} ${String.fromCharCodes(putRes.bodyBytes.take(200))}',
          code: 'upload_failed',
        );
      }
      final etag = putRes.headers['etag'] ?? '';

      // 3. Verifying: the server checks the bytes and puts the file in
      // place. Past this point the upload is not cancelled.
      step.verifying();
      final confirmBody = <String, dynamic>{
        'bucket': bucket,
        'path': path,
        'size': bytes.length,
        'content_type': mimeType,
        'etag': etag,
        'overwrite': overwrite,
        if (uploadId != null) 'upload_id': uploadId,
        if (metadata != null) 'metadata': metadata,
      };
      final confirmRes = await koolbaseHttp
          .post(
            Uri.parse('$baseUrl/v1/sdk/storage/confirm'),
            headers: await _headers(),
            body: jsonEncode(confirmBody),
          )
          .timeout(const Duration(seconds: 60));
      if (confirmRes.statusCode != 201) {
        throw await _error(confirmRes, fallbackMessage: 'Failed to confirm upload');
      }
      final object = KoolbaseObject.fromJson(jsonDecode(confirmRes.body) as Map<String, dynamic>);

      // 4. A link to read it now.
      final downloadUrl = await getDownloadUrl(bucket: bucket, path: path);
      return UploadResult(object: object, downloadUrl: downloadUrl, bucket: bucket);
    }));
  }

  /// Files larger than this go up in parts (S3): each part retried on its
  /// own, the upload resumable for a day with [resumeUpload]. 16 MiB.
  static int multipartThreshold = 16 * 1024 * 1024;

  /// Resume a large file's upload that failed or was interrupted -- the
  /// network dropped, the app was closed -- sending only the parts that did
  /// not arrive (S3). [uploadId] is the failed task's
  /// [KoolbaseUploadTask.uploadId]; [bytes] must be the same file. Within a
  /// day of the upload beginning.
  ///
  /// ```dart
  /// final task = Koolbase.storage.startUpload(bucket: 'video', path: 'talk.mp4', bytes: bytes);
  /// // keep task.uploadId once it is set; after a restart:
  /// await Koolbase.storage.resumeUpload(bucket: 'video', uploadId: id, bytes: bytes).result;
  /// ```
  KoolbaseUploadTask resumeUpload({
    required String bucket,
    required String uploadId,
    required List<int> bytes,
    Map<String, String>? metadata,
    bool overwrite = false,
  }) =>
      _listsReload(bucket, runUploadTask(bytes.length, (step) => _runInParts(step, bucket,
          bytes: bytes, metadata: metadata, overwrite: overwrite, resumeId: uploadId)));

  /// [task], whose success reloads [bucket]'s file lists (S4).
  static KoolbaseUploadTask _listsReload(String bucket, KoolbaseUploadTask task) {
    task.result.then((_) => koolbaseFilesChanged([bucket]), onError: (Object _) {});
    return task;
  }

  Future<UploadResult> _runInParts(
    KoolbaseUploadTaskControl step,
    String bucket, {
    String? path,
    required List<int> bytes,
    String? contentType,
    Map<String, String>? metadata,
    required bool overwrite,
    String? resumeId,
  }) async {
    final base = '$baseUrl/v1/sdk/storage/uploads';
    final KoolbaseMultipartPlan plan;
    if (resumeId != null) {
      final res = await koolbaseHttp
          .get(Uri.parse(base).replace(queryParameters: {'bucket': bucket, 'upload_id': resumeId}), headers: await _headers())
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) {
        throw await _error(res, fallbackMessage: 'Failed to resume the upload');
      }
      plan = KoolbaseMultipartPlan.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
      if (plan.size != bytes.length) {
        throw KoolbaseStorageValidationException(
            'This is not the file the upload began with: it has ${bytes.length} bytes, the upload ${plan.size}');
      }
    } else {
      final res = await koolbaseHttp
          .post(Uri.parse(base),
              headers: await _headers(),
              body: jsonEncode({
                'bucket': bucket,
                'path': path,
                'content_type': contentType,
                'size': bytes.length,
                'overwrite': overwrite,
              }))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 201) {
        throw await _error(res, fallbackMessage: 'Failed to begin the upload');
      }
      plan = KoolbaseMultipartPlan.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
    }
    step.begun(plan.uploadId);
    step.checkCancelled();

    try {
      await koolbaseSendParts(step, plan, bytes, (parts) async {
        final res = await koolbaseHttp
            .post(Uri.parse('$base/parts'),
                headers: await _headers(),
                body: jsonEncode({'bucket': bucket, 'upload_id': plan.uploadId, 'parts': parts}))
            .timeout(const Duration(seconds: 15));
        if (res.statusCode != 200) {
          throw await _error(res, fallbackMessage: 'Failed to get upload links');
        }
        final links = (jsonDecode(res.body) as Map<String, dynamic>)['links'] as Map<String, dynamic>;
        return {for (final e in links.entries) int.parse(e.key): e.value as String};
      });
    } catch (_) {
      // A failure keeps the parts that arrived, for a resume; a cancel
      // abandons the upload.
      if (step.cancelled) {
        try {
          await koolbaseHttp
              .delete(Uri.parse(base),
                  headers: await _headers(), body: jsonEncode({'bucket': bucket, 'upload_id': plan.uploadId}))
              .timeout(const Duration(seconds: 15));
        } catch (_) {
          // The reaper abandons it within a day.
        }
        throw const KoolbaseUploadCancelledException();
      }
      rethrow;
    }

    // The parts have arrived: the server joins and checks them. No longer
    // cancellable.
    step.verifying();
    final done = await koolbaseHttp
        .post(Uri.parse('$base/complete'),
            headers: await _headers(),
            body: jsonEncode({
              'bucket': bucket,
              'upload_id': plan.uploadId,
              'overwrite': overwrite,
              if (metadata != null) 'metadata': metadata,
            }))
        .timeout(const Duration(seconds: 120));
    if (done.statusCode != 201) {
      throw await _error(done, fallbackMessage: 'Failed to complete the upload');
    }
    final object = KoolbaseObject.fromJson(jsonDecode(done.body) as Map<String, dynamic>);
    final downloadUrl = await getDownloadUrl(bucket: bucket, path: object.path);
    return UploadResult(object: object, downloadUrl: downloadUrl, bucket: bucket);
  }

  /// Download a file's bytes, reporting them as they arrive (S3):
  /// [onProgress] gets the bytes received and the total, null when the size
  /// is not known.
  Future<Uint8List> downloadBytes({
    required String bucket,
    required String path,
    String? versionId,
    void Function(int received, int? total)? onProgress,
  }) async {
    final url = await getDownloadUrl(bucket: bucket, path: path, versionId: versionId);
    final client = http.Client();
    try {
      final res = await client.send(http.Request('GET', Uri.parse(url))).timeout(const Duration(seconds: 30));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        await res.stream.drain<void>();
        throw KoolbaseStorageException('Download failed: ${res.statusCode}', code: 'download_failed');
      }
      final total = res.contentLength;
      final out = BytesBuilder(copy: false);
      onProgress?.call(0, total);
      await for (final chunk in res.stream) {
        out.add(chunk);
        onProgress?.call(out.length, total);
      }
      return out.takeBytes();
    } on KoolbaseStorageException {
      rethrow;
    } catch (e) {
      throw KoolbaseStorageNetworkException(e.toString());
    } finally {
      client.close();
    }
  }

  /// A page of the bucket's files you may view (S1).
  ///
  /// [prefix] keeps paths that start with it (a folder: `'events/'`).
  /// [limit] is at most 100 (default 50). Pass a page's
  /// [KoolbaseFilePage.nextCursor] as [cursor] for the next one, with the
  /// same [sort] and [descending]. Every file is checked against the
  /// bucket's view rule on the server: you get only what you may view.
  ///
  /// ```dart
  /// var page = await Koolbase.storage.listFiles(bucket: 'posters', sort: KoolbaseFileSort.createdAt, descending: true);
  /// while (page.hasMore) {
  ///   page = await Koolbase.storage.listFiles(bucket: 'posters', sort: KoolbaseFileSort.createdAt, descending: true, cursor: page.nextCursor);
  /// }
  /// ```
  Future<KoolbaseFilePage> listFiles({
    required String bucket,
    String? prefix,
    int? limit,
    String? cursor,
    KoolbaseFileSort sort = KoolbaseFileSort.path,
    bool descending = false,
  }) async {
    final uri = Uri.parse('$baseUrl/v1/sdk/storage/files').replace(
      queryParameters: koolbaseListQuery(
        bucket: bucket,
        prefix: prefix,
        limit: limit,
        cursor: cursor,
        sort: sort,
        descending: descending,
      ),
    );
    final res = await koolbaseHttp.get(uri, headers: await _headers()).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw await _error(res, fallbackMessage: 'Failed to list files');
    }
    return KoolbaseFilePage.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// One file's details, without downloading it (S1). Throws
  /// [KoolbaseStorageNotFoundException] when there is no such file or you
  /// may not view it -- the two are not told apart.
  Future<KoolbaseFileInfo> getFileInfo({
    required String bucket,
    required String path,
  }) async {
    final uri = Uri.parse('$baseUrl/v1/sdk/storage/file').replace(
      queryParameters: {'bucket': bucket, 'path': path},
    );
    final res = await koolbaseHttp.get(uri, headers: await _headers()).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      throw await _error(res, fallbackMessage: 'Failed to get file info');
    }
    return KoolbaseFileInfo.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Move a file to [to], in its bucket or into [toBucket] (S1b). Nothing
  /// is uploaded again. The bucket's rules decide: delete on the file, and
  /// upload at the destination, whose limits apply as to an upload. The
  /// destination must be free.
  ///
  /// Within one bucket the file keeps its kept versions. Refused with
  /// [KoolbaseStorageFileInUseException] while records point at the file:
  /// change them first, or [copy] it.
  Future<KoolbaseObject> move({
    required String bucket,
    required String from,
    required String to,
    String? toBucket,
  }) =>
      _transfer('move', bucket, from, to, toBucket);

  /// Copy a file to [to], in its bucket or into [toBucket] (S1b): a new
  /// file, the caller's, with the same bytes. The bucket's rules decide:
  /// view on the file, and upload at the destination.
  Future<KoolbaseObject> copy({
    required String bucket,
    required String from,
    required String to,
    String? toBucket,
  }) =>
      _transfer('copy', bucket, from, to, toBucket);

  Future<KoolbaseObject> _transfer(String op, String bucket, String from, String to, String? toBucket) async {
    final res = await koolbaseHttp
        .post(
          Uri.parse('$baseUrl/v1/sdk/storage/$op'),
          headers: await _headers(),
          body: jsonEncode({
            'bucket': bucket,
            'from': from,
            'to': to,
            if (toBucket != null && toBucket != bucket) 'to_bucket': toBucket,
          }),
        )
        .timeout(const Duration(seconds: 60));
    if (res.statusCode != 201) {
      throw await _error(res, fallbackMessage: op == 'move' ? 'Failed to move the file' : 'Failed to copy the file');
    }
    final moved = KoolbaseObject.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
    koolbaseFilesChanged({bucket, toBucket ?? bucket});
    return moved;
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
    final res = await koolbaseHttp
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

    final updated = KoolbaseObject.fromJson(
        jsonDecode(res.body) as Map<String, dynamic>);
    koolbaseFilesChanged([bucket]);
    return updated;
  }

  /// [route] with [query] encoded: a path is a person's file name, and an
  /// "&", "#", "+" or "%" in it must reach the server as itself (12.29.1).
  Uri _query(String route, Map<String, String> query) =>
      Uri.parse('$baseUrl$route').replace(queryParameters: query);

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
    final res = await koolbaseHttp
        .get(
          _query('/v1/sdk/storage/download-url', {
            'bucket': bucket,
            'path': path,
            if (versionId != null) 'version_id': versionId,
          }),
          headers: await _headers(),
        )
        .timeout(const Duration(seconds: 10));

    if (res.statusCode != 200) {
      throw await _error(res, fallbackMessage: 'Failed to get download URL');
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return data['url'] as String;
  }

  /// Build the stable public CDN URL for a file in a public bucket, using
  /// the project identity the SDK learned at bootstrap — the normal runtime
  /// form of [publicUrl], which needs no projectId argument.
  ///
  /// Throws [KoolbaseStorageProjectIdentityException] while identity is
  /// unavailable (first bootstrap has never completed — e.g. a fresh
  /// install starting offline). The throw also nudges a background
  /// bootstrap refresh, so a later call in the same session succeeds once
  /// connectivity returns. This is a DIFFERENT state from a null public
  /// URL on [KoolbaseObject.publicUrl]: null means the project is known
  /// and the object simply has no public URL (private bucket).
  String publicUrlFor({
    required String bucket,
    required String path,
    KoolbaseImageTransform? transform,
  }) {
    final pid = _projectIdProvider?.call() ?? '';
    if (pid.isEmpty) {
      _nudgeBootstrap?.call();
      throw const KoolbaseStorageProjectIdentityException();
    }
    return publicUrl(
      projectId: pid,
      bucket: bucket,
      path: path,
      transform: transform,
    );
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
    final res = await koolbaseHttp
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
    koolbaseFilesChanged([bucket]);
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
    final res = await koolbaseHttp
        .get(
          _query('/v1/sdk/storage/object-versions',
              {'bucket': bucket, 'path': path}),
          headers: await _headers(),
        )
        .timeout(const Duration(seconds: 10));

    if (res.statusCode != 200) {
      throw await _error(res, fallbackMessage: 'Failed to list versions');
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
    final res = await koolbaseHttp
        .get(
          _query('/v1/sdk/storage/object-versions/${Uri.encodeComponent(versionId)}',
              {'bucket': bucket, 'path': path}),
          headers: await _headers(),
        )
        .timeout(const Duration(seconds: 10));

    if (res.statusCode != 200) {
      throw await _error(res, fallbackMessage: 'Failed to fetch version');
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
    final res = await koolbaseHttp
        .post(
          _query('/v1/sdk/storage/object-versions/${Uri.encodeComponent(versionId)}/restore',
              {'bucket': bucket, 'path': path}),
          headers: await _headers(),
        )
        .timeout(const Duration(seconds: 10));

    if (res.statusCode != 200) {
      throw await _error(res,
          fallbackMessage: 'Failed to restore version');
    }
    final restored = KoolbaseObject.fromJson(
        jsonDecode(res.body) as Map<String, dynamic>);
    koolbaseFilesChanged([bucket]);
    return restored;
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
    final res = await koolbaseHttp
        .delete(
          _query('/v1/sdk/storage/object-versions/${Uri.encodeComponent(versionId)}',
              {'bucket': bucket, 'path': path}),
          headers: await _headers(),
        )
        .timeout(const Duration(seconds: 10));

    if (res.statusCode != 204) {
      throw await _error(res, fallbackMessage: 'Failed to purge version');
    }
  }
}
