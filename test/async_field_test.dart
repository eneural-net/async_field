import 'package:async_field/async_field.dart';
import 'package:test/test.dart';

void main() {
  group('AsyncField', () {
    setUp(() {});

    test('AsyncStorage basic', () async {
      var storage = AsyncStorage();

      var field = storage.getField<int>('a');

      expect(field, isNotNull);

      expect(identical(storage.getField('a'), field), isTrue);

      expect(field.isSet, isFalse);
      expect(field.value, isNull);

      expect(field.set(123).get(), equals(123));
      expect(field.isSet, isTrue);

      expect(field.value, equals(123));
      expect(await field.get(), equals(123));
    });

    test('AsyncStorage fetcher', () async {
      var storage = AsyncStorage();

      var field =
          storage.getField<int>('a').withFetcher((asyncField) => 123456);

      expect(field, isNotNull);

      expect(identical(storage.getField('a'), field), isTrue);

      expect(field.value, isNull);

      var changes = <int>[];

      field.onChange.listen((field) => changes.add(field.value!));

      expect(changes.isEmpty, isTrue);

      expect(await field.get(), equals(123456));
      expect(field.isSet, isTrue);

      expect(changes.isNotEmpty, isTrue);

      expect(field.value, equals(123456));

      expect(changes[0], equals(123456));
    });
  });
}
