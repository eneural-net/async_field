import 'package:async_field/async_field.dart';
import 'package:test/test.dart';

void main() {
  group('AsyncField', () {
    setUp(() {});

    test('AsyncFieldID', () async {
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
      expect(field.isValid, isFalse);

      expect(field.info, equals('{ "id": "a" , "storage": 1 }'));

      expect(field.set(123).get(), equals(123));
      expect(field.isSet, isTrue);
      expect(field.isValid, isTrue);

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

      var field = storage.getField<int>('a')
        ..withFetcher((asyncField) => 123456);

      expect(field, isNotNull);

      expect(identical(storage.getField('a'), field), isTrue);

      expect(field.value, isNull);

      var fetches = <int>[];
      field.onFetch.listen((field) => fetches.add(field.valueNoTimeoutCheck!));

      var changes = <int>[];
      field.onChange.listen((field) => changes.add(field.value!));

      expect(fetches, isEmpty);
      expect(changes, isEmpty);

      expect(await field.get(), equals(123456));
      expect(field.isSet, isTrue);

      expect(fetches.isNotEmpty, isTrue);
      expect(changes.isNotEmpty, isTrue);

      expect(field.value, equals(123456));

      expect(fetches, equals([123456]));
      expect(changes, equals([123456]));
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

      var saves = <int>[];
      field.onSave.listen((field) => saves.add(field.value!));

      var deletes = <int>[];
      field.onDelete.listen((field) => deletes.add(field.value!));

      var disposes = <int>[];
      field.onDispose.listen((field) => disposes.add(field.value!));

      expect(changes.isEmpty, isTrue);
      expect(saves.isEmpty, isTrue);
      expect(deletes.isEmpty, isTrue);
      expect(disposes.isEmpty, isTrue);

      expect(await field.get(), equals(100));
      expect(field.isSet, isTrue);

      expect(storedValue, equals([100]));

      expect(changes.isNotEmpty, isTrue);
      expect(saves.isEmpty, isTrue);

      expect(field.value, equals(100));

      expect(changes, equals([100]));

      field.set(200);

      expect(field.value, equals(200));

      await Future.delayed(Duration(milliseconds: 200));

      expect(changes, equals([100, 200]));
      expect(saves, equals([200]));
      expect(deletes, isEmpty);
      expect(disposes, isEmpty);

      expect(storedValue, equals([200]));

      var deleted = await field.delete();

      expect(deleted, isTrue);
      expect(storedValue, isEmpty);

      await Future.delayed(Duration(milliseconds: 200));

      expect(deletes, equals([200]));
      expect(disposes, equals([200]));
    });

    test('AsyncField timeout', () async {
      var storage = AsyncStorage();

      expect(storage.toString(), matches(RegExp(r'AsyncStorage\{id: \d+\}')));

      var storedValue = <int>[100];

      var field = storage.getField<int>('a')
        ..withFetcher((field) => ++storedValue[0])
        ..timeout = Duration(seconds: 2);

      expect(field, isNotNull);

      expect(identical(storage.getField('a'), field), isTrue);

      expect(field.isSet, isFalse);
      expect(field.value, isNull);
      expect(field.valueTimeMillisecondsSinceEpoch, isNull);
      expect(field.valueTime, isNull);
      expect(field.isValid, isFalse);

      expect(
          field.info,
          matches(
              RegExp(r'\{ "id": "a" , "timeout": 2000ms , "storage": \d+ \}')));

      expect(field.get(), equals(101));
      expect(field.isSet, isTrue);
      expect(field.value, equals(101));
      expect(field.valueTimeMillisecondsSinceEpoch, isNotNull);
      expect(field.valueTime, isNotNull);
      expect(field.isExpire, isFalse);
      expect(field.isValid, isTrue);

      expect(field.valueTimeUntilExpire > 100, isTrue);

      expect(field.valueNoTimeoutCheck, equals(101));

      var slateValues = <int>[];
      expect(field.get(onSlateValue: (v) => slateValues.add(v)), equals(101));

      expect(slateValues, equals([]));

      await Future.delayed(Duration(milliseconds: 2100));

      expect(field.valueNoTimeoutCheck, equals(101));

      expect(field.valueTimeUntilExpire <= 0, isTrue);

      expect(field.get(onSlateValue: (v) => slateValues.add(v)), equals(102));

      expect(slateValues, equals([101]));

      expect(await field.get(), equals(102));

      expect(
          field.info,
          matches(RegExp(
              r'\{ "value": 102 , "id": "a" , "valueTime": \d+ , "timeout": 2000ms , "storage": \d+ \}')));
    });
  });
}
