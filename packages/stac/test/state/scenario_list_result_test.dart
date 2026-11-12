import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stac/stac.dart';

import 'harness.dart';

/// Scenario 14.2 (generic, no domain): screen A holds a list and opens screen
/// B to build one entry (a text plus a set of picked options). B returns the
/// entry as a result that A appends. Entries can be removed by index and the
/// whole list is sent in one request.

Map<String, dynamic> _state(String key) => StacBinding.state(key);
Map<String, dynamic> _expr(String e) => StacBinding.expr(e);

Map<String, dynamic> _button(
  String label,
  Map<String, dynamic> action, {
  Object? enabled,
}) => {
  'type': 'textButton',
  'onPressed': action,
  'enabled': ?enabled,
  'child': {'type': 'text', 'data': label},
};

const _options = [
  {'id': 1, 'label': 'Opt1'},
  {'id': 2, 'label': 'Opt2'},
  {'id': 3, 'label': 'Opt3'},
];

Map<String, dynamic> _screenB() => {'type': 'scaffold', 'body': _bodyB()};

Map<String, dynamic> _bodyB() => {
  'type': 'column',
  'state': {'campo': '', 'selecionados': <Object?>[]},
  'children': [
    {'type': 'textField', 'bind': 'campo'},
    for (final o in _options)
      _button(o['label']! as String, {
        'actionType': 'toggleItem',
        'key': 'selecionados',
        'value': o,
        'by': 'id',
      }),
    {'type': 'text', 'data': _expr("'picked=' + length(selecionados)")},
    _button('confirm', {
      'actionType': 'navigate',
      'navigationStyle': 'pop',
      'result': {'campo': _state('campo'), 'opcoes': _state('selecionados')},
    }, enabled: _expr('length(trim(campo)) > 0')),
    _button('back', {'actionType': 'navigate', 'navigationStyle': 'pop'}),
  ],
};

Map<String, dynamic> _screenA() => {
  'type': 'column',
  'state': {'lista': <Object?>[], 'enviando': false, 'erroEnvio': false},
  'children': [
    {'type': 'text', 'data': 'vazio', 'visible': _expr('length(lista) == 0')},
    {
      'type': 'listView',
      'shrinkWrap': true,
      'items': _state('lista'),
      'as': 'entrada',
      'indexAs': 'pos',
      'itemTemplate': {
        'type': 'column',
        'children': [
          {
            'type': 'text',
            'data': _expr("'entrada ' + pos + ':' + entrada.campo"),
          },
          {
            'type': 'listView',
            'shrinkWrap': true,
            'items': _state('entrada.opcoes'),
            'as': 'op',
            'itemTemplate': {
              'type': 'text',
              'data': _expr("'op:' + pos + ':' + op.label"),
            },
          },
          _button('remove', {
            'actionType': 'removeFromState',
            'key': 'lista',
            'index': _state('pos'),
          }),
        ],
      },
    },
    _button('add', {
      'actionType': 'navigate',
      'navigationStyle': 'push',
      'widgetJson': _screenB(),
      'onResult': {
        'actionType': 'appendState',
        'key': 'lista',
        'value': _state('result'),
      },
    }),
    _button('send', {
      'actionType': 'networkRequest',
      'url': '/enviar',
      'method': 'post',
      'body': _state('lista'),
      'onStart': {
        'actionType': 'setState',
        'values': {'enviando': true, 'erroEnvio': false},
      },
      'onSuccess': {
        'actionType': 'resetState',
        'keys': ['lista'],
      },
      'onError': {
        'actionType': 'setState',
        'values': {'erroEnvio': true},
      },
      'onFinally': {
        'actionType': 'setState',
        'values': {'enviando': false},
      },
    }, enabled: _expr('enviando == false && length(lista) > 0')),
    {'type': 'text', 'data': 'falhou', 'visible': _state('erroEnvio')},
  ],
};

final _adapter = FakeDioAdapter();

Future<StacStateStore> _pumpA(WidgetTester tester) async {
  await initStacForTest(dio: Dio()..httpClientAdapter = _adapter);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(builder: (c) => StacService.fromJson(_screenA(), c)!),
      ),
    ),
  );
  await tester.pump();
  return StacStateScope.storeOf(tester.element(find.text('vazio')))!;
}

Future<void> _tap(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

Future<void> _addEntry(
  WidgetTester tester,
  String campo,
  List<String> options,
) async {
  await _tap(tester, 'add');
  await tester.enterText(find.byType(TextField), campo);
  await tester.pump();
  for (final o in options) {
    await _tap(tester, o);
  }
  await _tap(tester, 'confirm');
}

bool _pressable(WidgetTester tester, String label) =>
    tester
        .widget<TextButton>(
          find.ancestor(
            of: find.text(label),
            matching: find.byType(TextButton),
          ),
        )
        .onPressed !=
    null;

void main() {
  setUp(() {
    StacGlobalState.instance.clear();
    _adapter.requests.clear();
  });

  testWidgets('B builds an entry, A lists it, repeat, remove, send', (
    tester,
  ) async {
    final store = await _pumpA(tester);
    expect(find.text('vazio'), findsOneWidget);

    // B: confirm is disabled until the field has text.
    await _tap(tester, 'add');
    expect(_pressable(tester, 'confirm'), isFalse);
    await tester.enterText(find.byType(TextField), '  ');
    await tester.pump();
    expect(_pressable(tester, 'confirm'), isFalse);
    await tester.enterText(find.byType(TextField), 'um');
    await tester.pump();
    expect(_pressable(tester, 'confirm'), isTrue);

    // Options toggle on/off.
    await _tap(tester, 'Opt1');
    await _tap(tester, 'Opt2');
    expect(find.text('picked=2'), findsOneWidget);
    await _tap(tester, 'Opt1');
    expect(find.text('picked=1'), findsOneWidget);
    await _tap(tester, 'Opt3');
    await _tap(tester, 'confirm');

    expect(find.text('vazio'), findsNothing);
    expect(find.text('entrada 0:um'), findsOneWidget);
    expect(find.text('op:0:Opt2'), findsOneWidget);
    expect(find.text('op:0:Opt3'), findsOneWidget);
    expect(find.text('op:0:Opt1'), findsNothing);

    // Repeat twice more; each B starts fresh.
    await _addEntry(tester, 'dois', ['Opt1']);
    await _addEntry(tester, 'tres', []);
    expect(find.text('entrada 1:dois'), findsOneWidget);
    expect(find.text('entrada 2:tres'), findsOneWidget);
    expect((store.read('lista') as List).length, 3);

    // Back without confirming leaves A untouched.
    await _tap(tester, 'add');
    await tester.enterText(find.byType(TextField), 'descartado');
    await tester.pump();
    await _tap(tester, 'back');
    expect((store.read('lista') as List).length, 3);
    expect(find.text('entrada 3:descartado'), findsNothing);

    // Remove the middle one by index.
    await tester.tap(find.text('remove').at(1));
    await tester.pumpAndSettle();
    expect((store.read('lista') as List).map((e) => (e as Map)['campo']), [
      'um',
      'tres',
    ]);
    expect(find.text('entrada 1:tres'), findsOneWidget);
    expect(find.text('entrada 2:tres'), findsNothing);

    // Send: disabled while in flight, cleared on success.
    _adapter.enqueue(
      const FakeResponse({'ok': true}, delay: Duration(milliseconds: 100)),
    );
    await tester.tap(find.text('send'));
    await tester.pump();
    expect(store.read('enviando'), true);
    expect(_pressable(tester, 'send'), isFalse);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(store.read('enviando'), false);
    expect(store.read('lista'), isEmpty);
    expect(find.text('vazio'), findsOneWidget);
    expect(_adapter.requests.single.data, [
      {
        'campo': 'um',
        'opcoes': [
          {'id': 2, 'label': 'Opt2'},
          {'id': 3, 'label': 'Opt3'},
        ],
      },
      {'campo': 'tres', 'opcoes': <Object?>[]},
    ]);
  });

  testWidgets('a failing send keeps the list and shows the error', (
    tester,
  ) async {
    final store = await _pumpA(tester);
    await _addEntry(tester, 'um', ['Opt1']);
    _adapter.enqueue(const FakeResponse({'msg': 'x'}, statusCode: 500));
    await tester.tap(find.text('send'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();

    expect(find.text('falhou'), findsOneWidget);
    expect((store.read('lista') as List).length, 1);
    expect(store.read('enviando'), false);
    expect(_pressable(tester, 'send'), isTrue);
  });
}
