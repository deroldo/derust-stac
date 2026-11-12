import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stac/stac.dart';

import 'harness.dart';

Map<String, dynamic> _state(String key) => {r'$state': key};
Map<String, dynamic> _expr(String e) => {r'$expr': e};

/// Widget stub that counts how many times its parser ran.
class _ProbeParser extends StacParser<Map<String, dynamic>> {
  const _ProbeParser();

  static int parses = 0;
  static Map<String, dynamic>? lastModel;

  @override
  String get type => 'probe';

  @override
  Map<String, dynamic> getModel(Map<String, dynamic> json) => json;

  @override
  Widget parse(BuildContext context, Map<String, dynamic> model) {
    parses++;
    lastModel = model;
    return Text('probe:${model['label']}');
  }
}

/// Action stub that records the model it was called with.
class _ProbeActionParser extends StacActionParser<Map<String, dynamic>> {
  const _ProbeActionParser();

  static final List<Map<String, dynamic>> calls = [];

  @override
  String get actionType => 'probeAction';

  @override
  Map<String, dynamic> getModel(Map<String, dynamic> json) => json;

  @override
  FutureOr<dynamic> onCall(BuildContext context, Map<String, dynamic> model) {
    calls.add(model);
    return null;
  }
}

/// Runs [body] collecting everything the logger prints.
Future<List<String>> _captureLogs(Future<void> Function() body) async {
  final lines = <String>[];
  await runZoned(
    body,
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) => lines.add(line),
    ),
  );
  return lines;
}

late StacStateStore _store;
late BuildContext _ctx;

Future<void> _pumpScreen(
  WidgetTester t,
  Map<String, dynamic> json, {
  Map<String, Object?> state = const {},
  ThemeData? theme,
}) async {
  await t.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(
        body: StacStateScope(
          initialState: state,
          child: Builder(
            builder: (c) {
              _ctx = c;
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

void main() {
  setUpAll(() async {
    await initStacForTest();
    StacRegistry.instance.register(const _ProbeParser());
    StacRegistry.instance.registerAction(const _ProbeActionParser());
  });
  setUp(() {
    StacGlobalState.instance.clear();
    _ProbeParser.parses = 0;
    _ProbeActionParser.calls.clear();
  });

  group('regression: JSON without bindings keeps the old path', () {
    testWidgets('no StacReactive and no envelope effect', (t) async {
      await pumpStac(t, {
        'type': 'column',
        'children': [
          {'type': 'text', 'data': 'plain'},
          {'type': 'probe', 'label': 'x'},
        ],
      });
      expect(find.text('plain'), findsOneWidget);
      expect(find.byType(StacReactive), findsNothing);
      expect(_ProbeParser.parses, 1);
    });

    testWidgets('fromStacWidget goes through the same path', (t) async {
      await initStacForTest();
      late Widget? built;
      await pumpStacWidget(
        t,
        Builder(
          builder: (c) {
            built = StacService.fromStacWidget(
              widget: StacText(data: 'sw'),
              context: c,
            );
            return built!;
          },
        ),
      );
      expect(find.text('sw'), findsOneWidget);
    });
  });

  group('reactive rebuild', () {
    testWidgets('text with \$expr follows the store', (t) async {
      await _pumpScreen(
        t,
        {'type': 'text', 'data': _expr("'Total: ' + total")},
        state: {'total': 0},
      );
      expect(find.text('Total: 0'), findsOneWidget);
      _store.write('total', 3);
      await t.pump();
      expect(find.text('Total: 3'), findsOneWidget);
      expect(find.text('Total: 0'), findsNothing);
    });

    testWidgets('text with \$state accepts numbers and null (D6, D7)', (
      t,
    ) async {
      await _pumpScreen(
        t,
        {'type': 'text', 'data': _state('n')},
        state: {'n': 3, 'unused': null},
      );
      expect(find.text('3'), findsOneWidget);
      _store.write('n', null);
      await t.pump();
      expect(find.text(''), findsOneWidget);
    });

    testWidgets('batch of several keys rebuilds once', (t) async {
      await _pumpScreen(
        t,
        {'type': 'probe', 'label': _expr("a + ',' + b")},
        state: {'a': 0, 'b': 0},
      );
      expect(find.text('probe:0,0'), findsOneWidget);
      final before = _ProbeParser.parses;
      _store.batch(() {
        _store.write('a', 1);
        _store.write('b', 2);
      });
      await t.pump();
      expect(find.text('probe:1,2'), findsOneWidget);
      expect(_ProbeParser.parses, before + 1);
    });

    testWidgets('unrelated key does not rebuild', (t) async {
      await _pumpScreen(
        t,
        {'type': 'probe', 'label': _state('a')},
        state: {'a': 0, 'other': 0},
      );
      final before = _ProbeParser.parses;
      _store.write('other', 9);
      await t.pump();
      expect(_ProbeParser.parses, before);
    });

    testWidgets('global key rebuilds', (t) async {
      StacGlobalState.instance.store.declare('user', {'name': 'Ana'});
      await _pumpScreen(t, {'type': 'text', 'data': _expr('global.user.name')});
      expect(find.text('Ana'), findsOneWidget);
      StacGlobalState.instance.store.write('user', {'name': 'Bia'});
      await t.pump();
      expect(find.text('Bia'), findsOneWidget);
    });

    testWidgets('child reacts on its own, parent is not rebuilt', (t) async {
      await _pumpScreen(
        t,
        {
          'type': 'column',
          'children': [
            {'type': 'probe', 'label': _state('a')},
            {'type': 'text', 'data': 'static'},
          ],
        },
        state: {'a': 1},
      );
      expect(find.byType(StacReactive), findsOneWidget);
      _store.write('a', 2);
      await t.pump();
      expect(find.text('probe:2'), findsOneWidget);
    });

    testWidgets('no setState during build / no errors', (t) async {
      await _pumpScreen(
        t,
        {'type': 'text', 'data': _state('a')},
        state: {'a': 'x'},
      );
      _store.write('a', 'y');
      await t.pump();
      expect(t.takeException(), isNull);
    });
  });

  group('visible', () {
    testWidgets('expression toggles the widget', (t) async {
      await _pumpScreen(
        t,
        {'type': 'text', 'data': 'shown', 'visible': _expr('total == 10')},
        state: {'total': 0},
      );
      expect(find.text('shown'), findsNothing);
      _store.write('total', 10);
      await t.pump();
      expect(find.text('shown'), findsOneWidget);
      _store.write('total', 11);
      await t.pump();
      expect(find.text('shown'), findsNothing);
    });

    testWidgets('literal false hides without StacReactive', (t) async {
      await pumpStac(t, {'type': 'text', 'data': 'x', 'visible': false});
      expect(find.text('x'), findsNothing);
      expect(find.byType(StacReactive), findsNothing);
    });

    testWidgets('invalid expression hides and logs (D6)', (t) async {
      late List<String> logs;
      logs = await _captureLogs(() async {
        await _pumpScreen(
          t,
          {'type': 'text', 'data': 'shown', 'visible': _expr('total ==')},
          state: {'total': 0},
        );
      });
      expect(find.text('shown'), findsNothing);
      expect(logs.join('\n'), contains('visible'));
    });

    testWidgets('missing key hides (null is not a bool)', (t) async {
      await _pumpScreen(t, {
        'type': 'text',
        'data': 'shown',
        'visible': _state('nope'),
      });
      expect(find.text('shown'), findsNothing);
    });

    testWidgets('native visible of visibility accepts a binding', (t) async {
      await _pumpScreen(
        t,
        {
          'type': 'visibility',
          'visible': _state('on'),
          'child': {'type': 'text', 'data': 'inner'},
        },
        state: {'on': false},
      );
      expect(find.text('inner'), findsNothing);
      _store.write('on', true);
      await t.pump();
      expect(find.text('inner'), findsOneWidget);
    });
  });

  group('enabled', () {
    testWidgets('resolved bool reaches the parser; invalid is false', (
      t,
    ) async {
      await _pumpScreen(
        t,
        {'type': 'probe', 'label': 'e', 'enabled': _state('flag')},
        state: {'flag': true},
      );
      expect(_ProbeParser.lastModel!['enabled'], isTrue);
      _store.write('flag', false);
      await t.pump();
      expect(_ProbeParser.lastModel!['enabled'], isFalse);
    });

    testWidgets('invalid expression becomes false', (t) async {
      await _pumpScreen(t, {
        'type': 'probe',
        'label': 'e',
        'enabled': _expr('1 +'),
      });
      expect(_ProbeParser.lastModel!['enabled'], isFalse);
    });
  });

  group('action condition and bindings', () {
    testWidgets('false condition prevents the action', (t) async {
      await _pumpScreen(t, {'type': 'text', 'data': 'x'}, state: {'total': 0});
      final result = await Stac.onCallFromJson({
        'actionType': 'probeAction',
        'condition': _expr('total > 1'),
      }, _ctx);
      expect(result, isNull);
      expect(_ProbeActionParser.calls, isEmpty);

      _store.write('total', 5);
      await Stac.onCallFromJson({
        'actionType': 'probeAction',
        'condition': _expr('total > 1'),
        'payload': _state('total'),
      }, _ctx);
      expect(_ProbeActionParser.calls, hasLength(1));
      // condition removed, binding resolved at execution time
      expect(_ProbeActionParser.calls.single, {
        'actionType': 'probeAction',
        'payload': 5,
      });
    });

    testWidgets('literal and invalid conditions', (t) async {
      await _pumpScreen(t, {'type': 'text', 'data': 'x'});
      await Stac.onCallFromJson({
        'actionType': 'probeAction',
        'condition': false,
      }, _ctx);
      await Stac.onCallFromJson({
        'actionType': 'probeAction',
        'condition': _expr('1 +'),
      }, _ctx);
      await Stac.onCallFromJson({
        'actionType': 'probeAction',
        'condition': _state('nope'),
      }, _ctx);
      expect(_ProbeActionParser.calls, isEmpty);
      await Stac.onCallFromJson({
        'actionType': 'probeAction',
        'condition': true,
      }, _ctx);
      expect(_ProbeActionParser.calls, hasLength(1));
    });

    testWidgets('bindings are read at call time, nested actions untouched', (
      t,
    ) async {
      await _pumpScreen(t, {'type': 'text', 'data': 'x'}, state: {'a': 1});
      final nested = {'actionType': 'probeAction', 'v': _state('a')};
      _store.write('a', 2);
      await Stac.onCallFromJson({
        'actionType': 'probeAction',
        'value': {'k': _state('a')},
        'onDone': nested,
      }, _ctx);
      final call = _ProbeActionParser.calls.single;
      expect(call['value'], {'k': 2});
      expect(call['onDone'], nested);
    });

    testWidgets('action variables are visible (event.value)', (t) async {
      await _pumpScreen(t, {'type': 'text', 'data': 'x'});
      await runWithStacActionVars(
        {
          'event': {'value': 'typed'},
        },
        () => Stac.onCallFromJson({
          'actionType': 'probeAction',
          'got': _state('event.value'),
        }, _ctx),
      );
      expect(_ProbeActionParser.calls.single['got'], 'typed');
    });

    testWidgets('action without condition/bindings passes json untouched', (
      t,
    ) async {
      await _pumpScreen(t, {'type': 'text', 'data': 'x'});
      final json = {'actionType': 'probeAction', 'a': 1};
      await Stac.onCallFromJson(json, _ctx);
      expect(identical(_ProbeActionParser.calls.single, json), isTrue);
    });
  });

  group('theme', () {
    testWidgets('theme change keeps resolving theme colors with bindings', (
      t,
    ) async {
      final json = {
        'type': 'container',
        'width': _state('w'),
        'height': 10,
        'color': 'primary',
      };
      Color? colorOf() =>
          (t.widget<Container>(find.byType(Container).first).decoration
                  as BoxDecoration?)
              ?.color ??
          t.widget<Container>(find.byType(Container).first).color;

      await _pumpScreen(
        t,
        json,
        state: {'w': 10.0},
        theme: ThemeData(
          colorScheme: const ColorScheme.light(primary: Colors.red),
        ),
      );
      expect(colorOf(), Colors.red);
      await _pumpScreen(
        t,
        json,
        state: {'w': 10.0},
        theme: ThemeData(
          colorScheme: const ColorScheme.light(primary: Colors.blue),
        ),
      );
      await t.pumpAndSettle();
      expect(colorOf(), Colors.blue);
      _store.write('w', 20.0);
      await t.pump();
      expect(colorOf(), Colors.blue);
      expect(
        t.widget<Container>(find.byType(Container).first).constraints?.maxWidth,
        20.0,
      );
    });
  });

  group('local scope', () {
    testWidgets('binding on a local variable follows the scope', (t) async {
      Widget app(String item) => MaterialApp(
        home: Scaffold(
          body: StacLocalScope(
            vars: {'item': item},
            child: Builder(
              builder: (c) => StacService.fromJson({
                'type': 'text',
                'data': _state('item'),
              }, c)!,
            ),
          ),
        ),
      );
      await t.pumpWidget(app('one'));
      expect(find.text('one'), findsOneWidget);
      await t.pumpWidget(app('two'));
      expect(find.text('two'), findsOneWidget);
    });
  });

  group('errors inside the reactive build', () {
    testWidgets('a parser error does not escape', (t) async {
      await _pumpScreen(
        t,
        {'type': 'sizedBox', 'width': _state('w')},
        state: {'w': 'not a number'},
      );
      expect(t.takeException(), isNull);
    });
  });
}
