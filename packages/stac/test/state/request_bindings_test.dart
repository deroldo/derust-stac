import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

/// A request that is only *carried* by another action or widget (`navigate`,
/// `showDialog`, `showModalBottomSheet`, `networkWidget`, `dynamicView`) must
/// have the bindings of its `headers`, `body` and `queryParameters` resolved
/// before it reaches the network, exactly like a plain `networkRequest`.
/// Regression: the raw binding map was sent (Dio printed `{$state: x}`).
void main() {
  final adapter = FakeDioAdapter();
  final dio = Dio()..httpClientAdapter = adapter;

  setUp(() {
    adapter.requests.clear();
    adapter.enqueue(const FakeResponse({'type': 'text', 'data': 'dest'}));
  });

  Map<String, dynamic> request({String method = 'get'}) => {
    'actionType': 'networkRequest',
    'url': 'https://x.test/screen',
    'method': method,
    'headers': {
      'X-Refresh': {r'$state': 'global.refreshToken'},
      'X-Screen': {r'$state': 'token'},
      'X-Expr': {r'$expr': "'Bearer ' + token"},
      'X-Plain': 'literal',
    },
    'queryParameters': {
      'q': {r'$state': 'token'},
    },
    if (method != 'get')
      'body': {
        'refresh_token': {r'$state': 'global.refreshToken'},
        'nested': {
          'deep': {r'$state': 'token'},
        },
      },
  };

  Map<String, dynamic> screen(Map<String, dynamic> child) => {
    'type': 'column',
    'globalState': {'refreshToken': 'rt-secret'},
    'state': {'token': 'abc123'},
    'children': [child],
  };

  Map<String, dynamic> button(Map<String, dynamic> action) => {
    'type': 'textButton',
    'onPressed': action,
    'child': {'type': 'text', 'data': 'go'},
  };

  void expectResolved(RequestOptions options, {bool hasBody = false}) {
    expect(options.headers['X-Refresh'], 'rt-secret');
    expect(options.headers['X-Screen'], 'abc123');
    expect(options.headers['X-Expr'], 'Bearer abc123');
    expect(options.headers['X-Plain'], 'literal');
    expect(options.queryParameters['q'], 'abc123');
    if (hasBody) {
      expect(options.data, {
        'refresh_token': 'rt-secret',
        'nested': {'deep': 'abc123'},
      });
    }
  }

  Future<void> tapGo(WidgetTester tester) async {
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(adapter.requests, hasLength(1));
  }

  testWidgets('networkRequest (control) resolves its own request', (
    tester,
  ) async {
    await pumpStac(tester, screen(button(request(method: 'post'))), dio: dio);
    await tapGo(tester);
    expectResolved(adapter.requests.single, hasBody: true);
  });

  testWidgets('navigate.request resolves headers, query and body', (
    tester,
  ) async {
    await pumpStac(
      tester,
      screen(
        button({'actionType': 'navigate', 'request': request(method: 'post')}),
      ),
      dio: dio,
    );
    await tapGo(tester);
    expectResolved(adapter.requests.single, hasBody: true);
    expect(find.text('dest'), findsOneWidget);
  });

  testWidgets('showDialog.request resolves its bindings', (tester) async {
    await pumpStac(
      tester,
      screen(button({'actionType': 'showDialog', 'request': request()})),
      dio: dio,
    );
    await tapGo(tester);
    expectResolved(adapter.requests.single);
    expect(find.text('dest'), findsOneWidget);
  });

  testWidgets('showModalBottomSheet.request resolves its bindings', (
    tester,
  ) async {
    await pumpStac(
      tester,
      screen(
        button({'actionType': 'showModalBottomSheet', 'request': request()}),
      ),
      dio: dio,
    );
    await tapGo(tester);
    expectResolved(adapter.requests.single);
    expect(find.text('dest'), findsOneWidget);
  });

  testWidgets('networkWidget.request resolves its bindings', (tester) async {
    await pumpStac(
      tester,
      screen({'type': 'networkWidget', 'request': request()}),
      dio: dio,
    );
    await tester.pumpAndSettle();
    expect(adapter.requests, hasLength(1));
    expectResolved(adapter.requests.single);
    expect(find.text('dest'), findsOneWidget);
  });

  testWidgets('dynamicView.request resolves its bindings', (tester) async {
    await pumpStac(
      tester,
      screen({'type': 'dynamicView', 'request': request()}),
      dio: dio,
    );
    await tester.pumpAndSettle();
    expect(adapter.requests, hasLength(1));
    expectResolved(adapter.requests.single);
  });

  testWidgets('a request without bindings is sent untouched', (tester) async {
    await pumpStac(
      tester,
      screen(
        button({
          'actionType': 'navigate',
          'request': {
            'actionType': 'networkRequest',
            'url': 'https://x.test/plain',
            'method': 'get',
            'headers': {'X-Plain': 'literal'},
          },
        }),
      ),
      dio: dio,
    );
    await tapGo(tester);
    expect(adapter.requests.single.headers['X-Plain'], 'literal');
    expect(find.text('dest'), findsOneWidget);
  });
}
