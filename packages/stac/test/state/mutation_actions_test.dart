import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stac/stac.dart';

import 'harness.dart';

Map<String, dynamic> _state(String key) => StacBinding.state(key);
Map<String, dynamic> _expr(String e) => StacBinding.expr(e);

int _probeBuilds = 0;

class _ProbeParser extends StacParser<Map<String, dynamic>> {
  const _ProbeParser();

  @override
  String get type => 'mutProbe';

  @override
  Map<String, dynamic> getModel(Map<String, dynamic> json) => json;

  @override
  Widget parse(BuildContext context, Map<String, dynamic> model) {
    _probeBuilds++;
    return Text('probe:${model['a']}:${model['b']}');
  }
}

Future<StacStateStore> _pump(
  WidgetTester tester,
  Map<String, Object?> initial,
  Widget Function(BuildContext) body,
) async {
  await initStacForTest();
  if (StacRegistry.instance.getParser('mutProbe') == null) {
    StacRegistry.instance.register(const _ProbeParser());
  }
  late StacStateStore store;
  await pumpStacWidget(
    tester,
    StacStateScope(
      initialState: initial,
      child: Builder(
        builder: (context) {
          store = StacStateScope.storeOf(context)!;
          return body(context);
        },
      ),
    ),
  );
  return store;
}

Widget _view(Map<String, dynamic> json) =>
    Builder(builder: (c) => StacService.fromJson(json, c)!);

Future<void> _run(WidgetTester tester, Map<String, dynamic> action) async {
  final context = tester.element(
    find
        .descendant(
          of: find.byType(StacStateScope),
          matching: find.byType(Builder),
        )
        .first,
  );
  await StacService.onCallFromJson(action, context);
  await tester.pump();
}

void main() {
  setUp(() => StacGlobalState.instance.clear());

  testWidgets('incrementState clamps at max and text follows', (tester) async {
    await _pump(tester, {
      'n': 8,
    }, (_) => _view({'type': 'text', 'data': _expr('"n=" + n')}));
    expect(find.text('n=8'), findsOneWidget);
    for (var i = 0; i < 4; i++) {
      await _run(tester, {
        'actionType': 'incrementState',
        'key': 'n',
        'max': 10,
      });
    }
    expect(find.text('n=10'), findsOneWidget);
    await _run(tester, {
      'actionType': 'decrementState',
      'key': 'n',
      'by': 20,
      'min': 0,
    });
    expect(find.text('n=0'), findsOneWidget);
  });

  testWidgets('setState with several keys rebuilds once', (tester) async {
    await _pump(tester, {
      'a': 1,
      'b': 2,
    }, (_) => _view({'type': 'mutProbe', 'a': _state('a'), 'b': _state('b')}));
    _probeBuilds = 0;
    await _run(tester, {
      'actionType': 'setState',
      'values': {'a': 5, 'b': _expr('a + 10')},
    });
    expect(_probeBuilds, 1);
    expect(find.text('probe:5:11'), findsOneWidget);
  });

  testWidgets('toggleState flips bool and ignores non-bool', (tester) async {
    final store = await _pump(tester, {'f': false, 's': 'x'}, (_) {
      return const SizedBox();
    });
    await _run(tester, {'actionType': 'toggleState', 'key': 'f'});
    expect(store.read('f'), true);
    await _run(tester, {'actionType': 'toggleState', 'key': 's'});
    expect(store.read('s'), 'x');
  });

  testWidgets('appendState writes a new list', (tester) async {
    final store = await _pump(tester, {
      'l': [1],
      'n': null,
    }, (_) => const SizedBox());
    final before = store.read('l');
    await _run(tester, {'actionType': 'appendState', 'key': 'l', 'value': 2});
    expect(store.read('l'), [1, 2]);
    expect(before, [1]);
    await _run(tester, {'actionType': 'appendState', 'key': 'n', 'value': 2});
    expect(store.read('n'), isNull);
  });

  testWidgets('resetState by keys and whole screen', (tester) async {
    StacGlobalState.instance.store.declare('g', 1);
    final store = await _pump(tester, {
      'a': 1,
      'b': 2,
    }, (_) => const SizedBox());
    await _run(tester, {
      'actionType': 'setState',
      'values': {'a': 9, 'b': 9, 'global.g': 9},
    });
    await _run(tester, {
      'actionType': 'resetState',
      'keys': ['a', 'global.g'],
    });
    expect(store.read('a'), 1);
    expect(store.read('b'), 9);
    expect(StacGlobalState.instance.store.read('g'), 1);
    await _run(tester, {'actionType': 'resetState'});
    expect(store.read('b'), 2);
  });

  testWidgets('global write reflects in reader', (tester) async {
    StacGlobalState.instance.store.declare('x', 'a');
    await _pump(
      tester,
      {},
      (_) => _view({'type': 'text', 'data': _state('global.x')}),
    );
    expect(find.text('a'), findsOneWidget);
    await _run(tester, {
      'actionType': 'setState',
      'values': {'global.x': 'b'},
    });
    expect(find.text('b'), findsOneWidget);
  });

  testWidgets('undeclared key does not throw', (tester) async {
    final store = await _pump(tester, {}, (_) => const SizedBox());
    await _run(tester, {
      'actionType': 'setState',
      'values': {'nope': 1},
    });
    await _run(tester, {'actionType': 'incrementState', 'key': 'nope'});
    expect(store.read('nope'), isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('multiAction sync sees earlier write via condition', (
    tester,
  ) async {
    final store = await _pump(tester, {'a': 0, 'b': 0}, (_) {
      return const SizedBox();
    });
    await _run(tester, {
      'actionType': 'multiAction',
      'sync': true,
      'actions': [
        {
          'actionType': 'setState',
          'values': {'a': 1},
        },
        {
          'actionType': 'setState',
          'condition': _expr('a == 1'),
          'values': {'b': 2},
        },
        {
          'actionType': 'setState',
          'condition': _expr('a == 0'),
          'values': {'b': 99},
        },
      ],
    });
    expect(store.read('b'), 2);
  });
}
