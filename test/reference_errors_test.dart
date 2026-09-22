import 'package:flutter_test/flutter_test.dart';
import 'package:koolbase_flutter/koolbase_flutter.dart';

// Reference fields are enforced by the database, so their violations can
// surface from any write — an insert, an update, an upsert, or a batch at
// commit. These map the server's four codes to catchable exceptions; without
// them an app's `on` clause silently never runs.
//
// The bodies here are what the API actually sends.

void main() {
  group('reference errors', () {
    test('reference_invalid is catchable', () {
      final e = koolbaseDataError(400, {
        'code': 'reference_invalid',
        'error': 'field "grant_id" points at record 3f2b… which does not exist',
      });
      expect(e, isA<KoolbaseReferenceInvalidException>());
      expect(e, isA<KoolbaseDataException>());
      expect((e as KoolbaseDataException).code, 'reference_invalid');
      expect(e.message, contains('grant_id'));
    });

    test('reference_in_use is catchable', () {
      final e = koolbaseDataError(409, {
        'code': 'reference_in_use',
        'error': 'record 8a1c… is still referenced by field "grant_id"',
      });
      expect(e, isA<KoolbaseReferenceInUseException>());
      expect((e as KoolbaseDataException).code, 'reference_in_use');
    });

    test('dangling_references carries the offending records', () {
      // The point of the code: the caller has to repair the data, so it needs
      // to know which records are wrong. Koolbase never repairs them.
      final e = koolbaseDataError(409, {
        'code': 'dangling_references',
        'error': 'existing records point at records that do not exist',
        'details': {
          'dangling': [
            {'record_id': 'rec_1', 'value': 'missing_1'},
            {'record_id': 'rec_2', 'value': 'missing_2'},
          ],
        },
      });
      expect(e, isA<KoolbaseDanglingReferencesException>());
      final d = e as KoolbaseDanglingReferencesException;
      expect(d.dangling, hasLength(2));
      expect(d.dangling.first.recordId, 'rec_1');
      expect(d.dangling.last.value, 'missing_2');
    });

    test('dangling_references with no details is still catchable', () {
      final e = koolbaseDataError(409, {
        'code': 'dangling_references',
        'error': 'nope',
      });
      expect(e, isA<KoolbaseDanglingReferencesException>());
      expect((e as KoolbaseDanglingReferencesException).dangling, isEmpty);
    });

    test('collection_referenced is catchable', () {
      final e = koolbaseDataError(409, {
        'code': 'collection_referenced',
        'error': 'another collection has a reference field pointing at this collection',
      });
      expect(e, isA<KoolbaseCollectionReferencedException>());
    });

    test('a reference error is not mistaken for a unique violation', () {
      // Both are 409s on a write; branching must still separate "this value
      // already exists" from "this record is still referenced".
      final e = koolbaseDataError(409, {
        'code': 'reference_in_use',
        'error': 'still referenced',
      });
      expect(e, isA<KoolbaseReferenceInUseException>());
      expect(e, isNot(isA<KoolbaseConflictException>()));
    });
  });
}
