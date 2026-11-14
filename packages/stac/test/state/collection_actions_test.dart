import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stac/stac.dart';

import 'harness.dart';

Map<String, dynamic> _state(String key) => StacBinding.state(key);
Map<String, dynamic> _expr(String e) => StacBinding.expr(e);

Future<StacStateStore> _pump(
  WidgetTester tester,
  Map<String, Object?> initial,
) async {
  await initStacForTest();
  late StacStateStore store;
  await pumpStacWidget(
    tester,
    StacStateScope(
      initialState: initial,
      child: Builder(
        builder: (context) {
          store = StacStateScope.storeOf(context)!;
          return StacService.fromJson({
            'type': 'text',
            'data': _expr('length(l)'),
          }, context)!;
        },
      ),
    ),
  );
  return store;
}

Future<void> _run(WidgetTester tester, Map<String, dynamic> action) async {
  final context = tester.element(find.byType(Text).first);
  await StacService.onCallFromJson(action, context);
  await tester.pump();
}

void main() {
  setUp(() => StacGlobalState.instance.clear());

  test('models serialize their fields', () {
    final r = StacRemoveFromStateAction.fromJson({
      'actionType': 'removeFromState',
      'key': 'l',
      'index': _state('i'),
    });
    expect(r.toJson()['index'], _state('i'));
    final t = StacToggleItemAction.fromJson({
      'actionType': 'toggleItem',
      'key': 'l',
      'value': 1,
      'by': 'id',
    });
    expect(t.toJson()['by'], 'id');
    expect(t.actionType, 'toggleItem');
  });

  group('removeFromState', () {
    testWidgets('removes by index writing a new list', (tester) async {
      final store = await _pump(tester, {
        'l': ['a', 'b', 'c'],
      });
      final before = store.read('l');
      await _run(tester, {
        'actionType': 'removeFromState',
        'key': 'l',
        'index': 1,
      });
      expect(store.read('l'), ['a', 'c']);
      expect(before, ['a', 'b', 'c']);
      expect(identical(before, store.read('l')), isFalse);
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('index accepts a binding', (tester) async {
      final store = await _pump(tester, {
        'l': ['a', 'b', 'c'],
        'i': 2,
      });
      await _run(tester, {
        'actionType': 'removeFromState',
        'key': 'l',
        'index': _state('i'),
      });
      expect(store.read('l'), ['a', 'b']);
    });

    testWidgets('removes the first deep-equal value', (tester) async {
      final store = await _pump(tester, {
        'l': [
          {
            'id': 1,
            'x': [1],
          },
          {'id': 2},
          {
            'id': 1,
            'x': [1],
          },
        ],
      });
      await _run(tester, {
        'actionType': 'removeFromState',
        'key': 'l',
        'value': {
          'id': 1,
          'x': [1],
        },
      });
      expect(store.read('l'), [
        {'id': 2},
        {
          'id': 1,
          'x': [1],
        },
      ]);
    });

    testWidgets('out of range, missing value and non-list are no-ops', (
      tester,
    ) async {
      final store = await _pump(tester, {
        'l': ['a'],
        'n': 3,
      });
      for (final bad in [
        {'key': 'l', 'index': 5},
        {'key': 'l', 'index': -1},
        {'key': 'l', 'value': 'zzz'},
        {'key': 'n', 'index': 0},
        {'key': 'nope', 'index': 0},
      ]) {
        await _run(tester, {'actionType': 'removeFromState', ...bad});
      }
      expect(store.read('l'), ['a']);
      expect(store.read('n'), 3);
    });
  });

  group('toggleItem', () {
    testWidgets('adds when absent and removes when present', (tester) async {
      final store = await _pump(tester, {
        'l': ['a'],
      });
      final before = store.read('l');
      final act = {'actionType': 'toggleItem', 'key': 'l', 'value': 'b'};
      await _run(tester, act);
      expect(store.read('l'), ['a', 'b']);
      expect(before, ['a']);
      await _run(tester, act);
      expect(store.read('l'), ['a']);
    });

    testWidgets('by defines identity for objects', (tester) async {
      final store = await _pump(tester, {
        'l': <Object?>[],
        'sel': {'id': 7, 'label': 'x'},
      });
      Map<String, dynamic> act(Object? v) => {
        'actionType': 'toggleItem',
        'key': 'l',
        'value': v,
        'by': 'id',
      };
      await _run(tester, act(_state('sel')));
      expect(store.read('l'), [
        {'id': 7, 'label': 'x'},
      ]);
      // Same id, different label: counts as present.
      await _run(tester, act({'id': 7, 'label': 'changed'}));
      expect(store.read('l'), isEmpty);
      // Without `by`, deep equality applies.
      await _run(tester, {
        'actionType': 'toggleItem',
        'key': 'l',
        'value': {'id': 7},
      });
      await _run(tester, {
        'actionType': 'toggleItem',
        'key': 'l',
        'value': {'id': 7, 'extra': 1},
      });
      expect((store.read('l') as List).length, 2);
    });

    testWidgets('non-list key is a no-op', (tester) async {
      final store = await _pump(tester, {'n': 1});
      await _run(tester, {'actionType': 'toggleItem', 'key': 'n', 'value': 1});
      expect(store.read('n'), 1);
    });
  });
}
