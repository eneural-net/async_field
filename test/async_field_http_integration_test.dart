@TestOn('vm')
@Timeout(Duration(seconds: 20))
library;

import 'dart:convert';
import 'dart:io';

import 'package:async_field/async_field.dart';
import 'package:test/test.dart';

/// A tiny key/value HTTP service on a local port:
/// - `GET /kv/<key>` -> `{"value": <v>}` or 404.
/// - `PUT /kv/<key>` with `{"value": <v>}` -> stores and echoes it.
/// - `DELETE /kv/<key>` -> 204, or 404 if missing.
class _KvServer {
  final HttpServer _server;
  final Map<String, Object?> data = {};
  final List<String> requests = [];

  /// When set, `GET` requests wait for it before answering.
  Completer<void>? getGate;

  /// Status code forced on the next `GET` responses, if any.
  final List<int> failNextGets = [];

  _KvServer._(this._server) {
    _server.listen(_handle);
  }

  static Future<_KvServer> start() async =>
      _KvServer._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  Uri uri(String key) => Uri.http('127.0.0.1:${_server.port}', '/kv/$key');

  int count(String method) =>
      requests.where((r) => r.startsWith('$method ')).length;

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest req) async {
    var key = req.uri.pathSegments.last;
    requests.add('${req.method} $key');
    var res = req.response;

    switch (req.method) {
      case 'GET':
        await getGate?.future;
        if (failNextGets.isNotEmpty) {
          res.statusCode = failNextGets.removeAt(0);
        } else if (!data.containsKey(key)) {
          res.statusCode = HttpStatus.notFound;
        } else {
          res.headers.contentType = ContentType.json;
          res.write(json.encode({'value': data[key]}));
        }
      case 'PUT':
        var body = json.decode(await utf8.decodeStream(req)) as Map;
        data[key] = body['value'];
        res.headers.contentType = ContentType.json;
        res.write(json.encode({'value': data[key]}));
      case 'DELETE':
        res.statusCode = data.remove(key) != null
            ? HttpStatus.noContent
            : HttpStatus.notFound;
      default:
        res.statusCode = HttpStatus.methodNotAllowed;
    }

    await res.close();
  }
}

class _HttpError implements Exception {
  final int statusCode;

  _HttpError(this.statusCode);

  @override
  String toString() => '_HttpError($statusCode)';
}

/// An [AsyncStorage] backed by [_KvServer] through [HttpClient].
class _HttpStorage extends AsyncStorage {
  final _KvServer server;
  final HttpClient client = HttpClient();

  _HttpStorage(this.server) : super('http');

  @override
  bool get canFetch => true;

  Future<(int, Object?)> _send(
    String method,
    String key, [
    Object? body,
  ]) async {
    var req = await client.openUrl(method, server.uri(key));
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.write(json.encode(body));
    }
    var res = await req.close();
    var text = await utf8.decodeStream(res);
    return (res.statusCode, text.isEmpty ? null : json.decode(text));
  }

  @override
  Future<T> fetch<T>(AsyncField<T> asyncField) async {
    var (status, body) = await _send('GET', asyncField.id.keyAsString);
    if (status != HttpStatus.ok) throw _HttpError(status);
    return (body as Map)['value'] as T;
  }

  @override
  Future<T> save<T>(AsyncField<T> asyncField, T value) async {
    var (status, body) = await _send('PUT', asyncField.id.keyAsString, {
      'value': value,
    });
    if (status != HttpStatus.ok) throw _HttpError(status);
    return (body as Map)['value'] as T;
  }

  @override
  Future<bool> delete<T>(AsyncField<T> asyncField) async {
    var (status, _) = await _send('DELETE', asyncField.id.keyAsString);
    return status == HttpStatus.noContent;
  }
}

void main() {
  late _KvServer server;
  late _HttpStorage storage;

  setUp(() async {
    server = await _KvServer.start();
    storage = _HttpStorage(server);
  });

  tearDown(() async {
    storage.client.close(force: true);
    await server.close();
  });

  group('AsyncField over HTTP', () {
    test('fetch, save, refresh and delete round-trip', () async {
      server.data['price'] = 100;
      var field = storage.getField<int>('price');

      var log = <String>[];
      field.onFetch.listen((f) => log.add('fetch'));
      field.onSave.listen((f) => log.add('save'));
      field.onChange.listen((f) => log.add('change:${f.valueNoTimeoutCheck}'));
      field.onDelete.listen((f) => log.add('delete'));

      expect(field.canRefresh, isTrue);
      expect(await field.get(), equals(100));
      expect(await field.get(), equals(100));
      expect(server.requests, equals(['GET price']));

      expect(await field.set(150), equals(150));
      expect(server.data, equals({'price': 150}));

      // Someone else changes the remote value; refresh() picks it up.
      server.data['price'] = 175;
      expect(await field.refresh(), equals(175));

      expect(await field.delete(), isTrue);
      expect(server.data, isEmpty);
      expect(field.isSet, isFalse);
      expect(field.deletedValue, equals(175));

      // Deleting again: the server reports 404, nothing changes locally.
      expect(await field.delete(), isFalse);

      expect(
        server.requests,
        equals([
          'GET price',
          'PUT price',
          'GET price',
          'DELETE price',
          'DELETE price',
        ]),
      );

      await pumpEventQueue();
      expect(
        log,
        equals([
          'fetch',
          'change:100',
          'save',
          'change:150',
          'fetch',
          'change:175',
          'delete',
        ]),
      );
    });

    test('concurrent get() calls issue a single request', () async {
      server.data['a'] = 'x';
      server.getGate = Completer<void>();

      var field = storage.getField<String>('a');
      var gets = [for (var i = 0; i < 20; i++) field.get()];

      // Let the single request reach the server.
      while (server.requests.isEmpty) {
        await Future.delayed(Duration.zero);
      }
      expect(field.isFetching, isTrue);

      server.getGate!.complete();
      var values = await Future.wait(gets.map((g) async => g));

      expect(values, everyElement('x'));
      expect(server.count('GET'), equals(1));
      expect(field.isFetching, isFalse);
    });

    test('a server error fails the fetch, the next get() recovers', () async {
      server.data['a'] = 1;
      server.failNextGets.add(HttpStatus.internalServerError);

      var field = storage.getField<int>('a');

      await expectLater(
        field.get(),
        throwsA(isA<_HttpError>().having((e) => e.statusCode, 'status', 500)),
      );
      expect(field.isSet, isFalse);
      expect(field.isFetching, isFalse);

      expect(await field.get(), equals(1));
      expect(server.count('GET'), equals(2));
    });

    test('a missing key fails with 404 and keeps the field unset', () async {
      var field = storage.getField<int>('missing');

      await expectLater(
        field.get(),
        throwsA(isA<_HttpError>().having((e) => e.statusCode, 'status', 404)),
      );
      expect(field.isSetOrSlate, isFalse);
    });

    test('an expired value is served as slate while refetching', () async {
      server.data['a'] = 1;
      var expired = false;
      var field = storage.getField<int>('a')..timeoutChecker = (_) => expired;

      expect(await field.get(), equals(1));

      server.data['a'] = 2;
      expired = true;

      var slates = <int>[];
      var refetch = field.get(onSlateValue: slates.add);
      expect(slates, equals([1]));
      expect(field.valueOrSlate, equals(1));

      expired = false;
      expect(await refetch, equals(2));
      expect(field.isSlate, isFalse);
      expect(server.count('GET'), equals(2));
    });

    test('many fields share one storage and one client', () async {
      for (var i = 0; i < 25; i++) {
        server.data['k$i'] = i * i;
      }

      var fields = [for (var i = 0; i < 25; i++) storage.getField<int>('k$i')];
      var values = await Future.wait(fields.map((f) async => f.get()));

      expect(values, equals([for (var i = 0; i < 25; i++) i * i]));
      expect(server.count('GET'), equals(25));

      await Future.wait([
        for (var i = 0; i < 25; i++) Future.value(fields[i].set(-i)),
      ]);
      expect(server.data, equals({for (var i = 0; i < 25; i++) 'k$i': -i}));
    });

    test('a closed storage stops talking to the server', () async {
      server.data['a'] = 1;
      var field = storage.getField<int>('a');
      expect(await field.get(), equals(1));

      storage.close();

      expect(await field.refresh(), equals(1));
      expect(await field.set(5), equals(5));
      expect(await field.delete(), isFalse);
      expect(server.requests, equals(['GET a']));
      expect(server.data, equals({'a': 1}));

      // Reopening clears local values; the next get() reads the server.
      storage.reopen();
      expect(field.isSet, isFalse);
      expect(await field.get(), equals(1));
      expect(server.requests, equals(['GET a', 'GET a']));
    });
  });
}
