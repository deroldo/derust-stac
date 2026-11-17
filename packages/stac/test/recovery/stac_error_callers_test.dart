import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:stac/src/recovery/stac_recovery_interceptor.dart';
import 'package:stac/stac.dart';

import '../state/harness.dart';

const _envelopeType = 'application/vnd.stac.error+json';

Map<String, dynamic> _state(String key) => StacBinding.state(key);

Map<String, dynamic> _append(Object? value) => {
  'actionType': 'appendState',
  'key': 'log',
  'value': value,
};

Map<String, dynamic> _recovery({Object? onFailure}) => {
  'recover': {
    'actionType': 'networkRequest',
    'url': 'https://x.test/recover-endpoint',
    'method': 'post',
    'onSuccess': {
      'actionType': 'setState',
      'values': {'global.tok': _state('response.body.token')},
    },
  },
  'onFailure': ?onFailure,
};

FakeResponse _envelope({
  Map<String, dynamic>? recovery,
  Map<String, dynamic>? screen,
  Map<String, dynamic>? action,
  int status = 401,
}) => FakeResponse(
  {
    'version': 1,
    'code': 'some_code',
    'recovery': ?recovery,
    'screen': ?screen,
    'action': ?action,
  },
  statusCode: status,
  headers: {
    'content-type': [_envelopeType],
  },
);

const _destination = FakeResponse({'type': 'text', 'data': 'dest'});

Map<String, dynamic> _request({Map<String, dynamic> extra = const {}}) => {
  'actionType': 'networkRequest',
  'url': 'https://x.test/data',
  'method': 'get',
  'headers': {'X-Token': _state('global.tok')},
  ...extra,
};

Map<String, dynamic> _screen(List<Map<String, dynamic>> children) => {
  'type': 'column',
  'globalState': {'tok': 'old', 'hook': 0},
  'state': {'log': <Object?>[]},
  'children': children,
};

Map<String, dynamic> _button(Map<String, dynamic> action) => {
  'type': 'textButton',
  'onPressed': action,
  'child': {'type': 'text', 'data': 'go'},
};

void main() {
  final adapter = FakeDioAdapter();
  final dio = Dio()..httpClientAdapter = adapter;
  late FakeResponse Function(RequestOptions) data;
  late FakeResponse Function(RequestOptions) refresh;

  setUp(() {
    adapter.requests.clear();
    data = (o) => o.headers['X-Token'] == 'new'
        ? _destination
        : _envelope(recovery: _recovery());
    refresh = (_) => const FakeResponse({'token': 'new'});
    adapter.responder = (o) =>
        o.uri.path == '/recover-endpoint' ? refresh(o) : data(o);
    StacRecoveryInterceptor.instance.reset();
    StacGlobalState.instance.store
      ..declare('tok', 'old')
      ..write('tok', 'old')
      ..declare('hook', 0)
      ..write('hook', 0);
  });

  tearDown(() => Stac.genericErrorBuilder = null);

  Future<void> settle(WidgetTester tester) async {
    for (var t = 0; t < 400; t += 10) {
      await tester.pump(const Duration(milliseconds: 10));
    }
  }

  Future<void> pumpScreen(
    WidgetTester tester,
    List<Map<String, dynamic>> children,
  ) async {
    await pumpStac(tester, _screen(children), dio: dio);
  }

  Map<String, dynamic> networkWidget({Map<String, dynamic>? errorWidget}) => {
    'type': 'networkWidget',
    'request': _request(),
    'errorWidget': ?errorWidget,
  };

  List<Object?> log(WidgetTester tester, [String text = 'go']) =>
      (StacStateScope.storeOf(
                tester.element(find.text(text, skipOffstage: false)),
              )!.read('log')
              as List)
          .cast<Object?>();

  group('fromNetwork final result', () {
    testWidgets('recoverable request renders the screen', (tester) async {
      await pumpScreen(tester, [networkWidget()]);
      await settle(tester);
      expect(find.text('dest'), findsOneWidget);
      expect(adapter.requests.map((r) => r.uri.path), [
        '/data',
        '/recover-endpoint',
        '/data',
      ]);
    });

    testWidgets('unrecoverable error renders the envelope screen', (
      tester,
    ) async {
      data = (_) => _envelope(
        status: 500,
        screen: {'type': 'text', 'data': 'server error screen'},
      );
      await pumpScreen(tester, [networkWidget()]);
      await settle(tester);
      expect(find.text('server error screen'), findsOneWidget);
      expect(find.text('Could not load'), findsNothing);
    });

    testWidgets('envelope screen of the repetition is the final screen', (
      tester,
    ) async {
      data = (o) => o.headers['X-Token'] == 'new'
          ? _envelope(status: 403, screen: {'type': 'text', 'data': 'denied'})
          : _envelope(recovery: _recovery());
      await pumpScreen(tester, [networkWidget()]);
      await settle(tester);
      expect(find.text('denied'), findsOneWidget);
    });

    testWidgets('no envelope: the built-in generic error, never blank', (
      tester,
    ) async {
      data = (_) => const FakeResponse({'x': 1}, statusCode: 500);
      await pumpScreen(tester, [networkWidget()]);
      await settle(tester);
      expect(find.text('Could not load'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('failed recovery without envelope: generic error', (
      tester,
    ) async {
      refresh = (_) => const FakeResponse({'x': 1}, statusCode: 500);
      await pumpScreen(tester, [networkWidget()]);
      await settle(tester);
      expect(find.text('Could not load'), findsOneWidget);
    });

    testWidgets('the errorWidget of networkWidget is used without envelope', (
      tester,
    ) async {
      data = (_) => const FakeResponse({'x': 1}, statusCode: 500);
      await pumpScreen(tester, [
        networkWidget(errorWidget: {'type': 'text', 'data': 'mine'}),
      ]);
      await settle(tester);
      expect(find.text('mine'), findsOneWidget);
      expect(find.text('Could not load'), findsNothing);
    });

    testWidgets('onFailure ran: the error is not rendered (G6b)', (
      tester,
    ) async {
      refresh = (_) => const FakeResponse({'x': 1}, statusCode: 400);
      data = (_) => _envelope(
        recovery: _recovery(
          onFailure: {'actionType': 'incrementState', 'key': 'global.hook'},
        ),
        screen: {'type': 'text', 'data': 'final screen'},
      );
      await pumpScreen(tester, [networkWidget()]);
      await settle(tester);
      expect(StacGlobalState.instance.store.read('hook'), 1);
      expect(find.text('Could not load'), findsNothing);
      expect(find.text('final screen'), findsNothing);
    });

    testWidgets('custom genericErrorBuilder', (tester) async {
      Object? seen;
      Stac.genericErrorBuilder = (context, error) {
        seen = error;
        return const Text('custom error');
      };
      data = (_) => const FakeResponse({'x': 1}, statusCode: 500);
      await pumpScreen(tester, [networkWidget()]);
      await settle(tester);
      expect(find.text('custom error'), findsOneWidget);
      expect(find.text('Could not load'), findsNothing);
      expect(seen, isA<DioException>());
    });

    testWidgets('genericErrorBuilder can turn it off', (tester) async {
      Stac.genericErrorBuilder = (_, _) => const SizedBox();
      data = (_) => const FakeResponse({'x': 1}, statusCode: 500);
      await pumpScreen(tester, [networkWidget()]);
      await settle(tester);
      expect(find.text('Could not load'), findsNothing);
      expect(find.byIcon(Icons.error_outline), findsNothing);
    });
  });

  group('callbacks of a carried request', () {
    testWidgets('navigate.request honors onError and onFinally', (
      tester,
    ) async {
      data = (_) => _envelope(
        status: 500,
        screen: {'type': 'text', 'data': 'error screen'},
        action: _append('action'),
      );
      await pumpScreen(tester, [
        _button({
          'actionType': 'navigate',
          'request': _request(
            extra: {
              'onError': _append(_state('response.statusCode')),
              'onFinally': _append('fin'),
            },
          ),
        }),
      ]);
      await tester.tap(find.text('go'));
      await settle(tester);
      expect(find.text('error screen'), findsOneWidget);
      // G13: onError, onFinally, then the server's action.
      expect(log(tester), [500, 'fin', 'action']);
    });

    testWidgets('onError is not run when the request ends well', (
      tester,
    ) async {
      await pumpScreen(tester, [
        _button({
          'actionType': 'navigate',
          'request': _request(
            extra: {'onError': _append('err'), 'onFinally': _append('fin')},
          ),
        }),
      ]);
      await tester.tap(find.text('go'));
      await settle(tester);
      expect(find.text('dest'), findsOneWidget);
      expect(log(tester), ['fin']);
    });

    testWidgets('showDialog.request renders the generic error', (tester) async {
      data = (_) => const FakeResponse({'x': 1}, statusCode: 500);
      await pumpScreen(tester, [
        _button({'actionType': 'showDialog', 'request': _request()}),
      ]);
      await tester.tap(find.text('go'));
      await settle(tester);
      expect(find.text('Could not load'), findsOneWidget);
    });

    testWidgets('showModalBottomSheet.request renders the envelope screen', (
      tester,
    ) async {
      data = (_) => _envelope(
        status: 500,
        screen: {'type': 'text', 'data': 'sheet error'},
      );
      await pumpScreen(tester, [
        _button({'actionType': 'showModalBottomSheet', 'request': _request()}),
      ]);
      await tester.tap(find.text('go'));
      await settle(tester);
      expect(find.text('sheet error'), findsOneWidget);
    });

    testWidgets('envelope with only an action runs it, shows nothing', (
      tester,
    ) async {
      data = (_) => _envelope(status: 500, action: _append('action'));
      await pumpScreen(tester, [networkWidget(), _button(_append('noop'))]);
      await settle(tester);
      expect(find.text('Could not load'), findsNothing);
      expect(log(tester), ['action']);
    });

    testWidgets('onFailure ran: the envelope action does not run', (
      tester,
    ) async {
      refresh = (_) => const FakeResponse({'x': 1}, statusCode: 400);
      data = (_) => _envelope(
        recovery: _recovery(onFailure: _append('hook')),
        action: _append('action'),
      );
      await pumpScreen(tester, [networkWidget(), _button(_append('noop'))]);
      await settle(tester);
      expect(log(tester), ['hook']);
    });
  });

  group('networkRequest action', () {
    Map<String, dynamic> action({Map<String, dynamic>? extra}) => {
      ..._request(),
      'onSuccess': _append('ok'),
      'onError': _append('err'),
      'onFinally': _append('fin'),
      ...?extra,
    };

    testWidgets('onSuccess after the repetition, never an intermediate '
        'onError', (tester) async {
      await pumpScreen(tester, [_button(action())]);
      await tester.tap(find.text('go'));
      await settle(tester);
      expect(adapter.requests, hasLength(3));
      expect(log(tester), ['ok', 'fin']);
    });

    testWidgets('onError with the final error, onFinally, then the action', (
      tester,
    ) async {
      data = (_) => _envelope(status: 500, action: _append('action'));
      await pumpScreen(tester, [
        _button(
          action(extra: {'onError': _append(_state('response.body.code'))}),
        ),
      ]);
      await tester.tap(find.text('go'));
      await settle(tester);
      expect(log(tester), ['some_code', 'fin', 'action']);
    });

    testWidgets('failed repetition: one onError, with the final response', (
      tester,
    ) async {
      data = (o) => o.headers['X-Token'] == 'new'
          ? _envelope(status: 403, action: _append('action'))
          : _envelope(recovery: _recovery());
      await pumpScreen(tester, [
        _button(
          action(extra: {'onError': _append(_state('response.statusCode'))}),
        ),
      ]);
      await tester.tap(find.text('go'));
      await settle(tester);
      expect(log(tester), [403, 'fin', 'action']);
    });

    testWidgets('screen does not apply; onFailure ran: no action', (
      tester,
    ) async {
      refresh = (_) => const FakeResponse({'x': 1}, statusCode: 400);
      data = (_) => _envelope(
        recovery: _recovery(onFailure: _append('hook')),
        screen: {'type': 'text', 'data': 'never shown'},
        action: _append('action'),
      );
      await pumpScreen(tester, [_button(action())]);
      await tester.tap(find.text('go'));
      await settle(tester);
      expect(find.text('never shown'), findsNothing);
      expect(log(tester), ['hook', 'err', 'fin']);
    });
  });
}
