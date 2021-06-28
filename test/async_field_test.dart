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
      expect(field.valueTimeMillisecondsSinceEpoch, isNull);
      expect(field.valueTime, isNull);

      expect(field.info, equals('{ "id": "a" , "storage": 1 }'));

      expect(field.set(123).get(), equals(123));
      expect(field.isSet, isTrue);

      expect(field.value, equals(123));
      expect(field.valueTimeMillisecondsSinceEpoch, isNotNull);
      expect(field.valueTime, isNotNull);

      expect(await field.get(), equals(123));
      expect(await field.getAsString(), equals('123'));
      expect(await field.getAsDouble(), equals(123.0));
      expect(await field.getAsInt(), equals(123));
      expect(await field.getAsBool(), equals(true));

      expect(field.valueAsString, equals('123'));
      expect(field.valueAsJson, equals('123'));
      expect(field.valueAsDouble, equals(123.0));
      expect(field.valueAsInt, equals(123));

      expect(
          field.info,
          matches(RegExp(
              r'\{ "value": 123 , "id": "a" , "valueTime": \d+ , "storage": 1 \}')));
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
