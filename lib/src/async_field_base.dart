import 'dart:convert';

import 'package:async_extension/async_extension.dart';
import 'package:collection/collection.dart';

typedef AsyncFieldFetcher<T> = FutureOr<T> Function(AsyncField<T> asyncField);

typedef AsyncFieldSaver<T> = FutureOr<T> Function(
    AsyncField<T> asyncField, T value);

typedef AsyncFieldDeleter<T> = FutureOr<bool> Function(
    AsyncField<T> asyncField);

/// The ID of an [AsyncField].
class AsyncFieldID {
  /// The key of this field ID.
  final Object key;

  /// Returns [key] as [String].
  String get keyAsString => '$key';

  /// Returns [key] as JSON.
  String get keyAsJson => json.encode(key);

  AsyncFieldID(this.key);

  factory AsyncFieldID.from(dynamic o) {
    if (o is AsyncFieldID) return o;
    return AsyncFieldID(o);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AsyncFieldID &&
          runtimeType == other.runtimeType &&
          equalsKey(other.key);

  static final DeepCollectionEquality _deepCollectionEquality =
      DeepCollectionEquality();

  bool equalsKey(Object key) {
    if (identical(this.key, key)) {
      return true;
    }
    return _deepCollectionEquality.equals(this.key, key);
  }

  int? _hashCode;

  @override
  int get hashCode {
    return _hashCode ??= _deepCollectionEquality.hash(key);
  }

  @override
  String toString() {
    return 'AsyncFieldID{key: $key}';
  }
}

/// An asynchronous field @ [storage].
class AsyncField<T> {
  /// The field storage.
  final AsyncStorage storage;

  /// The field ID in the [storage].
  final AsyncFieldID id;

  Object get idKey => id.key;

  Object get idKeyAsJson => json.encode(id.key);

  T? _value;

  String get valueAsJson {
    checkValueTimeout();
    return json.encode(value);
  }

  String get valueAsString {
    checkValueTimeout();
    return isSet ? '$_value' : (defaultValue ?? '?').toString();
  }

  double get valueAsDouble {
    checkValueTimeout();
    return double.parse(valueAsString);
  }

  int get valueAsInt {
    checkValueTimeout();
    return int.parse(valueAsString);
  }

  bool get valueAsBool {
    checkValueTimeout();
    var val = value;
    return _parseBool(val);
  }

  static bool _parseBool(val) {
    if (val == null) {
      return false;
    }

    if (val is num) {
      return val > 0;
    } else {
      var s = '$val'.trim();

      if (_parseFalse(s)) {
        return false;
      }

      var n = num.tryParse(s);
      if (n != null) {
        return n > 0;
      }

      s = s.toLowerCase();

      return !_parseFalse(s);
    }
  }

  static bool _parseFalse(String s) =>
      s.isEmpty ||
      s == '0' ||
      s == 'false' ||
      s == 'no' ||
      s == 'null' ||
      s == 'n';

  T? defaultValue;

  int? _valueTime;

  AsyncField(this.storage, this.id);

  /// Returns `true` if [storage.isClosed].
  /// - A closed [storage] will stop `fetch`, `save` and `delete` operations.
  /// - If [storage] is closed this field will return `slate` values only.
  bool get isClosed => storage.isClosed;

  /// Returns the current field value.
  T? get value {
    checkValueTimeout();
    return _value ?? defaultValue;
  }

  T? get valueNoTimeoutCheck {
    return _value ?? defaultValue;
  }

  /// Same as [valueTime], but `millisecondsSinceEpoch`.
  int? get valueTimeMillisecondsSinceEpoch => _valueTime;

  /// Returns the value time, when it was set.
  DateTime? get valueTime {
    var valueTime = _valueTime;
    return valueTime != null
        ? DateTime.fromMillisecondsSinceEpoch(valueTime)
        : null;
  }

  /// Returns the amount of time from the last value [set] or fetch.
  int get valueElapsedTime {
    var valueTime = _valueTime;
    return valueTime != null
        ? DateTime.now().millisecondsSinceEpoch - valueTime
        : 0;
  }

  /// Returns the amount of time until the current value is expired (in ms).
  int get valueTimeUntilExpire {
    var timeout = this.timeout;
    return timeout != null ? timeout.inMilliseconds - valueElapsedTime : 0;
  }

  /// Returns `true` if this [value] is valid, based in the [timeout] and [isSet].
  bool get isValid {
    var timeout = this.timeout;
    return timeout != null
        ? isSet && valueElapsedTime <= timeout.inMilliseconds
        : isSet;
  }

  /// Returns `true` if this value is expired, based in the [timeout].
  bool get isExpire {
    var timeout = this.timeout;

    return timeout != null && valueElapsedTime > timeout.inMilliseconds;
  }

  /// Returns `true` if this field value is set.
  bool get isSet => _valueTime != null;

  /// Checks [value] [timeout] and invalidate it if [isExpire].
  T? checkValueTimeout() {
    if (isExpire) {
      var slate = _value;
      _value = null;
      _valueTime = null;
      return slate;
    } else {
      return null;
    }
  }

  /// Discard the current [value].
  T? disposeValue() {
    var slate = _value;
    _value = null;
    _valueTime = null;
    return slate;
  }

  /// Returns the current value of the field.
  ///
  /// - [onSlateValue] if a slate value exists will be notified.
  ///
  /// A slate value is when the current value exists but is expired. Can
  /// be used before a fetch is performed.
  ///
  /// If [isFetching] is `true` it will return the current fetching [Future].
  /// See [refresh].
  FutureOr<T> get({void Function(T slate)? onSlateValue}) {
    var slate = checkValueTimeout();

    if (!isSet) {
      if (slate != null) {
        if (isClosed) {
          return slate;
        } else if (onSlateValue != null) {
          onSlateValue(slate);
        }
      }

      var value = refresh();
      return value;
    } else {
      var fetching = _fetching;

      if (fetching != null) {
        if (onSlateValue != null && slate != null) {
          onSlateValue(slate);
        }

        return fetching;
      }

      return _value as T;
    }
  }

  /// [get] as [String].
  FutureOr<String> getAsString() => get().resolveMapped((v) => '$v');

  /// [get] as JSON.
  FutureOr<String> getAsJson() => get().resolveMapped(json.encode);

  /// [get] as [double].
  FutureOr<double> getAsDouble() =>
      getAsString().resolveMapped((v) => double.parse(v));

  /// [get] as [int].
  FutureOr<int> getAsInt() => getAsString().resolveMapped((v) => int.parse(v));

  /// [get] as [bool].
  FutureOr<bool> getAsBool() =>
      getAsString().resolveMapped((v) => _parseBool(v));

  final StreamController<AsyncField<T>> _onChangeController =
      StreamController<AsyncField<T>>.broadcast();

  /// On change [value] event.
  Stream<AsyncField<T>> get onChange => _onChangeController.stream;

  /// Filters values changes before trigger [onChange].
  bool Function(T? prevValue, T? value)? onChangeFilter;

  bool _isChangingValue(T? prevValue, T? value) {
    final changeValidator = this.onChangeFilter;
    if (changeValidator != null) {
      return changeValidator(prevValue, value);
    } else {
      return true;
    }
  }

  /// Sets this field with [value].
  FutureOr<T> set(T value) {
    _value = value;
    _valueTime = DateTime.now().millisecondsSinceEpoch;

    return save();
  }

  // Internal _set called by [_onSave] and [onFetch].
  AsyncField<T> _set(T value) {
    var prevValue = _value;

    _value = value;
    _valueTime = DateTime.now().millisecondsSinceEpoch;

    if (_isChangingValue(prevValue, value)) {
      _onChangeController.add(this);
    }

    _checkPeriodicRefresh();

    return this;
  }

  void _checkPeriodicRefresh() {
    if (isClosed) return;

    var periodicRefresh = this.periodicRefresh;
    if (periodicRefresh == null || periodicRefresh.inMilliseconds < 1) return;

    var timeToPeriodicRefresh =
        periodicRefresh.inMilliseconds - valueElapsedTime;

    if (timeToPeriodicRefresh <= 0) {
      refresh();
      return;
    }

    Future.delayed(Duration(milliseconds: timeToPeriodicRefresh), () {
      var periodicRefresh = this.periodicRefresh;
      if (periodicRefresh == null || periodicRefresh.inMilliseconds < 1) return;

      if (valueElapsedTime < periodicRefresh.inMilliseconds) {
        _checkPeriodicRefresh();
      } else {
        refresh();
      }
    });
  }

  AsyncFieldFetcher<T>? fetcher;

  /// Defines the [fetcher] of this field.
  AsyncField<T> withFetcher(AsyncFieldFetcher<T>? fetcher,
      {bool overwrite = false}) {
    if (overwrite || this.fetcher == null) {
      this.fetcher = fetcher;
    }
    return this;
  }

  final StreamController<AsyncField<T>> _onFetchController =
      StreamController<AsyncField<T>>.broadcast();

  Stream<AsyncField<T>> get onFetch => _onFetchController.stream;

  /// Returns `true` if a [refresh] can be performed.
  bool get canRefresh => (fetcher != null || storage.canFetch) && !isClosed;

  Future<T>? _fetching;

  bool get isFetching => _fetching != null;

  /// Refreshes this field and returns the fresh value.
  FutureOr<T> refresh() {
    var fetching = _fetching;
    if (fetching != null) {
      return fetching;
    }

    if (isClosed) {
      var value = _value;
      if (value != null) {
        return value;
      }

      try {
        return null as T;
      } catch (_) {
        throw StateError(
            "Closed `storage`: can't return `null` value as `$T` @ $runtimeType#${id.key}");
      }
    }

    var fetcher = this.fetcher;

    var ret = fetcher != null ? fetcher(this) : storage.fetch<T>(this);

    if (ret is Future<T>) {
      _fetching = ret;
    }

    return ret.resolveMapped<T>(_onFetch);
  }

  FutureOr<T> _onFetch(T val) {
    _onFetchController.add(this);
    _set(val);
    _fetching = null;
    return val;
  }

  AsyncFieldSaver<T>? saver;

  /// Defines the [saver] of this field.
  AsyncField<T> withSaver(AsyncFieldSaver<T>? saver, {bool overwrite = false}) {
    if (overwrite || this.saver == null) {
      this.saver = saver;
    }
    return this;
  }

  final StreamController<AsyncField<T>> _onSaveController =
      StreamController<AsyncField<T>>.broadcast();

  Stream<AsyncField<T>> get onSave => _onSaveController.stream;

  /// Saves this field [value] and returns the saved value.
  FutureOr<T> save() {
    var saver = this.saver;
    var value = _value;

    if (value is! T) {
      throw StateError("Value not set!");
    }

    if (isClosed) {
      return value;
    }

    var ret = saver != null ? saver(this, value) : storage.save<T>(this, value);

    return ret.resolveMapped<T>(_onSave);
  }

  FutureOr<T> _onSave(T val) {
    _onSaveController.add(this);
    _set(val);
    return val;
  }

  AsyncFieldDeleter<T>? deleter;

  /// Defines the [deleter] of this field.
  AsyncField<T> withDeleter(AsyncFieldDeleter<T>? deleter,
      {bool overwrite = false}) {
    if (overwrite || this.deleter == null) {
      this.deleter = deleter;
    }
    return this;
  }

  final StreamController<AsyncField<T>> _onDeleteController =
      StreamController<AsyncField<T>>.broadcast();

  Stream<AsyncField<T>> get onDelete => _onDeleteController.stream;

  /// Deletes this field [value] from storage, but won't [dispose] it.
  /// See [deletedValue].
  FutureOr<bool> delete() {
    var deleter = this.deleter;

    if (isClosed) {
      return false;
    }

    var ret = deleter != null ? deleter(this) : storage.delete<T>(this);

    return ret.resolveMapped(_onDelete);
  }

  T? _deletedValue;

  /// The last deleted value. See [delete].
  T? get deletedValue => _deletedValue;

  void disposeDeletedValue() {
    _deletedValue = null;
  }

  FutureOr<bool> _onDelete(bool ok) {
    if (ok) {
      _deletedValue = _value;

      _value = null;
      _valueTime = DateTime.now().millisecondsSinceEpoch;

      _onDeleteController.add(this);
    }

    return ok;
  }

  final StreamController<AsyncField<T>> _onDisposeController =
      StreamController<AsyncField<T>>.broadcast();

  Stream<AsyncField<T>> get onDispose => _onDisposeController.stream;

  /// Disposes this field. Will remove it from [storage], but won't [delete] its [value].
  FutureOr<bool> dispose() {
    var ret = storage.dispose(this);
    return ret.resolveMapped((ok) {
      if (ok) {
        _onDisposeController.add(this);
      }
      return ok;
    });
  }

  /// The values timeout.
  Duration? timeout;

  /// Returns `true` if this field value has [timeout].
  bool get hasTimeout {
    var timeout = this.timeout;
    return timeout != null && timeout.inMilliseconds >= 1;
  }

  /// Refresh period. After set a value, it will refresh the value
  /// periodically.
  Duration? periodicRefresh;

  /// Returns `true` if this field value has [periodicRefresh].
  bool get hasPeriodicRefresh {
    var periodicRefresh = this.periodicRefresh;
    return periodicRefresh != null && periodicRefresh.inMilliseconds >= 1;
  }

  @override

  /// Same as [valueAsString].
  String toString() => valueAsString;

  String get info {
    var storageInfo = storage.name;
    if (storageInfo.isEmpty) {
      storageInfo = storage.id.toString();
    }

    var timeoutInfo =
        hasTimeout ? '"timeout": ${timeout!.inMilliseconds}ms , ' : '';

    if (isSet) {
      return '{ '
          '"value": $valueAsJson , '
          '"id": $idKeyAsJson , '
          '"valueTime": $_valueTime , '
          '$timeoutInfo'
          '"storage": $storageInfo'
          ' }';
    } else {
      return '{ '
          '"id": $idKeyAsJson , '
          '$timeoutInfo'
          '"storage": $storageInfo'
          ' }';
    }
  }

  /// DSX dynamic interface (package `dom_builder`).
  dynamic toDSXValue() {
    if (isSet && isValid) {
      return valueNoTimeoutCheck;
    } else {
      return get();
    }
  }

  /// DSX dynamic interface (package `dom_builder`).
  StreamSubscription<AsyncField<T>> listenDSXValue(
          void Function(AsyncField<T> field)? onData) =>
      onChange.listen(onData);
}

/// A storage for [AsyncField] instances.
class AsyncStorage {
  static int _idCount = 0;

  final int id = ++_idCount;

  final String name;

  AsyncStorage([this.name = '']);

  final Map<AsyncFieldID, AsyncField> _fields = <AsyncFieldID, AsyncField>{};

  List<AsyncField> get fields => _fields.values.toList();

  List<AsyncFieldID> get fieldsIDs => _fields.keys.toList();

  AsyncField operator [](dynamic id) => getField(id);

  /// Timeout to use in all fields instantiated by this storage.
  Duration? fieldsTimeout;

  /// Returns a [AsyncField] for the [id].
  AsyncField<T> getField<T>(dynamic id) {
    var fieldID = AsyncFieldID.from(id);

    var fieldCached = _fields[fieldID];

    if (fieldCached != null) {
      return fieldCached as AsyncField<T>;
    }

    var field = AsyncField<T>(this, fieldID);

    if (fieldsTimeout != null) {
      field.timeout = fieldsTimeout;
    }

    _fields[fieldID] = field;

    return field;
  }

  /// Sets the [AsyncField] for the [id] with [value].
  FutureOr<T> setField<T>(dynamic id, T value) {
    var field = getField<T>(id);
    return field.set(value);
  }

  /// Returns `true` if a [fetch] can be performed.
  bool get canFetch => false;

  /// Fetches an [asyncField] value.
  FutureOr<T> fetch<T>(AsyncField<T> asyncField) {
    if (isClosed) {
      var value = asyncField.value;
      if (value != null) {
        return value;
      }

      try {
        return null as T;
      } catch (_) {
        throw StateError(
            "Closed `storage`: can't return `null` value @ AsyncField#${asyncField.id.key}");
      }
    }

    throw AsyncFieldError(
        'No fetcher for ${asyncField.runtimeType}', asyncField.id);
  }

  /// Saves an [asyncField] [value].
  FutureOr<T> save<T>(AsyncField<T> asyncField, T value) => value;

  /// Deletes an [asyncField] [value].
  FutureOr<bool> delete<T>(AsyncField<T> asyncField) => true;

  /// Disposes an [asyncField].
  FutureOr<bool> dispose(AsyncField asyncField) {
    return _fields.remove(asyncField.id) != null;
  }

  /// Clear all [fields] calling [AsyncField.disposeValue].
  void clear() {
    for (var f in _fields.values) {
      f.disposeValue();
    }
  }

  /// Reopens this storage if [isClosed].
  /// - If [clear] is `true` will also [clear] the fields.
  bool reopen({bool clear = true}) {
    if (!isClosed) return false;

    if (clear) {
      this.clear();
    }

    _closed = false;

    return true;
  }

  bool _closed = false;

  /// Returns `true` if this instance is closed.
  /// - A closed storage will stop `fetch`, `save` and `delete` operations.
  /// - See [close].
  bool get isClosed => _closed;

  /// Closes this instance.
  /// - A closed storage will stop `fetch`, `save` and `delete` operations.
  /// - See [isClosed]
  void close() {
    if (_closed) return;
    _closed = true;
  }

  @override
  String toString() {
    return 'AsyncStorage{${name.isNotEmpty ? 'name: $name, ' : ''}id: $id}';
  }
}

class AsyncFieldError extends Error {
  final String message;

  final Object? id;

  AsyncFieldError(this.message, [this.id]);

  @override
  String toString() {
    return 'AsyncFieldError{message: $message, id: $id}';
  }
}
