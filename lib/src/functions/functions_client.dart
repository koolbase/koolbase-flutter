import 'dart:convert';
import 'package:http/http.dart' as http;
import 'functions_models.dart';
export 'functions_models.dart';

/// Supported function runtimes.
enum FunctionRuntime {
  /// TypeScript/JavaScript via Deno (default)
  deno,

  /// Dart runtime
  dart,
}

extension FunctionRuntimeExtension on FunctionRuntime {
  String get value {
    switch (this) {
      case FunctionRuntime.deno:
        return 'deno';
      case FunctionRuntime.dart:
        return 'dart';
    }
  }
}

/// Client for invoking Koolbase Functions from Flutter.
class KoolbaseFunctionsClient {
  final String baseUrl;
  final String publicKey;
  final Future<String?> Function()? _userAccessTokenProvider;
  String? _authToken;

  KoolbaseFunctionsClient({
    required this.baseUrl,
    required this.publicKey,
    Future<String?> Function()? userAccessTokenProvider,
  }) : _userAccessTokenProvider = userAccessTokenProvider;

  void setAuthToken(String? token) => _authToken = token;

  Future<Map<String, String>> _sdkHeaders() async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'x-api-key': publicKey,
    };
    final userToken = await _userAccessTokenProvider?.call();
    if (userToken != null && userToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $userToken';
    }
    return headers;
  }

  Map<String, String> get _authHeaders => {
        'Content-Type': 'application/json',
        if (_authToken != null) 'Authorization': 'Bearer $_authToken',
      };

  /// Invoke a deployed function by name.
  Future<FunctionInvokeResult> invoke(
    String name, {
    Map<String, dynamic>? body,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final uri = Uri.parse('$baseUrl/v1/sdk/functions/$name');
    try {
      final response = await http
          .post(
            uri,
            headers: await _sdkHeaders(),
            body: body != null ? jsonEncode({'body': body}) : '{"body":{}}',
          )
          .timeout(timeout);

      final raw = response.body;
      Map<String, dynamic>? data;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          data = decoded;
        }
      } catch (_) {}

      final success = response.statusCode >= 200 && response.statusCode < 300;
      if (!success) {
        final message =
            data?['error'] as String? ?? 'Function invocation failed';
        throw FunctionInvokeException(message, statusCode: response.statusCode);
      }

      return FunctionInvokeResult(
        statusCode: response.statusCode,
        data: data,
        raw: raw,
        success: success,
      );
    } on FunctionInvokeException {
      rethrow;
    } catch (e) {
      throw FunctionInvokeException('Network error: $e');
    }
  }

  /// Deploy a function from within a Flutter app.
  ///
  /// Requires a valid auth token — call after the user is logged in.
  ///
  /// [name] — function name (lowercase, letters, numbers, hyphens, underscores)
  /// [code] — the function source code
  /// [runtime] — [FunctionRuntime.deno] (TypeScript, default) or [FunctionRuntime.dart]
  /// [timeoutMs] — execution timeout in milliseconds (max 30000)
  ///
  /// Example — deploy a Dart function:
  /// ```dart
  /// await Koolbase.functions.deploy(
  ///   projectId: 'your-project-id',
  ///   name: 'send-welcome-email',
  ///   runtime: FunctionRuntime.dart,
  ///   code: '''
  ///     Future<Map<String, dynamic>> handler(Map<String, dynamic> ctx) async {
  ///       final email = ctx['request']['body']['email'];
  ///       return {'sent': true, 'to': email};
  ///     }
  ///   ''',
  /// );
  /// ```
  Future<Map<String, dynamic>> deploy({
    required String projectId,
    required String name,
    required String code,
    FunctionRuntime runtime = FunctionRuntime.deno,
    int timeoutMs = 10000,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (_authToken == null) {
      throw const FunctionInvokeException(
          'Auth token required — call Koolbase.auth.login() first');
    }

    final uri = Uri.parse('$baseUrl/v1/projects/$projectId/functions');
    try {
      final response = await http
          .post(
            uri,
            headers: _authHeaders,
            body: jsonEncode({
              'name': name,
              'code': code,
              'runtime': runtime.value,
              'timeout_ms': timeoutMs,
            }),
          )
          .timeout(timeout);

      final raw = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode != 201) {
        throw FunctionInvokeException(
          raw['error'] as String? ?? 'Deploy failed',
          statusCode: response.statusCode,
        );
      }

      return raw;
    } on FunctionInvokeException {
      rethrow;
    } catch (e) {
      throw FunctionInvokeException('Network error: $e');
    }
  }
}
