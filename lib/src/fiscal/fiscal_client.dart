import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../koolbase_exception.dart';
import 'fiscal_models.dart';

export 'fiscal_models.dart';

/// Client for Koolbase Fiscal — authority-grade sales recording with
/// jurisdiction adapters (Ghana GRA E-VAT live; kb-ref reference
/// adapter everywhere).
///
/// The contract in one paragraph: [submit] durably records the sale
/// and drives fiscalization; the SAME `clientRef` always refers to the
/// same intent, so retrying after a network failure is always safe and
/// never double-fiscalizes. Poll [status] until
/// [FiscalIntentResult.isFiscalized], then render the receipt with the
/// certification the authority granted.
///
/// Fiscal submissions deliberately do NOT ride the offline outbox: a
/// register needs a synchronous answer or an explicit pending state,
/// never silent queueing. Offline-first POS flows should record the
/// commercial sale locally (database module) and submit fiscally when
/// connectivity returns — the idempotent `clientRef` makes the replay
/// trivial.
class KoolbaseFiscalClient {
  final String baseUrl;
  final String publicKey;
  final Future<String?> Function()? _userAccessTokenProvider;

  /// Called when the server rejects the caller's credentials.
  final Future<void> Function()? _onSessionExpired;

  KoolbaseFiscalClient({
    required this.baseUrl,
    required this.publicKey,
    Future<String?> Function()? userAccessTokenProvider,
    Future<void> Function()? onSessionExpired,
  })  : _userAccessTokenProvider = userAccessTokenProvider,
        _onSessionExpired = onSessionExpired;

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

  /// Submit a sale (or refund, purchase record, ...) for fiscalization.
  ///
  /// [deviceId] is the fiscal device (register) identity from device
  /// onboarding. [clientRef] is YOUR durable reference for this
  /// transaction (e.g. the local sale id) — resubmitting the same ref
  /// returns the same intent, making retries always safe. [payload] is
  /// adapter-shaped; for Ghana (gh-gra) see the fiscal docs for the
  /// exact fields (kind, amounts, levies, items).
  ///
  /// Returns immediately with the intent's current state:
  /// - `fiscalized` with a certification when the authority answered
  ///   inside the synchronous window,
  /// - a pending status ([FiscalIntentResult.isPending]) when delivery
  ///   continues in the background — poll [status],
  /// - `blocked` with a reason when a precondition failed (nothing was
  ///   consumed; fix the cause and resubmit the same ref).
  Future<FiscalIntentResult> submit({
    required String deviceId,
    required String clientRef,
    required Map<String, dynamic> payload,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final uri = Uri.parse('$baseUrl/v1/sdk/fiscal/submit');
    final http.Response resp;
    try {
      resp = await http
          .post(uri,
              headers: await _sdkHeaders(),
              body: jsonEncode({
                'device_id': deviceId,
                'client_ref': clientRef,
                'payload': payload,
              }))
          .timeout(timeout);
    } on TimeoutException {
      throw const FiscalException(
          'fiscal submit timed out — the sale may still fiscalize; '
          'poll status with the same clientRef');
    }
    return _decode(resp);
  }

  /// Read an intent's current state by the reference you submitted it
  /// under. This is the receipt-rendering read: once
  /// [FiscalIntentResult.isFiscalized], the certification carries what
  /// the receipt must show (for Ghana: signature, receipt number, and
  /// the QR verification URL).
  Future<FiscalIntentResult> status({
    required String deviceId,
    required String clientRef,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final uri = Uri.parse('$baseUrl/v1/sdk/fiscal/status').replace(
        queryParameters: {'device_id': deviceId, 'client_ref': clientRef});
    final http.Response resp;
    try {
      resp = await http.get(uri, headers: await _sdkHeaders()).timeout(timeout);
    } on TimeoutException {
      throw const FiscalException('fiscal status timed out');
    }
    return _decode(resp);
  }

  Future<FiscalIntentResult> _decode(http.Response resp) async {
    if (resp.statusCode == 401 || resp.statusCode == 403) {
      await _onSessionExpired?.call();
      throw KoolbaseUnauthenticatedException(
          'fiscal: unauthenticated (${resp.statusCode})');
    }
    return decodeFiscalResponse(resp.statusCode, resp.body);
  }

  /// Response classification, separated for testability: status+body
  /// in, result or [FiscalException] out. Auth handling stays in
  /// [_decode] (it needs the session hook).
  static FiscalIntentResult decodeFiscalResponse(int statusCode, String body) {
    final Map<String, dynamic> parsed;
    try {
      parsed = jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      throw FiscalException('fiscal: unreadable response ($statusCode)',
          statusCode: statusCode);
    }
    if (statusCode >= 200 && statusCode < 300 || statusCode == 202) {
      return FiscalIntentResult.fromJson(parsed);
    }
    throw FiscalException(
        parsed['error'] as String? ?? 'fiscal: request failed',
        statusCode: statusCode);
  }
}
