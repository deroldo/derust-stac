import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stac/stac.dart';

import 'harness.dart';

Map<String, dynamic> _state(String key) => {r'$state': key};
Map<String, dynamic> _expr(String e) => {r'$expr': e};

Map<String, dynamic> _button(String label, Map<String, dynamic> action) => {
  'type': 'textButton',
  'onPressed': action,
  'child': {'type': 'text', 'data': label},
};

Map<String, dynamic> _pop({Object? result, bool withResult = false}) => {
  'actionType': 'navigate',
  'navigationStyle': 'pop',
  if (withResult) 'result': result,
};

/// Screen B: shows `params` and has a few ways of leaving.
Map<String, dynamic> _screenB() => {
  'type': 'column',
  'state': {'n': 0},
  'children': [
    {'type': 'text', 'data': _expr("'B:' + params.name + ':' + params.price")},
    {'type': 'text', 'data': _expr("'n=' + n")},
    _button('inc', {'actionType': 'incrementState', 'key': 'n'}),
    _button(
      'choose',
      _pop(
        withResult: true,
        result: {
          'name': _expr('params.name'),
          'price': _expr('params.price * 2'),
        },
      ),
    ),
    _button('popNull', _pop(withResult: true, result: null)),
    _button('popBare', _pop()),
    _button('setGlobal', {
      'actionType': 'setState',
      'values': {'global.x': 5},
    }),
  ],
};

Map<String, dynamic> _openB({bool handlers = true}) => {
  'actionType': 'navigate',
  'navigationStyle': 'push',
  'widgetJson': _screenB(),
  'params': {'name': _state('selected'), 'price': _state('price')},
  if (handlers) ...{
    'onResult': {
      'actionType': 'multiAction',
      'sync': true,
      'actions': [
        {
          'actionType': 'appendState',
          'key': 'picked',
          'value': _state('result'),
        },
        {
          'actionType': 'setState',
          'values': {'status': 'result'},
        },
      ],
    },
    'onCancel': {
      'actionType': 'setState',
      'values': {'status': 'cancel'},
    },
  },
};

Map<String, dynamic> _screenA({Map<String, dynamic>? open}) => {
  'type': 'column',
  'globalState': {'x': 0},
  'state': {
    'selected': 'Pen',
    'price': 10,
    'picked': <Object?>[],
    'status': 'none',
  },
  'children': [
    {'type': 'text', 'data': _expr("'status=' + status")},
    {'type': 'text', 'data': _expr("'count=' + length(picked)")},
    {'type': 'text', 'data': _expr("'x=' + global.x")},
    {'type': 'text', 'data': _expr("'sel=' + selected")},
    _button('open', open ?? _openB()),
  ],
};

Future<StacStateStore> _pumpA(
  WidgetTester tester,
  Map<String, dynamic> a,
) async {
  await initStacForTest();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) => StacService.fromJson(a, context)!),
      ),
    ),
  );
  await tester.pump();
  return StacStateScope.storeOf(tester.element(find.text('status=none')))!;
}

Future<void> _tap(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => StacGlobalState.instance.clear());

  test('navigate model tells a declared result from an absent one', () {
    final bare = StacNavigateAction.fromJson(_pop());
    expect(bare.hasResult, isFalse);
    expect(bare.toJson().containsKey('result'), isFalse);

    final explicitNull = StacNavigateAction.fromJson(_pop(withResult: true));
    expect(explicitNull.hasResult, isTrue);
    expect(explicitNull.result, isNull);
    expect(explicitNull.toJson().containsKey('result'), isTrue);

    final literal = StacNavigateAction.fromJson(
      _pop(withResult: true, result: [1, 2]),
    );
    expect(literal.result, [1, 2]);
  });

  testWidgets('params reach B without HTTP and are a snapshot', (tester) async {
    final store = await _pumpA(tester, _screenA());
    await _tap(tester, 'open');
    expect(find.text('B:Pen:10'), findsOneWidget);

    store.write('selected', 'Book');
    await tester.pumpAndSettle();
    expect(find.text('B:Pen:10'), findsOneWidget);
    expect(find.text('B:Book:10'), findsNothing);
  });

  testWidgets('pop with result runs onResult with `result` bindings', (
    tester,
  ) async {
    final store = await _pumpA(tester, _screenA());
    await _tap(tester, 'open');
    await _tap(tester, 'choose');

    expect(find.text('B:Pen:10'), findsNothing);
    expect(find.text('status=result'), findsOneWidget);
    expect(find.text('count=1'), findsOneWidget);
    expect(store.read('picked'), [
      {'name': 'Pen', 'price': 20},
    ]);
  });

  testWidgets('system back runs onCancel, not onResult', (tester) async {
    final store = await _pumpA(tester, _screenA());
    await _tap(tester, 'open');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('status=cancel'), findsOneWidget);
    expect(store.read('picked'), isEmpty);
  });

  testWidgets('pop without result is a cancellation', (tester) async {
    await _pumpA(tester, _screenA());
    await _tap(tester, 'open');
    await _tap(tester, 'popBare');
    expect(find.text('status=cancel'), findsOneWidget);
    expect(find.text('count=0'), findsOneWidget);
  });

  testWidgets('pop with explicit result: null runs onResult', (tester) async {
    final store = await _pumpA(tester, _screenA());
    await _tap(tester, 'open');
    await _tap(tester, 'popNull');

    expect(find.text('status=result'), findsOneWidget);
    expect(store.read('picked'), [null]);
  });

  testWidgets('repeated flow leaves no leftovers (fresh state in B)', (
    tester,
  ) async {
    final store = await _pumpA(tester, _screenA());
    for (var i = 1; i <= 3; i++) {
      await _tap(tester, 'open');
      expect(find.text('n=0'), findsOneWidget);
      await _tap(tester, 'inc');
      expect(find.text('n=1'), findsOneWidget);
      await _tap(tester, 'choose');
      expect(find.text('count=$i'), findsOneWidget);
    }
    expect((store.read('picked') as List).length, 3);
    expect(find.text('n=1'), findsNothing);
  });

  testWidgets('origin discarded before the pop does not throw', (tester) async {
    await _pumpA(tester, _screenA());
    await _tap(tester, 'open');

    // Replace A (the route below B) so its element is gone.
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    final aRoute = ModalRoute.of(
      tester.element(find.text('status=none', skipOffstage: false)),
    )!;
    navigator.replace(
      oldRoute: aRoute,
      newRoute: MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('C')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('status=none', skipOffstage: false), findsNothing);

    await _tap(tester, 'choose');
    expect(tester.takeException(), isNull);
    expect(find.text('C'), findsOneWidget);
  });

  testWidgets('global state changed in B updates A underneath', (tester) async {
    await _pumpA(tester, _screenA());
    await _tap(tester, 'open');
    expect(find.text('x=0', skipOffstage: false), findsOneWidget);
    await _tap(tester, 'setGlobal');
    expect(find.text('x=5', skipOffstage: false), findsOneWidget);
  });

  testWidgets('legacy caller receives the unwrapped result', (tester) async {
    await _pumpA(tester, _screenA());
    final context = tester.element(find.text('open'));
    final future = Future.value(
      StacService.onCallFromJson(_openB(handlers: false), context),
    );
    Object? received = 'pending';
    unawaited(future.then((v) => received = v));
    await tester.pumpAndSettle();
    await _tap(tester, 'choose');
    await tester.pumpAndSettle();
    expect(received, {'name': 'Pen', 'price': 20});
  });

  testWidgets('legacy caller receives null on system back', (tester) async {
    await _pumpA(tester, _screenA());
    final context = tester.element(find.text('open'));
    Object? received = 'pending';
    unawaited(
      Future.value(
        StacService.onCallFromJson(_openB(handlers: false), context),
      ).then((v) => received = v),
    );
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(received, isNull);
  });

  group('dialog and modal bottom sheet', () {
    Map<String, dynamic> content() => {
      'type': 'column',
      'mainAxisSize': 'min',
      'children': [
        {
          'type': 'text',
          'data': 'shown-in-overlay',
          'visible': _expr('flag == true'),
        },
        {'type': 'text', 'data': _expr("'sel:' + selected")},
        _button('hide', {
          'actionType': 'setState',
          'values': {'flag': false},
        }),
        _button('closeWith', _pop(withResult: true, result: {'ok': true})),
      ],
    };

    Map<String, dynamic> screen(Map<String, dynamic> open) => {
      'type': 'column',
      'state': {'flag': true, 'selected': 'Pen'},
      'children': [
        {'type': 'text', 'data': _expr("'flag=' + flag")},
        _button('open', open),
      ],
    };

    testWidgets('showDialog content reads and writes the screen state', (
      tester,
    ) async {
      await initStacForTest();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => StacService.fromJson(
                screen({'actionType': 'showDialog', 'widget': content()}),
                context,
              )!,
            ),
          ),
        ),
      );
      await tester.pump();
      await _tap(tester, 'open');
      expect(find.text('shown-in-overlay'), findsOneWidget);
      expect(find.text('sel:Pen'), findsOneWidget);

      await _tap(tester, 'hide');
      expect(find.text('shown-in-overlay'), findsNothing);
      expect(find.text('flag=false', skipOffstage: false), findsOneWidget);

      await _tap(tester, 'closeWith');
      expect(find.text('sel:Pen'), findsNothing);
    });

    testWidgets('showModalBottomSheet content reads the screen state', (
      tester,
    ) async {
      await initStacForTest();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => StacService.fromJson(
                screen({
                  'actionType': 'showModalBottomSheet',
                  'widget': content(),
                }),
                context,
              )!,
            ),
          ),
        ),
      );
      await tester.pump();
      await _tap(tester, 'open');
      expect(find.text('shown-in-overlay'), findsOneWidget);

      await _tap(tester, 'hide');
      expect(find.text('shown-in-overlay'), findsNothing);
    });
  });
}
