@Timeout(Duration(seconds: 20))
library;

import 'package:async_field/async_field.dart';
import 'package:test/test.dart';

void main() {
  group('AsyncFieldID', () {
    test('from() returns the same instance for an AsyncFieldID', () {
      var id = AsyncFieldID('a');
      expect(identical(AsyncFieldID.from(id), id), isTrue);
    });

    test('deep equality and hashCode for collection keys', () {
      var k1 = AsyncFieldID({
        'a': [1, 2],
      });
      var k2 = AsyncFieldID({
        'a': [1, 2],
      });
      var k3 = AsyncFieldID({
        'a': [1, 3],
      });

      expect(k1, equals(k2));
      expect(k1.hashCode, equals(k2.hashCode));
      expect(k1, isNot(equals(k3)));
      expect(k1.keyAsJson, equals('{"a":[1,2]}'));
      expect(AsyncFieldID([1, 2, 3]).keyAsString, equals('[1, 2, 3]'));
    });

    test('collection keys resolve to the same field', () {
      var storage = AsyncStorage();
      var f1 = storage.getField<int>([1, 2]);
      var f2 = storage.getField<int>([1, 2]);
      expect(identical(f1, f2), isTrue);
      expect(storage.fieldsIDs, hasLength(1));
    });
  });

  group('AsyncField values', () {
    test('defaultValue is used while unset', () {
      var field = AsyncStorage().getField<int>('a');

      expect(field.valueAsString, equals('?'));
      expect(field.valueAsBool, isFalse);

      field.defaultValue = 7;

      expect(field.isSet, isFalse);
      expect(field.value, equals(7));
      expect(field.valueOrSlate, equals(7));
      expect(field.valueAsString, equals('7'));
      expect(field.valueAsInt, equals(7));
    });

    test('valueAsBool / getAsBool parsing', () async {
      var field = AsyncStorage().getField<Object>('b');

      var cases = <Object, bool>{
        true: true,
        false: false,
        'true': true,
        'FALSE': false,
        'No': false,
        'N': false,
        'null': false,
        '': false,
        ' 0 ': false,
        '-1': false,
        '2.5': true,
        'yes': true,
        0: false,
        3: true,
        -0.5: false,
      };

      for (var e in cases.entries) {
        await field.set(e.key);
        expect(field.valueAsBool, equals(e.value), reason: 'value: ${e.key}');
        expect(
          await field.getAsBool(),
          equals(e.value),
          reason: 'value: ${e.key}',
        );
      }
    });

    test('info uses the storage name when present', () async {
      var field = AsyncStorage('db').getField<int>('a');
      expect(field.info, equals('{ "id": "a" , "storage": db }'));
      expect(field.storage.toString(), startsWith('AsyncStorage{name: db, '));
    });

    test('save() without a value throws', () {
      var field = AsyncStorage().getField<int>('a');
      expect(() => field.save(), throwsStateError);
    });
  });

  group('AsyncField fetch/store', () {
    test('withFetcher/withSaver/withDeleter respect `overwrite`', () async {
      var field = AsyncStorage().getField<int>('a');

      field.withFetcher((_) => 1).withFetcher((_) => 2);
      expect(await field.refresh(), equals(1));
      field.withFetcher((_) => 3, overwrite: true);
      expect(await field.refresh(), equals(3));

      field.withSaver((_, v) => v * 10).withSaver((_, v) => v * 100);
      expect(await field.set(1), equals(10));
      field.withSaver((_, v) => v * 100, overwrite: true);
      expect(await field.set(1), equals(100));

      field.withDeleter((_) => false).withDeleter((_) => true);
      expect(await field.delete(), isFalse);
      field.withDeleter((_) => true, overwrite: true);
      expect(await field.delete(), isTrue);
    });

    test('async saver: value is the saver result', () async {
      var stored = <int>[];
      var field = AsyncStorage().getField<int>('a')
        ..withSaver(
          (_, v) => Future.microtask(() {
            stored.add(v);
            return v * 2;
          }),
        );

      var saves = <int>[];
      field.onSave.listen((f) => saves.add(f.value!));

      var ret = field.set(5);
      expect(ret, isA<Future<int>>());
      expect(field.value, equals(5));

      expect(await ret, equals(10));
      expect(field.value, equals(10));
      expect(stored, equals([5]));

      await pumpEventQueue();
      expect(saves, equals([10]));
    });

    test('get() returns the in-flight refresh', () async {
      var completer = Completer<int>();
      var field = AsyncStorage().getField<int>('a')
        ..withFetcher((_) => completer.future);

      await field.set(1);

      var refreshing = field.refresh();
      var getting = field.get();

      expect(field.isFetching, isTrue);
      expect(field.value, equals(1));

      completer.complete(2);

      expect(await refreshing, equals(2));
      expect(await getting, equals(2));
      expect(field.isFetching, isFalse);
      expect(field.value, equals(2));
    });

    test('async fetch error resets isFetching', () async {
      var field = AsyncStorage().getField<int>('a')
        ..withFetcher((_) => Future<int>.error(StateError('boom')));

      var ret = field.refresh();
      expect(field.isFetching, isTrue);

      await expectLater(ret, throwsStateError);
      expect(field.isFetching, isFalse);
      expect(field.isSet, isFalse);
    });

    test('onChangeFilter suppresses unchanged values', () async {
      var field = AsyncStorage().getField<int>('a')
        ..onChangeFilter = (prev, v) => prev != v;

      var changes = <int>[];
      field.onChange.listen((f) => changes.add(f.value!));

      await field.set(1);
      await field.set(1);
      await field.set(2);
      await pumpEventQueue();

      expect(changes, equals([1, 2]));
    });

    test(
      'default storage delete, deletedValue and disposeDeletedValue',
      () async {
        var field = AsyncStorage().getField<int>('a');

        var deletes = <int?>[];
        field.onDelete.listen((f) => deletes.add(f.deletedValue));

        await field.set(42);
        expect(await field.delete(), isTrue);
        expect(field.value, isNull);
        expect(field.isSetOrSlate, isFalse);
        expect(field.deletedValue, equals(42));

        await pumpEventQueue();
        expect(deletes, equals([42]));

        field.disposeDeletedValue();
        expect(field.deletedValue, isNull);
      },
    );

    test('a failed delete keeps the value', () async {
      var field = AsyncStorage().getField<int>('a')
        ..withDeleter((_) => Future.value(false));

      var deletes = 0;
      field.onDelete.listen((_) => deletes++);

      await field.set(1);
      expect(await field.delete(), isFalse);
      expect(field.value, equals(1));
      expect(field.deletedValue, isNull);

      await pumpEventQueue();
      expect(deletes, equals(0));
    });

    test('dispose removes the field from storage', () async {
      var storage = AsyncStorage();
      var field = storage.getField<int>('a');

      var disposes = 0;
      field.onDispose.listen((_) => disposes++);

      await field.set(1);
      expect(await field.dispose(), isTrue);
      expect(storage.fields, isEmpty);
      expect(await field.dispose(), isFalse);

      await pumpEventQueue();
      expect(disposes, equals(1));

      var field2 = storage.getField<int>('a');
      expect(identical(field2, field), isFalse);
      expect(field2.isSet, isFalse);
    });

    test('storage subclass provides fetch/save/delete', () async {
      var storage = _MapStorage({'a': 1});
      var field = storage.getField<int>('a');

      expect(field.canRefresh, isTrue);
      expect(await field.get(), equals(1));

      await field.set(2);
      expect(storage.data, equals({'a': 2}));

      expect(await field.delete(), isTrue);
      expect(storage.data, isEmpty);
      expect(await field.delete(), isFalse);
    });
  });

  group('AsyncField timeout and slate values', () {
    test('timeoutChecker forces a slate value', () async {
      var counter = 0;
      var field = AsyncStorage().getField<int>('a')
        ..withFetcher((_) => ++counter);

      await field.set(10);
      expect(field.isValid, isTrue);

      field.timeoutChecker = (_) => true;

      expect(field.isExpired, isTrue);
      expect(field.isValid, isFalse);
      expect(field.value, isNull);
      expect(field.isSlate, isTrue);
      expect(field.isSet, isFalse);
      expect(field.isSetOrSlate, isTrue);
      expect(field.valueOrSlate, equals(10));
      expect(field.valueOrSlateNoTimeoutCheck, equals(10));

      var slates = <int>[];
      expect(await field.get(onSlateValue: slates.add), equals(1));
      expect(slates, equals([10]));

      field.timeoutChecker = null;
      expect(field.isSlate, isFalse);
      expect(field.value, equals(1));
    });

    test('timeoutChecker returning null falls back to timeout', () async {
      bool? forced;
      var field = AsyncStorage().getField<int>('a')
        ..timeout = Duration(hours: 1)
        ..timeoutChecker = (_) => forced;

      await field.set(1);

      expect(field.isExpired, isFalse);
      expect(field.isValid, isTrue);
      expect(field.valueTimeUntilExpire, greaterThan(0));
      expect(
        field.valueTimeUntilExpire,
        lessThanOrEqualTo(Duration(hours: 1).inMilliseconds),
      );

      forced = true;
      expect(field.isExpired, isTrue);
      expect(field.isValid, isFalse);

      forced = false;
      field.timeout = null;
      expect(field.valueTimeUntilExpire, equals(0));
      expect(field.isExpired, isFalse);
    });

    test('deprecated isExpire mirrors isExpired', () async {
      var field = AsyncStorage().getField<int>('a');
      await field.set(1);

      // ignore: deprecated_member_use_from_same_package
      expect(field.isExpire, isFalse);

      field.timeoutChecker = (_) => true;
      // ignore: deprecated_member_use_from_same_package
      expect(field.isExpire, isTrue);
    });

    test('closed storage returns the slate value without fetching', () async {
      var counter = 0;
      var storage = AsyncStorage();
      var field = storage.getField<int>('a')..withFetcher((_) => ++counter);

      await field.set(10);
      field.timeoutChecker = (_) => true;
      storage.close();

      var slates = <int>[];
      expect(field.get(onSlateValue: slates.add), equals(10));
      expect(slates, isEmpty);
      expect(counter, equals(0));
    });

    test('closed storage with a nullable type returns null', () {
      var storage = AsyncStorage()..close();
      var field = storage.getField<int?>('a');

      expect(field.refresh(), isNull);
      expect(storage.fetch(field), isNull);
    });

    test('toDSXValue without auto-fetch', () {
      var field = AsyncStorage().getField<int>('a')
        ..defaultValue = -1
        ..dsxValueAllowAutoFetch = false;

      field.dsxValueAllowSlate = true;
      expect(field.toDSXValue(), equals(-1));

      field.dsxValueAllowSlate = false;
      expect(field.toDSXValue(), equals(-1));
    });

    test('periodicRefresh is rescheduled after a newer value', () async {
      var storage = AsyncStorage();
      var fetchTimes = <int>[];

      var field = storage.getField<int>('a')
        ..withFetcher((_) {
          fetchTimes.add(DateTime.now().millisecondsSinceEpoch);
          return fetchTimes.length;
        })
        ..periodicRefresh = Duration(milliseconds: 200);

      expect(await field.get(), equals(1));

      await Future.delayed(Duration(milliseconds: 100));

      var setAt = DateTime.now().millisecondsSinceEpoch;
      await field.set(-1);

      var refreshed = await field.onFetch.first.timeout(Duration(seconds: 5));

      // The first scheduled refresh (from the fetch) fires while the value
      // set above is still fresh, so it must be rescheduled instead of
      // refreshing.
      expect(fetchTimes, hasLength(greaterThanOrEqualTo(2)));
      expect(fetchTimes[1] - setAt, greaterThanOrEqualTo(190));
      expect(refreshed.value, isNot(equals(-1)));

      field.periodicRefresh = null;
      storage.close();
    });
  });

  group('AsyncStorage', () {
    test('fieldsTimeout applies to new fields', () {
      var storage = AsyncStorage();
      var before = storage.getField<int>('a');

      storage.fieldsTimeout = Duration(seconds: 5);
      var after = storage.getField<int>('b');

      expect(before.timeout, isNull);
      expect(after.timeout, equals(Duration(seconds: 5)));
      expect(after.hasTimeout, isTrue);
    });

    test('clear and reopen', () async {
      var storage = AsyncStorage();
      await storage.setField('a', 1);
      await storage.setField('b', 2);

      expect(storage.reopen(), isFalse);

      storage.close();
      expect(storage.reopen(clear: false), isTrue);
      expect(storage.getField<int>('a').value, equals(1));

      storage.close();
      expect(storage.reopen(), isTrue);
      expect(storage.getField<int>('a').isSet, isFalse);
      expect(storage.getField<int>('b').isSet, isFalse);
      expect(storage.fields, hasLength(2));
    });

    test('operator [] returns the field', () async {
      var storage = AsyncStorage();
      await storage.setField('x', 'v');
      expect(storage['x'].value, equals('v'));
    });
  });
}

class _MapStorage extends AsyncStorage {
  final Map<String, Object?> data;

  _MapStorage(this.data);

  @override
  bool get canFetch => true;

  @override
  FutureOr<T> fetch<T>(AsyncField<T> asyncField) =>
      data[asyncField.id.keyAsString] as T;

  @override
  FutureOr<T> save<T>(AsyncField<T> asyncField, T value) {
    data[asyncField.id.keyAsString] = value;
    return value;
  }

  @override
  FutureOr<bool> delete<T>(AsyncField<T> asyncField) =>
      data.remove(asyncField.id.keyAsString) != null;
}
