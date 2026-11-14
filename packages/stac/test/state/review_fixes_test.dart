import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stac/stac.dart';

import 'harness.dart';

/// Regression tests for the code review findings (appBar casts, hidden
/// slivers, request lifecycle independent of the trigger widget, navigation
/// inside callbacks, scope keys, log redaction).

Map<String, dynamic> _state(String key) => StacBinding.state(key);
Map<String, dynamic> _expr(String e) => StacBinding.expr(e);

class _Adapter implements HttpClientAdapter {
  final List<FakeResponse> queue = [];
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
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

final _adapter = _Adapter();
final _dio = Dio()..httpClientAdapter = _adapter;

late StacStateStore _store;

Future<void> _pumpApp(
  WidgetTester t,
  Map<String, dynamic> json, {
  Map<String, Object?> state = const {},
}) async {
  await initStacForTest(dio: _dio);
  await t.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: StacStateScope(
          initialState: state,
          child: Builder(
            builder: (c) {
              _store = StacStateScope.storeOf(c)!;
              return StacService.fromJson(json, c)!;
            },
          ),
        ),
      ),
    ),
  );
  await t.pump();
}

Map<String, dynamic> _set(Map<String, Object?> values) => {
  'actionType': 'setState',
  'values': values,
};

Map<String, dynamic> _append(String key, Object? value) => {
  'actionType': 'appendState',
  'key': key,
  'value': value,
};

Map<String, dynamic> _button(String label, Map<String, dynamic> action) => {
  'type': 'textButton',
  'onPressed': action,
  'child': {'type': 'text', 'data': label},
};

void main() {
  setUp(() {
    StacGlobalState.instance.clear();
    _adapter
      ..queue.clear()
      ..requests.clear();
  });

  group('1. appBar with bindings/visible keeps the Scaffold working', () {
    Map<String, dynamic> screen(Map<String, dynamic> appBar) => {
      'type': 'scaffold',
      'state': {'c': false, 's': false, 'show': true},
      'appBar': appBar,
      'body': {
        'type': 'column',
        'children': [
          {'type': 'text', 'data': 'the body'},
          _button('toggle', {'actionType': 'toggleState', 'key': 'c'}),
          _button('scroll', {'actionType': 'toggleState', 'key': 's'}),
          _button('hide', {'actionType': 'toggleState', 'key': 'show'}),
        ],
      },
    };

    bool? centerTitle(WidgetTester t) =>
        t.widget<AppBar>(find.byType(AppBar)).centerTitle;

    testWidgets('appBar with a bound property renders the body and reacts', (
      t,
    ) async {
      await _pumpApp(t, {
        'type': 'scaffold',
        'appBar': {
          'type': 'appBar',
          'title': {'type': 'text', 'data': 'bar'},
          'centerTitle': _state('c'),
        },
        'state': {'c': false},
        'body': {
          'type': 'column',
          'children': [
            {'type': 'text', 'data': 'the body'},
            _button('toggle', {'actionType': 'toggleState', 'key': 'c'}),
          ],
        },
      });
      expect(tester(t), isNull);
      expect(find.text('the body'), findsOneWidget);
      expect(find.text('bar'), findsOneWidget);
      expect(centerTitle(t), false);
      await t.tap(find.text('toggle'));
      await t.pump();
      expect(centerTitle(t), true);
    });

    testWidgets('appBar toolbarHeight bound gives the bar that height', (
      t,
    ) async {
      await _pumpApp(t, {
        'type': 'scaffold',
        'state': {'h': 100},
        'appBar': {
          'type': 'appBar',
          'toolbarHeight': _state('h'),
          'title': {'type': 'text', 'data': 'bar'},
        },
        'body': {'type': 'text', 'data': 'the body'},
      });
      expect(tester(t), isNull);
      expect(find.text('the body'), findsOneWidget);
      expect(t.getSize(find.byType(AppBar)).height, greaterThanOrEqualTo(100));
    });

    testWidgets('appBar bottom (tabBar) with a binding', (t) async {
      await _pumpApp(t, {
        'type': 'defaultTabController',
        'length': 2,
        'child': screen({
          'type': 'appBar',
          'title': {'type': 'text', 'data': 'bar'},
          'bottom': {
            'type': 'tabBar',
            'isScrollable': _state('s'),
            'tabs': [
              {'type': 'tab', 'text': 'T1'},
              {'type': 'tab', 'text': 'T2'},
            ],
          },
        }),
      });
      expect(tester(t), isNull);
      expect(find.text('the body'), findsOneWidget);
      expect(find.text('T1'), findsOneWidget);
      expect(t.widget<TabBar>(find.byType(TabBar)).isScrollable, false);
      await t.tap(find.text('scroll'));
      await t.pump();
      expect(t.widget<TabBar>(find.byType(TabBar)).isScrollable, true);
    });

    testWidgets('appBar visible bound hides and shows the bar', (t) async {
      await _pumpApp(t, {
        'type': 'scaffold',
        'state': {'show': true},
        'appBar': {
          'type': 'appBar',
          'visible': _state('show'),
          'title': {'type': 'text', 'data': 'bar'},
        },
        'body': {
          'type': 'column',
          'children': [
            {'type': 'text', 'data': 'the body'},
            _button('hide', {'actionType': 'toggleState', 'key': 'show'}),
          ],
        },
      });
      expect(tester(t), isNull);
      expect(find.text('bar'), findsOneWidget);
      await t.tap(find.text('hide'));
      await t.pump();
      expect(tester(t), isNull);
      expect(find.text('bar'), findsNothing);
      expect(find.text('the body'), findsOneWidget);
    });

    testWidgets('appBar visible:false (static) does not break the Scaffold', (
      t,
    ) async {
      await _pumpApp(t, {
        'type': 'scaffold',
        'appBar': {'type': 'appBar', 'visible': false},
        'body': {'type': 'text', 'data': 'the body'},
      });
      expect(tester(t), isNull);
      expect(find.text('the body'), findsOneWidget);
    });

    testWidgets('sliverAppBar bottom with a binding', (t) async {
      await _pumpApp(t, {
        'type': 'defaultTabController',
        'length': 1,
        'state': {'s': false},
        'child': {
          'type': 'customScrollView',
          'slivers': [
            {
              'type': 'sliverAppBar',
              'title': {'type': 'text', 'data': 'bar'},
              'bottom': {
                'type': 'tabBar',
                'isScrollable': _state('s'),
                'tabs': [
                  {'type': 'tab', 'text': 'T1'},
                ],
              },
            },
          ],
        },
      });
      expect(tester(t), isNull);
      expect(find.text('T1'), findsOneWidget);
    });
  });

  group('1b. switch thumbIcon', () {
    testWidgets('a bound thumbIcon no longer breaks the switch', (t) async {
      await _pumpApp(
        t,
        {
          'type': 'switch',
          'value': false,
          'thumbIcon': {'type': 'icon', 'icon': 'check', 'size': _state('sz')},
        },
        state: {'sz': 12.0},
      );
      expect(tester(t), isNull);
      expect(find.byType(Switch), findsOneWidget);
    });
  });

  group('2. hidden widgets in sliver/appBar positions', () {
    testWidgets('sliverList visible:false followed by another sliver', (
      t,
    ) async {
      await _pumpApp(t, {
        'type': 'customScrollView',
        'slivers': [
          {
            'type': 'sliverList',
            'visible': false,
            'children': [
              {'type': 'text', 'data': 'hidden'},
            ],
          },
          {
            'type': 'sliverToBoxAdapter',
            'child': {'type': 'text', 'data': 'next'},
          },
        ],
      });
      expect(tester(t), isNull);
      expect(find.text('hidden'), findsNothing);
      expect(find.text('next'), findsOneWidget);
    });

    testWidgets('bound visible on a sliver toggles without breaking', (
      t,
    ) async {
      await _pumpApp(
        t,
        {
          'type': 'column',
          'children': [
            _button('flip', {'actionType': 'toggleState', 'key': 'show'}),
            {
              'type': 'sizedBox',
              'height': 200,
              'child': {
                'type': 'customScrollView',
                'slivers': [
                  {
                    'type': 'sliverToBoxAdapter',
                    'visible': _state('show'),
                    'child': {'type': 'text', 'data': 'first'},
                  },
                  {
                    'type': 'sliverToBoxAdapter',
                    'child': {'type': 'text', 'data': 'next'},
                  },
                ],
              },
            },
          ],
        },
        state: {'show': false},
      );
      expect(tester(t), isNull);
      expect(find.text('first'), findsNothing);
      expect(find.text('next'), findsOneWidget);
      await t.tap(find.text('flip'));
      await t.pump();
      expect(tester(t), isNull);
      expect(find.text('first'), findsOneWidget);
    });

    testWidgets('invalid visible expression on a sliver is hidden, no crash', (
      t,
    ) async {
      await _pumpApp(t, {
        'type': 'customScrollView',
        'slivers': [
          {
            'type': 'sliverList',
            'visible': _expr('1 +'),
            'children': [
              {'type': 'text', 'data': 'hidden'},
            ],
          },
          {
            'type': 'sliverToBoxAdapter',
            'child': {'type': 'text', 'data': 'next'},
          },
        ],
      });
      expect(tester(t), isNull);
      expect(find.text('hidden'), findsNothing);
      expect(find.text('next'), findsOneWidget);
    });
  });

  group('3. request lifecycle follows the screen, not the trigger widget', () {
    testWidgets('optimistic delete keeps onError/onFinally after removal', (
      t,
    ) async {
      await _pumpApp(
        t,
        {
          'type': 'column',
          'children': [
            {
              'type': 'sizedBox',
              'height': 300,
              'child': {
                'type': 'listView',
                'items': _state('todos'),
                'itemTemplate': _button('del-', {
                  'actionType': 'networkRequest',
                  'url': '/api',
                  'method': 'delete',
                  'onStart': {
                    'actionType': 'removeFromState',
                    'key': 'todos',
                    'index': _state('index'),
                  },
                  'onError': _append('log', _expr("'rollback:' + item.name")),
                  'onFinally': _append('log', 'finally'),
                }),
              },
            },
          ],
        },
        state: {
          'todos': [
            {'name': 'a'},
            {'name': 'b'},
          ],
          'log': <Object?>[],
        },
      );
      _adapter.queue.add(
        const FakeResponse(
          {'e': 1},
          statusCode: 500,
          delay: Duration(milliseconds: 50),
        ),
      );
      expect(find.text('del-'), findsNWidgets(2));
      await t.tap(find.text('del-').first);
      await t.pump();
      // The first item was removed optimistically; its button is gone.
      expect(find.text('del-'), findsOneWidget);
      expect((_store.read('todos') as List).length, 1);
      await t.pump(const Duration(milliseconds: 200));
      await t.pump();
      expect(_store.read('log'), ['rollback:a', 'finally']);
    });

    testWidgets('a dialog button that closes the dialog keeps onSuccess', (
      t,
    ) async {
      await _pumpApp(
        t,
        {
          'type': 'column',
          'children': [
            _button('open', {
              'actionType': 'showDialog',
              'widget': {
                'type': 'alertDialog',
                'actions': [
                  _button('send', {
                    'actionType': 'multiAction',
                    'actions': [
                      {
                        'actionType': 'networkRequest',
                        'url': '/api',
                        'method': 'get',
                        'onSuccess': _set({'x': _state('response.body.v')}),
                        'onFinally': _set({'done': true}),
                      },
                      {'actionType': 'navigate', 'navigationStyle': 'pop'},
                    ],
                  }),
                ],
              },
            }),
          ],
        },
        state: {'x': 0, 'done': false},
      );
      _adapter.queue.add(
        const FakeResponse({'v': 7}, delay: Duration(milliseconds: 600)),
      );
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      await t.tap(find.text('send'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400)); // dialog closes
      expect(find.text('send'), findsNothing);
      await t.pump(const Duration(milliseconds: 400));
      await t.pump();
      expect(_store.read('x'), 7);
      expect(_store.read('done'), true);
    });

    testWidgets('a closed screen still discards a late response', (t) async {
      await initStacForTest(dio: _dio);
      final show = ValueNotifier(true);
      StacGlobalState.instance.declareAll({'g': 0});
      await t.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<bool>(
            valueListenable: show,
            builder: (_, visible, _) => visible
                ? StacStateScope(
                    initialState: const {'x': 0},
                    child: Builder(
                      builder: (c) {
                        return TextButton(
                          onPressed: () => StacService.onCallFromJson({
                            'actionType': 'networkRequest',
                            'url': '/api',
                            'method': 'get',
                            'onSuccess': _set({'global.g': 1}),
                          }, c),
                          child: const Text('go'),
                        );
                      },
                    ),
                  )
                : const SizedBox(),
          ),
        ),
      );
      _adapter.queue.add(
        const FakeResponse({'v': 1}, delay: Duration(milliseconds: 100)),
      );
      await t.tap(find.text('go'));
      await t.pump();
      show.value = false;
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(StacGlobalState.instance.store.read('g'), 0);
    });
  });

  group('4. navigation inside request callbacks does not block onFinally', () {
    Map<String, dynamic> request(String style) => {
      'actionType': 'networkRequest',
      'url': '/api',
      'method': 'get',
      'onStart': _set({'loading': true}),
      'onSuccess': {
        'actionType': 'navigate',
        'navigationStyle': style,
        'widgetJson': {
          'type': 'scaffold',
          'body': {'type': 'text', 'data': 'next screen'},
        },
      },
      'onFinally': _set({'loading': false}),
    };

    testWidgets('push in onSuccess: onFinally runs right after', (t) async {
      await _pumpApp(
        t,
        _button('go', request('push')),
        state: {'loading': false},
      );
      _adapter.queue.add(
        const FakeResponse({'v': 1}, delay: Duration(milliseconds: 50)),
      );
      await t.tap(find.text('go'));
      await t.pump();
      expect(_store.read('loading'), true);
      await t.pump(const Duration(milliseconds: 100));
      await t.pump();
      expect(_store.read('loading'), false);
      await t.pumpAndSettle();
      expect(find.text('next screen'), findsOneWidget);
    });

    testWidgets('pushReplacement in onSuccess: onFinally still runs', (
      t,
    ) async {
      await _pumpApp(
        t,
        _button('go', request('pushReplacement')),
        state: {'loading': false},
      );
      _adapter.queue.add(
        const FakeResponse({'v': 1}, delay: Duration(milliseconds: 50)),
      );
      await t.tap(find.text('go'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      await t.pump();
      expect(_store.read('loading'), false);
    });
  });

  group('8. screen scope keys', () {
    testWidgets('the key is the full block content, not a hash', (t) async {
      await initStacForTest();
      final blocks = {
        'state': {'a': 1},
      };
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) => StacService.fromJson({
              'type': 'text',
              'data': 'x',
              ...blocks,
            }, c)!,
          ),
        ),
      );
      final scope = t.widget<StacStateScope>(find.byType(StacStateScope));
      final key = scope.key! as ValueKey;
      expect(key.value, jsonEncode(blocks));
    });
  });

  group('10. url in warnings is redacted', () {
    testWidgets('no-result warning does not print a secure value', (t) async {
      await initStacForTest(dio: _dio);
      StacGlobalState.instance.declareAll({
        'tok': {'initial': 'S3CR3T', 'secure': true},
      });
      _adapter.queue.add(const FakeResponse({'v': 1}, statusCode: 201));
      final lines = <String>[];
      await runZoned(
        () async {
          await t.pumpWidget(
            MaterialApp(
              home: Builder(
                builder: (c) => TextButton(
                  onPressed: () => StacService.onCallFromJson({
                    'actionType': 'networkRequest',
                    'url': '/api/S3CR3T',
                    'method': 'get',
                    'results': [
                      {
                        'statusCode': 200,
                        'action': {'actionType': 'none'},
                      },
                    ],
                  }, c),
                  child: const Text('go'),
                ),
              ),
            ),
          );
          await t.tap(find.text('go'));
          await t.pump();
          await t.pump(const Duration(milliseconds: 100));
          await t.pump();
        },
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => lines.add(line),
        ),
      );
      final text = lines.join('\n');
      expect(text, contains('No networkRequest result'));
      expect(text, isNot(contains('S3CR3T')));
    });

    testWidgets('body + bodyFromState warning does not print the secret', (
      t,
    ) async {
      await initStacForTest(dio: _dio);
      StacGlobalState.instance.declareAll({
        'tok': {'initial': 'S3CR3T', 'secure': true},
      });
      _adapter.queue.add(const FakeResponse({'v': 1}));
      final lines = <String>[];
      await runZoned(
        () async {
          await t.pumpWidget(
            MaterialApp(
              home: StacStateScope(
                initialState: const {'a': 1},
                child: Builder(
                  builder: (c) => TextButton(
                    onPressed: () => StacService.onCallFromJson({
                      'actionType': 'networkRequest',
                      'url': '/api/S3CR3T',
                      'method': 'post',
                      'body': {'k': 1},
                      'bodyFromState': ['a'],
                    }, c),
                    child: const Text('go'),
                  ),
                ),
              ),
            ),
          );
          await t.tap(find.text('go'));
          await t.pump();
          await t.pump(const Duration(milliseconds: 100));
        },
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => lines.add(line),
        ),
      );
      final text = lines.join('\n');
      expect(text, contains('explicit body wins'));
      expect(text, isNot(contains('S3CR3T')));
    });
  });
}

/// Pending framework exception (if any) of the current test.
Object? tester(WidgetTester t) => t.takeException();
