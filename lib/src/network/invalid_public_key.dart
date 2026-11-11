import 'dart:convert';

import '../koolbase_exception.dart';

/// The refusal in a failed response's body, when it is a refused app key
/// (#169); null otherwise. For clients that read a status before a code.
/// The refusal in a failed response's body, when a Run preview's request was
/// refused (preview_not_live, preview_origin_mismatch); null otherwise.
KoolbasePreviewException? previewRefusalIn(String body) {
  try {
    final j = jsonDecode(body);
    if (j is Map) return KoolbasePreviewException.fromCode(j['code'] as String?);
  } catch (_) {}
  return null;
}

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
