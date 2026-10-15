import 'package:flutter_test/flutter_test.dart';
import 'package:koolbase_flutter/koolbase_flutter.dart';

// #107B: a write refused for its declared fields says which fields, and
// what each expects, so a form can show each under its own input.
void main() {
  Map<String, dynamic> refusal(List<Object?> fields) => {
        'code': 'validation_error',
        'error': 'title is required; seats must be a whole number',
        'details': {'field': 'title', 'fields': fields},
      };

  test('each field, its code and its problem', () {
    final err = koolbaseDataError(
        400,
        refusal([
          {'field': 'title', 'code': 'required', 'problem': 'is required'},
          {
            'field': 'seats',
            'code': 'whole_number',
            'problem': 'must be a whole number'
          },
        ]));
    expect(err, isA<KoolbaseValidationException>());
    final fields = (err as KoolbaseValidationException).fields;
    expect([for (final f in fields) '${f.field} ${f.code}'],
        ['title required', 'seats whole_number']);
    expect(fields.last.problem, 'must be a whole number');
    expect(err.code, 'validation_error');
  });

  test('an older server sends no code: the field still arrives', () {
    final err = koolbaseDataError(
        400,
        refusal([
          {'field': 'title', 'problem': 'is required'},
        ])) as KoolbaseValidationException;
    expect(err.fields.single.field, 'title');
    expect(err.fields.single.code, '');
  });

  test('what is not a field problem is skipped, never guessed at', () {
    final err = koolbaseDataError(
        400,
        refusal([
          'title',
          {'code': 'required'},
          {'field': '', 'code': 'required'},
          {'field': 'seats', 'code': 7},
        ])) as KoolbaseValidationException;
    expect([for (final f in err.fields) '${f.field}:${f.code}'], ['seats:']);
  });

  test('a refusal with no fields is as before', () {
    final err = koolbaseDataError(
        400, {'code': 'validation_error', 'error': 'bad body'});
    expect(err, isA<KoolbaseValidationException>());
    expect((err as KoolbaseValidationException).fields, isEmpty);
    expect(const KoolbaseValidationException().fields, isEmpty);
    expect(KoolbaseError.from(err).details, isNull);
  });

  test('KoolbaseError carries the fields and codes, never the English', () {
    final e = KoolbaseError.from(koolbaseDataError(
        400,
        refusal([
          {'field': 'title', 'code': 'required', 'problem': 'is required'},
          {
            'field': 'day',
            'code': 'date',
            'problem': 'must be a date, YYYY-MM-DD'
          },
        ])));
    expect(e.code, KoolbaseErrorCode.validation);
    expect(e.details, {
      'field': 'title',
      'fields': [
        {'field': 'title', 'code': 'required'},
        {'field': 'day', 'code': 'date'},
      ],
    });
  });
}
