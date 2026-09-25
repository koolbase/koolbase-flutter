import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// The README's install line must match the version being released, so a
// release can't ship with a stale README.
void main() {
  test('README install line matches pubspec version', () {
    final version = RegExp(r'^version: (\S+)$', multiLine: true)
        .firstMatch(File('pubspec.yaml').readAsStringSync())!
        .group(1);
    final lines = RegExp(r'koolbase_flutter: \^(\S+)')
        .allMatches(File('README.md').readAsStringSync())
        .map((m) => m.group(1))
        .toList();
    expect(lines, isNotEmpty, reason: 'README has no install line');
    expect(lines, everyElement(version), reason: 'README says ^$lines, pubspec says $version');
  });
}
