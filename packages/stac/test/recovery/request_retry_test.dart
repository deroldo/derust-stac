import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:stac/src/recovery/stac_request_template.dart';
import 'package:stac/src/services/stac_network_service.dart';
import 'package:stac/src/state/stac_global_state.dart';
import 'package:stac/src/state/stac_scope.dart';
import 'package:stac_core/actions/network_request/stac_network_request.dart';

import '../state/harness.dart';

const _ok = FakeResponse({'type': 'text', 'data': 'dest'});
const _unauthorized = FakeResponse({'error': 'x'}, statusCode: 401);

void main() {
  final adapter = FakeDioAdapter();
  final dio = Dio()..httpClientAdapter = adapter;

  setUp(() {
    adapter.requests.clear();
    // The global store outlives the widgets: start every test from 'old'.
    StacGlobalState.instance.store
      ..declare('tok', 'old')
      ..write('tok', 'old');
  });

  Map<String, dynamic> request({
    String method = 'get',
    Map<String, dynamic>? extra,
  }) => {
    'actionType': 'networkRequest',
    'url': 'https://x.test/a',
    'method': method,
    'contentType': 'application/json',
    'requestKey': 'rk',
    'headers': {
      'X-Token': {r'$state': 'global.tok'},
      'X-Screen': {r'$state': 'k'},
      'X-Plain': 'literal',
    },
    'queryParameters': {
      'q': {r'$state': 'k'},
    },
    if (method != 'get')
      'body': {
        'token': {r'$state': 'global.tok'},
        'keep': 1,
      },
    ...?extra,
  };

  Map<String, dynamic> screen(Map<String, dynamic> child) => {
    'type': 'column',
    'globalState': {'tok': 'old'},
    'state': {'k': 'screen-v1'},
    'children': [child],
  };

  Map<String, dynamic> button(Map<String, dynamic> action) => {
    'type': 'textButton',
    'onPressed': action,
    'child': {'type': 'text', 'data': 'go'},
  };

  Future<void> changeState(WidgetTester tester) async {
    StacGlobalState.instance.store.write('tok', 'new');
    StacStateScope.storeOf(
      tester.element(find.text('go')),
    )!.write('k', 'screen-v2');
  }

  Future<Response?> retry(
    WidgetTester tester,
    RequestOptions options, {
    Map<String, dynamic>? overrides,
    List<String>? removeHeaders,
  }) async {
    final result = await tester.runAsync(
      () => StacNetworkService.retryRequest(
        options,
        overrides: overrides,
        removeHeaders: removeHeaders,
      ),
    );
    return result;
  }

  group('retryRequest with a template', () {
    testWidgets('re-evaluates bindings, keeps url/method/token/exempt', (
      tester,
    ) async {
      adapter
        ..enqueue(_unauthorized)
        ..enqueue(_ok);
      await pumpStac(tester, screen(button(request(method: 'post'))), dio: dio);
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(adapter.requests, hasLength(1));
      final first = adapter.requests.single;
      expect(first.headers['X-Token'], 'old');
      expect(first.headers['X-Screen'], 'screen-v1');
      expect(first.extra[stacRecoveryExemptExtraKey], isNull);
      expect(StacRequestTemplate.of(first), isNotNull);

      await changeState(tester);
      await retry(tester, first);

      expect(adapter.requests, hasLength(2));
      final second = adapter.requests.last;
      expect(second.headers['X-Token'], 'new');
      expect(second.headers['X-Screen'], 'screen-v2');
      expect(second.headers['X-Plain'], 'literal');
      expect(second.queryParameters['q'], 'screen-v2');
      expect(second.data, {'token': 'new', 'keep': 1});
      expect(second.path, first.path);
      expect(second.method, first.method);
      expect(second.contentType, first.contentType);
      expect(second.cancelToken, same(first.cancelToken));
      expect(second.extra[stacRecoveryExemptExtraKey], true);
      expect(StacRequestTemplate.of(second)!.requestKey, 'rk');
    });

    testWidgets('overrides merge by key, null removes, values take bindings', (
      tester,
    ) async {
      adapter
        ..enqueue(_unauthorized)
        ..enqueue(_ok);
      await pumpStac(tester, screen(button(request(method: 'post'))), dio: dio);
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      final first = adapter.requests.single;
      await changeState(tester);

      await retry(
        tester,
        first,
        overrides: {
          'headers': {
            'x-token': 'explicit', // case-insensitive replace
            'X-Screen': null, // removed
            'X-Fresh': {r'$state': 'global.tok'}, // binding resolved now
          },
          'queryParameters': {'extra': '1'},
          'body': {'keep': null, 'added': true},
        },
        removeHeaders: ['X-PLAIN'],
      );

      final second = adapter.requests.last;
      expect(second.headers['X-Token'], 'explicit');
      expect(second.headers.containsKey('X-Screen'), isFalse);
      expect(second.headers['X-Fresh'], 'new');
      expect(second.headers.containsKey('X-Plain'), isFalse);
      expect(second.queryParameters, {'q': 'screen-v2', 'extra': '1'});
      expect(second.data, {'token': 'new', 'added': true});
      expect(second.path, first.path);
      expect(second.method, 'POST');
    });

    testWidgets('onStart is not run again', (tester) async {
      adapter
        ..enqueue(_ok) // onStart request
        ..enqueue(_unauthorized)
        ..enqueue(_ok);
      await pumpStac(
        tester,
        screen(
          button(
            request(
              extra: {
                'onStart': {
                  'actionType': 'networkRequest',
                  'url': 'https://x.test/start',
                },
              },
            ),
          ),
        ),
        dio: dio,
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(adapter.requests.map((r) => r.uri.path), ['/start', '/a']);

      await retry(tester, adapter.requests.last);
      expect(adapter.requests.map((r) => r.uri.path), ['/start', '/a', '/a']);
    });

    testWidgets('bodyFromState is read again on the repetition', (
      tester,
    ) async {
      adapter
        ..enqueue(_unauthorized)
        ..enqueue(_ok);
      await pumpStac(
        tester,
        screen(
          button({
            'actionType': 'networkRequest',
            'url': 'https://x.test/a',
            'method': 'post',
            'bodyFromState': ['k'],
          }),
        ),
        dio: dio,
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      final first = adapter.requests.single;
      expect(first.data, {'k': 'screen-v1'});
      await changeState(tester);
      await retry(tester, first);
      expect(adapter.requests.last.data, {'k': 'screen-v2'});
    });

    testWidgets('retry is refused for a body that cannot be sent twice', (
      tester,
    ) async {
      adapter.enqueue(_ok);
      await pumpStac(tester, const {'type': 'text', 'data': 't'}, dio: dio);
      final context = tester.element(find.text('t'));
      await tester.runAsync(
        () => StacNetworkService.request(
          context,
          StacNetworkRequest(
            url: 'https://x.test/up',
            method: Method.post,
            body: FormData.fromMap({'a': 'b'}),
          ),
        ),
      );
      final options = adapter.requests.single;
      expect(options.extra[stacRetryUnsafeExtraKey], true);
      expect(stacRetryUnsafe(options), isTrue);
      final error = await tester.runAsync(() async {
        try {
          await StacNetworkService.retryRequest(options);
        } on DioException catch (e) {
          return e;
        }
        return null;
      });
      expect(error, isA<DioException>());
      expect(adapter.requests, hasLength(1));
    });
  });

  group('retryRequest without a template (the app Dio)', () {
    testWidgets('repeats the original options with overrides applied', (
      tester,
    ) async {
      adapter
        ..enqueue(_unauthorized)
        ..enqueue(_ok);
      final token = CancelToken();
      await tester.runAsync(() async {
        try {
          await dio.post<dynamic>(
            'https://x.test/plain',
            data: {'a': 1, 'b': 2},
            queryParameters: {'q': '1'},
            options: Options(
              headers: {'Authorization': 'Bearer old', 'X-Keep': 'k'},
              contentType: 'application/json',
            ),
            cancelToken: token,
          );
        } on DioException catch (_) {}
      });
      final first = adapter.requests.single;
      expect(StacRequestTemplate.of(first), isNull);
      expect(first.extra, isEmpty);

      await retry(tester, first);
      var second = adapter.requests.last;
      expect(second.headers['Authorization'], 'Bearer old');
      expect(second.data, {'a': 1, 'b': 2});
      expect(second.uri, first.uri);
      expect(second.method, 'POST');
      expect(second.contentType, 'application/json');
      expect(second.cancelToken, same(token));
      expect(second.extra[stacRecoveryExemptExtraKey], true);

      adapter.enqueue(_ok);
      await retry(
        tester,
        first,
        overrides: {
          'headers': {'authorization': 'Bearer new'},
          'queryParameters': {'q': null, 'r': '2'},
          'body': {'a': null, 'c': 3},
        },
        removeHeaders: ['x-keep'],
      );
      second = adapter.requests.last;
      expect(second.headers['Authorization'], 'Bearer new');
      expect(second.headers.containsKey('X-Keep'), isFalse);
      expect(second.queryParameters, {'r': '2'});
      expect(second.data, {'b': 2, 'c': 3});
      expect(second.method, 'POST');
      expect(second.path, first.path);
      // The original options were not changed.
      expect(first.headers['Authorization'], 'Bearer old');
      expect(first.data, {'a': 1, 'b': 2});
    });
  });

  group('plain requests are unchanged', () {
    testWidgets('no template, no recovery marks', (tester) async {
      adapter.enqueue(_ok);
      await pumpStac(tester, const {'type': 'text', 'data': 't'}, dio: dio);
      final context = tester.element(find.text('t'));
      await tester.runAsync(
        () => StacNetworkService.request(
          context,
          StacNetworkRequest(url: 'https://x.test/p'),
        ),
      );
      expect(adapter.requests.single.extra, isEmpty);
    });

    testWidgets('runExempt marks the requests built inside it', (tester) async {
      adapter
        ..enqueue(_ok)
        ..enqueue(_ok);
      await pumpStac(tester, const {'type': 'text', 'data': 't'}, dio: dio);
      final context = tester.element(find.text('t'));
      await tester.runAsync(() async {
        await runExempt(
          () => StacNetworkService.request(
            context,
            StacNetworkRequest(url: 'https://x.test/in', method: Method.post),
          ),
        );
        await StacNetworkService.request(
          context,
          StacNetworkRequest(url: 'https://x.test/out'),
        );
      });
      expect(adapter.requests.first.extra[stacRecoveryExemptExtraKey], true);
      expect(adapter.requests.last.extra[stacRecoveryExemptExtraKey], isNull);
    });
  });

  group('fromNetwork views', () {
    Map<String, dynamic> netRequest() => {
      'actionType': 'networkRequest',
      'url': 'https://x.test/resource',
      'headers': {
        'X-Token': {r'$state': 'global.tok'},
      },
    };

    testWidgets('networkWidget: template, alive() false after dispose', (
      tester,
    ) async {
      adapter
        ..enqueue(_ok)
        ..enqueue(_ok);
      await pumpStac(
        tester,
        screen({'type': 'networkWidget', 'request': netRequest()}),
        dio: dio,
      );
      await tester.pumpAndSettle();
      final first = adapter.requests.single;
      expect(first.headers['X-Token'], 'old');
      final template = StacRequestTemplate.of(first)!;
      expect(template.isAlive, isTrue);
      expect(template.cancelToken, same(first.cancelToken));

      StacGlobalState.instance.store.write('tok', 'new');
      await retry(tester, first);
      expect(adapter.requests.last.headers['X-Token'], 'new');

      await tester.pumpWidget(const SizedBox());
      expect(template.alive(), isFalse);
      expect(template.isAlive, isFalse);
      expect(first.cancelToken!.isCancelled, isTrue);
    });

    testWidgets('navigate.request: repetition re-evaluates the headers', (
      tester,
    ) async {
      adapter
        ..enqueue(_ok)
        ..enqueue(_ok);
      await pumpStac(
        tester,
        screen(button({'actionType': 'navigate', 'request': netRequest()})),
        dio: dio,
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      final first = adapter.requests.single;
      expect(first.headers['X-Token'], 'old');
      expect(find.text('dest'), findsOneWidget);

      StacGlobalState.instance.store.write('tok', 'new');
      await retry(tester, first);
      expect(adapter.requests.last.headers['X-Token'], 'new');
      expect(StacRequestTemplate.of(first)!.isAlive, isTrue);
    });

    testWidgets('dialog request: alive() false once the dialog closes', (
      tester,
    ) async {
      adapter.enqueue(_ok);
      await pumpStac(
        tester,
        screen(button({'actionType': 'showDialog', 'request': netRequest()})),
        dio: dio,
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      final template = StacRequestTemplate.of(adapter.requests.single)!;
      expect(template.isAlive, isTrue);
      Navigator.of(tester.element(find.text('dest'))).pop();
      await tester.pumpAndSettle();
      expect(template.isAlive, isFalse);
    });
  });

  group('stacApplyRetryOverrides', () {
    test('merges, removes and replaces', () {
      final result = stacApplyRetryOverrides(
        {
          'url': 'u',
          'method': 'get',
          'headers': {'A': '1', 'b': '2'},
          'body': 'raw',
        },
        overrides: {
          'headers': {'B': null, 'C': '3'},
          'queryParameters': {'q': '1'},
          'body': {'x': 1},
        },
        removeHeaders: ['a'],
      );
      expect(result['headers'], {'C': '3'});
      expect(result['queryParameters'], {'q': '1'});
      expect(result['body'], {'x': 1});
      expect(result['url'], 'u');
      expect(result['method'], 'get');
    });

    test('a null section removes it; no overrides is a copy', () {
      final json = {
        'headers': {'A': '1'},
        'body': {'a': 1},
      };
      expect(stacApplyRetryOverrides(json), json);
      final result = stacApplyRetryOverrides(json, overrides: {'body': null});
      expect(result.containsKey('body'), isFalse);
      expect(json.containsKey('body'), isTrue);
    });
  });
}
