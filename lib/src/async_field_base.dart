import 'dart:async';

import 'package:collection/collection.dart';

import 'package:async_extension/async_extension.dart';

typedef AsyncFieldFetcher<T> = FutureOr<T> Function(AsyncField<T> asyncField);

typedef AsyncFieldSaver<T> = FutureOr<T> Function(
    AsyncField<T> asyncField, T value);

typedef AsyncFieldDeleter<T> = FutureOr<bool> Function(
    AsyncField<T> asyncField);

class AsyncFieldID {
  final Object key;

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
}

class AsyncField<T> {
  /// The field storage.
  final AsyncStorage storage;

  /// The field ID in the [storage].
  final AsyncFieldID id;

  T? _value;

  int? _valueTime;

  AsyncField(this.storage, this.id);

  /// Returns the current field value.
  T? get value => _value;

  /// Same as [valueTime], but `millisecondsSinceEpoch`.
  int? get valueTimeMillisecondsSinceEpoch => _valueTime;

  /// Returns the value time, when it was set.
  DateTime? get valueTime {
    var valueTime = _valueTime;
    return valueTime != null
        ? DateTime.fromMillisecondsSinceEpoch(valueTime)
        : null;
  }

  /// Returns `true` if this field value is set.
  bool get isSet => _valueTime != null;

  /// Returns the current value of the field.
  FutureOr<T> get() {
    if (!isSet) {
      var value = refresh();
      return value;
    } else {
      return _value!;
    }
  }

  final StreamController<AsyncField<T>> _onChangeController =
      StreamController<AsyncField<T>>();

  Stream<AsyncField<T>> get onChange => _onChangeController.stream;

  /// Sets this field with [value].
  AsyncField<T> set(T value) {
    _value = value;
    _valueTime = DateTime.now().millisecondsSinceEpoch;

    _onChangeController.add(this);

    return this;
  }

  AsyncFieldFetcher<T>? fetcher;

  AsyncField<T> withFetcher(AsyncFieldFetcher<T>? fetcher,
      {bool overwrite = false}) {
    if (overwrite || this.fetcher == null) {
      this.fetcher = fetcher;
    }
    return this;
  }

  final StreamController<AsyncField<T>> _onFetchController =
      StreamController<AsyncField<T>>();

  Stream<AsyncField<T>> get onFetch => _onFetchController.stream;

  /// Refreshes this field and returns the fresh value.
  FutureOr<T> refresh() {
    var fetcher = this.fetcher;

    var ret = fetcher != null ? fetcher(this) : storage.fetch<T>(this);

    return ret.resolveMapped<T>(_onFetch);
  }

  FutureOr<T> _onFetch(T val) {
    _onFetchController.add(this);
    set(val);
    return val;
  }

  AsyncFieldSaver<T>? saver;

  AsyncField<T> withSaver(AsyncFieldSaver<T>? saver, {bool overwrite = false}) {
    if (overwrite || this.saver == null) {
      this.saver = saver;
    }
    return this;
  }

  final StreamController<AsyncField<T>> _onSaveController =
      StreamController<AsyncField<T>>();

  Stream<AsyncField<T>> get onSave => _onSaveController.stream;

  /// Saves this field [value] and returns the saved value.
  FutureOr<T> save() {
    var saver = this.saver;
    var value = _value!;

    var ret = saver != null ? saver(this, value) : storage.save<T>(this, value);

    return ret.resolveMapped<T>(_onSave);
  }

  FutureOr<T> _onSave(T val) {
    _onSaveController.add(this);
    set(val);
    return val;
  }

  AsyncFieldDeleter<T>? deleter;

  AsyncField<T> withDeleter(AsyncFieldDeleter<T>? deleter,
      {bool overwrite = false}) {
    if (overwrite || this.deleter == null) {
      this.deleter = deleter;
    }
    return this;
  }

  final StreamController<AsyncField<T>> _onDeleteController =
      StreamController<AsyncField<T>>();

  Stream<AsyncField<T>> get onDelete => _onDeleteController.stream;

  /// Deletes this field [value].
  FutureOr<bool> delete() {
    var deleter = this.deleter;

    var ret = deleter != null ? deleter(this) : storage.delete<T>(this);

    return ret.resolveMapped(_onDelete);
  }

  FutureOr<bool> _onDelete(bool ok) {
    if (ok) {
      _onDeleteController.add(this);
      dispose();
    }
    return ok;
  }

  final StreamController<AsyncField<T>> _onDisposeController =
      StreamController<AsyncField<T>>();

  Stream<AsyncField<T>> get onDispose => _onDisposeController.stream;

  FutureOr<bool> dispose() {
    var ret = storage.dispose(this);
    return ret.resolveMapped((ok) {
      if (ok) {
        _onDisposeController.add(this);
      }
      return ok;
    });
  }

  @override
  String toString() {
    return 'AsyncField{ '
        'id: $id, '
        'value: $_value, '
        'valueTime: $_valueTime, '
        'storage: $storage '
        '}';
  }
}

/// A storage for [AsyncField] instances.
class AsyncStorage {
  static int _idCount = 0;

  final id = ++_idCount;

  final name;

  AsyncStorage([this.name = '?']);

  final Map<AsyncFieldID, AsyncField> _fields = <AsyncFieldID, AsyncField>{};

  List<AsyncFieldID> get fieldsIDs => _fields.keys.toList();

  AsyncField operator [](dynamic id) => getField(id);

  /// Returns a [AsyncField] for the [id].
  AsyncField<T> getField<T>(dynamic id) {
    var fieldID = AsyncFieldID.from(id);

    var fieldCached = _fields[fieldID];

    if (fieldCached != null) {
      return fieldCached as AsyncField<T>;
    }

    var field = AsyncField<T>(this, fieldID);

    _fields[fieldID] = field;

    return field;
  }

  /// Sets the [AsyncField] for the [id] with [value].
  AsyncField<T> setField<T>(dynamic id, T value) {
    var field = getField<T>(id);
    field.set(value);
    return field;
  }

  /// Fetches an [asyncField] value.
  FutureOr<T> fetch<T>(AsyncField<T> asyncField) {
    throw AsyncFieldError('No fetcher for $asyncField', asyncField.id);
  }

  /// Saves an [asyncField] [value].
  FutureOr<T> save<T>(AsyncField<T> asyncField, T value) {
    throw AsyncFieldError('No saver for $asyncField', asyncField.id);
  }

  /// Deletes an [asyncField] [value].
  FutureOr<bool> delete<T>(AsyncField<T> asyncField) {
    throw AsyncFieldError('No deleter for $asyncField', asyncField.id);
  }

  /// Disposes an [asyncField].
  FutureOr<bool> dispose(AsyncField asyncField) {
    return _fields.remove(asyncField) != null;
  }

  @override
  String toString() {
    return 'AsyncStorage{name: $name, id: $id}';
  }
}

class AsyncFieldError {
  final String message;

  final Object? id;

  AsyncFieldError(this.message, [this.id]);

  @override
  String toString() {
    return 'AsyncFieldError{message: $message, id: $id}';
  }
}
