import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stac/stac.dart';

import 'harness.dart';

Map<String, dynamic> _state(String key) => {r'$state': key};

Map<String, dynamic> _copy(String from, String to) => {
  'actionType': 'setState',
  'values': {to: _state(from)},
};

Map<String, dynamic> _text(String data, {Object? visible}) => {
  'type': 'text',
  'data': data,
  'visible': ?visible,
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

  group('checkBox', () {
    testWidgets('bind drives a dependent widget and writes before onChanged', (
      t,
    ) async {
      final store = await _pump(
        t,
        {'aceito': false, 'copia': null},
        {
          'type': 'column',
          'children': [
            {
              'type': 'checkBox',
              'bind': 'aceito',
              'onChanged': _copy('aceito', 'copia'),
            },
            _text('go', visible: _state('aceito')),
          ],
        },
      );
      expect(find.text('go'), findsNothing);
      await t.tap(find.byType(Checkbox));
      await t.pump();
      expect(store.read('aceito'), true);
      expect(store.read('copia'), true);
      expect(find.text('go'), findsOneWidget);
      expect(t.widget<Checkbox>(find.byType(Checkbox)).value, true);
    });

    testWidgets('external setState updates it without firing onChanged', (
      t,
    ) async {
      final store = await _pump(
        t,
        {'aceito': false, 'copia': 'untouched'},
        {
          'type': 'checkBox',
          'bind': 'aceito',
          'onChanged': _copy('aceito', 'copia'),
        },
      );
      store.write('aceito', true);
      await t.pump();
      expect(t.widget<Checkbox>(find.byType(Checkbox)).value, true);
      expect(store.read('copia'), 'untouched');
    });

    testWidgets('read-only value with onChanged receives event.value', (
      t,
    ) async {
      final store = await _pump(
        t,
        {'got': null},
        {
          'type': 'checkBox',
          'value': false,
          'onChanged': _copy('event.value', 'got'),
        },
      );
      await t.tap(find.byType(Checkbox));
      await t.pump();
      expect(store.read('got'), true);
    });
  });

  group('switch', () {
    testWidgets('bind shows and hides a block', (t) async {
      final store = await _pump(
        t,
        {'on': false},
        {
          'type': 'column',
          'children': [
            {'type': 'switch', 'bind': 'on'},
            _text('panel', visible: _state('on')),
          ],
        },
      );
      expect(find.text('panel'), findsNothing);
      await t.tap(find.byType(Switch));
      await t.pump();
      expect(store.read('on'), true);
      expect(find.text('panel'), findsOneWidget);
      store.write('on', false);
      await t.pump();
      expect(find.text('panel'), findsNothing);
      expect(t.widget<Switch>(find.byType(Switch)).value, false);
    });

    testWidgets('onChanged without bind sees event.value', (t) async {
      final store = await _pump(
        t,
        {'got': null},
        {
          'type': 'switch',
          'value': false,
          'onChanged': _copy('event.value', 'got'),
        },
      );
      await t.tap(find.byType(Switch));
      await t.pump();
      expect(store.read('got'), true);
    });
  });

  group('slider', () {
    testWidgets('bind follows the store and writes on drag', (t) async {
      final store = await _pump(
        t,
        {'v': 0.2, 'copia': null},
        {
          'type': 'slider',
          'bind': 'v',
          'sliderType': 'material',
          'onChanged': _copy('v', 'copia'),
        },
      );
      expect(t.widget<Slider>(find.byType(Slider)).value, 0.2);
      store.write('v', 0.8);
      await t.pump();
      expect(t.widget<Slider>(find.byType(Slider)).value, 0.8);
      expect(store.read('copia'), isNull);
      await t.tap(find.byType(Slider));
      await t.pump();
      expect(store.read('v'), isNot(0.8));
      expect(store.read('copia'), store.read('v'));
    });
  });

  group('radioGroup', () {
    Map<String, dynamic> radio(Object v) => {'type': 'radio', 'value': v};

    testWidgets('choice selects which form is shown', (t) async {
      final store = await _pump(
        t,
        {'tipo': 'a', 'copia': null},
        {
          'type': 'column',
          'children': [
            {
              'type': 'radioGroup',
              'bind': 'tipo',
              'onChanged': _copy('tipo', 'copia'),
              'child': {
                'type': 'column',
                'children': [radio('a'), radio('b')],
              },
            },
            _text('form A', visible: {r'$expr': 'tipo == "a"'}),
            _text('form B', visible: {r'$expr': 'tipo == "b"'}),
          ],
        },
      );
      expect(find.text('form A'), findsOneWidget);
      expect(find.text('form B'), findsNothing);
      await t.tap(find.byType(Radio<dynamic>).at(1));
      await t.pump();
      expect(store.read('tipo'), 'b');
      expect(store.read('copia'), 'b');
      expect(find.text('form B'), findsOneWidget);
      expect(find.text('form A'), findsNothing);
      store.write('tipo', 'a');
      await t.pump();
      expect(find.text('form A'), findsOneWidget);
    });

    testWidgets('onChanged without bind sees event.value', (t) async {
      final store = await _pump(
        t,
        {'got': null},
        {
          'type': 'radioGroup',
          'groupValue': 'a',
          'onChanged': _copy('event.value', 'got'),
          'child': {
            'type': 'column',
            'children': [radio('a'), radio('b')],
          },
        },
      );
      await t.tap(find.byType(Radio<dynamic>).at(1));
      await t.pump();
      expect(store.read('got'), 'b');
    });

    testWidgets('bind on an individual radio is ignored (logged)', (t) async {
      await _pump(
        t,
        {'x': 'a'},
        {
          'type': 'radioGroup',
          'groupValue': 'a',
          'child': {
            'type': 'column',
            'children': [
              {'type': 'radio', 'value': 'a', 'bind': 'x'},
            ],
          },
        },
      );
      expect(find.byType(Radio<dynamic>), findsOneWidget);
    });
  });
}
