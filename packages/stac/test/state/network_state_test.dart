import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stac/src/state/stac_memory_state_store.dart';
import 'package:stac/stac.dart';

import 'harness.dart';

Map<String, dynamic> _state(String key) => StacBinding.state(key);
Map<String, dynamic> _expr(String e) => StacBinding.expr(e);

/// Like [FakeDioAdapter], but answers per URL path: a request cancelled before
/// it reaches the adapter must not shift the responses of the others.
class _RoutedAdapter implements HttpClientAdapter {
  final Map<String, List<FakeResponse>> _queues = {};
  final List<RequestOptions> requests = [];

  void enqueue(FakeResponse response, {String url = '/api'}) =>
      (_queues[url] ??= []).add(response);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final queue = _queues[options.path];
    if (queue == null || queue.isEmpty) {
      throw StateError('no queued response for ${options.path}');
    }
    final response = queue.removeAt(0);
    if (response.delay > Duration.zero) {
      await Future<void>.delayed(response.delay);
    }
    return ResponseBody.fromBytes(
      utf8.encode(jsonEncode(response.body)),
      response.statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

final _adapter = _RoutedAdapter();
final _dio = Dio()..httpClientAdapter = _adapter;

int _probeBuilds = 0;

class _ProbeParser extends StacParser<Map<String, dynamic>> {
  const _ProbeParser();

  @override
  String get type => 'netProbe';

  @override
  Map<String, dynamic> getModel(Map<String, dynamic> json) => json;

  @override
  Widget parse(BuildContext context, Map<String, dynamic> model) {
    _probeBuilds++;
    return Text('probe:${model['a']}:${model['b']}');
  }
}

Map<String, dynamic> _set(Map<String, Object?> values) => {
  'actionType': 'setState',
  'values': values,
};

Map<String, dynamic> _inc(String key) => {
  'actionType': 'incrementState',
  'key': key,
};

Map<String, dynamic> _append(String key, Object? value) => {
  'actionType': 'appendState',
  'key': key,
  'value': value,
};

Map<String, dynamic> _request({
  String url = '/api',
  String? requestKey,
  Object? onStart,
  Object? onSuccess,
  Object? onError,
  Object? onFinally,
  Map<String, dynamic>? extra,
}) => {
  'actionType': 'networkRequest',
  'url': url,
  'requestKey': ?requestKey,
  'onStart': ?onStart,
  'onSuccess': ?onSuccess,
  'onError': ?onError,
  'onFinally': ?onFinally,
  ...?extra,
};

late StacStateStore _store;

Future<void> _pump(
  WidgetTester tester,
  Map<String, Object?> initial, {
  Widget Function(BuildContext)? body,
}) async {
  await initStacForTest(dio: _dio);
  if (StacRegistry.instance.getParser('netProbe') == null) {
    StacRegistry.instance.register(const _ProbeParser());
  }
  await pumpStacWidget(
    tester,
    StacStateScope(
      initialState: initial,
      child: Builder(
        builder: (context) {
          _store = StacStateScope.storeOf(context)!;
          return body?.call(context) ?? const SizedBox();
        },
      ),
    ),
  );
}

BuildContext _ctx(WidgetTester tester) => tester.element(
  find
      .descendant(
        of: find.byType(StacStateScope),
        matching: find.byType(Builder),
      )
      .first,
);

/// Fires [action] without waiting for it.
void _fire(WidgetTester tester, Map<String, dynamic> action) {
  StacService.onCallFromJson(action, _ctx(tester));
}

Future<void> _settle(WidgetTester tester, [int ms = 500]) async {
  await tester.pump(Duration(milliseconds: ms));
  await tester.pump();
}

void main() {
  setUp(() {
    StacGlobalState.instance.clear();
    _adapter
      ..requests.clear()
      .._queues.clear();
  });

  group('lifecycle', () {
    testWidgets(
      'onStart -> onSuccess -> onFinally, one rebuild for many keys',
      (tester) async {
        await _pump(
          tester,
          {'a': 0, 'b': 0, 'carregando': false, 'log': <Object?>[]},
          body: (c) => StacService.fromJson({
            'type': 'netProbe',
            'a': _state('a'),
            'b': _state('b'),
          }, c)!,
        );
        _adapter.enqueue(
          const FakeResponse({
            'x': 1,
            'y': 2,
          }, delay: Duration(milliseconds: 50)),
        );
        _probeBuilds = 0;
        _fire(
          tester,
          _request(
            onStart: [
              _set({'carregando': true}),
              _append('log', 'start'),
            ],
            onSuccess: [
              _set({
                'a': _state('response.body.x'),
                'b': _state('response.body.y'),
              }),
              _append('log', _expr('"ok" + response.statusCode')),
            ],
            onFinally: [
              _set({'carregando': false}),
              _append('log', 'finally'),
            ],
          ),
        );
        await tester.pump();
        expect(_store.read('carregando'), true);
        expect(_store.read('log'), ['start']);
        await _settle(tester, 100);
        expect(_store.read('a'), 1);
        expect(_store.read('b'), 2);
        expect(_store.read('carregando'), false);
        expect(_store.read('log'), ['start', 'ok200', 'finally']);
        expect(find.text('probe:1:2'), findsOneWidget);
        // a and b changed in a single setState: a single rebuild.
        expect(_probeBuilds, 1);
      },
    );

    testWidgets('200 with an error payload is handled by condition', (
      tester,
    ) async {
      await _pump(tester, {'erro': false, 'ok': false});
      _adapter.enqueue(const FakeResponse({'erro': true}));
      _fire(
        tester,
        _request(
          onSuccess: [
            {
              ..._set({'erro': true}),
              'condition': _expr('response.body.erro == true'),
            },
            {
              ..._set({'ok': true}),
              'condition': _expr('response.body.erro == false'),
            },
          ],
        ),
      );
      await _settle(tester);
      expect(_store.read('erro'), true);
      expect(_store.read('ok'), false);
    });

    testWidgets('500 runs onError (not onSuccess) and onFinally', (
      tester,
    ) async {
      await _pump(tester, {'log': <Object?>[]});
      _adapter.enqueue(const FakeResponse({'msg': 'boom'}, statusCode: 500));
      _fire(
        tester,
        _request(
          onSuccess: _append('log', 'success'),
          onError: _append('log', _expr('"err" + response.statusCode')),
          onFinally: _append('log', 'finally'),
        ),
      );
      await _settle(tester);
      expect(_store.read('log'), ['err500', 'finally']);
    });

    testWidgets('response.body is readable in onError', (tester) async {
      await _pump(tester, {'msg': ''});
      _adapter.enqueue(const FakeResponse({'msg': 'boom'}, statusCode: 422));
      _fire(
        tester,
        _request(onError: _set({'msg': _state('response.body.msg')})),
      );
      await _settle(tester);
      expect(_store.read('msg'), 'boom');
    });

    testWidgets('failure without response runs onError with null status', (
      tester,
    ) async {
      await _pump(tester, {'log': <Object?>[]});
      // Nothing queued: the adapter throws, like a connection failure.
      _fire(
        tester,
        _request(
          onError: _append('log', _expr('response.statusCode')),
          onFinally: _append('log', 'finally'),
        ),
      );
      await _settle(tester);
      expect(_store.read('log'), [null, 'finally']);
    });

    testWidgets('a single action (not a list) is accepted', (tester) async {
      await _pump(tester, {'n': 0});
      _adapter.enqueue(const FakeResponse({}));
      _fire(tester, _request(onSuccess: _inc('n'), onFinally: _inc('n')));
      await _settle(tester);
      expect(_store.read('n'), 2);
    });

    testWidgets(
      'legacy results run after the new lists and keep {{response}}',
      (tester) async {
        await _pump(tester, {'log': <Object?>[], 'legacy': ''});
        _adapter.enqueue(const FakeResponse({'name': 'Ana'}));
        _fire(
          tester,
          _request(
            onSuccess: _append('log', 'success'),
            onFinally: _append('log', 'finally'),
            extra: {
              'results': [
                {
                  'statusCode': 200,
                  'action': _set({'legacy': '{{response.name}}'}),
                },
              ],
            },
          ),
        );
        await _settle(tester);
        expect(_store.read('log'), ['success', 'finally']);
        expect(_store.read('legacy'), 'Ana');
      },
    );

    testWidgets('request bindings are evaluated at trigger time', (
      tester,
    ) async {
      await _pump(tester, {'q': 'abc'});
      _adapter.enqueue(const FakeResponse({}));
      _fire(
        tester,
        _request(
          extra: {
            'queryParameters': {'q': _state('q')},
          },
        ),
      );
      _store.write('q', 'changed');
      await _settle(tester);
      expect(_adapter.requests.single.queryParameters['q'], 'abc');
    });
  });

  group('ordering and cancellation (Review Focus 2)', () {
    testWidgets('a late response does not overwrite the newer one', (
      tester,
    ) async {
      await _pump(tester, {'v': '', 'fin': 0});
      // 1st request answers late (200ms), the 2nd early (50ms).
      _adapter
        ..enqueue(
          const FakeResponse({'v': 'old'}, delay: Duration(milliseconds: 200)),
          url: '/s1',
        )
        ..enqueue(
          const FakeResponse({'v': 'new'}, delay: Duration(milliseconds: 50)),
          url: '/s2',
        );
      Map<String, dynamic> req(String url) => _request(
        url: url,
        requestKey: 'search',
        onSuccess: _set({'v': _state('response.body.v')}),
        onFinally: _inc('fin'),
      );
      _fire(tester, req('/s1'));
      await tester.pump(const Duration(milliseconds: 10));
      _fire(tester, req('/s2'));
      await _settle(tester, 100);
      expect(_store.read('v'), 'new');
      await _settle(tester, 300);
      expect(_store.read('v'), 'new');
      // Only the newest request ran its onFinally.
      expect(_store.read('fin'), 1);
      expect(_adapter.requests, hasLength(2));
    });

    testWidgets('late error of a superseded request does not run onError', (
      tester,
    ) async {
      await _pump(tester, {'erro': false, 'v': ''});
      _adapter
        ..enqueue(
          const FakeResponse(
            {'e': 1},
            statusCode: 500,
            delay: Duration(milliseconds: 200),
          ),
          url: '/s1',
        )
        ..enqueue(
          const FakeResponse({'v': 'new'}, delay: Duration(milliseconds: 50)),
          url: '/s2',
        );
      _fire(
        tester,
        _request(url: '/s1', requestKey: 'k', onError: _set({'erro': true})),
      );
      await tester.pump();
      _fire(
        tester,
        _request(
          url: '/s2',
          requestKey: 'k',
          onSuccess: _set({'v': _state('response.body.v')}),
        ),
      );
      await _settle(tester, 400);
      expect(_store.read('erro'), false);
      expect(_store.read('v'), 'new');
    });

    testWidgets('remaining callbacks of a superseded request are dropped', (
      tester,
    ) async {
      await _pump(tester, {'v': ''});
      _adapter
        ..enqueue(const FakeResponse({'v': 'A'}), url: '/A')
        ..enqueue(
          const FakeResponse({'v': 'B'}, delay: Duration(milliseconds: 10)),
          url: '/B',
        );
      Map<String, dynamic> req(String tag) => _request(
        url: '/$tag',
        requestKey: 'k',
        onSuccess: [
          if (tag == 'A') {'actionType': 'delay', 'milliseconds': 100},
          _set({'v': _state('response.body.v')}),
        ],
      );
      _fire(tester, req('A'));
      await tester.pump(const Duration(milliseconds: 20));
      // A is now waiting in its delay; B starts and finishes first.
      _fire(tester, req('B'));
      await tester.pump(const Duration(milliseconds: 30));
      expect(_store.read('v'), 'B');
      await _settle(tester, 300);
      expect(_store.read('v'), 'B');
    });

    testWidgets('requests with different keys do not cancel each other', (
      tester,
    ) async {
      await _pump(tester, {'a': '', 'b': ''});
      _adapter
        ..enqueue(
          const FakeResponse({'v': 'A'}, delay: Duration(milliseconds: 50)),
          url: '/A',
        )
        ..enqueue(
          const FakeResponse({'v': 'B'}, delay: Duration(milliseconds: 20)),
          url: '/B',
        );
      _fire(
        tester,
        _request(
          url: '/A',
          requestKey: 'a',
          onSuccess: _set({'a': _state('response.body.v')}),
        ),
      );
      _fire(
        tester,
        _request(
          url: '/B',
          requestKey: 'b',
          onSuccess: _set({'b': _state('response.body.v')}),
        ),
      );
      await _settle(tester, 100);
      expect(_store.read('a'), 'A');
      expect(_store.read('b'), 'B');
    });

    testWidgets('cancelRequest discards the pending request', (tester) async {
      await _pump(tester, {'log': <Object?>[]});
      _adapter.enqueue(
        const FakeResponse({'v': 1}, delay: Duration(milliseconds: 100)),
      );
      _fire(
        tester,
        _request(
          requestKey: 'k',
          onSuccess: _append('log', 'success'),
          onFinally: _append('log', 'finally'),
        ),
      );
      await tester.pump(const Duration(milliseconds: 10));
      _fire(tester, {'actionType': 'cancelRequest', 'requestKey': 'k'});
      await _settle(tester, 300);
      expect(_store.read('log'), isEmpty);
      expect(StacStateScope.requestsOf(_ctx(tester)).pendingCount, 0);
    });

    testWidgets('cancelRequest for an unknown key is a no-op', (tester) async {
      await _pump(tester, {});
      _fire(tester, {'actionType': 'cancelRequest', 'requestKey': 'nope'});
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('no tokens are left after requests finish', (tester) async {
      await _pump(tester, {});
      _adapter
        ..enqueue(const FakeResponse({}))
        ..enqueue(const FakeResponse({}, statusCode: 500))
        ..enqueue(const FakeResponse({}));
      _fire(tester, _request(requestKey: 'k'));
      _fire(tester, _request());
      await _settle(tester, 100);
      _fire(tester, _request(requestKey: 'k'));
      await _settle(tester, 100);
      expect(StacStateScope.requestsOf(_ctx(tester)).pendingCount, 0);
    });

    testWidgets('screen closed before the response: nothing runs, no throw', (
      tester,
    ) async {
      await _pump(tester, {'x': 0});
      StacGlobalState.instance.store.declare('fin', 0);
      _adapter.enqueue(
        const FakeResponse({'v': 1}, delay: Duration(milliseconds: 100)),
      );
      final context = _ctx(tester);
      final requests = StacStateScope.requestsOf(context);
      StacService.onCallFromJson(
        _request(
          requestKey: 'k',
          onSuccess: _inc('global.fin'),
          onFinally: _inc('global.fin'),
        ),
        context,
      );
      await tester.pump(const Duration(milliseconds: 10));
      // The screen goes away while the request is in flight.
      await tester.pumpWidget(const SizedBox());
      await _settle(tester, 300);
      expect(tester.takeException(), isNull);
      expect(StacGlobalState.instance.store.read('fin'), 0);
      expect(requests.pendingCount, 0);
    });

    testWidgets('keyless request is also dropped when the screen closes', (
      tester,
    ) async {
      await _pump(tester, {});
      StacGlobalState.instance.store.declare('fin', 0);
      _adapter.enqueue(
        const FakeResponse({'v': 1}, delay: Duration(milliseconds: 100)),
      );
      StacService.onCallFromJson(
        _request(onSuccess: _inc('global.fin'), onFinally: _inc('global.fin')),
        _ctx(tester),
      );
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pumpWidget(const SizedBox());
      await _settle(tester, 300);
      expect(tester.takeException(), isNull);
      expect(StacGlobalState.instance.store.read('fin'), 0);
    });
  });

  group('bodyFromState', () {
    testWidgets('sends the listed keys, leaving out secure ones', (
      tester,
    ) async {
      final global = _SecureStore({'token'});
      StacGlobalState.instance.useStore(global);
      global
        ..declare('token', 'secret')
        ..declare('tema', 'dark');
      await _pump(tester, {'nome': 'Ana', 'idade': 30});
      _adapter.enqueue(const FakeResponse({}));
      _fire(tester, {
        'actionType': 'networkRequest',
        'url': '/save',
        'method': 'post',
        'bodyFromState': ['nome', 'global.tema', 'global.token'],
      });
      await _settle(tester);
      expect(_adapter.requests.single.data, {
        'nome': 'Ana',
        'global.tema': 'dark',
      });
    });

    testWidgets('an explicit body wins over bodyFromState', (tester) async {
      await _pump(tester, {'nome': 'Ana'});
      _adapter.enqueue(const FakeResponse({}));
      _fire(tester, {
        'actionType': 'networkRequest',
        'url': '/save',
        'method': 'post',
        'body': {'fixo': _state('nome')},
        'bodyFromState': ['nome'],
      });
      await _settle(tester);
      expect(_adapter.requests.single.data, {'fixo': 'Ana'});
    });

    testWidgets('reads the values at trigger time', (tester) async {
      await _pump(tester, {'nome': 'Ana'});
      _adapter.enqueue(const FakeResponse({}));
      _fire(tester, {
        'actionType': 'networkRequest',
        'url': '/save',
        'method': 'post',
        'bodyFromState': ['nome'],
      });
      _store.write('nome', 'Bia');
      await _settle(tester);
      expect(_adapter.requests.single.data, {'nome': 'Ana'});
    });
  });
}

/// Memory store that reports some keys as secure.
class _SecureStore extends StacMemoryStateStore {
  _SecureStore(this._secure);

  final Set<String> _secure;

  @override
  bool isSecure(String key) => _secure.contains(key);
}
