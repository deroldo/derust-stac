import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stac/src/framework/stac.dart' as framework;
import 'package:stac/stac.dart';

import 'harness.dart';

Map<String, dynamic> _state(String key) => {r'$state': key};
Map<String, dynamic> _expr(String e) => {r'$expr': e};

Map<String, dynamic> _button(String label, Map<String, dynamic> action) => {
  'type': 'textButton',
  'onPressed': action,
  'child': {'type': 'text', 'data': label},
};

Map<String, dynamic> _screen({
  Map<String, dynamic>? state,
  Map<String, dynamic>? globalState,
  Object? onInit,
  List<Map<String, dynamic>> children = const [],
}) => {
  'type': 'column',
  'state': ?state,
  'globalState': ?globalState,
  'onInit': ?onInit,
  'children': children,
};

Map<String, dynamic> _inc(String key, {num? max}) => {
  'actionType': 'incrementState',
  'key': key,
  'max': ?max,
};

void main() {
  setUp(() {
    StacGlobalState.instance.clear();
  });

  group('screen blocks', () {
    testWidgets('state + text + conditional + button', (tester) async {
      await pumpStac(
        tester,
        _screen(
          state: {'total': 0},
          children: [
            {'type': 'text', 'data': _expr("'Total: ' + total")},
            {
              'type': 'conditional',
              'condition': _expr('total == 2'),
              'ifTrue': {'type': 'text', 'data': 'two!'},
              'ifFalse': {'type': 'text', 'data': 'not yet'},
            },
            {
              'type': 'text',
              'data': 'shown at 1',
              'visible': _expr('total == 1'),
            },
            _button('inc', _inc('total')),
          ],
        ),
      );
      expect(find.text('Total: 0'), findsOneWidget);
      expect(find.text('not yet'), findsOneWidget);
      expect(find.text('shown at 1'), findsNothing);

      await tester.tap(find.text('inc'));
      await tester.pump();
      expect(find.text('Total: 1'), findsOneWidget);
      expect(find.text('shown at 1'), findsOneWidget);

      await tester.tap(find.text('inc'));
      await tester.pump();
      expect(find.text('two!'), findsOneWidget);
      expect(find.text('not yet'), findsNothing);
    });

    testWidgets('conditional keeps legacy string conditions', (tester) async {
      await pumpStac(tester, {
        'type': 'conditional',
        'condition': '1 == 1',
        'ifTrue': {'type': 'text', 'data': 'legacy ok'},
      });
      expect(find.text('legacy ok'), findsOneWidget);
    });

    testWidgets('conditional with a literal bool', (tester) async {
      await pumpStac(tester, {
        'type': 'conditional',
        'condition': false,
        'ifTrue': {'type': 'text', 'data': 'yes'},
        'ifFalse': {'type': 'text', 'data': 'no'},
      });
      expect(find.text('no'), findsOneWidget);
    });

    testWidgets('conditional with invalid expression is false (D6)', (
      tester,
    ) async {
      await pumpStac(
        tester,
        _screen(
          state: {'a': 1},
          children: [
            {
              'type': 'conditional',
              'condition': _expr('a +'),
              'ifTrue': {'type': 'text', 'data': 'yes'},
              'ifFalse': {'type': 'text', 'data': 'no'},
            },
          ],
        ),
      );
      expect(find.text('no'), findsOneWidget);
    });

    testWidgets('state initial values can read params and global', (
      tester,
    ) async {
      await pumpStac(tester, {
        'type': 'column',
        'globalState': {'user': 'ana'},
        'state': {'greeting': _expr("'hi ' + global.user"), 'n': 3},
        'children': [
          {'type': 'text', 'data': _state('greeting')},
          {'type': 'text', 'data': _expr('n * 2')},
        ],
      });
      expect(find.text('hi ana'), findsOneWidget);
      expect(find.text('6'), findsOneWidget);
    });

    testWidgets('reserved screen key is rejected, others kept', (tester) async {
      await pumpStac(
        tester,
        _screen(
          state: {'global': 5, 'ok': 1},
          children: [
            {'type': 'text', 'data': _expr('ok')},
          ],
        ),
      );
      expect(find.text('1'), findsOneWidget);
      expect(StacGlobalState.instance.store.has('global'), isFalse);
    });
  });

  group('globalState', () {
    testWidgets('is idempotent across screens', (tester) async {
      final first = _screen(
        globalState: {'count': 1},
        children: [_button('bump', _inc('global.count'))],
      );
      await pumpStac(tester, first);
      await tester.tap(find.text('bump'));
      await tester.pump();
      expect(StacGlobalState.instance.store.read('count'), 2);

      // A second screen declares the same key with another initial value.
      await tester.pumpWidget(const SizedBox());
      await pumpStac(
        tester,
        _screen(
          globalState: {'count': 100},
          children: [
            {'type': 'text', 'data': _expr('global.count')},
          ],
        ),
      );
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('accepts the declaration object form (D12)', (tester) async {
      await pumpStac(
        tester,
        _screen(
          globalState: {
            'a': {'initial': 7, 'persist': false},
            'b': {'other': 1}, // not a declaration: plain map value
          },
        ),
      );
      final store = StacGlobalState.instance.store;
      expect(store.read('a'), 7);
      expect(store.read('b'), {'other': 1});
    });
  });

  group('onInit', () {
    testWidgets('runs once, in sequence, after first frame', (tester) async {
      await pumpStac(
        tester,
        _screen(
          state: {'n': 0},
          onInit: [_inc('n'), _inc('n')],
          children: [
            {'type': 'text', 'data': _expr("'n=' + n")},
          ],
        ),
      );
      await tester.pump();
      expect(find.text('n=2'), findsOneWidget);

      // Re-render of the same content does not run it again.
      await tester.pump();
      expect(find.text('n=2'), findsOneWidget);
    });

    testWidgets('accepts a single action', (tester) async {
      await pumpStac(
        tester,
        _screen(
          state: {'n': 0},
          onInit: _inc('n'),
          children: [
            {'type': 'text', 'data': _expr("'n=' + n")},
          ],
        ),
      );
      await tester.pump();
      expect(find.text('n=1'), findsOneWidget);
    });
  });

  group('parent rebuild vs new server response (Review Focus 5)', () {
    Map<String, dynamic> json() => _screen(
      state: {'total': 0},
      onInit: _inc('total'),
      children: [
        {'type': 'text', 'data': _expr("'total=' + total")},
        _button('inc', _inc('total')),
      ],
    );

    testWidgets('theme switch keeps state and does not rerun onInit', (
      tester,
    ) async {
      await initStacForTest();
      ThemeData theme = ThemeData.light();
      late StateSetter setOuter;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            setOuter = setState;
            return MaterialApp(
              theme: theme,
              home: Scaffold(
                body: Builder(
                  builder: (context) => StacService.fromJson(json(), context)!,
                ),
              ),
            );
          },
        ),
      );
      await tester.pump();
      expect(find.text('total=1'), findsOneWidget);
      await tester.tap(find.text('inc'));
      await tester.pump();
      expect(find.text('total=2'), findsOneWidget);

      setOuter(() => theme = ThemeData.dark());
      await tester.pump();
      await tester.pump();
      expect(find.text('total=2'), findsOneWidget);
    });

    testWidgets('new response resets state and reruns onInit', (tester) async {
      await initStacForTest();
      var response = Object();
      late StateSetter setOuter;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            setOuter = setState;
            return MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (context) => KeyedSubtree(
                    key: ObjectKey(response),
                    child: StacService.fromJson(json(), context)!,
                  ),
                ),
              ),
            );
          },
        ),
      );
      await tester.pump();
      await tester.tap(find.text('inc'));
      await tester.tap(find.text('inc'));
      await tester.pump();
      expect(find.text('total=3'), findsOneWidget);

      setOuter(() => response = Object());
      await tester.pump();
      await tester.pump();
      expect(find.text('total=1'), findsOneWidget);
    });

    testWidgets('changed state/onInit content resets the scope', (
      tester,
    ) async {
      await initStacForTest();
      var initial = 0;
      late StateSetter setOuter;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            setOuter = setState;
            return MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (context) => StacService.fromJson(
                    _screen(
                      state: {'total': initial},
                      children: [
                        {'type': 'text', 'data': _expr("'total=' + total")},
                        _button('inc', _inc('total')),
                      ],
                    ),
                    context,
                  )!,
                ),
              ),
            );
          },
        ),
      );
      await tester.pump();
      await tester.tap(find.text('inc'));
      await tester.pump();
      expect(find.text('total=1'), findsOneWidget);
      setOuter(() => initial = 10);
      await tester.pump();
      expect(find.text('total=10'), findsOneWidget);
    });
  });

  group('Stac(routeName) fetch', () {
    testWidgets('fetches once across rebuilds and keys state by response', (
      tester,
    ) async {
      await StacService.initialize(
        options: const StacOptions(name: 'n', projectId: 'p'),
        override: true,
        statePersistence: const NullStatePersistence(),
        secureStatePersistence: const NullStatePersistence(),
      );
      var calls = 0;
      var total = 0;
      framework.debugStacScreenFetcher = (routeName) async {
        calls++;
        return Response<dynamic>(
          requestOptions: RequestOptions(path: routeName),
          data: {
            'stacJson': jsonEncode(
              _screen(
                state: {'total': 0},
                children: [
                  {'type': 'text', 'data': _expr("'total=' + total")},
                  _button('inc', _inc('total')),
                ],
              ),
            ),
          },
        );
      };
      addTearDown(() => framework.debugStacScreenFetcher = null);

      var route = '/a';
      late StateSetter setOuter;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            setOuter = setState;
            return MaterialApp(
              theme: total.isEven ? ThemeData.light() : ThemeData.dark(),
              home: Scaffold(body: Stac(routeName: route)),
            );
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(calls, 1);
      await tester.tap(find.text('inc'));
      await tester.pump();
      expect(find.text('total=1'), findsOneWidget);

      // Parent rebuild (theme switch): no refetch, state kept.
      setOuter(() => total++);
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.text('total=1'), findsOneWidget);

      // Another route: refetch, fresh response, fresh state.
      setOuter(() => route = '/b');
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.text('total=0'), findsOneWidget);
    });
  });
}
