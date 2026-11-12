import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stac/stac.dart';

import 'harness.dart';

Map<String, dynamic> _expr(String e) => StacBinding.expr(e);

Map<String, dynamic> _text(String data) => {'type': 'text', 'data': data};

Map<String, dynamic> _inc(String key) => {
  'actionType': 'incrementState',
  'key': key,
};

Future<StacStateStore> _pump(
  WidgetTester tester,
  Map<String, Object?> initial,
  Map<String, dynamic> json,
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
          return StacService.fromJson(json, context)!;
        },
      ),
    ),
  );
  return store;
}

void main() {
  setUp(() => StacGlobalState.instance.clear());

  testWidgets('button follows a flag written by another widget', (
    tester,
  ) async {
    final store = await _pump(
      tester,
      {'aceito': false},
      {
        'type': 'elevatedButton',
        'enabled': _expr('aceito'),
        'onPressed': _inc('n'),
        'child': _text('go'),
      },
    );
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNull,
    );
    store.write('aceito', true);
    await tester.pump();
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNotNull,
    );
    store.write('aceito', false);
    await tester.pump();
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNull,
    );
  });

  testWidgets('plus button is disabled once total reaches 10', (tester) async {
    final store = await _pump(
      tester,
      {'total': 9},
      {
        'type': 'column',
        'children': [
          _text('x'),
          {
            'type': 'iconButton',
            'enabled': _expr('total < 10'),
            'icon': {'type': 'icon', 'icon': 'add'},
            'onPressed': {'actionType': 'incrementState', 'key': 'total'},
          },
        ],
      },
    );
    IconButton button() => tester.widget<IconButton>(find.byType(IconButton));
    expect(button().onPressed, isNotNull);
    await tester.tap(find.byType(IconButton));
    await tester.pump();
    expect(store.read('total'), 10);
    expect(button().onPressed, isNull);
  });

  testWidgets('literal enabled false disables and blocks the action', (
    tester,
  ) async {
    final store = await _pump(
      tester,
      {'n': 0},
      {
        'type': 'textButton',
        'enabled': false,
        'onPressed': _inc('n'),
        'child': _text('go'),
      },
    );
    expect(
      tester.widget<TextButton>(find.byType(TextButton)).onPressed,
      isNull,
    );
    await tester.tap(find.byType(TextButton), warnIfMissed: false);
    expect(store.read('n'), 0);
  });

  testWidgets('enabled true keeps the action', (tester) async {
    final store = await _pump(
      tester,
      {'n': 0},
      {
        'type': 'filledButton',
        'enabled': true,
        'onPressed': _inc('n'),
        'child': _text('go'),
      },
    );
    await tester.tap(find.byType(FilledButton));
    expect(store.read('n'), 1);
  });

  testWidgets('inkWell is inert when disabled', (tester) async {
    final store = await _pump(
      tester,
      {'n': 0, 'on': false},
      {
        'type': 'inkWell',
        'enabled': _expr('on'),
        'onTap': _inc('n'),
        'child': _text('tap'),
      },
    );
    InkWell ink() => tester.widget<InkWell>(find.byType(InkWell));
    expect(ink().onTap, isNull);
    await tester.tap(find.text('tap'));
    expect(store.read('n'), 0);
    store.write('on', true);
    await tester.pump();
    await tester.tap(find.text('tap'));
    expect(store.read('n'), 1);
  });

  testWidgets('gestureDetector and chip lose their touch callbacks', (
    tester,
  ) async {
    final store = await _pump(
      tester,
      {'n': 0},
      {
        'type': 'column',
        'children': [
          {
            'type': 'gestureDetector',
            'enabled': false,
            'onTap': _inc('n'),
            'child': _text('g'),
          },
          {
            'type': 'chip',
            'enabled': false,
            'label': _text('c'),
            'onDeleted': _inc('n'),
          },
        ],
      },
    );
    expect(
      tester.widget<GestureDetector>(find.byType(GestureDetector).first).onTap,
      isNull,
    );
    expect(tester.widget<Chip>(find.byType(Chip)).onDeleted, isNull);
    await tester.tap(find.text('g'));
    expect(store.read('n'), 0);
  });

  test('checkBox, switch and slider lose their change callbacks', () {
    for (final type in ['checkBox', 'switch', 'slider']) {
      final out = StacEnvelope.apply({
        'type': type,
        'value': false,
        'enabled': false,
        'onChanged': _inc('n'),
        'onChangeEnd': _inc('n'),
        'label': 'keep',
      }, type)!;
      expect(out.containsKey('onChanged'), isFalse, reason: type);
      expect(out.containsKey('onChangeEnd'), isFalse, reason: type);
      expect(out['label'], 'keep');
      expect(out['enabled'], isFalse);
    }
    final on = StacEnvelope.apply({
      'type': 'checkBox',
      'enabled': true,
      'onChanged': _inc('n'),
    }, 'checkBox')!;
    expect(on.containsKey('onChanged'), isTrue);
  });

  testWidgets('disabled checkBox ignores taps and does not fire onChanged', (
    tester,
  ) async {
    final store = await _pump(
      tester,
      {'n': 0},
      {
        'type': 'checkBox',
        'value': false,
        'enabled': false,
        'onChanged': _inc('n'),
      },
    );
    await tester.tap(find.byType(Checkbox), warnIfMissed: false);
    await tester.pump();
    expect(store.read('n'), 0);
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, false);
  });

  testWidgets('floatingActionButton is disabled', (tester) async {
    await _pump(tester, {}, {
      'type': 'floatingActionButton',
      'enabled': false,
      'onPressed': _inc('n'),
      'child': _text('f'),
    });
    expect(
      tester
          .widget<FloatingActionButton>(find.byType(FloatingActionButton))
          .onPressed,
      isNull,
    );
  });

  testWidgets('invalid enabled expression disables (D6)', (tester) async {
    await _pump(
      tester,
      {'n': 0},
      {
        'type': 'elevatedButton',
        'enabled': _expr('1 +'),
        'onPressed': _inc('n'),
        'child': _text('go'),
      },
    );
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNull,
    );
  });

  testWidgets('enabled is ignored on a widget without touch actions', (
    tester,
  ) async {
    await _pump(tester, {}, {
      'type': 'elevatedButton',
      'enabled': false,
      'child': _text('go'),
    });
    expect(find.text('go'), findsOneWidget);
  });
}
