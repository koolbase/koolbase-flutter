import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:koolbase_flutter/koolbase_flutter.dart';

void main() {
  test('network errors carry a short, safe userMessage', () {
    final e = KoolbaseError.from(const SocketException('Connection refused'));
    expect(e.code, KoolbaseErrorCode.network);
    expect(e.userMessage, "We can't connect right now. Check your connection and try again.");
  });

  test('other errors leave the wording to the app', () {
    expect(KoolbaseError.from(Exception('x')).userMessage, isNull);
  });
}
