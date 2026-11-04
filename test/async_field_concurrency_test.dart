@Timeout(Duration(seconds: 20))
library;

import 'package:async_field/async_field.dart';
import 'package:test/test.dart';

/// Expiry flag driven by the test, so timeouts are deterministic and need no
/// sleeps: `timeoutChecker` reads it instead of the wall clock.
class _Expiry {
  bool expired = false;

  bool? call(AsyncField _) => expired;
}

/// A storage whose `fetch` is asynchronous and gated by a [Completer] per
/// field, recording every fetch.
class _GatedStorage extends AsyncStorage {
  final Map<String, int> fetchCounts = {};
  final Map<String, Completer<int>> gates = {};

  @override
  bool get canFetch => true;

  @override
  FutureOr<T> fetch<T>(AsyncField<T> asyncField) {
    var key = asyncField.id.keyAsString;
    fetchCounts[key] = (fetchCounts[key] ?? 0) + 1;
    var gate = gates[key] = Completer<int>();
    return gate.future.then((v) => v as T);
  }

  void completeAll(int Function(String key) valueOf) {
    for (var e in gates.entries) {
      if (!e.value.isCompleted) e.value.complete(valueOf(e.key));
    }
  }
}

void main() {
  group('Concurrent fetch', () {
    test(
      'many concurrent get()/refresh() on an unset field fetch once',
      () async {
        var fetches = 0;
        var completer = Completer<int>();
        var field = AsyncStorage().getField<int>('a')
          ..withFetcher((_) {
            fetches++;
            return completer.future;
          });

        var fetchEvents = 0;
        var changeEvents = 0;
        field.onFetch.listen((_) => fetchEvents++);
        field.onChange.listen((_) => changeEvents++);

        var calls = <FutureOr<int>>[
          for (var i = 0; i < 50; i++) i.isEven ? field.get() : field.refresh(),
        ];

        expect(fetches, equals(1));
        expect(field.isFetching, isTrue);
        expect(field.isSet, isFalse);
        expect(calls.every((c) => c is Future<int>), isTrue);

        completer.complete(7);

        expect(await Future.wait(calls.map((c) async => c)), everyElement(7));
        expect(fetches, equals(1));
        expect(field.isFetching, isFalse);
        expect(field.value, equals(7));

        await pumpEventQueue();
        expect(fetchEvents, equals(1));
        expect(changeEvents, equals(1));

        // Once the value is set, get() no longer fetches; refresh() does.
        expect(field.get(), equals(7));
        expect(fetches, equals(1));

        completer = Completer<int>();
        var refreshing = field.refresh();
        expect(fetches, equals(2));
        completer.complete(8);
        expect(await refreshing, equals(8));
      },
    );

    test('an async fetch error fails every concurrent caller', () async {
      var fetches = 0;
      var completer = Completer<int>();
      var field = AsyncStorage().getField<int>('a')
        ..withFetcher((_) {
          fetches++;
          return completer.future;
        });

      var changes = 0;
      field.onChange.listen((_) => changes++);

      var calls = [for (var i = 0; i < 10; i++) field.get()];
      expect(fetches, equals(1));

      completer.completeError(StateError('down'));

      for (var c in calls) {
        await expectLater(c, throwsA(isA<StateError>()));
      }

      expect(field.isFetching, isFalse);
      expect(field.isSet, isFalse);
      expect(field.value, isNull);

      // The next get() starts a fresh fetch.
      completer = Completer<int>();
      var retry = field.get();
      expect(fetches, equals(2));
      completer.complete(3);
      expect(await retry, equals(3));

      await pumpEventQueue();
      expect(changes, equals(1));
    });

    test('a synchronous fetcher error leaves no fetch in flight', () async {
      var fail = true;
      var field = AsyncStorage().getField<int>('a')
        ..withFetcher((_) => fail ? throw StateError('sync') : 5);

      expect(() => field.refresh(), throwsStateError);
      expect(field.isFetching, isFalse);
      expect(field.isSet, isFalse);

      fail = false;
      expect(field.get(), equals(5));
    });

    test('get() on a set value returns the in-flight refresh', () async {
      var completer = Completer<int>();
      var field = AsyncStorage().getField<int>('a')
        ..withFetcher((_) => completer.future);

      await field.set(1);

      var refreshing = field.refresh();
      var slates = <int>[];
      var getting = field.get(onSlateValue: slates.add);

      // While the value is current, the in-flight future is returned and no
      // slate value is reported.
      expect(getting, isA<Future<int>>());
      expect(field.value, equals(1));

      completer.complete(2);
      expect(await refreshing, equals(2));
      expect(await getting, equals(2));
      expect(slates, isEmpty);
    });

    // Pins current behaviour: a fetch started before a local set() is not
    // cancelled, so its (older) result overwrites the newer local value when
    // it completes.
    test('a fetch in flight overwrites a value set meanwhile', () async {
      var completer = Completer<int>();
      var saved = <int>[];
      var field = AsyncStorage().getField<int>('a')
        ..withFetcher((_) => completer.future)
        ..withSaver((_, v) {
          saved.add(v);
          return v;
        });

      var fetching = field.refresh();

      expect(await field.set(99), equals(99));
      expect(field.value, equals(99));
      expect(saved, equals([99]));

      // The value is set, but a fetch is in flight: get() joins the fetch.
      var getting = field.get();

      completer.complete(1);

      expect(await fetching, equals(1));
      expect(await getting, equals(1));
      expect(field.value, equals(1));
      expect(saved, equals([99]));
    });
  });

  group('Saver interleavings', () {
    // Pins current behaviour: concurrent saves are not serialized; the value
    // is whatever the last *completed* save returned.
    test('the last completed save wins', () async {
      var gates = <int, Completer<int>>{};
      var field = AsyncStorage().getField<int>('a')
        ..withSaver((_, v) => (gates[v] = Completer<int>()).future);

      var changes = <int>[];
      field.onChange.listen((f) => changes.add(f.valueNoTimeoutCheck!));

      var s1 = field.set(1);
      var s2 = field.set(2);

      // set() applies the value locally right away.
      expect(field.value, equals(2));

      gates[2]!.complete(2);
      expect(await s2, equals(2));
      expect(field.value, equals(2));

      gates[1]!.complete(1);
      expect(await s1, equals(1));
      expect(field.value, equals(1));

      await pumpEventQueue();
      expect(changes, equals([2, 1]));
    });

    test('an async saver error keeps the local value unsaved', () async {
      var field = AsyncStorage().getField<int>('a')
        ..withSaver((_, v) => Future<int>.error(StateError('save failed')));

      var saves = 0;
      var changes = 0;
      field.onSave.listen((_) => saves++);
      field.onChange.listen((_) => changes++);

      await expectLater(field.set(5), throwsStateError);

      expect(field.value, equals(5));
      expect(field.isSet, isTrue);

      await pumpEventQueue();
      expect(saves, equals(0));
      expect(changes, equals(0));
    });

    test('a synchronous saver error is thrown by set()', () {
      var field = AsyncStorage().getField<int>('a')
        ..withSaver((_, v) => throw ArgumentError.value(v));

      expect(() => field.set(5), throwsArgumentError);
      expect(field.value, equals(5));
    });

    // Pins current behaviour: set() does not clear a slate value, so while an
    // async save of a new value over an expired one is in flight the field
    // still reports `isSlate`. The save completion clears it.
    test('set() over a slate value with an async saver', () async {
      var expiry = _Expiry();
      var completer = Completer<int>();
      var field = AsyncStorage().getField<int>('a')
        ..timeoutChecker = expiry.call;

      await field.set(1);
      expiry.expired = true;
      expect(field.value, isNull);
      expect(field.isSlate, isTrue);

      expiry.expired = false;
      field.withSaver((_, v) => completer.future);
      var saving = field.set(2);

      expect(field.value, equals(2));
      expect(field.valueOrSlate, equals(2));
      expect(field.isSlate, isTrue);
      expect(field.isSet, isFalse);

      completer.complete(2);
      expect(await saving, equals(2));
      expect(field.isSlate, isFalse);
      expect(field.isSet, isTrue);
    });

    test(
      'onChangeFilter receives the previous value of set and fetch',
      () async {
        var counter = 10;
        var pairs = <List<int?>>[];
        var field = AsyncStorage().getField<int>('a')
          ..withFetcher((_) => Future.microtask(() => ++counter))
          ..withSaver((_, v) => Future.microtask(() => v))
          ..onChangeFilter = (prev, v) {
            pairs.add([prev, v]);
            return prev != v;
          };

        var changes = <int>[];
        field.onChange.listen((f) => changes.add(f.valueNoTimeoutCheck!));

        await field.set(1);
        await field.refresh();
        await field.set(11);
        await field.set(12);

        expect(
          pairs,
          equals([
            [null, 1],
            [1, 11],
            [11, 11],
            [11, 12],
          ]),
        );

        await pumpEventQueue();
        expect(changes, equals([1, 11, 12]));
      },
    );
  });

  group('Event ordering', () {
    test('fetch, save, delete and dispose events', () async {
      var log = <String>[];
      var storage = AsyncStorage();
      var counter = 0;
      var field = storage.getField<int>('a')
        ..withFetcher((_) => Future.microtask(() => ++counter))
        ..withSaver((_, v) => Future.microtask(() => v * 10));

      field.onFetch.listen((f) => log.add('fetch:${f.valueNoTimeoutCheck}'));
      field.onSave.listen((f) => log.add('save:${f.valueNoTimeoutCheck}'));
      field.onChange.listen((f) => log.add('change:${f.valueNoTimeoutCheck}'));
      field.onDelete.listen((f) => log.add('delete:${f.deletedValue}'));
      field.onDispose.listen((f) => log.add('dispose'));

      await field.get();
      await pumpEventQueue();
      expect(log, equals(['fetch:1', 'change:1']));

      log.clear();
      await field.set(2);
      await pumpEventQueue();
      expect(log, equals(['save:20', 'change:20']));

      log.clear();
      expect(await field.delete(), isTrue);
      await pumpEventQueue();
      expect(log, equals(['delete:20']));

      log.clear();
      expect(await field.dispose(), isTrue);
      await pumpEventQueue();
      expect(log, equals(['dispose']));
      expect(storage.fields, isEmpty);
    });

    test('onChange is delivered asynchronously, to every listener', () async {
      var field = AsyncStorage().getField<int>('a');

      var l1 = <int>[];
      var l2 = <int>[];
      field.onChange.listen((f) => l1.add(f.valueNoTimeoutCheck!));
      field.onChange.listen((f) => l2.add(f.valueNoTimeoutCheck!));

      expect(field.set(1), equals(1));
      expect(l1, isEmpty);

      await pumpEventQueue();
      expect(l1, equals([1]));
      expect(l2, equals([1]));
    });

    test('a closed storage emits no events', () async {
      var storage = AsyncStorage();
      var field = storage.getField<int>('a')..withFetcher((_) => 1);

      var events = 0;
      field.onFetch.listen((_) => events++);
      field.onSave.listen((_) => events++);
      field.onChange.listen((_) => events++);
      field.onDelete.listen((_) => events++);

      storage.close();
      storage.close();
      expect(storage.isClosed, isTrue);

      expect(field.set(3), equals(3));
      expect(field.refresh(), equals(3));
      expect(field.delete(), isFalse);
      expect(field.value, equals(3));

      await pumpEventQueue();
      expect(events, equals(0));
    });
  });

  group('Timeouts and slate values (deterministic)', () {
    test(
      'concurrent get() on a slate value notifies and fetches once',
      () async {
        var expiry = _Expiry();
        var fetches = 0;
        var completer = Completer<int>();
        var field = AsyncStorage().getField<int>('a')
          ..timeoutChecker = expiry.call
          ..withFetcher((_) {
            fetches++;
            return completer.future;
          });

        await field.set(1);
        expiry.expired = true;

        var slates = <int>[];
        var g1 = field.get(onSlateValue: slates.add);
        var g2 = field.get(onSlateValue: slates.add);

        expect(fetches, equals(1));
        expect(slates, equals([1, 1]));
        expect(field.valueOrSlate, equals(1));
        expect(field.value, isNull);

        expiry.expired = false;
        completer.complete(2);

        expect(await g1, equals(2));
        expect(await g2, equals(2));
        expect(field.isSlate, isFalse);
        expect(field.value, equals(2));
        expect(fetches, equals(1));
      },
    );

    test('valueAsString and valueAsJson invalidate an expired value', () async {
      var expiry = _Expiry();
      var field = AsyncStorage().getField<int>('a')
        ..timeoutChecker = expiry.call
        ..defaultValue = 0;

      await field.set(5);
      expect(field.valueAsString, equals('5'));
      expect(field.valueAsJson, equals('5'));

      expiry.expired = true;
      expect(field.valueAsString, equals('0'));
      expect(field.valueAsJson, equals('0'));
      expect(field.valueOrSlate, equals(5));
      expect(field.valueOrSlateNoTimeoutCheck, equals(5));

      // A slate that is no longer expired does not come back as the value.
      expiry.expired = false;
      expect(field.value, equals(0));
      expect(field.isSlate, isTrue);
    });

    test('toDSXValue: slate value or fetch', () async {
      var expiry = _Expiry();
      var counter = 0;
      var field = AsyncStorage().getField<int>('a')
        ..timeoutChecker = expiry.call
        ..withFetcher((_) => ++counter);

      await field.set(100);
      expiry.expired = true;

      field.dsxValueAllowSlate = true;
      expect(field.toDSXValue(), equals(100));
      expect(counter, equals(0));

      field.dsxValueAllowSlate = false;
      expect(field.toDSXValue(), equals(1));
      expect(counter, equals(1));
    });
  });

  group('Storage lifecycle', () {
    test('many fields in one storage fetch independently', () async {
      var storage = _GatedStorage();

      var fields = [for (var i = 0; i < 100; i++) storage.getField<int>('f$i')];
      expect(storage.fields, hasLength(100));

      var gets = [
        for (var f in fields) ...[f.get(), f.get(), f.refresh()],
      ];

      expect(storage.fetchCounts, hasLength(100));
      expect(storage.fetchCounts.values, everyElement(1));

      storage.completeAll((key) => int.parse(key.substring(1)));

      var values = await Future.wait(gets.map((g) async => g));
      expect(
        values,
        equals([
          for (var i = 0; i < 100; i++) ...[i, i, i],
        ]),
      );

      for (var i = 0; i < 100; i++) {
        expect(storage.getField<int>('f$i').value, equals(i));
      }

      storage.clear();
      expect(fields.every((f) => !f.isSet), isTrue);
      expect(storage.fields, hasLength(100));

      var again = fields[42].get();
      expect(storage.fetchCounts['f42'], equals(2));
      expect(storage.fetchCounts['f41'], equals(1));
      storage.completeAll((key) => -1);
      expect(await again, equals(-1));
    });

    // Pins current behaviour: closing the storage does not cancel a fetch in
    // flight; its result is still applied to the field.
    test('close() while a fetch is in flight, then reopen', () async {
      var storage = _GatedStorage();
      var field = storage.getField<int>('a');

      var fetching = field.get();
      storage.close();

      storage.completeAll((_) => 1);
      expect(await fetching, equals(1));
      expect(field.value, equals(1));

      // Closed: refresh() returns the current value without fetching.
      expect(field.refresh(), equals(1));
      expect(storage.fetchCounts['a'], equals(1));

      // Reopen keeping values: no fetch needed.
      expect(storage.reopen(clear: false), isTrue);
      expect(field.get(), equals(1));
      expect(storage.fetchCounts['a'], equals(1));

      // Close and reopen clearing values: the next get() fetches again.
      storage.close();
      expect(storage.reopen(), isTrue);
      expect(field.isSet, isFalse);

      var refetch = field.get();
      expect(storage.fetchCounts['a'], equals(2));
      storage.completeAll((_) => 2);
      expect(await refetch, equals(2));
    });

    // Pins current behaviour: dispose() only detaches the field from the
    // storage; an in-flight fetch still completes on the detached field.
    test('dispose() while a fetch is in flight', () async {
      var storage = _GatedStorage();
      var field = storage.getField<int>('a');

      var disposes = 0;
      field.onDispose.listen((_) => disposes++);

      var fetching = field.get();
      expect(await field.dispose(), isTrue);
      expect(storage.fields, isEmpty);

      var replacement = storage.getField<int>('a');
      expect(identical(replacement, field), isFalse);

      storage.gates['a']!.complete(1);
      expect(await fetching, equals(1));
      expect(field.value, equals(1));
      expect(replacement.isSet, isFalse);
      expect(storage.fields, equals([replacement]));

      await pumpEventQueue();
      expect(disposes, equals(1));
    });

    test('dispose() while a save is in flight', () async {
      var storage = AsyncStorage();
      var completer = Completer<int>();
      var field = storage.getField<int>('a')
        ..withSaver((_, v) => completer.future);

      var saving = field.set(5);
      expect(await field.dispose(), isTrue);

      completer.complete(6);
      expect(await saving, equals(6));
      expect(field.value, equals(6));
      expect(storage.fields, isEmpty);
    });

    // Pins current behaviour: disposeValue()/delete() do not cancel a fetch
    // in flight, whose result is applied afterwards.
    test('disposeValue() and delete() while a fetch is in flight', () async {
      var storage = _GatedStorage();
      var field = storage.getField<int>('a');

      await field.set(1);

      var fetching = field.refresh();
      expect(field.disposeValue(), equals(1));
      expect(field.isSetOrSlate, isFalse);

      storage.gates['a']!.complete(2);
      expect(await fetching, equals(2));
      expect(field.value, equals(2));

      fetching = field.refresh();
      expect(await field.delete(), isTrue);
      expect(field.deletedValue, equals(2));
      expect(field.isSet, isFalse);

      storage.gates['a']!.complete(3);
      expect(await fetching, equals(3));
      expect(field.value, equals(3));
    });
  });

  group('Periodic refresh', () {
    // A value that is already older than `periodicRefresh` when committed
    // triggers an immediate refresh. The `onChangeFilter` runs between the
    // value timestamp and the periodic check, so waiting there for the clock
    // to pass `periodicRefresh` makes this deterministic.
    test('an already-elapsed period refreshes immediately', () {
      var storage = AsyncStorage();
      var fetches = 0;
      var stalled = false;

      var field = storage.getField<int>('a')
        ..withFetcher((_) => 100 + ++fetches)
        ..periodicRefresh = Duration(milliseconds: 1);

      field.onChangeFilter = (prev, v) {
        if (!stalled) {
          stalled = true;
          while (field.valueElapsedTime < 1) {}
        }
        return true;
      };

      expect(field.set(1), equals(1));

      // The refresh ran synchronously, inside set().
      expect(fetches, greaterThanOrEqualTo(1));
      expect(field.value, equals(100 + fetches));

      field.periodicRefresh = null;
      storage.close();
    });

    test('an immediate refresh joins a fetch still in flight', () async {
      var storage = AsyncStorage();
      var fetches = 0;
      var stalled = false;

      var field = storage.getField<int>('a')
        ..withFetcher((_) => Future.microtask(() => ++fetches))
        ..periodicRefresh = Duration(milliseconds: 1);

      field.onChangeFilter = (prev, v) {
        if (!stalled) {
          stalled = true;
          while (field.valueElapsedTime < 1) {}
        }
        return true;
      };

      expect(await field.get(), equals(1));
      field.periodicRefresh = null;
      storage.close();

      await pumpEventQueue();
      expect(fetches, equals(1));
      expect(field.isFetching, isFalse);
    });

    test('clearing periodicRefresh stops the scheduled refresh', () async {
      var fetches = 0;
      var field = AsyncStorage().getField<int>('a')
        ..withFetcher((_) => ++fetches)
        ..periodicRefresh = Duration(milliseconds: 20);

      expect(field.get(), equals(1));
      field.periodicRefresh = null;

      await Future.delayed(Duration(milliseconds: 60));
      expect(fetches, equals(1));
    });

    test('a closed storage stops periodic fetches', () async {
      var storage = AsyncStorage();
      var fetches = 0;
      var field = storage.getField<int>('a')
        ..withFetcher((_) => ++fetches)
        ..periodicRefresh = Duration(milliseconds: 20);

      expect(field.get(), equals(1));
      storage.close();

      await Future.delayed(Duration(milliseconds: 60));
      expect(fetches, equals(1));
      expect(field.value, equals(1));

      // Setting a value while closed schedules nothing either.
      expect(field.set(2), equals(2));
      await Future.delayed(Duration(milliseconds: 40));
      expect(fetches, equals(1));
    });

    test('repeated set() calls do not multiply periodic fetches', () async {
      var storage = AsyncStorage();
      var fetches = 0;
      var field = storage.getField<int>('a')
        ..withFetcher((_) => ++fetches)
        ..periodicRefresh = Duration(milliseconds: 50);

      for (var i = 0; i < 20; i++) {
        await field.set(i);
      }

      await Future.delayed(Duration(milliseconds: 180));

      // About one fetch per period (3), not one per set() call (20+).
      expect(fetches, inInclusiveRange(1, 5));

      field.periodicRefresh = null;
      storage.close();
    });
  });
}
