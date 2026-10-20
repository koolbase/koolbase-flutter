import 'dart:convert';

import '../koolbase_exception.dart';

/// The refusal in a failed response's body, when it is a refused app key
/// (#169); null otherwise. For clients that read a status before a code.
KoolbaseInvalidPublicKeyException? invalidPublicKeyIn(String body) {
  try {
    final j = jsonDecode(body);
    if (j is Map && j['code'] == 'invalid_public_key') {
      final msg = j['error'];
      return KoolbaseInvalidPublicKeyException(
          msg is String && msg.isNotEmpty ? msg : kInvalidPublicKeyMessage);
    }
  } catch (_) {}
  return null;
}
