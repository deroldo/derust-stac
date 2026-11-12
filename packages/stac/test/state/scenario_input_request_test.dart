import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stac/stac.dart';

import 'harness.dart';

/// Scenario 14.1 (generic, no domain): typing in an input triggers a lookup
/// request that fills two other fields; loading and error indicators follow
/// flags; changing the input clears, cancels and starts over.

Map<String, dynamic> _state(String key) => StacBinding.state(key);
Map<String, dynamic> _expr(String e) => StacBinding.expr(e);

class _Reply {
  const _Reply(this.body, {this.status = 200, this.delayMs = 0});

  final Object? body;
  final int status;
  final int delayMs;
}

/// Answers by request path, so cancelled requests cannot shift the others.
class _PathAdapter implements HttpClientAdapter {
  final Map<String, _Reply> replies = {};
  final List<String> paths = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    paths.add(options.path);
    final reply = replies[options.path];
    if (reply == null) throw StateError('no reply for ${options.path}');
    if (reply.delayMs > 0) {
      await Future<void>.delayed(Duration(milliseconds: reply.delayMs));
    }
    return ResponseBody.fromBytes(
      utf8.encode(jsonEncode(reply.body)),
      reply.status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

final _adapter = _PathAdapter();
final _dio = Dio()..httpClientAdapter = _adapter;

final Map<String, dynamic> _screen = {
  'type': 'column',
  'children': [
    {
      'type': 'textField',
      'bind': 'campo',
      'onChanged': {
        'actionType': 'multiAction',
        'sync': true,
        'actions': [
          {'actionType': 'cancelRequest', 'requestKey': 'lookup'},
          {
            'actionType': 'resetState',
            'keys': ['nome', 'cidade', 'veioDoServidor', 'carregando', 'erro'],
          },
          {
            'actionType': 'networkRequest',
            'condition': _expr('length(campo) >= 3'),
            'url': _expr('"/lookup/" + campo'),
            'requestKey': 'lookup',
            'onStart': {
              'actionType': 'setState',
              'values': {'carregando': true, 'erro': false},
            },
            'onSuccess': {
              'actionType': 'setState',
              'values': {
                'nome': _state('response.body.nome'),
                'cidade': _state('response.body.cidade'),
                'veioDoServidor': true,
              },
            },
            'onError': {
              'actionType': 'setState',
              'values': {'erro': true},
            },
            'onFinally': {
              'actionType': 'setState',
              'values': {'carregando': false},
            },
          },
        ],
      },
    },
    {
      'type': 'textField',
      'bind': 'nome',
      'enabled': _expr('veioDoServidor == false'),
    },
    {
      'type': 'textField',
      'bind': 'cidade',
      'enabled': _expr('veioDoServidor == false'),
    },
    {'type': 'circularProgressIndicator', 'visible': _state('carregando')},
    {'type': 'text', 'data': 'falhou', 'visible': _state('erro')},
  ],
};

Future<StacStateStore> _pump(WidgetTester tester) async {
  await initStacForTest(dio: _dio);
  late StacStateStore store;
  await pumpStacWidget(
    tester,
    StacStateScope(
      initialState: const {
        'campo': '',
        'nome': '',
        'cidade': '',
        'veioDoServidor': false,
        'carregando': false,
        'erro': false,
      },
      child: Builder(
        builder: (context) {
          store = StacStateScope.storeOf(context)!;
          return StacService.fromJson(_screen, context)!;
        },
      ),
    ),
  );
  return store;
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField).first, text);
  await tester.pump();
}

bool _enabled(WidgetTester tester, int index) =>
    tester.widget<TextField>(find.byType(TextField).at(index)).enabled ?? true;

String _textOf(WidgetTester tester, int index) =>
    tester.widget<TextField>(find.byType(TextField).at(index)).controller!.text;

final _spinner = find.byType(CircularProgressIndicator);

void main() {
  setUp(() {
    StacGlobalState.instance.clear();
    _adapter.replies.clear();
    _adapter.paths.clear();
  });

  testWidgets('lookup fills the fields, restarts and cancels on change', (
    tester,
  ) async {
    final store = await _pump(tester);
    _adapter.replies['/lookup/abc'] = const _Reply({
      'nome': 'Ana',
      'cidade': 'Rio',
    }, delayMs: 100);
    _adapter.replies['/lookup/abcd'] = const _Reply({
      'nome': 'Bia',
      'cidade': 'Sao Paulo',
    }, delayMs: 300);
    _adapter.replies['/lookup/abcde'] = const _Reply({
      'nome': 'Cris',
      'cidade': 'Recife',
    }, delayMs: 50);

    // Fewer than 3 chars: no request, nothing shown.
    await _type(tester, 'ab');
    expect(_adapter.paths, isEmpty);
    expect(_spinner, findsNothing);

    // 3 chars: request starts, spinner on, fields still editable.
    await _type(tester, 'abc');
    expect(_spinner, findsOneWidget);
    expect(_enabled(tester, 1), isTrue);

    await tester.pump(const Duration(milliseconds: 150));
    expect(_spinner, findsNothing);
    expect(_textOf(tester, 1), 'Ana');
    expect(_textOf(tester, 2), 'Rio');
    expect(_enabled(tester, 1), isFalse);
    expect(_enabled(tester, 2), isFalse);
    expect(store.read('veioDoServidor'), true);

    // Changing the input clears the filled fields and re-enables them...
    await _type(tester, 'abcd');
    expect(_textOf(tester, 1), '');
    expect(_textOf(tester, 2), '');
    expect(_enabled(tester, 1), isTrue);
    expect(_spinner, findsOneWidget);

    // ...and typing again while the request is pending cancels it: the slow
    // reply for "abcd" must never show up.
    await tester.pump(const Duration(milliseconds: 20));
    await _type(tester, 'abcde');
    await tester.pump(const Duration(milliseconds: 100));
    expect(_textOf(tester, 1), 'Cris');
    expect(_textOf(tester, 2), 'Recife');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(_textOf(tester, 1), 'Cris');
    expect(_textOf(tester, 2), 'Recife');
    expect(_spinner, findsNothing);
    expect(store.read('erro'), false);

    // Dropping below 3 chars clears everything and sends nothing.
    final sent = _adapter.paths.length;
    await _type(tester, 'ab');
    expect(_textOf(tester, 1), '');
    expect(_enabled(tester, 1), isTrue);
    expect(_adapter.paths.length, sent);
  });

  testWidgets('a failing lookup shows the error and stops loading', (
    tester,
  ) async {
    final store = await _pump(tester);
    _adapter.replies['/lookup/xyz'] = const _Reply(
      {'msg': 'x'},
      status: 500,
      delayMs: 50,
    );
    await _type(tester, 'xyz');
    expect(_spinner, findsOneWidget);
    expect(find.text('falhou'), findsNothing);
    await tester.pump(const Duration(milliseconds: 100));
    expect(_spinner, findsNothing);
    expect(find.text('falhou'), findsOneWidget);
    expect(_enabled(tester, 1), isTrue);
    expect(store.read('veioDoServidor'), false);

    // Typing again clears the error.
    await _type(tester, 'xy');
    expect(find.text('falhou'), findsNothing);
  });
}
