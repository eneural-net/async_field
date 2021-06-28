import 'package:async_field/async_field.dart';
import 'package:test/test.dart';

void main() {
  group('AsyncField', () {
    setUp(() {});

    test('AsyncStorage basic', () async {
      var k1 = AsyncFieldID.from([1, 2, 3]);
      var k2 = AsyncFieldID.from([1, 2, 3]);

      expect(k1 == k2, isTrue);

      expect(k1.equalsKey([1, 2, 3]), isTrue);
      expect(k1.equalsKey(k2.key), isTrue);

      expect(k1.toString(), equals('AsyncFieldID{key: [1, 2, 3]}'));
    });

    test('AsyncStorage basic', () async {
      var storage = AsyncStorage();

      expect(storage.toString(), equals('AsyncStorage{id: 1}'));

      var field = storage.getField<int>('a');

      expect(field, isNotNull);

      expect(identical(storage.getField('a'), field), isTrue);

      expect(storage.fieldsIDs.map((e) => e.keyAsString), equals(['a']));
      expect(storage.fieldsIDs.map((e) => e.keyAsJson), equals(['"a"']));

      expect(storage.fields.map((e) => e.idKey).contains(field.idKey), isTrue);
      expect(
          storage.fields.map((e) => e.idKeyAsJson).contains(field.idKeyAsJson),
          isTrue);

      expect(storage.fieldsIDs.map((e) => e.key).toList(), equals(['a']));

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
      expect(await field.getAsJson(), equals('123'));
      expect(await field.getAsDouble(), equals(123.0));
      expect(await field.getAsInt(), equals(123));
      expect(await field.getAsBool(), equals(true));

      expect(field.valueAsString, equals('123'));
      expect(field.valueAsJson, equals('123'));
      expect(field.valueAsJson, equals('123'));
      expect(field.valueAsDouble, equals(123.0));
      expect(field.valueAsInt, equals(123));
      expect(field.valueAsBool, isTrue);

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

    test('AsyncStorage fetcher/saver/deleter', () async {
      var storage = AsyncStorage();

      var storedValue = <int>[100];

      var field = storage.getField<int>('a')
        ..withFetcher((field) => storedValue[0])
        ..withSaver((field, val) => storedValue[0] = val)
        ..withDeleter((field) {
          storedValue.clear();
          return true;
        });

      expect(field, isNotNull);
      expect(identical(storage.getField('a'), field), isTrue);

      expect(field.value, isNull);

      var changes = <int>[];

      field.onChange.listen((field) => changes.add(field.value!));

      expect(changes.isEmpty, isTrue);

      expect(await field.get(), equals(100));
      expect(field.isSet, isTrue);

      expect(storedValue, equals([100]));

      expect(changes.isNotEmpty, isTrue);

      expect(field.value, equals(100));

      expect(changes, equals([100]));

      field.set(200);

      expect(field.value, equals(200));

      await Future.delayed(Duration(milliseconds: 200));

      expect(changes, equals([100, 200]));

      expect(storedValue, equals([200]));

      var deleted = await field.delete();

      expect(deleted, isTrue);

      expect(storedValue, isEmpty);
    });
  });
}
