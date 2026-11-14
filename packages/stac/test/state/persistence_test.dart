import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stac/src/framework/stac_error.dart';
import 'package:stac/src/state/stac_binding.dart' as runtime;
import 'package:stac/src/state/stac_persistent_state_store.dart';
import 'package:stac/stac.dart';

import 'harness.dart';

/// In-memory [StacStatePersistence] that records every operation.
class _FakePersistence implements StacStatePersistence {
  _FakePersistence([Map<String, String>? initial]) : data = {...?initial};

  final Map<String, String> data;
  final List<String> ops = [];

  @override
  Future<Map<String, String>> readAll() async => {...data};

  @override
  Future<void> write(String key, String value) async {
    ops.add('write:$key');
    data[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    ops.add('delete:$key');
    data.remove(key);
  }
}

class _ThrowingPersistence implements StacStatePersistence {
  @override
  Future<Map<String, String>> readAll() async => throw StateError('boom');

  @override
  Future<void> write(String key, String value) async =>
      throw StateError('boom');

  @override
  Future<void> delete(String key) async => throw StateError('boom');
}

final _adapter = FakeDioAdapter();
final _dio = Dio()..httpClientAdapter = _adapter;

late _FakePersistence _plain;
late _FakePersistence _secure;

StacPersistentStateStore get _global =>
    StacGlobalState.instance.store as StacPersistentStateStore;

/// Runs [body] collecting everything the logger prints.
Future<List<String>> _captureLogs(FutureOr<void> Function() body) async {
  final lines = <String>[];
  await runZoned(
    () async => body(),
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) => lines.add(line),
    ),
  );
  return lines;
}

Future<void> _hydrate({
  Map<String, String> plain = const {},
  Map<String, String> secure = const {},
}) async {
  _plain = _FakePersistence(plain);
  _secure = _FakePersistence(secure);
  await StacGlobalState.instance.hydrate(
    persistence: _plain,
    securePersistence: _secure,
  );
}

Map<String, Object?> _decl(Object? initial, {bool? persist, bool? secure}) => {
  'initial': initial,
  'persist': ?persist,
  'secure': ?secure,
};

void main() {
  setUp(() async {
    // Once per isolate; it must run before the tests configure their fakes.
    await initStacForTest(dio: _dio);
    SharedPreferences.setMockInitialValues({});
    StacGlobalState.instance.clear();
  });

  group('hydration', () {
    test('persisted value wins over the initial value', () async {
      await _hydrate(plain: {'theme': jsonEncode('dark')});
      StacGlobalState.instance.declareAll({
        'theme': _decl('light', persist: true),
      });
      expect(_global.read('theme'), 'dark');
    });

    test('memory wins over persisted', () async {
      _global
        ..declareWithFlags('theme', 'light', const StacKeyFlags(persist: true))
        ..write('theme', 'blue');
      await _hydrate(plain: {'theme': jsonEncode('dark')});
      expect(_global.read('theme'), 'blue');
    });

    test('initial is used when nothing was persisted', () async {
      await _hydrate();
      StacGlobalState.instance.declareAll({
        'theme': _decl('light', persist: true),
      });
      expect(_global.read('theme'), 'light');
    });

    test('an orphan persisted key stays hidden until declared', () async {
      await _hydrate(plain: {'late': jsonEncode(7)});
      expect(_global.has('late'), isFalse);
      expect(_global.read('late'), isNull);
      expect(_global.hasPending('late'), isTrue);
      StacGlobalState.instance.declareAll({'late': _decl(0, persist: true)});
      expect(_global.read('late'), 7);
      expect(_global.hasPending('late'), isFalse);
    });

    test('a key declared without persist ignores the stored value', () async {
      await _hydrate(plain: {'theme': jsonEncode('dark')});
      StacGlobalState.instance.declareAll({'theme': 'light'});
      expect(_global.read('theme'), 'light');
    });

    test('incompatible type is discarded, logged and erased', () async {
      await _hydrate(plain: {'count': jsonEncode('abc')});
      final logs = await _captureLogs(() async {
        StacGlobalState.instance.declareAll({'count': _decl(0, persist: true)});
        await _global.flush();
      });
      expect(_global.read('count'), 0);
      expect(_plain.data.containsKey('count'), isFalse);
      expect(logs.join('\n'), contains('count'));
      expect(logs.join('\n'), isNot(contains('abc')));
    });

    test('invalid JSON is discarded', () async {
      await _hydrate(plain: {'count': '{not json'});
      StacGlobalState.instance.declareAll({'count': _decl(3, persist: true)});
      expect(_global.read('count'), 3);
    });

    test('lists and maps round-trip', () async {
      await _hydrate(
        plain: {
          'cart': jsonEncode([
            {'id': 1},
          ]),
        },
      );
      StacGlobalState.instance.declareAll({
        'cart': _decl(<Object?>[], persist: true),
      });
      expect(_global.read('cart'), [
        {'id': 1},
      ]);
      expect(
        () => (_global.read('cart') as List).add(1),
        throwsUnsupportedError,
      );
    });

    test('a failing storage does not break hydrate', () async {
      final logs = await _captureLogs(() async {
        await StacGlobalState.instance.hydrate(
          persistence: _ThrowingPersistence(),
          securePersistence: _ThrowingPersistence(),
        );
      });
      expect(logs.join('\n'), contains('Failed to read'));
      StacGlobalState.instance.declareAll({'a': _decl(1, persist: true)});
      expect(_global.read('a'), 1);
    });

    test('SharedPrefsPersistence reads only prefixed keys', () async {
      SharedPreferences.setMockInitialValues({
        'stac_state.theme': jsonEncode('dark'),
        'other': 'x',
      });
      await StacGlobalState.instance.hydrate(
        securePersistence: _FakePersistence(),
      );
      StacGlobalState.instance.declareAll({
        'theme': _decl('light', persist: true),
      });
      expect(_global.read('theme'), 'dark');
    });

    testWidgets('Stac.initialize hydrates before the first frame', (
      tester,
    ) async {
      StacGlobalState.instance.clear();
      await StacService.initialize(
        dio: _dio,
        statePersistence: _FakePersistence({'theme': jsonEncode('dark')}),
        secureStatePersistence: _FakePersistence(),
      );
      await pumpStac(tester, {
        'type': 'column',
        'globalState': {'theme': _decl('light', persist: true)},
        'children': [
          {
            'type': 'text',
            'data': {r'$state': 'global.theme'},
          },
        ],
      });
      expect(find.text('dark'), findsOneWidget);
      expect(find.text('light'), findsNothing);
    });
  });

  group('writing', () {
    test('changes are written as JSON', () async {
      await _hydrate();
      StacGlobalState.instance.declareAll({
        'theme': _decl('light', persist: true),
      });
      _global.write('theme', 'dark');
      await _global.flush();
      expect(_plain.data, {'theme': jsonEncode('dark')});
    });

    test('bursts are coalesced into one write with the last value', () async {
      await _hydrate();
      StacGlobalState.instance.declareAll({'n': _decl(0, persist: true)});
      _global
        ..write('n', 1)
        ..write('n', 2)
        ..write('n', 3);
      await _global.flush();
      expect(_plain.ops, ['write:n']);
      expect(_plain.data['n'], '3');
    });

    test('writes happen on a microtask without flush()', () async {
      await _hydrate();
      StacGlobalState.instance.declareAll({'n': _decl(0, persist: true)});
      _global.write('n', 5);
      await Future<void>.delayed(Duration.zero);
      expect(_plain.data['n'], '5');
    });

    test('keys without persist are never stored', () async {
      await _hydrate();
      StacGlobalState.instance.declareAll({'n': 0});
      _global.write('n', 5);
      await _global.flush();
      expect(_plain.data, isEmpty);
      expect(_secure.data, isEmpty);
    });

    test('a storage failure is logged, not thrown', () async {
      StacGlobalState.instance.declareAll({'n': _decl(0, persist: true)});
      _global.configure(persistence: _ThrowingPersistence());
      final logs = await _captureLogs(() async {
        _global.write('n', 1);
        await _global.flush();
      });
      expect(logs.join('\n'), contains('Failed to write'));
    });
  });

  group('reset', () {
    test(
      'reset restores the initial value and erases the stored one',
      () async {
        await _hydrate(plain: {'theme': jsonEncode('dark')});
        StacGlobalState.instance.declareAll({
          'theme': _decl('light', persist: true),
        });
        _global.reset('theme');
        await _global.flush();
        expect(_global.read('theme'), 'light');
        expect(_plain.data, isEmpty);
      },
    );

    test('resetAll erases plain and secure copies', () async {
      await _hydrate(plain: {'a': '1'}, secure: {'t': jsonEncode('tok')});
      StacGlobalState.instance.declareAll({
        'a': _decl(0, persist: true),
        't': _decl('', secure: true),
      });
      _global.resetAll();
      await _global.flush();
      expect(_global.read('a'), 0);
      expect(_global.read('t'), '');
      expect(_plain.data, isEmpty);
      expect(_secure.data, isEmpty);
    });

    test('a write after a reset is stored again, in order', () async {
      await _hydrate();
      StacGlobalState.instance.declareAll({'n': _decl(0, persist: true)});
      _global
        ..write('n', 1)
        ..reset('n')
        ..write('n', 2);
      await _global.flush();
      expect(_plain.data['n'], '2');
    });

    testWidgets('resetState action on a global key erases it', (tester) async {
      await _hydrate(plain: {'n': '9'});
      await pumpStac(tester, {
        'type': 'column',
        'globalState': {'n': _decl(0, persist: true)},
        'children': [
          {
            'type': 'textButton',
            'onPressed': {
              'actionType': 'resetState',
              'keys': ['global.n'],
            },
            'child': {'type': 'text', 'data': 'reset'},
          },
        ],
      });
      expect(_global.read('n'), 9);
      await tester.tap(find.text('reset'));
      await tester.pump();
      await tester.pump(); // storage operations run on microtasks
      expect(_global.read('n'), 0);
      expect(_plain.data, isEmpty);
    });
  });

  group('secure keys', () {
    test('go to the secure storage, not to the plain one', () async {
      await _hydrate();
      StacGlobalState.instance.declareAll({
        'token': _decl('', secure: true),
        'theme': _decl('light', persist: true),
      });
      _global
        ..write('token', 'abc123')
        ..write('theme', 'dark');
      await _global.flush();
      expect(_secure.data, {'token': jsonEncode('abc123')});
      expect(_plain.data, {'theme': jsonEncode('dark')});
    });

    test('never reach shared_preferences', () async {
      await StacGlobalState.instance.hydrate(
        securePersistence: _secure = _FakePersistence(),
      );
      StacGlobalState.instance.declareAll({'token': _decl('', secure: true)});
      _global.write('token', 'abc123');
      await _global.flush();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), isEmpty);
      expect(_secure.data['token'], jsonEncode('abc123'));
    });

    test('are hydrated from the secure storage', () async {
      await _hydrate(secure: {'token': jsonEncode('abc123')});
      StacGlobalState.instance.declareAll({'token': _decl('', secure: true)});
      expect(_global.read('token'), 'abc123');
      expect(_global.isSecure('token'), isTrue);
    });

    test('secure with persist false warns and still persists', () async {
      await _hydrate();
      final logs = await _captureLogs(() async {
        StacGlobalState.instance.declareAll({
          'token': _decl('', secure: true, persist: false),
        });
      });
      expect(logs.join('\n'), contains('secure implies persist'));
      _global.write('token', 'x');
      await _global.flush();
      expect(_secure.data, isNotEmpty);
    });

    test('plain keys are not secure', () async {
      await _hydrate();
      StacGlobalState.instance.declareAll({
        'a': _decl(1, persist: true),
        'b': 2,
      });
      expect(_global.isSecure('a'), isFalse);
      expect(_global.isSecure('b'), isFalse);
    });

    test('web: the noop storage keeps nothing and warns once', () async {
      NoopSecurePersistence.resetWarning();
      await StacGlobalState.instance.hydrate(
        persistence: _plain = _FakePersistence(),
        securePersistence: const NoopSecurePersistence(),
      );
      StacGlobalState.instance.declareAll({'token': _decl('', secure: true)});
      final logs = await _captureLogs(() async {
        _global
          ..write('token', 'abc123')
          ..write('token', 'def456');
        await _global.flush();
        _global.write('token', 'ghi789');
        await _global.flush();
      });
      expect(_global.read('token'), 'ghi789');
      expect(_plain.data, isEmpty);
      expect(logs.where((l) => l.contains('Secure storage')), hasLength(1));
      expect(const NoopSecurePersistence().readAll(), completion(isEmpty));
    });
  });

  group('screen keys', () {
    testWidgets('persist on a screen key is logged and ignored', (
      tester,
    ) async {
      await _hydrate();
      late List<String> logs;
      logs = await _captureLogs(() async {
        await pumpStac(tester, {
          'type': 'column',
          'state': {'n': _decl(4, persist: true)},
          'children': [
            {
              'type': 'text',
              'data': {r'$state': 'n'},
            },
          ],
        });
      });
      expect(find.text('4'), findsOneWidget);
      expect(logs.join('\n'), contains('only apply to globalState'));
      await tester.pump();
      expect(_plain.data, isEmpty);
    });
  });

  group('log masking', () {
    testWidgets('secure values are masked in logs', (tester) async {
      await _hydrate();
      StacGlobalState.instance.declareAll({'token': _decl('', secure: true)});
      _global.write('token', 's3cr3t-token');
      await pumpStac(tester, {
        'type': 'text',
        'data': 'x',
        'visible': {r'$state': 'global.token'},
      });
      final logs = await _captureLogs(() async {
        runtime.StacBinding.strictBool('s3cr3t-token', 'visible');
      });
      final text = logs.join('\n');
      expect(text, contains('***'));
      expect(text, isNot(contains('s3cr3t-token')));
    });

    test('redact handles values nested in secure maps and lists', () async {
      await _hydrate();
      StacGlobalState.instance.declareAll({
        'auth': _decl({
          'access': 'AAA111',
          'refresh': ['RRR222'],
        }, secure: true),
        'plain': 'visible',
      });
      final out = StacGlobalState.instance.redact(
        'a AAA111 b RRR222 c visible',
      );
      expect(out, 'a *** b *** c visible');
      expect(StacGlobalState.instance.hasSecrets, isTrue);
    });

    test('redact is the identity without secure values', () {
      expect(StacGlobalState.instance.redact('hello'), 'hello');
      expect(StacGlobalState.instance.hasSecrets, isFalse);
    });

    testWidgets('the Stac error widget does not print secure values', (
      tester,
    ) async {
      await _hydrate();
      StacGlobalState.instance.declareAll({'token': _decl('', secure: true)});
      _global.write('token', 's3cr3t-token');
      await initStacForTest();
      await pumpStacWidget(
        tester,
        Builder(
          builder: (context) => StacService.fromJson({
            'type': 'definitelyUnknownType',
            'note': 'has s3cr3t-token inside',
          }, context)!,
        ),
      );
      expect(find.byType(StacErrorWidget), findsOneWidget);
      await tester.tap(find.byIcon(Icons.expand_more).first);
      await tester.pump();
      await tester.tap(find.text('JSON Data'));
      await tester.pump();
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
          .join('\n');
      final selectable = tester
          .widgetList<SelectableText>(find.byType(SelectableText))
          .map((t) => t.data ?? '')
          .join('\n');
      expect('$texts\n$selectable', isNot(contains('s3cr3t-token')));
      expect('$texts\n$selectable', contains('***'));
    });
  });

  group('requests', () {
    Future<void> pumpTokenScreen(
      WidgetTester tester,
      Map<String, dynamic> request,
    ) async {
      await _hydrate();
      await initStacForTest(dio: _dio);
      StacGlobalState.instance.declareAll({
        'token': _decl('', secure: true),
        'tema': _decl('dark', persist: true),
      });
      _global.write('token', 'abc123');
      await pumpStacWidget(
        tester,
        StacStateScope(
          initialState: const {'nome': 'Ana'},
          child: Builder(builder: (context) => const SizedBox()),
        ),
      );
      _adapter
        ..requests.clear()
        ..enqueue(const FakeResponse({}));
      final ctx = tester.element(find.byType(SizedBox).first);
      StacService.onCallFromJson(request, ctx);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
    }

    testWidgets('bodyFromState leaves a persisted secure key out', (
      tester,
    ) async {
      await pumpTokenScreen(tester, {
        'actionType': 'networkRequest',
        'url': '/save',
        'method': 'post',
        'bodyFromState': ['nome', 'global.tema', 'global.token'],
      });
      expect(_adapter.requests.single.data, {
        'nome': 'Ana',
        'global.tema': 'dark',
      });
    });

    testWidgets('Authorization header can use a secure key', (tester) async {
      await pumpTokenScreen(tester, {
        'actionType': 'networkRequest',
        'url': '/me',
        'method': 'get',
        'headers': {
          'Authorization': {r'$expr': "'Bearer ' + global.token"},
        },
      });
      expect(
        _adapter.requests.single.headers['Authorization'],
        'Bearer abc123',
      );
    });
  });
}
