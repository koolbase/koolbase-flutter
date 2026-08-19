import 'package:flutter_test/flutter_test.dart';
import 'package:koolbase_flutter/src/fiscal/fiscal_client.dart';

void main() {
  group('FiscalIntentResult.fromJson', () {
    test('fiscalized with certification (the receipt contract)', () {
      final r = FiscalIntentResult.fromJson({
        'intent_id': 'i1',
        'status': 'fiscalized',
        'numbers': {'INV': 502},
        'sealed_at': '2026-08-19T00:38:20.941192Z',
        'certification': {
          'ysdcregsig': 'XPJF-ZIY7-SMYW-YFDO',
          'ysdcrecnum': '1001-6318-NS13',
          'qr_code': 'https://verification.vat-gh.com?data=x',
        },
      });
      expect(r.isFiscalized, isTrue);
      expect(r.isPending, isFalse);
      expect(r.numbers, {'INV': 502});
      expect(r.certification?['ysdcregsig'], 'XPJF-ZIY7-SMYW-YFDO');
      expect(r.sealedAt, isNotNull);
    });

    test('blocked carries reason and NO numbers — blocked consumed nothing',
        () {
      final r = FiscalIntentResult.fromJson({
        'intent_id': 'i2',
        'status': 'blocked',
        'blocked_reason': 'credential_missing',
      });
      expect(r.status, FiscalStatus.blocked);
      expect(r.blockedReason, 'credential_missing');
      expect(r.numbers, isNull);
      expect(r.certification, isNull);
      expect(r.isFiscalized, isFalse);
      expect(r.isPending, isFalse);
    });

    test('pending: sealed numbers, no certification yet', () {
      final r = FiscalIntentResult.fromJson({
        'intent_id': 'i3',
        'status': 'queued',
        'numbers': {'INV': 503},
        'sealed_at': '2026-08-19T00:40:00Z',
      });
      expect(r.isPending, isTrue);
      expect(r.certification, isNull);
    });

    test('purchase-shaped: fiscalized WITHOUT certification is valid', () {
      final r = FiscalIntentResult.fromJson(
          {'intent_id': 'i4', 'status': 'fiscalized', 'numbers': {'INV': 504}});
      expect(r.isFiscalized, isTrue);
      expect(r.certification, isNull);
    });

    test('unknown status is forward-compatible, never a crash', () {
      final r = FiscalIntentResult.fromJson(
          {'intent_id': 'i5', 'status': 'some_future_state'});
      expect(r.status, FiscalStatus.unknown);
    });

    test('numbers coerce num -> int', () {
      final r = FiscalIntentResult.fromJson({
        'intent_id': 'i6',
        'status': 'queued',
        'numbers': {'INV': 502.0},
      });
      expect(r.numbers?['INV'], 502);
    });
  });

  group('decodeFiscalResponse', () {
    test('200 parses', () {
      final r = KoolbaseFiscalClient.decodeFiscalResponse(
          200, '{"intent_id":"x","status":"fiscalized"}');
      expect(r.isFiscalized, isTrue);
    });

    test('202 blocked is a RESULT, not an exception', () {
      final r = KoolbaseFiscalClient.decodeFiscalResponse(202,
          '{"intent_id":"x","status":"blocked","blocked_reason":"credential_missing"}');
      expect(r.status, FiscalStatus.blocked);
    });

    test('4xx throws FiscalException carrying the server message', () {
      expect(
        () => KoolbaseFiscalClient.decodeFiscalResponse(
            400, '{"error":"device not found"}'),
        throwsA(isA<FiscalException>()
            .having((e) => e.message, 'message', 'device not found')
            .having((e) => e.statusCode, 'statusCode', 400)),
      );
    });

    test('garbage body throws FiscalException, never a raw crash', () {
      expect(
        () => KoolbaseFiscalClient.decodeFiscalResponse(500, '<html>oops'),
        throwsA(isA<FiscalException>()),
      );
    });
  });
}
