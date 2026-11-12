import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stac/stac.dart';

import 'harness.dart';

Map<String, dynamic> _state(String key) => {r'$state': key};
Map<String, dynamic> _expr(String e) => {r'$expr': e};

Map<String, dynamic> _set(Map<String, Object?> values) => {
  'actionType': 'setState',
  'values': values,
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

/// Types [text] into the focused field through the platform channel,
/// keeping the caret at [caret].
Future<void> _platformEdit(WidgetTester t, String text, int caret) async {
  t.testTextInput.updateEditingValue(
    TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: caret),
    ),
  );
  await t.pump();
}

final _dropdown = find.byWidgetPredicate((w) => w is DropdownMenu);

void main() {
  setUp(() => StacGlobalState.instance.clear());

  for (final type in ['textField', 'textFormField']) {
    group(type, () {
      testWidgets('typing writes the key on every change', (t) async {
        final store = await _pump(
          t,
          {'busca': ''},
          {
            'type': 'column',
            'children': [
              {'type': type, 'bind': 'busca'},
              {'type': 'text', 'data': _expr("'q=' + busca")},
            ],
          },
        );
        await t.enterText(find.byType(EditableText), 'abc');
        await t.pump();
        expect(store.read('busca'), 'abc');
        expect(find.text('q=abc'), findsOneWidget);
        await t.enterText(find.byType(EditableText), 'abcd');
        await t.pump();
        expect(store.read('busca'), 'abcd');
      });

      testWidgets('typing in the middle keeps text, caret and focus', (
        t,
      ) async {
        final store = await _pump(
          t,
          {'busca': 'hello'},
          {'type': type, 'bind': 'busca'},
        );
        await t.showKeyboard(find.byType(EditableText));
        await t.pump();
        EditableTextState editable() =>
            t.state<EditableTextState>(find.byType(EditableText));
        expect(editable().widget.controller.text, 'hello');

        await _platformEdit(t, 'hello', 2);
        // User types "X" between "he" and "llo".
        await _platformEdit(t, 'heXllo', 3);

        expect(store.read('busca'), 'heXllo');
        expect(editable().widget.controller.text, 'heXllo');
        expect(editable().widget.controller.selection.baseOffset, 3);
        expect(editable().widget.focusNode.hasFocus, isTrue);

        // And once more, still in the middle.
        await _platformEdit(t, 'heXYllo', 4);
        expect(store.read('busca'), 'heXYllo');
        expect(editable().widget.controller.selection.baseOffset, 4);
        expect(editable().widget.focusNode.hasFocus, isTrue);
      });

      testWidgets('keeps the same controller across store changes', (t) async {
        final store = await _pump(
          t,
          {'busca': ''},
          {'type': type, 'bind': 'busca'},
        );
        final before = t
            .state<EditableTextState>(find.byType(EditableText))
            .widget
            .controller;
        await t.enterText(find.byType(EditableText), 'a');
        await t.pump();
        store.write('busca', 'b');
        await t.pump();
        final after = t
            .state<EditableTextState>(find.byType(EditableText))
            .widget
            .controller;
        expect(identical(before, after), isTrue);
      });

      testWidgets('external setState updates the shown text', (t) async {
        final store = await _pump(
          t,
          {'busca': 'old', 'fired': 0},
          {
            'type': type,
            'bind': 'busca',
            'onChanged': {'actionType': 'incrementState', 'key': 'fired'},
          },
        );
        expect(find.text('old'), findsOneWidget);
        store.write('busca', 'new');
        await t.pump();
        expect(find.text('new'), findsOneWidget);
        expect(find.text('old'), findsNothing);
        expect(store.read('fired'), 0);
        // clearing from outside works too
        store.write('busca', null);
        await t.pump();
        expect(
          t
              .state<EditableTextState>(find.byType(EditableText))
              .widget
              .controller
              .text,
          '',
        );
      });

      testWidgets('onChanged sees the already written value (>= 3 chars)', (
        t,
      ) async {
        final store = await _pump(
          t,
          {'busca': '', 'pronto': false},
          {
            'type': type,
            'bind': 'busca',
            'onChanged': _set({'pronto': _expr('length(busca) >= 3')}),
          },
        );
        await t.enterText(find.byType(EditableText), 'ab');
        await t.pump();
        expect(store.read('pronto'), false);
        await t.enterText(find.byType(EditableText), 'abc');
        await t.pump();
        expect(store.read('pronto'), true);
      });

      testWidgets('value-only with onChanged receives event.value', (t) async {
        final store = await _pump(
          t,
          {'got': null},
          {
            'type': type,
            'onChanged': _set({'got': _state('event.value')}),
          },
        );
        await t.enterText(find.byType(EditableText), 'xyz');
        await t.pump();
        expect(store.read('got'), 'xyz');
      });

      testWidgets('enabled by binding disables the field', (t) async {
        final store = await _pump(
          t,
          {'busca': '', 'liberado': false},
          {'type': type, 'bind': 'busca', 'enabled': _state('liberado')},
        );
        EditableText editable() =>
            t.widget<EditableText>(find.byType(EditableText));
        expect(editable().readOnly || !_isEnabled(t), isTrue);
        store.write('liberado', true);
        await t.pump();
        expect(_isEnabled(t), isTrue);
        expect(editable().readOnly, isFalse);
      });

      testWidgets('maxLength and digits-only formatters are respected', (
        t,
      ) async {
        final store = await _pump(
          t,
          {'cod': ''},
          {
            'type': type,
            'bind': 'cod',
            'maxLength': 4,
            'inputFormatters': [
              {'type': 'allow', 'rule': r'[0-9]'},
            ],
          },
        );
        await t.enterText(find.byType(EditableText), 'a1b2c3d4e5');
        await t.pump();
        expect(store.read('cod'), '1234');
      });

      testWidgets('numeric bound value is shown as text', (t) async {
        await _pump(t, {'n': 42}, {'type': type, 'bind': 'n'});
        expect(find.text('42'), findsOneWidget);
      });
    });
  }

  group('dropdownMenu', () {
    Map<String, dynamic> dropdown({Map<String, dynamic>? extra}) => {
      'type': 'dropdownMenu',
      'dropdownMenuEntries': [
        {'value': 'a', 'label': 'Option A'},
        {'value': 'b', 'label': 'Option B'},
      ],
      ...?extra,
    };

    testWidgets('bind selects the entry and writes the choice', (t) async {
      final store = await _pump(
        t,
        {'opcao': 'a', 'copia': null},
        dropdown(
          extra: {
            'bind': 'opcao',
            'onSelected': _set({'copia': _state('opcao')}),
          },
        ),
      );
      expect(_shownText(t), 'Option A');
      await t.tap(_dropdown);
      await t.pumpAndSettle();
      await t.tap(find.text('Option B').last);
      await t.pumpAndSettle();
      expect(store.read('opcao'), 'b');
      expect(store.read('copia'), 'b');
    });

    testWidgets('external setState changes the selection', (t) async {
      final store = await _pump(
        t,
        {'opcao': 'a', 'fired': 0},
        dropdown(
          extra: {
            'bind': 'opcao',
            'onSelected': {'actionType': 'incrementState', 'key': 'fired'},
          },
        ),
      );
      expect(_shownText(t), 'Option A');
      store.write('opcao', 'b');
      await t.pumpAndSettle();
      expect(_shownText(t), 'Option B');
      expect(store.read('fired'), 0);
    });

    testWidgets('onSelected without bind receives event.value', (t) async {
      final store = await _pump(
        t,
        {'got': null},
        dropdown(
          extra: {
            'onSelected': _set({'got': _state('event.value')}),
          },
        ),
      );
      await t.tap(_dropdown);
      await t.pumpAndSettle();
      await t.tap(find.text('Option B').last);
      await t.pumpAndSettle();
      expect(store.read('got'), 'b');
    });

    testWidgets('selection drives a dependent widget', (t) async {
      await _pump(
        t,
        {'opcao': null},
        {
          'type': 'column',
          'children': [
            dropdown(extra: {'bind': 'opcao'}),
            _text('picked b', visible: _expr("opcao == 'b'")),
          ],
        },
      );
      expect(find.text('picked b'), findsNothing);
      await t.tap(_dropdown);
      await t.pumpAndSettle();
      await t.tap(find.text('Option B').last);
      await t.pumpAndSettle();
      expect(find.text('picked b'), findsOneWidget);
    });

    testWidgets('enabled by binding', (t) async {
      final store = await _pump(t, {
        'opcao': null,
        'liberado': false,
      }, dropdown(extra: {'bind': 'opcao', 'enabled': _state('liberado')}));
      expect(t.widget<DropdownMenu<dynamic>>(_dropdown).enabled, false);
      store.write('liberado', true);
      await t.pump();
      expect(t.widget<DropdownMenu<dynamic>>(_dropdown).enabled, true);
    });
  });
}

bool _isEnabled(WidgetTester t) {
  final field = find.byType(TextField);
  if (field.evaluate().isNotEmpty) {
    return t.widget<TextField>(field).enabled ?? true;
  }
  return t.widget<TextFormField>(find.byType(TextFormField)).enabled;
}

/// Text currently shown by the dropdown's input.
String _shownText(WidgetTester t) => t
    .widget<TextField>(
      find.descendant(of: _dropdown, matching: find.byType(TextField)),
    )
    .controller!
    .text;
