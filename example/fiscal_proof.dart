import 'package:koolbase_flutter/src/fiscal/fiscal_client.dart';

Future<void> main() async {
  final fiscal = KoolbaseFiscalClient(
    baseUrl: 'https://api.koolbase.com',
    publicKey: const String.fromEnvironment('PK_KEY'),
  );

  // Read the GRA-stamped ceremony invoice through the SDK.
  final r = await fiscal.status(
    deviceId: '7e8841d6-4ec4-4c34-b919-0733d08a6fd6',
    clientRef: 'GH-CEREMONY-001',
  );
  print('status:        ${r.status.name}');
  print('fiscalized:    ${r.isFiscalized}');
  print('numbers:       ${r.numbers}');
  print('signature:     ${r.certification?['ysdcregsig']}');
  print('receipt:       ${r.certification?['ysdcrecnum']}');
  print('qr present:    ${(r.certification?['qr_code'] as String?)?.isNotEmpty}');

  // And a fresh submit — the SDK's first stamped invoice.
  final s = await fiscal.submit(
    deviceId: '7e8841d6-4ec4-4c34-b919-0733d08a6fd6',
    clientRef: 'SDK-FIRST-001',
    payload: {
      'kind': 'INVOICE', 'currency': 'GHS', 'exchange_rate': '1.0',
      'user_name': 'Kofi Ghana', 'calculation_type': 'EXCLUSIVE',
      'total_vat': 675, 'total_levy': 225, 'total_amount': 4500,
      'total_excise_amount': 0, 'transaction_date': '2026-01-01',
      'business_partner_name': 'Ama Ghana (Cash Customer)',
      'business_partner_tin': 'C0000000000', 'sale_type': 'NORMAL',
      'discount_type': 'GENERAL', 'discount_amount': 0,
      'tax_type': 'STANDARD', 'reference': '', 'group_reference_id': '',
      'purchase_order_reference': '',
      'items': [
        {
          'item_code': 'ABT301', 'item_category': '', 'expire_date': '',
          'description': 'Abrokyire Ntomah', 'quantity': 45,
          'levy_a': 112.50, 'levy_b': 112.50, 'levy_d': 0, 'levy_e': 0,
          'discount_amount': 0, 'excise_amount': 0, 'batch_code': '',
          'unit_price': 100,
        }
      ],
    },
  );
  print('submit:        ${s.status.name}  numbers: ${s.numbers}');

  // Poll to fiscalized (the pending path a real POS walks).
  var polled = s;
  for (var i = 0; i < 10 && !polled.isFiscalized; i++) {
    await Future<void>.delayed(const Duration(seconds: 2));
    polled = await fiscal.status(
        deviceId: '7e8841d6-4ec4-4c34-b919-0733d08a6fd6',
        clientRef: 'SDK-FIRST-001');
  }
  print('final:         ${polled.status.name}');
  print('sdk signature: ${polled.certification?['ysdcregsig']}');
}
