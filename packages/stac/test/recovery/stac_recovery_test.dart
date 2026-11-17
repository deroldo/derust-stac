import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:stac/src/framework/stac_network_view.dart';
import 'package:stac/src/recovery/stac_recovery_exception.dart';
import 'package:stac/src/recovery/stac_recovery_interceptor.dart';
import 'package:stac/src/recovery/stac_recovery_run.dart';
import 'package:stac/stac.dart';

import '../state/harness.dart';

Map<String, dynamic> _state(String key) => StacBinding.state(key);

const _envelopeType = 'application/vnd.stac.error+json';

/// A recovery instruction; `key` is only sent when [key] is given (or `null`
/// explicitly with [keyNull]).
Map<String, dynamic> _recovery({
  Object? recover,
  String? key,
  bool keyNull = false,
  Map<String, dynamic>? retry,
  Object? onFailure,
  Object? onUnavailable,
  int? timeoutMs,
  String refreshUrl = 'https://x.test/recover-endpoint',
}) => {
  'recover': recover ?? _refresh(url: refreshUrl),
  if (key != null || keyNull) 'key': key,
  'retry': ?retry,
  'onFailure': ?onFailure,
  'onUnavailable': ?onUnavailable,
  'timeoutMs': ?timeoutMs,
};

FakeResponse _envelope(
  Map<String, dynamic>? recovery, {
  int status = 401,
  Duration delay = Duration.zero,
}) => FakeResponse(
  {
    'version': 1,
    'code': 'session_expired',
    'message': 'expired',
    'recovery': ?recovery,
  },
  statusCode: status,
  delay: delay,
  headers: {
    'content-type': [_envelopeType],
  },
);

/// `recover`: refresh the token and keep what the bindings of `recover` see.
Map<String, dynamic> _refresh({
  String url = 'https://x.test/recover-endpoint',
}) => {
  'actionType': 'networkRequest',
  'url': url,
  'method': 'post',
  'onSuccess': {
    'actionType': 'setState',
    'values': {
      'global.tok': _state('response.body.token'),
      'global.seenCode': _state('failure.code'),
      'global.seenUrl': _state('request.url'),
      'global.seenMethod': _state('request.method'),
    },
  },
};

Map<String, dynamic> _inc(String key) => {
  'actionType': 'incrementState',
  'key': key,
};

/// A `networkRequest` to /data, carrying the token and a tag.
Map<String, dynamic> _data({
  String method = 'get',
  String tag = '1',
  bool counters = true,
}) => {
  'actionType': 'networkRequest',
  'url': 'https://x.test/data',
  'method': method,
  'contentType': 'application/json',
  'requestKey': 'rk$tag',
  'headers': {'X-Token': _state('global.tok'), 'X-N': tag, 'X-Plain': 'p'},
  if (method != 'get') 'body': {'n': tag},
  if (counters) 'onSuccess': _inc('ok'),
  if (counters) 'onError': _inc('err'),
  if (counters) 'onFinally': _inc('fin'),
};

Map<String, dynamic> _button(String tag, Map<String, dynamic> action) => {
  'type': 'textButton',
  'onPressed': action,
  'child': {'type': 'text', 'data': 'go$tag'},
};

Map<String, dynamic> _screen(List<Map<String, dynamic>> children) => {
  'type': 'column',
  'globalState': {
    'tok': 'old',
    'seenCode': '',
    'seenUrl': '',
    'seenMethod': '',
    'hook': 0,
  },
  'state': {'ok': 0, 'err': 0, 'fin': 0, 'hookLocal': 0},
  'children': children,
};

/// Simulates an action whose asynchronous work fails.
class _ThrowParser extends StacActionParser<Map<String, dynamic>> {
  const _ThrowParser();

  @override
  String get actionType => 'testThrow';

  @override
  Map<String, dynamic> getModel(Map<String, dynamic> json) => json;

  @override
  FutureOr onCall(BuildContext context, Map<String, dynamic> model) =>
      Future<void>.error(StateError('boom'));
}

void main() {
  final adapter = FakeDioAdapter();
  final dio = Dio()..httpClientAdapter = adapter;
  final hits = <String, int>{};

  /// The default server: /data needs the new token, /recover-endpoint gives it.
  late FakeResponse Function(RequestOptions) server;
  FakeResponse defaultServer(RequestOptions o) {
    final path = o.uri.path;
    hits[path] = (hits[path] ?? 0) + 1;
    switch (path) {
      case '/recover-endpoint':
        return const FakeResponse({
          'token': 'new',
        }, delay: Duration(milliseconds: 50));
      case '/data':
        return o.headers['X-Token'] == 'new'
            ? const FakeResponse({'type': 'text', 'data': 'dest'})
            : _envelope(_recovery(), delay: const Duration(milliseconds: 20));
    }
    return const FakeResponse({});
  }

  setUp(() {
    adapter.requests.clear();
    hits.clear();
    server = defaultServer;
    if (StacRegistry.instance.getActionParser('testThrow') == null) {
      StacRegistry.instance.registerAction(const _ThrowParser());
    }
    adapter.responder = (o) => server(o);
    StacRecoveryInterceptor.instance.reset();
    final store = StacGlobalState.instance.store;
    for (final e in {
      'tok': 'old',
      'seenCode': '',
      'seenUrl': '',
      'seenMethod': '',
      'hook': 0,
    }.entries) {
      store
        ..declare(e.key, e.value)
        ..write(e.key, e.value);
    }
  });

  Future<void> settle(WidgetTester tester, [int ms = 600]) async {
    for (var t = 0; t < ms; t += 10) {
      await tester.pump(const Duration(milliseconds: 10));
    }
  }

  Future<void> pumpScreen(
    WidgetTester tester,
    List<Map<String, dynamic>> children,
  ) => pumpStac(tester, _screen(children), dio: dio);

  Object? local(WidgetTester tester, String key, [String tag = '1']) =>
      StacStateScope.storeOf(tester.element(find.text('go$tag')))!.read(key);

  Object? global(String key) => StacGlobalState.instance.store.read(key);

  List<RequestOptions> sent(String path) =>
      adapter.requests.where((r) => r.uri.path == path).toList();

  /// A request through the real StacNetworkLoad (so it has a template);
  /// returns what the future ends with.
  Future<Object?> load(
    WidgetTester tester, {
    Map<String, dynamic>? headers,
    Method method = Method.get,
    void Function(StacNetworkLoad)? onStart,
  }) async {
    await pumpStac(tester, _screen([_button('1', {})]), dio: dio);
    Object? result;
    var done = false;
    final context = tester.element(find.text('go1'));
    final request = StacNetworkRequest(
      url: 'https://x.test/data',
      method: method,
      headers: headers ?? {'X-Token': _state('global.tok'), 'X-Plain': 'p'},
    );
    final started = StacNetworkLoad.start(context, request);
    onStart?.call(started);
    started.future.then<void>(
      (r) {
        result = r;
        done = true;
      },
      onError: (Object e) {
        result = e;
        done = true;
      },
    );
    await settle(tester);
    expect(done, isTrue, reason: 'the request never finished');
    return result;
  }

  group('recovery and repetition', () {
    testWidgets('one recovery, then the request is repeated with new data', (
      tester,
    ) async {
      server = (o) {
        if (o.uri.path == '/data' && o.headers['X-Token'] != 'new') {
          hits['/data'] = (hits['/data'] ?? 0) + 1;
          return _envelope(
            _recovery(
              retry: {
                'overrides': {
                  'headers': {'X-Extra': 'e'},
                },
                'removeHeaders': ['X-Plain'],
              },
            ),
          );
        }
        return defaultServer(o);
      };
      await pumpScreen(tester, [_button('1', _data())]);
      await tester.tap(find.text('go1'));
      await settle(tester);

      expect(adapter.requests.map((r) => r.uri.path), [
        '/data',
        '/recover-endpoint',
        '/data',
      ]);
      final first = adapter.requests.first;
      final second = adapter.requests.last;
      expect(first.headers['X-Token'], 'old');
      expect(second.headers['X-Token'], 'new');
      expect(second.headers['X-Extra'], 'e');
      expect(second.headers.containsKey('X-Plain'), isFalse);
      expect(second.uri, first.uri);
      expect(second.method, first.method);
      // `request` and `failure` were readable by the bindings of `recover`.
      expect(global('seenCode'), 'session_expired');
      expect(global('seenUrl'), 'https://x.test/data');
      expect(global('seenMethod'), 'GET');
      // The caller sees only the final answer.
      expect(local(tester, 'ok'), 1);
      expect(local(tester, 'err'), 0);
      expect(local(tester, 'fin'), 1);
    });

    for (final method in const ['get', 'post', 'put', 'delete']) {
      testWidgets('works for $method', (tester) async {
        await pumpScreen(tester, [_button('1', _data(method: method))]);
        await tester.tap(find.text('go1'));
        await settle(tester);
        final data = sent('/data');
        expect(data, hasLength(2));
        expect(data[1].method, method.toUpperCase());
        expect(data[1].headers['X-Token'], 'new');
        if (method != 'get') expect(data[1].data, {'n': '1'});
        expect(hits['/recover-endpoint'], 1);
        expect(local(tester, 'ok'), 1);
      });
    }

    testWidgets('5 concurrent requests: 1 recover, each repeats its own', (
      tester,
    ) async {
      // Odd requests carry the same `recover` with its keys in another order:
      // the canonical JSON makes them one identity.
      server = (o) {
        if (o.uri.path == '/data' && o.headers['X-Token'] != 'new') {
          hits['/data'] = (hits['/data'] ?? 0) + 1;
          final n = int.parse('${o.headers['X-N']}');
          final refresh = _refresh();
          final recover = n.isOdd
              ? Map<String, dynamic>.fromEntries(
                  refresh.entries.toList().reversed,
                )
              : refresh;
          return _envelope(
            _recovery(recover: recover),
            delay: const Duration(milliseconds: 20),
          );
        }
        return defaultServer(o);
      };
      final tags = ['1', '2', '3', '4', '5'];
      await pumpScreen(tester, [
        for (final t in tags) _button(t, _data(tag: t)),
      ]);
      for (final t in tags) {
        await tester.tap(find.text('go$t'));
      }
      await settle(tester);

      expect(hits['/recover-endpoint'], 1);
      expect(sent('/data'), hasLength(10));
      final repeats = sent('/data').where((r) => r.headers['X-Token'] == 'new');
      expect(repeats.map((r) => r.headers['X-N']).toList()..sort(), tags);
      expect(local(tester, 'ok'), 5);
      expect(local(tester, 'err'), 0);
    });

    testWidgets('different keys are different recoveries', (tester) async {
      server = (o) {
        if (o.uri.path == '/data' && o.headers['X-Token'] != 'new') {
          hits['/data'] = (hits['/data'] ?? 0) + 1;
          return _envelope(
            _recovery(key: 'k${o.headers['X-N']}'),
            delay: const Duration(milliseconds: 20),
          );
        }
        return defaultServer(o);
      };
      await pumpScreen(tester, [
        _button('1', _data(tag: '1')),
        _button('2', _data(tag: '2')),
      ]);
      await tester.tap(find.text('go1'));
      await tester.tap(find.text('go2'));
      await settle(tester);
      expect(hits['/recover-endpoint'], 2);
      expect(local(tester, 'ok'), 2);
    });

    testWidgets('same key coalesces even when recover differs', (tester) async {
      server = (o) {
        if (o.uri.path == '/data' && o.headers['X-Token'] != 'new') {
          hits['/data'] = (hits['/data'] ?? 0) + 1;
          return _envelope(
            _recovery(
              key: 'same',
              refreshUrl: 'https://x.test/recover-endpoint?${o.headers['X-N']}',
            ),
            delay: const Duration(milliseconds: 20),
          );
        }
        return defaultServer(o);
      };
      await pumpScreen(tester, [
        _button('1', _data(tag: '1')),
        _button('2', _data(tag: '2')),
      ]);
      await tester.tap(find.text('go1'));
      await tester.tap(find.text('go2'));
      await settle(tester);
      expect(hits['/recover-endpoint'], 1);
      expect(local(tester, 'ok'), 2);
    });

    testWidgets('key: null turns coalescing off', (tester) async {
      server = (o) {
        if (o.uri.path == '/data' && o.headers['X-Token'] != 'new') {
          hits['/data'] = (hits['/data'] ?? 0) + 1;
          return _envelope(
            _recovery(keyNull: true),
            delay: const Duration(milliseconds: 20),
          );
        }
        return defaultServer(o);
      };
      await pumpScreen(tester, [
        _button('1', _data(tag: '1')),
        _button('2', _data(tag: '2')),
      ]);
      await tester.tap(find.text('go1'));
      await tester.tap(find.text('go2'));
      await settle(tester);
      expect(hits['/recover-endpoint'], 2);
      expect(local(tester, 'ok'), 2);
      expect(StacRecoveryInterceptor.instance.runsInFlight, 0);
    });

    testWidgets('generation: a late failure of an older request only repeats', (
      tester,
    ) async {
      server = (o) {
        if (o.uri.path == '/data' && o.headers['X-Token'] != 'new') {
          hits['/data'] = (hits['/data'] ?? 0) + 1;
          return _envelope(
            _recovery(),
            delay: Duration(milliseconds: o.headers['X-N'] == 'A' ? 300 : 20),
          );
        }
        return defaultServer(o);
      };
      await pumpScreen(tester, [
        _button('A', _data(tag: 'A')),
        _button('B', _data(tag: 'B')),
      ]);
      await tester.tap(find.text('goA'));
      await tester.tap(find.text('goB'));
      await settle(tester, 700);

      // B recovered at ~70ms; A's 401 only arrived at 300ms, after it.
      expect(hits['/recover-endpoint'], 1);
      expect(sent('/data'), hasLength(4));
      expect(local(tester, 'ok', 'A'), 2);
      expect(local(tester, 'err', 'A'), 0);
    });

    testWidgets('a request without template (app Dio) is recovered too', (
      tester,
    ) async {
      server = (o) {
        if (o.uri.path == '/plain' && o.headers['Authorization'] != 'new') {
          hits['/plain'] = (hits['/plain'] ?? 0) + 1;
          return _envelope(
            _recovery(
              retry: {
                'overrides': {
                  'headers': {'Authorization': 'new'},
                },
              },
            ),
          );
        }
        if (o.uri.path == '/plain') return const FakeResponse({'ok': true});
        return defaultServer(o);
      };
      await pumpStac(tester, const {'type': 'text', 'data': 't'}, dio: dio);
      Response<dynamic>? response;
      dio
          .get<dynamic>(
            'https://x.test/plain',
            options: Options(headers: {'Authorization': 'old'}),
          )
          .then((r) => response = r);
      await settle(tester);
      expect(response?.statusCode, 200);
      expect(hits['/recover-endpoint'], 1);
      expect(sent('/plain').map((r) => r.headers['Authorization']), [
        'old',
        'new',
      ]);
      // recover's setState ran in the global scope: the token changed.
      expect(global('tok'), 'new');
    });
  });

  group('final error', () {
    testWidgets('a failing repetition is the final error, not recovered', (
      tester,
    ) async {
      server = (o) {
        if (o.uri.path == '/data') {
          hits['/data'] = (hits['/data'] ?? 0) + 1;
          return _envelope(_recovery(), status: hits['/data'] == 1 ? 401 : 403);
        }
        return defaultServer(o);
      };
      final error = await load(tester);
      expect(error, isA<StacRecoveryException>());
      final e = error as StacRecoveryException;
      expect(e.retried, isTrue);
      expect(e.result, StacRecoveryResult.success);
      expect(e.lastError.response?.statusCode, 403);
      expect(e.response?.statusCode, 403);
      expect(e.envelope?.code, 'session_expired');
      expect(e.original.response?.statusCode, 401);
      expect(hits['/recover-endpoint'], 1);
      expect(hits['/data'], 2);
      expect(e.hookRan, isFalse);
    });

    testWidgets('requests of recover and the repetition are never recovered', (
      tester,
    ) async {
      server = (o) {
        hits[o.uri.path] = (hits[o.uri.path] ?? 0) + 1;
        if (o.uri.path == '/recover-endpoint') {
          // The refresh itself answers with a recovery envelope.
          return _envelope(_recovery());
        }
        return _envelope(_recovery());
      };
      final error = await load(tester);
      final e = error as StacRecoveryException;
      expect(e.result, StacRecoveryResult.failure);
      expect(e.retried, isFalse);
      // The last request that failed in `recover` is the last error observed.
      expect(e.lastError.requestOptions.uri.path, '/recover-endpoint');
      expect(e.original.requestOptions.uri.path, '/data');
      expect(hits['/recover-endpoint'], 1);
      expect(hits['/data'], 1);
      expect(StacRecoveryInterceptor.instance.runsInFlight, 0);
    });

    testWidgets('a body that cannot be sent twice is not recovered', (
      tester,
    ) async {
      server = (o) {
        hits[o.uri.path] = (hits[o.uri.path] ?? 0) + 1;
        return _envelope(_recovery());
      };
      await pumpStac(tester, const {'type': 'text', 'data': 't'}, dio: dio);
      final context = tester.element(find.text('t'));
      Object? error;
      StacNetworkService.request(
        context,
        StacNetworkRequest(
          url: 'https://x.test/up',
          method: Method.post,
          body: FormData.fromMap({'a': 'b'}),
        ),
      ).then<void>((_) {}, onError: (Object e) => error = e);
      await settle(tester);
      expect(error, isA<DioException>());
      expect(error, isNot(isA<StacRecoveryException>()));
      expect(stacEnvelopeOf(error), isNotNull);
      expect(adapter.requests, hasLength(1));
    });
  });

  group('without recovery', () {
    for (final entry in {
      'no envelope': const FakeResponse({'error': 'x'}, statusCode: 401),
      'envelope without recovery': _envelope(null),
      'unsupported version': FakeResponse(
        {'version': 2, 'recovery': _recovery()},
        statusCode: 401,
        headers: {
          'content-type': [_envelopeType],
        },
      ),
      'envelope in a 2xx': FakeResponse(
        {'version': 1, 'recovery': _recovery()},
        headers: {
          'content-type': [_envelopeType],
        },
      ),
    }.entries) {
      testWidgets('${entry.key}: the plain behavior', (tester) async {
        server = (o) {
          hits[o.uri.path] = (hits[o.uri.path] ?? 0) + 1;
          return entry.value;
        };
        await pumpScreen(tester, [_button('1', _data())]);
        await tester.tap(find.text('go1'));
        await settle(tester);
        expect(adapter.requests, hasLength(1));
        final failed = entry.value.statusCode != 200;
        expect(local(tester, 'err'), failed ? 1 : 0);
        expect(local(tester, 'ok'), failed ? 0 : 1);
        expect(local(tester, 'fin'), 1);
      });
    }

    testWidgets('an envelope without recovery stays attached to the error', (
      tester,
    ) async {
      server = (o) => _envelope(null);
      final error = await load(tester);
      expect(error, isA<DioException>());
      expect(error, isNot(isA<StacRecoveryException>()));
      expect(stacEnvelopeOf(error)?.code, 'session_expired');
    });

    testWidgets('a network error without response is never recovered', (
      tester,
    ) async {
      server = (o) {
        hits[o.uri.path] = (hits[o.uri.path] ?? 0) + 1;
        throw DioException.connectionError(
          requestOptions: o,
          reason: 'offline',
        );
      };
      final error = await load(tester);
      expect(error, isA<DioException>());
      expect(error, isNot(isA<StacRecoveryException>()));
      expect(adapter.requests, hasLength(1));
    });
  });

  group('cancellation and a dying leader', () {
    testWidgets('a cancelled request is not repeated; the run goes on', (
      tester,
    ) async {
      final error = await load(
        tester,
        onStart: (l) =>
            Future<void>.delayed(const Duration(milliseconds: 40), l.dispose),
      );
      expect(error, isA<DioException>());
      expect((error as DioException).type, DioExceptionType.cancel);
      expect(error, isNot(isA<StacRecoveryException>()));
      expect(sent('/data'), hasLength(1));
      // The shared execution was not stopped by one request leaving.
      expect(hits['/recover-endpoint'], 1);
      expect(global('tok'), 'new');
    });

    testWidgets('the leader screen dies: recover finishes, others repeat', (
      tester,
    ) async {
      await initStacForTest(dio: dio);
      final showA = ValueNotifier<bool>(true);
      addTearDown(showA.dispose);
      await pumpStacWidget(
        tester,
        ValueListenableBuilder<bool>(
          valueListenable: showA,
          builder: (context, visible, _) => Column(
            children: [
              if (visible)
                Builder(
                  key: const ValueKey('A'),
                  builder: (c) => StacService.fromJson(
                    _screen([_button('A', _data(tag: 'A'))]),
                    c,
                  )!,
                ),
              Builder(
                key: const ValueKey('B'),
                builder: (c) => StacService.fromJson(
                  _screen([_button('B', _data(tag: 'B'))]),
                  c,
                )!,
              ),
            ],
          ),
        ),
      );
      await tester.tap(find.text('goA'));
      await tester.tap(find.text('goB'));
      await tester.pump(const Duration(milliseconds: 40));
      // A led the recovery; its screen goes away while `recover` runs.
      showA.value = false;
      await settle(tester);

      expect(find.text('goA'), findsNothing);
      expect(hits['/recover-endpoint'], 1);
      expect(global('tok'), 'new', reason: 'recover ran to the end');
      final data = sent('/data');
      expect(data.where((r) => r.headers['X-N'] == 'A'), hasLength(1));
      expect(data.where((r) => r.headers['X-N'] == 'B'), hasLength(2));
      expect(local(tester, 'ok', 'B'), 1);
    });
  });

  group('result and hooks', () {
    Future<StacRecoveryException> failed(
      WidgetTester tester,
      FakeResponse refresh, {
      Map<String, dynamic>? recovery,
    }) async {
      server = (o) {
        hits[o.uri.path] = (hits[o.uri.path] ?? 0) + 1;
        if (o.uri.path == '/recover-endpoint') return refresh;
        return _envelope(recovery ?? _recovery());
      };
      return await load(tester) as StacRecoveryException;
    }

    testWidgets('4xx in recover = failure, onFailure runs once', (
      tester,
    ) async {
      final e = await failed(
        tester,
        const FakeResponse({'x': 1}, statusCode: 400),
        recovery: _recovery(
          onFailure: [
            {'actionType': 'incrementState', 'key': 'global.hook'},
            // A request of the hook: exempt, so its envelope is not followed.
            {'actionType': 'networkRequest', 'url': 'https://x.test/notify'},
          ],
          onUnavailable: _inc('global.hook'),
        ),
      );
      expect(e.result, StacRecoveryResult.failure);
      expect(e.onFailureRan, isTrue);
      expect(e.onUnavailableRan, isFalse);
      expect(global('hook'), 1);
      expect(hits['/notify'], 1);
      expect(hits['/recover-endpoint'], 1);
      expect(e.lastError.response?.statusCode, 400);
    });

    testWidgets('5xx in recover = unavailable, onUnavailable only', (
      tester,
    ) async {
      final e = await failed(
        tester,
        const FakeResponse({'x': 1}, statusCode: 503),
        recovery: _recovery(
          onFailure: {'actionType': 'incrementState', 'key': 'global.hook'},
          onUnavailable: [
            {'actionType': 'incrementState', 'key': 'global.hook'},
            {'actionType': 'incrementState', 'key': 'global.hook'},
          ],
        ),
      );
      expect(e.result, StacRecoveryResult.unavailable);
      expect(e.onFailureRan, isFalse);
      expect(e.onUnavailableRan, isTrue);
      expect(global('hook'), 2);
    });

    testWidgets('a network error in recover = unavailable', (tester) async {
      server = (o) {
        hits[o.uri.path] = (hits[o.uri.path] ?? 0) + 1;
        if (o.uri.path == '/recover-endpoint') {
          throw DioException.connectionError(
            requestOptions: o,
            reason: 'offline',
          );
        }
        return _envelope(_recovery());
      };
      final e = await load(tester) as StacRecoveryException;
      expect(e.result, StacRecoveryResult.unavailable);
      expect(e.lastError.response, isNull);
    });

    testWidgets('no failed request in recover = success', (tester) async {
      server = (o) {
        hits[o.uri.path] = (hits[o.uri.path] ?? 0) + 1;
        return o.headers['X-Token'] == 'old'
            ? _envelope(
                _recovery(
                  recover: {
                    'actionType': 'setState',
                    'values': {'global.tok': 'fresh'},
                  },
                ),
              )
            : const FakeResponse({'type': 'text', 'data': 'dest'});
      };
      final response = await load(tester);
      expect(response, isA<Response<dynamic>>());
      expect(sent('/data').last.headers['X-Token'], 'fresh');
    });

    testWidgets('5 concurrent failures: onFailure runs once', (tester) async {
      server = (o) {
        hits[o.uri.path] = (hits[o.uri.path] ?? 0) + 1;
        if (o.uri.path == '/recover-endpoint') {
          return const FakeResponse({}, statusCode: 400);
        }
        return _envelope(
          _recovery(
            onFailure: {'actionType': 'incrementState', 'key': 'global.hook'},
          ),
          delay: const Duration(milliseconds: 20),
        );
      };
      final tags = ['1', '2', '3', '4', '5'];
      await pumpScreen(tester, [
        for (final t in tags) _button(t, _data(tag: t)),
      ]);
      for (final t in tags) {
        await tester.tap(find.text('go$t'));
      }
      await settle(tester);
      expect(hits['/recover-endpoint'], 1);
      expect(global('hook'), 1);
      expect(local(tester, 'err'), 5, reason: 'each caller ends in onError');
      expect(local(tester, 'fin'), 5);
    });

    testWidgets('nothing runs when no request is alive', (tester) async {
      server = (o) {
        hits[o.uri.path] = (hits[o.uri.path] ?? 0) + 1;
        if (o.uri.path == '/recover-endpoint') {
          return const FakeResponse(
            {},
            statusCode: 400,
            delay: Duration(milliseconds: 50),
          );
        }
        return _envelope(
          _recovery(
            onFailure: {'actionType': 'incrementState', 'key': 'global.hook'},
          ),
        );
      };
      await load(
        tester,
        onStart: (l) =>
            Future<void>.delayed(const Duration(milliseconds: 20), l.dispose),
      );
      await settle(tester);
      expect(hits['/recover-endpoint'], 1);
      expect(global('hook'), 0);
    });

    testWidgets('timeoutMs makes the result unavailable', (tester) async {
      final e = await failed(
        tester,
        const FakeResponse({}),
        recovery: _recovery(
          recover: {'actionType': 'delay', 'milliseconds': 5000},
          timeoutMs: 100,
          onUnavailable: {'actionType': 'incrementState', 'key': 'global.hook'},
        ),
      );
      expect(e.result, StacRecoveryResult.unavailable);
      expect(e.onUnavailableRan, isTrue);
      expect(global('hook'), 1);
      expect(hits['/data'], 1);
      // Let the abandoned `delay` of recover end.
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('an explicit emission wins over the deduction', (tester) async {
      // 503 would be `unavailable`; the recovery says `success`.
      server = (o) {
        hits[o.uri.path] = (hits[o.uri.path] ?? 0) + 1;
        if (o.uri.path == '/recover-endpoint') {
          return const FakeResponse({}, statusCode: 503);
        }
        return o.headers['X-Token'] == 'old'
            ? _envelope(
                _recovery(
                  recover: [
                    _refresh(),
                    {'actionType': 'recoveryOutcome', 'result': 'success'},
                    {'actionType': 'recoveryOutcome', 'result': 'failure'},
                  ],
                ),
              )
            : const FakeResponse({'type': 'text', 'data': 'dest'});
      };
      await load(tester);
      expect(hits['/data'], 2, reason: 'first emission (success) won');

      // And 200 would be `success`; the recovery says `failure`.
      StacRecoveryInterceptor.instance.reset();
      hits.clear();
      server = (o) {
        hits[o.uri.path] = (hits[o.uri.path] ?? 0) + 1;
        if (o.uri.path == '/recover-endpoint') {
          return const FakeResponse({'token': 'x'});
        }
        return _envelope(
          _recovery(
            recover: [
              _refresh(),
              {'actionType': 'recoveryOutcome', 'result': 'failure'},
            ],
          ),
        );
      };
      final error = await load(tester);
      expect(
        (error as StacRecoveryException).result,
        StacRecoveryResult.failure,
      );
    });

    testWidgets('condition: a false condition does not emit', (tester) async {
      server = (o) {
        hits[o.uri.path] = (hits[o.uri.path] ?? 0) + 1;
        if (o.uri.path == '/recover-endpoint') {
          return const FakeResponse({'token': 'x'});
        }
        return _envelope(
          _recovery(
            recover: [
              _refresh(),
              {
                'actionType': 'recoveryOutcome',
                'result': 'failure',
                'condition': false,
              },
              {
                'actionType': 'recoveryOutcome',
                'result': 'unavailable',
                'condition': true,
              },
            ],
          ),
        );
      };
      final e = await load(tester) as StacRecoveryException;
      expect(e.result, StacRecoveryResult.unavailable);
    });

    testWidgets('an exception in recover = failure', (tester) async {
      server = (o) {
        hits[o.uri.path] = (hits[o.uri.path] ?? 0) + 1;
        return _envelope(
          _recovery(
            recover: [
              {'actionType': 'testThrow'},
            ],
            onFailure: {'actionType': 'incrementState', 'key': 'global.hook'},
          ),
        );
      };
      final e = await load(tester) as StacRecoveryException;
      expect(e.result, StacRecoveryResult.failure);
      expect(global('hook'), 1);
    });

    testWidgets('recoveryOutcome outside a recovery is a no-op', (
      tester,
    ) async {
      await pumpScreen(tester, [
        _button('1', {'actionType': 'recoveryOutcome', 'result': 'failure'}),
      ]);
      await tester.tap(find.text('go1'));
      await settle(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('recoveryOutcome inside a hook stays a no-op', (tester) async {
      final e = await failed(
        tester,
        const FakeResponse({}, statusCode: 400),
        recovery: _recovery(
          onFailure: [
            {'actionType': 'recoveryOutcome', 'result': 'success'},
            {'actionType': 'incrementState', 'key': 'global.hook'},
          ],
        ),
      );
      expect(e.result, StacRecoveryResult.failure);
      expect(global('hook'), 1);
    });

    testWidgets('G7-B: onFailure that requests an envelope does not recover', (
      tester,
    ) async {
      for (final hook in [
        {'actionType': 'networkRequest', 'url': 'https://x.test/target'},
        {
          'actionType': 'navigate',
          'request': {'url': 'https://x.test/target', 'method': 'get'},
        },
      ]) {
        StacRecoveryInterceptor.instance.reset();
        hits.clear();
        server = (o) {
          hits[o.uri.path] = (hits[o.uri.path] ?? 0) + 1;
          if (o.uri.path == '/recover-endpoint') {
            return const FakeResponse({}, statusCode: 400);
          }
          // /data and /target both answer with a recovery envelope.
          return _envelope(_recovery(onFailure: hook));
        };
        final e = await load(tester) as StacRecoveryException;
        await settle(tester);
        expect(e.result, StacRecoveryResult.failure);
        expect(
          hits['/recover-endpoint'],
          1,
          reason: 'no second recovery (${hook['actionType']})',
        );
        expect(hits['/target'], 1, reason: 'the hook request ran once');
        expect(hits['/data'], 1);
      }
    });
  });

  group('StacRecoveryRun', () {
    test('the first emission wins and none is taken outside a recovery', () {
      final run = StacRecoveryRun(
        identity: 'i',
        instruction: const StacRecoveryInstruction(recover: {}),
      );
      expect(run.emit(StacRecoveryResult.unavailable, condition: 'c'), isTrue);
      expect(run.emit(StacRecoveryResult.success), isFalse);
      expect(StacRecoveryRun.current, isNull);
      expect(StacRecoveryRun.emitCurrent(StacRecoveryResult.failure), isFalse);
    });
  });

  group('installation', () {
    tearDown(() => StacNetworkService.initialize(dio));

    test('is not duplicated and moves with the Dio', () {
      int count(Dio d) =>
          d.interceptors.whereType<StacRecoveryInterceptor>().length;
      StacNetworkService.initialize(dio);
      StacNetworkService.initialize(dio);
      expect(count(dio), 1);

      final other = Dio();
      StacNetworkService.initialize(other);
      StacNetworkService.initialize(other);
      expect(count(other), 1);
      expect(count(dio), 0);
    });
  });
}
