import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:koolbase_flutter/src/database/database_exceptions.dart';
import 'package:koolbase_flutter/src/functions/functions_models.dart';
import 'package:koolbase_flutter/src/koolbase_error.dart';
import 'package:koolbase_flutter/src/koolbase_exception.dart';
import 'package:koolbase_flutter/src/network/invalid_public_key.dart';
import 'package:koolbase_flutter/src/storage/storage_exceptions.dart';

// A Run preview the API would not serve (koolbase-preview.app): an ended
// preview, or another project's key. Both are 403s from the API's preview
// guard. Neither is the user's session: nothing signs out.
void main() {
  const ended = '{"code":"preview_not_live","error":"this preview has expired or was replaced; press Run again"}';
  const other = '{"code":"preview_origin_mismatch","error":"a preview can only call its own project"}';

  test('a data 403 for an ended preview says so and signs no one out', () async {
    var signedOut = false;
    final err = await koolbaseDataErrorNotifying(
      http.Response(ended, 403),
      onSessionExpired: () async => signedOut = true,
    );
    expect(err, isA<KoolbasePreviewException>());
    expect(err.code, 'preview_not_live');
    expect(err.message, kPreviewEndedMessage);
    expect(signedOut, isFalse);
  });

  test("another project's key is named as that", () {
    final err = koolbaseStorageError(403, {
      'code': 'preview_origin_mismatch',
      'error': 'a preview can only call its own project',
    });
    expect(err, isA<KoolbasePreviewException>());
    expect(err.message, kPreviewOtherProjectMessage);
  });

  test('a Function 403 from the guard is the preview, not a permission', () {
    expect(functionInvokeError(403, 'x', code: 'preview_not_live'),
        isA<KoolbasePreviewException>());
    expect(functionInvokeError(403, 'no'), isNot(isA<KoolbasePreviewException>()));
  });

  test('a body names the refusal, and only that', () {
    expect(previewRefusalIn(ended), isA<KoolbasePreviewException>());
    expect(previewRefusalIn(other)?.code, 'preview_origin_mismatch');
    expect(previewRefusalIn('{"code":"permission_denied"}'), isNull);
    expect(previewRefusalIn('not json'), isNull);
  });

  test('KoolbaseError files it under server, never unauthorized', () {
    final e = KoolbaseError.from(KoolbasePreviewException.fromCode('preview_not_live')!);
    expect(e.code, KoolbaseErrorCode.server);
    expect(e.rawCode, 'preview_not_live');
    expect(e.message, kPreviewEndedMessage);
  });
}
