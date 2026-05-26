import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
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
  Future<UploadResult> upload({
    required String bucket,
    required String path,
    required File file,
    String? contentType,
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
          }),
        )
        .timeout(const Duration(seconds: 10));

    if (urlRes.statusCode != 200) {
      final body = jsonDecode(urlRes.body) as Map<String, dynamic>;
      throw Exception(body['error'] ?? 'Failed to get upload URL');
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
      throw Exception('Upload to storage failed: ${uploadRes.statusCode}');
    }

    final etag = uploadRes.headers['etag'] ?? '';

    // Step 3: Confirm upload
    final confirmRes = await http
        .post(
          Uri.parse('$baseUrl/v1/sdk/storage/confirm'),
          headers: await _headers(),
          body: jsonEncode({
            'bucket': bucket,
            'path': path,
            'size': fileSize,
            'content_type': mimeType,
            'etag': etag,
          }),
        )
        .timeout(const Duration(seconds: 10));

    if (confirmRes.statusCode != 201) {
      final body = jsonDecode(confirmRes.body) as Map<String, dynamic>;
      throw Exception(body['error'] ?? 'Failed to confirm upload');
    }

    final object = KoolbaseObject.fromJson(
        jsonDecode(confirmRes.body) as Map<String, dynamic>);

    // Step 4: Get download URL
    final downloadUrl = await getDownloadUrl(bucket: bucket, path: path);

    return UploadResult(object: object, downloadUrl: downloadUrl);
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
      throw Exception('Failed to get download URL');
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return data['url'] as String;
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
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      throw Exception(body['error'] ?? 'Failed to delete file');
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
